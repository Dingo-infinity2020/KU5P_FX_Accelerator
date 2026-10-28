# PCIe 训练状态诊断

2026-10-28。d3 已在当前主机完成保持供电的 Windows 重启验证，配置保留、本地复位为 0，但链路和枚举仍未通过。具体启动证据见 [×4 记录](lesson05d-pcie-x4.md)。这一阶段增加训练状态观察，继续使用片内已知数据应用；不集成 FX 或网络，也不改动 RFSoC 原始工程。

## d4 的观察范围

独立构建目录为 `D:/work/build/KU5P_FX_Accelerator/lesson05d_pcie_training`，顶层 `lesson05d_pcie_training_top`，VIO 身份 `465805d4`。Gen3×4、256 位/125 MHz、PCI ID `10EE:9034`、22 个引脚、参考时钟和应用寄存器契约沿用 d3。应用 BAR 身份仍为 `465805d1`。

启用 XDMA 的 **PCIe Debug Ports**，实际 Vivado 4.2 属性为 `CONFIG.enable_pcie_debug_ports=True`。`CONFIG.en_debug_ports` 是事务流调试接口，不能用它替代配置状态输出；本阶段仍为 false。已核对本机 IP 实例化模板和生成的 `core_top.sv`：状态来自 `cfg_ltssm_state`，调试速度/宽度只是原始编码补零；`axi_aclk=user_clk`，因此先在此源时钟域记录，再传到独立 100 MHz 监测域。AMD 的接口定义见 [PG195 Debug Options](https://docs.amd.com/r/4.1-English/pg195-pcie-dma/Debug-Options-Tab?contentId=LVoU~Tp6Blb5G_xOwD8lMw) 与 [PG213 Configuration Status](https://docs.amd.com/r/en-US/pg213-pcie4-ultrascale-plus/Configuration-Status-Interface)。

新增监测逻辑不依赖 AXI reset 释放，否则会失去训练期间的状态。配置 FPGA 时初始化，后续端点复位不清除历史。64 位 bitmap 记录曾经过的 LTSSM 状态，32 位饱和计数器记录状态跳转；当前状态、速度/宽度原始值、错误观测和序号一起经 `xpm_cdc_handshake` 传输，禁止把多位异步编码直接逐位同步后当作一致状态。

快照是历史采样，不能代替独立时钟 watchdog、实时 link_up 或 Windows 枚举。源时钟停止后，最近快照和 valid 保持，必须结合 watchdog 和序号判断。状态集合能捕获相邻源时钟边沿间经历的一周期状态，但不记录状态的先后顺序或每态停留时间；跳转计数到最大值后饱和。

| VIO 输入 | 内容 |
|---|---|
| 0，8 位 | 原 d3 状态：时钟活动、GTPOWERGOOD、PERSTn、MSI、AXI reset、done、link |
| 1，32 位 | d4 身份 `465805d4` |
| 2，128 位 | 一致快照，字段见下表 |
| 3，1 位 | 自本次 FPGA 配置以来至少接收过一次快照 |

| 快照位 | 内容 |
|---|---|
| 63:0 | 已经过的状态 bitmap，bit 编号为 LTSSM 原始状态 |
| 95:64 | 跳转次数，32 位饱和 |
| 101:96 | 当前状态 |
| 104:102 | 速度原始编码 |
| 108:105 | 宽度原始编码 |
| 116:109 | sticky 观测：低三位为 correctable/nonfatal/fatal，余五位是 valid 时 local_error 编码的逐位 OR |
| 117 | 保留为 0 |
| 118 | 此快照的 link_up |
| 119 | 此快照的 axi_aresetn |
| 127:120 | 快照序号，8 位循环 |

`local_error` 的逐位 OR 只用于判断是否观察到非零编码，不能反解为单一错误码或独立错误清单。速度/宽度在未建链时不应解释为已协商结果；解码程序保留 raw 值。

## 复现和验收

```powershell
.\scripts\run_lesson05d.ps1 -Lanes 4 -TrainingDebug `
  -Python 'python' `
  -VivadoBin 'D:\AMDDesignTools\2026.1\Vivado\bin'
```

新的 profile 必须使用独立输出目录，脚本在生成向量前检查旧 manifest，拒绝覆盖其他宽度/profile。构建仍通过唯一入口 `tcl/build.tcl`。训练模块的九项仿真观察覆盖无源时钟、复位未释放、短状态保留、元数据、单周期错误及 valid 门控、返回检测态、停钟保留和恢复。原应用的 118784 字节及七项时钟 watchdog 仿真也须通过；这些不是 PCIe 根端口仿真或 DMA 测试。

实施完成后另记录实际时序、CDC、引脚、SRAM 下载与训练读取结果；没有实测证据前不把诊断能力记作建链成功。仍保留 d3 手动复位合并路径的 CDC-10 审查范围，不通过降低严重级别处理。

## 本次实现和上板结果

d4 已完成实现并实际配置到 SRAM，Flash 未修改。19004 LUT、23525 FF、46 BRAM36 等效块、0 DSP；WNS=+1.440 ns、WHS=+0.011 ns、WPWS=0，内部未约束/无时钟端点为零。40620 个可布线网络全部完成，零路由错误；22 个封装引脚、四条 GTYE4_CHANNEL_X0Y4..7、参考/AXI 计数器 10/8 ns 约束均已核对。快照数据跨域路径有 XPM 生成的 8 ns datapath-only max-delay，最差 slack 为 +7.261 ns，并非通过任意全局 false-path 跳过数据传输约束。

最终实现日志零 error / critical warning；DRC 保留 26 项 warning。CDC 为 56 项 CDC-3 Info、13 项 CDC-9 Info、76 项 CDC-15 Warning，以及 **1 项 CDC-10 Critical**。唯一 Critical 仍为 VIO 与物理 PERSTn 合并后进入 XDMA 两级 FDCE/ASYNC_REG 异步复位同步器的路径；人工核对了两个实际单元，使用范围仍限手动长时间保持、单次释放。不隐藏/改级告警，新增握手监测没有增加 Critical。

约 19:06 下载后，初始本地复位实际读回 1，随后显式释放并读回 0。复位释放后的首次与后续复查各有 12 个训练快照：valid=1、状态 `00/Detect.Quiet`、已见状态 bitmap=`0000000000000001`、跳转计数 0、速度/宽度 raw=0、错误观测为 00。序号多次变化，AXI 时钟 watchdog 高，说明这些是持续更新的观察，而非只读到停钟前的旧值。原状态字六次均为 `f0`，实际 link_up=0、axi_aresetn=0；Windows 清单仍没有 `10EE:9034`，实际 BAR/DMA 未测试。

这些结果说明 **d4 配置以来未观察到进入 Detect.Active、Polling 或 L0**，把排查点推进到训练开始前/初期。它不能单独区分 GT/PLL/PHY 初始化、复位条件和主机侧条件，也不等同于覆盖了 18:38 的启动：那次启动运行的是 d3，d4 在后面才下载。下一步优先增加 GT reset-done、所选 PLL 锁定和 PHY reset 状态，先不重复相同的重扫/重启流程。

已经在外部临时探测工程中核对本机 XDMA 的 `CONFIG.en_transceiver_status_ports=true` 模板，可提供 `gt_txresetdone`、`gt_rxresetdone`、`gt_qpll1lock`、`gt_cplllock`、`phy_rst_idle` 等。但它同时暴露控制输入（含 `gt_pcieuserratedone`、额外复位、PRBS/loopback 等），下一阶段必须核对生成 HDL 和官方默认连接，保持正常 PCIe 工作语义；不能仅打开开关而悬空输入，也不能将模板能力当作已上板的 PHY 观测。当前板上仍是 d4。

| 产物 | SHA-256 |
|---|---|
| bit | `52895c57d3fa07ef64a4ec2789b86372b7ebe08fbd075cb566c2ea599bf8beb0` |
| LTX | `d73fbdae828aab24d563cb7ad761546dd44f563043bd3b095d7e76d5224e1db4` |
| routed DCP | `9b603b725a72793b812d81d8d6936f71bedff2ab87c01d34d8d334518336fbba` |

实际构建目录内的 `verification.json`、`hardware_verification.json`、`final_observed_training.json`、`hardware/local_reset_actions.tsv` 和各报告分别记录实现、硬件状态、训练历史与复位动作；d3 的重启记录保留在原 ×4 目录。

后续 d5 审计补充：这里历史状态字名为 GTPOWERGOOD 的 bit5 来自 IP 的 `sys_clk_ce_out`，本机生成 RTL 实际将它连接到公共 `!rst_txpisopd` 标志，不能理解为四个 GT 原语原始 power-good 的逐路观测。原始记录和哈希保持不变，具体说明见 [GT/PHY 诊断](lesson05d-phy.md)。
