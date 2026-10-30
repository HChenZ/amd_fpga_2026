---
name: pynq-style-notes
description: "Use when writing PYNQ host-side Python: code style, naming, docstrings, logging and project layout conventions for Notebook and script code on Zynq boards."
---

# PYNQ 主机代码风格约定（对照组 Skill）

本 Skill 只规定代码风格与组织方式，不涉及硬件行为。

## 1. 文件与模块组织

- 一个 overlay 对应一个 Python 包；Notebook 只做演示，逻辑放在 `.py` 模块中，便于复用与评审。
- 模块顶部依次为：模块 docstring、标准库导入、第三方导入、本地导入，各组之间空一行。
- 常量全部大写并集中放在模块顶部；不要在函数体中定义常量。
- 公共函数放在文件上部，私有辅助函数（以下划线开头）放在下部。

## 2. 命名

- 函数与变量使用 `snake_case`，类使用 `CapWords`，常量使用 `UPPER_CASE`。
- 名字表达含义而不是类型：用 `sample_count` 而不是 `n_int`；用 `result_bytes` 而不是 `tmp`。
- 布尔变量用 `is_`/`has_`/`should_` 前缀。
- 避免单字母变量，循环下标 `i`、`j` 除外。

## 3. 文档字符串与注释

- 每个公共函数写 docstring：一句话摘要、参数、返回值、可能抛出的异常。
- 注释解释"为什么"，而不是复述代码在做什么。
- 不保留被注释掉的旧代码；需要时从版本控制中找回。

## 4. 类型标注

- 公共函数的参数与返回值写类型标注；复杂类型使用 `typing` 中的别名并起有意义的名字。
- 对外暴露的数据结构优先使用 `dataclasses.dataclass`。

## 5. 日志与输出

- 使用 `logging` 而不是 `print`；模块内 `logger = logging.getLogger(__name__)`。
- 日志级别：调试细节用 DEBUG，流程节点用 INFO，可恢复问题用 WARNING，失败用 ERROR。
- 日志消息使用参数化格式：`logger.info("loaded %s", name)`，不要预先拼接字符串。

## 6. 异常

- 抛出语义明确的异常类型，并在消息中带上关键参数值。
- 不要使用裸 `except:`；捕获后若不能处理，应重新抛出。
- 自定义异常继承自合适的内置异常，并以 `Error` 结尾。

## 7. 函数设计

- 一个函数只做一件事；超过约 40 行时考虑拆分。
- 参数超过 4 个时考虑使用关键字参数或配置对象。
- 避免可变默认参数（如 `def f(x=[])`）。

## 8. Notebook 习惯

- 第一格写清目的、依赖与运行顺序；每格保持短小。
- 运行前 "Restart & Run All" 确认可以从头执行。
- 输出较长时只展示摘要，详细数据写入文件。

## 9. 格式

- 遵循 PEP 8；行宽不超过 100 字符；使用 4 个空格缩进。
- 提交前运行格式化工具与静态检查（例如 `black`、`ruff`）。
