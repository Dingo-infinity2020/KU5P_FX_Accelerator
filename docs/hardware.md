# 板卡信息

2026-10-31开发：e6已通过离线SIM/ROUTED接受，尚未上板。 当前静态连接器0..3→GT7..4→硬核PIPE0..3，物理GT倒序不等于逻辑lane倒序。e6的PHY仅受物理PERST控制，VIO输出0保留。最后实测SRAM仍是历史e4记录，本轮未读板；见[版本和验收](lesson05j-pcie-reference-reset.md)。

2026-10-31静态审计勘误：父XDMA选项写lane reversal=true，实际子核/硬核PL_DISABLE_LANE_REVERSAL=TRUE；尚需核对参数适用性和完整映射，不能继续只凭上层选项声称最终硬核已启用。事件RAM实际3个RAMB36E2+1个RAMB18E2。见[审计与下一方案](pcie-audit-and-next-plan-2026-10-31.md)。本轮无新BOARD。

**最新停止点（2026-10-31）：** 用户完成第二长槽保留e4重启。当前四路GT TX/RX/PMA done高，AXI和训练更新至Polling.Compliance；PLL锁定指示低，仍无L0/10EE枚举。512地址已保存，但首事件时间戳早于昨晚记录，完整启动溯源HOLD。最终e4/DONE1/reset0/arm0/epoch2，Hardware Manager关闭；不要求再次重启或复位。 见[当前复核](slot2-e4-restart-2026-10-31.md)。下方2026-10-30停止点均为历史。

最新实板更新（2026-10-30晚）：用户确认FPGA现为第二长槽、网卡第一长槽，并更正原FPGA一直在第三长槽，旧“第二长槽”口述记录不能作精确物理归因。本轮原e4 ×4下载一次后最终reset0，PLL/GT未初始化，无L0/枚举；完整事件和ILA已保存，见[第二槽测试](slot2-e4-trial-2026-10-30.md)。当前等待用户手动Windows重新启动作新槽启动对照；下表e0等是此前历史状态。

> 本文件只放**可公开**的硬件信息。序列号、MAC、许可证 hostid 一律不入库。

## 基本

| 项 | 值 | 状态 |
|---|---|---|
| 器件 | XCKU5P（Kintex UltraScale+，16nm） | 已确认 |
| 封装 / 速度等级 | 厂家原理图标注 XCKU5P-1FFVB676I；本课目标 `xcku5p-ffvb676-1-i` | 资料已核对，实物丝印待核对；JTAG 仅确认 xcku5p |
| 板卡型号 / 厂商 | FNIC-KU5P Rev1.0 / 微相科技 MicroPhase，依据本机厂家资料 | 资料已核对 |
| FPGA 温度等级 | I，依据原理图完整料号 | 资料已核对 |
| 配置 Flash | TODO（型号/容量，是否支持 PCIe 单独 reprogram） | 待确认 |

## PCIe

| 项 | 值 | 状态 |
|---|---|---|
| 链路宽度 / 代数 | 原理图 PCIE 3.0 页及厂家 XDC 显示 TX/RX 0–7，共八条，目标 Gen3×8 | 资料核对；实际协商代数/宽度待含 PCIe 端点的位流和主机读回 |
| 插槽 | 主机 PCIe x16 插槽（Z790-P） | 已确认 |
| BAR 大小 | 05D 配置用户 AXI-Lite 4 KiB、DMA 控制 64 KiB | IP 配置已生成，实际系统资源分配待枚举读回 |
| 供电 | TODO（是否需要外接 6/8pin） | 待确认 |
| 当前状态 | 显卡下方 ×4 插槽；SRAM 为 e0 Gen3×4 诊断版，本地复位 0。2026-10-29 重启后首次 CPLL mask0001、四路 GT TX/RX 初始化完成；随后局部复位后未恢复，最终 PLL/done 低 | 首次实时 Polling.Compliance、无 L0/枚举；最终 Detect.Quiet 快照冻结。SYS_CLK MMCM 和四路 raw GTPOWERGOOD 高不等于插槽参考已合格；BAR/DMA 待测，见[三阶段实测](pcie-restart-observation-2026-10-29.md) |

## 存储与时钟

| 项 | 值 |
|---|---|
| DDR4 | TODO（位宽/容量/速率） |
| 参考时钟 | PCIe 插槽目标 100 MHz 差分输入 AB7/AB6，PERSTn=T19/LVCMOS12；缓冲后计数有活动但重复 ILA 采集的边沿间隔不稳定，同域 256 点校验通过；尚无稳定 100 MHz 或电气测量证据 |
| 用户时钟 | 厂家资料：100 MHz 单端 SYS_CLK，AB21 / LVCMOS18，BANK64 的 VCCO 为 1.8 V；第五课采用 IBUF/BUFG 接入 |
| 独立 GT 对照 | SYS_CLK 管理复位、四通道固定 8 Gb/s/QPLL1 的 e1 已实现并上板，PLL 仍未锁定；SYS_CLK 主机时间粗测约 100 MHz，e1 参考计数两次短采集无边沿。已恢复同一 e0，见[第五课 E](lesson05e-gt-isolation.md) |
| 板载可编程时钟 | 原理图：X2 为 25 MHz，Si5338 CLK2 经 B225_CLK0 到 V7/V6，独立于插槽 AB7/AB6；已在0x70只读两份page0，均LOS_CLKIN=1、输入选择IN1/2而板载源接IN3、输出格式保留值0。尚无有效输出频率证明，未写配置，见[第五课 F](lesson05f-si5338-readonly.md) |

