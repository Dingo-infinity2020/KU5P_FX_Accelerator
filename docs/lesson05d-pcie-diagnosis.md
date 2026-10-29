# PCIe 重扫描后的时钟诊断

后续：用户主机重启后 d2 仍保留，AXI 时钟已观察到活动，链路仍未建立。用户确认当前插槽为 ×4，已进入 [d3 ×4 配置和复位诊断](lesson05d-pcie-x4.md)。本文保留 d2 的实现及重启前观察。

2026-10-28。用户已在管理员 PowerShell 成功执行 `pnputil /scan-devices`。随后 Windows 只读检查仍未发现 `10EE:9038`，原 d1 固件的六次 JTAG 状态仍均为 `0x10`：PERSTn 高、link_up 低、AXI reset 未释放。此前权限不足的重扫描问题已经解决；不能继续把它列为本次排查未完成事项。

原始固件及本次扫描后的证据仍在仓库外 `lesson05d_pcie/`：`windows_admin_rescan.json`、`hardware/after_admin_rescan.tsv`、`hardware_after_admin_rescan.json`。改动前的全部冻结源及硬件脚本另存 `source_snapshot/` 并核对哈希。原 bit/LTX 保留；新诊断构建使用独立的 `lesson05d_pcie_diag/` 目录。

## 诊断改动

`pcie_clock_monitor.sv` 用独立板载 100 MHz 时钟监测两路时钟活动：

1. PCIe 差分参考输入 AB7/AB6 → 原 `IBUFDS_GTE4.ODIV2` → 共用的 `BUFG_GT_SYNC/BUFG_GT` → XDMA 与 8 位监测计数器。
2. XDMA `axi_clk` → 另一独立 8 位计数器。

每个源只把最高计数位经两级 ASYNC_REG 同步到监测时钟域；两个信号互不组成有意义的多位数据。监测域分别记录最近一次跳变，超出约 655 微秒无跳变便将相应 recent 位清零；启动时默认无活动。这样能发现启动、停止与恢复，避免用六个稀疏的 heartbeat 快照推断时钟是否持续存在。

参考缓冲保持 AMD 的 GTPOWERGOOD 使能方式：XDMA 的 `ext_sys_clk_bufg` 选项置 true，由导出的 `sys_clk_ce_out` 经 `BUFG_GT_SYNC` 控制唯一的共享缓冲。GTPOWERGOOD=0 时参考监测支路会被关闭，不能直接把 ref_recent=0 解释成插槽没有参考时钟；bit5 同时提供该使能状态。

