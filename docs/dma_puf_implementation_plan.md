# DMA 与 PUF：实现及验证方案

2026-10-29；owner TBD。本文为设计计划，不是已实现、已综合或已板测结果。
用户确认已提交简介不可修改：本轮不改简介或报告，不把下述新功能追写为已提交成果。
11-01 是当前提交/冻结节点，按阶段结果决定是否将新实验作为补充材料；原 PYNQ release 保持可演示。

## 1. 当前代码基点

| 方向 | 已存在 | 本轮检查发现的实际缺口 |
|---|---|---|
| 数据通道 | PS GP0 → AXI-Lite字节FIFO → UART → RV32；三模式板测通过 | 每次Python字节访问与串口开销较高，PS单次调用中位约4.262–5.216ms；不是AXI DMA |
| Ascon HW | ascon_aead_core.v有32-bit流式包装 | 内部只缓冲16B AD/消息，然后调用128-bit核一次；包装名含stream不等于多块算法 |
| SW/ISE | 软件多块循环与P8/P12置换指令 | 当前service共同容量16B；扩容还涉及frame、buffer、能力广告和验证 |
| CPU缓存 | 0x100xxxxx为cacheable，外设uncached | 无通用D-cache维护接口；不宜直接让DMA改CPU已有cacheable代码/数据BRAM |
| PUF | 256 RO、128响应位、DNA、注册/匹配、P12派生、MMIO | 已有同次上电v3 quality128/128与重建状态通过；非跨上电可靠性证明 |
| PUF错误传播 | 采样域watchdog强制done | 无独立采样失败输出，可能重新发布旧raw/dither；采样域时钟停摆时同域watchdog也不能救援 |
| PUF秘密边界 | key无直接读地址 | REF/RAW/MASK/DNA可读且派生确定，可重算key；DNA-only回退不是秘密密钥 |
| PUF时序 | 曾记录受约束路径正余量 | 既有源集no_clock10944、内部未约束27312；必须核对网表，不能靠补一个假时钟掩盖常量折叠 |

参考代码：`src/rtl/ascon/ascon_aead_core.v`、`src/rtl/dcache.v`、`src/rtl/keys/{ro_puf_core,puf_key,key_mmio,ro_unit}.v`、
`src/firmware/pynq_svc/`、`board/vivado_zynq7000_xc7z020_pynq/build.tcl`。

## 2. DMA 推荐分两阶段

### 2.1 D-A：先加速传输，保留 RV32 三模式（优先）

```text
PS Python / 连续物理DDR buffer
         ↕ PS S_AXI_HP0（非一致性路径）
      AXI DMA MM2S / S2MM
         ↕ 32-bit AXI-Stream
  请求/响应FIFO或独立packet BRAM
         ↕ 新增RV32 uncached MMIO端点
 RV32服务固件 → SW / 原MMIO核 / ISE

PS M_AXI_GP0 → DMA控制 + 新endpoint控制/状态（AXI-Lite）
已有UART路径保留为bring-up/诊断参考，测试时独占一个数据通道。
```

PS端DMA从DDR读请求、把响应写回DDR。RV32仍参与读输入与写输出，不能宣传“CPU完全不搬运”。
其价值是去掉Python逐字节轮询与UART串行瓶颈，并保留同一CPU上的三模式比较。
缓冲优先使用独立packet存储，不改当前启动BRAM内容，也不依赖D-cache失效。

**建议初始配置（未在Vivado应用/回读）：**

