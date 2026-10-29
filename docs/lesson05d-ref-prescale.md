# 无需主机重启的参考时钟交叉核验

2026-10-29。用户选择继续不重启的诊断；Windows 完整重启仍为可选启动时序对照，不是本轮前置条件。FPGA 保持在显卡下方原来的电气 ×4 长槽。

## 本轮要排除的测量假设

dd 的 ILA 同域心跳校验通过，但参考缓冲后的八位计数器边沿间隔不稳定。原计数器在标称 100 MHz 约束下的最差路径 slack 为 +9.129 ns、数据路径延迟 0.762 ns；没有证据证明它在 100 MHz 下违反时序。不过实际输入频率、波形仍未独立测得，因此加入另一种总分频相同的测量实现进行对照。

de / `465805de` 从原 dd routed DCP 派生：

- 新增并行 BUFG_GT，输入来自同一个 IBUFDS_GTE4/ODIV2，DIV=111，即先硬件 ÷8。
- 它与原缓冲共用相同 CE、CLR、CEMASK、CLRMASK，不增加第二组控制同步器。
- 原诊断 counter 的八个触发器改用这个慢时钟，观测 bit4，产生 ÷32。
- 总分频仍为 `8 × 32 = 256`，原 dd 为直接观测 bit7 的 ÷256；两种情况下标称 100 MHz 均应每 256 个标称 SYS_CLK 采样点重复。
- ILA bit1 仍为同域 heartbeat[7]，状态 bit7 仍不代表 AXI 活动。raw GTPOWERGOOD 四位布局保持 dd 不变。

