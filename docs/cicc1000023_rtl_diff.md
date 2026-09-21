# CICC1000023 RTL 逐文件比较

日期：2026-09-21。ZIP SHA-256：`f86c448e8923c6ddde4bca6f276f48ef00828af0849d4b5b28af85c95058af60`。

比较 ZIP 工程的 `riscv_vivado_project.srcs/sources_1/imports/rtl/` 与本轮开始时仓库 `src/rtl/`，不以另一个软件资料目录替代工程 imports。当前开发 RTL 没有被覆盖。

## 结论

- ZIP imports 有 31 个 Verilog/header 文件；仓库递归有 33 个。
- **14 identical、17 modified_eol_only、0 modified_content、0 zip_only、2 repo_only**。
- modified_eol_only 表示原始 SHA-256 确实不同，但仅将 CRLF 转为 LF 后字节完全相同；不是忽略空白或注释后才相同。
- 31 个共有文件的规范化内容 unified diff 全为空；不宣称某份更“新”或更“正确”。
- 仅仓库有 `ascon/ascon_round.v` 和 `ascon/ascon_word.v`，不能自动并入历史 baseline。

## 重点模块

cpu_core.v、csr_file.v、cpi_cnt.v、defines.v、cpu_axi_bridge.v、axi_full_master.v 字节完全一致。icache.v、dcache.v、bus_interconnect.v、top.v、top_pl_bram.v 仅换行差异，无逻辑文本差异。其他文件逐行结论见下表。

## 文件、SHA-256 与内容 diff

