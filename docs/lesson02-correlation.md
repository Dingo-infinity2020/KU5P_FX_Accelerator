# 第二课：两通道复数相关器

日期：2026-10-28。近期主线为 FX；本课实现其中的两通道 X，后续接入 512 点时间 FFT。FFTT 仍为长期目标。

## 1. 我们增加了什么

输入是一对已经对齐的复数电压 `A=Ia+jQa`、`B=Ib+jQb`。每累计 M 对，原子地输出两个自相关和一个复数互相关：

```text
Paa = Σ(Ia² + Qa²)
Pbb = Σ(Ib² + Qb²)
Re(Vab) = Σ(Ia·Ib + Qa·Qb)
Im(Vab) = Σ(Qa·Ib − Ia·Qb)
Vab = Σ(A·conj(B))
```

这里的 Σ 对同一个窗口的成功输入传输求和。`Vba=conj(Vab)`，所以两通道相关矩阵只有三项独立相关：Paa、Pbb、Vab。它是未来十六通道 136 项独立相关的起点。

输入可以代表同一频道的频谱帧序列；本课用合成电压检查运算。模块本身没有时间 FFT/PFB，尚不能从 RFSoC 原始时域数据输出完整的频率可见度。

## 2. 先亲手算一组数

设置 M=4，每次给 `A=3+4j`、`B=1+2j`。单次有：

`A·conj(B)=(3+4j)(1−2j)=11−2j`

因此四次后的输出应为：

| 输出端口 | 数值 | 含义 |
|---|---:|---|
| `m_axis_auto_a` | 100 | 4×25 |
| `m_axis_auto_b` | 20 | 4×5 |
| `m_axis_cross_real` | 44 | 4×11 |
| `m_axis_cross_imag` | −8 | 4×(−2) |
| `m_axis_sample_count` | 4 | 成功接收的样本对数 |

这些是未归一化整数总和。若要平均可见度，下游再除以计数；本课没有硬件除法、物理单位或校准求解。

相位方向也有明确约定：若 B 相对 A 超前 90°，即 `B=jA`，则 `Vab=−jΣ|A|²`，虚部应为负。交换 A/B 后，两个功率交换，实部相同，虚部反号。测试会检查这些关系，防止共轭方向接反。

## 3. FPGA 如何同时处理多对样本

本课增加了乘法寄存器，使运算形成流水线：

```mermaid
flowchart LR
    A[同拍输入 A、B] --> P[8 个乘法结果寄存器]
    P --> S[形成两路功率与互相关实虚部]
    S --> C[4 个累加状态]
    C --> O[窗口结束：输出总和与计数]
```

乘法寄存器保存上一拍的数据；累加级处理它的同时，乘法级可以接收下一对。RTL 中的非阻塞赋值 `<=` 让时钟上升沿读取旧寄存器值、再更新新值，并不表示两级会在同一拍依次执行完。

在没有停顿时，以 M=4 为例：

| 上升沿 | 乘法级接收 | 累加级处理 | 上升沿后的结果状态 |
|---|---|---|---|
| t0 | 第 1 对 | 无有效乘积 | 无输出 |
| t1 | 第 2 对 | 第 1 对 | 部分累加 |
| t2 | 第 3 对 | 第 2 对 | 部分累加 |
| t3 | 第 4 对 | 第 3 对 | 部分累加 |
| t4 | 可接收下个窗口第 1 对 | 第 4 对 | 本窗口结果 valid=1 |
| t5 | 可继续接收 | 下个窗口第 1 对 | 若 ready=1，上游窗口结果被接收 |

窗口末尾标签 `product_last` 和计数 `product_count` 与乘积一起前进。输入级在 t3 已经完成窗口计数，累加级要到 t4 才用完末样本；不能直接拿已经更新的输入计数判断累加结束。

M=1 且下游持续 ready 时，同样可以连续每拍接收一对、在流水线填充后每拍输出一个窗口。这个吞吐行为由仿真检查；实际可用时钟频率仍需布局布线和硬件验证。

## 4. 接口、停顿、配置与复位

所有信号属于同一个 `clk` 域。一个输入 valid/ready 同时覆盖 A、B 四个 I/Q 分量，只在上升沿 `s_axis_tvalid && s_axis_tready` 时接收一对。上游应保证等待 ready 时 valid 和数据稳定。

**A、B 的时间和频道对齐由上游保证。** 本模块没有两个独立输入 FIFO，也不会根据包号或到达顺序自动对齐 RFSoC。不能把两块板的独立数据接口直接连到这里。

