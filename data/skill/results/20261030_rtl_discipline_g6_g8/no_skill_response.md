# counter8 RTL 说明

## 寄存器清单

| 寄存器 | 宽度 | 时钟 | 复位 | 作用 |
|---|---:|---|---|---|
| `count` | 8 bit | `clk` 上升沿 | 同步低有效 `rst_n` | 输出计数状态，也是模块唯一的状态寄存器 |

模块不增加流水级、辅助状态或额外计数器。

## 下一值选择与优先级推导

设 `N` 为每个 `clk` 上升沿要装入 `count` 的下一值。按题目给定优先级从高到低判断：

| 优先级 | 条件 | 下一值 `N` | 推导结果 |
|---:|---|---|---|
| 1 | `rst_n == 0` | `8'h00` | 同步复位覆盖所有其他输入 |
| 2 | `rst_n == 1 && clear` | `8'h00` | `clear` 覆盖 `load` 和 `enable` |
| 3 | `rst_n == 1 && !clear && load` | `load_data` | `load` 覆盖 `enable` |
| 4 | `rst_n == 1 && !clear && !load && enable` | `count + 8'h01` | 递增；8 位结果在 255 后自然回绕到 0 |
| 5 | 其他情况 | `count` | 保持当前值 |

对应的选择式为：

```text
N = !rst_n                         ? 8'h00
  : clear                          ? 8'h00
  : load                           ? load_data
  : enable                         ? (count + 8'h01)
  :                                  count
```

## 可编译 Verilog

```verilog
module counter8 (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       clear,
    input  wire       enable,
    input  wire       load,
    input  wire [7:0] load_data,
    output reg  [7:0] count
);

    always @(posedge clk) begin
        if (!rst_n) begin
            count <= 8'h00;
        end else if (clear) begin
            count <= 8'h00;
        end else if (load) begin
            count <= load_data;
        end else if (enable) begin
            count <= count + 8'h01;
        end
    end

endmodule
```

## 假设

1. 所有端口都是同步接口；仅在 `clk` 上升沿采样 `rst_n`、`clear`、`load`、`enable` 和 `load_data`。
2. `rst_n` 是同步低有效复位，不进入敏感列表；`rst_n` 拉低后，状态在下一个上升沿清零。
3. 输入同时有效时严格采用 `rst_n > clear > load > enable` 的优先级。
4. `load == 0` 时 `load_data` 的值无关；`load == 1` 时，采样值应满足宿主系统的建立/保持时间要求。
5. 模块在第一次同步复位或第一次同步 `clear`/`load` 前不定义上电初值；系统必须在正常计数前执行一次同步复位。
6. 递增使用 8 位加法，因此 `8'hFF + 8'h01` 的结果为 `8'h00`。

## 验证计划

验证时应使用非零、互不相同的 `load_data`（例如 `8'hA5`），以区分 `clear`、`load` 和复位结果。全部检查在上升沿后的稳定时刻采样，避免与寄存器更新竞争。

### 编译和结构检查

1. 使用 Verilog 编译器检查模块可无错误编译。
2. 使用 lint 检查端口方向、位宽以及“恰好一个时钟进程”的约束。
3. 确认 `count[7:0]` 是唯一的状态寄存器，没有附加流水级或辅助状态。

### 控制组合

穷举 `{rst_n, clear, load, enable}` 的 16 种输入组合：

- `rst_n == 0` 的 8 种组合：无论 `clear/load/enable` 为何，均检查下一拍 `count == 0`。
- `rst_n == 1, clear == 1` 的 4 种组合：均检查下一拍 `count == 0`。
- `rst_n == 1, clear == 0, load == 1` 的 2 种组合：均检查下一拍 `count == load_data`，包括 `enable == 1`。
- `rst_n == 1, clear == 0, load == 0, enable == 1`：检查下一拍递增 1。
- `rst_n == 1, clear == 0, load == 0, enable == 0`：检查保持。

### 定向边界用例

1. **复位优先级**：先装入非零计数，再令 `rst_n=0, clear=1, load=1, enable=1`；下一拍应为 `0`。
2. **clear 与 load 同时为 1**：从非零计数出发，令 `clear=1, load=1`；下一拍应为 `0`，不能装入 `load_data`。
3. **clear 与 enable 同时为 1**：下一拍应为 `0`，不能递增。
4. **load 与 enable 同时为 1**：下一拍应等于 `load_data`，不能递增。
5. **255 回绕**：通过 `load` 装入 `8'hFF`，随后令 `enable=1, load=0`；下一拍应为 `8'h00`。
6. **保持**：在 `8'h00`、中间值和 `8'hFF` 分别令 `clear=load=enable=0` 保持多个周期，检查值不变。
7. **连续 load**：在相邻上升沿连续装入至少三个不同值（如 `8'hA5`、`8'h3C`、`8'hFF`），每个上升沿后检查对应值；可额外在 `enable=1` 时重复，以确认 `load` 优先。

