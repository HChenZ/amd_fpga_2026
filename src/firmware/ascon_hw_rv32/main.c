/* Ascon-AEAD128 hardware (MMIO accelerator) self-test + benchmark on RV32IM.
 *
 * Drives the ascon_mmio peripheral (base 0x30000000) that wraps the
 * KAT-verified crypto_aead RTL core. Runs four official KAT vectors
 * (<=16 bytes), a decrypt round-trip, a tamper-reject check, and the >16-byte
 * reject path. Measures warm cycle counts (mcycle) for both the pure hardware
 * crypto latency (START->DONE) and the full MMIO round-trip.
 */
#include <stdint.h>
#include "uart.h"

/* ------------------------------------------------------------------ */
/* MMIO register map (base 0x30000000, 32-bit word access)            */
/* ------------------------------------------------------------------ */
#define ASCON_BASE 0x30000000u
#define REG(off) (*(volatile uint32_t*)(ASCON_BASE + (off)))

#define ASCON_CTRL       REG(0x00)   /* W [0]=START [1]=ENCRYPT */
#define ASCON_STATUS     REG(0x04)   /* R [0]=BUSY [1]=DONE [2]=FAIL */
#define ASCON_ADLEN      REG(0x08)
#define ASCON_MLEN       REG(0x0C)
#define ASCON_KEY0       REG(0x10)
#define ASCON_KEY1       REG(0x14)
#define ASCON_KEY2       REG(0x18)
#define ASCON_KEY3       REG(0x1C)
#define ASCON_NONCE0     REG(0x20)
#define ASCON_NONCE1     REG(0x24)
#define ASCON_NONCE2     REG(0x28)
#define ASCON_NONCE3     REG(0x2C)
#define ASCON_TAGIN0     REG(0x30)
#define ASCON_TAGIN1     REG(0x34)
#define ASCON_TAGIN2     REG(0x38)
#define ASCON_TAGIN3     REG(0x3C)
#define ASCON_AD_WDATA   REG(0x40)
#define ASCON_MSG_WDATA  REG(0x44)
#define ASCON_OUT_RDATA  REG(0x48)
#define ASCON_TAGOUT0    REG(0x4C)
#define ASCON_TAGOUT1    REG(0x50)
#define ASCON_TAGOUT2    REG(0x54)
#define ASCON_TAGOUT3    REG(0x58)

#define STATUS_BUSY 0x1
#define STATUS_DONE 0x2
#define STATUS_FAIL 0x4

/* ------------------------------------------------------------------ */
/* Performance counters (mcycle via CSR 0xB00/0xB80)                  */
/* ------------------------------------------------------------------ */
static inline uint32_t rd_csr(uint32_t csr)
{
    uint32_t v;
    __asm__ volatile ("csrr %0, %1" : "=r"(v) : "i"(csr));
    return v;
}

static uint64_t read_mcycle(void)
{
    uint32_t hi, lo, hi2;
    hi  = rd_csr(0xB80);
    lo  = rd_csr(0xB00);
    hi2 = rd_csr(0xB80);
    if (hi != hi2) {
        hi = rd_csr(0xB80);
        lo = rd_csr(0xB00);
    }
    return ((uint64_t)hi << 32) | lo;
}

/* ------------------------------------------------------------------ */
/* Helpers                                                            */
/* ------------------------------------------------------------------ */
static inline uint32_t le32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void wr128(volatile uint32_t *base, const uint8_t *b)
{
    base[0] = le32(b);
    base[1] = le32(b + 4);
    base[2] = le32(b + 8);
    base[3] = le32(b + 12);
}

static void rd128(const volatile uint32_t *base, uint8_t *b)
{
    uint32_t w0 = base[0], w1 = base[1], w2 = base[2], w3 = base[3];
    int i;
    for (i = 0; i < 4; i++) { b[i]     = (uint8_t)(w0 >> (8 * i)); }
    for (i = 0; i < 4; i++) { b[4 + i] = (uint8_t)(w1 >> (8 * i)); }
    for (i = 0; i < 4; i++) { b[8 + i] = (uint8_t)(w2 >> (8 * i)); }
    for (i = 0; i < 4; i++) { b[12 + i] = (uint8_t)(w3 >> (8 * i)); }
}

static int bytes_eq(const uint8_t *a, const uint8_t *b, uint32_t n)
{
    uint32_t i;
    for (i = 0; i < n; i++)
        if (a[i] != b[i]) return 0;
    return 1;
}

/* ------------------------------------------------------------------ */
/* MMIO driver                                                        */
/* ------------------------------------------------------------------ */

