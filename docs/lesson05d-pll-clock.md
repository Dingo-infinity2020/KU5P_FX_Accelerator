# PLL 控制与时钟排查（2026-10-28）

承接 [d5 GT/PHY 诊断](lesson05d-phy.md)。本轮仍在 Windows 主机进行；板卡插槽为显卡下方的电气 ×4 槽。下面各目录均在 `D:/work/build/KU5P_FX_Accelerator/`，不在 Git 仓库内。

## 证据修正

最初 d6/d7 的网表 ECO 观测连接没有在跨层连接时使用 `connect_net -hierarchical`。工具只给警告，生成位流和时序通过也没有保证这些观测连接存在。关闭并重开 DCP 后发现首级同步器输入断开，因此这两版新增控制位的硬件读数无效，目录内已写 `INVALID_OBSERVERS.json`，不能采用“PLL 一直保持复位/掉电”的结论。

d8 使用跨层连接，保存、关闭并重开 DCP 后核对六条观测连接全部存在，同时逐项比较 GT 功能输入未改动。生成的 ×4 wrapper 反转了通道数组，逻辑 CPLL[0] 对应 primitive[3]，本次按这个对应关系选择观测对象。

另外，生成的 GT wrapper 把 `cplllockdetclk_in` 和 `qpll1lockdetclk_in` 接到常量 0。其 REFCLKLOST 电平不能证明参考时钟丢失；d8/d9 的输出目录另有 `refclklost_interpretation.json` 记录这个限制。参考时钟存在与频率需独立测量。

## 已完成实验

| 版本 | 外部目录 | 修改与实际结果 |
|---|---|---|
| d8 / `465805d8` | `lesson05d_pcie_pll_checked` | 有效观测：逻辑 CPLL0 RESET/PD 与 QPLL1 RESET/PD 的稳定读数均为 0，锁定仍为 0。未更改功能输入。 |
| d9 / `465805d9` | `lesson05d_pcie_refclk_north` | 从 d8 更改 GT 参考入口为 NORTHREFCLK1，选择值 100；重开 DCP 核对连接及选择位。30 项变化全部属于 REFCLK，其余 GT 输入不变。实际锁定仍为 0，未改善初始化。 |

d8 WNS/WHS 为 +1.098/+0.010 ns；d9 为 +1.164/+0.011 ns，两者均完全布通、DRC 无 Error。CDC 各有 3 项 Critical CDC-10：原手动复位合并路径一项，QPLL RESET/PD 组合输出的观测路径两项。后者只接两级 ASYNC_REG 观测寄存器，不反馈控制，仅用于长时间稳定电平排查；不据此判断窄脉冲或复位时序，未 waive 或降低严重度。

原理图/封装核对：AB7/AB6 为 bank224 的 MGTREFCLK0，PCIe GT 位于 bank225；原实现使用相邻 quad 的专用参考时钟连线。单凭 bank 不同不能判定非法；d9 的阴性结果也没有确立根因。

## 独立测频工程

`lesson05d_pcie_clock_hdl` 使用自写 `lesson05d_pcie_clock_top`，VIO 身份 `465805da`。恢复原 d5 的电气连接，不包含 d8 的六个 ECO 观测位。两个源时钟计数器的 bit7 已通过原有两级同步器进入板载 SYS_CLK 域，HDL 实例化的 ILA 在该域连续采集 4096 点。

参考时钟位为 probe0[0]，AXI 时钟位为 probe0[1]。每个完整周期对应 256 个源时钟周期。依据板载 SYS_CLK **标称** 100 MHz，频率计算为 `256 × 100 / 平均上升沿间隔` MHz。该结果只用于分辨明显频率偏差或停振，不是校准后的 ppm、抖动或信号完整性测量。无足够边沿时不给出频率。

Vivado BASIC 不支持本次尝试的网表级 `create_debug_core ... ila`，失败尝试保存在 `lesson05d_pcie_clock_measure`；实际测频工程改用此前板级回放验证过的 HDL ILA 实例化，不改授权设置。

da 已实现并上板：WNS/WHS 为 +1.409/+0.011 ns，43100 个可布线网络全部完成，22 引脚核对通过，DRC 无 Error。CDC 与 d5 相同：1 项 Critical CDC-10、75 项 Info CDC-3、13 项 Info CDC-9、76 项 Warning CDC-15。118784 字节应用仿真、7 项 clock watchdog、9 项训练监测、5 项 PHY 监测检查均为本轮新跑通过。三次 4096 点采集的参考/AXI 计数边沿不均匀，不满足脚本的稳定周期筛选，不报告单一稳定频率。

## 门控对照、采集校验和原始 power-good

| 版本 | 目录 | 结果 |
|---|---|---|
| db / `465805db` | `lesson05d_pcie_clock_ungate` | 只把参考 fabric BUFG_GT 的 CEMASK 置 1，并更换身份。WNS/WHS +1.275/+0.010 ns。两次采集仍不稳定，PLL 未锁定、AXI watchdog 不活动，不能作为修复。 |
| dc / `465805dc` | `lesson05d_pcie_clock_sanity` | 以原 da 为基准，恢复门控；外部诊断寄存器 sample2[1] 改采同域 heartbeat[7]，不修改 ILA 内部。WNS/WHS +1.224/+0.010 ns。两次采集心跳上升沿间隔均严格 256 点，参考位仍不稳定。 |
| dd / `465805dd` | `lesson05d_pcie_raw_power` | 基于 dc，在原有四个 spare 同步器加入 GT 原语 GTPOWERGOOD；WNS/WHS +1.256/+0.010 ns。重新打开 DCP 后四条连接全部核对通过。 |

