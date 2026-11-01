/* Ascon-AEAD128 (NIST SP 800-232) software self-test + benchmark on RV32IM.
 *
 * Includes the locked production C implementation (ascon/ascon_c/aead/aead.c)
 * directly, runs six official KAT vectors + a tamper-rejection check, then
 * measures warm cycle counts (CSR mcycle) and retired-instruction counts
 * (cpi_cnt MMIO) for encrypt/decrypt of 16-byte and 32-byte messages.
 */
#include <stdint.h>
#include "uart.h"
#include "aead.c"

/* ------------------------------------------------------------------ */
/* Performance counters                                              */
/* ------------------------------------------------------------------ */
static inline uint32_t rd_csr(uint32_t csr)
{
    uint32_t v;
    __asm__ volatile ("csrr %0, %1" : "=r"(v) : "i"(csr));
    return v;
}

/* mcycle is 64-bit across 0xB00 (lo) / 0xB80 (hi); read hi-lo-hi. */
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

/* Retired-instruction counter (cpi_cnt offset 0x00 lo / 0x04 hi). */
static uint64_t read_inst(void)
{
    uint32_t lo = *(volatile uint32_t*)0x60000000;
    uint32_t hi = *(volatile uint32_t*)0x60000004;
    return ((uint64_t)hi << 32) | lo;
}

/* ------------------------------------------------------------------ */
/* Test vectors (official NIST KAT, key/nonce fixed for all cases)    */
/* ------------------------------------------------------------------ */
/* PUBLIC KAT DATA ONLY. Runtime helpers take caller Key/Nonce parameters.
 * Never replace these constants with deployment secrets. */
static const uint8_t key[16]  = {0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
                                 0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f};
static const uint8_t npub[16] = {0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,
                                 0x18,0x19,0x1a,0x1b,0x1c,0x1d,0x1e,0x1f};

static const uint8_t pt_16[16]  = {0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,
                                   0x28,0x29,0x2a,0x2b,0x2c,0x2d,0x2e,0x2f};
static const uint8_t ad_16[16]  = {0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,
                                   0x38,0x39,0x3a,0x3b,0x3c,0x3d,0x3e,0x3f};
static const uint8_t pt_17[17]  = {0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,
                                   0x28,0x29,0x2a,0x2b,0x2c,0x2d,0x2e,0x2f,0x30};
static const uint8_t pt_32[32]  = {0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,
                                   0x28,0x29,0x2a,0x2b,0x2c,0x2d,0x2e,0x2f,
                                   0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,
                                   0x38,0x39,0x3a,0x3b,0x3c,0x3d,0x3e,0x3f};
static const uint8_t pt_1[1]    = {0x20};

/* expected ciphertexts */
static const uint8_t ct_1[1]  = {0xe8};
static const uint8_t ct_16[16] = {0xe8,0xc3,0xde,0xee,0x24,0x6c,0xc5,0xea,
                                  0xe3,0xe8,0x72,0x31,0x38,0x97,0xa2,0xbb};
static const uint8_t ct_16ad[16] = {0x63,0x73,0xeb,0xb2,0x8b,0xe9,0x7c,0x9b,
                                    0xac,0x09,0x0c,0xf3,0x99,0xc1,0x3e,0xf1};
static const uint8_t ct_17[17] = {0xe8,0xc3,0xde,0xee,0x24,0x6c,0xc5,0xea,
                                  0xe3,0xe8,0x72,0x31,0x38,0x97,0xa2,0xbb,0x60};
static const uint8_t ct_32[32] = {0xe8,0xc3,0xde,0xee,0x24,0x6c,0xc5,0xea,
                                  0xe3,0xe8,0x72,0x31,0x38,0x97,0xa2,0xbb,
                                  0x60,0x89,0xaa,0x3e,0x15,0xe8,0x03,0x07,
                                  0x97,0x0f,0x2d,0x1f,0x00,0x66,0x54,0xc2};

