/* Test the actual firmware entry points, never a crypto replacement. */
#define main original_kat_main
#if defined(TEST_SW)
#include "../../src/firmware/ascon_rv32/main.c"
#elif defined(TEST_HW)
#include "../../src/firmware/ascon_hw_rv32/main.c"
#else
#include "../../src/firmware/ascon_ise_rv32/main.c"
#endif
#undef main
#include "key_cases.h"

static int equal_bytes(const uint8_t *a, const uint8_t *b, unsigned n) {
    unsigned i; for(i=0;i<n;i++) if(a[i]!=b[i]) return 0; return 1;
}
int main(void) {
    uint8_t out[64], ct[64], k[16], zero[64]={0};
    unsigned t, i, bad, n, an, passed=0, failed=0;
    int rc;
    unsigned long long olen;
    uart_puts("KEY lifecycle tests\n");
    for(t=0;t<sizeof(key_cases)/sizeof(key_cases[0]);t++) {
        n=key_cases[t].n; an=key_cases[t].an;
#ifdef TEST_HW
        if(n>16 || an>16) continue;
#endif
        for(i=0;i<16;i++) k[i]=key_cases[t].k[i];
#ifdef TEST_SW
        crypto_aead_encrypt(ct,&olen,key_cases[t].m,n,key_cases[t].ad,an,0,key_cases[t].nonce,k);
#elif defined(TEST_HW)
        ascon_hw_start(1,an,n,k,key_cases[t].nonce,0,key_cases[t].ad,key_cases[t].m);
        rc=ascon_hw_poll(); ascon_hw_read_out(ct,n); rd128(&ASCON_TAGOUT0,ct+n);
        if(rc) failed++;
#else
        ascon_encrypt(ct,ct+n,key_cases[t].m,n,key_cases[t].ad,an,key_cases[t].nonce,k);
#endif
        if(equal_bytes(ct,key_cases[t].expected,n+16)) passed++; else failed++;
        for(bad=0;bad<4;bad++) {
            for(i=0;i<n+16;i++) ct[i]=key_cases[t].expected[i];
            for(i=0;i<64;i++) out[i]=0xa5;
            if(bad==1) k[0]^=1;
            if(bad==2) ct[n+15]^=1;
            if(bad==3) { if(!n) continue; ct[0]^=1; }
            olen=99;
#ifdef TEST_SW
            rc=crypto_aead_decrypt(out+1,&olen,0,ct,n+16,key_cases[t].ad,an,key_cases[t].nonce,k);
#elif defined(TEST_HW)
            ascon_hw_start(0,an,n,k,key_cases[t].nonce,ct+n,key_cases[t].ad,ct);
            rc=ascon_hw_poll(); ascon_hw_read_out(out+1,n); olen=rc?0:n;
#else
#ifdef KEY_AUDIT_LEGACY
            rc=ascon_decrypt(out+1,ct,n,key_cases[t].ad,an,key_cases[t].nonce,k);
            olen=rc?0:n;
#else
            uint32_t ml=99;
            rc=ascon_decrypt(out+1,ct,n,key_cases[t].ad,an,key_cases[t].nonce,k,&ml);
            olen=ml;
#endif
#endif
            if(bad==1) k[0]^=1;
            if((bad ? (rc!=0 && olen==0 && equal_bytes(out+1,zero,n)) :
                       (rc==0 && olen==n && equal_bytes(out+1,key_cases[t].m,n))) &&
               out[0]==0xa5 && out[n+1]==0xa5) passed++; else failed++;
        }
#if defined(TEST_ISE) && !defined(KEY_AUDIT_LEGACY)
        for(i=0;i<10;i++) { if(ascon_rd(i)==0) passed++; else failed++; }
#elif defined(TEST_HW) && !defined(KEY_AUDIT_LEGACY)
        ASCON_CTRL=4; /* ZEROIZE; read status serializes MMIO */
        if(ASCON_STATUS==0 && ASCON_OUT_RDATA==0 && ASCON_KEY0==0) passed++; else failed++;
#endif
    }
    uart_puts("checks PASS="); uart_putdec_u64(passed);
    uart_puts(" failed="); uart_putdec_u64(failed);
    uart_puts(failed ? "\nFAIL\n" : "\nPASS\n");
    uart_puts("===DONE===\n"); for(;;) {}
}
