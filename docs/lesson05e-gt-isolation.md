# 独立 GT 时钟与复位隔离实验

2026-10-29。目的是检查：沿用同一组参考输入和 GT 通道，在没有 XDMA/PCIe 控制器、使用独立 SYS_CLK 管理复位时，QPLL1 能否锁定。本实验不实现 PCIe 协议，不会枚举为 XDMA 端点，也不能用来测试 DMA。

## 配置与边界

| 项目 | 配置 |
|---|---|
| FPGA/通道 | xcku5p-ffvb676-1-i；GTYE4_CHANNEL_X0Y4–Y7；COMMON_X0Y1 |
| 参考输入 | PCIe 原 AB7/AB6，名义 100 MHz；IBUFDS_GTE4；不改板上接线 |
| 固定速率 | TX/RX 8 Gb/s，QPLL1，8B10B，用户 32 位/内部 40 位；不做 PCIe 动态变速 |
| 管理时钟 | AB21 的板载 SYS_CLK，名义 100 MHz，经普通时钟缓冲进入 Wizard freerun 端口 |
| 初始化 | 独立 MMCM 监测 SYS_CLK，LOCKED 两级同步后等待 16384 个管理时钟周期，再释放 Wizard reset-all；手动复位或失锁重新保持复位 |
| 用户时钟 | Wizard 内部 TX/RX user-clocking helper；复位方式沿用生成示例的 PMARESETDONE 全通道归约 |
| 发送输出 | 四路 TXINHIBIT=1、TXELECIDLE=1，常量在实现网表中逐路核验 |
| 固件身份 | `465805e1`；独立 VIO 输入布局，不使用 e0 PHY 解析布局 |

