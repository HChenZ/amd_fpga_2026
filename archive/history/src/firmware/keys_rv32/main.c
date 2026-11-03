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

/* 硬件 keygen 一次约 13 ms@100MHz（WINDOW=65536,M=5，5 个窗口 + 起振/结算）。
 * 板上实测上电自动 reconstruct + enroll + reconstruct 三次共约 40 ms。 */
#define TIMEOUT_LOOPS 800000u   /* 单次操作完成上限，给 ~6 倍余量 */
#define TIMEOUT_IDLE  400000u   /* 等 busy 落下（上电自动 reconstruct 也要等） */

static void nl(void) { uart_putc('\n'); }

static void put_label(const char *s) { uart_puts(s); }

/* 打印 STATUS 并逐字段解释：busy=1 说明操作已进入但没走完；busy=0 且 done=0
 * 说明 START 根本没被接受（这一版已改成排队，理论上不应再出现）。 */
static void show_status(const char *tag)
{
    uint32_t st = REG(R_STATUS);
    put_label(tag);
    uart_puthex32(st);
    uart_puts(" busy=");     uart_putdec_u32(st & 1u);
    uart_puts(" enrolled="); uart_putdec_u32((st >> 2) & 1u);
    uart_puts(" done=");     uart_putdec_u32((st >> 5) & 1u);
    uart_puts(" quality=");  uart_putdec_u32((st >> 8) & 0xFFu);
    nl();
}

/* 短暂延时：CLEAR 与下一次 START 之间留出空拍，避免同拍覆盖 */
static void settle_delay(void)
{
    volatile uint32_t d;
    for (d = 0; d < 2000u; d++) { }
}

/* 等器件空闲：上电后 soc_top 会自动发一次 reconstruct，此刻 busy=1。
 * 不等它落下就发 START，自己的操作会和它撞车，wait_done 抓到的是它的 done
 * —— 板上第一次新版固件就是这样把 enroll 读成 quality=0 的。 */
static int wait_idle(void)
{
    uint32_t n = TIMEOUT_IDLE;
    while (n--) { if (!(REG(R_STATUS) & ST_BUSY)) return 0; }
    return -1;
}

/* CLEAR→START，并确认这次 START 真的被受理（busy 拉高，或操作已极快完成） */
static int start_op(uint32_t mode_bit)
{
    uint32_t n = TIMEOUT_LOOPS;
    settle_delay();
    REG(R_CTRL) = 0x4;                 /* 清 done/mismatch/fallback 粘滞位 */
    REG(R_CTRL) = 0x1u | mode_bit;     /* START [+ENROLL] */
    while (n--) {
        uint32_t st = REG(R_STATUS);
        if ((st & ST_BUSY) || (st & ST_DONE)) return 0;
    }
    return -1;
}

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

    /* 1. 上电状态（只记录，不作为判定依据） */
    show_status("STATUS boot   : ");

    /* 1b. 必须等上电自动 reconstruct 收尾，否则自己的 START 会和它撞车 */
    if (wait_idle()) {
        show_status("STATUS idle   : ");
        uart_puts("FAIL boot op stuck (busy never cleared)\nDONE\n");
        return 1;
    }
    show_status("STATUS idle   : ");

    /* 2. enroll */
    if (start_op(0x2u)) {
        show_status("STATUS at enr : ");
        uart_puts("FAIL enroll start not accepted\nDONE\n");
        return 1;
    }
    if (wait_done()) {
        show_status("STATUS at enr : ");
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

    /* REF 全 0 说明比对器系统性偏一边（128 位全落在同一侧），功能上仍能匹配，
     * 但熵为零，必须记录；这是 PUF 质量问题的直接证据。 */
    if ((REG(R_REF0) | REG(R_REF0 + 4) | REG(R_REF0 + 8) | REG(R_REF0 + 12)) == 0u) {
        uart_puts("WARN ref==0 (comparator biased, no entropy)\n");
    }

    /* 3. reconstruct（超时则重试一次） */
    if (wait_idle()) {
        show_status("STATUS at rec : ");
        uart_puts("FAIL busy stuck after enroll\nDONE\n");
        return 1;
    }
    if (start_op(0x0u)) {
        show_status("STATUS at rec : ");
        uart_puts("FAIL reconstruct start not accepted\nDONE\n");
        return 1;
    }
    if (wait_done()) {
        show_status("STATUS at rec : ");
        uart_puts("RETRY reconstruct\n");
        if (start_op(0x0u) || wait_done()) {
            show_status("STATUS retry  : ");
            uart_puts("FAIL reconstruct timeout\nDONE\n");
            return 1;
        }
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
