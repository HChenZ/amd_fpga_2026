#include "puf_mmio_v2.h"
int pv_command(unsigned command, uint32_t budget) {
    uint32_t expected, s;
    if (!budget || command<1 || command>7) return -3;
    if ((pv_read(PV_STATUS)&1) && command!=PV_CLEAR) return -3;
    expected=pv_read(PV_IDSEQ)+1u;
    pv_write(PV_CTRL,command);
    while(budget--) {
        s=pv_read(PV_STATUS);
        if(pv_read(PV_IDSEQ)!=expected) continue;
        if(!(s&1) && (s&4)) return ((s&8) && !(pv_read(PV_ERROR)&255))?0:-1;
    }
    pv_write(PV_CTRL,PV_CLEAR);
    return -2;
}
