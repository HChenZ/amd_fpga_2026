/* Ascon-AEAD128 with the permutation accelerated by the custom ISE.
 *
 * The CPU runs the full Ascon-AEAD128 algorithm in C (init / AD absorb /
 * plaintext squeeze / finalize), but every P12/P8 permutation is executed by
 * the custom instruction (ascon.p12 / ascon.p8) on the 320-bit state register
 * instead of the uint64_t software permutation. Verifies official KAT vectors
 * and measures warm cycle counts to compare against the pure-software baseline.
 *
 * Custom instructions (custom-0 opcode 0x0B):
 *   ascon.w   funct3=0 : state[32*idx] = data   (rs1=data, rs2=idx)
 *   ascon.rd  funct3=1 : rd = state[32*idx]     (rs1=idx)
 *   ascon.p12 funct3=2 : state = P12(state)
 *   ascon.p8  funct3=3 : state = P8(state)
 */
#include <stdint.h>
#include "uart.h"

/* ------------------------------------------------------------------ */
/* ISE wrappers (inline asm, custom-0 R-type via .insn)               */
/* ------------------------------------------------------------------ */
static inline void ascon_w(uint32_t data, uint32_t idx)
{
    __asm__ volatile (".insn r 0x0B, 0, 0, x0, %0, %1" :: "r"(data), "r"(idx));
}
static inline uint32_t ascon_rd(uint32_t idx)
{
    uint32_t r;
    __asm__ volatile (".insn r 0x0B, 1, 0, %0, %1, x0" : "=r"(r) : "r"(idx));
    return r;
}
static inline void ascon_p12(void) { __asm__ volatile (".insn r 0x0B, 2, 0, x0, x0, x0"); }
static inline void ascon_p8(void)  { __asm__ volatile (".insn r 0x0B, 3, 0, x0, x0, x0"); }

/* ------------------------------------------------------------------ */
/* Performance counter (mcycle)                                       */
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
    if (hi != hi2) { hi = rd_csr(0xB80); lo = rd_csr(0xB00); }
    return ((uint64_t)hi << 32) | lo;
}

/* ------------------------------------------------------------------ */
/* Ascon state + ISE permutation                                      */
/* ------------------------------------------------------------------ */
typedef struct { uint64_t x[5]; } ascon_state_t;

static void ise_load(const uint64_t *x)
{
    int i;
    for (i = 0; i < 5; i++) {
        ascon_w((uint32_t)(x[i] & 0xFFFFFFFFull), (uint32_t)(2 * i));
        ascon_w((uint32_t)(x[i] >> 32), (uint32_t)(2 * i + 1));
    }
}
static void ise_store(uint64_t *x)
{
    int i;
    for (i = 0; i < 5; i++) {
        uint32_t lo = ascon_rd((uint32_t)(2 * i));
        uint32_t hi = ascon_rd((uint32_t)(2 * i + 1));
        x[i] = ((uint64_t)hi << 32) | lo;
    }
}
static void ise_p12(ascon_state_t *s) { ise_load(s->x); ascon_p12(); ise_store(s->x); }
static void ise_p8(ascon_state_t *s)  { ise_load(s->x); ascon_p8();  ise_store(s->x); }

/* ------------------------------------------------------------------ */
/* Byte helpers (little-endian, matches ascon C reference)            */
/* ------------------------------------------------------------------ */
static inline uint64_t LOADBYTES(const uint8_t *b, int n)
{
    uint64_t x = 0;
    int i;
    for (i = 0; i < n; i++) x |= (uint64_t)b[i] << (8 * i);
    return x;
}
static inline void STOREBYTES(uint8_t *b, uint64_t x, int n)
{
    int i;
    for (i = 0; i < n; i++) b[i] = (uint8_t)(x >> (8 * i));
}

#define ASCON_128A_IV 0x00001000808C0001ull
#define DSEP 0x8000000000000000ull

