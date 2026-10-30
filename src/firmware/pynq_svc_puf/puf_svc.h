/* puf_svc.h —— pynq_svc_puf：PUF v1 密钥子系统服务（Y01P 请求 / Y01K 响应）
 *
 * 寄存器：Ascon 窗口 0x3000_0000 内的 0x80 段（board/vivado_zynq7000_xc7z020_pynq_puf3/rtl/key_mmio.v）
 *   STATUS 0x80: [0]busy [1]key_ready [2]enrolled [3]mismatch [4]fallback [5]done
 *                [6]key_hw_sel [7]hwkey_on [15:8]quality
 *   CTRL   0x84: [0]START [1]ENROLL [2]CLEAR [3]HWKEY_ON [4]HWKEY_OFF
 *
 * Y01P（PS -> RV32，16B）：magic | u32 version | u32 cmd | u32 seq
 * Y01K（RV32 -> PS，112B）：见 puf_svc.c 的 send_puf_frame()（末 8B 为发帧时刻 mcycle）
 */
#ifndef PUF_SVC_H
#define PUF_SVC_H

#include <stdint.h>

#define KEY_REG(o)   (*(volatile uint32_t *)(0x30000000u + (o)))
#define KEY_STATUS   KEY_REG(0x80)
#define KEY_CTRL     KEY_REG(0x84)
#define KEY_DNA_LO   0x88u
#define KEY_DNA_HI   0x8Cu
#define KEY_REF0     0x94u
#define KEY_MASK0    0xA4u
#define KEY_DITH0    0xB4u
#define KEY_RAW0     0xC4u

#define KST_BUSY      (1u << 0)
#define KST_READY     (1u << 1)
#define KST_ENROLLED  (1u << 2)
#define KST_MISMATCH  (1u << 3)
#define KST_FALLBACK  (1u << 4)
#define KST_DONE      (1u << 5)
#define KST_HWSEL     (1u << 6)
#define KST_HWKEY_ON  (1u << 7)

#define KCTRL_START     0x01u
#define KCTRL_ENROLL    0x02u
#define KCTRL_CLEAR     0x04u
#define KCTRL_HWKEY_ON  0x08u
#define KCTRL_HWKEY_OFF 0x10u

#define PUF_REQ_BYTES  16u
#define PUF_RSP_BYTES  112u

#define PUF_CMD_STATUS      0u
#define PUF_CMD_ENROLL      1u
#define PUF_CMD_RECONSTRUCT 2u
#define PUF_CMD_HWKEY_ON    3u
#define PUF_CMD_HWKEY_OFF   4u

#define PUF_OK            0u
#define PUF_TIMEOUT       1u
#define PUF_NOT_ACCEPTED  2u
#define PUF_BAD_CMD       3u
#define PUF_BAD_VERSION   4u
#define PUF_NO_PUF_KEY    5u
#define PUF_BUSY_STUCK    6u

/* 魔数 "Y01P" 已被帧同步读走；本函数读剩余 12B、执行并回 Y01K */
void puf_handle_request(void);
/* 自检/epoch 前调用：保证 HW 模式用调用方的 key */
void puf_hwkey_off(void);

#endif /* PUF_SVC_H */