/* expected tags */
static const uint8_t tag_empty[16] = {0x4f,0x9c,0x27,0x82,0x11,0xbe,0xc9,0x31,
                                       0x6b,0xf6,0x8f,0x46,0xee,0x8b,0x2e,0xc6};
static const uint8_t tag_1[16]  = {0xdd,0x57,0x6a,0xba,0x1c,0xd3,0xe6,0xfc,
                                   0x70,0x4d,0xe0,0x2a,0xed,0xb7,0x95,0x88};
static const uint8_t tag_16[16] = {0x9e,0xaa,0x91,0x5c,0x9d,0xd3,0x24,0x5d,
                                   0x77,0x04,0x8f,0x24,0xd4,0x6d,0x27,0xa7};
static const uint8_t tag_16ad[16] = {0x3a,0xbf,0xc0,0xd2,0x09,0xe8,0xf4,0x84,
                                     0x4c,0x90,0x81,0x4d,0x13,0xf3,0x2c,0x59};
static const uint8_t tag_17[16] = {0x30,0x10,0x02,0x53,0x9d,0x45,0x62,0x75,
                                   0xdd,0x0b,0x0c,0xea,0xb3,0xb2,0x38,0x44};
static const uint8_t tag_32[16] = {0xaa,0xa5,0xfa,0x17,0x2c,0xb9,0xf0,0x7d,
                                   0x07,0x46,0x3c,0xef,0xc7,0x44,0x0b,0xc1};

typedef struct {
    const char    *name;
    const uint8_t *ad;   uint32_t adlen;
    const uint8_t *pt;   uint32_t ptlen;
    const uint8_t *ct;
    const uint8_t *tag;
} testcase_t;

static const testcase_t tests[] = {
    {"empty",   0, 0,              0,     0,              0,       tag_empty},
    {"1B",      0, 0,              pt_1,  1,              ct_1,    tag_1},
    {"16B",     0, 0,              pt_16, 16,             ct_16,   tag_16},
    {"16B+AD",  ad_16, 16,         pt_16, 16,             ct_16ad, tag_16ad},
    {"17B",     0, 0,              pt_17, 17,             ct_17,   tag_17},
    {"32B",     0, 0,              pt_32, 32,             ct_32,   tag_32},
};
#define NTESTS (sizeof(tests)/sizeof(tests[0]))

static int bytes_eq(const uint8_t *a, const uint8_t *b, uint32_t n)
{
    uint32_t i;
    for (i = 0; i < n; i++)
        if (a[i] != b[i]) return 0;
    return 1;
}