/* Setup registers and data buffers, then fire START. Does not poll.  */
static void ascon_hw_start(int encrypt, uint32_t adlen, uint32_t mlen,
                           const uint8_t *key, const uint8_t *nonce,
                           const uint8_t *tagin,
                           const uint8_t *ad, const uint8_t *msg)
{
    uint32_t i, aw = (adlen + 3) / 4, mw = (mlen + 3) / 4;

    /* Reject before narrowing 32-bit API lengths to 16-bit registers. */
    ASCON_ADLEN = adlen > 16 ? 17 : adlen;
    ASCON_MLEN  = mlen > 16 ? 17 : mlen;
    if(adlen > 16 || mlen > 16) aw = mw = 0;
    wr128(&ASCON_KEY0, key);
    wr128(&ASCON_NONCE0, nonce);
    if (!encrypt)
        wr128(&ASCON_TAGIN0, tagin);

    /* Never read beyond partial caller buffers (1/7/9/15-byte cases). */
    for (i = 0; i < aw; i++) {
        uint32_t w=0;
        for(uint32_t b=0;b<4 && 4*i+b<adlen;b++) w |= (uint32_t)ad[4*i+b] << (8*b);
        ASCON_AD_WDATA=w;
    }
    for (i = 0; i < mw; i++) {
        uint32_t w=0;
        for(uint32_t b=0;b<4 && 4*i+b<mlen;b++) w |= (uint32_t)msg[4*i+b] << (8*b);
        ASCON_MSG_WDATA=w;
    }

    ASCON_CTRL = (encrypt ? 2u : 0u) | 1u;   /* ENCRYPT | START */
}

/* Poll STATUS until DONE, return the fail bit (0 = success). */
static uint32_t ascon_hw_poll(void)
{
    uint32_t st;
    do {
        st = ASCON_STATUS;
    } while (!(st & STATUS_DONE));
    return (st & STATUS_FAIL) ? 1u : 0u;
}

static void ascon_hw_read_out(uint8_t *out, uint32_t mlen)
{
    uint32_t i, w;
    for (i = 0; i < (mlen + 3) / 4; i++) {
        w = ASCON_OUT_RDATA;
        for (int b = 0; b < 4; b++)
            if (4 * i + b < mlen) out[4 * i + b] = (uint8_t)(w >> (8 * b));
    }
}

/* ------------------------------------------------------------------ */
/* Test vectors                                                       */
/* ------------------------------------------------------------------ */
/* PUBLIC KAT DATA ONLY. Runtime helpers take caller Key/Nonce parameters.
 * Never replace these constants with deployment secrets. */
static const uint8_t key[16]  = {0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
                                 0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f};
static const uint8_t npub[16] = {0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,
                                 0x18,0x19,0x1a,0x1b,0x1c,0x1d,0x1e,0x1f};

static const uint8_t pt_1[1]    = {0x20};
static const uint8_t pt_16[16]  = {0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,
                                   0x28,0x29,0x2a,0x2b,0x2c,0x2d,0x2e,0x2f};
static const uint8_t ad_16[16]  = {0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,
                                   0x38,0x39,0x3a,0x3b,0x3c,0x3d,0x3e,0x3f};

static const uint8_t ct_1[1]  = {0xe8};
static const uint8_t ct_16[16] = {0xe8,0xc3,0xde,0xee,0x24,0x6c,0xc5,0xea,
                                  0xe3,0xe8,0x72,0x31,0x38,0x97,0xa2,0xbb};
static const uint8_t ct_16ad[16] = {0x63,0x73,0xeb,0xb2,0x8b,0xe9,0x7c,0x9b,
                                    0xac,0x09,0x0c,0xf3,0x99,0xc1,0x3e,0xf1};

static const uint8_t tag_empty[16] = {0x4f,0x9c,0x27,0x82,0x11,0xbe,0xc9,0x31,
                                       0x6b,0xf6,0x8f,0x46,0xee,0x8b,0x2e,0xc6};
static const uint8_t tag_1[16]  = {0xdd,0x57,0x6a,0xba,0x1c,0xd3,0xe6,0xfc,
                                   0x70,0x4d,0xe0,0x2a,0xed,0xb7,0x95,0x88};
static const uint8_t tag_16[16] = {0x9e,0xaa,0x91,0x5c,0x9d,0xd3,0x24,0x5d,
                                   0x77,0x04,0x8f,0x24,0xd4,0x6d,0x27,0xa7};
static const uint8_t tag_16ad[16] = {0x3a,0xbf,0xc0,0xd2,0x09,0xe8,0xf4,0x84,
                                     0x4c,0x90,0x81,0x4d,0x13,0xf3,0x2c,0x59};