/* ------------------------------------------------------------------ */
/* Ascon-AEAD128 encrypt (permutation via ISE)                        */
/* ------------------------------------------------------------------ */
static void ascon_encrypt(uint8_t *c, uint8_t *tag,
                          const uint8_t *m, uint32_t mlen,
                          const uint8_t *ad, uint32_t adlen,
                          const uint8_t *npub, const uint8_t *k)
{
    uint64_t K0 = LOADBYTES(k, 8), K1 = LOADBYTES(k + 8, 8);
    uint64_t N0 = LOADBYTES(npub, 8), N1 = LOADBYTES(npub + 8, 8);
    ascon_state_t s;

    s.x[0] = ASCON_128A_IV; s.x[1] = K0; s.x[2] = K1; s.x[3] = N0; s.x[4] = N1;
    ise_p12(&s);
    s.x[3] ^= K0; s.x[4] ^= K1;

    if (adlen) {
        while (adlen >= 16) {
            s.x[0] ^= LOADBYTES(ad, 8);
            s.x[1] ^= LOADBYTES(ad + 8, 8);
            ise_p8(&s);
            ad += 16; adlen -= 16;
        }
        if (adlen >= 8) {
            s.x[0] ^= LOADBYTES(ad, 8);
            s.x[1] ^= LOADBYTES(ad + 8, (int)adlen - 8);
            s.x[1] ^= 1ull << (8 * (adlen - 8));
        } else {
            s.x[0] ^= LOADBYTES(ad, (int)adlen);
            s.x[0] ^= 1ull << (8 * adlen);
        }
        ise_p8(&s);
    }
    s.x[4] ^= DSEP;

    while (mlen >= 16) {
        s.x[0] ^= LOADBYTES(m, 8);
        s.x[1] ^= LOADBYTES(m + 8, 8);
        STOREBYTES(c, s.x[0], 8);
        STOREBYTES(c + 8, s.x[1], 8);
        ise_p8(&s);
        m += 16; c += 16; mlen -= 16;
    }
    if (mlen >= 8) {
        s.x[0] ^= LOADBYTES(m, 8);
        s.x[1] ^= LOADBYTES(m + 8, (int)mlen - 8);
        STOREBYTES(c, s.x[0], 8);
        STOREBYTES(c + 8, s.x[1], (int)mlen - 8);
        s.x[1] ^= 1ull << (8 * (mlen - 8));
    } else {
        s.x[0] ^= LOADBYTES(m, (int)mlen);
        STOREBYTES(c, s.x[0], (int)mlen);
        s.x[0] ^= 1ull << (8 * mlen);
    }

    s.x[2] ^= K0; s.x[3] ^= K1;
    ise_p12(&s);
    s.x[3] ^= K0; s.x[4] ^= K1;
    STOREBYTES(tag, s.x[3], 8);
    STOREBYTES(tag + 8, s.x[4], 8);
}

/* ------------------------------------------------------------------ */
/* Ascon-AEAD128 decrypt (permutation via ISE)                        */
/* ------------------------------------------------------------------ */
static int ascon_decrypt(uint8_t *m, const uint8_t *c, uint32_t clen,
                         const uint8_t *ad, uint32_t adlen,
                         const uint8_t *npub, const uint8_t *k)
{
    uint64_t K0 = LOADBYTES(k, 8), K1 = LOADBYTES(k + 8, 8);
    uint64_t N0 = LOADBYTES(npub, 8), N1 = LOADBYTES(npub + 8, 8);
    ascon_state_t s;
    int i, result = 0;

    s.x[0] = ASCON_128A_IV; s.x[1] = K0; s.x[2] = K1; s.x[3] = N0; s.x[4] = N1;
    ise_p12(&s);
    s.x[3] ^= K0; s.x[4] ^= K1;

    if (adlen) {
        while (adlen >= 16) {
            s.x[0] ^= LOADBYTES(ad, 8);
            s.x[1] ^= LOADBYTES(ad + 8, 8);
            ise_p8(&s);
            ad += 16; adlen -= 16;
        }
        if (adlen >= 8) {
            s.x[0] ^= LOADBYTES(ad, 8);
            s.x[1] ^= LOADBYTES(ad + 8, (int)adlen - 8);
            s.x[1] ^= 1ull << (8 * (adlen - 8));
        } else {
            s.x[0] ^= LOADBYTES(ad, (int)adlen);
            s.x[0] ^= 1ull << (8 * adlen);
        }
        ise_p8(&s);
    }
    s.x[4] ^= DSEP;

    while (clen >= 16) {
        uint64_t c0 = LOADBYTES(c, 8), c1 = LOADBYTES(c + 8, 8);
        STOREBYTES(m, s.x[0] ^ c0, 8);
        STOREBYTES(m + 8, s.x[1] ^ c1, 8);
        s.x[0] = c0; s.x[1] = c1;
        ise_p8(&s);
        m += 16; c += 16; clen -= 16;
    }
    if (clen >= 8) {
        uint64_t c0 = LOADBYTES(c, 8), c1 = LOADBYTES(c + 8, (int)clen - 8);
        STOREBYTES(m, s.x[0] ^ c0, 8);
        STOREBYTES(m + 8, s.x[1] ^ c1, (int)clen - 8);
        s.x[0] = c0;
        s.x[1] = (s.x[1] & ~((1ull << (8 * (clen - 8))) - 1)) | c1;
        s.x[1] ^= 1ull << (8 * (clen - 8));
    } else {
        uint64_t c0 = LOADBYTES(c, (int)clen);
        STOREBYTES(m, s.x[0] ^ c0, (int)clen);
        s.x[0] = (s.x[0] & ~((1ull << (8 * clen)) - 1)) | c0;
        s.x[0] ^= 1ull << (8 * clen);
    }

    s.x[2] ^= K0; s.x[3] ^= K1;
    ise_p12(&s);
    s.x[3] ^= K0; s.x[4] ^= K1;

    {
        uint8_t t[16];
        STOREBYTES(t, s.x[3], 8);
        STOREBYTES(t + 8, s.x[4], 8);
        for (i = 0; i < 16; i++) result |= c[i] ^ t[i];   /* c now points at the tag */
    }
    return (result != 0);
}