## 高速接口

| 项 | 值 |
|---|---|
| GTY 收发器分配 | 原理图显示两个 QSFP28 各占一组四通道 GTY，PCIe 另占八条，合计十六条；每一接口的实际时钟与约束仍需交叉核对 |
| 光接口 | 两个 QSFP28 物理接口；物理连接器/25G lane 数量不等于独立 100GbE MAC/PCS 数量 |
| 100G 硬核 | KU5P 集成一个 100G Ethernet 硬核，见 [AMD XMP103 第四页](https://docs.amd.com/api/khub/documents/Fz8MLna3N2KIo_xWN_Iv3w/content)；不能直接作为两个独立的 100GbE 接收端 |

单口 100GbE 与 PCIe 可在同一 FPGA 工程并存，协议硬核和相应 GT 通道并不互相替代。按当前硬核方案先验收一个 100GbE 口；第二个接口如要同时运行独立 100GbE，需要额外经过验证的 MAC/PCS/FEC 实现与相应资源/授权。平均业务总量低于 100 Gb/s，不会消除第二个端口持续维持物理链路的要求。

不能用一个 CMAC 的数量推导“整张卡任意数据流加起来永远只能 100G”，也不能推导两个 QSFP28 已提供双 100GbE。厂家手册第八章展示双端口 Corundum 网卡及互 ping 操作，但现有文字没有给出两口均为 100GbE 的配置和持续吞吐证据。源工程和现场速率仍需核对。

厂家 XDC 中 `qsfp_0` / `qsfp_1` 的 bank 编号与原理图的连接器编号存在对应差异；构建网络位流前应按封装引脚、lane 和实物位置建立映射，不能只按名称选口。原始文件保留在本机下载/研究目录。

## 接收带宽与主机读出带宽

Gen3×8 只扣 128b/130b 编码后的单向理论上限为 `8 GT/s × 8 × 128/130 = 63.015 Gb/s`，即约 7.877 GB/s，实际 DMA 净带宽还要扣 PCIe 事务等开销。因此不能把持续的 100 Gb/s 原始数据全部经此接口送往主机；缓存也不能补足长期平均速率差。插到更高代数或更长的主板插槽不会升级卡本身。

如果实际协商只有 Gen3×4，上限进一步降至约 31.508 Gb/s。实际插槽电气宽度、链路代数和驱动吞吐都须读回与实测。对于 FX 的积分可见度，FPGA 内部处理后送出的数据量可显著低于原始采样，PCIe 预算应按实际输出产品与积分周期计算。

截至 2026-10-28，两路流水线已通过仿真与 OOC 布线；独立 PCIe 测试端点已实现并配置 SRAM，Windows 用户态程序已通过模拟端点/普通文件测试。网络接收、实际 PCIe 链路与 BAR/DMA 均尚未接通；不能把应用测试当作 DMA 测试。见[PCIe 阶段记录](lesson05d-pcie.md)。

## 调试接口

| 项 | 值 |
|---|---|
| JTAG | 板载排针 + Digilent 下载器（已验证可识别 `xcku5p_0`） |
| 串口 | TODO |
| LED / 按键 | 厂家资料：LED1=AF14、LED2=AF15，LVCMOS33、低有效；KEY1=AF13。第五课仅使用两个 LED，复位/启动由 VIO 控制 |

本次使用引脚在厂家手册、原理图和 XDC 之间交叉核对，来源哈希及板级实现范围见 [第五课 A](lesson05-board-replay.md)。原始厂家 PDF/XDC 保留在本机下载目录，仓库只包含自行编写的约束子集。

## 当前 PCIe IP 选择

| 用途 | 候选 | 备注 |
|---|---|---|
| PCIe 端点 | XDMA 4.2，Gen3×8 能力、AXI Stream 256 位/250 MHz | 05D 已生成；实际协商结果待链路建立 |
| 主机控制 | 用户 BAR → AXI-Lite 寄存器；DMA 控制 BAR；MSI | 当前用户态按常见 Windows XDMA 节点准备，仍需匹配内核驱动 |
| DMA 描述符 | XDMA descriptor engine，由主机驱动提交 | FPGA 测试源默认空闲，不自行生成主机地址/描述符 |
