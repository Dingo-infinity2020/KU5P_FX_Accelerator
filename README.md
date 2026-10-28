# KU5P_FX_Accelerator

基于 AMD Kintex UltraScale+ **XCKU5P** 的 FPGA 加速卡开发仓库。

卡片插在主机 PCIe 插槽上，通过 PCIe DMA 与主机交互；FPGA 侧无 ARM 核，因此不涉及
PetaLinux / Vitis 嵌入式流程，全部逻辑在 Vivado 中完成。

当前开始 FPGA 数据处理与学习实现，近期先做 FX 相关器，输出通用复数可见度并为校准提供基础；FFTT 空间变换 demo 保留为长期目标。现有 RFSoC 工程仍输出时域基带。已完成单路功率、两通道 X、双 512 点 FFT-FX，并加入 4 抽头/相位 PFB、计划帧窗口、来源/配置标签与三种有效贡献 W。

第五课 A 已通过当前聊天的 Vivado MCP 完成片内回放的板级实现与真实 FPGA 验证：两次独立抓取各 2048 行，全部 650 位逐行匹配。含 ROM/ILA/VIO 的板级设计使用 9526 LUT、16977 FF、56 DSP、62.5 BRAM36 等效块，10 ns 约束下布线后 WNS=+3.339 ns。RFSoC 暂不可连接时，先推进候选协议测试、PC/ConnectX-5↔KU5P 链路准备与连续处理；当前算术硬件仍为可暂停的合成数据回放。

第五课 D 已完成独立 XDMA 测试端点、仿真、板级布线和 JTAG SRAM 配置。当前 ×4 主机上板 dd 时钟校验/原始 GT power-good 诊断版，WNS=+1.256 ns；四路 raw power-good 为高，但 CPLL/QPLL1 未锁定，GT TX/RX 复位未完成。同域心跳采集严格每 256 点重复，参考路径计数边沿仍不稳定；门控旁路、显式 NORTH 入口和 6 MHz 下载均未修复。Windows 尚未枚举，真实 BAR/DMA 待验收。见[PLL/时钟排查与证据修正](docs/lesson05d-pll-clock.md)、[原 d5 诊断](docs/lesson05d-phy.md)与[训练历史](docs/lesson05d-training.md)。

## 快速索引

完整进度、云端保存范围和重建入口见[2026-10-28 进度快照](docs/progress-2026-10-28.md)。当前 PCIe 尚未建链，不能把源码同步理解为驱动或 DMA 已验收。

| 文档 | 内容 |
|---|---|
| [docs/hardware.md](docs/hardware.md) | 板卡规格、接口、待确认项 |
| [docs/environment.md](docs/environment.md) | 已验证的开发机与工具链状态 |
| [docs/workflow.md](docs/workflow.md) | 仓库约定、分支与提交规范、构建方式 |
| [docs/rfsoc-interface.md](docs/rfsoc-interface.md) | RFSoC 数据源核对、320 MS/s 接口与同步边界、容量影响 |
| [docs/dual-rfsoc-plan.md](docs/dual-rfsoc-plan.md) | 两台 RFSoC、16 路范围、100/320 MS/s 对比与接入路线 |
| [docs/implementation-roadmap.md](docs/implementation-roadmap.md) | 当前实施顺序、学习验收与长期 FFTT 方向 |
| [docs/lesson01-power.md](docs/lesson01-power.md) | 第一课：复数功率/累加、参考值、仿真与综合复现 |
| [docs/lesson02-correlation.md](docs/lesson02-correlation.md) | 第二课：两通道相关、流水线、相位检查及可操作的 Vivado 工程 |
| [docs/lesson03-fft-fx.md](docs/lesson03-fft-fx.md) | 第三课：双 512 点时间 FFT、定点标度、逐频道积分与完整链路验证 |
| [docs/lesson04-pfb-weights.md](docs/lesson04-pfb-weights.md) | 第四课：4 抽头/相位 PFB、计划窗口、有效贡献 W、帧标签与 Vivado 操作 |
| [docs/lesson05-board-replay.md](docs/lesson05-board-replay.md) | 第五课 A：ROM 回放、板级时序、VIO/ILA、两次真实 FPGA 抓取与逐位验收 |
| [docs/lesson05c-pipeline-notes.md](docs/lesson05c-pipeline-notes.md) | 第五课 C：并行 PFB、弹性 FFT 配对、流水 X、帧间重叠与吞吐验证记录 |
| [docs/lesson05d-pcie.md](docs/lesson05d-pcie.md) | 第五课 D：XDMA 测试端点、Windows 用户态程序、板级实现与当前链路观察 |
| [docs/lesson05d-pcie-diagnosis.md](docs/lesson05d-pcie-diagnosis.md) | 管理员重扫后的 d2 诊断：共享参考时钟、GT 状态与重启前后的验收 |
| [docs/lesson05d-pcie-x4.md](docs/lesson05d-pcie-x4.md) | 当前 ×4 主机配置、反序降宽限制、d3 固件与可控复位观察 |
| [docs/lesson05d-training.md](docs/lesson05d-training.md) | d4 一致训练历史、Detect.Quiet 实测、时序/CDC 与后续 GT/PHY 排查 |
| [docs/lesson05d-phy.md](docs/lesson05d-phy.md) | d5 GT/PLL/PHY 实测、默认控制连接、同步修订及 Windows 验收边界 |
| [docs/lesson05d-pll-clock.md](docs/lesson05d-pll-clock.md) | PLL 控制实测、无效证据修正、独立时钟采集/校验与原始 GT power-good 对照 |
| [docs/rfsoc-preparation.md](docs/rfsoc-preparation.md) | RFSoC 接入前：现有光模块/ConnectX-5、PCIe 限制、候选协议工具及分阶段验收 |
| [docs/vivado-first-steps.md](docs/vivado-first-steps.md) | 怎样在 Vivado 中查看本课综合网表、资源和波形 |
| [docs/vivado-mcp.md](docs/vivado-mcp.md) | 本地 Vivado MCP 的安装配置、兼容修正、实测与连接刷新 |

