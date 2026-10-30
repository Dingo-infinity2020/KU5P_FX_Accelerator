# CURRENT_STATE — KU5P FX Accelerator

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

Latest stop point is H1_HOLD_POSITIVE_CONTROL in the top override: user completed the retained-e4 host restart, new events are saved, GT initialization observed, but no L0/enumeration. Preserve this state; no repeated reset/reboot or driver installation. A new causal experiment needs an available independent positive-control condition and a concrete scope. Earlier WAIT_FOR_HOST_RESTART and documentation-only sections are historical.

The plan in [DEVELOPMENT_PLAN](DEVELOPMENT_PLAN.md) is prospective. For raw report and latest real status, the dated experimental record takes precedence over a progress checkbox.