[AMD UG974 的 BUFG_GT 说明](https://docs.amd.com/r/en-US/ug974-vivado-ultrascale-libraries/BUFG_GT) 定义硬件分频值为 DIV+1。[PG213 时钟说明](https://docs.amd.com/r/en-US/pg213-pcie4-ultrascale-plus/Clocking) 要求来自同一 IBUFDS_GTE4 的 BUFG_GT 共用 CE/CLR；本实验保持这些连接一致。相邻 quad 共享参考时钟本身不是已证实的错误，未据此修改 GT 参考入口。

新测量只观察缓冲后的计数，不测差分信号的电压、抖动或绝对 ppm 精度，也不保证能排除所有时钟波形问题。

## 仿真与实现审查

使用 Vivado 自带 UNISIM BUFG_GT 模型完成四项新仿真：100 MHz 输入平均周期 256 点，125 MHz 为 204.833333 点，500 MHz 为 51.166667 点，以及停振后输出保持。理想期望分别为 256、204.8、51.2，采样量化误差通过检查。仿真不等同于实板能够接收这些频率。

构建从已验证 dd DCP 开始，关闭并重开新 DCP 后核对 ÷8 输入、所有 counter 时钟、bit4 采样、80 ns 派生时钟，以及 6267 项 GT/PCIe 输入及核心参考时钟驱动完全一致。只有诊断计数时钟、采样位与版本身份有逻辑变化。

实施中保留了未上板的失败/未接受产物：

| 尝试 | 结果与处理 |
|---|---|
| 全部重新布线 | 核心原复位 recovery 路径 WNS −0.120 ns、96 个端点失败，保留 `attempt_full_reroute`，未上板。 |
| 固定新增 BUFG 后直接增量布线 | 时序恢复，但 Route35-586 指出诊断时钟借用未实例化的 BUFG 作 route-through，保留 `attempt_clock_route_through`，未上板。 |
| 放置状态筛选 | 当前版本的筛选未匹配到单元，脚本停止；改为检查非空 LOC 和单元数量，保留失败日志，未上板。 |
| Tcl 连接核验 | 常量网跨层集合超过默认 500 项显示上限；设为 0 以完整核验集合，没有豁免 DRC/CDC 或改动时序约束。 |

最终实现方式让八个诊断 counter 触发器及新 BUFG 在参考源所在的 Y0 时钟行内自动布局，其余已有原语固定位置，随后增量布线。新增 primitive 使用正常布局流程，而非让路由器借用未实例化缓冲器；此方向符合 [AMD ECO 实现流程](https://docs.amd.com/r/en-US/ug904-vivado-implementation/Run-Section)。

接受脚本 `scripts/check_pcie_ref_prescale_build.py` 拒绝不完整日志、任何行首 ERROR/Critical Warning、时序不通过、未完全布通、引脚不符、过期位流或源字节变化。原有两项已记录的 CDC Critical 仍须如实报告，不降低严重度。

## 诊断分支与复现

| 身份 | 构建目录末段 | 变化 |
|---|---|---|
| `465805de` | `lesson05d_pcie_ref_prescale` | 上述 ÷8 × ÷32 诊断链，共用原门控 |
| `465805df` | `lesson05d_pcie_ref_ungated` | 只把新增诊断 BUFG 的 CEMASK 设为 1；核心原门控不变 |
| `465805e0` | `lesson05d_pcie_monitor_pll` | 在 df 基础上增加 SYS_CLK MMCM 资格监测；不以 MMCM 输出驱动功能逻辑 |

所有构建目录都在 `D:/work/build/KU5P_FX_Accelerator/`，native 产物、失败尝试和原始采集留在仓库外。各目录的 `eco_inputs.json` 冻结输入哈希，`verification.json` 记录接受结果，`source_snapshot` 保存对应源字节；父 DCP 哈希必须匹配。已有 DCP 仍需本地保留，单靠脚本不能从不存在的父产物直接恢复实验。

两个新 UNISIM 仿真入口为 `scripts/run_pcie_ref_prescale_test.ps1` 与 `scripts/run_pcie_monitor_pll_test.ps1`，均要求显式 VivadoBin 与仓库外 BuildDir。`tcl/build.tcl` 的诊断 profile 分别为 `lesson05d_ref_prescale`、`lesson05d_ref_ungated`、`lesson05d_monitor_pll`，第四个参数为已接受父 routed DCP。

完成构建后还必须运行 `scripts/check_pcie_ref_prescale_build.py --build-dir ... --parent-dir ... --profile prescale|ungated|monitor-pll`，通过后才允许 JTAG 下载。原 de/df 接受脚本也按其哈希保存在构建目录的 `audit_source_snapshot`，后续工具扩展不能改变历史审核的含义。

e0 使用原 SYS_CLK 输入缓冲后的信号驱动 MMCME4_ADV，反馈经独立 BUFGCE。局部 VIO 复位同时复位新增监测 MMCM；原 MARK_DEBUG 复位网的 DONT_TOUCH 属性只在增加一个诊断负载时临时清除并恢复，原驱动不变。独立同步后的 PHY bit27 表示 MMCM LOCKED，bit31 表示 CLKINSTOPPED，不能再套用 d8/d9 的 REFCLKLOST 布局。解析器依据固件身份选择布局。

MMCM 仿真覆盖稳定 100 MHz、输入停止、复位恢复与稳定 125 MHz。[AMD MMCM 说明](https://docs.amd.com/r/en-US/ug974-vivado-ultrascale-libraries/MMCME4_BASE) 中的 LOCKED 表示锁定条件满足；本实验刻意验证 125 MHz 同样能锁定，因此不能把 LOCKED=1 写成绝对 100 MHz 或 ppm 精度证明。失锁或输入条件改变后的恢复需要复位；若 SYS_CLK 本身停转，使用它采样的 VIO 也可能冻结，CLKINSTOPPED 的阴性读数不能排除所有停振。

## 实板结果

de 与 df 均已通过实现审查并以 6 MHz JTAG 下载，局部复位保持后释放，读回均为 0。两版 WNS=+1.256 ns、WHS=+0.010 ns，43108/43108 条可布线网全部布通，完整实现日志没有 ERROR 或 Critical Warning。6267 项功能输入驱动完全相同。

两版均观察到四路 raw GTPOWERGOOD 高，但 CPLL/QPLL1 未锁定，TX/RX resetdone 为 0。连续参考边沿仍不满足稳定周期筛选；同域心跳校验均严格每 256 点重复。df 的两次参考周期范围分别为 49–186、46–123 个采样点。这些是数字观测链的边沿间隔，不作为主机 PCIe 差分输入的真实频率值。只旁路诊断门控未消除异常，不能据此单独归咎门控。

e0 也已通过审查并下载：WNS=+1.256 ns、WHS=+0.010 ns，43112/43112 条可布线网全部布通，完整实现日志无 ERROR/Critical Warning，6267 项功能输入驱动完全相同。重开 DCP 逐项核对 MMCM 源、复位、反馈、两位观察连接及两级 ASYNC_REG 属性，原复位网 DONT_TOUCH=1 已恢复。

| e0 观测 | 结果 |
|---|---|
| 局部复位保持时 | MMCM LOCKED=0 |
| 释放后与稍后复查，各 12 次 | MMCM LOCKED=1，CLKINSTOPPED=0，PHY 当前字均 `00002c0f0000` |
| GT 初始化 | 四路 raw GTPOWERGOOD=1；CPLL/QPLL1=0；TX/RX resetdone=0；rrst_n=1、prst_n=0、rst_idle=0 |
| 两次 4096 点采集 | 同域心跳均严格每 256 点；参考边沿间隔分别 48–145、70–584 点，未通过稳定周期筛选 |
| 训练/主机 | 已存快照只有 Detect.Quiet，序号不更新；Windows `10EE:9034` 端点数 0；BAR/DMA 未测 |

新 MMCM 能随复位解除而锁定，增加了独立于心跳序列的 SYS_CLK 资格检查；该结果仍不确认 SYS_CLK 的绝对频率，也不等于 PCIe 参考输入已经合格。当前主要未解项仍是 PCIe 参考输入、板级连接和 GT 初始化条件之间的关系。没有证据把问题归因于 Windows XDMA 协议、插槽通道数，或认定板卡已经损坏。

原有 2 项 CDC Critical 保持可见：手动复位组合到同步链的 CDC-10，以及旧 AXI 观测首级寄存器的 CDC-1。后者 Q 负载为 0，无反馈，后续从 HDL 重建诊断工程时应删除；此次没有豁免或降级。没有新增 Critical 路径。

本轮可公开证据见 [2026-10-29 无重启时钟交叉核验](validation/lesson05d-ref-prescale-2026-10-29.json)。当前板上保留 e0，局部复位为 0。主机未重启，未修改 BIOS/Windows 安全设置、安装驱动或写入 Flash。

## 下一步边界

下一项可在现有硬件上实施的软件实验是独立 GT Wizard 最小参考时钟/PLL 测试：沿用已经核对的引脚、GT quad 与 100 MHz 配置，使用板载 SYS_CLK 作为复位管理时钟，观察原始 GTPOWERGOOD、PLL lock 和复位状态，尽量减少 XDMA 复位控制的影响。应先审核配置、仿真和时序，再通过 SRAM 替换测试，仍不要求主机重启。

此实验**尚未实施**。若独立 GT 测试能锁定，再对比 XDMA 的初始化条件；若同样不锁定，保留完整结果，后续需要主机/插槽对照或具备合适探头的时钟实测来区分电气条件与配置问题。数字计数异常不能替代模拟波形测量。
