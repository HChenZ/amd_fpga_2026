# PUF3 固件与保留的共享依赖

| 目录 | 当前用途 |
|---|---|
| pynq_svc_puf | 主固件main/puf_svc与build.py，身份pynq-svc-puf3 |
| pynq_svc | 共享svc_io/ascon_modes/svc.h/bin2coe；不使用其旧main/build.sh作为当前服务 |
| ascon_hw_rv32 | 共享crt0/libc_min/riscv.ld/bin2vhex；其单镜像自测main为旧兼容文件 |

旧ascon_rv32/ascon_ise_rv32/keys与DMA固件已隔离到archive/history/src/firmware。
共享头文件的旧FW_ID由PUF3 main显式覆写；不通过全局替换ID改变程序。
COE随bitstream初始化BRAM，单独重编译ELF/BIN不会更新已发布bit。