| 项 | 初始选择 | 实施时必须核验 |
|---|---|---|
| DMA | AXI DMA，MM2S/S2MM双通道，simple mode，不启用SG | PYNQ2.7驱动绑定、IP版本、实际接口和寄存器模式 |
| AXI-MM内存侧 | 64-bit、地址覆盖当前PS DDR | PS HP0位宽、地址段、板端PS配置和时钟；不能只改BD不验PS状态 |
| AXI-Stream | 32-bit，TKEEP/TLAST，单事务起步 | 不等宽接口需要实际转换器；不靠自动推断而不回读 |
| 时钟 | 首版同100MHz，复位按域同步释放 | DMA、HP端口、桥和CPU的所有时钟/复位连接 |
| 对齐 | 连续buffer基址按总线要求对齐；首版禁不对齐偏移 | DRE开关与地址对齐要求据PG021/当前驱动确认 |
| 长度字段 | 覆盖最大完整帧，不只覆盖消息体 | 有效上限是字段可表示值和驱动限制；按真实配置做边界测试 |
| CPU窗口 | 拟0x20020000、4KiB寄存器窗口 | 属提议地址，须核对全地址译码无冲突；以最终接口文档为准 |
| packet容量 | 首版仅16B算法，随后SW/ISE到32B，再按需1KiB | 超容量在接收/存储前拒绝；不能先写爆再报错 |

若PT/AD均1KiB，按当前请求字段扩展的最大请求为48+16+16+1024+1024+16=2144B，
输出最大48+1024+16=1088B；可先配每方向4KiB packet存储（设计预算，资源/时序未测）。
DDR缓冲要用真实分配的device_address，不用Python虚拟地址。

### 2.2 接口和固件改动

建立独立工程 `board/vivado_zynq7000_xc7z020_pynq_dma/`，不要直接执行原脚本的force覆盖正式release。
固定来自当前release的输入源集，显式选择rtl_p0顶层，输出至新的release候选目录。

计划新增：

- `src/rtl/pynq_dma/axis_packet_rx.v`、`axis_packet_tx.v`：流握手、计数、TKEEP/TLAST和FIFO/packet存储。
- `src/rtl/pynq_dma/rv32_dma_endpoint.v`：uncached RX/TX数据、状态、长度、epoch、doorbell、错误与reset。
- 新top/总线接线：明确新增CPU从设备译码；尽量保留CPU流水本体，不能声称完全不改SoC。
- 固件抽出transport收发接口，保留AEAD算法适配器与mcycle调用边界；新增DMA endpoint后端。
- `src/pynq/dma_transport.py`：连续buffer分配、发送/接收、限时状态轮询、失败恢复、释放所有权。
- `sim/pynq_dma/`：协议scoreboard、背压与坏帧TB、真实CPU服务测试。

首版可保留v1帧字节布局和共同16B容量，但必须单独标识transport/firmware_id，
不能把DMA响应送给旧UART backend。若支持按模式不同长度，新增**版本化能力握手**，例如SW/ISE=32B、HW=16B，
旧客户端遇到新版本应明确拒绝；不静默改变v1共同容量语义。

### 2.3 一次事务与异常契约

1. 主机获得单客户端独占权；分配互不重叠的TX/RX连续buffer，填请求、清理旧输出。
2. PS写入后flush/sync_to_device，预先提交S2MM接收，再提交MM2S发送；避免下游未准备好造成堵塞。
3. RX按TVALID且TREADY才消费；背压时TDATA/TKEEP/TLAST保持。按帧头与累计有效字节双重验证长度。
4. request完全接收且合法后才发布给RV32；CPU不得读半帧。一个epoch/request_id只执行一次。
5. 加密返回header+CT+tag；解密仅认证成功后返回header+PT。失败也返回固定非零长度header，
   payload长度0；因此空消息/认证失败都不需要发零字节DMA事务。
6. TX每响应只生成一个TLAST；RX容量是上限，实际完成长度须与响应头、TKEEP计数一致。
7. 主机确认DMA完成且无错误后invalidate/sync_from_device，校验epoch/id/op/mode/status/长度，再发布结果。
8. 超时、短帧、超长、错误TLAST、DMA错误：停止生产者、使DMA静止、确认不再访问buffer，清FIFO/候选输出，
   更新epoch后恢复。未确认DMA停止不能释放或复用buffer；单纯Python timeout不等于硬件已停止。