[PG182 复位控制器说明](https://docs.amd.com/r/en-US/pg182-gtwizard-ultrascale/Reset-Controller-Helper-Block) 要求配置前即提供连续运行的管理时钟。[管理时钟频率说明](https://docs.amd.com/r/en-US/pg182-gtwizard-ultrascale/Free-Running-and-DRP-Clock-Frequency-MHz) 要求其频率与定制参数相符。本设计按板卡资料中的 100 MHz 配置，增加完整 32 位 heartbeat 供主机时间作粗略交叉核对；不是校准仪器或 ppm 级频率计。

GT 内部时钟/复位控制由新生成的 Wizard 负责；未复制或修改生成的 AMD RTL，未应用旧版 power-good 补丁。它与 XDMA 所用 GT 设置并非所有属性逐项相同，尤其不包含 PCIe 动态变速/初始化逻辑。因此独立工程通过或失败都需要结合配置差异解释，不能直接证明原 PCIe 协议或板卡电气条件已合格。

## 仿真覆盖

第一次复位测试在释放边界少算了一个采样周期，测试已纠正为：锁定已同步时在第 16 周期释放（测试参数 HOLD_BITS=4），锁定刚上升时额外经过两级同步。原 RTL 未因测试边界而改动；失败记录保存在仓库外。

完整四通道真实 GT 模型达到 94904 个实例，超过当前 Vivado BASIC 仿真的 50000 个实例上限，未能运行。没有将这项记录为通过，也没有通过修改许可或模型规避限制。

缩小为单通道后仍超限：与 MMCM 合并时 63341 实例，独立 GT 测试为 63337 实例。因此 **原 8 Gb/s/QPLL1 动态仿真没有执行成功**。保留该单通道 testbench 供具备足够许可时使用；它只完成编译、展开并生成仿真快照，不能把 elaboration 当成运行通过。后续独立 CPLL 测试见下节，覆盖范围不同。

当前实际运行的仿真为：复位控制 4 项（无锁定保持、锁定后延时释放、手动复位及失锁恢复），真实 SYS_CLK/MMCM 包装模块 4 项（100 MHz、输入停止、复位恢复、125 MHz）。MMCM 与 GT 逻辑已分成独立模块，单 GT testbench 的资格输入由测试激励提供。仿真模式的其余三路状态补零，不表示三路已模拟成功；硬件顶层固定使用四通道分支。

动态 GT 覆盖缺口不能靠静态检查消除。本实验只在网表确认四路发送禁止、原引脚/GT 位置正确、复位控制仿真与时序检查通过后进行受限实板观测，利用真实硬件记录每路电源就绪、PLL 和复位状态；不扩大到数据发送或 PCIe/DMA 验收。

## 构建与审查

源码入口为 `tcl/build.tcl` 的 `lesson05e_gt_top` profile。新生成 IP 只保存在外部 `vivado_project`，不入仓库。`scripts/run_gt_isolation.ps1` 需要显式 Python、VivadoBin 和仓库外 BuildDir，可运行 `all`、`simulate`、`implement`。

`inputs.json` 与 `source_snapshot/` 冻结设计和测试输入。修改这些字节后，应保存旧尝试并建立新的冻结记录；不要覆盖历史验证。`check_gt_isolation.py accept` 检查实际 native 日志、控制/时钟仿真标记、GT elaboration 日志、时序、完整路由、原板引脚、常量发送控制、PLL 分频属性和产物时间，接受后才生成 `verification.json` 供受限实板观测；其中 `gt_dynamic_simulation_passed=false` 必须保留。

AMD IP 自带的 CDC waivers 可能随生成文件进入工程。报告使用 `report_cdc -no_waiver` 忽略这些豁免，并保存厂商 waiver 列表；不增加自定义豁免。不能以 IP 默认报告隐藏的路径声称整体 CDC clean。

首轮完整实现虽时序通过，但 CDC 检查指出诊断模块为 TX/RX RESETDONE 和 user-clock ACTIVE 增加了与 Wizard 内部并行的同步链，共 20 条 CDC-11。该版本没有接受或上板。修正方式是移除这十个重复观测位，改用 Wizard 的 aggregate TX/RX reset-done，再经诊断两级同步进入管理时钟域，并保留八位逐通道 PMARESETDONE。位13–20、23–24成为保留位，解析器对应原始 per-channel RESETDONE/user-clock ACTIVE 返回 null，不能把保留零解释成硬件状态为零。没有修改厂商 RTL、添加 waiver 或降低严重度。

此前文字把 aggregate reset-done 的源时钟域写错了：TX done 同步到 TXUSRCLK2，RX done 同步到 RXUSRCLK2；并非 Wizard 已替外部诊断同步到管理时钟域。RTL 原本已有诊断两级同步，本次只纠正文档。[PG182 复位状态机说明](https://docs.amd.com/r/en-US/pg182-gtwizard-ultrascale/Reset-State-Machines) 给出了两种 done 的时钟域。

另一项构建修正是把仿真专用单通道 IP 的源/XDC 排除在硬件综合和实现之外，避免其 scoped XDC 在四通道硬件中找不到对应实例。IP-XACT XML 文档没有 synthesis/implementation 标志，不对文档对象强设不存在的属性。板级 XDC 使用显式引脚赋值，避免当前约束解析器不支持循环语句的问题；没有放松引脚或时序约束。

## 实现与实板结果

最终 e1：WNS=+4.005 ns、WHS=+0.007 ns，4265/4265 条可布线网全部布通；完整 native 日志无 Critical Warning/Error；`report_cdc -no_waiver` 的 Critical 数为 0。重开保存的 DCP 后，逐项 GT/端口/常量审计与保存前完全一致。

| 实测项目 | 结果 |
|---|---|
| 复位保持 | manual_reset=1、reset_all=1、MMCM LOCKED=0 |
| 释放后及稍后，各 12 次 | manual_reset=0、reset_all=0、MMCM LOCKED=1、CLKINSTOPPED=0 |
| 逐通道状态 | 四路 raw GTPOWERGOOD=1，四路 TX/RX PMARESETDONE 均为 0 |
| PLL/复位流程 | QPLL1LOCK=0；Wizard aggregate TX/RX reset-done 均为 0 |
| SYS_CLK 粗测 | 释放后主机时间条件范围约 99.853–100.228 MHz；稍后约 99.783–100.340 MHz，符合名义 100 MHz 的粗略检查 |
| 两次 4096 点 ILA | 心跳均严格每 256 点；参考计数位均未观测到上升沿 |

主机时间粗测使用每次 VIO refresh 前后的单调微秒时间戳，以及完整 32 位计数器的增量；假设采样发生于对应命令区间、观测间隔内不超过一次计数器回绕。它用于区分明显的时钟配置错误，不提供 ppm 或抖动精度。MMCM LOCKED 也不能单独证明绝对频率。

参考计数链为 IBUFDS_GTE4/ODIV2 → BUFG_GT ÷8 → counter[4] ÷32 → 两级同步 → ILA bit0。重开 DCP 已核对这些连接、80 ns 派生约束与 DIV=111。工具在 CE/CLR 上自动插入 BUFG_GT_SYNC，但 CEMASK/CLRMASK 均为常高；诊断计数不受动态门控/清零控制。两次短窗口无边沿是该数字观测链的结果，不能替代插槽差分时钟的电气测量，不能据此直接断定主板或 FPGA 损坏。

实验后已恢复**哈希完全相同的 e0**，当前 SRAM 身份 `465805e0`，局部复位 0，JTAG 6 MHz。e0 PHY 当前字仍为 `00002c0f0000`；CPLL/QPLL1 未锁定，训练快照只有 Detect.Quiet、序号 1 不更新；Windows `10EE:9034` 数量为 0。两次 e0 回退后采集通过同域校验，参考边沿范围分别 22–120、22–75 点，仍不给出稳定频率。不能把 e1 与 e0 不同计数现象直接归结成插槽频率改变。

本阶段已完成独立 GT 对照，**没有恢复 PCIe 建链，也没有通过 BAR/DMA 测试**。独立工程同样未锁定，支持继续检查参考输入及 GT 初始化条件，不能将根因归结为 Windows 驱动或只剩某一个配置错误。未重启主机、移卡、写 Flash、安装驱动或改变 BIOS。

e1 阶段的 8 项控制/时钟仿真、33 项 Python 测试通过；原 QPLL1 GT 动态模型受许可限制仍未运行。完整哈希、原始采集摘要、回退证明及验证边界见[本阶段验证记录](validation/lesson05e-gt-isolation-2026-10-29.json)。

## 后续：减少实例后的动态仿真

2026-10-29 继续尝试减少实例。单 GT/QPLL1 的 `xelab --debug off` 仍产生 63337 个实例，xsim 因 BASIC 上限 50000 拒绝启动；不能靠去掉调试信息解决。安装的 GT 模型已用 FAST 模式与 reset speedup，未修改厂商模型或许可检查。

另建**一个 GTY 通道、5 Gb/s、CPLL、100 MHz 参考输入**的独立测试，生成参数确认 CHANNELS=1、COMMONS=0。它成功运行到 435810 ns，输出 `PASS gt_cpll_reduced_checks=4`，native 日志也检查此标记后才输出 `CPLL_REDUCED_SIMULATION_COMPLETE`。实际通过：

1. 上电时管理复位请求保持，TX 初始化尚未完成。
2. 释放后 CPLL 锁定、GT power-good、TX PMA ready、TX helper done 成立。
3. 再次请求复位时管理控制正确保持。
4. 请求释放后实际观察到 CPLL 解锁、TX done 拉低，随后两者恢复。

第一次测试错误地要求 reset-all 请求保持高时 CPLL 必须立即解锁。按 PG182 和本机生成的 helper，reset-all 状态机在同步请求的**下降沿**启动；已改为在释放后等待并检查真实解锁及恢复，而非删去恢复检查。失败尝试留在仓库外。

该模型沿用生成 IP 的 `C_SIM_CPLL_CAL_BYPASS=1`，不验证模拟 CPLL 校准精度。TX 发送保持禁止，没有 RX 数据源，不验证 RX 数据恢复、BER、PCIe 训练或 DMA。它没有 QPLL common，**不能替代原 8 Gb/s/QPLL1 工程的动态仿真**，原缺口仍为未通过。硬件 e1 和 e0 均未因此改成 5 Gb/s/CPLL。

复现时在全新仓库外目录运行（不会生成位流或自动上板）：

```powershell
New-Item -ItemType Directory -Path D:/work/build/KU5P_FX_Accelerator/cpll_fresh
Push-Location D:/work/build/KU5P_FX_Accelerator/cpll_fresh
& D:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat -mode batch `
  -source D:/work/KU5P_FX_Accelerator/tcl/simulate_gt_cpll_reduced.tcl `
  -log D:/work/build/KU5P_FX_Accelerator/cpll_fresh/native_sim.log `
  -tclargs D:/work/build/KU5P_FX_Accelerator/cpll_fresh
Pop-Location
```

工作目录设为 `cpll_fresh`，避免在源码目录产生工具临时文件。需同时检查实际 runtime PASS、结束时间和完成标记；xsim 在许可失败时也可能返回退出码 0。结果及源文件哈希见[缩小仿真验证记录](validation/lesson05e-cpll-reduced-2026-10-29.json)。

## 原理图复核与下一步

再次目视核对本机厂家原理图 PDF 的第 6、12、16 页（图纸页号 06、13、17）：PCIe J7 A13/A14 经 C187/C188 到 `PCIE_CLK_P/N`，再到 AB7/AB6，确实是插槽参考输入；Si5338 CLK2 的 `B225_CLK0_P/N` 另经 C31/C32 到 V7/V6。两者不是同一个源，不能把 Si5338 未初始化直接写成 PCIe 参考输入失败的根因。

时钟页还表明 X2 是 **25 MHz**，经时钟选择器送入 Si5338。厂家 XDC 对 QSFP 参考的“161.1328125 MHz / from X2”注释不能证明当前硬件上电即输出该频率；PCIe 注释中的 bank225 也与实际 AB7/AB6 的 bank224 不符。实际连接优先以原理图网络和器件封装核对，最终频率仍需配置读回与测量。

e1 阶段没有访问或改写 Si5338。后续已完成引脚、电压、开漏审计及实板只读采集，见[第五课 F](lesson05f-si5338-readonly.md)。本地参考仍需配置计划与独立测量，不能直接替换进 PCIe 端点。
