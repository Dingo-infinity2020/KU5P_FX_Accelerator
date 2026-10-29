# 第三课：两路 512 点时间 FFT 接入 X

日期：2026-10-28。近期主线为 FX；本课把 F 和 X 接起来，形成分帧回放用的两通道 FFT-FX。FFTT 空间变换仍保留为长期目标。

## 1. 这次的数据走向

```mermaid
flowchart LR
    T[512 对时域 I/Q] --> D[分别向两个 FFT 可靠送入]
    D --> F[两个 512 点时间 FFT]
    F --> J[核对频道索引与帧尾后配对]
    J --> Q[除以 1024、舍入回 16 位]
    Q --> X[复用第二课：两路自相关与复数互相关]
    X --> R[512 个频道各自积分 M 帧]
    R --> O[按频道输出相关值、计数与本地窗口号]
```

第二课只保存一对天线、一个频道的状态。本课复用其乘积核心，但为 512 个频道分别保存累加值，避免把不同频率混进同一结果。

目前 F 使用矩形窗、连续 512 点分块、无重叠，没有 PFB。输入是已经对齐的两路时域复数电压，仍未加入 RFSoC UDP 解析、跨板时间对齐或时钟域转换。

## 2. 时间 FFT 做了什么

每个天线分别计算正向变换：

`X[k] = Σ(n=0..511) x[n] · exp(−j·2π·k·n/512)`

采用自然顺序输出，`k=0..511`，没有在硬件中做 fftshift。给定复数采样率 fs：

| 频道 | 频率解释 |
|---|---|
| 0 | 直流 |
| 1..255 | `k·fs/512` |
| 256..511 | `(k−512)·fs/512`，其中 256 是负 Nyquist 边界的表示 |

例如把 fs 定义为 100 MS/s，频道间隔为 195.3125 kHz，k=128 对应 +25 MHz，k=384 对应 −25 MHz。这里只解释采样率与索引；它不证明某个 RFSoC 模式具有完整平坦的 100 MHz 有效科学通带。

本课采用本机 Vivado 2026.1 自带的 AMD FFT v9.1，Tcl 配置固定为 512 点、单通道、流水线架构、自然顺序、正向变换、非实时握手。项目中生成一个 IP 定义，RTL 实例化两份，分别处理 A/B；两份硬件资源都计入综合。

## 3. 位宽、舍入和最终标度

输入每个 I/Q 分量是有符号 16 位。FFT 选用不缩放定点模式，输出分量宽度为 `16+log₂(512)+1=26` 位；旋转因子宽度为 24 位，蝶形选择收敛舍入。不缩放保留了整数位增长，旋转因子和内部小数位仍有定点误差，不能等同于无限精度 DFT。

FFT IP 的 26 位分量各填充到 32 位，实部在低 32 位、虚部在高 32 位；包装层提取 `[25:0]` 与 `[57:32]`。频道索引通过 TUSER 核对。

为了接回第二课的 16 位相关核心，本课定义：

`E[k] = saturate16(round_ties_even(X_integer[k] / 1024))`

- 除数 1024 等于 2N。对本课合法输入，它给复数分量留出余量；仍保留显式饱和与 `status_clip` 诊断。
- 舍入采用最近整数，中点取偶数。例：512/1024 → 0，1536/1024 → 2，−512/1024 → 0，−1536/1024 → −2。
- `status_clip` 是复位后保持的历史告警，置位后需要检查数据和标度。本课测试要求所有实际合法输入均不触发。

X 计算 `Vab[k]=Σ(Ea[k]·conj(Eb[k]))`。相对于未缩放 DFT 的整数结果，电压标度为 1/1024，功率和可见度标度为 **1/1048576**，另有明确的定点舍入误差。输出为总和；平均相关值需再除以该频道的贡献计数 M。

64 位自相关、64 位有符号互相关和 32 位计数沿用第二课的容量上界。最终物理单位还需要输入量化、模拟链路增益、FFT/PFB 归一化与校准定义。

