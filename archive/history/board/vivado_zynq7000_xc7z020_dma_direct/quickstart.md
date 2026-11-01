# HW_DIRECT candidate: board execution handoff

All board actions below are **NOT_RUN** in this workspace. Original release is
unchanged. This candidate does not contain the RISC-V CPU: mode4 is a direct PL
AEAD datapath with PL computation cycles, not an ISE benchmark.

Candidate directory:
`data/advanced/dma_direct/vivado_20261030_024214/candidate/`

| File | SHA-256 |
|---|---|
| dma_direct.bit | 1f37855208d7e5b8af79501f7b54bc3722c39c21798859e19e0fc953c0d01896 |
| dma_direct.hwh | f3731a00255ea729beca9ce79aa54789b7b59542f6383f02700f21d81d360c41 |

The generated HWH exposes `engine` at0x40000000 and `dma` at0x40400000.
It advertises mode4 only, data/AD1024B each. Clock is configured100MHz; physical
frequency and real PS HP0/DDR/cache behavior still need board verification.

Copy the repository source plus both candidate files to the board. From its
repository root, with the normal board PYNQ2.7 environment and hardware privileges:

```sh
sudo -E python3 board/vivado_zynq7000_xc7z020_pynq_dma_cpu/bringup.py \
  --bit data/advanced/dma_direct/vivado_20261030_024214/candidate/dma_direct.bit \
  --hwh data/advanced/dma_direct/vivado_20261030_024214/candidate/dma_direct.hwh \
  --bit-sha256 1f37855208d7e5b8af79501f7b54bc3722c39c21798859e19e0fc953c0d01896 \
  --hwh-sha256 f3731a00255ea729beca9ce79aa54789b7b59542f6383f02700f21d81d360c41 \
  --download --control-ip engine --dma-ip dma --modes 4 --smoke \
  --output data/advanced/dma_direct/board_smoke.json
```

After smoke passes, use a **new output file** and `--full` for1089 official cases;
then `--benchmark 30 --message-bytes 1024 --ad-bytes 0` for supported long-message
measurement. Keep16B/AD0 comparison separate and retain all raw samples.
Do not claim full KAT alone measures random-key/nonce behavior or sustained bandwidth.

No `--firmware` is needed for mode4. CPU modes1/2/3 require the distinct CPU-DMA
overlay and its firmware artifact. The tool deliberately does not fall back to a
host model or silently accept an unsupported mode/capacity.

If quiescence fails, preserve the process and its buffers until verified reset;
do not kill the process to fake successful cleanup. Keep the old PYNQ bit/HWH and
board boot setup ready for rollback. Full handling details are in
`docs/advanced_board_handoff.md` and the permanent CLI's `--help`.