| file | classification | ZIP SHA-256 | repo SHA-256 | content diff（CRLF→LF 后） |
|---|---|---|---|---|
| `ascon/ascon_round.v` | repo_only | `-` | `0c04effa44590673ae048d958d0b65887e0eb33b0cfe4b5ec80dc58115a657be` | 不适用：单边文件 |
| `ascon/ascon_word.v` | repo_only | `-` | `daea6ac80b1e8a8f20f15c3eb8696eba4a58671f6939378a41909413d703f51b` | 不适用：单边文件 |
| `axi_full_master.v` | identical | `7130b046b3e9074a5dab20099a5c49aa49c5b6ddd24bb9e67b261ea2153b1dd5` | `7130b046b3e9074a5dab20099a5c49aa49c5b6ddd24bb9e67b261ea2153b1dd5` | 空，0 行差异 |
| `branch_predictor.v` | identical | `c8e9c26c8f74ff6d7f11046e6a2b36a5b6cd84fc0196eab806790da8e6da9df1` | `c8e9c26c8f74ff6d7f11046e6a2b36a5b6cd84fc0196eab806790da8e6da9df1` | 空，0 行差异 |
| `bus_interconnect.v` | modified_eol_only | `75f2958f1157ca034392367f4ca88ef0bae6ef4c76ab923225542e719ecc8664` | `a0c8a1d52b4247e422a034297a1e653423abd2086a605e6b8b267d8348b04365` | 空，0 行差异 |
| `bypass.v` | modified_eol_only | `875eb4cf57e91113475ef32cd505128a7952131a06973e55f724e9c7bf88dc73` | `31796dd4efa681cd72057f39d9ee5fc2aa4b9a9bfd6f72c402469c740f1cecf5` | 空，0 行差异 |
| `clint.v` | modified_eol_only | `eb7ea2708da7a8e9b9cc0f2fbbf91172a36ca477427fad56bdd963458333571e` | `539b86f859db13e08a5923832ff7443ec272eeaf17f0872365a8da7b653db95c` | 空，0 行差异 |
| `cpi_cnt.v` | identical | `01a7e126bdbdb481bf3301aa350457996976690a58ab303312435db63d3f06de` | `01a7e126bdbdb481bf3301aa350457996976690a58ab303312435db63d3f06de` | 空，0 行差异 |
| `cpu_axi_bridge.v` | identical | `1c08e8ca0a7588ebbfa9938d304172c4bade8ad6fab4ca9fdac10bcb51547987` | `1c08e8ca0a7588ebbfa9938d304172c4bade8ad6fab4ca9fdac10bcb51547987` | 空，0 行差异 |
| `cpu_core.v` | identical | `ccc51a554da4abc3e44d779a68e842f30db7310ae0ce3c914b5dd40f27cb3b67` | `ccc51a554da4abc3e44d779a68e842f30db7310ae0ce3c914b5dd40f27cb3b67` | 空，0 行差异 |
| `csr_file.v` | identical | `b017d3f876957fa5818a3fdbb5f6c1fb6682b8f4f2b67c85973afe7e49838c49` | `b017d3f876957fa5818a3fdbb5f6c1fb6682b8f4f2b67c85973afe7e49838c49` | 空，0 行差异 |
| `ctrl.v` | modified_eol_only | `3e6c20faaf405549dc0be6d9da45dba39889b9e089d1e4cce1109ce0ecc26cfc` | `b6f4eef20b1e1c2394c5d6c48cd121e6943224f06d751bc7b2bf6b794a0cb559` | 空，0 行差异 |
| `dcache.v` | modified_eol_only | `bb1b4b5c412f97ba290cb568514d55ffc03a74d3ca2accda7f5354f13eb096f9` | `5532245684c1ccabef440d105dda66f44fb8e5b4a522589740bbe7269924dc11` | 空，0 行差异 |
| `defines.v` | identical | `c8958c2f2523ec73980c74de726728d1da4e473137d43077812ebb24bb056e80` | `c8958c2f2523ec73980c74de726728d1da4e473137d43077812ebb24bb056e80` | 空，0 行差异 |
| `divider.v` | identical | `1b553787ab718b493cf89cbc3cb817f28b06104851920e2cf2fe610aafa5b32a` | `1b553787ab718b493cf89cbc3cb817f28b06104851920e2cf2fe610aafa5b32a` | 空，0 行差异 |
| `ex_mem.v` | modified_eol_only | `313da15f51d4c55cf72bd6ab338598d38bf9ad11957849537925cb14dd3a0bc7` | `d656b3387ca73ce2e4d9eb4e01f1503fe8a91c05f9f70fd054c69a9b6fddd7e6` | 空，0 行差异 |
| `ex_stage.v` | modified_eol_only | `fb5eb5cbf8d2c1ce977a8f17769158a6b1c182eaba2ed552fb9592f1d4a8446f` | `34061bbba1caab321390067af9b01ad8fddf18f8b0532245ec72fd96edd9cfdf` | 空，0 行差异 |
| `gpio.v` | identical | `9bc51017dc6e1d280125a59bcc9d0b095b25c6746438f9107d835d403da0af5b` | `9bc51017dc6e1d280125a59bcc9d0b095b25c6746438f9107d835d403da0af5b` | 空，0 行差异 |
| `icache.v` | modified_eol_only | `23bd25cc39dd4e9c874d81519baeee69ee6b98362f4bd6364cac722c17bc739d` | `ab2001b57bac463f168714a7843f07330c2072f91d1c80ec0014fbf4f9dc988f` | 空，0 行差异 |
| `id_ex.v` | modified_eol_only | `02181503d8393021726584bf8291a3cc926e7cb84b19e80fc5c98475c84d1522` | `7588b49e7a4b12d61ee933f73fda8136f902c578cf7cf809c31e540efac9ca84` | 空，0 行差异 |
| `id_stage.v` | identical | `e7cc97c530ba792549070a200c0056b625e872de81aefbaefea1dc677e267310` | `e7cc97c530ba792549070a200c0056b625e872de81aefbaefea1dc677e267310` | 空，0 行差异 |
| `if_id.v` | modified_eol_only | `4e518476292891d49b8c0f2bed22339f283c94f171cb52a85e85b484fd1ad8e9` | `a9df4d2c0ee14fa70e166459caee4b68cf0f491888c3d2bc29c4dbff042468ce` | 空，0 行差异 |
| `if_stage.v` | identical | `e2770b86300b4209dda7ed9673c976ff2efbe7ecabf120b32458bfcc8400a0cb` | `e2770b86300b4209dda7ed9673c976ff2efbe7ecabf120b32458bfcc8400a0cb` | 空，0 行差异 |
| `mem_stage.v` | modified_eol_only | `c9f69c52cbb4f869514ad29af774d933fdab06248e1bdfab85664ff523902a34` | `9afab521420ad1a6241b571a61269ee4774b87f55fbcf63af0601b616ff26317` | 空，0 行差异 |
| `mem_wb.v` | identical | `26a5880c73a089249c6278cb8b93b1db6d23ec0f02c2fd8ecfcf1cc4e58e6e10` | `26a5880c73a089249c6278cb8b93b1db6d23ec0f02c2fd8ecfcf1cc4e58e6e10` | 空，0 行差异 |
| `mult.v` | modified_eol_only | `561c91867f1793cbb8993b32b7ea4c90eb0f69f41e23a7bf34ced8d41fb3e855` | `dcff59d086098167667f2365364743b26c1dad82fd7544be616fd0eb3ae0a904` | 空，0 行差异 |
| `regfile.v` | identical | `5aacf513bb2db596afebe3428ff472c1639d7369769c718a3af64a6d19cfca69` | `5aacf513bb2db596afebe3428ff472c1639d7369769c718a3af64a6d19cfca69` | 空，0 行差异 |
| `soc_top.v` | modified_eol_only | `8d9490895f96c4870cf66cb40f405a07a8b101ad7af03fe714420f83df200e5c` | `623cc69b19d26533fbfc952fea2ccaa95304b1be4d08b80ebe0c3222c9dfc91f` | 空，0 行差异 |
| `top.v` | modified_eol_only | `7a84cdc42c7d58168b3825820a10fb2c71221929d13ab0444b6edac5465559e3` | `37405e5d5b8f5f5b565499264fac463d7346ee9561ad0b0cbae39ab461229dc2` | 空，0 行差异 |
| `top_pl_bram.v` | modified_eol_only | `f33c9a5c6d26b84375d8f46b852299d42b38ad23f11bd3ab58f03c759ebd63e7` | `6098a6f7056fad1fe8275df55e53ef15bbf448e4756e89037ad4a522c7d1fc31` | 空，0 行差异 |
| `uart_ctrl.v` | modified_eol_only | `554a3d740edf5b86d87896d7810fc88c367e7221b292a805cfb579415befa588` | `c9a0bba23e8d23c528ba9c7e7e4063624216a1085634aa36c677f534f631a5bc` | 空，0 行差异 |
| `uart_rx.v` | identical | `b2de3abd1e006c8f3bef4cfd55e8a9cce96606ddbf10a3a13fd17f4dbb697a40` | `b2de3abd1e006c8f3bef4cfd55e8a9cce96606ddbf10a3a13fd17f4dbb697a40` | 空，0 行差异 |
| `uart_tx.v` | modified_eol_only | `e7c68a3718658a32efc3cb3879de3a7d143b22ca2235c35e3afaefccec3e7c47` | `3e72b58918843c2a57b10b8b52456c4a9f8e0102a7ceee6e0d79b73a7f370c1d` | 空，0 行差异 |