依据：[AMD PG109 位宽增长](https://docs.amd.com/r/en-US/pg109-xfft/Finite-Word-Length-Considerations)、[舍入实现](https://docs.amd.com/r/en-US/pg109-xfft/Rounding-Implementation)、[频道索引](https://docs.amd.com/r/en-US/pg109-xfft/XK-Index)。

## 4. 一次积分怎样走完

配置 `cfg_window_frames=M`，M 为 1 到 2³²−1：

1. 窗口第一帧的第一对时域样本被接收时锁存 M；M=0 时不启动新窗口。
2. 每接收 512 对时域样本，产生一对 FFT 帧。包装层为每个 FFT 独立记录待发送数据，确保其中一份先 ready 时不会重复或遗漏另一份的数据。
3. 两路 FFT 输出都有效且频道标签一致时，送入 X。若标签、顺序或帧尾不一致，`status_protocol_error` 保持为 1，停止配对与继续输入，复位后重新开始。
4. X 每次处理一个频道，读取该频道的旧累加值，加入新乘积，再写回。窗口第一帧直接以零作为旧值。
5. 前 M−1 帧仅更新 512 组状态；第 M 帧按 k=0..511 输出完整相关谱，下游反压时结果与元数据一起保持。
6. 末频道的结果被接收后，本地窗口号加一，允许启动新窗口。

所有接口属于同一个 clk 域，采用同步低有效复位。每个输入传输原子地包含 A/B 四个分量；上游必须在等待 ready 时保持 valid 和数据。固定每 512 个成功传输组成一帧，输入没有独立 TLAST；数据源在复位后必须从约定的帧起点开始。

RAM 不做逐项复位清零。每个新窗口第一帧绕过旧 RAM，之后只读取已经写过的频道，因此复位后的残留内容不会参与新结果。这也便于综合器把状态映射成块 RAM。

四组 `512×64` 位的频道累加存储合计 16 KiB；它保存两路自相关和一路复数互相关，不包含 FFT 内部缓冲。

复位取消未装满的 FFT 帧、FFT 在途数据、未完成积分和未被下游接收的结果；本地窗口号回零。它不是观测会话或绝对时标。

## 5. 输出包含什么

只有在 `m_axis_tvalid && m_axis_tready` 的上升沿，以下字段共同构成一个结果：

| 字段 | 含义 |
|---|---|
| `m_axis_bin` | 9 位频道号，0..511 |
| `m_axis_tlast` | 本窗口谱的末频道标记，k=511；仅 valid 时有意义 |
| `m_axis_window_id` | 32 位本地窗口序号，复位为零，按模 2³² 计数 |
| `m_axis_sample_count` | 每个频道实际累计的频谱帧对数 M |
| `m_axis_auto_a/b` | 两路自相关总和，各无符号 64 位 |
| `m_axis_cross_real/imag` | `Σ(A·conj(B))` 的实部与虚部，各有符号 64 位 |

M 现在数的是**每个频道的频谱帧对**，与第二课输入一个电压对时的计数单位不同。只有输入连续、无丢样、无重叠时，M 帧才对应 M×512 个原始采样时刻。

当前回放接口的停顿只改变传输时间，未提供绝对采样时间。科学积分仍需下一阶段引入源身份、频谱帧时标、有效贡献 W、配置版本和计划时间窗口，防止丢失贡献导致窗口延长。

## 6. 用一个可手算的谱线验收

测试 `positive_bin128` 的 A 按下列四点重复 128 次构成一帧：

`16384, +j16384, −16384, −j16384`

B=jA，相对 A 超前 90°。这是一根精确落在 k=128 的谱线。FFT 后除以 1024，A[k128]=8192，B[k128]=j8192，其余频道为零。

累计三帧应输出：

| k=128 的输出 | 结果 |
|---|---:|
| Paa | 201326592 |
| Pbb | 201326592 |
| Re(Vab) | 0 |
| Im(Vab) | −201326592 |
| count | 3 |

虚部的负号来自固定共轭方向 `A·conj(B)`。另一个测试把相位旋转方向反转，峰值移动到 k=384，用于检查正负频率和输出顺序；随机输入交换 A/B 后，功率交换、实部不变、虚部反号。

## 7. 参考模型与自检查仿真

验证分成两层：

- **独立数学参考**：NumPy 对相同的整数时域输入计算浮点 FFT，检查频谱方向、频道顺序和数值。预先固定允许界为原始 FFT 分量误差不超过 128 个整数单位，除以 1024 后不超过 1 个输出整数单位。这是分量绝对误差界，不是所有弱信号频道都具有相同的相对精度。
- **定点逐位参考**：从本机 Vivado 的安装包解出 AMD C model 到仓库外，配置与硬件相同，产生原始 26 位期望值。Python 再精确计算最近偶数舍入及每频道整数相关、跨帧累加。RTL 的原始 FFT、电压量化和最终相关输出都须精确匹配，不使用容差。

AMD C model 与 FFT IP 属于同一厂商实现体系，因此还需要上面的独立 NumPy 检查；它们提供的证据不同。模型 DLL、头文件、生成 IP、测试数据与 Vivado 产物都不入库，参考程序记录安装包和模型文件的 SHA256。

12 个参考窗口共 31 对 FFT 帧、15872 对时域输入、6144 个最终频道结果，包含：零、冲激、直流、正/负频道单音、最小负数、Nyquist/直流边界、多音且帧间幅度改变、随机独立输入及交换输入、非整数频道泄漏、一侧零输入。

协议场景另检查输入间隙、输出反压、M=0、窗口内修改 M，以及装载中、积分中、输出阻塞时复位。测试还故意损坏一侧 FFT 频道标签，检查错误保持、阻止错配结果和复位恢复。未通过 FPGA 或网络执行这类故障注入。

完整链路 XSIM 已通过：12 个窗口、6144 个最终频道结果、15872 对 FFT 及量化结果逐项精确匹配参考值，所有参考条目均被消费。独立 NumPy 对照中，原始 FFT 分量最大绝对差约 15.697 个整数单位，量化后最大差 1 个单位，均在预先定义的界内。

本次检查经历 2125 拍输出反压、39931 拍 FFT 到 X 的等待、86864 拍输入等待；源、FFT 与下游的停顿属于回放握手。参考记录从首个输入到末个输出共 109568 拍，不包含前后的故意取消/故障场景。仿真故意损坏标签一次，并验证复位恢复。

Vivado 2026.1 已对 `xcku5p-ffvb676-1-i` 完成含两份 FFT 的整体独立综合，所有 IP 已解析，没有黑盒：

| 资源 | 数量 |
|---|---:|
| LUT（含 1882 个移位寄存器 LUT） | 6345 |
| 触发器 | 11632 |
| DSP48E2 | 52 |
| RAMB36E2 | 4 |
| RAMB18E2 | 12 |
| Block RAM Tile，折合 36Kb 单元 | 10 |
| URAM | 0 |

每份 FFT 用 22 个 DSP、6 个 RAMB18；X 乘积核心用 8 个 DSP，四组频道累加用 4 个 RAMB36。资源使用详见 `reports/utilization_hierarchical_synth.rpt`。这提供了两通道模块的实测综合预算，尚不能据此直接推断十六通道、全带宽系统的最终使用量。

时序检查中无时钟寄存器和未约束内部端点均为零；99 个输入、334 个输出尚未设置端口延迟，独立时钟源 `HD.CLK_SRC` 也未绑定板级位置。当前没有布局布线、bitstream 或上板结果。

## 8. 复现方式和文件分工

Python 需要 NumPy；模型加载当前面向本机 Windows x64 的 Vivado 安装包。在仓库 PowerShell 中运行：

```powershell
$python = 'C:\path\to\python.exe'
$vivadoBin = 'D:\AMDDesignTools\2026.1\Vivado\bin'
.\scripts\run_lesson03.ps1 -Python $python -VivadoBin $vivadoBin -Synthesize
```

省略 `-Synthesize` 时仍会创建/打开可重建的 GUI 工程并运行行为仿真。可用 `-BuildDir` 指定仓库外目录；已有 FFT 配置不符时脚本会停止，避免悄悄沿用不同的定点规则。

| 文件 | 作用 |
|---|---|
| [fft_pair_512.sv](../rtl/fft_pair_512.sv) | 双 FFT 的独立握手、配置、复位延展、输出配对与协议检查 |
| [channelized_x_engine.sv](../rtl/channelized_x_engine.sv) | 复用第二课乘积，按频道读写 512 组累加状态 |
| [two_channel_fft_fx.sv](../rtl/two_channel_fft_fx.sv) | 顶层窗口控制、量化和结果元数据 |
| [fft512_reference.py](../scripts/fft512_reference.py) | 本地定点模型接口与独立 NumPy 核对 |
| [generate_lesson03_vectors.py](../scripts/generate_lesson03_vectors.py) | 生成时域样本、FFT/相关期望值及可手算的约束 |
| [tb_two_channel_fft_fx.sv](../sim/tb_two_channel_fft_fx.sv) | 完整链路自检查与复位/反压/故障场景 |
| [run_lesson03.ps1](../scripts/run_lesson03.ps1) / [run_lesson03.tcl](../tcl/run_lesson03.tcl) | 重建 IP、工程、仿真及可选独立综合 |
| [lesson03_ooc.xdc](../constraints/lesson03_ooc.xdc) | 综合前读取的 10 ns 算术模块时钟目标 |

默认输出目录为 `D:/work/build/KU5P_FX_Accelerator/lesson03_fx`，生成产物和 RFSoC 原工程均不纳入源码仓库。新增 RTL 和主机程序为自行编写，厂家 FFT 从本机安装目录重新生成。

## 9. 在 Vivado 中操作

打开空的 Vivado 2026.1，在 Tcl Console 输入：

```tcl
open_project {D:/work/build/KU5P_FX_Accelerator/lesson03_fx/vivado_project/lesson03_fx.xpr}
```

1. **Sources**：设计顶层应为 `two_channel_fft_fx`，Simulation Sources 顶层应为 `tb_two_channel_fft_fx`。FFT IP 是本机生成的 `lesson03_fft512`，可打开配置界面查看参数。
2. **Run Simulation → Run Behavioral Simulation**：运行到 `$finish` 后查看 PASS；开始包含故意取消的帧，最后包含预期的频道标签故障，便于学习复位与错误状态。
3. 在 `dut` 层看 `input_index`、`fft_bin`、FFT 原始 I/Q、`quant_*`、`frames_in_window`、输出频道、计数、实部/虚部及 valid/ready。输入/FFT/相关分量选有符号十进制，功率和计数选无符号。
4. 找到 `window_id=3、bin=128、count=3` 的输出，核对上一节的三帧谱线结果。观察其他频道是否为零，再看随机数据的频道状态是否各自积累。
5. **Run Synthesis → Open Synthesized Design** 查看 `fft_pair` 的两份 FFT 和 `x_engine` 的相关/存储资源。也可在另一个空窗口打开构建目录中的 `two_channel_fft_fx_synth.dcp`。

主要证据文件是 `simulation_pass.txt`、`vectors.json`、`verification.json`、`reports/` 和工程仿真目录的 `tb_two_channel_fft_fx_behav.wdb`。GUI 手动实验会更新工程自己的仿真/综合结果；`verification.json` 对应脚本成功运行时的源码哈希。

可选的 [plot_lesson03_results.py](../scripts/plot_lesson03_results.py) 使用 Matplotlib 绘制通过 RTL 核对的整数参考谱；它会先检查验证记录及源码哈希。运行方式为 `python scripts/plot_lesson03_results.py --build-dir D:/work/build/KU5P_FX_Accelerator/lesson03_fx`，输出 `lesson03_spectra.png`。

本机已在构建目录的 `plot_env` 虚拟环境安装绘图依赖，绘图解释器为 `D:/work/build/KU5P_FX_Accelerator/lesson03_fx/plot_env/Scripts/python.exe`。基础仿真参考程序使用 Python/NumPy，绘图程序另需 Matplotlib。

## 10. 当前实现的吞吐边界与下一阶段

当前控制器一次只让一对 FFT 帧在途，完成该帧的 X 处理后再收下一帧。输入还有一个保守的双路发送寄存器，X 对频道逐项处理；输出阻塞时会向前传播反压。这是可暂停的分帧回放路径，不能接到无法停采的 ADC 后就声称持续接收 100/320 MS/s。

100 MHz 是独立综合的目标时钟。FFT 标称流水线架构不代表整个包装器具有每拍一对输入的持续吞吐；综合时序也不能替代布局布线、真实时钟源、I/O/CDC 约束及上板测试。

下一阶段沿 FX 继续：PFB 与科学频道定义、输入精度/缩放、可追踪的帧标签和有效贡献/计划积分窗口。真实数据接入和持续吞吐改造要结合缓存、网络资源、跨板同步及科学带宽一起验收。

后续进展：上述 PFB、计划帧窗口、三种有效贡献及帧标签已在[第四课](lesson04-pfb-weights.md)完成仿真与独立综合。本文件继续记录第三课的矩形 FFT 实现与原始验收边界。
