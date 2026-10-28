# 当前主机的 PCIe ×4 配置

2026-10-28。用户确认 KU5P 插在 PRIME Z790-P 的显卡下方长槽，该槽的电气宽度为 ×4。新建当前主机专用的 ×4 配置；原 ×8 位流与源快照仍保留，以后在具备 ×8 电气宽度的主机上另行验证。

## 重启观察与兼容条件

本次 Windows 启动时间读回为 17:34:42，之后先读取 JTAG，没有重新下载固件：DONE=1、一个 VIO、标识仍为 `465805d2`。六次状态均为 `f0`，表明参考缓冲后时钟和 AXI 时钟均有活动，PERSTn/GTPOWERGOOD 高，但 AXI reset 未释放、链路未建立；Windows 仍未发现 `10EE:9038`。与此前 `70` 相比，新增观察为 AXI 时钟活动，不代表已经建立链路。

原卡的八条 PCIe lane 在 FPGA GTY 上反序。AMD 明确列出，lane reversal 支持完整 ×8、×4 等配置，反序的 ×8 端点降宽到 ×4 不在支持组合内，见 [PG213 Lane Reversal](https://docs.amd.com/r/en-US/pg213-pcie4-ultrascale-plus/Lane-Reversal)。因此之前采用的常规自动降宽假设不适合这组板卡布线和当前插槽，需显式生成 ×4 配置。这是已确认的配置兼容限制，是否解释本次全部现象仍需实际联调验证。

`lesson05d_pcie_diag/` 保存 d2 的重启前后记录、原 bit/LTX 和 `source_snapshot_d2/`。d3 使用独立的 `lesson05d_pcie_x4/`，不会把 d2 的重启观察当作 d3 的结果。

## d3 设计范围

| 项目 | 配置 |
|---|---|
| 顶层 | `lesson05d_pcie_x4_top`，实例化参数化的通用 PCIe 测试顶层 |
| PCIe | Gen3×4 能力，GTY quad 225，lane reversal 开启 |
| 实际接入 lane | 板卡连接器 lane 0..3；其余四条未实例化 |
| 参考时钟 / PERSTn | 原 AB7/AB6、T19；共享参考缓冲方式保持 |
| AXI Stream | 256 位，125 MHz 目标 |
| PCI ID | 自动生成 `10EE:9034` |
| VIO 板级标识 | `465805d3` |
| 用户 BAR 应用标识 | 仍为 `465805d1`，数据与寄存器契约保持 |
| 调试控制 | 一个 VIO 本地 PCIe 复位输出，初值 1，先保持端点复位 |

本地复位经 `physical_PERSTn && !debug_reset` 接到 XDMA 的异步复位输入；不替代物理 PERSTn。下载后由 JTAG 显式释放，必要时可在端点内部重新复位，避免每次调试都依赖主机重启。不操作主机根端口，不安装驱动，不写 Flash。当前测试源仍为空闲，只有主机写应用启动寄存器才产生已知数据。

只有 22 个板级端口需要本次封装引脚审计；四条 lane 使用厂家资料核对的连接器 lane 0..3 引脚，保留反序配置。板级时钟目标由 250 MHz 调整为 125 MHz，应用单元仿真的 4 ns 时钟仍仅用于协议/字节验证，不能作为实际 PCIe 吞吐测量。

## 复现与记录

```powershell
.\scripts\run_lesson05d.ps1 -Lanes 4 `
  -Python 'python' `
  -VivadoBin 'D:\AMDDesignTools\2026.1\Vivado\bin' `
  -BuildDir 'D:\work\build\KU5P_FX_Accelerator\lesson05d_pcie_x4'
.\scripts\inspect_pcie_windows.ps1 -DeviceId 9034 `
  -Report 'D:\work\build\KU5P_FX_Accelerator\lesson05d_pcie_x4\windows_inventory.json'
```

脚本会拒绝将另一个 lane 宽度的输入证明覆盖到同一构建目录。应用单元测试仍通过：29 包、3712 beat、118784 字节全部匹配；时钟监测七项场景均通过。实现、JTAG、协商结果、Windows 枚举和 DMA 分别记录，实际结果以后续证据为准。

## 实现与真实上板结果

Gen3×4/256 位/125 MHz 版本已完成实现：18454 LUT、22356 FF、46 BRAM36 等效块、0 DSP。WNS=+1.303 ns、WHS=+0.010 ns、WPWS=0，内部未约束端点与无时钟端点均为零。39159 个可布线网络全部完成，零路由错误；22 个端口引脚和 GTYE4_CHANNEL_X0Y4..7 全部核对通过。参考监测计数器时钟约束为 10 ns，AXI 计数器为 8 ns。

最终实现日志零 error / critical warning；DRC 保留 26 项 warning（3 项调试 LUT、22 项 IP BRAM、1 项无可路由负载）。CDC 报告另保留 76 项生成 IP 的 CDC-15 warning，以及 **1 项 CDC-10 Critical**：VIO 复位控制与物理 PERSTn 相与，组合逻辑位于 XDMA 异步复位同步器前。该路径经人工核对终止于复位同步器的 CLR，两级寄存器均为 FDCE 且 ASYNC_REG=1；本次操作是长时间保持复位、再单次显式释放，VIO 控制在其余观察期间保持稳定。没有将该告警改级或隐去；这份试验固件的手动复位使用范围与数据通路 CDC 应分别看待，自动复位协调仍需后续设计。

2026-10-28 18:14 左右，已实际下载 d3 到 SRAM。VIO 初始复位输出读回为 1；保持期间状态在 `30/70` 间变化。随后显式写 0 并从硬件读回确认，延时后六次状态均为 `f0`、标识为 `465805d3`：参考与 AXI 时钟有活动，PERSTn/GTPOWERGOOD 高，AXI reset 未释放、link_up 低。Windows 第一次检查尚未发现 `10EE:9034`。因此当前 ×4 配置与可控复位已实现，**实际链路和枚举仍未通过**；不能只凭修正 lane 宽度就宣告故障已解决。

复位动作及读回保存在 `hardware/local_reset_actions.tsv`，真实状态、实现及硬件源哈希分别见构建目录的 `hardware_verification.json`、`verification.json` 和相关报告。当前局部复位为 0，Flash 未修改，真实 BAR/DMA 尚未测试。工具进程当前无管理员 token，已请用户对新固件执行一次管理员 PnP 重扫描；之前的扫描针对旧 ×8 配置。

用户随后已成功完成新固件下的管理员重扫描。18:20 左右复查，Windows 仍未发现 `10EE:9034`，六次 d3 状态仍为 `f0`，本地复位硬件读回为 0。下一步是保持 FPGA 供电，让已释放复位的 d3 参与一次 Windows 主机启动，验证启动时的训练与枚举。此前主机重启运行的是 d2 ×8，不能替代这项 ×4 启动验证；也不能因重扫描成功就推断根端口已经执行了完整复位/重训练。

| 产物 | SHA-256 |
|---|---|
| bit | `98e6e2107d484dd11836456126c10f423b6fed8dfc920a68bc9fce4ef1631555` |
| LTX | `f9d41b67511b854b5e9c60aa27576cdc709c4b788485e771beb0c04b3f3b2018` |
| routed DCP | `5e6f2b688e9e64e5ca7b590d20b3753e740f1dc76709c3be9bd622b8d4f4dd91` |

## d3 参与主机启动后的结果

用户再次重启后，Windows 启动时间为 2026-10-28 18:38:06。先读取保留的配置，未重新下载，也未操作本地复位：DONE=1、一个 VIO、身份 `465805d3`、本地复位读回 0；六次状态仍全部为 `f0`。Windows 当前设备清单中仍无 `10EE:9034`。因此 d3 已实际参与这次启动，但链路与枚举仍未通过；下一步增加训练状态观察，不再重复相同的重扫/重启步骤。

证据位于 ×4 构建目录的 `d3_restart_observation.json`、`hardware/after_d3_windows_restart.tsv`、`windows_after_d3_restart.json`、`hardware_after_d3_restart.json`；重启前证明另存为 `hardware_before_d3_restart.json`。修改构建流程前，已将 d3 的 17 项冻结构建源和 5 项硬件脚本复制到 `source_snapshot_d3/`，逐项核对 SHA-256，保留可复查的历史身份。

只读 JTAG 检查使用对应构建目录的 LTX，并显式指定 d3 身份（不重新下载）：

```tcl
source -notrace {D:/work/KU5P_FX_Accelerator/tcl/lesson05d_hardware.tcl}
set device [lesson05d_attach]
set_property PROBES.FILE {D:/work/build/KU5P_FX_Accelerator/lesson05d_pcie_x4/lesson05d_pcie_top.ltx} $device
refresh_hw_device $device
lesson05d_read_status {D:/work/build/KU5P_FX_Accelerator/lesson05d_pcie_x4} after_d3_windows_restart 465805d3
```
