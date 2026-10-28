/* ascon_modes.c —— pynq_svc 的三种 Ascon-AEAD128 实现
 *
 * MODE_SW  : 直接 #include 仓库里锁定的生产 C 实现 ascon/ascon_c/aead/aead.c，
 *            与 host 侧 golden_checker / MemoryTransport 用的是同一份参考代码。
 * MODE_ISE : CPU 编排 + ascon.p12/p8 自定义指令（custom-0, opcode 0x0B），
 *            算法主体与 P0 已签核的 ascon_ise_rv32/main.c 同构。
 * MODE_HW  : 0x30000000 ascon_mmio 加速器（寄存器序列与 ascon_hw_rv32/main.c 相同）。
 *
 * 三种模式都只处理调用方给定的长度；长度上限由 main.c 在调用前检查，
 * 这里不做任何隐式截断。每种实现末尾都做软件可见的状态清理。
 */
#include "svc.h"

/* ========================== 官方 KAT（公开数据） ========================== */
static const uint8_t kat_key[16] = {0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
                                    0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f};
static const uint8_t kat_npub[16] = {0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,
                                     0x18,0x19,0x1a,0x1b,0x1c,0x1d,0x1e,0x1f};
static const uint8_t kat_pt1[1]   = {0x20};
static const uint8_t kat_pt16[16] = {0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,
                                     0x28,0x29,0x2a,0x2b,0x2c,0x2d,0x2e,0x2f};
static const uint8_t kat_ad16[16] = {0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,
                                     0x38,0x39,0x3a,0x3b,0x3c,0x3d,0x3e,0x3f};
static const uint8_t kat_ct1[1]   = {0xe8};
static const uint8_t kat_ct16[16] = {0xe8,0xc3,0xde,0xee,0x24,0x6c,0xc5,0xea,
                                     0xe3,0xe8,0x72,0x31,0x38,0x97,0xa2,0xbb};
static const uint8_t kat_ct16ad[16] = {0x63,0x73,0xeb,0xb2,0x8b,0xe9,0x7c,0x9b,
                                       0xac,0x09,0x0c,0xf3,0x99,0xc1,0x3e,0xf1};
static const uint8_t kat_tag_empty[16] = {0x4f,0x9c,0x27,0x82,0x11,0xbe,0xc9,0x31,
                                          0x6b,0xf6,0x8f,0x46,0xee,0x8b,0x2e,0xc6};
static const uint8_t kat_tag1[16] = {0xdd,0x57,0x6a,0xba,0x1c,0xd3,0xe6,0xfc,
                                     0x70,0x4d,0xe0,0x2a,0xed,0xb7,0x95,0x88};
static const uint8_t kat_tag16[16] = {0x9e,0xaa,0x91,0x5c,0x9d,0xd3,0x24,0x5d,
                                      0x77,0x04,0x8f,0x24,0xd4,0x6d,0x27,0xa7};
static const uint8_t kat_tag16ad[16] = {0x3a,0xbf,0xc0,0xd2,0x09,0xe8,0xf4,0x84,
                                        0x4c,0x90,0x81,0x4d,0x13,0xf3,0x2c,0x59};

static int bytes_eq(const uint8_t *a, const uint8_t *b, uint32_t n)
{
    uint32_t i;
    for (i = 0; i < n; i++) if (a[i] != b[i]) return 0;
    return 1;
}

static void wipe(void *p, uint32_t n)
{
    volatile uint8_t *q = (volatile uint8_t *)p;
    while (n--) *q++ = 0;
}

/* =============================== MODE_SW ================================== */
/* 锁定 C 参考实现（NIST SP 800-232 Final）；只借用它的公钥算法实现。 */
#include "aead.c"

static int sw_encrypt(uint8_t *ct, uint8_t *tag,
                      const uint8_t *m, uint32_t mlen,
                      const uint8_t *ad, uint32_t adlen,
                      const uint8_t *npub, const uint8_t *k)
{
    unsigned char buf[48];
    unsigned long long clen = 0;
    uint32_t i;

    if (mlen > 32) return -2;
    if (crypto_aead_encrypt(buf, &clen, m, mlen, ad, adlen, 0, npub, k) != 0)
        return -2;
    for (i = 0; i < mlen; i++) ct[i] = buf[i];
    for (i = 0; i < 16; i++)   tag[i] = buf[mlen + i];
    wipe(buf, sizeof(buf));
    return 0;
}

