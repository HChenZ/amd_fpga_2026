#ifndef PUF_MMIO_V2_H
#define PUF_MMIO_V2_H
#include <stdint.h>
#ifndef PUF_V2_BASE
#define PUF_V2_BASE 0x30010000u /* independent test/SoC-integration assignment */
#endif
enum { PV_ID=0x00, PV_CTRL=0x04, PV_STATUS=0x08, PV_ERROR=0x0c,
       PV_IDSEQ=0x10, PV_LENGTH=0x20, PV_DATA=0x30, PV_AD=0x40,
       PV_NONCE=0x50, PV_TAG=0x60, PV_REF=0x70, PV_MASK=0x80,
       PV_VERSION=0xa0, PV_TARGET=0xa4, PV_EXPECT_VERSION=0xa8,
       PV_EXPECT_TARGET=0xac, PV_OUT=0xb0, PV_OUT_TAG=0xc0,
       PV_EXPORT_REF=0xd0, PV_EXPORT_MASK=0xe0 };
enum { PV_ENROLL=1, PV_RECONSTRUCT=2, PV_LOAD=3, PV_ENCRYPT=4,
       PV_DECRYPT=5, PV_IMAGE_VERIFY=6, PV_CLEAR=7 };
static inline uint32_t pv_read(unsigned off) {
    uint32_t v = *(volatile uint32_t *)(uintptr_t)(PUF_V2_BASE+off);
    __asm__ volatile ("fence iorw, iorw" ::: "memory"); return v;
}
static inline void pv_write(unsigned off, uint32_t v) {
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    *(volatile uint32_t *)(uintptr_t)(PUF_V2_BASE+off)=v;
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
}
int pv_command(unsigned command, uint32_t budget);
#endif
