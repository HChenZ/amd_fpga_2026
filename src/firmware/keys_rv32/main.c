/* 密钥子系统自检固件（RO-PUF + Device DNA → Ascon KDF）
 *
 * 流程：
 *   1. 打印上电时 STATUS（puf_key 在上电 ~0xFFFF 拍后自动尝试一次 reconstruct；
 *      若 helper 还没烧进去，这里会看到 mismatch+fallback，属预期）
 *   2. CTRL = 0x3（START + ENROLL）→ 轮询 STATUS[5] (done)
 *   3. 打印 quality / DNA / REF / MASK / DITHER / RAW
 *      —— REF/MASK 要回填到顶层参数 KEY_INIT_REF / KEY_INIT_MASK
 *   4. CTRL = 0x4（清粘滞）→ CTRL = 0x1（START，reconstruct）→ 轮询 done
 *   5. 判定 mismatch/fallback 均为 0 才 PASS（key 本身不可读，一致性由硬件比对保证）
 *
 * MMIO（Ascon 窗口 0x3000_0000 内的 0x80 段，详见 docs/key_subsystem.md §3.4）
 */
#include <stdint.h>
#include "uart.h"

#define KEY_BASE  0x30000000u
#define REG(o)    (*(volatile uint32_t *)(KEY_BASE + (o)))

#define R_STATUS  0x80
#define R_CTRL    0x84
#define R_DNA_LO  0x88
#define R_DNA_HI  0x8C
#define R_QUAL    0x90
#define R_REF0    0x94
#define R_MASK0   0xA4
#define R_DITH0   0xB4
#define R_RAW0    0xC4

#define ST_BUSY      (1u << 0)
#define ST_READY     (1u << 1)
#define ST_ENROLLED  (1u << 2)
#define ST_MISMATCH  (1u << 3)
#define ST_FALLBACK  (1u << 4)
#define ST_DONE      (1u << 5)

/* 硬件 keygen 一次约 3.3 ms@100MHz(WINDOW=16384,M=5)；这里给 ~8 ms 的余量。
 * 仿真里 KEY_WINDOW 被调小，这个循环会立刻返回。 */
#define TIMEOUT_LOOPS 200000u

static void nl(void) { uart_putc('\n'); }

static void put_label(const char *s) { uart_puts(s); }

/* 等 done；返回 0 成功，-1 超时 */
static int wait_done(void)
{
    uint32_t n = TIMEOUT_LOOPS;
    while (n--) {
        if (REG(R_STATUS) & ST_DONE)
            return 0;
    }
    return -1;
}

static void dump4(const char *name, uint32_t off)
{
    put_label(name);
    uart_puthex32(REG(off + 0x0)); uart_putc(' ');
    uart_puthex32(REG(off + 0x4)); uart_putc(' ');
    uart_puthex32(REG(off + 0x8)); uart_putc(' ');
    uart_puthex32(REG(off + 0xC)); nl();
}

int main(void)
{
    uint32_t st;
    int failed = 0;

    uart_puts("=== KEY SUBSYSTEM SELF-TEST ===\n");

    /* 1. 上电状态（不以此为判定依据） */
    st = REG(R_STATUS);
    put_label("STATUS boot : ");
    uart_puthex32(st);
    nl();

    /* 2. enroll */
    REG(R_CTRL) = 0x4;             /* 清粘滞 */
    REG(R_CTRL) = 0x3;             /* START + ENROLL */
    if (wait_done()) {
        uart_puts("FAIL enroll timeout\nDONE\n");
        return 1;
    }
    st = REG(R_STATUS);
    put_label("STATUS enrol: ");
    uart_puthex32(st);
    put_label(" quality=");
    uart_putdec_u32((st >> 8) & 0xFF);
    nl();
    if (!(st & ST_ENROLLED)) { uart_puts("FAIL enroll not marked\n"); failed = 1; }
    if (((st >> 8) & 0xFF) == 0) { uart_puts("FAIL quality=0\n"); failed = 1; }

    put_label("DNA         : ");
    uart_puthex32(REG(R_DNA_HI) & 0x1FFFFFFu);
    uart_puthex32(REG(R_DNA_LO));
    nl();
    dump4("REF         : ", R_REF0);
    dump4("MASK        : ", R_MASK0);
    dump4("DITHER      : ", R_DITH0);
    dump4("RAW         : ", R_RAW0);

    /* 3. reconstruct */
    REG(R_CTRL) = 0x4;             /* 清粘滞 */
    REG(R_CTRL) = 0x1;             /* START，reconstruct */
    if (wait_done()) {
        uart_puts("FAIL reconstruct timeout\nDONE\n");
        return 1;
    }
    st = REG(R_STATUS);
    put_label("STATUS recon: ");
    uart_puthex32(st);
    nl();
    if (!(st & ST_READY))    { uart_puts("FAIL key not ready\n"); failed = 1; }
    if (st & ST_MISMATCH)    { uart_puts("FAIL puf mismatch (fallback used)\n"); failed = 1; }
    if (st & ST_FALLBACK)    { uart_puts("FAIL dna-only fallback\n"); failed = 1; }

    if (failed == 0) {
        uart_puts("PASS key subsystem: enroll + reconstruct stable\n");
        uart_puts("DONE\n");
        return 0;
    }
    uart_puts("FAIL\n");
    return 1;
}