int main(void)
{
    uint8_t out[32], tag[16];
    uint32_t fail, ok, all_ok = 1;
    uint64_t c0, c1, crypto_cyc, full_cyc;

    uart_puts("\n=== ASCON-AEAD128 hardware (MMIO) on RV32IM ===\n");

    /* ---- KAT encrypt via MMIO ---- */

    /* empty (0B msg, 0B AD) */
    ascon_hw_start(1, 0, 0, key, npub, 0, 0, 0);
    fail = ascon_hw_poll();
    rd128(&ASCON_TAGOUT0, tag);
    ok = !fail && bytes_eq(tag, tag_empty, 16);
    uart_puts("KAT empty   : "); uart_puts(ok ? "PASS\n" : "FAIL\n"); if(!ok) all_ok = 0;

    /* 1B msg */
    ascon_hw_start(1, 0, 1, key, npub, 0, 0, pt_1);
    fail = ascon_hw_poll();
    ascon_hw_read_out(out, 1);
    rd128(&ASCON_TAGOUT0, tag);
    ok = !fail && bytes_eq(out, ct_1, 1) && bytes_eq(tag, tag_1, 16);
    uart_puts("KAT 1B      : "); uart_puts(ok ? "PASS\n" : "FAIL\n"); if(!ok) all_ok = 0;

    /* 16B msg */
    ascon_hw_start(1, 0, 16, key, npub, 0, 0, pt_16);
    fail = ascon_hw_poll();
    ascon_hw_read_out(out, 16);
    rd128(&ASCON_TAGOUT0, tag);
    ok = !fail && bytes_eq(out, ct_16, 16) && bytes_eq(tag, tag_16, 16);
    uart_puts("KAT 16B     : "); uart_puts(ok ? "PASS\n" : "FAIL\n"); if(!ok) all_ok = 0;

    /* 16B msg + 16B AD */
    ascon_hw_start(1, 16, 16, key, npub, 0, ad_16, pt_16);
    fail = ascon_hw_poll();
    ascon_hw_read_out(out, 16);
    rd128(&ASCON_TAGOUT0, tag);
    ok = !fail && bytes_eq(out, ct_16ad, 16) && bytes_eq(tag, tag_16ad, 16);
    uart_puts("KAT 16B+AD  : "); uart_puts(ok ? "PASS\n" : "FAIL\n"); if(!ok) all_ok = 0;

    /* ---- decrypt round-trip (16B) ---- */
    ascon_hw_start(0, 0, 16, key, npub, tag_16, 0, ct_16);
    fail = ascon_hw_poll();
    ascon_hw_read_out(out, 16);
    ok = !fail && bytes_eq(out, pt_16, 16);
    uart_puts("dec roundtrip: "); uart_puts(ok ? "PASS\n" : "FAIL\n"); if(!ok) all_ok = 0;

    /* ---- tamper reject (flip one ciphertext byte -> decrypt must FAIL) ---- */
    {
        uint8_t bad_ct[16];
        for (int i = 0; i < 16; i++) bad_ct[i] = ct_16[i];
        bad_ct[0] ^= 0x01;
        ascon_hw_start(0, 0, 16, key, npub, tag_16, 0, bad_ct);
        fail = ascon_hw_poll();
        ok = (fail == 1);
        uart_puts("tamper reject: "); uart_puts(ok ? "PASS\n" : "FAIL\n"); if(!ok) all_ok = 0;
    }

    /* ---- length reject (17B > 16B must be rejected, FAIL) ---- */
    {
        static const uint8_t pt_17[17] = {0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,
                                          0x28,0x29,0x2a,0x2b,0x2c,0x2d,0x2e,0x2f,0x30};
        ascon_hw_start(1, 0, 17, key, npub, 0, 0, pt_17);
        fail = ascon_hw_poll();
        ok = (fail == 1);
        uart_puts("len reject  : "); uart_puts(ok ? "PASS\n" : "FAIL\n"); if(!ok) all_ok = 0;
    }

    /* ---- benchmark (warm): 16B encrypt ---- */
    /* warm-up (fills caches + proves the path) */
    ascon_hw_start(1, 0, 16, key, npub, 0, 0, pt_16);
    ascon_hw_poll();
    ascon_hw_read_out(out, 16);

    /* full MMIO round-trip: registers + data + START + poll + readback */
    c0 = read_mcycle();
    ascon_hw_start(1, 0, 16, key, npub, 0, 0, pt_16);
    ascon_hw_poll();
    ascon_hw_read_out(out, 16);
    rd128(&ASCON_TAGOUT0, tag);
    full_cyc = read_mcycle() - c0;

    /* pure crypto latency: START -> DONE (registers/data already in place,
       re-trigger while idle so only the core execution is timed) */
    ascon_hw_start(1, 0, 16, key, npub, 0, 0, pt_16);
    ascon_hw_poll();                    /* finish this op so we are idle */
    c0 = read_mcycle();
    ASCON_CTRL = (2u | 1u);             /* START only; buffers/registers persist */
    {
        uint32_t st;
        do { st = ASCON_STATUS; } while (!(st & STATUS_DONE));
    }
    c1 = read_mcycle();
    crypto_cyc = c1 - c0;

    uart_puts("--- benchmark (warm) 16B encrypt ---\n");
    uart_puts("crypto latency : "); uart_putdec_u64(crypto_cyc); uart_puts(" cycles\n");
    uart_puts("full MMIO      : "); uart_putdec_u64(full_cyc); uart_puts(" cycles\n");

    ASCON_CTRL = 4u; /* idle ZEROIZE after the final result was consumed */

    /* ---- summary ---- */
    uart_puts("===DONE===\n");
    for (;;) { }
    return all_ok ? 0 : 1;
}
