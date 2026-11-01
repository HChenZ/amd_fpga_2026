# Ascon SoC poster

任务 D03，owner TBD，更新 2026-11-01。PPT 共两页：第 1 页中文，第 2 页英文；
在用户手动更新的海报上修改，保留 960 × 540 pt 画布、AMD 标识与三栏布局。
文字、DNA/PUF派生图、架构图、性能条形图和数据表可编辑。指导老师按用户要求不填。
当前交付范围、创新一、创新二的说明分别采用1–3、1–4、1–3逐项编号，中英文同步。

## 交付文件

- [ascon_soc_poster.pptx](ascon_soc_poster.pptx)：中英文两页海报。
- [ascon_soc_poster.png](ascon_soc_poster.png)：中文页，2400 × 1350。
- [ascon_soc_poster_en.png](ascon_soc_poster_en.png)：英文页，2400 × 1350。
- `readme.md`：使用说明、来源与验证摘要。

原 `build_poster.ps1` 是初稿生成脚本，`verify_poster.py` 是核验脚本，五份 JSON 是工具/哈希/
布局/文字边界/内容检查记录，不是播放 PPT 的依赖。按用户要求已从本目录及本次仓库版本移除，
本地临时保留。修改海报直接编辑当前 PPTX，再用 PowerPoint 导出两页 PNG。

## 学校与成员

学校：华南理工大学（South China University of Technology）。
成员：熊雅琦、胡潇正、黄晨中；英文按拼音写为 Yaqi Xiong、Xiaozheng Hu、Chenzhong Huang。

校徽取自[华南理工大学官网“学校标识”](https://www.scut.edu.cn/new/9017/list.htm)，
使用该页[校徽高清原图](https://www.scut.edu.cn/_upload/article/images/16/02/3166fd1b4c8cb0148ec56c04f071/8ab1bcf6-62d8-47c0-bff4-0ce88872dbd7.jpg)，
获取日期 2026-11-01。原图已嵌入两页，保持比例，未裁切或重绘，校徽权利归华南理工大学。

## 项目数据与边界

- 周期/加速比、KAT、PUF与频率：[PUF3实板原始记录](../../data/pynq_puf3/notebook_20261031_114512/result.json)，时间2026-10-31T11:45:13.863864+00:00，`physical_board_pynq_puf3`、`pynq-svc-puf3`、非仿真。KAT #529，PT=16 B、AD=0、HWKEY关闭，预热5次，每模式30次采样，CPU mcycle中位数，不含PS/UART。
- PUF3三模式每模式289/289容量内KAT通过、289次坏Tag拒绝。注册质量127/128，同一会话连续5次重建稳定，HWKEY关闭后KAT恢复。
- 9项错误门禁/7次reset/epoch恢复：[PYNQ v1历史error gate](../../data/pynq/error_gate_20261031_112812/pynq_board_error_gate.json)，海报明确归属v1，不计为PUF3通过项。
- PUF3资源/时序：[utilization](../../board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/reports/utilization.rpt)、[timing summary](../../board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/reports/timing_summary.rpt)、[gate](../../board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/reports/gate.txt)。架构、ISE仍参考[技术报告](../../docs/tech_report/report.md)。
- Skill L3：[汇总](../../data/skill/l3_20261031_063709/40_summary.json)。右上实物照片来自 `docs/tech_report/figs/board_photo.jpg`。

| 模式 | 加密cycles | 加密加速比 | 解密cycles | 解密加速比 |
| --- | ---: | ---: | ---: | ---: |
| SW | 21,862 | 1.000× | 22,562 | 1.000× |
| MMIO | 1,369 | 15.969× | 1,213 | 18.600× |
| ISE | 3,895 | 5.613× | 4,288 | 5.262× |

PUF3实现资源为LUT18,674、FF32,002、BRAM34.5、DSP4。已约束路径WNS +0.104 ns、
TNS 0、WHS +0.041 ns；RO计数器域尚未签核，不能据此宣称全域时序通过。
配置频率100 MHz，`clock.fclk0_mhz_measured_mcycle`为99.9723 MHz，来自mcycle/PS时基估测，
不是示波器测量或Fmax测量。

左侧为PUF3同一overlay集成的Device DNA与RO-PUF密钥派生通路：128-bit PUF响应和57-bit器件标识
与固定上下文组成输入，经Ascon P12派生128-bit key。依据技术报告§2.3.4及
`src/rtl/keys/puf_key.v`、`device_dna.v`。两者是独立输入，DNA非秘密。
图示为PUF参与的正常派生路径；DNA-only回退未展开，不提供秘密密钥保证。
依据[接口说明](../../docs/interfaces.md)，PUF3仍是独立于PYNQ release ABI的变体，但其自身同一overlay已集成RO-PUF/DNA通路；
左右数据现在统一为PUF3，普通SW/MMIO/ISE benchmark在HWKEY关闭时测量，不冒充PUF硬件密钥模式的性能。

仅有同会话功能验证，诊断量REF/MASK/RAW/DNA可读，不能据此宣称密钥保密隔离。
跨上电、温度、BER、熵、唯一性均为`not_measured`，保密隔离未验收。逐项来源也写入两页备注。

## 验证

本次仅更新两页数据、数据归属、测量边界及备注，保留原版式。PowerPoint16.0保存及渲染；
Python3.14.3原始JSON/周期/加速比/柱长/表格/未修改区域/资源文字等503项核验PASS。
除明确的数据更新对象外，原有图形XML与改前完全一致；全部对象位置尺寸保持原样，柱长与数值标签位置随数据更新。
母版、布局XML语义、主题和嵌入图像不变，三处编号保持原样，两页表格及派生图仍可编辑。
PPTX结构和布局检查均exit0、0 finding，PowerPoint文字宽高检查0溢出，两页PNG均已视觉检查。
未重跑板测/RTL，未验证其他Office/WPS/印刷。
临时脚本和JSON位于本地忽略目录 `build/tmp/poster_puf3_data_20261101/`（既有脚本未修改），不是交付依赖。

PPTX SHA-256：`d7b6ef1f8110e09c96ebaca295da3b46f25ae3bf058f63b727f716475ced4f70`。

D03仅海报子项完成，整体材料状态保持in_progress；下一接收D06材料归档，owner TBD。