| 项目 | 规则 |
|---|---|
| 数据位宽 | A、B 的 I/Q 各有符号 16 位 |
| 输出位宽 | 自相关各无符号 64 位；互相关实部、虚部各有符号 64 位；计数 32 位 |
| 配置 M | 在每个窗口第一对被接收时锁存；M=0 时不启动新窗口 |
| 窗口中修改 M | 当前窗口仍按原 M 完成，新值供下个窗口使用 |
| 下一个 M 变为 0 | 已在流水线中的旧窗口仍能完成 |
| 下游不接收结果 | 输出、乘积及累加状态保持，输入 ready=0 |
| 解除反压 | 已在途乘积继续处理，结果不重复、不丢失 |
| `rst_n=0` | 同步低有效；取消部分累加、在途乘积和待接收输出 |

采用整条流水线一起停顿，便于学习和验证。它的寄存器容量有限，持续输出反压会传到输入。真实 ADC 不能因此停止采样；接入网络前还要设计缓存、吞吐预算及溢出标记。

接口只采用 valid/ready 的握手约定，没有完整 AXI4-Stream 的频道、帧、时标和配置元数据。模块只保存一对逻辑通道、一个频道的累加状态，不能直接混入多个频道或天线对。

M 仍表示成功传输数。后续科学积分要按计划频谱帧号划定名义窗口，并另记有效贡献 W；缺样不能通过延长接收时间来补齐 M。本课也不实现真实一秒积分。

## 5. 位宽和正负号

16 位有符号乘法保留完整 32 位结果。互相关的加减先把乘积符号扩展到 33 位，再运算；之后符号扩展到 64 位累加。功率则按非负值扩展。

例如四个输入分量全为 −32768 时，互相关实部和两个自相关都为 `2³¹`，不能放入有符号 32 位正数。虚部则为零。测试包含这个边界和正负大虚部。

单次四项输出的绝对值可保守界定为不超过 `2³¹`。对于 32 位非零 M：

`|累计值| ≤ (2³²−1)×2³¹ = 9223372034707292160 < 2⁶³`

因此当前 16 位输入定义下，64 位输出足够。最大 M 的完整传输没有仿真数十亿拍；采用数值上界证明，再检查最大 M 的部分窗口不会提前结束。FFT/PFB 引起输入位宽变化时需要重新分析，不能随意截位后沿用这一结论。

## 6. 复现与源文件

在仓库目录打开 PowerShell：

```powershell
$python = 'C:\path\to\python.exe'
$vivadoBin = 'D:\AMDDesignTools\2026.1\Vivado\bin'
.\scripts\run_lesson02.ps1 -Python $python -VivadoBin $vivadoBin -Synthesize -CreateProject
```

Python 只需标准库。可以省略 `-Synthesize` 或 `-CreateProject`；仿真通过后才执行这些步骤。默认产物在仓库外 `D:/work/build/KU5P_FX_Accelerator/lesson02_x`，也可用 `-BuildDir` 指定仓库外目录。已有 GUI 工程不会被创建脚本覆盖。

| 源文件 | 用途 |
|---|---|
| [two_channel_correlator.sv](../rtl/two_channel_correlator.sv) | 两路自相关、互相关及流水线状态 |
| [generate_lesson02_vectors.py](../scripts/generate_lesson02_vectors.py) | Python 任意精度参考、相位/共轭/边界向量 |
| [tb_two_channel_correlator.sv](../sim/tb_two_channel_correlator.sv) | 数值比对、连续传输、反压、配置和复位测试 |
| [run_lesson02.ps1](../scripts/run_lesson02.ps1) | 生成向量、编译、仿真、可选综合和 GUI 工程 |
| [lesson02_ooc.xdc](../constraints/lesson02_ooc.xdc) | 算术模块的 10 ns 时钟目标 |
| [synth_lesson02.tcl](../tcl/synth_lesson02.tcl) | 综合前读入时钟约束，保存 DCP 与报告 |
| [create_lesson02_project.tcl](../tcl/create_lesson02_project.tcl) | 创建外部 GUI 工程，直接引用仓库中的源码 |