cache测试分两处：PS DDR与DMA之间需实际flush/invalidate验证；RV32通过uncached端点避免共享cache行。
不把“DMA接HP口”视为自动缓存一致性。禁止两个进程或两个transport同时控制同一硬件事务槽。

### 2.4 D-B：真正多块 AEAD / 直连DMA密码核（后续）

现有 `ascon_aead_core.v` 不是任意长度流核。若要HW跑全1089或大消息，需新增持久320-bit状态的多块AEAD控制器：

```text
初始化P12 → AD整块/尾块吸收P8 → 域分离
→ 消息整块/尾块处理 → 终结P12 → tag验证 → 结果发布/擦除
```

- 覆盖AD=0、消息=0、完整16B边界的额外padding、不同尾字节数、decrypt状态更新。
- DMA分包只影响传输；AEAD状态跨分包保持。不能将每16B独立加密再拼接冒充同一条标准消息。
- 解密首版设有界MAX_MSG，例如1KiB，候选明文暂存在PL私有BRAM，认证通过后才允许输出到S2MM。
  不得把候选明文先写到PS可读DDR、最后返回AUTH_FAILED作为认证前不泄露的替代。
- 更大消息若不能私有缓存，需另行设计可信两遍处理及输入不可变性，不能无条件宣称无限流式解密。
- 可选DMA直接连接多块核，标为 `HW_DIRECT`；这是独立加速器路径，不是CPU ISE。
  此路径不使用CPU mcycle包装成核周期，须新增准确边界的PL计数器。

## 3. DMA 分层验证

| 层级 | 用例 | 通过标准 / 证据 |
|---|---|---|
| D0 DMA环回 | 1/2/3/4/7/15/16/17/31/32/63/64/65/255/256/257B，最大合法帧，跨4KiB边界 | RX逐字节相同；canary未破坏；DMA实际长度一致 |
| D1 流协议 | 随机TREADY、间歇TVALID、最后1/2/3字节TKEEP、早/晚/缺TLAST、复位中途 | 无丢失/重复/重排；坏帧显式失败，限时恢复 |
| D2 CPU集成 | 同一289官方KAT、encrypt/decrypt、逐位坏tag、三模式、旧UART对照 | 三模式结果一致；真实CPU执行；证据不带simulated标志 |
| D3 SW/ISE扩容 | 完整1089官方KAT（PT/AD0–32）与各类篡改 | SW/ISE全量通过；原HW仍限16B，不隐式fallback |
| D4 多块HW | 同1089+随机key/nonce/AD/PT，长度63/64/65/255/256/257/1023/1024 | Final参考逐字节相同；认证前/失败无PT输出 |
| D5 负向/恢复 | DMA错误、非法长度/id/epoch、超容量、接收没准备、FIFO满、reset、重复请求 | 有界完成或有界失败；恢复后重跑合法KAT；无旧响应混入 |
| D6 板级缓存 | 更换TX内容、复用不同RX buffer、canary、连续请求 | 新输入/输出可见，不靠上次cache内容偶然通过 |
| D7 实现 | 最终top/part/IP/source/clock/约束、routed时序与DRC、BRAM固件一致性 | 无未解释的同步路径缺约束；新bit/hwh/固件配套hash |

性能至少分：预分配buffer条件下PS事务墙钟、CPU AEAD mcycle、DMA纯搬运时间、可选PL核周期。
分别测16/32/64/256/1024B，按模式支持范围选择；5次预热+至少30次样本，保留min/median/P95/max。
记录分配、序列化、cache维护是否计时；吞吐计算使用**有效消息字节**，包头/AD/Tag字节另外报告。
相同新固件下SW与ISE比较；不能用旧UART 23342或历史20806作为任意新路径的固定分母。
短16B不保证DMA更快，不能预设加速倍数。

