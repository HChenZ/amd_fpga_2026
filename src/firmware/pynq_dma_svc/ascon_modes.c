/* Controlled reuse: upstream helpers already implement SW/ISE multi-block
 * loops and 48-byte SW buffers. DMA main enforces 32B SW/ISE and 16B HW.
 * Production UART protocol constants and code remain untouched. */
#define svc_aead_encrypt dma_reused_encrypt
#define svc_aead_decrypt dma_reused_decrypt
#include "../pynq_svc/ascon_modes.c"
#undef svc_aead_encrypt
#undef svc_aead_decrypt

/* Preserve explicit HW timeout versus authentication failure. The legacy UART
 * helper maps both to -1; this variant must not report a hung engine as auth. */
static int dma_hw(int encrypt, uint8_t *out, uint8_t *tagout,
                  const uint8_t *in, uint32_t n, const uint8_t *ad, uint32_t an,
                  const uint8_t *nonce, const uint8_t *key, const uint8_t *tagin)
{
    uint32_t st, i, j, w;
    uint64_t start;
    if (ASCON_STATUS & ASCON_ST_BUSY) return -2;
    hw_start(encrypt, an, n, key, nonce, tagin, ad, in);
    start=svc_mcycle();
    do {
        st=ASCON_STATUS;
        if (svc_mcycle()-start >= 10000000ull) return -2;
    } while (!(st & ASCON_ST_DONE));
    if (st & ASCON_ST_FAIL) { wipe(out,n); return encrypt ? -2 : -1; }
    for(i=0;i<(n+3)/4;i++) {
        w=ASCON_OUT_RDATA;
        for(j=0;j<4 && 4*i+j<n;j++) out[4*i+j]=(uint8_t)(w>>(8*j));
    }
    if(encrypt) hw_read128(&ASCON_TAGOUT0,tagout);
    return 0;
}

int svc_aead_encrypt(uint32_t mode, uint8_t *ct, uint8_t *tag,
                     const uint8_t *m, uint32_t n, const uint8_t *ad, uint32_t an,
                     const uint8_t *nonce, const uint8_t *key)
{
    if(n>(mode==MODE_HW?16u:32u) || an>(mode==MODE_HW?16u:32u)) return -2;
    if(mode==MODE_HW) return dma_hw(1,ct,tag,m,n,ad,an,nonce,key,0);
    return dma_reused_encrypt(mode,ct,tag,m,n,ad,an,nonce,key);
}

int svc_aead_decrypt(uint32_t mode, uint8_t *m, uint32_t *n_out,
                     const uint8_t *ct, uint32_t n, const uint8_t *ad, uint32_t an,
                     const uint8_t *nonce, const uint8_t *key, const uint8_t *tag)
{
    int rc;
    *n_out=0;
    if(n>(mode==MODE_HW?16u:32u) || an>(mode==MODE_HW?16u:32u)) return -2;
    if(mode!=MODE_HW) return dma_reused_decrypt(mode,m,n_out,ct,n,ad,an,nonce,key,tag);
    rc=dma_hw(0,m,0,ct,n,ad,an,nonce,key,tag);
    if(!rc) *n_out=n;
    return rc;
}
