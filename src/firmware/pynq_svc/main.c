/* main.c —— pynq_svc：PS(ARM) <-> RV32 的邮箱服务固件（Y01 draft v1）
 *
 * 链路：PS 侧 AXI-Lite 字节 FIFO <-> (PL 内 uart_tx/uart_rx) <-> RV32 UART MMIO。
 *       字节流格式与 src/pynq/mailbox_protocol.md 完全一致：
 *         请求 "Y01Q" + 48B header + key16 + nonce16 + AD + input + tag
 *         响应 "Y01R" + 48B header + payload
 *       另有两个服务帧（本固件新增，不属于 mailbox 消息，只用于握手/取证）：
 *         开机/epoch 应答 "Y01S" 64B（固件标识、能力、自检结果、boot mcycle）
 *         PS 下发 epoch   "Y01E" 20B
 *
 * 单槽：一次只处理一个请求，响应发完后才回到帧同步，因此 PS 不需要额外的 ACK 线。
 * cycles：只在 AEAD 调用边界读 mcycle 差值（CSR 0xB00/0xB80），不含串口传输。
 * 证据类别：本固件的响应 flags 的 SIMULATED 位恒为 0（真实硬件执行）。
 *
 * 注意：MGMT 只发文本日志与 Y01S/Y01R 帧；文本行不会与二进制帧交错
 *       （单线程、顺序写），PS 侧驱动按魔数分帧。
 */
#include "svc.h"

#define BUF_BYTES 160u

static uint8_t  rxbuf[BUF_BYTES];
static uint8_t  txbuf[BUF_BYTES];
static uint64_t fw_epoch;
static uint64_t fw_boot_id;

/* ------------------------------ 小端工具 ------------------------------ */
static uint32_t get_u16(const uint8_t *b)
{
    return (uint32_t)b[0] | ((uint32_t)b[1] << 8);
}
static uint32_t get_u32(const uint8_t *b)
{
    return (uint32_t)b[0] | ((uint32_t)b[1] << 8) |
           ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
}
static uint64_t get_u64(const uint8_t *b)
{
    return (uint64_t)get_u32(b) | ((uint64_t)get_u32(b + 4) << 32);
}
static void put_u16(uint8_t *b, uint16_t v)
{
    b[0] = (uint8_t)v; b[1] = (uint8_t)(v >> 8);
}
static void put_u32(uint8_t *b, uint32_t v)
{
    b[0] = (uint8_t)v;         b[1] = (uint8_t)(v >> 8);
    b[2] = (uint8_t)(v >> 16); b[3] = (uint8_t)(v >> 24);
}
static void put_u64(uint8_t *b, uint64_t v)
{
    put_u32(b, (uint32_t)v);
    put_u32(b + 4, (uint32_t)(v >> 32));
}

static int magic_is(const uint8_t *m, const char *tag)
{
    return m[0] == (uint8_t)tag[0] && m[1] == (uint8_t)tag[1] &&
           m[2] == (uint8_t)tag[2] && m[3] == (uint8_t)tag[3];
}

static void read_bytes(uint8_t *dst, uint32_t n)
{
    while (n--) *dst++ = svc_getc();
}
static void write_bytes(const uint8_t *src, uint32_t n)
{
    while (n--) svc_putc(*src++);
}

/* --------------------------- Y01S 服务帧 --------------------------- */
static void send_service_frame(uint32_t selftest_mask, uint64_t boot_mcycle,
                              uint64_t boot_id, int epoch_set)
{
    uint8_t f[SVC_FRAME_BYTES];
    uint32_t i;
    uint32_t caps = (1u << (MODE_SW - 1)) | (1u << (MODE_HW - 1)) | (1u << (MODE_ISE - 1));

    for (i = 0; i < SVC_FRAME_BYTES; i++) f[i] = 0;
    f[0] = 'Y'; f[1] = '0'; f[2] = '1'; f[3] = 'S';
    put_u16(f + 4, (uint16_t)PROTO_VERSION);
    put_u16(f + 6, (uint16_t)(((selftest_mask == caps) ? 0x2u : 0u) |
                              (epoch_set ? 0x4u : 0u)));
    put_u64(f + 8, fw_epoch);
    put_u32(f + 16, caps);
    put_u32(f + 20, MAX_MSG_BYTES);
    put_u32(f + 24, MAX_AD_BYTES);
    put_u32(f + 28, selftest_mask);
    put_u64(f + 32, boot_mcycle);
    put_u64(f + 40, boot_id);
    for (i = 0; i < 16 && FW_ID_STR[i] != '\0'; i++) f[48 + i] = (uint8_t)FW_ID_STR[i];

    write_bytes(f, SVC_FRAME_BYTES);
}

