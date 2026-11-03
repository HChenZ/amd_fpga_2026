# LaTeX 工程（由 build_latex.py 生成）

正文来自 `src/*.md` 和 `src_template/new/*.md`，重排后由 `src_template/*.md` 生成。
**不要直接改 `chapters/*.tex`**。从仓库根运行完整入口：

```bash
python -X utf8 docs/tech_report/build_report.py
```

## 编译

- **Overleaf**：新建项目，上传本目录全部文件（含 chapters/），主文件设为 `main.tex`，
  编译器选 **XeLaTeX**。中文字体使用 TeX Live 自带 fandol，无需本地字体。
- **本地**：需 XeLaTeX（TeX Live / MiKTeX，含 ctex 宏包）。

```bash
bash build.sh          # 或 PowerShell: ./build.ps1
```

## 结构

| 文件 | 说明 |
|---|---|
| `main.tex` | 主文件：封面、目录、章节 include |
| `preamble.tex` | 导言区：宏包、字体、标记宏、图占位宏、代码块环境 |
| `chapters/ch01..ch09` | 摘要、作品概要、正文第 1–9 章 |
| `chapters/app01..app04` | 附录 A（术语）、B（地址与编码）、C（证据索引）、D（参考文献） |

## 已编译验证

本工程已用 XeLaTeX（Tectonic 0.15 便携版，TeX Live 2025 包集）实际编译通过：
**62 页、0 error、0 缺字（Missing character）**，仅余少量 1–5 pt 的 overfull 提示（表格单元格边界）。
编译产物 `main.pdf` 随工程提供，可用于对照。

Overleaf 编译注意：主文件 `main.tex`、编译器选 **XeLaTeX**；中文字体走 `ctex` 自带的 fandol，
无需上传字体。若本地装了 TeX Live/MiKTeX，直接 `bash build.sh`。

## 未做的事（下一版）

1. 图仍为占位框：`\figplaceholder` 共 14 处，待替换为 TikZ / pgfplots / 实拍；
2. 尚未按《技术报告模板》五部分重排（当前按 9 章正文，映射见"作品概要"一节）；
3. 页眉已按模板放置赛题标志（`header_logo.png`，居中，宽 6.5 cm），页码居中于页脚；图表编号格式待按模板微调。
