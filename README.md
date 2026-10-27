# KU5P_FX_Accelerator

基于 AMD Kintex UltraScale+ **XCKU5P** 的 FPGA 加速卡开发仓库。

卡片插在主机 PCIe 插槽上，通过 PCIe DMA 与主机交互；FPGA 侧无 ARM 核，因此不涉及
PetaLinux / Vitis 嵌入式流程，全部逻辑在 Vivado 中完成。

## 快速索引

| 文档 | 内容 |
|---|---|
| [docs/hardware.md](docs/hardware.md) | 板卡规格、接口、待确认项 |
| [docs/environment.md](docs/environment.md) | 已验证的开发机与工具链状态 |
| [docs/workflow.md](docs/workflow.md) | 仓库约定、分支与提交规范、构建方式 |

## 技术栈

- **器件**: XCKU5P (Kintex UltraScale+)，36 个可用 part（`xcku5p-ffva676-*` / `xcku5p-sfva784-*`）
- **工具**: Vivado 2026.1（BASIC 授权已验证覆盖 xcku5p，可产出 bitstream）
- **主机交互**: PCIe + DMA（IP 选型见 docs/hardware.md）
- **主机侧**: Windows 为主（Linux 驱动路线待评估，见 docs/workflow.md）
- **下载/调试**: Digilent JTAG + Vivado Hardware Manager / ILA

## 目录结构

```
.
├─ rtl/                 # 设计源码（Verilog/SystemVerilog）
├─ tcl/                 # 构建脚本（工程创建、综合、实现、bitstream）
├─ docs/                # 硬件与环境的说明文档
├─ scripts/             # 主机侧脚本（后续加入）
└─ README.md
```

构建产物（`.Xil/`、`*.dcp`、`*.bit`、`*.rpt`、Vivado 工程目录等）不入库，见 `.gitignore`。

## 构建

```powershell
# 用法: <part> <top> [工程目录]
D:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat -mode batch `
  -source tcl/build.tcl -tclargs xcku5p-ffva676-1-i top D:\work\ku5p_build
```

脚本会依次执行 synth → opt → place → route → write_bitstream，并把报告写到工程目录下。

仓库自带一个无 IO 的最小设计 `rtl/example_top.v`（用 STARTUPE3 的 CFGMCLK 当时钟），
可直接用上面的命令验证环境是否完好，不需要板卡引脚信息。

## 状态

- [x] 开发环境就绪（Vivado 2026.1 + BASIC license + JTAG）
- [x] JTAG 识别到 `xcku5p_0`
- [x] 最小设计全流程（到 bitgen）验证通过
- [ ] 板卡具体规格补齐（见 docs/hardware.md 的 TODO）
- [ ] PCIe DMA 通路打通，卡片在主机侧可枚举
- [ ] 主机侧驱动 / 用户态 API
