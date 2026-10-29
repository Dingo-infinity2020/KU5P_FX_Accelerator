# Si5338 只读核对与实板采集

2026-10-29。已完成 FPGA I²C 读回、两份完整 page0 快照和实际总线波形检查。发现当前输入选择与板载 25 MHz 路径不一致，`LOS_CLKIN=1`，输出格式字段也是保留编码，因此**尚不能使用 Si5338 输出作为已知良好的参考源**。本阶段未写时钟配置、页选择或 NVM；实验后恢复了哈希相同的 PCIe e0 固件。

## 电气连接和只读边界

已目视复核本机厂家原理图 `FNIC-KU5P_SCH_Rev1.0.pdf` 的 PDF 第 5、12 页（图纸页号 05、13），并核对厂家引脚表：

| 网络 | FPGA 管脚与处理 |
|---|---|
| SCL / SDA | F14 / F13，BANK87/VCCO 3.3 V，LVCMOS33；板载 1 kΩ 上拉 |
| INTR / FPGA 侧 I2C_LSB | E13 / E12，只作输入并两级同步 |
| CLK_SEL | D13，只作输入，不改变时钟选择 |
| SYS_CLK | AB21/LVCMOS18，沿用独立管理时钟 |
| I²C 地址 | 固定 7 位 0x70，实板应答；不是扫描所有地址 |

SCL/SDA 只通过 IOBUF 输出 0 或高阻，DRIVE4/SLEW SLOW；DCP 重开后再次确认 IOBUF.I 接 GND。读回 E12 为高不能推导芯片地址为 0x71：原理图 R95 默认 NC，隔开 FPGA 网络与芯片地址脚，芯片侧另由 R96 接地。解析字段明确命名为 `fpga_i2c_lsb_net_high`。

