# 板卡信息

> 本文件只放**可公开**的硬件信息。序列号、MAC、许可证 hostid 一律不入库。

## 基本

| 项 | 值 | 状态 |
|---|---|---|
| 器件 | XCKU5P（Kintex UltraScale+，16nm） | 已确认 |
| 封装 / 速度等级 | TODO（看器件丝印，`ffva676` 或 `sfva784`） | 待确认 |
| 板卡型号 / 厂商 | TODO | 待确认 |
| FPGA 温度等级 | TODO（E / I / 工业级） | 待确认 |
| 配置 Flash | TODO（型号/容量，是否支持 PCIe 单独 reprogram） | 待确认 |

## PCIe

| 项 | 值 | 状态 |
|---|---|---|
| 链路宽度 / 代数 | TODO（按原理图与实测 link status） | 待确认 |
| 插槽 | 主机 PCIe x16 插槽（Z790-P） | 已确认 |
| BAR 大小 | TODO（决定是否必须开 Above 4G Decoding） | 待确认 |
| 供电 | TODO（是否需要外接 6/8pin） | 待确认 |
| 当前状态 | FPGA 未配置时 PCIe 硬核不响应，主机侧枚举不到属正常现象 | 已验证 |

## 存储与时钟

| 项 | 值 |
|---|---|
| DDR4 | TODO（位宽/容量/速率） |
| 参考时钟 | TODO（PCIe refclk 来源、板载晶振频率） |
| 用户时钟 | TODO |

## 高速接口

| 项 | 值 |
|---|---|
| GTH 收发器使用情况 | TODO |
| 光模块 / SMA 接口 | TODO |

## 调试接口

| 项 | 值 |
|---|---|
| JTAG | 板载排针 + Digilent 下载器（已验证可识别 `xcku5p_0`） |
| 串口 | TODO |
| LED / 按键 | TODO |

## IP 选型（待定）

| 用途 | 候选 | 备注 |
|---|---|---|
| PCIe 端点 | XDMA / QDMA / PCIe Subsystem | XDMA 生态最成熟；驱动官方仅 Linux |
| 主机内存访问 | XDMA AXI Master + BAR | 需确认 64bit BAR / MSI-X |
| DMA 描述符 | 自带 descriptor engine | 与主机驱动匹配 |