/* --------------------------- Y01R 响应 --------------------------- */
static void send_response(uint64_t epoch, uint64_t rid, uint32_t op, uint32_t mode,
                          uint32_t status, const uint8_t *payload, uint32_t plen,
                          uint64_t cycles, int cycles_valid)
{
    uint8_t *h = txbuf;
    uint32_t i;

    for (i = 0; i < RSP_HEADER_BYTES; i++) h[i] = 0;
    h[0] = 'Y'; h[1] = '0'; h[2] = '1'; h[3] = 'R';
    put_u16(h + 4, (uint16_t)PROTO_VERSION);
    put_u16(h + 6, (uint16_t)(cycles_valid ? 0x1u : 0u));   /* bit1 SIMULATED 恒 0 */
    put_u64(h + 8, epoch);
    put_u64(h + 16, rid);
    put_u32(h + 24, status);
    put_u32(h + 28, op);
    put_u32(h + 32, mode);
    put_u32(h + 36, plen);
    put_u64(h + 40, cycles_valid ? cycles : 0ull);

    write_bytes(h, RSP_HEADER_BYTES);
    if (status == ST_OK && plen) write_bytes(payload, plen);
}

/* --------------------------- 请求处理 --------------------------- */
static void handle_request(void)
{
    uint8_t  *h = rxbuf;
    uint32_t  op, mode, alen, dlen, cap, tlen, body_bytes, got;
    uint64_t  epoch, rid, c0, cycles = 0;
    uint32_t  status = ST_OK, plen = 0, plen_discard = 0;
    int       rc = 0, cycles_valid = 0;
    const uint8_t *key, *nonce, *ad, *input, *tag;
    uint8_t  *out = txbuf + RSP_HEADER_BYTES;
    uint32_t  mlen = 0;

    read_bytes(rxbuf + 4, REQ_HEADER_BYTES - 4);   /* 魔数已在同步阶段读走 */

    /* 48B = magic(4) + <HHQQIIIIII> 44B */
    epoch = get_u64(h + 8);
    rid   = get_u64(h + 16);
    op    = get_u32(h + 24);
    mode  = get_u32(h + 28);
    alen  = get_u32(h + 32);
    dlen  = get_u32(h + 36);
    cap   = get_u32(h + 40);
    tlen  = get_u32(h + 44);

    /* 先算 body 长度，无论是否合法都要把字节从流里读干净，保持帧同步 */
    body_bytes = 32u + alen + dlen + tlen;

    if (get_u16(h + 4) != PROTO_VERSION || get_u16(h + 6) != 0) {
        status = ST_INTERNAL;
    } else if (op != OP_ENCRYPT && op != OP_DECRYPT) {
        status = ST_UNSUPPORTED;
    } else if (mode != MODE_SW && mode != MODE_HW && mode != MODE_ISE) {
        status = ST_UNSUPPORTED;
    } else if (alen > MAX_AD_BYTES || dlen > MAX_MSG_BYTES ||
               tlen != ((op == OP_DECRYPT) ? 16u : 0u)) {
        status = ST_LENGTH;
    } else if (cap < (op == OP_ENCRYPT ? dlen + 16u : dlen)) {
        status = ST_LENGTH;
    } else if (epoch != fw_epoch) {
        status = ST_INTERNAL;                     /* 旧 epoch：明确拒绝，不执行 */
    }

    if (status == ST_OK) {
        got = body_bytes;                         /* 正常请求：整帧读进缓冲 */
        if (got > BUF_BYTES) got = BUF_BYTES;
        read_bytes(rxbuf, got);
        if (body_bytes > got)                     /* 理论上不会发生（已限长） */
            for (plen_discard = body_bytes - got; plen_discard; plen_discard--)
                (void)svc_getc();
    } else {
        for (plen_discard = body_bytes; plen_discard; plen_discard--)
            (void)svc_getc();
        send_response(epoch, rid, op, mode, status, 0, 0, 0, 0);
        return;
    }

    key   = rxbuf;
    nonce = rxbuf + 16;
    ad    = rxbuf + 32;
    input = ad + alen;
    tag   = input + dlen;

    c0 = svc_mcycle();
    if (op == OP_ENCRYPT) {
        out = txbuf + RSP_HEADER_BYTES;
        rc = svc_aead_encrypt(mode, out, out + dlen, input, dlen, ad, alen, nonce, key);
        if (rc == 0) plen = dlen + 16u;
    } else {
        rc = svc_aead_decrypt(mode, out, &mlen, input, dlen, ad, alen, nonce, key, tag);
        if (rc == 0) plen = mlen;
    }
    cycles = svc_mcycle() - c0;

    if (rc == 0) {
        status = ST_OK;
        cycles_valid = 1;
    } else if (rc == -1) {
        status = (op == OP_DECRYPT) ? ST_AUTH_FAILED : ST_INTERNAL;
        plen = 0;
        cycles_valid = 0;
    } else {
        status = ST_UNSUPPORTED;
        plen = 0;
        cycles_valid = 0;
    }

    send_response(epoch, rid, op, mode, status, out, plen, cycles, cycles_valid);

    /* 请求缓冲里含 key/nonce/明文：发完响应后立刻清零 */
    {
        uint32_t i;
        for (i = 0; i < BUF_BYTES; i++) rxbuf[i] = 0;
    }
}

