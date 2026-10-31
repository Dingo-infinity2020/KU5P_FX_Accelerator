# CURRENT_STATE — KU5P FX Accelerator

**2026-10-31最新开发覆盖段（非BOARD）：** 用户按PR6计划授权一轮离线开发，分支 `codex/pcie-cfg-development-2026-10-31`，e5源23ddf83、e6冻结源 `460fa77888d6b45fe4b7f3c5441df73adf9f6615`。e6已通过离线SIM/ROUTED接受，尚未上板。 e5时序通过但CDC-10 Critical1，门槛拒绝/无bit；e6移除VIO与PERST合并，只保留物理PERST。配置父flag开关未改变98生成文件，完整lane0..3静态映射为0..3，不能把动态反转禁用直接当根因。见[实施/验收](lesson05j-pcie-reference-reset.md)、[机器摘要](validation/h1a-cfg-development-2026-10-31.json)。

**本轮停止点：** BUILD_ONLY_COMPLETE_WAIT_FOR_CONCRETE_BOARD_SCOPE。e6 VIO输出0保留/init0，不是PHY复位，旧e4 helper必须拒绝不同身份；新板上步骤需具体授权及经审查的读回入口。没有连接硬件或重读主机；最后历史BOARD仍是e4/DONE1/reset0/arm0/地址1ff/epoch2、GT done高、Polling.Compliance，无L0/枚举。本轮不能宣告现在硬件实测已改变，也不再要求相同e4重启。下方审计-only/WAIT_FOR_IMPLEMENTATION_AUTH为已被当前离线授权覆盖的历史。

**2026-10-31 后续STATIC审计（非新BOARD）：** 进入源 `43580d3`，分支 `codex/pcie-audit-plan-2026-10-31`。确认解析/仿真缺少跨捕获首时间戳溯源门槛；实际DCP的timestamp64输入均接通。另发现XDMA父选项enable_lane_reversal=true，但子核/PCIE40E4的PL_DISABLE_LANE_REVERSAL=TRUE，需查支持接口/参数传播及两端映射，未证实为未建链根因。事件存储实为3 RAMB36E2+1 RAMB18E2，勘误旧“4 RAMB36”。见[审计及具体下一工作包](pcie-audit-and-next-plan-2026-10-31.md)、[摘要](validation/pcie-audit-plan-2026-10-31.json)。没有连接硬件、构建或改RTL；下方仍是最新BOARD历史。下一建议H1a-CFG BUILD_ONLY，WAIT_FOR_IMPLEMENTATION_AUTH；不要重做M0或再次相同重启。

**最新实测覆盖段（2026-10-31）：** 用户“已经重启”，主机记录启动10:02:11.5+08:00。进入源 `bd0b687`，当前分支 `codex/slot2-e4-restart-2026-10-31`。先读确认e4/465805e4、DONE1、实际reset0/arm0、epoch1→2/512。36样本四路GT TX/RX/PMA done高，AXI和训练快照持续更新到Polling.Compliance；当前PLL锁定指示低，无L0/Windows10EE。512地址和8字重复读取均已保存；首事件时间戳早于昨晚epoch1，事件字不含epoch，不能宣称整个启动段溯源通过。事件1..511跨度名义4.92280064秒，仅作为后段相对观察。见[本次报告](slot2-e4-restart-2026-10-31.md)和[机器摘要](validation/slot2-e4-restart-2026-10-31.json)。

**当前停止点 H1_HOLD_POSITIVE_CONTROL_AND_RECORDER_PROVENANCE：** 最终e4/DONE1/reset0/arm0/地址1ff/epoch2，Hardware Manager关闭，无构建/仿真/采集。没有program/reset/arm/ILA trigger，仅安全提交RAM读地址；未写Flash/Si5338/BIOS/驱动/内存/网卡。H1未通过，BAR/DMA NOT RUN。不再等待或要求相同主机重启；后续须先审查记录溯源，并取得有区分力的独立训练/电气正对照。下方所有WAIT_FOR_USER_WARM_RESTART_SLOT2及阴性状态均为历史，不能作为当前待办或当前GT状态。