监测到跳变不等于测得准确 100/250 MHz，也不证明抖动、电平或 PCIe 眼图合格。AMD 说明 PCIe 用户时钟依赖 GT 输出及其复位，可能不连续运行，因此 AXI 时钟无活动本身不能独立证明插槽参考时钟消失，见 [PG213 Clock and Reset Interface](https://docs.amd.com/r/en-US/pg213-pcie4-ultrascale-plus/Clock-and-Reset-Interface)。

只读 VIO 的 port0 现在使用完整 8 位：

| bit | 内容 |
|---|---|
| 0 | user_lnk_up |
| 1 | 应用 done |
| 2 | axi_aresetn |
| 3 | MSI enabled |
| 4 | 插槽 PERSTn |
| 5 | GTPOWERGOOD / 参考缓冲使能 |
| 6 | PCIe 参考缓冲后时钟最近有活动 |
| 7 | AXI 时钟最近有活动 |

VIO port1 的诊断固件标识改为 `465805d2`。用户 BAR 的应用 build_id 仍为 `465805d1`，其寄存器和数据格式保持相同；二者分别标识板级诊断版本和应用接口版本。

新增约束只将两条监测同步器的第一级 D 引脚作为异步路径终点；不切断整组时钟之间的路径。XDMA 的外部时钟缓冲选项改变，Gen3×8、AXI、BAR 和通道配置保持不变；顶层端口及原 38 个封装引脚也保持不变，FX/PFB 源码没有修改。

## 验证与复现

新增 `tb_pcie_clock_monitor.sv` 验证七种情况：两路均停、仅参考时钟、两路运行、仅 AXI 时钟、两路停止、两路恢复、AXI 停止而参考时钟继续。独立计时等待后核对活动状态，仿真结果为 `PASS clock_monitor_checks=7`。应用单元测试重跑仍为 29 包、3712 beat、118784 字节完整匹配。

第一次重新综合 XDMA 时遇到 Vivado `EXCEPTION_ACCESS_VIOLATION`。清理该崩溃遗留的独立 worker 并重置失败 run 后，使用 Vivado 原生跨工程 IP cache 恢复，cache-ID=`841f04b5c587a189`，日志明确报告命中。该次监测设计随后被布局前 DRC 拒绝：独立增加的第二个 BUFG_GT 与 IP 内部缓冲控制不同，不满足 BFGTL-1 / REQP-1963。没有放宽检查，也没有上板该版本。

修正为 IP 支持的外部共享缓冲选项后，重新冻结源码、仿真并重建。由于 IP 配置改变，最终构建不再把旧 cache-ID 的命中作为该新配置的证明。增加 `lesson05d_synth_settings.tcl`，将 general/synth.maxThreads 均限制为 1，减少崩溃相关的并行 worker；这只是本次恢复设置，不代表已确定工具崩溃的根因。初次失败源、输入证明和 DRC 日志位于 `first_monitor_attempt/`，不与最终验收混淆。

`run_lesson05d.ps1` 已包含两项仿真与冻结源校验，硬件动作仍显式执行，不自动重启主机或写 Flash。复现时显式选新目录：

```powershell
.\scripts\run_lesson05d.ps1 `
  -Python 'python' `
  -VivadoBin 'D:\AMDDesignTools\2026.1\Vivado\bin' `
  -BuildDir 'D:\work\build\KU5P_FX_Accelerator\lesson05d_pcie_diag'
```

构建、引脚/CDC/时序审计和真实 JTAG 结果分别保存；物理链路、主机枚举、BAR 访问和真实 DMA 仍按实际结果逐项记录。Windows 内核驱动的缺失不妨碍只读链路诊断，但真实 BAR/DMA 验收仍需兼容驱动。

## 最终实现及实际读数

最终 d2 已完成重新综合、布局布线与板级检查：19526 LUT、25151 FF、46 BRAM36 等效块、0 DSP；250 MHz AXI 时钟约束下 WNS=+0.265 ns、WHS=+0.012 ns、WPWS=0。43043 个可布线网络全部完成，零路由错误；38 个顶层端口封装引脚全部匹配。无时钟及内部未约束端点均为零，异步 PERSTn 和两只 LED 仍按其用途设 false path。

最终实现日志为零 error / critical warning。DRC 保留与 d1 相同类别的 26 项 warning（3 项调试 LUT、22 项 IP BRAM、1 项无可路由负载）；CDC 保留 148 项生成 IP 的 CDC-15 warning。时钟监测的两条一级同步 D 引脚及原六条诊断同步 D 引脚均在预期集合内，四项 bus skew 约束通过。原始 ODIV2 的 leaf 输入负载实际仅为一个 BUFG_GT 和一个 BUFG_GT_SYNC，共享连接通过原生 DRC。

新配置的 XDMA 已实际重新综合，配置/cache-ID 为 `ba39dcabc2a4a7d7`；最终构建不复用初次尝试的旧配置结果。`ip_configuration_change.json` 记录与 d1 相比的外部缓冲参数、导出端口及校验和变化。

2026-10-28 16:16 左右，真实 KU5P 已经 JTAG SRAM 配置 d2，DONE 高，VIO 标识正确。六次采样均为 `0x70`：

| 项目 | 实际观察 |
|---|---|
| 板级监测时钟 / JTAG | 工作，可连续读取 VIO |
| PERSTn | 高 |
| GTPOWERGOOD | 高 |
| 参考缓冲后时钟 | 最近有活动 |
| AXI 时钟 | 最近无活动 |
| AXI reset | 未释放 |
| PCIe link_up | 低 |
| Windows `10EE:9038` | 未枚举 |
| BAR / DMA | 未测试 |

参考缓冲后的活动已证实；后续检查集中在 GT/PCIe 初始化、复位和启动枚举。仍未测出参考时钟精确频率或定位最终根因。Windows 驱动是否可用是后续 BAR/DMA 的独立条件，当前尚未到驱动传输验收。

| 产物 | SHA-256 |
|---|---|
| bit | `bef629a393bb14f629ebf8d28b6b0a329b97b28f682fb0646a823ecb49e8309e` |
| LTX | `b15f91e2df074b3e1ce0ba24875d21925977445a04eb76dc538e582806e46cef` |
| routed DCP | `571598c4b4d65a6652846e03d1465b9e4319c411f7311d2ceba89b96e7635bca` |

`lesson05d_pcie_diag/verification.json` 为仿真/实现证明，`hardware_verification.json` 为实际状态；原 d1 及失败的诊断原型分开保存。当前 SRAM 为 d2，Flash 未写入。FX/PFB 的第四课和 05C 验证源哈希保持不变。

## 下一次主机操作

下一步验证**保持 FPGA 供电的 Windows“重启”**，观察启动时的 PCIe 复位与枚举。此操作中断用户工作和当前工具会话，留给用户保存工作后执行；本次未自动重启，也未重置根端口或改 BIOS。

重启后先通过 JTAG 确认 DONE、d2 VIO 标识及状态，再检查 Windows 枚举，先不重新下载位流，以便判断 d2 是否参与了此次启动。若 d2 已丢失，应将其记录为未保留 SRAM 配置，不能把那次未枚举作为 d2 启动枚举失败的证明。常规断电会丢失 SRAM，Flash 持久启动仍属于另一个需核对的工作项。

用于继续检查的 Vivado Tcl（不下载固件）：

```tcl
source -notrace {D:/work/KU5P_FX_Accelerator/tcl/lesson05d_hardware.tcl}
set device [lesson05d_attach]
set_property PROBES.FILE {D:/work/build/KU5P_FX_Accelerator/lesson05d_pcie_diag/lesson05d_pcie_top.ltx} $device
refresh_hw_device $device
lesson05d_read_status {D:/work/build/KU5P_FX_Accelerator/lesson05d_pcie_diag} after_windows_restart
```
