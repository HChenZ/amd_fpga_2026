/* DMA ABI v2 service. CPU SW/ISE 32B; original MMIO HW 16B. */
#include "../pynq_svc/svc.h"
#define REG(o) (*(volatile uint32_t *)(0x20020000u + (o)))
static uint32_t rx_words[40], tx_words[24];
static uint64_t last_id;

static uint32_t u32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1]<<8) | ((uint32_t)p[2]<<16) | ((uint32_t)p[3]<<24);
}
static uint64_t u64(const uint8_t *p) { return u32(p) | ((uint64_t)u32(p+4)<<32); }
static void p32(uint8_t *p, uint32_t v) { unsigned i; for(i=0;i<4;i++) p[i]=(uint8_t)(v>>(i*8)); }
static void p64(uint8_t *p, uint64_t v) { p32(p,(uint32_t)v); p32(p+4,(uint32_t)(v>>32)); }
static void clear(void *p, uint32_t n) { volatile uint8_t *q=p; while(n--) *q++=0; }

static void process(void) {
    uint8_t *r=(uint8_t *)rx_words, *t=(uint8_t *)tx_words;
    uint32_t n=REG(4), i, status=0, op=0, mode=0, alen=0, dlen=0, cap=0, taglen=0, plen=0;
    uint64_t epoch=0, id=0, cycles=0, start, actual_epoch;
    int rc;
    clear(rx_words,sizeof(rx_words)); clear(tx_words,sizeof(tx_words));
    for(i=0;i<(n+3)/4 && i<40;i++) rx_words[i]=REG(8);
    actual_epoch=(uint64_t)REG(0x18) | ((uint64_t)REG(0x1c)<<32);
    if(n>=48) {
        epoch=u64(r+8); id=u64(r+16); op=u32(r+24); mode=u32(r+28);
        alen=u32(r+32); dlen=u32(r+36); cap=u32(r+40); taglen=u32(r+44);
    }
    if(n<48 || u32(r)!=0x51313044u || u32(r+4)!=2) status=5;
    else if(!epoch || epoch!=actual_epoch || !id || id<=last_id) status=6;
    else {
        last_id=id;
        if((op!=1 && op!=2) || mode<1 || mode>3) status=3;
        else if(alen>(mode==2?16u:32u) || dlen>(mode==2?16u:32u) ||
                taglen!=(op==2?16u:0u) || cap<dlen+(op==1?16u:0u)) status=2;
        else if(n!=80+alen+dlen+taglen) status=5;
    }
    if(!status) {
        const uint8_t *key=r+48, *nonce=r+64, *ad=r+80, *input=ad+alen;
        start=svc_mcycle();
        if(op==1) {
            rc=svc_aead_encrypt(mode,t+48,t+48+dlen,input,dlen,ad,alen,nonce,key);
            if(!rc) plen=dlen+16;
        } else {
            rc=svc_aead_decrypt(mode,t+48,&plen,input,dlen,ad,alen,nonce,key,input+dlen);
        }
        cycles=svc_mcycle()-start;
        if(rc) { status=(rc==-1 && op==2)?1:4; plen=0; cycles=0; clear(t+48,48); }
        if(mode==2) {
            /* A stuck HW engine cannot safely accept another request. Invalid
             * endpoint store latches transport fault and resets this CPU. */
            if (ASCON_STATUS & ASCON_ST_BUSY) REG(0x20)=1;
            ASCON_CTRL=4; /* idle ZEROIZE after completion */
        }
    }
    p32(t,0x52313044u); p32(t+4,status?2u:0x10002u);
    p64(t+8,epoch); p64(t+16,id); p32(t+24,status); p32(t+28,op); p32(t+32,mode);
    p32(t+36,plen); p64(t+40,cycles);
    clear(rx_words,sizeof(rx_words));
    for(i=0;i<(48+plen+3)/4;i++) REG(0x0c)=tx_words[i];
    REG(0x10)=48+plen;
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    REG(0x14)=1;
    clear(tx_words,sizeof(tx_words));
}

int main(void) {
    last_id=0;
    for(;;) if(REG(0)&1) process();
}