## 4. PUF 三个递进目标

### P-A 功能原型可信完成（优先，不改成量产承诺）

1. **错误与新鲜度**：采样接口增加sample_error/error_code/transaction_id或等价机制。
   watchdog不得沿成功路径发布旧raw/dither；失败时valid=0或error明确、key_valid保持0。
   核心clk域另加请求deadline，覆盖ro_clk停摆；失败清旧key_ready、清key/候选状态，busy必须退出。
2. **RO健康**：保存实际计数和差值的调试样本，检测不振荡、饱和/回绕、相等计数、窗口不完整与全部同向。
   相等计数不作为稳定“1”直接通过；它应标为无效/低置信位。质量是样本通过数，不是熵位数。
3. **CDC/时钟**：先检查综合网表里RO环、BUFG、分频寄存器是否真实存在，定位常高根因。
   管理状态机可优先改用100MHz+clock-enable，减少fabric分频时钟；RO计数域仍需独立跨域设计。
   req/done只在最终同步级之后检测边沿；控制计数使能/清零、停止后快照须有明确稳定窗口和确认机制。
   异步计数采集可用Gray计数/稳定快照握手，但仍要约束总线偏斜及CDC路径，不能靠双拍采样任意二进制总线。
4. **约束与布局**：给所有可同步分析时钟真实模型；RO自振无法照普通理想时钟证明所有行为。
   有意组合环与异步边界按具体对象、理由、计数、CDC证据管理；不能全局false_path让报告变绿。
   pblock容量与放置同样核验；所有局限跟新源集/DCP/hash绑定。
5. **使用证明**：新增板端“内部key完成固定消息AEAD→重建→相同nonce/输入得相同CT/tag”的演示，
   仅使用专用测试消息/nonce重复作一致性验证；不导出key，不能把当前状态自检当成这一步已完成。
6. **失败关闭**：取消正常模式DNA-only静默放行。采样/重建失败返回KEY_NOT_READY/RECON_FAIL，
   拒绝AEAD，且无明文输出；DNA-only只可保留在清晰标识的诊断模式，不能进入安全模式。

建议涉及 `ro_puf_core.v`、`puf_key.v`、`key_mmio.v`、独立top/约束与 `keys_rv32`；
在独立变体实现，不直接污染已板测PYNQ release。

### P-B 跨上电重建（持久化 + 纠错/验证）

**诊断路线**：先把现有REF/MASK持久化至PS文件/SD，严格保存board_id、版本、构建hash、采样参数与校验。
断电后载入同一份helper，仅执行reconstruct，不重新enroll。此路线只验证重建工程流程，
由于存了完整参考响应，不能作为秘密密钥方案。

**保密路线**：不能继续把完整REF/RAW公开并称helper无泄漏。应改为经过分析的secure sketch/纠错辅助数据，
配合提取器与域分离的标准构造；根据真实BER选择纠错码，而不是先拍定BCH参数。

- 注册与验证样本分离；选择RO对时基于多轮频差余量与稳定性，不只M=5全一致。
- 现128原始位经筛选和helper泄漏后不足以直接声称128-bit秘密熵；需更多有效原始熵或降低安全目标。
  增加RO对/挑战数不自动增加独立熵，要评估相关性。密钥输出宽128不等于安全强度128。
- helper允许公开不代表允许任意篡改；必须绑定设备、构建、参数、版本，设计认证/校验与回滚策略。
  CRC只防偶然损坏。若要抵抗恶意替换，可信公钥/元数据根必须来自已信任的配置/启动链；不能用helper自身自证。
- 推荐评估具备明确提取性质的构造再做标准KDF（例如HKDF-SHA-256），或严谨定义的Ascon-XOF派生方案；
  不把当前固定上下文+P12截取的自定义电路直接命名为标准安全KDF。