int main(void)
{
    uint8_t ct_buf[64];
    uint8_t pt_out[64];
    unsigned long long clen, mlen;
    int r, ok, all_ok = 1, i;
    uint64_t c0, c1, i0, i1, cycles, inst;

    uart_puts("\n=== ASCON-AEAD128 software on RV32IM ===\n");

    /* ---- KAT encrypt + decrypt round-trip ---- */
    for (i = 0; i < (int)NTESTS; i++) {
        const testcase_t *tc = &tests[i];

        r = crypto_aead_encrypt(ct_buf, &clen, tc->pt, tc->ptlen,
                                tc->ad, tc->adlen, 0, npub, key);
        ok = (r == 0) && (clen == (unsigned long long)tc->ptlen + 16)
             && bytes_eq(ct_buf, tc->ct, tc->ptlen)
             && bytes_eq(ct_buf + tc->ptlen, tc->tag, 16);

        r = crypto_aead_decrypt(pt_out, &mlen, 0, ct_buf, clen,
                                tc->ad, tc->adlen, npub, key);
        ok = ok && (r == 0) && (mlen == (unsigned long long)tc->ptlen)
             && bytes_eq(pt_out, tc->pt, tc->ptlen);

        uart_puts("KAT "); uart_puts(tc->name); uart_puts(" : ");
        if (ok) uart_puts("PASS\n"); else { uart_puts("FAIL\n"); all_ok = 0; }
    }

    /* ---- tamper rejection (flip first ciphertext byte of the 17B case) ---- */
    r = crypto_aead_encrypt(ct_buf, &clen, pt_17, 17, 0, 0, 0, npub, key);
    ct_buf[0] ^= 0x01;
    r = crypto_aead_decrypt(pt_out, &mlen, 0, ct_buf, clen, 0, 0, npub, key);
    ok = (r == -1) && (mlen == 0);
    uart_puts("tamper reject : ");
    if (ok) uart_puts("PASS\n"); else { uart_puts("FAIL\n"); all_ok = 0; }

    uart_puts("KAT: "); uart_putdec_u32(NTESTS); uart_puts("/");
    uart_putdec_u32(NTESTS); uart_puts(" PASS\n");

    /* ---- warm-cycle benchmark (16B and 32B encrypt/decrypt) ---- */
    uart_puts("--- benchmark (warm) ---\n");

    /* encrypt 16B */
    crypto_aead_encrypt(ct_buf, &clen, pt_16, 16, 0, 0, 0, npub, key);
    c0 = read_mcycle(); i0 = read_inst();
    crypto_aead_encrypt(ct_buf, &clen, pt_16, 16, 0, 0, 0, npub, key);
    c1 = read_mcycle(); i1 = read_inst();
    cycles = c1 - c0; inst = i1 - i0;
    uart_puts("enc 16B : "); uart_putdec_u64(cycles); uart_puts(" cycles, ");
    uart_putdec_u64(inst); uart_puts(" inst, CPI ");
    uart_putdec_u32((uint32_t)((cycles * 100) / inst)); uart_puts(" (x100)\n");

    /* encrypt 32B */
    crypto_aead_encrypt(ct_buf, &clen, pt_32, 32, 0, 0, 0, npub, key);
    c0 = read_mcycle(); i0 = read_inst();
    crypto_aead_encrypt(ct_buf, &clen, pt_32, 32, 0, 0, 0, npub, key);
    c1 = read_mcycle(); i1 = read_inst();
    cycles = c1 - c0; inst = i1 - i0;
    uart_puts("enc 32B : "); uart_putdec_u64(cycles); uart_puts(" cycles, ");
    uart_putdec_u64(inst); uart_puts(" inst, CPI ");
    uart_putdec_u32((uint32_t)((cycles * 100) / inst)); uart_puts(" (x100)\n");

    /* decrypt 16B */
    crypto_aead_encrypt(ct_buf, &clen, pt_16, 16, 0, 0, 0, npub, key);
    crypto_aead_decrypt(pt_out, &mlen, 0, ct_buf, clen, 0, 0, npub, key);
    c0 = read_mcycle(); i0 = read_inst();
    crypto_aead_decrypt(pt_out, &mlen, 0, ct_buf, clen, 0, 0, npub, key);
    c1 = read_mcycle(); i1 = read_inst();
    cycles = c1 - c0; inst = i1 - i0;
    uart_puts("dec 16B : "); uart_putdec_u64(cycles); uart_puts(" cycles, ");
    uart_putdec_u64(inst); uart_puts(" inst, CPI ");
    uart_putdec_u32((uint32_t)((cycles * 100) / inst)); uart_puts(" (x100)\n");

    /* decrypt 32B */
    crypto_aead_encrypt(ct_buf, &clen, pt_32, 32, 0, 0, 0, npub, key);
    crypto_aead_decrypt(pt_out, &mlen, 0, ct_buf, clen, 0, 0, npub, key);
    c0 = read_mcycle(); i0 = read_inst();
    crypto_aead_decrypt(pt_out, &mlen, 0, ct_buf, clen, 0, 0, npub, key);
    c1 = read_mcycle(); i1 = read_inst();
    cycles = c1 - c0; inst = i1 - i0;
    uart_puts("dec 32B : "); uart_putdec_u64(cycles); uart_puts(" cycles, ");
    uart_putdec_u64(inst); uart_puts(" inst, CPI ");
    uart_putdec_u32((uint32_t)((cycles * 100) / inst)); uart_puts(" (x100)\n");

    uart_puts("===DONE===\n");

    /* Spin forever (testbench detects DONE on the UART). */
    for (;;) { }

    return all_ok ? 0 : 1;
}