static int sw_decrypt(uint8_t *m, uint32_t *mlen,
                      const uint8_t *c, uint32_t clen,
                      const uint8_t *ad, uint32_t adlen,
                      const uint8_t *npub, const uint8_t *k,
                      const uint8_t *tag)
{
    unsigned char buf[48];
    unsigned long long olen = 0;
    uint32_t i;
    int rc;

    if (clen > 32) return -2;
    for (i = 0; i < clen; i++) buf[i] = c[i];
    for (i = 0; i < 16; i++)   buf[clen + i] = tag[i];
    rc = crypto_aead_decrypt(buf, &olen, 0, buf, clen + 16, ad, adlen, npub, k);
    if (rc == 0) {
        for (i = 0; i < clen; i++) m[i] = buf[i];
        *mlen = clen;
    } else {
        wipe(m, clen);
        *mlen = 0;
    }
    wipe(buf, sizeof(buf));
    return (rc == 0) ? 0 : -1;
}

/* =============================== MODE_ISE ================================= */
/* custom-0 (0x0B)：w=0 写 state[32*idx]、rd=1 读、p12=2、p8=3 */
static inline void ise_w(uint32_t data, uint32_t idx)
{
    __asm__ volatile (".insn r 0x0B, 0, 0, x0, %0, %1" :: "r"(data), "r"(idx));
}
static inline uint32_t ise_rd(uint32_t idx)
{
    uint32_t r;
    __asm__ volatile (".insn r 0x0B, 1, 0, %0, %1, x0" : "=r"(r) : "r"(idx));
    return r;
}
static inline void ise_p12_c(void) { __asm__ volatile (".insn r 0x0B, 2, 0, x0, x0, x0"); }
static inline void ise_p8_c(void)  { __asm__ volatile (".insn r 0x0B, 3, 0, x0, x0, x0"); }

static void ise_clear(void)
{
    uint32_t i;
    for (i = 0; i < 10; i++) ise_w(0, i);
    __asm__ volatile ("" ::: "memory");
}

typedef struct { uint64_t x[5]; } ise_state_t;

static void ise_load(const uint64_t *x)
{
    int i;
    for (i = 0; i < 5; i++) {
        ise_w((uint32_t)(x[i] & 0xFFFFFFFFull), (uint32_t)(2 * i));
        ise_w((uint32_t)(x[i] >> 32),           (uint32_t)(2 * i + 1));
    }
}
static void ise_store(uint64_t *x)
{
    int i;
    for (i = 0; i < 5; i++) {
        uint32_t lo = ise_rd((uint32_t)(2 * i));
        uint32_t hi = ise_rd((uint32_t)(2 * i + 1));
        x[i] = ((uint64_t)hi << 32) | lo;
    }
}
static void ise_p12(ise_state_t *s) { ise_load(s->x); ise_p12_c(); ise_store(s->x); }
static void ise_p8(ise_state_t *s)  { ise_load(s->x); ise_p8_c();  ise_store(s->x); }

static inline uint64_t ld64(const uint8_t *b, int n)
{
    uint64_t x = 0;
    int i;
    for (i = 0; i < n; i++) x |= (uint64_t)b[i] << (8 * i);
    return x;
}
static inline void st64(uint8_t *b, uint64_t x, int n)
{
    int i;
    for (i = 0; i < n; i++) b[i] = (uint8_t)(x >> (8 * i));
}

#define ISE_IV   0x00001000808C0001ull
#define ISE_DSEP 0x8000000000000000ull

static void ise_ad_absorb(ise_state_t *s, const uint8_t *ad, uint32_t adlen)
{
    while (adlen >= 16) {
        s->x[0] ^= ld64(ad, 8);
        s->x[1] ^= ld64(ad + 8, 8);
        ise_p8(s);
        ad += 16; adlen -= 16;
    }
    if (adlen >= 8) {
        s->x[0] ^= ld64(ad, 8);
        s->x[1] ^= ld64(ad + 8, (int)adlen - 8);
        s->x[1] ^= 1ull << (8 * (adlen - 8));
    } else {
        s->x[0] ^= ld64(ad, (int)adlen);
        s->x[0] ^= 1ull << (8 * adlen);
    }
    ise_p8(s);
}

