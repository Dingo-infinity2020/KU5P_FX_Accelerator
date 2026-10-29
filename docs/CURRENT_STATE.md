# CURRENT_STATE — KU5P FX Accelerator

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

Current permission: DOCUMENTATION ONLY. This doc/AGENTS/plan change is not an experiment and adds no hardware proof.
After an explicit user RESUME instruction, propose **M0 reproducibility/baseline review** first: check clean working tree, re-run bounded Python tests, inspect Tcl for side effects, create frozen manifest/coverage, prepare focused PR(s), then request permission for M1 PCIe or M2 continuous two-lane implementation. M1 BOARD work must always have its own scoped grant.

The plan in [DEVELOPMENT_PLAN](DEVELOPMENT_PLAN.md) is prospective. For raw report and latest real status, the dated experimental record takes precedence over a progress checkbox.
