# 第一次在 Vivado 中查看自己的电路

日期：2026-10-27；对应 Vivado 2026.1。近期主线为 FX，FFTT 保留为长期目标。

2026-10-28 更新：[第二课两通道相关器](lesson02-correlation.md) 已提供可操作的 GUI 工程，可以重新运行仿真和综合。本文仍保留第一课 DCP/WDB 的查看方法。

[第三课](lesson03-fft-fx.md) 进一步提供双 FFT 与 512 频道 X 的完整工程，可在 Vivado 中查看实际 FFT IP 配置与频道化波形。

## 1. 综合是什么

RTL 描述寄存器和运算之间的硬件关系。综合把这些描述转换成目标 FPGA 能实现的元件与连接，形成网表。这里不是让一个 CPU 逐条执行 `I*I+Q*Q`，而是建立相应的算术与状态电路。

| 阶段 | 回答的问题 | 本课状态 |
|---|---|---|
| RTL 展开 | 工具怎样理解模块、端口和逻辑结构？ | 没有单独保存展开结果；已有源码 |
| 行为仿真 | 输入、停顿和复位发生时，数值及行为是否符合定义？ | 已通过，保存 WDB 波形 |
| 综合 | 逻辑怎样映射为 FPGA 资源？用了多少资源？ | 已完成，保存 DCP 检查点 |
| 实现 | 电路放在哪里、如何连线、实际延迟是否满足要求？ | 尚未布局布线 |
| 配置与上板 | 如何配置 FPGA，并观察真实信号？ | 尚未生成本模块 bitstream 或下载 |

仿真、综合、实现与实测分别提供不同证据。综合后的正时序裕量不能代替布局布线、板级约束或实际数据验收。

## 2. 我这次实际怎么运行

入口 `scripts/run_lesson01.ps1 -Synthesize` 先生成 Python 参考结果，编译 testbench 并运行 XSIM。确认 PASS 后，才启动同一套 Vivado 的批处理模式，执行 [synth_lesson01.tcl](../tcl/synth_lesson01.tcl)。

脚本的重要命令包括：

```tcl
synth_design -mode out_of_context -top complex_power_accumulator -part xcku5p-ffvb676-1-i
create_clock -name clk -period 10.000 [get_ports clk]
```

前面还有 `create_project -in_memory` 和 `read_verilog -sv`，后面调用资源/时序报告，并用 `write_checkpoint` 保存设计。

- `part` 是指定的映射目标；当前工具已装这个 KU5P part，但不等于实物料号、板级管脚和参考时钟已经核对。
- `top` 是待综合的硬件顶层。testbench 是测试程序，不包含在本次综合源文件中。
- `out_of_context` 表示把小模块单独拿出来检查，没有接入整板的时钟、网络和管脚。
- 10 ns 是报告使用的时钟目标，对应 100 MHz。此脚本在综合后才设置该约束，因此不能声称综合器已经按它做了时序优化。
- DCP 保存综合后的设计；本次没有生成磁盘上的 `.xpr` 工程文件。

Tcl 批处理和图形界面使用同一套 Vivado 工具。脚本保存可复现步骤，GUI 帮助我们理解电路、波形和报告；GUI 的 Tcl Console 也能执行这些命令。

## 3. 现在就能打开综合结果

启动一个新的、没有打开其他设计的 Vivado 2026.1 窗口，找到底部的 **Tcl Console**，粘贴：

```tcl
source {D:/work/KU5P_FX_Accelerator/tcl/open_lesson01_results.tcl}
```

辅助脚本只打开已有检查点并生成资源报告，不运行 bitgen 或硬件操作；若已有设计打开，它会提示使用单独窗口，避免替换当前设计。脚本按默认的仓库外构建目录定位文件。

也可手动逐条执行：

```tcl
open_checkpoint {D:/work/build/KU5P_FX_Accelerator/lesson01_power/complex_power_accumulator_synth.dcp}
report_utilization
get_cells -hierarchical -filter {REF_NAME == DSP48E2}
```

本次应看到 2 个 DSP48E2、189 LUT、225 个触发器，BRAM/URAM 为零。辅助脚本生成名为 `lesson01_utilization` 的报告，并打印两个 DSP 的实例名。

## 4. 先观察三个地方

1. **Netlist（网表）与 Schematic（原理图）**：在网表中找 `i_squared`、`q_squared`，选择对象并打开 Schematic。先看两个乘法器及周围连接，再逐步展开加法和寄存器，避免一开始展开整张图。
2. **Utilization（资源报告）**：DSP 是适合乘法等算术的专用块；LUT 实现逻辑和选择；触发器保存状态。代码表达式与最终元件不是简单的一行对应一个，工具会优化映射。
3. **Timing / Device**：可观察时序报告及器件结构，但当前没有布局布线。独立综合时钟源和端口延迟还未绑定整板条件，不能据此宣称已在实物上达到 100 MHz，也不能把未放置元件当成最终布局。

## 5. 打开保存的仿真波形

建议在另一个新的 Vivado 窗口查看波形，先把它与综合网表分开。在 Tcl Console 输入：

```tcl
open_wave_database {D:/work/build/KU5P_FX_Accelerator/lesson01_power/lesson01_power.wdb}
```

这是静态仿真记录，可查看过去的值，不能修改输入后继续运行。若波形窗口为空，在 Scopes 中选择 `tb_complex_power_accumulator/dut`，从 Objects 选择信号并使用 Add to Wave Window，然后缩放到关心的时间范围。

先加入 `clk`、`rst_n`、I/Q、输入 valid/ready、`samples_accepted`、`accumulator`、输出 valid/ready、`m_axis_power_sum` 和 `m_axis_sample_count`。I/Q 用有符号十进制，功率和计数用无符号十进制。

按三个问题读：这个上升沿是否 valid 与 ready 同时为 1？累计 M 个成功传输后是否输出正确总和？输出 ready 为 0 时，结果是否保持不变？

波形中有测试故意插入的复位和配置改变；它不是 RFSoC 实测记录。当前的成功传输数也不等于真实观测时间。

## 6. 后续可以在项目模式做什么

当 GUI 工程中已经加入正确的源码、testbench、测试数据和约束后，Flow Navigator 的 Open Elaborated Design、Run Simulation、Run Synthesis、Open Synthesized Design、Run Implementation 等入口分别对应上述阶段。

当前保存的是脚本流程的结果。打开 DCP 后，不能假设已经具备完整 GUI 工程和所有仿真数据配置。这次先看现有 DCP/WDB；下一课沿 FX 路线增加两路互相关，再学习完整的工程仿真设置。

官方依据：[UG904 打开综合检查点](https://docs.amd.com/r/en-US/ug904-vivado-implementation/Creating-and-Opening-the-Synthesized-Design-in-Non-Project-Mode)、[UG901 分析综合结果](https://docs.amd.com/r/en-US/ug901-vivado-synthesis/Analyzing-Synthesis-Results)、[UG835 打开静态波形数据库](https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/open_wave_database)。
