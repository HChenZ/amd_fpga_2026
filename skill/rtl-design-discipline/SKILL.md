---
name: rtl-design-discipline
description: "Use when writing/reviewing RTL. Hardware-first, minimal."
---

# RTL 电路设计纪律（Hardware-First RTL）

RTL 描述的是硬件，不是程序。每一行 `assign`/`always`/`Mux` 最终都变成硅片上的逻辑门、触发器、连线。写代码之前先想清楚电路长什么样；写完的代码应当是**最小、最清晰**的那份电路表达。

本 skill 针对 AI 写电路代码最常见的四个毛病（适用范围：Verilog / SystemVerilog / Chisel / VHDL / HLS C++）：
1. 同一段逻辑写出一堆等价的废话（重复的嵌套表达式）
2. 打补丁式改代码，越改越绕
3. 电路层面优化意识差（不知道综合出来是什么硬件）
4. 生成一堆没必要的组合逻辑 / 多余的寄存器

## 0. 先画电路，再写代码

动手前，先在脑子里（或纸上）确定三件事：
- **状态（寄存器）**：有哪些触发器？每个 `reg` 都是一片真实的 FF。多一个 reg = 多面积 + 多一拍延迟。
- **组合函数**：从「当前状态 + 输入」到「下一状态 + 输出」的纯组合逻辑是什么？
- **数据通路 vs 控制**：哪些是数据（加、移位、选通），哪些是控制（使能、选择、复位）？

寄存器清单就是设计，代码只是记法。先把每个寄存器的「下一值」写清楚，再填组合逻辑。

## 1. 一个信号 = 一个语义 = 一处赋值

任何「同一个值」只能在一处定义，其余地方引用它。两个表达式若算的是同一个东西，挑最清楚的那个、起个名字（中间 wire），不要各算一遍。

反例——真实案例（RISC-V 核取指单元，示意简化，`Mux(c,a,b)` = `c?a:b`）：

```scala
// 坏：同一个 Mux(redirectNow, redirectNowTarget, …) 在不同嵌套层被重写多遍，
//     还夹着一个深层条件 redirectPendingFire
pc := Mux(ifu.io.pc.ready,
        Mux(redirectNow, redirectNowTarget,
            Mux(redirectPendingFire, nxtPredictedPC, redirectTargetReg)),
        Mux(redirectNow, redirectNowTarget, nxtPredictedPC),
        Mux(redirectNow, redirectNowTarget, pc))

// 好：把「PC 下一值」和「喂给 IFU 的值」两个信号分开，各自写一次
pc          := Mux(redirectNow, redirectNowTarget,
                   Mux(ifu.io.pc.ready, nxtPredictedPC, pc))
pcFeedToIFU := Mux(redirectPendingReg, redirectTargetReg, pc)
```

坏版本里 `Mux(redirectNow, redirectNowTarget, …)` 出现了 3 次。只要其中一处和别处有一点点不一致，就是一个真实的取指 / 分支预测 bug。**重复 = 漂移 = bug。**

## 2. 禁止嵌套条件蔓延（No nested-conditional sprawl）

深度嵌套的 `?:` / `Mux` / `if-else` 链、且子表达式反复出现，是典型的打补丁产物：先加一个特例，再加一个特例，越套越深。

做法：
1. 把每个「事实」提出来命名：`redirect_taken`、`redirect_target`、`seq_pc`、`stall`。
2. 最后一个 `assign` / `Mux` 只做一次干净的选择。
3. 经验法则：**同一个子表达式出现 ≥2 次，就提成一个具名 wire。**

```verilog
// 坏：为支持 stall，把原来的 next_pc 表达式又整个包了一层
assign pc = stall ? pc
          : (redirect ? redirect_target
                      : (branch ? branch_target : pc + 4));

// 好：先算「顺行下一值」，再做平铺的优先级选择
wire [31:0] seq_pc = branch ? branch_target : pc + 4;
assign pc = stall    ? pc
          : redirect ? redirect_target
          :            seq_pc;
```

## 3. 分清「优先级选择」与「并行选择」

综合出来的硬件不一样，别写错：
- `if-else` 链 → **优先级编码器**（级联 Mux，逻辑更深、路径更长）。
- `case`（带 `default`）→ 分支互斥时综合成**并行 Mux**（更平、更快）。

语义上需要优先级（中断 > 异常 > 正常、重定向）用 `if-else`；分支天然互斥（指令译码、状态机状态）用 `case`，别写成一串 `if-else`。

