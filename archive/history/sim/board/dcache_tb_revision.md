# D-Cache测试契约修订（V01，2026-10-25，owner TBD）

这是测试修订，生产RTL未修改。本轮从`feat/navigator_preboard` / `68fafc8eca095ce8afdf203edf4aea726151dfbc`进入，保留前轮13项未提交工作；修改前快照、原失败日志与VCD都在build/local，未commit/push/merge。

## 独立复现与根因

原TB已在本轮连续两次实际重现4个FAIL/exit1，初始日志在 `build/local/dcache_tb_revision_20261025_01/before_0.log` 与 `before_1.log`，修改前文件在同目录before/。定向入口另将发布提交68fafc8的原TB和对应RTL冻结到各次独立输出目录，保存每次历史复现的log/VCD，不把失败结果覆盖。

| 原断言 | 旧检查时刻ns | 实际 | 预期 | 合法请求事件ns |
|---|---:|---|---|---:|
| cold cacheable load bus load miss | 36 | 0 | 1 | 45 |
| cold cacheable load load miss pulse | 36 | 0 | 1 | 45 |
| cold cacheable load miss addr capture | 36 | 0x00000000 | 0x10000000 | 45 |
| store miss target is still a load miss | 206 | 0 | 1 | 215 |

当前dcache在IDLE接受cold load，锁存地址/分类并进入MISS_CAPTURE；下一沿从锁存值发单拍`bus_mem_re_o/bus_load_miss_o`并进入FILL。原TB在接受沿后1ns立即检查总线，早一拍；地址也尚未发布。store miss采用write-through且不分配line，之后load仍是真miss，同样走该流水拍。接口没有ready引脚，单拍strobe是下游接受请求的边界，4个valid beat按WRAP顺序回填。

复核不只依赖旧结论：miss流水前f52bc49原TB PASS，Store Buffer前38e96fb与已发布68fafc8原TB同4 FAIL；Store Buffer前与当前的4种子逐拍trace/MEMSUM仍相同；独立事务TB检查实际数据正确性。分类为**TB_STALE**，未发现这4项对应的RTL功能错误，不外推为完整Cache形式证明。

## 修订前后差异

- 原`load_miss_and_fill`在固定一个posedge后检查read/miss/address。现先排入独立预期事务队列，单周期驱动CPU请求，等monitor实际观察到匹配的总线事务；最多等8个posedge，未发/发多了均非零退出。四个原始断言名称及其预期值保留，在请求事件处检查。
- 单一monitor在posedge后`#1`采样注册输出，刺激/回填/reset均在negedge驱动，任务在posedge后`#2`读取monitor结果，避免DUT NBA与TB采样竞争。修订后绝对仿真时刻可以不同，不硬编码45/215ns。
- 事务队列严格检查单一读写方向、顺序、地址、写data/mask和miss qualifier；不允许无预期事务或重复事务。请求总数、各方向总数、成功/中止fill与beat总数都在结尾核对。
- 完成上限仍为原30拍，另加8拍请求上限和全局watchdog。不是删除断言、改expected或单纯多等一拍；故障注入证明事件等待不会放过错请求。
- 保留原cold miss/hit、masked store、store miss后load、MMIO读写与stall场景。原`AAAA_*`、`EEEE_*`、`FACE_CAFE`等预期内容不改；新增byte lane0/lane3、连续store、跨3个时钟的hold，以及reset中止2-beat部分line后重新miss/回填/命中。复位前已经完整有效的line也必须重新miss，避免只检查部分line而漏掉valid/tag残留。
- 修订原路径TB正常结果：116项检查，13个事务（5 cacheable read、6 cacheable write、1 MMIO read、1 MMIO write），18个回填beat（4次完整fill+1次2-beat reset中止）。

## 交叉验证和反例

`tb_dcache_contract.v`保留独立reference memory与随机/定向驱动，仍检查578次load、671次store、404次read transaction及1616个回填beat，覆盖紧邻store→load转发及store→store→load，并校验最终256字memory。

