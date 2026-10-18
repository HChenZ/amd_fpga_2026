# 并行任务卡 A：P1 PYNQ Host 层（代码向）

适合有 Python 能力、不需要板子的 AI。与任务卡 B 零文件冲突（B 只碰 docs/ 和任务看板）。

## 背景

项目：RISC-V SoC + ASCON-AEAD128 ISE（xc7z020clg400-1）。芯片级 100 MHz STA 已收敛、
功能回归全绿。P0 基本完成；本卡做 P1（PYNQ 展示）中**不依赖实板**的部分。
必读（按序）：`AGENTS.md` → `docs/project_overview.md` → `docs/technical_rules.md` →
`tasks/task_board.md` → `project_log/actual_progress.md`。

## 交付物（新目录 `src/pynq/`，不要动任何已有目录）

1. **`src/pynq/ascon_host_api.py`** — Python host API（对应看板 Y03）：
   - 输入 key/nonce/AD/plaintext（bytes），返回 ciphertext/tag/cycles（dict 或轻量 dataclass）
   - 错误显式：长度越界、非法 tag（解密）、超时、总线错误 → 抛具体异常，不静默返回垃圾
   - **后端抽象**：`Backend` 接口（当前实现 `SimulatedBackend`，调用锁定的 C/Python
     reference 计算 CT/tag，cycles 用公开的仿真实测值表（见下）占位并**标注 simulated**）；
     将来板级 `PynqBackend` 按 Y01 寄存器协议实现后无缝替换
   - 目录名/文件名英文小写下划线；Python 3.11，仅标准库 + 无 pip 依赖（与现有脚本一致）
2. **`src/pynq/golden_checker.py`** — 对照锁定 reference 的逐字节校验器：
   - 用 `data/ascon/kat/asconaead128.txt`（1,089 官方 KAT）+ 锁定 C/Python reference
     （`ascon/ascon_c/aead/` 与 `ascon/python/`）逐字节比 CT/tag
   - 全量 KAT 跑通：输出 PASS/FAIL 计数，FAIL 时报首个差异的字节偏移（从 0 起）
   - 支持注入错误（篡改 tag/密文）验证拒绝路径（参照 `sim/ascon/test_harness.py` 的做法）
3. **`src/pynq/jupyter_demo.ipynb` 骨架**（Y04 的无板部分）：
   - 顺序执行：导入 API → 跑 KAT 向量 → 打印加密/解密正确性与 cycles 表 →
     软件 vs MMIO vs ISE 加速比对比（数据取自下表）
   - 板级单元格用注释标 `# TODO(board)`，无板环境跑不通的部分不写
4. **`src/pynq/readme.md`** — 用法、后端接口定义、测试命令、与 Y01 协议的关系

## 验收标准

- `python src/pynq/golden_checker.py` 全量 1,089 KAT：PASS 1089 / FAIL 0，exit 0
- API 对空消息/1B/16B/16B+AD/17B/32B 六个代表向量输出与锁定 reference 一致（含 tag）
- 篡改拒绝测试：错误 tag → 异常/拒绝，不输出明文
- 所有路径在仓库根运行；不在代码里硬编码 C:\ 绝对路径

## 周期数据（供 API/notebook 使用，标注 simulated 来源）

| 实现 | 16B 加密 cycles（仿真实测） | 来源 |
|---|---|---|
| 纯软件 sw | 17353 | data/ascon/results/key_lifecycle/sw_timing_acb_sw.json |
| MMIO 完整往返 hw | 670 | hw_timing_acb_hw.json |
| ISE ise | 2496 | ise_timing_acb_ise.json |

## 禁区（违反会毁掉并行任务）

- 不碰：`src/rtl/`（含 dcache_experiments/）、`sim/ascon/`、`build/local/`、
  `build/reports/`、`ascon/`（用户自己的 Vivado 工程）、`docs/`、`tasks/`
- 不启动 Vivado（任务卡 B 的文档工作与其余收口不需要，且避免资源冲突）
- 不 commit/push；只留工作区文件

## 完成标准

- 四个交付文件齐全，验收标准全过；把运行命令、exit code、PASS 数写进 readme
- 在 `project_log/development_log.md` **末尾追加**一条你的活动记录（先读该文件格式再写；
  这是唯一允许你碰的共享文件）
