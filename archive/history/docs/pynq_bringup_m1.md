# M1 起板：从镜像写卡到 PYNQ 网络起来（纯 GUI 分步）

> 2026-11-01 范围：这是板卡 PYNQ 2.7 镜像/网络起板步骤，不是加载 PUF3 或旧 v1 的专用操作。
> 后续已在该平台运行 PUF3；具体 overlay、固件身份和 Notebook 按 version_entrypoints.md 选择。

2026-10-28 目标，owner TBD。所有操作由用户本人点，本文件只给步骤与要留的证据。
镜像：`E:\...\正点原子领航者(V2)ZYNQ开发板资料盘(A盘)\4_Source_Code\5_PYNQ_Design\IMG\ZYNQ-7020-2.7.0.zip`
（1,869,237,643 B；解压后约 8.09 GB，需 ≥16 GB TF 卡）。
文档依据：`2_文档教程\5_【正点原子】领航者ZYNQ_PYNQ开发指南_v3.2.pdf` §2.2–2.3（p19–23）。

---

## 0. 准备（5 分钟）

1. TF 卡：≥16 GB（8 GB 镜像 + 余量），先备份卡内原有内容。
2. 读卡器插电脑，记下盘符（例如 `F:`）。**写卡会清空整卡**，确认盘符别选成移动硬盘。
3. 解压：右键 ZIP → 用 **7-Zip → Extract to "ZYNQ-7020-2.7.0\"**（Windows 自带解压对 8 GB
   的 `.img` 可能失败）。解压目录里应有单个 `.img`，右键属性确认大小 ≈ 8.09 GB。
4. 装 USB 串口驱动（板载 CH340/CP210x，看设备管理器 COM 口是否出现）。

## 1. 写卡（GUI）

1. 打开 **balenaEtcher**（或 Win32DiskImager）。
2. Etcher：**Flash from file** → 选第 0 步解压出的 `.img`。
   或 Win32DiskImager：Image File 选 `.img`，Device 选卡盘符。
3. **Select target** → 选 TF 卡盘符（核对容量，别选错）。
4. **Flash!** → 等校验完成（约 10–20 分钟）→ 看到 `Flash Complete!` 再拔卡。
5. 把卡插回板子（**断电插卡**）。

## 2. 跳线与启动（断电操作）

1. 底板 **P5** 跳线帽：接 **1-3 / 2-4**（PS 串口）。**不要**同时桥 3-5/4-6（PL 串口），
   两套不能同时桥接。
2. 启动模式拨码开关：拨到 **SD 卡启动**（见开发指南 §2.3 图示；拨码标签以底板丝印为准）。
3. USB 线：板子的 **USB-UART** 口 → 电脑；网线：板子 **PS 网口（ENET0）** → 路由器/交换机。
4. 先开串口助手（XCOM / MobaXterm）：波特率 **115200**、8 数据位、无校验、1 停止位、
   无流控，选对应 COM 口，**先打开串口再上电**（可完整抓到 boot log）。
5. 上电（12V DC）。串口应出现 U-Boot → kernel 日志。

## 3. 登录与取证（串口控制台）

登录：用户名 `xilinx`，密码 `xilinx`（厂家镜像通常如此；不对就看开发指南 §2.3 的登录信息）。

逐条执行并**把输出整段存下来**（XCOM 右键"保存窗口"存 .txt，或用 MobaXterm 的 logging）：

```sh
uname -a
cat /etc/issue
python3 --version
python3 -c "import pynq; print('pynq', pynq.__version__)"
ip a
df -h
lsblk
ls /sys/class/fpga_manager/ 2>/dev/null
dmesg | head -80
```

判定标准（M1 通过条件）：

| 项 | 通过条件 |
|---|---|
| boot | 串口有完整 boot 输出，最后出现 login 提示 |
| PYNQ | `import pynq` 成功并打印版本（PYNQ 2.7 期望 2.7） |
| 内核 | `uname -a` 有输出（指南描述 5.4.x，以实际为准并记录） |
| 网络 | `ip a` 里 eth0 有 IPv4；记下地址 |
| 存储 | `df -h` 里根分区已扩展到整卡（或至少 ≥6 GB 可用） |
| fpga_manager | `/sys/class/fpga_manager/` 存在（PYNQ 装载 overlay 的底层） |

## 4. Jupyter（浏览器）

1. 在电脑浏览器打开 `http://<第 3 步记下的 IP>:9090`；
   若打不开，先试厂家默认 `http://192.168.2.99:9090`（PYNQ 静态默认地址）。
2. 密码：`xilinx`（PYNQ 默认）。
3. 新建 notebook，跑一行验证：

```python
from pynq import Overlay
print(Overlay)
import pynq, platform
print(pynq.__version__, platform.platform())
```

能打印出类与版本即 M1 的"PYNQ 可用"部分达成。**M1 不加载我们的 overlay**
（M2 才有 bit/hwh）。

## 5. 要交的证据文件（放到 `data/pynq/` 下）

| 文件 | 内容 | 来源 |
|---|---|---|
| `boot_20261028.log` | 上电到 login 的完整串口输出 | XCOM/MobaXterm 保存 |
| `env_20261028.txt` | 第 3 步 9 条命令的原始输出 | 串口复制 |
| `jupyter_20261028.png` | 浏览器里 notebook 打印 pynq 版本的截图 | 截图 |
| `notes.md` | 镜像 ZIP 的 sha256、TF 卡型号/容量、板子丝印、P1 跳线实际位置、IP | 手工 |

镜像 sha256 可在电脑上算（PowerShell 或 `certutil -hashfile <zip> SHA256`），
写进 `notes.md`，与 `board/atk_navigator_7020/vendor_sources.json` 里的记录对照。

## 6. 常见坑（都踩过或已确认）

- **P5 双桥接**会让 PS 和 PL 抢同一个 USB-UART，表现是启动日志乱码或完全无输出。
- 串口无输出先查：SD 卡是否插好、拨码是否在 SD 启动、波特率是否 115200、TX/RX 是否插反。
- 开发指南写的是 "UART1"，实际是 **PS UART0 走 MIO14-15**（见
  `board/atk_navigator_7020/vendor_findings.md`）——板子网口/丝印命名不代表要改 PS 配置。
- 我们用的是**厂家自己的 7020 PYNQ 移植镜像**，不是 PYNQ-Z2 板；
  不要照抄官方 PYNQ-Z2 base overlay 的 MIO/时钟配置。
- 8 GB 镜像 + Windows 自带解压容易失败，用 7-Zip。
- 网络不通时先看路由器 DHCP 列表里是否出现新设备；板子若是静态 192.168.2.99，
  需要把电脑网口也配成 192.168.2.x/24 才能直连。

## 7. M1 之后的下一步

M1 通过后按 `board/vivado_zynq7000_xc7z020_pynq/readme.md` §6 建 overlay 工程（M2）。
M2 的验收命令（在板子上跑）：

```sh
python3 src/pynq/make_pynq_profile.py --hwh ... --bit ... --firmware ... \
        --firmware-id pynq-svc-v1 --out pynq_profile.json
```

（具体参数见该 readme；`validate_overlay: PASS` 才算 M2 的地址一致性通过。）

> 本文件里所有 M1 项目前都是 **NOT_RUN**：镜像已就位，但写卡/启动/网络是板级操作，
> 由用户执行后按 §5 交付证据，才能把 B03 的"PYNQ 平台/镜像"项关掉。
