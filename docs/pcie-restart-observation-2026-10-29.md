# e0 参与主机重新启动后的实测

2026-10-29，用户完成 Windows“重新启动”。只读系统启动时间由 2026-10-28 18:38:06.5 变为 2026-10-29 18:45:52.5（UTC+8）。首次 JTAG 观察前没有下载位流、操作本地复位或写 Si5338。

**本次确实观察到 CPLL 和四路 GT 完成初始化，并进入实时更新的 Polling.Compliance；但没有进入 L0、没有枚举。随后一次端点局部复位又使初始化无法恢复。板卡仍未打通，当前状态不能写成“PLL 问题已解决”。**

## 三个阶段分别保留

| 观测 | 重启前 e0/reset0 | 重启后首次只读 | 随后局部复位释放后及最终复查 |
|---|---|---|---|
| 位流身份 / DONE | 465805e0 / 1 | 465805e0 / 1 | 465805e0 / 1 |
| 本地复位 | 0 | 原样保留 0 | 1→0，分别读回；最终 0 |
| PHY 当前字 | 00002c0f0000 | f0ff7c1fffff | 00f02c0f0000 |
| CPLL lock mask | 0000 | 0001 | 0000 |
| TX/RX resetdone mask | 0000 / 0000 | 1111 / 1111 | 0000 / 0000 |
| TX/RX PMA resetdone mask | 0000 / 0000 | 1111 / 1111 | 0000 / 0000 |
| PHY rst_idle / rrst_n / prst_n | 0 / 1 / 0 | 1 / 1 / 1 | 0 / 1 / 0 |
| 四路 raw GTPOWERGOOD | 全高 | 全高 | 全高 |
| SYS_CLK 监测 MMCM | 已锁定 | 已锁定 | 已锁定 |
| 训练快照 | Detect.Quiet，序号 1 不更新 | Polling.Compliance，12 个序号均不同 | Detect.Quiet，序号 111 不更新 |
| 累计训练跳转 | 0 | 3 | 4 |
| Windows 10EE:9034 | 0 个 | 0 个 | 0 个 |

第一次只读保留记录确认 DONE=1、一个 VIO、身份 e0、实际复位输出 0、JTAG 6 MHz；不是靠重新下载制造的“启动成功”。随后先完成状态 6 次、PHY 12 次、训练 12 次和 Windows 清单，才执行下一项局部复位实验。三个阶段使用不同标签，原始失败和正向读数均未覆盖。