每个事务固定为 `START E0 ACK pointer ACK STOP, START E1 ACK data NACK STOP`。地址指针是读取所需的选择操作，后面没有配置数据字节；状态机没有一般写寄存器接口。[Si5338 数据手册](https://www.skyworksinc.com/-/media/SkyWorks/SL/documents/public/data-sheets/Si5338.pdf) 的读时序支持此过程。禁止自动写 reg255 切页，所以只读当前页；若不是 page0，解析器不会套用 page0 位定义。

支持 SCL stretching、NACK、总线忙超时、事务超时和发送 1 时的仲裁丢失检查；异常释放两线，不自动产生 9 脉冲清总线或器件复位。VIO 命令只包含寄存器地址和触发翻转，另一个输出只复位 FPGA 读取器。

## 验证与实现

I²C RTL 仿真通过 10 项检查，覆盖正常读、255 地址、stretch、三处 NACK、总线忙、恢复、仲裁丢失和长 stretch 超时。仿真从设备会拒绝地址指针之后出现额外配置数据时钟。

| 只读 FPGA 固件 `465805f1` | 结果 |
|---|---|
| 布线后时序 | WNS +6.912 ns，WHS +0.016 ns |
| 路由 | 3958/3958，无 routing errors |
| CDC | `report_cdc -no_waiver` Critical=0，不增加 waiver |
| 时钟覆盖 | no_clock=0，内部未约束端点=0 |
| 资源 | 1709 LUT、2953 FF、2.5 BRAM36 等效块、0 DSP |
| 重开 DCP | 引脚和开漏审计逐字节相同，ILA 时钟周期 80 ns |

报告仍有异步输入/协议输出缺少同步 I/O delay 的计数 5/4；这些并非同步外部器件时序收敛的证明。I²C 慢时序由状态机、开漏约束、仿真和实际总线采集共同核对。新设计不含 GT/PCIe，不能用其 CDC=0 覆盖原 e0 的两项历史 CDC Critical。

## 实板读回

共完成 516 次读事务：首次页核对 1 次、状态波形对应读 1 次、两份快照各 257 次。两份快照顺序均为 `255,0..254,255`，全部 error=0、完成计数连续、页首尾均为 0；256 个地址字节在两次快照间**完全相同**。保留地址的读值仅存档，不用作配置模板。

| 项目 | 两次快照一致的结果 |
|---|---|
| 识别 | reg0=01，revision code1；reg2=26，低6位十进制38，符合 Si5338 家族 |
| 状态 | reg218=04，LOS_CLKIN=1；PLL_LOL/LOS_FDBK/SYS_CAL=0；reg241 bit7=0 |
| 输入选择 | reg28=83、reg29=00，P1DIV_IN=0，即 IN1/IN2；PFD 参考选 P1DIV_IN |
| 实际板载源连接 | 原理图 25 MHz 经选择器接 Si5338 IN3；CLK_SEL 实读0，选择板载 X2 |
| 四路输出 | reg31..34=02，MultiSynth 均 power-down；driver power-down 位0，reg230关闭位均0 |
| 输出格式 | reg36..39=00，格式 code0 为保留值，不能解释为 LVDS |

位定义按 [Si5338 Reference Manual](https://www.skyworksinc.com/-/media/Skyworks/SL/documents/public/reference-manuals/Si5338-RM.pdf) 的 reg28/29、31..39、218、230、241 解码。`PLL_LOL=0` 并不抵消输入丢失：手册明确该位不因外部参考输入丢失而置位。上述输入选择与原理图的矛盾是后续配置核对线索，**尚不能断言晶振坏了、器件从未配置或 NVM 损坏**。

8192 点 ILA 在 12.5 MHz 采样，实际捕获并解码出 `E0 ACK DA ACK STOP / E1 ACK 04 NACK STOP`，与 reg218 的 VIO 读回一致。逻辑探针被 Vivado 拆成多个片段，使用导出的 port/first_bit/width 表重组，并校验重叠、完整性和重复 busy。该波形只有指针写，无配置数据写；其他事务还受相同 RTL 状态机约束。

同源心跳严格每 32 个 ILA 样点重复，证明本次 /8 采样与计数比率一致；这是同源比率检查，**不是独立测得绝对 100 MHz 或时钟质量**。

Si5338 CLK2 到 V7/V6，而 PCIe 插槽参考到 AB7/AB6。两者不是同源；本次异常不直接解释原 PCIe 参考输入，也不能把未验证的板载输出接进 PCIe 端点。

## 回退和下一步

从保存目录恢复哈希相同的 e0（465805e0）bit/LTX/DCP，局部复位 1→0 并核对读回。新采集状态 6 次、PHY 12 次、训练 12 次：PHY 当前字均 `00002c0f0000`，SYS_CLK MMCM 锁定、四路 raw GTPOWERGOOD 高，CPLL/QPLL1 仍低，TX/RX reset-done 仍低。训练快照只有 Detect.Quiet、sequence1 不更新；Windows 10EE:9034 数量0，BAR/DMA 未测试。JTAG 6 MHz；没有重启、改 BIOS、装驱动或写 Flash。

下一阶段先形成可复核的本地参考频率计划：核对 IN3/25 MHz、输出电压/电气格式、CLK2 目标频率及共享 PLL 对其他输出的影响，并准备逐项恢复和读回校验。只有输出确实有效后才在独立 GT 工程对照 V7/V6，先观察锁定与复位，再考虑原 PCIe。当前原始寄存器读值不应直接整页回写，尤其不能把保留或只读值当作初始化脚本。

## 复现与证据

用全新仓库外目录运行，入口只构建，不自动上板：

```powershell
./scripts/run_si5338_readonly.ps1 `
  -VivadoBin D:/AMDDesignTools/2026.1/Vivado/bin `
  -Python <本机Python路径> `
  -BuildDir D:/work/build/KU5P_FX_Accelerator/si5338_fresh
```

`si5338_manifest.py` 冻结源文件和仿真标记；`check_si5338_build.py` 接受时序、路由、未豁免 CDC、原生完整日志及开漏审计后才产生 proof。硬件操作在 `tcl/lesson05f_si5338_hardware.tcl`，source 仅定义过程；任何上板前均应保存并核验现有固件的回退文件。

`si5338_readonly.py dump <dump.tsv> --output <summary.json>` 校验两份读回；`trace <capture.csv> --layout <capture_layout.tsv> --output <trace.json>` 校验物理协议。全部原始寄存器图、ILA、报告、失败尝试、源快照及回退文件保存在 `D:/work/build/KU5P_FX_Accelerator/lesson05f_si5338_readonly`，不加入 Git。仓库保存自编源码、约束、脚本和[验证摘要](validation/lesson05f-si5338-readonly-2026-10-29.json)，没有 RFSoC 原工程或生成的 AMD IP。