与第一课相比，这次时钟约束在综合前通过 `read_xdc` 读入，使综合器看到目标周期。它仍然没有板级管脚、输入/输出延迟、真实时钟源或布局布线，不能把综合时序报告当作实物运行证明。[AMD UG903 非工程模式约束流程](https://docs.amd.com/r/en-US/ug903-vivado-using-constraints/Non-Project-Flows) 说明了综合前读约束的顺序。

## 7. 本次验证结果

XSIM 已通过：253 个 Python 参考窗口、16752 对参考输入，连同定向协议场景，共比较 289 个输出窗口、接收 16795 对输入。统计包含复位故意取消的输入和结果。

- 包含固定相位、交换输入、相同/反相输入、零输入、精确抵消、4096 对长累加、7 个边界值的全部 2401 种四分量组合，以及 120 组随机窗口和对应的交换窗口。
- 每个参考窗口还检查 `Vba=conj(Vab)` 以及 `|Vab|²≤Paa·Pbb` 的精确整数关系。
- 输出反压共经历 96 拍，其中 8 拍同时持有尚未累加的乘积；输出和在途状态保持检查通过。
- 连续接收最长 98 拍；同拍接收输入和输出的情况出现 246 次。
- 覆盖 M=0、M=1、非二次幂 M、窗口内改 M、最大 M 的部分窗口，以及部分累加、在途乘积和待输出结果三处复位。

构建目录中的 `simulation_pass.txt`、`vectors.json`、`verification.json`、`lesson02_x.wdb` 保存实际证据。`verification.json` 记录源码 SHA256，便于判断结果是否对应当前源码；修改源码后应重跑。

还通过工程模式的 `launch_simulation` 实际打开所生成的 `.xpr`，验证参考数据自动复制、编译和仿真，同样得到 `PASS windows=289`。检查记录为构建目录中的 `project_flow_verified.txt`。

Vivado 2026.1 已对 `xcku5p-ffvb676-1-i` 完成独立综合：475 LUT、643 个触发器、8 个 DSP48E2，BRAM/URAM 为零，没有黑盒。8 个 DSP 对应四个自相关平方乘法和四个互相关乘法；综合器还可能把邻近加减运算合入 DSP，网表不一定与 RTL 表达式逐项对应。

`reports/check_timing_synth.rpt` 中无时钟寄存器和未约束内部端点均为零；99 个输入、290 个输出尚无端口延迟约束，并有独立时钟源 `HD.CLK_SRC` 提示。综合后的内部时序检查不是板级时序收敛或最高频率证明。尚未布局布线、生成本模块 bitstream 或上板。

## 8. 现在可以在 Vivado 中亲手操作

打开一个空的 Vivado 2026.1 窗口，在 Tcl Console 输入：

```tcl
open_project {D:/work/build/KU5P_FX_Accelerator/lesson02_x/vivado_project/lesson02_x.xpr}
```

这是可重新运行仿真的 GUI 工程，设计顶层为 `two_channel_correlator`，仿真顶层为 `tb_two_channel_correlator`。Simulation Sources 包含生成的 `windows.txt` 参考数据。不要把 testbench 设置成综合顶层。

1. 点击 **Run Simulation → Run Behavioral Simulation**。测试会运行到 `$finish`，在控制台寻找 `PASS windows=289`；任一数值或协议检查失败会报 Fatal。
2. 在 Scopes 选择 `tb_two_channel_correlator/dut`，把输入 I/Q、valid/ready、`product_valid`、`product_last`、四个 accumulator 及输出加入波形。互相关实部/虚部和输入 I/Q 用有符号十进制显示，功率和计数用无符号十进制。
3. 找到 `cfg_window_samples=4`、A 为 `3+4j`、B 为 `1+2j` 的区间，检查输出 `100、20、44、−8、4`。再看 ready=0 区间，在途乘积和输出应一起保持。
4. 关闭仿真后，可用 **Run Synthesis → Open Synthesized Design** 自己综合并看网表。该工程已设置独立综合模式，所用约束仍限于算术模块。

也可在另一个空 Vivado 窗口直接查看已完成的综合结果：

```tcl
open_checkpoint {D:/work/build/KU5P_FX_Accelerator/lesson02_x/two_channel_correlator_synth.dcp}
report_utilization
get_cells -hierarchical -filter {REF_NAME == DSP48E2}
```

查看本次批处理保存的静态波形则用：

```tcl
open_wave_database {D:/work/build/KU5P_FX_Accelerator/lesson02_x/lesson02_x.wdb}
```

GUI 工程的重新仿真、重新综合会生成各自的运行目录，不会自动替换上述批处理的 WDB/DCP 或 `verification.json`。后者对应 `run_lesson02.ps1` 的那次运行。

本阶段完成后，下一步接入两路固定 512 点时间 FFT，明确标度、频谱顺序和相位，再与本课的 X 组成最小 FFT-FX。PFB、多频道状态、观测时标和真实 RFSoC 网络接入仍按路线逐步加入。

2026-10-28 更新：[第三课 FFT-FX](lesson03-fft-fx.md) 已接入双 FFT，并为 512 个频道分别累加，完整链路仿真通过。
