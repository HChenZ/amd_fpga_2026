/* puf_svc.c —— Y01P/Y01K：通过 PS 邮箱控制 PUF v1 密钥子系统
 *
 * 流程与 2026-10-27 板测通过的 keys_rv32 v3 相同（等空闲 -> CLEAR -> START[+ENROLL]
 * -> 确认受理 -> 等 done），只是超时改用 mcycle 期限、结果打包成二进制帧。
 *
 * 策略（固件层，不是硬件强制）：
 *   * ENROLL/RECONSTRUCT 开始前先关 HWKEY：密钥重算期间 HW 模式回到调用方 key。
 *   * HWKEY_ON 只在 key_ready=1、enrolled=1、mismatch=0、fallback=0、busy=0 时执行，
 *     否则返回 PUF_NO_PUF_KEY，避免把 DNA-only 降级密钥当作 PUF 密钥使用。
 * 安全边界：REF/MASK/RAW/DITHER/DNA 可读（PUF v1 设计如此），key 本身不可读。
 */
#include "svc.h"
#include "puf_svc.h"

#define PUF_WAIT_CYCLES 30000000ull   /* 300 ms @100 MHz；硬件单次 keygen 约 13 ms */

static uint32_t rd_u32le(const uint8_t *b)
{
    return (uint32_t)b[0] | ((uint32_t)b[1] << 8) |
           ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
}

static void wr_u32le(uint8_t *b, uint32_t v)
{
    b[0] = (uint8_t)v;         b[1] = (uint8_t)(v >> 8);
    b[2] = (uint8_t)(v >> 16); b[3] = (uint8_t)(v >> 24);
}

void puf_hwkey_off(void)
{
    KEY_CTRL = KCTRL_HWKEY_OFF;
}

static int wait_idle(void)
{
    uint64_t deadline = svc_mcycle() + PUF_WAIT_CYCLES;
    while (KEY_STATUS & KST_BUSY) {
        if (svc_mcycle() >= deadline) return -1;
    }
    return 0;
}

static int wait_done(void)
{
    uint64_t deadline = svc_mcycle() + PUF_WAIT_CYCLES;
    while (!(KEY_STATUS & KST_DONE)) {
        if (svc_mcycle() >= deadline) return -1;
    }
    return 0;
}

static uint32_t run_keygen(uint32_t enroll)
{
    uint64_t deadline;
    volatile uint32_t d;
    uint32_t st;

    puf_hwkey_off();
    if (wait_idle()) return PUF_BUSY_STUCK;
    for (d = 0; d < 64u; d++) { }                /* CLEAR 与 START 之间留空拍 */
    KEY_CTRL = KCTRL_CLEAR;
    KEY_CTRL = KCTRL_START | (enroll ? KCTRL_ENROLL : 0u);
    deadline = svc_mcycle() + PUF_WAIT_CYCLES;
    for (;;) {
        st = KEY_STATUS;
        if (st & (KST_BUSY | KST_DONE)) break;
        if (svc_mcycle() >= deadline) return PUF_NOT_ACCEPTED;
    }
    if (wait_done()) return PUF_TIMEOUT;
    return PUF_OK;
}

static uint32_t hwkey_on(void)
{
    uint32_t st = KEY_STATUS;
    if ((st & KST_BUSY) || !(st & KST_READY) || !(st & KST_ENROLLED) ||
        (st & (KST_MISMATCH | KST_FALLBACK)))
        return PUF_NO_PUF_KEY;
    KEY_CTRL = KCTRL_HWKEY_ON;
    if (!(KEY_STATUS & KST_HWSEL)) {             /* 硬件没有生效：撤销并报告 */
        puf_hwkey_off();
        return PUF_NO_PUF_KEY;
    }
    return PUF_OK;
}

static void put_block(uint8_t *dst, uint32_t off)
{
    uint32_t i;
    for (i = 0; i < 4; i++) wr_u32le(dst + 4 * i, KEY_REG(off + 4 * i));
}

/* Y01K 112B：
 *   0 magic "Y01K" | 4 u16 version | 6 u16 flags(bit1 SIMULATED 恒 0)
 *   8 u32 cmd | 12 u32 seq | 16 u32 result | 20 u32 STATUS
 *  24 u32 DNA_LO | 28 u32 DNA_HI | 32 u64 op mcycle
 *  40 REF[16] | 56 MASK[16] | 72 RAW[16] | 88 DITHER[16] | 104 u64 发帧时刻 mcycle
 * 发帧时刻 mcycle 让 PS 用两帧的 Δmcycle/Δwall 直接测出 CPU 实际时钟（FCLK0）。 */
static void send_puf_frame(uint32_t cmd, uint32_t seq, uint32_t result, uint64_t cycles)
{
    uint8_t f[PUF_RSP_BYTES];
    uint32_t i;
    uint64_t now;

    for (i = 0; i < PUF_RSP_BYTES; i++) f[i] = 0;
    f[0] = 'Y'; f[1] = '0'; f[2] = '1'; f[3] = 'K';
    f[4] = (uint8_t)PROTO_VERSION;
    wr_u32le(f + 8, cmd);
    wr_u32le(f + 12, seq);
    wr_u32le(f + 16, result);
    wr_u32le(f + 20, KEY_STATUS);
    wr_u32le(f + 24, KEY_REG(KEY_DNA_LO));
    wr_u32le(f + 28, KEY_REG(KEY_DNA_HI));
    wr_u32le(f + 32, (uint32_t)cycles);
    wr_u32le(f + 36, (uint32_t)(cycles >> 32));
    put_block(f + 40, KEY_REF0);
    put_block(f + 56, KEY_MASK0);
    put_block(f + 72, KEY_RAW0);
    put_block(f + 88, KEY_DITH0);
    now = svc_mcycle();
    wr_u32le(f + 104, (uint32_t)now);
    wr_u32le(f + 108, (uint32_t)(now >> 32));
    for (i = 0; i < PUF_RSP_BYTES; i++) svc_putc(f[i]);
}

void puf_handle_request(void)
{
    uint8_t b[PUF_REQ_BYTES - 4];
    uint32_t i, version, cmd, seq, result;
    uint64_t c0;

    for (i = 0; i < sizeof(b); i++) b[i] = svc_getc();
    version = rd_u32le(b);
    cmd     = rd_u32le(b + 4);
    seq     = rd_u32le(b + 8);

    c0 = svc_mcycle();
    if (version != PROTO_VERSION) {
        result = PUF_BAD_VERSION;
    } else {
        switch (cmd) {
            case PUF_CMD_STATUS:      result = PUF_OK; break;
            case PUF_CMD_ENROLL:      result = run_keygen(1u); break;
            case PUF_CMD_RECONSTRUCT: result = run_keygen(0u); break;
            case PUF_CMD_HWKEY_ON:    result = hwkey_on(); break;
            case PUF_CMD_HWKEY_OFF:   puf_hwkey_off(); result = PUF_OK; break;
            default:                  result = PUF_BAD_CMD; break;
        }
    }
    send_puf_frame(cmd, seq, result, svc_mcycle() - c0);
}