dc/dd 的 ILA bit1 是同域心跳，**不是 AXI 时钟**，旧 `divided_samples[1:0]` CSV 名称保留；状态 bit7 的 watchdog 也随之改为心跳，不能再解释为 AXI 活动。验证 JSON 明确设置 `status_bit7_represents_axi_activity=false`，解码结果的 AXI 活动字段为 null。参考位仍为 ILA bit0，未改其计数/同步链。

试图直接修改已实现的 HDL ILA 输入或通过 debug API 重接探针均被工具拒绝，未生成或配置这些尝试的位流。最终 dc 只改 **ILA 外部** 的诊断寄存器输入。由此遗留一个原 AXI 首级观测寄存器，其 Q 的负载数为 0，导致 CDC-1 Critical 一项；另有原手动复位 CDC-10 Critical 一项。dc/dd 均如实记录 **2 项 Critical**，不 waive、不降低严重度，孤立寄存器没有控制或观测反馈。它是校验工程残留，后续 HDL 固化时应移除。

dd 的四路 raw power-good 分别放在 PHY 当前字 bit17、18、19、26，对应 GTYE4_CHANNEL_X0Y4、Y5、Y6、Y7。15 MHz 下载和 6 MHz 下载后，各 12 次稳定读取中这四位均为 1；CPLL/QPLL1 锁定及 TX/RX reset-done 仍为 0。原始 power-good 为高不等于已测量模拟供电纹波或所有上电时序合格。

[AMD PG182](https://docs.amd.com/r/en-US/pg182-gtwizard-ultrascale/Reset-Sequencing-and-Other-Services) 提到 UltraScale+ 在超过 6 MHz 的 JTAG 下载后，IBUFDS_GTE4/BUFG_GT 输出可能有初始不稳定。本轮用**同一个 dd 位流**做 15 MHz 与 6 MHz 下载对照，两种情况下各两次采集均通过同域 256 点校验，但参考计数位仍不稳定、PLL 均未锁定。因此本轮没有验证“降到 6 MHz 即修复”的结论。当前 JTAG 频率保留 6 MHz。

[AMD AR72746](https://docs.amd.com/r/en-US/72746/Solution) 的旧 delay_powergood 补丁针对早期 Vivado 版本，文档明确说明 PCIe IP 设计不受影响；本工程未应用该补丁，未修改 AMD 生成源或工具安装。

## 当前结论与下一项验收

采集校验支持“当前参考缓冲后的计数边沿不稳定”这一观测；不能从此直接推导插槽差分信号频率、抖动或器件故障。当前没有稳定 100 MHz 参考证据，优先核对插槽参考时钟、板上连接与缓冲路径。可用另一台主机/插槽做同位流对照，或由具备合适探头的仪器测量参考时钟；这一步不依赖 XDMA 驱动。

当前 SRAM 为 dd，复位已释放。dd 保留原 da 的功能时钟/GT 输入，额外内容均为诊断；db 的门控旁路没有保留。Windows 枚举与训练的最终读数另存于输出目录。没有写 Flash、改变 BIOS/安全设置、安装驱动或复位主机根端口。实际 PCIe 枚举和 BAR/DMA 尚未验收。

22:12 最后复查：12 次 PHY 当前值均为 `0000240f0000`，raw GTPOWERGOOD 全高，CPLL/QPLL1=0，TX/RX reset-done=0，PHY rrst_n=1、prst_n=0、rst_idle=0。训练历史仍只有 Detect.Quiet；校验版的 bit7 不代表 AXI 活动，不能凭它声称快照持续更新。Windows `10EE:9034` 数量为 0。6 MHz 下最后一次采集同域校验通过，参考上升沿间隔为 76–561 个采样点，仍不给出单一稳定频率。

用户目前没有另一台可装卡主机或合适示波器。下一项可用现有主机另一个可容纳板卡的电气 ×4 长槽做对照：由用户正常关机、断开电源后移卡，重新启动；先记录原有枚举/配置状态，再通过 JTAG 下载同一份已验证 dd 位流，读取版本/复位并采集相同数据。**不把更换插槽当成已实施或已通过的测试**。重新连接 Hardware Manager 后须显式设置并读回 6 MHz，不能假设该设置永久保存。该对照不要求先安装 XDMA 驱动。

每个成功实验保留 `verification.json`、位流/LTX/DCP 哈希、报告、源快照以及硬件原始数据。历史构建的源字节可从归档核对，不能因为工作区后来修改了 dispatcher 就重写历史证明。d5 的既有公开验证 JSON 继续代表 d5 快照。

可公开的结果、原始采集哈希、各次构建位流哈希和验证边界汇总于 [2026-10-28 时钟诊断证据](validation/lesson05d-clock-2026-10-28.json)。原始 RFSoC 工程、生成的 AMD IP、位流与本机硬件日志不入 Git。