- release构建关闭RAW/REF/debug读口，允许生命周期限定的注册窗口；JTAG/未认证bitstream攻击是否在模型内须声明。
  不在本轮烧写不可逆eFuse或修改板级启动安全配置。

### P-C 镜像认证原型（最后）

只有P-A/P-B相应目标通过后，才接PUF派生key与Ascon-AEAD镜像验证。
将版本、长度、目标地址等作为认证元数据；认证成功前不放行执行，失败清候选和错误状态。
还需可信boot stub/配置、重放与回滚边界，否则只能称“镜像完整性/认证演示”，不是完整安全启动链。
PUF并不能自动保护FPGA bitstream不被替换；DMA也不提供机密性/认证，三者是不同问题。

## 5. PUF 验证矩阵

| 层 | 必测情形 | 通过标准 |
|---|---|---|
| 控制/状态TB | enroll、reconstruct、无helper、mismatch、连续START、busy/clear竞争、reset各阶段 | 有界结束；事务不串；旧ready/key不被复用 |
| 故障注入 | 停RO/停ro_clk、强制计数相等/饱和、watchdog、缺done、坏helper | 明确失败；不生成有效新key；AEAD拒绝；恢复后合法流程通过 |
| 纠错（若实现） | 0..t位错误、边界/超过t错误、helper损坏、错误板标识 | 可纠正范围正确；超范围不能仅信decoder，结合完整性验证拒绝误纠正 |
| 使用证明 | 内部key驱动AEAD，同次重建再算，错误key/坏tag | 可重复CT/tag，错误认证拒绝；不导出key；全程有日志 |
| CDC/STA/结构 | 真实时钟、RO环数量、同步级、稳定快照、pblock容量、RO健康 | 同步逻辑签核；异步例外逐项解释，不靠一张正WNS表 |
| 上电试验 | 固定enrollment，真正断电后reconstruct，至少50次作为初步实验 | 保存每次结果与失败；不得每次重注册；只称有限样本通过 |
| 温度/电压 | 仅在板卡/器件规格允许且可测范围内，固定helper | 保存实际温压、计数/BER、重建失败率；无仪器记not_measured |
| 多器件 | 多块物理芯片、相同方法与独立enrollment | inter-device HD与相关性分析；单板不能证明唯一性 |

统计：intra BER=同设备响应与固定参考的HD/有效位数；inter HD=不同芯片响应HD/比较位数，
另报有效位比例、重建成功/失败数、时延、计数差分布。原始响应只在受控诊断记录保存，不放入release公开日志。
quality128/128不是概率/熵/不可克隆性证明。即便50次重建0失败，按独立同分布假设，95%单侧失败率上界仍约5.82%，
不能宣传99.9%可靠性；约2995次独立零失败才对应0.1%上界，真实温压相关性还需另外考虑。

## 6. 资料与配置覆盖

本次未启动Vivado，**没有应用任何IP配置**。上表是候选设计；CONFIG属性名、范围、IP版本、HP接口与驱动行为
须在Vivado2025.2 scratch工程与真实板端回读后定案。不能把此计划写成“DMA已配置完成”。

已读取（2026-10-29）：

- PYNQ2.7 DMA文档：https://pynq.readthedocs.io/en/v2.7.0/pynq_libraries/dma.html
  simple mode、MM2S/S2MM、TLAST结束与最大传输配置要求。
- PYNQ2.7 allocate文档：https://pynq.readthedocs.io/en/v2.7.0/pynq_libraries/allocate.html
  连续物理buffer、device_address、coherent、flush/invalidate。
- AMD PG021入口：https://docs.amd.com/r/en-US/pg021_axi_dma （本次仅返回动态页面壳，未核读参数正文）。
- AMD UG585为Zynq PS/HP口参考；具体参数实施前核对当前版本。

当前客户端未注册amd-doc-search；因此不在本文给未经核实的set_property属性或猜测修复Tcl。
计划表见 `../tasks/advanced_features_plan_20261101.md`。
