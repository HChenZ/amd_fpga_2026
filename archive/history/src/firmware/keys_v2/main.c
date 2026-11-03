#include "puf_mmio_v2.h"
#include "uart.h"
#define BUDGET 200000u
volatile uint32_t puf_v2_selftest_result;
static int fail(unsigned phase) {
    puf_v2_selftest_result=0xbad00000u|phase;
    uart_puts("PUF_V2_FAIL "); uart_puthex32(phase); uart_puts("\n");
    pv_write(PV_CTRL,PV_CLEAR); return 1;
}
int main(void) {
    uint32_t ct[4],tag[4],ref[4],mask[4],s,n;
    unsigned i;
    uart_puts("PUF_V2_OFFLINE_SELFTEST\n");
    if(pv_read(PV_ID)!=0x50550202u) return fail(1);
    for(n=0;n<BUDGET && !(pv_read(PV_STATUS)&16);++n) {}
    if(n==BUDGET) return fail(2);
    if(pv_command(PV_RECONSTRUCT,BUDGET)!=-1) return fail(3);
    if(pv_command(PV_ENROLL,BUDGET)) return fail(4);
    s=pv_read(PV_STATUS);
    if(!(s&2)) return fail(5);
    /* Explicitly diagnostic builds only; no helper/key reads in normal mode. */
    if(s&32) {
        for(i=0;i<4;++i) { ref[i]=pv_read(PV_EXPORT_REF+4*i); mask[i]=pv_read(PV_EXPORT_MASK+4*i); }
        if(pv_command(PV_CLEAR,BUDGET)) return fail(6);
        for(i=0;i<4;++i) { pv_write(PV_REF+4*i,ref[i]); pv_write(PV_MASK+4*i,mask[i]); }
        if(pv_command(PV_LOAD,BUDGET) || pv_command(PV_RECONSTRUCT,BUDGET)) return fail(7);
    }
    pv_write(PV_LENGTH,0x1010);
    for(i=0;i<4;++i) {
        pv_write(PV_DATA+4*i,0x12345670u+i); pv_write(PV_NONCE+4*i,0x11223300u+i);
    }
    /* Authenticated image metadata: version, length, destination, domain magic. */
    pv_write(PV_AD,7); pv_write(PV_AD+4,16); pv_write(PV_AD+8,0x10001000);
    pv_write(PV_AD+12,0x32474d49);
    if(pv_command(PV_ENCRYPT,BUDGET)) return fail(8);
    for(i=0;i<4;++i) { ct[i]=pv_read(PV_OUT+4*i); tag[i]=pv_read(PV_OUT_TAG+4*i); }
    if(pv_command(PV_RECONSTRUCT,BUDGET) || pv_command(PV_ENCRYPT,BUDGET)) return fail(9);
    for(i=0;i<4;++i)
        if(ct[i]!=pv_read(PV_OUT+4*i) || tag[i]!=pv_read(PV_OUT_TAG+4*i)) return fail(10);
    for(i=0;i<4;++i) { pv_write(PV_DATA+4*i,ct[i]); pv_write(PV_TAG+4*i,tag[i]); }
    if(pv_command(PV_DECRYPT,BUDGET)) return fail(11);
    for(i=0;i<4;++i) if(pv_read(PV_OUT+4*i)!=0x12345670u+i) return fail(12);
    pv_write(PV_TAG,tag[0]^1);
    if(pv_command(PV_DECRYPT,BUDGET)!=-1) return fail(13);
    for(i=0;i<4;++i) if(pv_read(PV_OUT+4*i) || pv_read(PV_OUT_TAG+4*i)) return fail(14);
    pv_write(PV_TAG,tag[0]); pv_write(PV_VERSION,7); pv_write(PV_EXPECT_VERSION,7);
    pv_write(PV_TARGET,0x10001000); pv_write(PV_EXPECT_TARGET,0x10001000);
    if(pv_command(PV_IMAGE_VERIFY,BUDGET) || !(pv_read(PV_STATUS)&64)) return fail(15);
    pv_write(PV_VERSION,8); pv_write(PV_EXPECT_VERSION,8);
    if(pv_command(PV_IMAGE_VERIFY,BUDGET)!=-1 || (pv_read(PV_STATUS)&64)) return fail(16);
    pv_write(PV_LENGTH,0x1020);
    if(pv_command(PV_ENCRYPT,BUDGET)!=-1) return fail(17);
    if(pv_command(PV_CLEAR,BUDGET) || (pv_read(PV_STATUS)&2)) return fail(18);
    puf_v2_selftest_result=0x600d0002;
    uart_puts("PUF_V2_TEST_PASS\n");
    return 0;
}
