# GT 复位、PLL 与 PHY 初始化诊断

2026-10-28。当前目标是查清 PCIe 在 `Detect.Quiet` 不推进的条件，保持 Windows 路线。d4 的配置/训练历史已经在修改前再次读取，仍是复位 0、状态 `f0`、历史仅有状态 00，Windows 启动时间未变。

## Windows 端尚未验收

PCIe 链路、主机枚举、XDMA 驱动、BAR 和真实 DMA 是分别验收的步骤。目前已生成并实现 XDMA 硬核与片内测试应用，但链路和枚举还未通过，兼容且可信可加载的 Windows 内核驱动尚未取得，用户态程序只有模拟端点/普通文件测试。不能称为已经解决 Windows PCIe/XDMA 通路或把当前未建链归因于缺少应用驱动。

Microsoft 区分了总线驱动枚举设备和设备功能驱动处理读写的职责，见 [Bus Drivers](https://learn.microsoft.com/windows-hardware/drivers/kernel/bus-drivers)。因此继续先查板上的物理初始化，不用尚未获得的 XDMA 驱动去解释所有现象。

## d5 设计与默认连接

独立构建目录 `D:/work/build/KU5P_FX_Accelerator/lesson05d_pcie_phy`，顶层 `lesson05d_pcie_phy_top`，VIO 标识 `465805d5`。PCIe 仍为 Gen3×4、256 位/125 MHz、ID `10EE:9034`；原应用和 d4 的一致训练历史保持。

启用本机 XDMA 4.2 的 `CONFIG.en_transceiver_status_ports=true`，另外保留 `enable_pcie_debug_ports=True`。逐一核对 d4 实际生成 wrapper 中原本隐藏端口的连接：16 个 GT 控制输入全部为固定零，新顶层采用相同位宽、相同零值，包括 rate-done、loopback、PRBS、额外复位和 DMONITOR 控制。原始 HDL 和生成 IP 保留在外部构建目录，仓库只保存自写接口与审计程序。

本次不改变 GT 工作模式，不通过 VIO 控制额外 GT 复位。AMD 对这些输入要求按 GT 指南驱动，见 [PG213 Transceiver Control and Status Ports](https://docs.amd.com/r/en-US/pg213-pcie4-ultrascale-plus/Transceiver-Control-and-Status-Ports)；本次以原实例默认常量作为具体连接依据，`control_tieoff_audit.json` 保存核对清单。

新增 `pcie_phy_monitor` 在独立 100 MHz 监测域逐位同步稳定标志，并记录曾为高/低的历史。这里每位是独立标志，不把它们拼成一致的多位状态机编码；窄脉冲可能漏采。同步器设置两级 ASYNC_REG，约束只截止到第一级 D，历史延迟到同步器预热后再开始，避免把初始化的零值当作实际低电平。

首轮实现审计发现 5 项 CDC-11：原状态字与四条新同步器重复采样同一个源。核对本机生成的 `gt_phy_wrapper.v`，`DBG_GTPOWERGOOD` 实际复制自公共的 `!rst_txpisopd`，`sys_clk_ce_out` 也来自这一标志。修订版只跨域同步一次该公共标志，原状态字复用这个已同步值，其余三个填充位固定 0；不通过改级或 waiver 处理 CDC-11。首轮位流未上板，产物/源快照另存 `attempt_before_cdc_fanout_fix/`。旧 d2..d4 记录中的 `GTPOWERGOOD` 字段保持原始命名和读数，但其物理解释应更新为 IP 导出的公共电源时序标志，不能当作四个 GT 原语原始 power-good 的逐路观测。

VIO 输入 0..3 沿用 d4，输入 4 为 144 位：低 48 位是当前同步标志，中间 48 位是 ever-high，高 48 位是 ever-low。端点复位不清除历史，FPGA 重新配置才初始化。每个四位 nibble 分组如下，四通道向量按 IP 端口 bit0..3 保留，不先假定为连接器/协商 lane 编号：

| 48 位标志中的位 | 内容 |
|---|---|
| 3:0 | gt_txresetdone |
| 7:4 | gt_rxresetdone |
| 11:8 | gt_rxpmaresetdone |
| 15:12 | gt_txpmaresetdone |
| 16 | IP 导出的公共 power-on 标志，与 sys_clk_ce_out 同源；19:17 固定 0 |
| 23:20 | gt_cplllock |
| 24 / 25 | gt_qpll1lock / gt_qpll0lock；27:26 固定 0 |
| 28 / 29 / 30 | phy_rst_idle / phy_rrst_n / phy_prst_n；31 固定 0 |
| 35:32 | gt_txprogdivresetdone |
| 39:36 | gt_txsyncdone |
| 43:40 | gt_rxsyncdone |
| 47:44 | gt_rxcdrlock |

已审阅本机生成的 PHY reset RTL：Gen3 设计的复位推进检查 CPLL 与 QPLL1，之后检查 TXPROGDIVRESETDONE、TX/RX RESETDONE、TXSYNC_DONE 等条件。该版本对 CPLL 的检查是 lane0，并非要求四个 CPLL 全部同时锁定；具体实测必须结合当前生成设计解释，不能把 QPLL0 未使用时为低视为故障。当前没有把 PHY 编码状态机、PHYSTATUS 窄脉冲或精确时钟测频纳入本观测，不能由这组标志凭空断言完整根因。

## 复现和验证范围

```powershell
.\scripts\run_lesson05d.ps1 -Lanes 4 -PhyDebug `
  -Python 'python' `
  -VivadoBin 'D:\AMDDesignTools\2026.1\Vivado\bin'
```

`-PhyDebug` 自动包含训练历史，并拒绝覆盖其他 profile 的构建目录。新增五项仿真检查覆盖同步器预热、初始高电平无伪低历史、混合通道、下降和恢复；原 118784 字节应用验证、七项时钟 watchdog、九项训练监测检查均须通过。实现和真实上板另行记录；仿真通过不能替代 PLL/PHY 实测。

## 最终实现与真实上板结果

修订版已实际配置到 SRAM，并保持本地复位读回 0；Flash 未写入。19547 LUT、24451 FF、46 BRAM36 等效块、0 DSP；WNS=+1.104 ns、WHS=+0.010 ns、WPWS=0，内部未约束和无时钟端点为零。41627 个可布线网络全部完成，零路由错误；22 个引脚和 GTYE4_CHANNEL_X0Y4..7 已核对。96 个监测同步寄存器的 ASYNC_REG 属性已检查；训练快照的 8 ns datapath-only 跨域约束 slack=+7.272 ns。

最终实现日志零 error / critical warning，DRC 保留 26 项 warning。CDC 为 75 项 CDC-3 Info、13 项 CDC-9 Info、76 项 CDC-15 Warning，**CDC-11 已为零**；仍保留原手动复位合并路径的 **1 项 CDC-10 Critical**。实际核对其终止于 XDMA 两级 FDCE/ASYNC_REG 异步复位同步器，使用范围仍限长时间保持、单次显式释放；没有改级或 waiver。首轮带重复同步的位流未下载，不能与本版审计混用。

约 19:55 下载后，先观察本地复位为 1，再显式释放为 0。释放后的首次与稍后复查各采 12 个 PHY 样本，全部稳定为 `000060010000`；对应结果：

| 观察项 | 当前读数 | 判断范围 |
|---|---|---|
| CPLL 锁定向量 | `0x0` | 包括初始化所需 CPLL[0]，均未观察到锁定 |
| QPLL1 锁定 | `0` | Gen3 初始化所需 QPLL1 未锁定 |
| QPLL0 锁定 | `0` | 本配置不据此单项判断故障 |
| TXRESETDONE / RXRESETDONE | `0x0 / 0x0` | 四通道复位尚未完成 |
| TX/RX PMA reset-done | `0x0 / 0x0` | 当前尚未完成 |
| TXPROGDIVRESETDONE / TXSYNC_DONE | `0x0 / 0x0` | 当前未完成 |
| PHY rrst_n / prst_n | `1 / 1` | PHY 两个同步复位已释放，不等同于 PLL 的内部复位控制也已释放 |
| PHY rst_idle | `0` | PHY 初始化未进入完成的空闲状态 |
| IP 公共 power-on 标志 | `1` | 是公共时序标志，不是四个 raw power-good |

已采到的历史中 CPLL/QPLL1 也没有高电平；但窄脉冲可能漏采，不能将它扩展为无限时间或模拟电气质量的证明。训练快照 valid=1 且序号变化，历史仍只有 `00/Detect.Quiet`、跳转计数 0。六次原状态字均为 `f0`。Windows 当前设备清单仍无 `10EE:9034`，实际 BAR 和 DMA 未测试。

这组证据把排查点缩小到 **PLL/PHY 初始化未完成**，没有解决 Windows PCIe/XDMA 通路。它还不能区分参考时钟频率/选路不合适、PLL 持续处于 reset/power-down，或复位状态机尚未放行等原因。现有 watchdog 只证明缓冲后时钟有活动，没有精确测频；当前也没有实际观测 PLL 内部 reset/power-down 与 PHY 编码状态机。下一阶段优先测参考时钟频率并增加这些控制状态，暂不再要求重复主机重启或扫描。

| 产物 | SHA-256 |
|---|---|
| bit | `2bf16e3cd7e300441394835fdc02392ecf52f39e2d143b52e0a65c5563ad83df` |
| LTX | `4c294b45552e7ec726ace939df6e60fcff85f07bf72ad56bf4465084b78880c3` |
| routed DCP | `608afc04a858288cd3fa0b2f2617c62ed2da89d66b7a4d3e67572654a8d3b297` |

构建目录中的 `verification.json`、`hardware_verification.json`、`final_observed_phy.json`、`final_observed_training.json`、`windows_final.json` 和 `diagnostic_audit.json` 分别保存实现、硬件、PHY、训练、枚举与审计证据；`source_snapshot_d5/` 逐项保存并核验 34 项构建源/硬件脚本。d4 与首轮未上板尝试的历史分别保留，不覆盖成新结果。d5 在 18:38 主机启动之后才下载，尚未作为一次主机启动的固件验证。