static int ise_encrypt(uint8_t *c, uint8_t *tag,
                       const uint8_t *m, uint32_t mlen,
                       const uint8_t *ad, uint32_t adlen,
                       const uint8_t *npub, const uint8_t *k)
{
    uint64_t K0 = ld64(k, 8), K1 = ld64(k + 8, 8);
    uint64_t N0 = ld64(npub, 8), N1 = ld64(npub + 8, 8);
    ise_state_t s;

    s.x[0] = ISE_IV; s.x[1] = K0; s.x[2] = K1; s.x[3] = N0; s.x[4] = N1;
    ise_p12(&s);
    s.x[3] ^= K0; s.x[4] ^= K1;

    if (adlen) ise_ad_absorb(&s, ad, adlen);
    s.x[4] ^= ISE_DSEP;

    while (mlen >= 16) {
        s.x[0] ^= ld64(m, 8);
        s.x[1] ^= ld64(m + 8, 8);
        st64(c, s.x[0], 8);
        st64(c + 8, s.x[1], 8);
        ise_p8(&s);
        m += 16; c += 16; mlen -= 16;
    }
    if (mlen >= 8) {
        s.x[0] ^= ld64(m, 8);
        s.x[1] ^= ld64(m + 8, (int)mlen - 8);
        st64(c, s.x[0], 8);
        st64(c + 8, s.x[1], (int)mlen - 8);
        s.x[1] ^= 1ull << (8 * (mlen - 8));
    } else {
        s.x[0] ^= ld64(m, (int)mlen);
        st64(c, s.x[0], (int)mlen);
        s.x[0] ^= 1ull << (8 * mlen);
    }

    s.x[2] ^= K0; s.x[3] ^= K1;
    ise_p12(&s);
    s.x[3] ^= K0; s.x[4] ^= K1;
    st64(tag, s.x[3], 8);
    st64(tag + 8, s.x[4], 8);

    ise_clear();
    wipe(&s, sizeof(s));
    wipe(&K0, sizeof(K0)); wipe(&K1, sizeof(K1));
    wipe(&N0, sizeof(N0)); wipe(&N1, sizeof(N1));
    return 0;
}

static int ise_decrypt(uint8_t *m, uint32_t *mlen,
                       const uint8_t *c, uint32_t clen,
                       const uint8_t *ad, uint32_t adlen,
                       const uint8_t *npub, const uint8_t *k,
                       const uint8_t *tag)
{
    uint8_t  *m_out = m;
    uint32_t  plen  = clen;
    uint64_t  K0 = ld64(k, 8), K1 = ld64(k + 8, 8);
    uint64_t  N0 = ld64(npub, 8), N1 = ld64(npub + 8, 8);
    ise_state_t s;
    int i, diff = 0;

    *mlen = 0;
    s.x[0] = ISE_IV; s.x[1] = K0; s.x[2] = K1; s.x[3] = N0; s.x[4] = N1;
    ise_p12(&s);
    s.x[3] ^= K0; s.x[4] ^= K1;

    if (adlen) ise_ad_absorb(&s, ad, adlen);
    s.x[4] ^= ISE_DSEP;

    while (clen >= 16) {
        uint64_t c0 = ld64(c, 8), c1 = ld64(c + 8, 8);
        st64(m, s.x[0] ^ c0, 8);
        st64(m + 8, s.x[1] ^ c1, 8);
        s.x[0] = c0; s.x[1] = c1;
        ise_p8(&s);
        m += 16; c += 16; clen -= 16;
    }
    if (clen >= 8) {
        uint64_t c0 = ld64(c, 8), c1 = ld64(c + 8, (int)clen - 8);
        st64(m, s.x[0] ^ c0, 8);
        st64(m + 8, s.x[1] ^ c1, (int)clen - 8);
        s.x[0] = c0;
        s.x[1] = (s.x[1] & ~((1ull << (8 * (clen - 8))) - 1)) | c1;
        s.x[1] ^= 1ull << (8 * (clen - 8));
    } else {
        uint64_t c0 = ld64(c, (int)clen);
        st64(m, s.x[0] ^ c0, (int)clen);
        s.x[0] = (s.x[0] & ~((1ull << (8 * clen)) - 1)) | c0;
        s.x[0] ^= 1ull << (8 * clen);
    }

    s.x[2] ^= K0; s.x[3] ^= K1;
    ise_p12(&s);
    s.x[3] ^= K0; s.x[4] ^= K1;

    {
        uint8_t t[16];
        st64(t, s.x[3], 8);
        st64(t + 8, s.x[4], 8);
        for (i = 0; i < 16; i++) diff |= tag[i] ^ t[i];
        wipe(t, sizeof(t));
    }
    if (diff) wipe(m_out, plen);
    else      *mlen = plen;

    ise_clear();
    wipe(&s, sizeof(s));
    wipe(&K0, sizeof(K0)); wipe(&K1, sizeof(K1));
    wipe(&N0, sizeof(N0)); wipe(&N1, sizeof(N1));
    return diff ? -1 : 0;
}