/* --------------------------- 帧同步 --------------------------- */
static void sync_and_dispatch(void)
{
    uint8_t m[4];
    uint32_t i;

    for (;;) {
        for (i = 0; i < 4; i++) m[i] = svc_getc();
        if (magic_is(m, "Y01Q")) {
            /* 把魔数放回缓冲头，保持 48B header 布局 */
            rxbuf[0] = m[0]; rxbuf[1] = m[1]; rxbuf[2] = m[2]; rxbuf[3] = m[3];
            handle_request();
            return;
        }
        if (magic_is(m, "Y01E")) {
            uint8_t e[EPOCH_FRAME_BYTES - 4];
            uint64_t new_epoch;
            read_bytes(e, EPOCH_FRAME_BYTES - 4);
            if (get_u32(e) == PROTO_VERSION && get_u32(e + 4) == 0) {
                new_epoch = get_u64(e + 8);
                if (new_epoch != 0) fw_epoch = new_epoch;
            }
            {
                uint32_t mask = 0;
                uint64_t cyc = 0;
                svc_selftest(&mask, &cyc);        /* 重新自检不影响 epoch */
                send_service_frame(mask, cyc, fw_boot_id, 1);
            }
            return;
        }
        /* 非帧字节（文本噪音）：忽略，继续找魔数 */
    }
}

/* --------------------------- main --------------------------- */
int main(void)
{
    uint32_t mask = 0;
    uint64_t boot_id, cyc = 0;

    boot_id = svc_mcycle();
    fw_boot_id = boot_id;
    fw_epoch = 0;

    svc_puts("\n=== pynq_svc v1: RV32 Ascon-AEAD128 mailbox service ===\n");
    svc_puts("mode caps: sw,hw,ise  max_msg=16  max_ad=16\n");

    svc_selftest(&mask, &cyc);
    svc_puts("selftest mask = 0x");
    svc_puthex32(mask);
    svc_puts(mask == 0x7u ? " (sw+hw+ise PASS)\n" : " (INCOMPLETE)\n");
    svc_puts("16B encrypt mcycle (first passing mode) = ");
    svc_putdec(cyc);
    svc_puts("\nready\n");

    send_service_frame(mask, cyc, boot_id, 0);

    for (;;) sync_and_dispatch();
    return 0;
}
