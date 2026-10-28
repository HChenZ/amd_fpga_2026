/* svc.h —— pynq_svc 固件的公共声明与 MMIO 寄存器表
 *
 * 目标：RV32IM 软核（P0 上板签核同一源集）+ 三个 Ascon 实现：
 *   MODE_SW  = ascon/ascon_c/aead/aead.c 锁定 C 参考实现（与 host golden 完全同源）
 *   MODE_HW  = 0x30000000 ascon_mmio 加速器
 *   MODE_ISE = custom-0 (opcode 0x0B) 置换指令
 */
#ifndef PYNS_SVC_H
#define PYNS_SVC_H

#include <stdint.h>

/* ---- UART MMIO（见 src/rtl/uart_ctrl.v：0x00 STATUS / 0x04 DATA / 0x08 CTRL）---- */
#define UART_STATUS (*(volatile uint32_t *)0x20000000u)
#define UART_DATA   (*(volatile uint32_t *)0x20000004u)
/* STATUS bit0 = TX busy/pending，bit1 = !RX empty */

/* ---- Ascon MMIO 加速器（0x30000000，见 src/rtl/ascon/ascon_mmio.v）---- */
#define ASCON_BASE   0x30000000u
#define ASCON_REG(o) (*(volatile uint32_t *)(ASCON_BASE + (o)))
#define ASCON_CTRL       ASCON_REG(0x00)
#define ASCON_STATUS     ASCON_REG(0x04)
#define ASCON_ADLEN      ASCON_REG(0x08)
#define ASCON_MLEN       ASCON_REG(0x0C)
#define ASCON_KEY0       ASCON_REG(0x10)
#define ASCON_NONCE0     ASCON_REG(0x20)
#define ASCON_TAGIN0     ASCON_REG(0x30)
#define ASCON_AD_WDATA   ASCON_REG(0x40)
#define ASCON_MSG_WDATA  ASCON_REG(0x44)
#define ASCON_OUT_RDATA  ASCON_REG(0x48)
#define ASCON_TAGOUT0    ASCON_REG(0x4C)

#define ASCON_ST_BUSY 0x1u
#define ASCON_ST_DONE 0x2u
#define ASCON_ST_FAIL 0x4u

/* ---- 模式编号：与 src/pynq/mailbox_protocol.py 的 Mode 枚举一致 ---- */
#define MODE_SW  1
#define MODE_HW  2
#define MODE_ISE 3

/* ---- 固件标识（会出现在 Y01S 服务帧里，host profile 的 firmware_id 必须相同）---- */
#define FW_ID_STR "pynq-svc-v1"

/* ---- 能力上限：三种模式共用 16B（与 P0 MMIO KAT 口径一致，超限显式拒绝）---- */
#define MAX_MSG_BYTES 16u
#define MAX_AD_BYTES  16u

/* ---- 协议常量（与 mailbox_protocol.py 一致）---- */
#define PROTO_VERSION 1u
#define OP_ENCRYPT 1u
#define OP_DECRYPT 2u

#define ST_OK          0u
#define ST_AUTH_FAILED 1u
#define ST_LENGTH      2u
#define ST_UNSUPPORTED 3u
#define ST_INTERNAL    4u

#define REQ_HEADER_BYTES 48u
#define RSP_HEADER_BYTES 48u
#define SVC_FRAME_BYTES  64u
#define EPOCH_FRAME_BYTES 20u

/* ---- 串口阻塞 I/O（svc_io.c）---- */
uint8_t svc_getc(void);
void    svc_putc(uint8_t c);
void    svc_puts(const char *s);
void    svc_puthex32(uint32_t v);
void    svc_putdec(uint64_t v);

/* ---- 计数器 ---- */
static inline uint32_t rd_csr(uint32_t csr)
{
    uint32_t v;
    __asm__ volatile ("csrr %0, %1" : "=r"(v) : "i"(csr));
    return v;
}

/* 64-bit mcycle：hi-lo-hi 一致读取（csr_file.v 的 mcycle 是周期来源） */
static inline uint64_t svc_mcycle(void)
{
    uint32_t hi, lo, hi2;
    do {
        hi = rd_csr(0xB80); lo = rd_csr(0xB00); hi2 = rd_csr(0xB80);
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}

/* ---- 三种模式（ascon_modes.c）----
 * 成功返回 0；解密认证失败返回 -1；其它错误返回 -2。
 * 长度上限由调用方检查，这里不再截断。
 */
int svc_aead_encrypt(uint32_t mode, uint8_t *ct, uint8_t *tag,
                     const uint8_t *m, uint32_t mlen,
                     const uint8_t *ad, uint32_t adlen,
                     const uint8_t *npub, const uint8_t *k);

int svc_aead_decrypt(uint32_t mode, uint8_t *m, uint32_t *mlen,
                     const uint8_t *c, uint32_t clen,
                     const uint8_t *ad, uint32_t adlen,
                     const uint8_t *npub, const uint8_t *k,
                     const uint8_t *tag);

uint32_t svc_selftest(uint32_t *mask_out, uint64_t *cycles_out);

#endif /* PYNS_SVC_H */