/* =============================== MODE_HW ================================== */
static void hw_push128(volatile uint32_t *base, const uint8_t *b)
{
    base[0] = (uint32_t)b[0]        | ((uint32_t)b[1] << 8)  |
              ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
    base[1] = (uint32_t)b[4]        | ((uint32_t)b[5] << 8)  |
              ((uint32_t)b[6] << 16) | ((uint32_t)b[7] << 24);
    base[2] = (uint32_t)b[8]        | ((uint32_t)b[9] << 8)  |
              ((uint32_t)b[10] << 16) | ((uint32_t)b[11] << 24);
    base[3] = (uint32_t)b[12]       | ((uint32_t)b[13] << 8) |
              ((uint32_t)b[14] << 16) | ((uint32_t)b[15] << 24);
}

static void hw_read128(volatile uint32_t *base, uint8_t *b)
{
    uint32_t w[4];
    int i, j;
    for (i = 0; i < 4; i++) w[i] = base[i];
    for (i = 0; i < 4; i++)
        for (j = 0; j < 4; j++) b[4 * i + j] = (uint8_t)(w[i] >> (8 * j));
}

/* 先写寄存器与数据缓冲，再 START，然后轮询 DONE。 */
static void hw_start(int encrypt, uint32_t adlen, uint32_t mlen,
                     const uint8_t *key, const uint8_t *nonce,
                     const uint8_t *tagin,
                     const uint8_t *ad, const uint8_t *msg)
{
    uint32_t i, aw = (adlen + 3u) / 4u, mw = (mlen + 3u) / 4u;

    ASCON_ADLEN = adlen;
    ASCON_MLEN  = mlen;
    hw_push128(&ASCON_KEY0, key);
    hw_push128(&ASCON_NONCE0, nonce);
    if (!encrypt) hw_push128(&ASCON_TAGIN0, tagin);

    for (i = 0; i < aw; i++) {
        uint32_t w = 0, b;
        for (b = 0; b < 4 && 4 * i + b < adlen; b++)
            w |= (uint32_t)ad[4 * i + b] << (8 * b);
        ASCON_AD_WDATA = w;
    }
    for (i = 0; i < mw; i++) {
        uint32_t w = 0, b;
        for (b = 0; b < 4 && 4 * i + b < mlen; b++)
            w |= (uint32_t)msg[4 * i + b] << (8 * b);
        ASCON_MSG_WDATA = w;
    }
    ASCON_CTRL = (encrypt ? 2u : 0u) | 1u;
}

static uint32_t hw_poll(void)
{
    uint32_t st;
    uint64_t deadline = svc_mcycle() + 10000000ull;
    do {
        st = ASCON_STATUS;
        if (svc_mcycle() >= deadline) return 1u;
    } while (!(st & ASCON_ST_DONE));
    return (st & ASCON_ST_FAIL) ? 1u : 0u;
}

static int hw_encrypt(uint8_t *ct, uint8_t *tag,
                      const uint8_t *m, uint32_t mlen,
                      const uint8_t *ad, uint32_t adlen,
                      const uint8_t *npub, const uint8_t *k)
{
    uint32_t i, w;
    hw_start(1, adlen, mlen, k, npub, 0, ad, m);
    if (hw_poll()) return -1;
    for (i = 0; i < (mlen + 3u) / 4u; i++) {
        w = ASCON_OUT_RDATA;
        if (4 * i + 0 < mlen) ct[4 * i + 0] = (uint8_t)(w);
        if (4 * i + 1 < mlen) ct[4 * i + 1] = (uint8_t)(w >> 8);
        if (4 * i + 2 < mlen) ct[4 * i + 2] = (uint8_t)(w >> 16);
        if (4 * i + 3 < mlen) ct[4 * i + 3] = (uint8_t)(w >> 24);
    }
    hw_read128(&ASCON_TAGOUT0, tag);
    return 0;
}

static int hw_decrypt(uint8_t *m, uint32_t *mlen,
                      const uint8_t *c, uint32_t clen,
                      const uint8_t *ad, uint32_t adlen,
                      const uint8_t *npub, const uint8_t *k,
                      const uint8_t *tag)
{
    uint32_t i, w;
    *mlen = 0;
    hw_start(0, adlen, clen, k, npub, tag, ad, c);
    if (hw_poll()) {                     /* 认证失败：候选输出已被硬件清零 */
        wipe(m, clen);
        return -1;
    }
    for (i = 0; i < (clen + 3u) / 4u; i++) {
        w = ASCON_OUT_RDATA;
        if (4 * i + 0 < clen) m[4 * i + 0] = (uint8_t)(w);
        if (4 * i + 1 < clen) m[4 * i + 1] = (uint8_t)(w >> 8);
        if (4 * i + 2 < clen) m[4 * i + 2] = (uint8_t)(w >> 16);
        if (4 * i + 3 < clen) m[4 * i + 3] = (uint8_t)(w >> 24);
    }
    *mlen = clen;
    return 0;
}

