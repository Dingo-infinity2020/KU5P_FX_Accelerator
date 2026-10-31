# 第二长槽 e4 保留配置重启复核（2026-10-31）

**结论：四路 GT TX/RX/PMA done 已观察到，AXI 与训练快照持续更新至 Polling.Compliance；仍无 L0、无 Windows 10EE 枚举。H1 HOLD。** 当前 PLL 锁定指示低，不能宣布稳定 PLL/参考已通过。首事件时间戳存在跨会话一致性问题，完整启动段时间溯源尚未通过；读回原文及重复结果均保留。

工作树 `D:/work/KU5P_FX_Accelerator`，进入分支 `codex/slot2-e4-trial-2026-10-30`，源提交 `bd0b687e2d745fd714b24008af7265433bf4d774`；工作树干净，fetch 后与远端一致。按用户“已经重启”及[上一轮约定](slot2-e4-trial-2026-10-30.md)，创建 `codex/slot2-e4-restart-2026-10-31`，只读保存当前身份、实际控制、VIO、事件和 Windows。未恢复 RTL 开发或发起新硬件配置实验。

## 当前实测与操作

- Windows 启动时间为主机记录的 `2026-10-31T10:02:11.5000000+08:00`；不是校准 UTC。用户此前确认网卡第一长槽、FPGA第二长槽、显卡第三长槽，本轮未插拔或独立检查实物丝印。
- 核对原 e4 接受证明、冻结源与 bit/LTX/DCP 哈希后，以 Vivado 2026.1 / JTAG 6MHz 只读关联 LTX。DONE1、标签 `465805e4`、实际 reset0/arm0/地址1ff，epoch1→2，entries512。没有配置回读，位流身份来自标签、保留过程和原文件哈希，不是重新测得 SRAM 全部位的哈希。
- 三阶段共36个 VIO 样本，16批各32条读取完整512个地址；之后为核对首事件再读0..7八个地址，原始256位事件全部逐字相同。每次提交读地址前刷新真实全部 VIO 输出并守护其他端口；没有 program/reset/arm/ILA trigger。
- 最终实际 reset0、arm0、地址1ff、DONE1、epoch2，Hardware Manager 已关闭，无构建、仿真或采集进行。地址变化不会修改事件存储内容。

| 观察 | 本轮结果 |
|---|---|
| 36个 raw 状态 | 均为 `f00000f00fffff0f` |
| TX/RX/PMA done、RXCDRLOCK | 四路高；不是稳定 PLL 或有效训练序列的独立验收 |
| 当前 CPLL/QPLL0/QPLL1 | 指示低；QPLL RESET/PD仍未知，CPLL RESET/PD采样0 |
| 时钟及训练 | 每阶段 AXI÷8计数、训练序号变化，training_recent=1；实时 Polling.Compliance，不是冻结快照 |
| RX/TX | RXELECIDLE=F，RXVALID/COMMA=0，TXELECIDLE/TXINHIBIT=0；未解码 TS1/TS2 |
| 参考观察 | 有活动，当前名义窗口不合格；不由计数推断物理频率、抖动或时钟根因 |
| L0 / Windows | lifetime bitmap和已读事件无L0，link_up低；前后 PresentOnly VEN_10EE和9034均0 |
| 主机其他设备 | ConnectX-5两个功能Gen3×16、RTX5060Ti Gen4×4、UHD770 OK，前后WHEA0；不能替代FPGA插槽正对照 |
| BAR / DMA | NOT RUN；未安装驱动或执行管理员设备重扫 |

## 首事件时间戳疑点及可用范围

新读口元数据为 epoch2，但**事件字本身没有保存 epoch**。首事件时间戳 `244641140`，早于昨晚 epoch1 首事件 `1314341712`，也早于昨晚最终观察 `10516269668`；事件1则为 `4260663719941`，晚于昨晚。独立计数器在所查 RTL 中不随端点复位或新 epoch 清零。0..7八个地址再次读回完全相同，不能仅按当前元数据称512条全是时间溯源一致的新启动事件。

这是未解释的跨会话时间一致性问题，**没有证明是 FPGA RAM、读口、工具或其他某一环节的具体缺陷**。不能把首条到事件1的巨大差值直接解释成整夜 PERST 保持低，也不能以“索引递增、epoch相同、时间递增”自动判定完整新启动段通过。原始异常不删改，不触发新捕获去覆盖。

事件1..511在数值上顺序递增、均晚于昨晚观察，跨度 `492280064` SYS_CLK周期，即按声明100MHz折算的**名义4.92280064秒**。下面只以事件1同步PERSTn高为相对起点描述这个后段，不包含首条，也不是绝对UTC/电气测量或完整启动验收：

| 首次已读状态 | 索引 | 相对事件1周期 |
|---|---:|---:|
| endpoint_reset_n高 | 2 | 2 |
| 任一CPLLLOCK指示 | 4 | 48982 |
| 四路TXRESETDONE | 12 | 475059 |
| 四路RXRESETDONE | 13 | 574315 |
| Detect.Active | 16 | 1847776 |
| Polling.Active | 17 | 1847889 |
| Polling.Compliance | 21 | 4789257 |
| L0/link_up | 未捕获 | — |

512个已读字里CPLL maskF为450条、mask8为2条、0为60条；TXdoneF为500条、RXdoneF为499条，458条参考名义窗口为真。它们是事件字计数，不是锁定时间占比；包含首事件，不能据此抹去溯源限制。记录满后冻结、遗漏数继续增长；最后实际元数据见[机器摘要](validation/slot2-e4-restart-2026-10-31.json)。

## 验收、保存与停止点

本轮 BOARD：保留身份/真实控制观察、512地址读回和八字重复一致；GT完成指示确实已在当前36个样本观察到。完整事件时间溯源 **HOLD**，稳定PLL/物理参考 **NOT VERIFIED**，LINK/枚举 **FAIL**，BAR/DMA **NOT RUN**。没有新 SIM/SYNTH/ROUTED 结果；原e4历史时序/CDC不冒充本次复测。

原始证据和分析在 `D:/work/build/KU5P_FX_Accelerator/h1_slot2_e4_restart_20261031_attempt1`；公开摘要保存证据哈希。原e4 bit SHA256 `a12257b3eddf1a1160be04e23d1e7374103c05e2c19c5e3c56ebb6abfd9eb300`，旧第二槽、第三槽及e0证据均保持不变。未写Flash/Si5338/BIOS/驱动/内存/网卡配置，未发100G流量、未自动重启。保留e4现场及原e0精确诊断回退文件；它们不是已通过L0的运行固件。

停止点 **H1_HOLD_POSITIVE_CONTROL_AND_RECORDER_PROVENANCE**。不要求再次相同重启，不重复局部复位或下载。后续可单独开展源代码/布线与读口的溯源审查，先建立能解释首条异常的可复现假设；硬件新实验需具体授权。PCIe根因仍需厂家已验证的适配端点、另一合适主机或仪器测量之一作独立对照，不能由此次相似的槽位结果认定某个槽损坏。H2/H3仍未进入。