首次训练历史包含 Detect.Quiet、Detect.Active、Polling.Active、Polling.Compliance；未看到 L0。12 次快照序号变化，说明此次 Polling.Compliance 观察有源域更新证据。AMD [PG213 配置状态接口](https://docs.amd.com/r/en-US/pg213-pcie4-ultrascale-plus/Configuration-Status-Interface)把 03 定义为 Polling.Compliance。未建链时 speed_raw=0、width_raw=2 不构成已协商 Gen1×4 的证明。

CPLL mask=0001 不能说成“四个 CPLL 都锁定”。本次 QPLL0/1 均低，但不能只凭此把已进入低速训练的状态判为初始化全失败；需要结合当前速率和实际选用的 PLL。AMD [PG213 Clocking](https://docs.amd.com/r/en-US/pg213-pcie4-ultrascale-plus/Clocking)说明使用 QPLL 的应用中 TXOUTCLK 仍依赖 CPLL。本次没有证明 Gen3 的 QPLL/速率切换已通过。

## 局部复位恢复实验

保存首次读数和 ILA 后，执行一次 VIO 端点本地复位 1→0，保持至少 1 秒，并分别读回。没有复位主机根端口、重新下载 FPGA 或修改任何 IP 参数。释放后等待 2 秒再读取；随后复查，CPLL 与 TX/RX resetdone 仍低。

最终训练序号固定 111、累计跳转 4。历史 bitmap 仍保留此前 Polling.Compliance，因为该监测器历史只在 FPGA 配置时初始化；不能由历史位判断复位后再次到达 Polling。最终 Detect.Quiet 是冻结的最后快照，不应描述为实时状态机一直停留在该状态。

## 参考观察链的边界

重启后首次及复位后最终各保存一次 4096 点时钟 ILA，两次同域心跳周期都严格为 256 点，采集间距自检通过。

- 首次参考计数观察到 10 个上升沿，9 个完整周期为 216–545 个管理时钟样本；不满足稳定比率门槛，不能换算为可信物理频率。
- 最终采集参考计数未见上升沿，VIO 的参考活动位主要为低，PHY 采集中有一个样本短暂为高。这不是稳定参考或可靠恢复的证据。

上述是片内数字观察，尚不能单独区分插槽门控、输入电气质量、GT/时钟缓冲状态或观测支路异常；不能直接宣布“主板关掉了 100 MHz”。MMCM 使用独立 SYS_CLK，它锁定也不验证插槽参考的绝对频率或抖动。

## 板级连接复核

使用本机厂家原理图的 J7 PCIe 页复核：A13/A14 经 C187/C188 连接 PCIE_CLK_P/N，A11 为 PERSTn；连接器接收、发送对与现有约束的命名方向一致。该页 B12 标为 RESERVED1 且未画连接，没有可直接由 FPGA 控制的 CLKREQ# 网络证据。仅凭图纸没有该网络，不能断言本机实际启用了时钟门控，也不能直接提出由 FPGA 驱动某个未知引脚。

现有显式 ×4、GTY quad225、lane reversal 配置不变。AMD [PG213 Lane Reversal](https://docs.amd.com/r/en-US/pg213-pcie4-ultrascale-plus/Lane-Reversal)列有受支持的反序宽度组合；后续若降为 ×1，必须重新核对连接器 lane0 到硬核物理 lane 的合法映射，不能直接把参数改为 ×1。原理图只在本机复核，没有复制进仓库。

## 下一步的实验门槛

1. 保留这次启动正向读数，不再重复无新增观测的复位或重启。e2/e3 六轮阴性发生在此前启动会话，本次没有重新测试它们，不能追改为通过。
2. 下一个 FPGA 诊断应在独立 SYS_CLK 下记录启动时间线：物理 PERSTn、本地复位、参考资格/Gray 计数窗口、CPLL/QPLL lock、TX/RX 初始化、训练状态及逐路 RX electrical-idle/接收状态。须使用可保留的时间戳/事件记录，避免只得到终态或过短 ILA。
3. 优先核对生成 XDMA 的正常时钟/复位契约和实际收发输入；记录当前使用的 PLL/速率及 TS1/TS2 可见性，再区分“初始化没有恢复”和“初始化成功但收不到有效训练”。不以拉高 done、改写内部训练状态或忽略 Critical 的方式造出通过。
4. 若启动时间线和专用参考观察仍无法区分原因，补充另一主机、厂商已验证工程或合适仪器的正对照。BIOS 设置只作为有证据的单变量对照候选，当前未改。Si5338 仍按完整频率表、电气条件和恢复方案的既有门槛准备，当前没有写入。

## 证据和最终状态

[公开验证摘要](validation/pcie-restart-2026-10-29.json)由仓库外脚本校验身份、原 bit/LTX/DCP 哈希、冻结源、37 个输入文件、阶段序号和真实复位读回后生成。原 `hardware_verification.json` 保留为重启前证明，没有用新读数覆盖；新摘要独立记录本次三阶段。该验证没有重新综合或运行仿真。

原始数据、两组 ILA、解码 JSON、Windows 清单和 `summarize_restart_observation.py` 均在 `D:/work/build/KU5P_FX_Accelerator/lesson05g_cpll_pcie_ref/restore_e0`。最终仍为原 e0、DONE=1、本地复位=0，Hardware Manager 已关闭；本次没有重新 program、写 Flash/Si5338、安装驱动或改 BIOS。真实链路、枚举、BAR/DMA 均未通过。