/* ============================== 分发 + 自检 =============================== */
int svc_aead_encrypt(uint32_t mode, uint8_t *ct, uint8_t *tag,
                     const uint8_t *m, uint32_t mlen,
                     const uint8_t *ad, uint32_t adlen,
                     const uint8_t *npub, const uint8_t *k)
{
    switch (mode) {
        case MODE_SW:  return sw_encrypt(ct, tag, m, mlen, ad, adlen, npub, k);
        case MODE_HW:  return hw_encrypt(ct, tag, m, mlen, ad, adlen, npub, k);
        case MODE_ISE: return ise_encrypt(ct, tag, m, mlen, ad, adlen, npub, k);
        default:       return -2;
    }
}

int svc_aead_decrypt(uint32_t mode, uint8_t *m, uint32_t *mlen,
                     const uint8_t *c, uint32_t clen,
                     const uint8_t *ad, uint32_t adlen,
                     const uint8_t *npub, const uint8_t *k,
                     const uint8_t *tag)
{
    switch (mode) {
        case MODE_SW:  return sw_decrypt(m, mlen, c, clen, ad, adlen, npub, k, tag);
        case MODE_HW:  return hw_decrypt(m, mlen, c, clen, ad, adlen, npub, k, tag);
        case MODE_ISE: return ise_decrypt(m, mlen, c, clen, ad, adlen, npub, k, tag);
        default:       return -2;
    }
}

/* 开机自检：每模式跑 empty/1B/16B/16B+AD 加密 + 16B 解密回环 + 篡改拒绝，
 * 全部通过则置该模式的 mask 位；同时给出该模式 16B 加密的 mcycle 增量。 */
uint32_t svc_selftest(uint32_t *mask_out, uint64_t *cycles_out)
{
    static const uint32_t modes[3] = {MODE_SW, MODE_HW, MODE_ISE};
    uint8_t ct[32], tag[16], pt[32], bad[16];
    uint32_t mask = 0, i, j, mlen;
    uint64_t c0;
    int ok;

    *cycles_out = 0;

    for (i = 0; i < 3; i++) {
        uint32_t mode = modes[i];
        ok = 1;

        ok &= (svc_aead_encrypt(mode, ct, tag, 0, 0, 0, 0, kat_npub, kat_key) == 0)
              && bytes_eq(tag, kat_tag_empty, 16);
        ok &= (svc_aead_encrypt(mode, ct, tag, kat_pt1, 1, 0, 0, kat_npub, kat_key) == 0)
              && bytes_eq(ct, kat_ct1, 1) && bytes_eq(tag, kat_tag1, 16);
        ok &= (svc_aead_encrypt(mode, ct, tag, kat_pt16, 16, 0, 0, kat_npub, kat_key) == 0)
              && bytes_eq(ct, kat_ct16, 16) && bytes_eq(tag, kat_tag16, 16);
        ok &= (svc_aead_encrypt(mode, ct, tag, kat_pt16, 16, kat_ad16, 16, kat_npub, kat_key) == 0)
              && bytes_eq(ct, kat_ct16ad, 16) && bytes_eq(tag, kat_tag16ad, 16);
        ok &= (svc_aead_decrypt(mode, pt, &mlen, kat_ct16, 16, 0, 0,
                                kat_npub, kat_key, kat_tag16) == 0)
              && mlen == 16 && bytes_eq(pt, kat_pt16, 16);

        for (j = 0; j < 16; j++) bad[j] = kat_ct16[j];
        bad[0] ^= 0x01;
        ok &= (svc_aead_decrypt(mode, pt, &mlen, bad, 16, 0, 0,
                                kat_npub, kat_key, kat_tag16) == -1);

        if (ok) {
            mask |= (1u << (mode - 1));
            /* 记录该模式 16B 加密的 mcycle 增量（暖态，仅供 boot 帧展示） */
            svc_aead_encrypt(mode, ct, tag, kat_pt16, 16, 0, 0, kat_npub, kat_key);
            c0 = svc_mcycle();
            svc_aead_encrypt(mode, ct, tag, kat_pt16, 16, 0, 0, kat_npub, kat_key);
            if (*cycles_out == 0) *cycles_out = svc_mcycle() - c0;
        }
    }

    wipe(ct, sizeof(ct)); wipe(tag, sizeof(tag)); wipe(pt, sizeof(pt)); wipe(bad, sizeof(bad));
    *mask_out = mask;
    return mask;
}
