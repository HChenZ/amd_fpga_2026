## Q1
DMASR bit4 DMAIntErr：S2MM 申请长度小于 PL 实际包长（TLAST 来得晚）。打印请求长度与包长确认。

## Q2
PL 未发 TLAST，S2MM 永不完成；PYNQ 的 wait() 是无超时自旋。改为带 deadline 的轮询并解码 DMASR。

## Q3
缺少 invalidate：CPU 缓存里是旧数据，m_axi 写 DDR 与缓存不一致。完成后调用 buf.invalidate()。

## Q4
PYNQ 使用与 bit 同名的 hwh，目录里的 design_v2.hwh 是旧的、与新 bit 不匹配，ip_dict 地址错误。用哈希核对。

## Q5
fclk 读回值按 PS 参考时钟假设推算；hwh 晶振 33.333 MHz 而 PYNQ 假设 50 MHz，导致 1.5 倍偏差。

## Q6
ap_done 是 clear-on-read（COR），调试打印那次读取已经把 done 清掉了。一次读取保存全部位。

## Q7
写入的是虚拟地址而不是物理地址；应使用 buffer.physical_address。

## Q8
64 位地址只写了低 32 位，高位寄存器（0x14 等 _hi）残留旧值；两个都要写。
