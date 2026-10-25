# V01 定向验证与提交交接（2026-10-25，owner TBD）

本轮仅首次提交已完成的20文件：`68fafc8eca095ce8afdf203edf4aea726151dfbc`，已推送到 `origin/feat/navigator_preboard`。推送前逐文件暂存、敏感信息/大小/路径核查和 `git diff --cached --check` 通过；远程 main 保持 `f88e178acb23e1a4cab2c6d8263349fdcb7bb85e`。提交没有skill、PUF、生产RTL、原始baseline、生成镜像或日志。以下新增测试及本文件均为**后续本地未提交工作**，不再次commit/push。

原始 [handoff.md](handoff.md) 是提交前事实快照，D-Cache FAIL、中断BLOCKED、PYNQ NOT_CONFIGURED记录保留；本文件补充后续验证，不能回写旧记录冒充当时已通过。

## D-Cache：TB_STALE

原TB不改，仍exit1。准确断言名称取原TB完整字符串（旧display为32字节会截断名字）；时刻/实际值来自本轮VCD：

| 原断言 | 时刻ns | 实际 | 预期 |
|---|---:|---|---|
| cold cacheable load bus load miss | 36 | 0 | 1 |
| cold cacheable load load miss pulse | 36 | 0 | 1 |
| cold cacheable load miss addr capture | 36 | 0x00000000 | 0x10000000 |
| store miss target is still a load miss | 206 | 0 | 1 |

接受load的35/205ns上升沿先锁存请求并进入MISS_CAPTURE，45/215ns上升沿才把锁存地址和一次请求脉冲发给总线。旧TB在接受沿后1ns要求总线已发请求，错一拍；stall已经正确拉起，之后回填/读命中、masked store、MMIO读写等原检查通过。

根因定位跨三个固定版本：

- `f52bc491db731791d43a073e034d66225c0ff370`（`3c6f134^`，引入miss流水拍之前）：原TB PASS/exit0。
- `38e96fb4c6504b87276bf0d8b6ce1cf46c169fde`（`964d1a3^`，Store Buffer之前、已有MISS_CAPTURE）：原TB同4个FAIL/exit1。
- 当前生产RTL：原TB同4个FAIL/exit1。因此这4个FAIL不是Store Buffer引入的新错误。`3c6f134`引入的miss流水变化使固定拍数假设失效。

复用 `build/timing_tests/tb_dcache_trace.v`，4种子(1/17/1234567/305419896)、每种1000轮定向/随机组合：Store Buffer前后逐拍CPU地址/读数据/stall、总线读写/地址/掩码、miss、回填和最终MEMSUM均逐字节一致。差分本身不证明两版都正确，因此新增 `tb_dcache_contract.v` 独立scoreboard：

- 由接受的CPU写请求更新reference memory，独立检查总线写的顺序/地址/数据/字节掩码，捕获重复/丢失事务；读取必须对应当前请求，miss地址必须保持锁存值。
- 总线模型采用有等待与beat间隙的4-beat WRAP回填；不预设miss必须第几拍发出，检查每个事务和最终数据，界定完成上限；不是放宽原超时。
- 首次cold miss、非零word offset回绕、store hit/miss、部分字节、紧邻store→load、store→store→load、请求hold以及500轮固定seed输入。
- 修改前后均PASS：578次load、671次store、404个read transaction、1616个回填beat；最终256字memory与独立reference一致。
- 保留最小旧时序探针：仍exit1；错误回填BAD_FILL和丢写DROP_WRITE都触发数据断言exit1，证明新TB会抓实错。没有删除原断言、修改生产dcache或篡改expected。

分类结论仅针对这4项：**TB_STALE**；未发现对应RTL功能错误，不代表完整Cache/AXI/一致性形式验证完成。

## 中断：6个真实接受/handler/mret场景PASS