/* ------------------------------------------------------------------ */
/* Test vectors                                                       */
/* ------------------------------------------------------------------ */
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

static int bytes_eq(const uint8_t *a, const uint8_t *b, uint32_t n)
{
    uint32_t i;
    for (i = 0; i < n; i++) if (a[i] != b[i]) return 0;
    return 1;
}

int main(void)
{
    uint8_t ct[32], tag[16], m[32];
    uint64_t c0, c1;
    int ok, all_ok = 1;

    uart_puts("\n=== ASCON-AEAD128 ISE (permutation in hardware) ===\n");

    /* empty */
    ascon_encrypt(ct, tag, 0, 0, 0, 0, npub, key);
    ok = bytes_eq(tag, tag_empty, 16);
    uart_puts("KAT empty  : "); uart_puts(ok ? "PASS\n" : "FAIL\n"); if(!ok) all_ok = 0;

    /* 1B */
    ascon_encrypt(ct, tag, pt_1, 1, 0, 0, npub, key);
    ok = bytes_eq(ct, ct_1, 1) && bytes_eq(tag, tag_1, 16);
    uart_puts("KAT 1B     : "); uart_puts(ok ? "PASS\n" : "FAIL\n"); if(!ok) all_ok = 0;

    /* 16B */
    ascon_encrypt(ct, tag, pt_16, 16, 0, 0, npub, key);
    ok = bytes_eq(ct, ct_16, 16) && bytes_eq(tag, tag_16, 16);
    uart_puts("KAT 16B    : "); uart_puts(ok ? "PASS\n" : "FAIL\n"); if(!ok) all_ok = 0;

    /* 16B + 16B AD */
    ascon_encrypt(ct, tag, pt_16, 16, ad_16, 16, npub, key);
    ok = bytes_eq(ct, ct_16ad, 16) && bytes_eq(tag, tag_16ad, 16);
    uart_puts("KAT 16B+AD : "); uart_puts(ok ? "PASS\n" : "FAIL\n"); if(!ok) all_ok = 0;

    /* decrypt round-trip (16B): decrypt ct||tag back to plaintext */
    {
        uint8_t ctt[32];
        for (int i = 0; i < 16; i++) ctt[i]      = ct_16[i];
        for (int i = 0; i < 16; i++) ctt[16 + i] = tag_16[i];
        ok = (ascon_decrypt(m, ctt, 16, 0, 0, npub, key) == 0) && bytes_eq(m, pt_16, 16);
        uart_puts("dec round  : "); uart_puts(ok ? "PASS\n" : "FAIL\n"); if(!ok) all_ok = 0;
    }

    /* tamper reject (flip one ciphertext byte -> tag verify must fail) */
    {
        uint8_t bad[32];
        for (int i = 0; i < 16; i++) bad[i]      = ct_16[i];
        for (int i = 0; i < 16; i++) bad[16 + i] = tag_16[i];
        bad[0] ^= 0x01;
        ok = (ascon_decrypt(m, bad, 16, 0, 0, npub, key) != 0);
        uart_puts("tamper     : "); uart_puts(ok ? "PASS\n" : "FAIL\n"); if(!ok) all_ok = 0;
    }

    /* ---- benchmark (warm): 16B encrypt ---- */
    ascon_encrypt(ct, tag, pt_16, 16, 0, 0, npub, key);  /* warm-up */
    c0 = read_mcycle();
    ascon_encrypt(ct, tag, pt_16, 16, 0, 0, npub, key);
    c1 = read_mcycle();
    uart_puts("--- benchmark (warm) 16B encrypt ---\n");
    uart_puts("ISE cycles   : "); uart_putdec_u64(c1 - c0); uart_puts("\n");

    uart_puts("===DONE===\n");
    for (;;) { }
    return all_ok ? 0 : 1;
}