```verilog
always_comb begin
    if (irq)         vec = irq_vec;   // 有优先级：中断压过异常
    else if (except) vec = exc_vec;
    else             vec = 32'd0;
end

always_comb begin
    unique case (state)                 // 状态互斥：用 case，不是 if-else 链
        IDLE:   next_state = READ;
        READ:   next_state = EXEC;
        EXEC:   next_state = IDLE;
        default: next_state = IDLE;
    endcase
end
```

## 4. 组合逻辑必须完整（否则隐式锁存器）

`always_comb` / `always @(*)` 里，每个输出在**每条路径**上都要被赋值（或在块顶给默认值）。不完整的 `if`（缺 `else`）或 `case`（缺 `default`）会让综合器推断出**锁存器**——多了一块你没要求的状态。

```verilog
always_comb begin
    out = 0;              // 块顶默认值，保证完整
    case (sel)
        2'b00: out = a;
        2'b01: out = b;
        default: out = 0;
    endcase
end
```

（顺序块 `always @(posedge clk)` 里不写 `else` 是合法的「保持」，组合块里不写就是 bug。）

## 5. 别替综合器干活，也别假装它万能

- 知道什么综合成什么：Mux→LUT、加法/移位→进位链、比较→LUT、RAM→BRAM、乘→DSP。别手写综合器本来就会优化掉的东西。
- 但**别**故意写冗余项、指望工具替你化简——写你真正要的布尔表达式（化简掉冗余项）。化简是表达**意图**，不是炫技，更不是把一堆冗余 `| x` 丢给工具。
- 优化只在报告要求时才做：时序不达标 → 看关键路径，针对性优化（重定时、流水、资源共享），而不是一开始就手搓「聪明」电路。**先正确、清晰，再优化。**

## 6. 改代码 = 重构，不是打补丁

改动引入新条件 / 新优先级 / 新特例时，**不要**把现有表达式再包一层 `if` / `Mux`。回到第 0 步的数据通路图，重新推导完整的「下一值」，干净地重写整段选择逻辑。
- 打补丁 → 冗余嵌套（第 2 条的根源）。
- 重构 → 最小等价形式。

## 7. 命名承载设计

`next_pc`、`redirect_target`、`stall`、`taken` 这样的名字本身就是注释，帮读者（和 AI 自己）对齐语义。禁用 `tmp` / `w1` / `x` / `a` 这类无名信号。名字对不上语义时，先改名字再改逻辑。

## 8. 验证对电路负责

收工前自问：
- 每个 Mux 的**每个输入**都被测试向量覆盖了吗？（每个分支、每级优先级）
- 复位、使能、stall、back-to-back 重定向这类**角落情况**测了吗？
- 每个 `reg` 的状态迁移路径都对了吗？

测试想的不是「代码跑通」，而是「这个电路在所有输入组合下都做对了」。

## 9. HLS 里同样是 hardware-first

HLS（Vitis HLS / Catapult）的 C/C++ 是功能描述，电路由**数据依赖 + 显式约束**决定。写 C 时脑子里仍要画电路：
- **变量 = 硬件**：跨迭代读写的标量会变成寄存器（FF），数组会变成存储（RAM/BRAM）。心里先定「这个数组要 partition 成几块、要不要 ping-pong」，而不是等综合报告出来再补 `array_partition`。
- **循环 = 迭代调度**：II / 流水 / 展开是**结构决策**（依赖允许吗？资源够吗？），不是出问题后随手贴的一个 pragma 补丁。先看依赖，再定 II，再上 pragma。
- **数据流**：级联的函数用 `dataflow` 并行，但先想清楚 stage 之间传的是 stream 还是 buffer——这决定存多少、延迟多少。
- **别替工具干活**：不手动展开循环、不手动把公共子表达式提成寄存器、不把一堆函数内联成一个巨型函数（会堵死数据流分析）。
- 具体 pragma 语法（`target_ti`、pipeline scope、dataflow channel）回对应的 hls-* skill；本条只管「电路思维」这一层。

---

## 与其它 skill 的分工

- 本 skill 管**设计质量**：电路该怎么想、怎么写才最小最清晰。
- `Verilog Design Flow` 管**流程**：spec → 实现 → slang 语法检查 → 仿真 → VCD 波形调试。
- `karpathy-coding-guidelines` 管**通用工程纪律**：想清楚再动手、最小改动、外科手术式编辑、目标驱动。
- hls-* 系列 skill 管 **HLS 具体 pragma 与流程**：本 skill 的「电路思维」是它们的前提，具体怎么打 pragma 回 hls-optimize / hls-pipeline / hls-dataflow。

三者叠加：写 RTL 时本 skill 优先；流程问题回 Verilog Design Flow；通用习惯回 karpathy；HLS 落地回 hls-*。