新增 `tb_cpu_interrupt.v` 实例化真实生产 `cpu_core` 和 `clint`。独立memory BFM完成I/D Cache行回填、引入等待，CLINT配置BFM写实际mtimecmp，由真实mtime比较生成timer_irq；不force irq/PC/CSR/valid/guard。`interrupt_firmware.s`通过真实CSR指令设置mtvec、mie.MTIE和mstatus.MIE，执行计数、DIV、load和分支循环；handler执行csrr mepc/mcause/mstatus、计数和mret。

| case | 场景 | timer pending时关键覆盖计数 | 接受/mret |
|---|---|---|---|
| 0 | 基础timer | 等待合法指令后进入 | 1 / 1 |
| 1 | 延迟I-Cache回填 | icache stall15拍、guard=0等待18拍 | 1 / 1 |
| 2 | DIV多周期 | ex_stall31拍 | 1 / 1 |
| 3 | 外部存储停顿 | axi_hold8拍 | 1 / 1 |
| 4 | D-Cache miss | dcache stall15拍；也跨I-Cache miss | 1 / 1 |
| 5 | 分支flush/guard延后 | 分支flush1次、guard=0等待13拍、axi_hold8拍 | 1 / 1 |

每次接受均检查：上一拍slow条件与实际inter_slow_ok_q一致；有效EX指令、无被禁止的stall；trap_pc指向ELF中实际被中断指令（非气泡）；flush[3:1]/jump_sel/icache_flush正确。接受沿后检查mepc、mcause=0x80000007、MIE=0/MPIE=1和PC=mtvec。真实handler退休后检查其读回值/计数；mret沿检查MIE/MPIE恢复、PC回到mepc，之后循环计数不跳过/不重复、DIV=7、load=0x13579bdf。

case5的合法结果是先完成分支redirect，guard条件恢复后在有效指令处接受；不要求在guard=0的那条branch上强行接受。测试仍要求timer pending与branch flush实际重叠，不能用“最终没卡住”代替覆盖。

三项负向门禁均实际exit1：NO_TIMER（必须真有接受）、BROKEN_MRET固件（必须真正返回）、仅build/local临时副本绕过inter_slow_ok_q（必须检测非法接受）。生产cpu_core、CLINT、CSR、SoC文件均未改。早期TB曾误用ID阶段id_pc作为EX触发、在mret处过早检查尚未退休的handler结果，调试失败日志保留；修正测试阶段边界后才得上述结果，没有改RTL或放过错误值。

范围限制：这是CPU+CLINT+有界memory BFM的RV32 RTL集成测试，不覆盖SoC CLINT MMIO路由、嵌套/全部中断优先级、RV64、异步CDC、所有FENCE/MUL/ISE抢占、真实AXI背压或实板。V01保持in_progress。既有全回归旧FAIL/BLOCKED报告不改写，本轮不重复耗时Ascon全SoC运行。

## 复现与证据

```powershell
python -B sim/board/run_targeted_validation.py --out build/local/targeted_new
# 也可 --mode dcache 或 --mode interrupt；输出目录必须不存在。
```

最终实跑：`build/local/preboard_targeted_final_03/summary.json` / `.md`，overall PASS/exit0，D-Cache classification TB_STALE；每个真实子命令的PASS/FAIL、预期退出码与gate分别保存，不把旧FAIL或故障注入exit1改成原始PASS。小摘要见 [validation_evidence.json](validation_evidence.json)。工具Icarus/vvp12.0 devel(g2693dd32b)、WSL GCC13.2.0/binutils2.42、Python3.14.3；命令、Git SHA、源SHA256和原始log/VCD/trace/ELF/HEX均在独立local目录。

`build/local/preboard_followup_20261025_01/`是本轮诊断/早期失败证据目录，不是交付RTL快照或正式测试通过记录。下一接收 V01/TBD 扩展SoC/异常与中断，B03/B02/TBD进行 [下一步上板](next_bringup.md)。所有新增代码与文档留本地待审，不自动再次提交。