## 技术栈

- **器件**: XCKU5P (Kintex UltraScale+)；第一课已用 `xcku5p-ffvb676-1-i` 独立综合，板级精确料号仍以实物与厂家工程核对
- **工具**: Vivado 2026.1（BASIC 授权已验证覆盖 xcku5p，可产出 bitstream）
- **主机交互**: PCIe + DMA（IP 选型见 docs/hardware.md）
- **主机侧**: 用户已选择继续 Windows；兼容 XDMA 内核驱动待取得，见 docs/workflow.md
- **下载/调试**: Digilent JTAG + Vivado Hardware Manager / ILA

## 目录结构

```
.
├─ rtl/                 # 设计源码（Verilog/SystemVerilog）
├─ tcl/                 # 构建脚本（工程创建、综合、实现、bitstream）
├─ constraints/         # 约束；当前课堂时钟约束不代表板级约束
├─ sim/                 # 自检查仿真 testbench
├─ docs/                # 硬件、学习与验证说明
├─ scripts/             # Python 参考向量与 PowerShell 复现入口
└─ README.md
```

构建产物（`.Xil/`、`*.dcp`、`*.bit`、`*.rpt`、Vivado 工程目录等）不入库，见 `.gitignore`。

## 构建

```powershell
# 用法: <part> <top> [工程目录]
D:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat -mode batch `
  -source tcl/build.tcl -tclargs xcku5p-ffvb676-1-i example_top D:\work\build\KU5P_FX_Accelerator\example_top_xcku5p
```

本地工作区布局见 [docs/workflow.md](docs/workflow.md#本地工作区)。

脚本会依次执行 synth → opt → place → route → write_bitstream，并把报告写到工程目录下。

仓库自带一个无 IO 的最小设计 `rtl/example_top.v`（用 STARTUPE3 的 CFGMCLK 当时钟），
可直接用上面的命令验证环境是否完好，不需要板卡引脚信息。

## 状态

- [x] 开发环境就绪（Vivado 2026.1 + BASIC license + JTAG）
- [x] JTAG 识别到 `xcku5p_0`
- [x] 最小设计全流程（到 bitgen）验证通过
- [x] 第一课复数功率/累加：参考值、RTL 仿真与 KU5P 独立综合
- [x] 第二课两通道 X：两路自相关、复数互相关，仿真、独立综合及可重建 GUI 工程
- [x] 两路 512 点时间 FFT + X：分帧回放、512 频道独立累加、完整仿真与整体独立综合
- [x] Vivado MCP 本地安装、Codex 注册与 MCP 协议/报告/XSIM 验证
- [x] 两路 PFB-FX：滤波/定点定义、计划帧窗口、有效贡献 W、标签检查及完整仿真/独立综合
- [x] 片内回放与板级观察：布局布线、JTAG SRAM 配置、两次完整硬件抓取与参考比较
- [x] 候选 RFSoC 报文的离线生成/解析：正常十六流及重复/乱序/缺口/坏包测试，真实格式待抓包确认
- [x] 两路处理流水线优化的完整数值/协议仿真：226 帧、90 窗口；128 帧吞吐测试按 125 MHz 折算每路约 122.114 MS/s，尚非上板测速
- [x] 新流水线独立布局布线：8 ns 内部时钟约束，WNS=+2.683 ns；7215 LUT、72 DSP、15 BRAM36 等效块，板级时钟/I/O 仍需验收
- [x] 独立 PCIe/XDMA 测试端点：已知数据及 AXI-Lite 仿真、板级布线、SRAM 配置和只读 VIO 身份确认；当前链路未建立
- [ ] 片内持续数据源、缓存和缺失记录；ConnectX-5 因机械干涉改用另一台主机，外部联调后续接入
- [ ] 真实短记录、网络输入、持续吞吐及科学通带验收
- [ ] 板卡具体规格补齐（见 docs/hardware.md 的 TODO）
- [ ] PCIe DMA 通路打通，卡片在主机侧可枚举
- [ ] 主机侧驱动 / 用户态 API