**最新实测覆盖段：2026-10-30 22:07–22:11，用户新授权的一轮第二长槽 e4 测试结束。** 进入源 `cad2269`，分支 `codex/slot2-e4-trial-2026-10-30`。用户更正旧FPGA实际在第三长槽，现确认在第二长槽；ConnectX-5在第一长槽、GPU第三长槽。初始DONE1但无e4调试核，镜像UNKNOWN；原已验收e4 ×4仅下载一次，arm一次、仅释放一次reset，保存512条epoch1新事件、40个VIO样本和4096点ILA。最终e4/DONE1/reset0/arm0/读址1ff，PLL/GT done低、AXI÷8固定10、Detect.Quiet快照冻结，无L0/10EE枚举；网卡Gen3×16、显卡Gen4×4，主机WHEA仍0。没有Flash/Si5338/BIOS/驱动/内存设置变更。见[本轮记录](slot2-e4-trial-2026-10-30.md)与[验证摘要](validation/slot2-e4-trial-2026-10-30.json)。

**当前停止点 WAIT_FOR_USER_WARM_RESTART_SLOT2：** Hardware Manager关闭，无构建/仿真/采集进行。如继续新第二槽的启动对照，需要用户手动Windows“重新启动”并保持板卡供电/JTAG；不得自动重启。返回后先只读保全DONE/身份/真实控制/epoch，不能先program/reset/arm。下方主机恢复时UNKNOWN及早上第三槽epoch2为历史状态，不是当前镜像；旧槽号错误不抹去原实测。

**最新覆盖段：2026-10-30 晚，主机黑屏事故后逐卡恢复。** 用户完全断电拆卡、内存由5400降至4000并调整后确认A2/B2；Windows内存诊断通过，MemTest86四轮48/48项通过、零错误。随后用户依次装回ConnectX-5、FPGA及RTX 5060 Ti，21:35主机只读检查：网卡Gen3 x16、显卡Gen4 x4、USB调试桥均正常枚举，本次启动WHEA为0；FPGA无10EE枚举，100G端口未连通。详见[事故与恢复历史](host-black-screen-triage-2026-10-30.md)。根因未确定；不是FPGA或系统链路验收通过。

**当前停止点 HOST_RECOVERED_FPGA_STATE_UNKNOWN / WAIT_FOR_AUTH：** 下午断电后不能继续假定早上e4 SRAM现场保留；当前镜像/DONE/GT/LTSSM均未读，本轮未连接Vivado或操作FPGA。原e4实验和原始证据保持不变，下面“保留现场”属于早上历史。下一次FPGA实验需新授权并重建可核对的当前硬件基线，H1/H2/H3仍未通过。

**最新实测覆盖段：2026-10-30 09:34 主机重启已完成，先读 e4 现场已保存。** 进入源为 `eb4ec31`，新记录分支 `codex/e4-restart-observation-2026-10-30`。e4/DONE1/reset0/arm0 保留，epoch1→2，完整读出512条新事件（名义4.711秒）。36个后读样本四路TX/RX/PMA done高、CPLL当前mask2、AXI计数和训练序号活跃，实时更新的 Polling.Compliance；没有L0、Windows无9034，BAR/DMA未测。没有program/局部复位/arm/触发ILA，仅为读RAM安全提交地址。最终读址1ff，Hardware Manager关闭。详见[新启动观察](e4-restart-observation-2026-10-30.md)与[验证摘要](validation/e4-restart-2026-10-30.json)。

**当前停止点 H1_HOLD_POSITIVE_CONTROL：** 保留已初始化现场，不再次要求相同重启或局部复位。下一项有效对照需厂家已运行的兼容PCIe示例、另一合适主机或参考/接收侧测量之一；尚不具备。启动早期的锁定和数字比率不能替代稳定参考/PLL及L0验收。下方WAIT_FOR_HOST_RESTART与epoch1均为该次重启前历史，不是当前待办。

