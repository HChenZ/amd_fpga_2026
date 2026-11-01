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

- 周期/加速比：[原始 benchmark](../../data/pynq/notebook_20261031_112052/pynq_warm_benchmark.json)。KAT #529，PT=16 B、AD=0，预热5次，每档30次采样，中位数。
- 三模式各289组 KAT 与坏 Tag：[smoke](../../data/pynq/notebook_20261031_112052/pynq_board_smoke.json)。
- 9项错误门禁/7次恢复：[error gate](../../data/pynq/error_gate_20261031_112812/pynq_board_error_gate.json)。
- 架构、ISE、资源/时序：[技术报告](../../docs/tech_report/report.md)及其原始报告摘录。
- Skill L3：[汇总](../../data/skill/l3_20261031_063709/40_summary.json)。右上实物照片来自 `docs/tech_report/figs/board_photo.jpg`。

左侧为项目已有的Device DNA与RO-PUF密钥派生通路：128-bit PUF响应和57-bit器件标识
与固定上下文组成输入，经Ascon P12派生128-bit key。依据技术报告§2.3.4及
`src/rtl/keys/puf_key.v`、`device_dna.v`。两者是独立输入，DNA非秘密。
图示为PUF参与的正常派生路径；DNA-only回退未展开，不提供秘密密钥保证。
这是独立扩展原型，跨上电稳定性、密钥保密隔离及RO域时序尚未验收，不混入右侧主线benchmark。

CPU `mcycle` 不含 PS/UART；100 MHz 是主线配置，主线独立频率与跨上电稳定性为
`not_measured`。独立 PUF 结果未混入主线。逐项来源也写入两页备注。

## 验证

PowerPoint 16.0 保存及渲染，Python 3.14.3 ZIP/XML/原始数据通用核验51项 PASS；未改动区域/新图专项核对157项 PASS。
除左侧图示/图注和备注外，其他原有图形的XML与改前完全一致。
两页数据一致、三处列表逐项编号，各有可编辑派生图、表格及官方校徽；PPTX结构和布局检查均exit 0、0 finding，
PowerPoint文字高度检查0溢出，两页PNG均已视觉检查。未重跑板测/RTL，未验证其他Office/WPS/印刷。
临时脚本和JSON位于本地忽略目录 `build/tmp/poster_dna_20261101/`（既有脚本未修改，前版记录仍保留本地），不是交付依赖。

PPTX SHA-256：`fe0f7ccdb4d92dfe1176b6d646f7cc521c1b4d07e1a4d03a9b16f9c4e395e465`。

D03仅海报子项完成，整体材料状态保持in_progress；下一接收D06材料归档，owner TBD。
