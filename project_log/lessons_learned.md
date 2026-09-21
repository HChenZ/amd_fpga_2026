# 经验与踩坑

更新：2026-09-21。区分“已观察”与“待验证假设”，失败不删除，结论变化时追加证据。

| ID | 现象 / 状态 | 原因或证据 | 应对与关联任务 |
|---|---|---|---|
| L01 | 项目目标是 XC7Z020，现有 XPR 却是 Kintex（已观察） | 初始 Git HEAD 的 Part/synth/impl 均为 Kintex；后续 ZIP 已找到 XC7Z020 配置 | 以源码事实写审计，不因背景描述而改 part；B02/B03 独立恢复与核板 |
| L02 | `top` 静态展开成功，工程顶层失败（已复现） | 初始 HEAD 的 top_pl_bram 实例化 3 个未入库 IP，Icarus exit=4；XCI 现已恢复；源码文件路径存在不代表依赖齐全 | 不用空壳 IP 掩盖缺失；B02 恢复源配置/Tcl，V01 再验证功能 |
| L03 | CPI 名称容易被当成 cycle counter（已观察语义） | cpi_cnt 统计指令/停顿/flush，flush 每次加 2；真正 mcycle 在 csr_file | C04 使用 CSR 差值与 RV32 一致读取；保留计数器微测试和开销 |
| L04 | 软件目录存在但版本正确性无证据（待 C01/C03） | C api.h 是 1.3.0，Python README 链接 draft，没有锁定 final KAT 结果 | 不武断宣称旧版或合规；固定来源、逐项核对、可信 KAT 比对 |
| L05 | 文件名 ascon_round.v 不能证明 round 已完成（已观察） | 内容只定义 ror；ascon_word.v 只定义 load_bytes/store_bytes；未接 CPU/XPR | I02 从 spec 出发；不把辅助代码标成已完成 ISE |
| L06 | 参考仓库匿名访问返回 404，Git 有权读取（已观察） | API 404，git ls-remote/只读浅克隆成功 | 404 不等于仓库不存在；不索要凭据、不输出令牌，用已有 Git 权限读取结构 |
| L07 | 既有中文/空格路径与新增命名规范冲突（已观察） | 根目录历史选题指南文件名；XDC 注释非 UTF-8，defines.v 部分注释出现替换字符 | 不批量改名/转码；审计保留问题，D05/D06 制定发布映射并验证引用 |
| L08 | ignore 不会清除已跟踪 cache（Git 行为，当前有 2 个生成元数据文件） | project.wpc 和 .hw/*.lpr 已入索引 | 本轮保持不动，未来有重建证据再单独评审清理；不执行 git rm |
| L09 | PATH 检查不足以判定工具未安装（检查局限） | 只发现 Python/Icarus/Git，未全盘查 Vivado 等 | 写“PATH 未发现”，不写“机器未安装”；B02 记录实际 tool version |
| L10 | 文档验证脚本首次误报所有任务列数不符（检查脚本问题） | 检查器误设 9 列；实际规范是 ID/task 加 owner/prerequisite/deliverable/acceptance/deadline/status，共 8 列 | 修正检查器后重跑，不能按误报修改正确任务表；同时核对 P1 Skill 完成日期先于 PUF 门禁 |
| L11 | 任务日期检查发现 C02 目标编译排在 B04 固件基础之前（已修正） | C02 原内部日期 09-27、B04 为 09-28；依赖存在但日期不一致 | C02 调到 09-28，保留 C03 09-29、C04 09-30，未改变用户里程碑；依赖图与日期检查通过 |

新增条目模板：任务/日期、触发条件、完整现象、命令与日志、原因（已证实/假设）、尝试与结果、最终处理、未解决项、影响下游。不要把未运行的测试记成失败或成功。

## 原始 ZIP 到达后的证据更新（2026-09-21）

L01/L02 仅描述初始 Git HEAD；三个 IP 与原 XC7Z020 工程现已在 ZIP 找到并恢复。not_in_current_repo 不等于 not_available。

| ID | 已观察事实 | 处理 |
|---|---|---|
| L12 | 原 ZIP 与 Git 的 17 个 RTL 哈希不同，但只有 CRLF/LF 差异 | 同时给原字节哈希与规范化 diff，不武断判断哪个更新 |
| L13 | 后续 Git 提交只改 Part，初始 Git XPR 却已不同于 ZIP | 分开证明两段历史，不能以后一段推断更早的转换 |
| L14 | 原 XPR 引用生成 incremental DCP | 独立恢复副本最小移除 checkpoint；保持源路径，不导入整个 runs/gen |
| L15 | FreeRTOS app/COE 齐全不等于 kernel 源齐全；bootloader 只有 COE | 精确列缺口，不下载任意最新版冒充原版本，不擅自替换初始化 |
| L16 | 旧 add TB 使用 u_ram/u_cpu_core，AXI top 已不同；部分 env 链接扁平化为文本 | 保存原件，后续显式适配/测试；HEX 存在不是 ISA 回归通过 |
| L17 | 历史 WNS 为正但有未设 IO delay，资源报告有阶段差异 | 报告时注明时钟/覆盖和 placed/synthesis 阶段，不冒充 Fmax/本轮实测 |

## foundation 收口更新

L08 的“保留两个跟踪生成元数据”是此前策略；本轮按用户“无 generated build cache”要求完成清理。ignore 不会取消跟踪，需显式移出索引。git mv 会暂存 rename，故收口后不能继续报告“索引为空”；普通 git diff --stat 也不包含 staged rename 或 untracked 资产，应同时检查 cached diff 和状态。

收尾发现：默认 cached diff 检查把原 Kintex XPR/XDC 的 CRLF 判作行尾空白。保持源字节不动，仅在 `.gitattributes` 对这两个文件声明 cr-at-eol，同时保留 blank-at-eol、blank-at-eof、space-before-tab 检查；复核原哈希和检查结果。
