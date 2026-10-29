# 第四课：PFB、计划帧窗口与有效贡献 W

日期：2026-10-28。主线继续 FX，两路实现用于学习与回放，空间 FFTT 仍为长期方向。

## 1. 本课解决的问题

第三课以每 512 个时域样本做一次矩形窗 FFT。本课加入 4 抽头/相位的 PFB FIR 前端，仍用原来的双 FFT 和逐频道 X；同时让窗口覆盖固定的计划帧号，分别记录自相关与互相关的有效贡献。输入允许暂停，因此当前仍是单时钟、两路已对齐数据的回放模块。

```mermaid
flowchart LR
    H[帧号、来源、配置、两路有效标记] --> C[检查并锁存帧头]
    I[512 对时域 I/Q] --> P[4 抽头/相位 PFB FIR]
    C --> P
    P --> F[复用双 512 点 FFT]
    F --> X[逐频道共轭乘积与积分]
    C --> W[固定 M 帧窗口与 W_A/W_B/W_AB]
    W --> O[512 个结果与相同窗口元数据]
    X --> O
```

PFB FIR 与 FFT 一起构成频道化器，参见 [CASPER 频谱仪教程](https://casper-toolflow.readthedocs.io/projects/tutorials/en/latest/tutorials/snap/tut_spec.html)。本课自行编写 RTL 和系数生成器，使用 Hann 窗乘 sinc；[MeerKAT 相关器的信号处理说明](https://katgpucbf.readthedocs.io/en/latest/signal_path.html)也使用窗函数乘 sinc，但其归一化与实现参数不同，本课以下述定义为准。

## 2. 4 抽头究竟存了什么

FFT 长度 N=512，PFB 每次前进 512 个原始采样时刻，使用当前与前三个数据块，共 2048 个时域样本。相邻频谱相隔 512 点，使用的数据有重叠；输出仍是 512 个复数频道。

设 m 为本次数据块/频谱帧号，n=0..511。原型滤波器为：

`h[r] = A · sinc((r−1023.5)/512) · Hann2048[r]，r=0..2047`

这里 sinc(x)=sin(πx)/(πx)，Hann 是首尾对称窗，A 使 `Σh=512`。系数转换为有符号 18 位 Q17，最近偶数舍入；ROM 地址 `{age,n}` 保存 `round(h[age·512+511−n]·2¹⁷)`。年龄 age=0 是当前块，age=3 是最旧块。

每个分量先计算：

`v_m[n] = round_even(Σ(age=0..3) c[age,n]·x[(m−age)·512+n] / 2¹⁸)`

再送入第三课的正向自然顺序 FFT，最后除以 1024、最近偶数舍入到 16 位。因此相对于原型 h 的浮点滤波/DFT，额外电压因子约为 **1/2048**；稳态、精确落在频道中心的单音，其电压增益约为 `512/2048=1/4`。这与第三课的矩形 FFT 标度不同，功率和互相关应按电压增益的平方处理。

整数系数总和恰为 512×2¹⁷。每相位系数绝对值之和最大为 148660，对任意合法 16 位输入，FIR 分量舍入前绝对值不超过 18582.5；36 位累加器足够，另保留显式饱和与历史 `status_clip` 告警。FFT 的 26 位输出、/1024 转换以及 64 位 X 运算沿用第三课规则。

这不是单位噪声增益归一化。生成记录保存 `Σh²` 等指标；物理单位需要 ADC 增益、滤波器带形及后续校准。相邻频道和相邻频谱的噪声可能相关，W 是有效贡献数量，不等于统计独立样本数。

## 3. 丢样怎样影响结果

每个输入块分别带 `s_frame_good_a/b`。若某路有任何缺样，适配器应将该路整个 512 点块标为无效，仍提供该计划帧和 512 个占位输入。RTL 忽略该路占位数值并存零。

一个天线的频谱只有在所需四个块全部有效时才参与相关。因此：

- 复位后的前三个频谱没有完整历史，不计入 W；第四帧开始可以有效。
- 一路在帧 j 缺样，会使该路频谱 j..j+3 无效，连续四个有效块后恢复。
- A/B 各自独立判断。A 有效时累加 Paa 并增加 W_A；B 有效时累加 Pbb 并增加 W_B；两路都有效时累加 `A·conj(B)` 并增加 W_AB。
- 无效电压在 FFT 前置零，因此复用原 X 的乘积和累加状态。输出权重保留“缺贡献”和“真实零信号”的区别。

当前标记粒度是整块、整路，所有频道共用同一组 W；没有逐样本质量权重或逐频道 RFI 掩码。

## 4. 计划窗口和帧标签

第一次正确接收帧头时锁存 `cfg_window_frames=M`、`cfg_first_frame`、两路 16 位来源 ID、32 位 epoch ID 与配置 ID。本课配置保持到复位；运行期间修改 cfg 引脚不会改变当前会话。M=0 时不启动新会话，合法范围为 1..2³²−1。

每个帧头后必须传输 512 对时域输入，TLAST 只能出现在末样本。下一帧头要等待本帧 X 完成，所有流接口均为 valid/ready；数据及标签在等待 ready 时必须保持。

帧号是 64 位，必须从 cfg_first_frame 连续递增。重复、跳号、错误来源/epoch/config、两路来源相同或 TLAST 错误都会使 `status_protocol_error` 保持并阻止继续输入，需要复位恢复。网络适配器必须先补出显式无效帧，不能直接跳过缺失帧号。这个模块检查标签一致性；真实 RFSoC 共同时间、频率与相位的建立仍属于上游同步工作。

窗口 w 固定覆盖：

`first = cfg_first_frame + w·M；last = first + M−1`

每个完整窗口总会输出 512 行，即使 W 全为零。输出提供两路功率总和、复数互相关总和，以及以下信息：

| 字段 | 含义 |
|---|---|
| `m_axis_bin/tlast` | 自然频道号 0..511，511 为窗口末行 |
| `m_axis_window_id` | 本地 32 位窗口序号，复位为零 |
| `m_axis_first_frame/last_frame` | 本窗口固定的首、末计划频谱帧 |
| `m_axis_window_frames` | 计划 M，包含无效频谱 |
| `m_axis_weight_a/b/ab` | 三种结果各自的有效贡献数 |
| `m_axis_epoch_id/config_id` | 观察会话与处理配置的标识 |
| `m_axis_source_a/b` | 固定共轭顺序中的来源：A·conj(B) |

需要平均值时，Paa 除以 W_A，Pbb 除以 W_B，Vab 除以 W_AB。W=0 的平均值未定义，主机应标为无效。窗口起止与标签不能从 W 推回。

滤波历史跨积分窗口保留；清零的是 X 的窗口积分状态。复位会取消部分输入、部分窗口与未接收结果，并重新建立滤波历史。计数器按其位宽回绕；科学观测应在帧号或窗口号回绕前结束并启动新的 epoch。

时间标签约定为“包含最新输入块 m 的频谱”。若 epoch 采样编号与帧号满足 `sample=m·512+n`，该频谱锚点为块尾 `m·512+511`，对称 FIR 的中心是锚点减去 1023.5 个采样时刻。元数据不包含已验证的 UTC 映射。

100 MS/s 时，帧间隔为 5.12 μs，M=4 的名义窗口为 20.48 μs。100 MS/s 下精确 1 s 不是整数个 512 点 hop，本课固定整数 M 的实现仍不是精确一秒计时器；未来需按采样时间边界定义长积分。

## 5. 可在波形里找到的丢样例子

测试场景 `independent_antenna_gaps` 从一个新 epoch 开始，M=4，A 在相对帧 4 无效，B 在相对帧 6 无效：

| 相对计划帧 | W_A | W_B | W_AB | 原因 |
|---|---:|---:|---:|---|
| 0..3 | 1 | 1 | 1 | 三帧启动历史无效，只有帧 3 可用 |
| 4..7 | 0 | 2 | 0 | A 受缺样影响四帧；B 的帧 4、5 仍可用于自相关 |
| 8..11 | 4 | 2 | 2 | A 已恢复；B 在帧 10 恢复 |

三个窗口都在各自的计划末帧结束。对 W_AB=0 的中间窗口，不能把互相关的零总和解释为一次真实的零可见度测量。

## 6. 验收与资源记录

参考生成器先独立核对完整 2048 点原型/DFT 与多相分解的顺序，再核对系数量化/舍入误差，最后接入本机 AMD FFT 定点 C model 和 Python 整数 X。模型文件与生成 IP 均留在仓库外。

七组主场景已通过：50 对频谱帧、25600 对时域/PFB/FFT 输入、18 个窗口、9216 行最终结果，包括分数频道单音、独立缺样、M=1 启动、满量程随机及对调、DC/Nyquist 极值、冲激历史。PFB、FFT、量化、相关值和全部输出标签均逐项匹配。还验证了 3326 拍输出反压、28 拍 PFB 输出等待、124654 拍输入等待，以及配置锁存、输入/输出复位和八次协议故障。

FIR 整数输出与未量化系数的浮点参考分量差最大约 0.6342，小于预先设定的 1.0 界；后续 RTL 对整数参考均为精确匹配，不使用这个浮点容差替代逐位检查。

系数模型在偏移 1.5..4 个频道的范围内测得最大旁瓣约 −63.38 dB；25.25 频道单音在保留频道 24..27 之外的模型泄漏，相对矩形 FFT 下降约 64.50 dB。这些是明确范围内的模型指标，不代表真实 ADC 的动态范围，也不等于所有频率/噪声条件下的结果。

最终通过记录、源文件哈希、系数与测试数据哈希、综合资源及时序范围统一保存于构建目录的 `verification.json`，项目级结果以该文件和新产生的 PASS 为准。

Vivado 2026.1 对 `xcku5p-ffvb676-1-i` 的整体独立综合已通过，无未解析黑盒：

| 资源 | 整体 | 其中 PFB 前端 |
|---|---:|---:|
| LUT | 7593 | 987 |
| 触发器 | 12067 | 177 |
| DSP48E2 | 56 | 4 |
| RAMB36E2 | 8 | 4 |
| RAMB18E2 | 12 | 0 |
| BRAM36 等效块 | 14 | 4 |
| URAM | 0 | 0 |

PFB 的 4 个 RAMB36 对应三个历史块和系数 ROM；原 X 继续使用 4 个 RAMB36，两份 FFT 合计使用 12 个 RAMB18、44 DSP。本课多了 4 个 DSP，整体 LUT 比第三课增加 1248。

10 ns 时钟目标下综合 WNS=+3.977 ns、WHS=+0.039 ns，缺失时钟和未约束内部端点均为零。423 个输入、655 个输出未设置板级延迟，HD.CLK_SRC 未绑定物理时钟源；当前没有布局布线或上板时序结果。这些数据不能证明持续接收 100/320 MS/s，当前串行 PFB 和一次一帧控制器仍会产生反压。

## 7. 复现和 Vivado 操作

在仓库 PowerShell 运行，Python 需要 NumPy：

```powershell
.\scripts\run_lesson04.ps1 -Python 'C:\path\to\python.exe' `
  -VivadoBin 'D:\AMDDesignTools\2026.1\Vivado\bin' -Synthesize
```

构建默认写到 `D:/work/build/KU5P_FX_Accelerator/lesson04_pfb`。省略 -Synthesize 只做仿真；-PrepareOnly 生成参考文件并冻结输入哈希，供 MCP 驱动同一个 Tcl 流程。完整脚本先记录输入哈希，结束时拒绝期间发生的源码/数据变化和旧 PASS/DCP。

MCP 可运行如下 Tcl 创建工程，随后用 launch_simulation/run_simulation 控制行为仿真，结束后执行 `lesson04_finish 1` 收集结果并综合：

```tcl
set argv [list {D:/work/build/KU5P_FX_Accelerator/lesson04_pfb} xcku5p-ffvb676-1-i prepare]
source -notrace {D:/work/KU5P_FX_Accelerator/tcl/run_lesson04.tcl}
```

采用 MCP 手动驱动时，最后还需运行 `python -B scripts/lesson04_manifest.py finish --build-dir <build_dir> --synthesized` 才会形成哈希验证记录。不要在同一份工程正被其他 Vivado 进程操作时重建。

在 Vivado GUI 中打开 `vivado_project/lesson04_pfb.xpr`：

1. Sources 顶层是 `two_channel_pfb_fx`，Simulation Sources 顶层是 `tb_two_channel_pfb_fx`。
2. Run Behavioral Simulation，运行到 `$finish`，检查 PASS。开头有主动取消/协议故障测试；它们是预期场景。
3. 看 `dut/pfb` 的 phase、tap、coefficient、accumulator_ai，理解“一份乘法器分四拍处理四个历史块”。看 history_valid_a/b 与 contribution_a/b，观察启动与丢样恢复。
4. 找到 epoch_id=701、config_id=101 的输出，按上一节核对三个窗口的权重；观察 m_axis_tvalid 为 1 且 ready 为 0 时数据和标签共同保持。
5. Open Synthesized Design，查看 pfb 下的系数 ROM、三个块延迟 RAM 和 DSP，再与 fft_pair、x_engine 对比。综合时钟目标仍为 10 ns，板级时钟源、I/O 延迟、布局布线和持续吞吐另行验收。

可选 `plot_lesson04_results.py --build-dir <build_dir>` 使用 Matplotlib；它会先核对验证记录与哈希，绘制滤波响应、RTL 匹配的整数谱和权重示例。RFSoC 原始工程没有复制或上传；本课仅使用自行编写的程序和合成输入。

| 源文件 | 作用 |
|---|---|
| [pfb_fir_pair_512.sv](../rtl/pfb_fir_pair_512.sv) | 串行四抽头 MAC、历史 RAM、系数 ROM、历史有效性 |
| [two_channel_pfb_fx.sv](../rtl/two_channel_pfb_fx.sv) | 帧标签检查、原 FFT/X 复用、计划窗口与三种 W |
| [pfb512_reference.py](../scripts/pfb512_reference.py) | 系数、完整原型对照和整数滤波模型 |
| [generate_lesson04_vectors.py](../scripts/generate_lesson04_vectors.py) | 确定性输入、三级参考结果与权重场景 |
| [tb_two_channel_pfb_fx.sv](../sim/tb_two_channel_pfb_fx.sv) | 逐位/标签检查、协议故障、反压与复位验收 |
| [run_lesson04.ps1](../scripts/run_lesson04.ps1) / [run_lesson04.tcl](../tcl/run_lesson04.tcl) | 可复现工程、仿真与综合入口 |
| [lesson04_manifest.py](../scripts/lesson04_manifest.py) | 冻结输入与核对结果/检查点的哈希和新鲜度 |
| [plot_lesson04_results.py](../scripts/plot_lesson04_results.py) | 验证图，输出 lesson04_pfb_weights.png |