## 原始字节与换行差异

CRLF/LF-only 以字节计数；不改变任何原文件换行。

| file | ZIP bytes | repo bytes | ZIP CRLF / LF-only | repo CRLF / LF-only |
|---|---:|---:|---|---|
| `bus_interconnect.v` | 14745 | 15222 | 0 / 477 | 477 / 0 |
| `bypass.v` | 945 | 988 | 0 / 43 | 43 / 0 |
| `clint.v` | 4446 | 4469 | 106 / 23 | 129 / 0 |
| `ctrl.v` | 4613 | 4624 | 124 / 11 | 135 / 0 |
| `dcache.v` | 16664 | 17130 | 0 / 466 | 466 / 0 |
| `ex_mem.v` | 2654 | 2754 | 0 / 100 | 100 / 0 |
| `ex_stage.v` | 18323 | 18328 | 530 / 5 | 535 / 0 |
| `icache.v` | 10936 | 11226 | 0 / 290 | 290 / 0 |
| `id_ex.v` | 6205 | 6210 | 190 / 5 | 195 / 0 |
| `if_id.v` | 3597 | 3664 | 59 / 67 | 126 / 0 |
| `mem_stage.v` | 4468 | 4591 | 0 / 123 | 123 / 0 |
| `mult.v` | 2076 | 2148 | 0 / 72 | 72 / 0 |
| `soc_top.v` | 16336 | 16844 | 0 / 508 | 508 / 0 |
| `top.v` | 4510 | 4651 | 0 / 141 | 141 / 0 |
| `top_pl_bram.v` | 6589 | 6813 | 0 / 224 | 224 / 0 |
| `uart_ctrl.v` | 6774 | 7014 | 0 / 240 | 240 / 0 |
| `uart_tx.v` | 2300 | 2391 | 0 / 91 | 91 / 0 |

完整机读结果：[rtl_comparison.json](../data/recovery/cicc1000023/rtl_comparison.json)。原始大小、每份哈希和逐文件规范化 unified diff 均保留。

补充检查：ZIP 的 `rtl源代码/Verilog设计代码/` 另有同名 31 文件，CRLF→LF 后也与工程 imports 一致；没有用该副本替换 imports。上述事实不决定后续开发版本选择，也不代替功能验证。