修订TB必须实际拒绝：BAD_FILL（输入响应损坏）、missing_read、duplicate_read、wrong_address、wrong_write_data、wrong_write_mask、missing_write。后六种仅在build/local生成独立RTL故障副本；生产`dcache.v`字节不动，每个编译/执行命令、替换内容和SHA均入报告。缺请求触发有界超时，重复请求触发队列越界/重复检查，错误地址/数据/mask触发原值比较；任何正常退出或缺少对应失败标记都会使负向gate失败。

事务TB的BAD_FILL/DROP_WRITE和原有六组CPU+CLINT中断验证继续运行，包含禁timer/坏mret/绕过guard的非零退出门禁。JSON将actual状态/退出码、expected_exit_code与gate分别记录；预期反例的exit1不等于正常功能测试被忽略，任何未解释的FAIL都使整体非零退出。

## 入口与证据

```powershell
python -B sim/board/run_targeted_validation.py --mode dcache --out build/local/dcache_check_new
python -B sim/board/run_tests.py --mode smoke
python -B sim/board/run_tests.py --mode regression
```

统一入口直接编译/执行修订原路径TB；其targeted_baseline子目录还实际运行独立事务TB、四种子差分、故障注入以及六个中断场景。所有输出在build/local独立新目录，不覆盖旧报告。完整运行结果与版本/退出码见本轮完成时生成的 `build/local/dcache_tb_revision_20261025_01/final_report.json`。

本轮不修改PYNQ、Skill、PUF/密钥管理、共享CPU/SoC/Ascon RTL或原Vivado baseline。V01仍是部分覆盖，不能把这套回归PASS等同完整ISA/异常/RV64或板级门禁完成。

## 本轮最终实跑结果

工具：Python3.14.3、Icarus/vvp12.0 devel(g2693dd32b)、RISC-V GCC13.2.0/binutils2.42、Host GCC13.3.0。

| 验证 | 实际结果 | 退出码 / 证据 |
|---|---|---|
| smoke | 6 PASS / 0 FAIL / 0 BLOCKED / 9 NOT_RUN，16.394s | 0；build/local/preboard/20261025_111612_829523_smoke/summary.json |
| 完整regression | 15 PASS / 0 FAIL / 0 BLOCKED / 1 NOT_RUN，757.713s | 0；build/local/preboard/20261025_111629_599017_regression/summary.json |
| 修订原路径TB | 116项检查、13事务、18beat；Store Buffer前与当前均PASS | 各0；regression/targeted_baseline/*_revised_tb.log |
| 独立事务TB | 578 load、671 store、404读事务、1616beat；前后均PASS | 各0；regression/targeted_baseline/*_contract.log |
| 六个中断场景 | 每组接受1次timer、执行1次handler/mret并验证恢复结果 | 各0；regression/targeted_baseline/irq_case_*.log |
| 当前TB故障注入 | 坏回填/缺读/重复读/错地址/错写data/错mask/缺写全部被检出 | 各1为预期，gate PASS |
| 其他反例 | 事务TB坏回填/丢写；中断禁timer/坏mret/绕过guard全部被检出 | 各1为预期，gate PASS |

完整回归还实际运行SW/MMIO/ISE CPU、完整Host KAT、Mailbox和COE/CPU执行BIN一致性门禁，均PASS。唯一regression NOT_RUN是实板UART/Overlay，硬件cycles仍NOT_MEASURED。原失败快照保留actual FAIL/exit1，当前正常测试不存在未解释的功能性FAIL。

本轮直接修改原路径TB、既有定向runner、本说明与入口readme；统一run_tests.py沿用前轮未提交的调用逻辑，本轮未再改它，完整实跑已证明两套Cache TB与中断确实接入。公共日志及V01追加本轮结果，其余前轮未提交文件保留。

建议提交信息：`test(dcache): replace stale timing checks and pass full regression`。评审时应将原路径TB、定向runner、独立Cache TB、中断TB/汇编、统一入口及配套测试说明一起审查，避免只提交原TB而遗漏未提交依赖。远程68fafc8目前不含这些本地修订，因此不建议直接合并该远程版本；可在用户审核并提交必要文件后再评估PR合并。本轮没有自动commit/push/merge。