**最新覆盖段：2026-10-30 夜间用户已明确授权恢复开发，至需要重启/人工操作时停下。** 已从远端 `ddf306e` 创建 `codex/m0-nightly-baseline-2026-10-30`，完成 M0：冻结源 `fb7a0d9` 的 72 Python 测试、14 诊断/9 训练检查、29 包应用仿真、226 帧/90 窗口完整 PFB-FX 回归通过；不是板级持续吞吐。235 项输入冻结，新旧证据严格分开。原 05A 构建脚本已按原哈希恢复并归档。详见[本轮报告及恢复入口](m0-night-development-2026-10-30.md)与[验证摘要](validation/m0-night-2026-10-30.json)。

**当前停止点 WAIT_FOR_HOST_RESTART：** 本轮实际只读确认仍为 e4/465805e4、DONE1、local reset0、arm0、epoch1/512 条，尾事件与旧记录一致；未 program/reset/arm/触发 ILA，无新综合/布线。Windows PresentOnly 9034 仍 0、无 L0/BAR/DMA；Hardware Manager 已关闭。下一步需要用户手动 Windows“重新启动”并保持板/JTAG供电，返回后先只读保全，不得先重下位流/复位/arm。以下 2026-10-29 的 documentation-only 与暂停是历史基线，不覆盖本轮新授权和实测。

## 2026-10-29 历史基线

