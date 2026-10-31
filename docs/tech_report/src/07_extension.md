## 7 扩展原型：RO-PUF 与器件绑定密钥通路

本章保留已实现的进阶探索，范围为独立 PL-only 扩展原型，不属于当前 PYNQ release。
其成果是 RO 采样、注册、重建判定、派生和内部接线的功能链，不宣称已经完成产品级硬件信任根或安全启动。

### 7.1 架构与已实现代码

`src/rtl/keys/` 包含 device_dna、ro_unit、ro_puf_core、puf_key 和 key_mmio。
256 路 RO 经计数、两两比较及多次表决产生 128-bit 响应；注册保存参考响应与掩码，
重建将当前响应的掩码位与参考比较。Device DNA 提供 57-bit 器件标识，不是秘密熵源。

派生通路将固定上下文、响应及 DNA 组成 320-bit 状态，执行 P12 后取低 128 bit 作为 key。
这是项目自定义的置换派生原型，不是 NIST SP 800-232 对该 KDF 构造的认证或安全证明。
key 寄存器本身没有 CPU 读地址，内部连接至扩展版 ascon_mmio；当前 PYNQ 的调用者 key 路径与此不同。
采样窗口由构建参数决定，不使用旧稿的 3.3 ms 估算作为板级实测延迟。

> <span class="figslot">图 2-8</span> **独立扩展原型结构**：RO 阵列、计数与表决、参考和掩码、
> DNA 与 P12 派生、128-bit 内部 key；调试回读通路和未验收时钟边界均保留说明。

### 7.2 实板观测与失败保留

证据为 `data/ascon/results/board/uart_20261027_keys3.txt` 及对应 XDat。
同一文件含两个版本片段，必须区分：

| 片段 | 原始状态 | 可以支持的结论 |
|---|---|---|
| v2 抢跑片段 | busy 时启动，出现 quality=0，后续 127，最终 FAIL | 不能把该 127/128 当作正式通过结果 |
| v3 先等 idle | enroll=0x00008026，quality=128；MASK 全 1、DITHER 全 0、REF=RAW | 此次注册 128/128 位通过该采样判据 |
| v3 reconstruct | status=0x00008026；固件输出 PASS | 同次上电注册后，重建状态未报告 mismatch/fallback |

固件 `keys_rv32/main.c` 的 PASS 检查的是 ready、mismatch 与 fallback 状态，
并未在这份板级日志中直接比较两次秘密 key，也没有以派生 key 完成 AEAD Tag 验证。
因此“同次注册/重建自检通过”成立，“跨上电同密钥稳定”“认证启动通过”不成立。

### 7.3 安全与实现边界

当前 key_mmio 可回读 REF、MASK、RAW 与 DNA，puf_key 的派生上下文和算法也可见。
因此仅有“key 寄存器不可直接读取”不足以证明软件无法重算派生值；本版应称为可观测的密钥生成实验原型，
不能称为已经实现密钥保密隔离。无 helper 或匹配失败时的 DNA-only 回退也不提供秘密密钥保证。

已有扩展源集的时序审查记录 no_clock=10944、未约束内部端点=27312，位于 RO 采样域。
正 WNS 只覆盖当时已约束路径，不代表该扩展全域时序签核；这些数值不能套到无该子系统的 PYNQ 发布版。
跨上电、温压、多器件唯一性及小时级稳定性未测，不是本次提交的阻塞条件，但报告不将其写成通过。

本原型作为已实施的探索展示；后续若开展可靠性或安全隔离改造，须独立立项、构建与验收，
不替换已验证的三模式 PYNQ 演示版本。

<span class="evid">证据 src/rtl/keys/puf_key.v；src/rtl/keys/key_mmio.v；src/firmware/keys_rv32/main.c；data/ascon/results/board/uart_20261027_keys3.txt；docs/io_timing_signoff.md 的 RO 采样域记录</span>