**Snapshot:** 2026-10-29. **Reviewed source:** codex/progress-2026-10-28 @ b89a5c433e9222e5ed2cedce110c5e79790bca2f (unmerged Draft PR #1). **Scope:** cloud source/docs and prior experimental evidence; no fresh Vivado/board run by this review.

> STOP / HUMAN GATE: Prior user instructed development to pause after final e4 PCIe experiment. The 2026-10-29 follow-up authorized documentation/agent/planning updates only. Do not resume board, driver, RTL or BUILD work just because a milestone exists. Revalidate this STOP at each new local session against more recent explicit user instructions.

## Repository topology

- Default main @ e00d357: bootstrap only, not a working FX implementation.
- Active feature branch: codex/progress-2026-10-28 @ b89a5c4 before this documentation update, Draft PR #1 -> main; does not imply merge approval.
- Frozen source snapshot contains 227 files: 36 rtl/, 21 sim/, 65 scripts/, 35 tcl/, 10 tests/, 43 docs/ plus constraints and top-level files. No canonical AGENTS.md existed before this change.
- Worktree: D:\work\KU5P_FX_Accelerator. Artifacts: D:\work\build\KU5P_FX_Accelerator; local generated IP and original/vendor/RFSoC sources remain off GitHub.
- Windows 10/Vivado 2026.1 BASIC and JTAG setup have been recorded as working on the original development host. Actual availability must be checked locally.

## Capability and evidence matrix

| Capability | Evidence already in repo | Status/limit |
|---|---|---|
| complex power and two-channel X | Python integer reference, HDL simulation, independent synthesis | Prototype PASS; not sixteen streams |
| two 512-bin temporal FFT-FX | official AMD FFT cores and independent verification | simulation/OOC PASS, FPGA integration later |
| 4 taps/phase PFB, fixed windows, W_A/W_B/W_AB, epoch/source tags | 226-frame/90-window pipeline suite and fixed-point comparison | simulated PASS, no full continuous physical ingress |
| lesson05A onboard ROM replay | two captures each 8192 input pairs / 2048 result rows, 650-bit exact comparison; 100 MHz design WNS +3.339 ns | short BOARD PASS, not an external stream |
| optimized two-lane PFB-FFT-X | 128-frame 65536-pair throughput case; at nominal 125 MHz ~122.114 MS/s/lane; OOC 8 ns WNS +2.683ns, 72 DSP, ~15 BRAM36 | simulation/OOC PASS; real continuous 100 MS/s BOARD NOT RUN |
| offline candidate RFSoC UDP parser | synthetic packets, corruption/reorder cases | candidate only; real I/Q format and synchronization NOT VERIFIED |
| PCIe XDMA test endpoint / Windows test | AXI-Lite, AXI Stream, patterned-DMA source, routed diagnostic builds; user app simulated/file-tested | link L0, OS 10EE:9034, BAR and hardware DMA NOT PASS |
| PHY/clock diagnostic experiments | e0, d-series, e1-e4; checked pin/GT refs and saved logs | useful evidence, unresolved root cause; no blanket “PLL fixed” |
| independent Si5338 read-only | two page0 reads, read waveform; LOS_CLKIN and input selection discrepancy | evidence PASS, external clock output not qualified; no writes |
| single-port 100GbE receive | preliminary catalog/protocol and CMAC planning | no received real packets or link |
| 16-input / 136-product FX | architectural budget and candidate protocol | NOT IMPLEMENTED/NOT VERIFIED |
| sky calibration/FFTT | long-term proposals | NOT IMPLEMENTED |

## Exact hardware stop

Latest: e4 / identification 465805e4 loaded to SRAM, DONE=1, local reset=0, hardware manager closed. e4 recorder built with ROUTED WNS +1.174 ns, CDC Critical 0 for checked diagnostic, 512 event entries captured. It observed transient CPLL indications, but TX/RX resetdone remained zero; PCIe LTSSM did not reach L0, Windows had zero 10EE:9034 devices, BAR and actual DMA untested. The event FIFO filled early (~212 ms nominal), so it did not fully observe the later startup window.

Earlier **e0 retained host-restart experiment** is not the same as e4: at first observation it had GT TX/RX resetdone high and reached live Polling.Compliance, but no L0/OS enumeration; after local reset it failed to reinitialize. A hypothesis must explain BOTH conditions, rather than erasing the earlier positive indication. Numerical “reference clock” counters were not stable calibrated measurements.

Si5338 page0 had LOS_CLKIN=1, IN1/2 selection despite board source expected IN3 and reserved output format encoding; the clock was not reprogrammed. Its CLK2 V7/V6 is a separate route from slot PCIe ref AB7/AB6; do not claim direct causality. No driver install, BIOS change, reboot or Flash/NVM writes in final e4 experiment.

Read first:
- [Final e4 stop](lesson05i-pcie-boot-recorder.md)
- [e0 three-stage retained-restart observation](pcie-restart-observation-2026-10-29.md)
- [Independent physical-routing audit and recovery hypotheses](review-and-recovery-plan-2026-10-29.md)
- [Si5338 read-only](lesson05f-si5338-readonly.md)
- [Post-route reference and reset evidence](validation/physical-refclk-review-2026-10-29.json)

## Unresolved blocking risks

P0: Unstable PCIe reference/GT/clock-reset bring-up, no working L0/enum/BAR/DMA.
P0 for real science: genuine time/phase alignment, per-stream sample identity and transport loss accounting not verified.
P1: non-stallable ingress admission, bounded overflow, complete planned-window semantics and resilience under saturation.
P1: 16-stream compute/BRAM/URAM/F-engine and link capacity have not been closed or mapped.
P1: production CDC/reset coverage and negative/error recovery test matrix.
P2: wide PR mixes mature FX, experimental GT diagnostics and unmerged lessons; refactor only after frozen proof.

## Next authorized action and safe next development package

Latest BOARD stop remains H1_HOLD_POSITIVE_CONTROL_AND_RECORDER_PROVENANCE; the second-slot restart completed with GT done observed but no L0/enumeration. The subsequent STATIC audit proposes H1a-CFG BUILD_ONLY under new explicit implementation scope, not repeated reboot, M0 or hardware changes. See the dated audit/plan above. No board reread in the audit.

The plan in [DEVELOPMENT_PLAN](DEVELOPMENT_PLAN.md) is prospective. For raw report and latest real status, the dated experimental record takes precedence over a progress checkbox.
