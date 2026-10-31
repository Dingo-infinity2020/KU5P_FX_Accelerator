# DEVELOPMENT_PLAN — stage-gated KU5P FX Accelerator roadmap

**Created:** 2026-10-29. **Reference:** codex/progress-2026-10-28 @ b89a5c4, Draft PR #1. **Status:** PLAN / NOT AUTHORIZATION. No new RTL, Vivado run, hardware operation or driver change was performed while preparing this plan. Do not override the latest stopped e4 hardware state.

## 1. Objectives, exclusions, measurable definition of done

**Near-term scientific instrument:** an FPGA FX correlator for 16 complex signal streams with 512 frequency channels (subject to science passband revision), 16 real auto spectra + 120 unique complex crosses = 136 visibility products, separately recorded valid contribution weights, source/polarization identifiers and fixed planned integration intervals. Validation must include a golden correlator comparison, known complex phases and delays, noise/RFI, repeatable throughput, transport loss and host readback. Envisaged scientific integration example is ~1 s, but cannot call it a real UTC-second interval until PPS/epoch mapping is verified.

**First supported configuration:** 2 complex streams, 100 MS/s/stream nominal target, KU5P 512-channel 4-tap PFB -> forward FFT -> complex X -> planned-window accumulation, existing signed fixed-point implementation preserved until reviewed. A user-provided 16-bit I/Q container is not proof of 16 effective ADC bits.

**Out of scope until explicitly authorized:** changing existing RFSoC original project, direct dual 100GbE reception without a second proven MAC/PCS, FFTT/spatial Fourier telescope, automated astronomical calibration solver, full 320 MS/s two-board path, NVM/Si5338 permanent settings, full-band raw capture to host.

**Global completion:** independent acceptance of numeric correctness (SIM), timing/CDC/resources (ROUTED), actual data and reset safety (BOARD/LINK), sustained loss-accounted streaming (SYSTEM) and scientific metrics (SCIENCE). No green status for unexecuted layers.

## 2. Proven capabilities to reuse, not rebuild

- rtl/complex_power_accumulator.sv, rtl/two_channel_correlator.sv: sample-domain baseline complex power/X.
- rtl/pfb_fir_pair_512_pipeline.sv, rtl/fft_pair_512_pipeline.sv, rtl/channelized_x_pipeline.sv, rtl/two_channel_pfb_fx_pipeline.sv: newer pipelined 2-stream PFB/FFT/X and metadata.
- sim/tb_pfb_fx_pipeline.sv and supporting reference vectors: 226 frames, 90 windows, 46080 650-bit result rows in recorded successful tests.
- rtl/lesson05_replay.sv and lesson05_board_top.sv: a **separate earlier** on-board ROM replay, not the pipelined continuous-ingress proof.
- rtl/pcie_test_endpoint.sv + rtl/dma_pattern_source.sv: independent test application, not working hardware DMA while LTSSM is below L0.
- rtl/lesson05i_pcie_boot_top.sv, rtl/pcie_boot_diagnostics.sv: current board diagnostic hardware, not production PCIe reset design.

Do not regenerate/rewrite old historical experimental source just to clean naming. New cores use separate names, immutable comparison vectors and fresh build paths. All known numerical scaling and reference conventions must be preserved or versioned when intentionally changed.

## 3. Dependencies and parallel work lanes

Lane H (HOST/PCIe): H0 baseline evidence -> H1 stable GT/PLL and L0 -> H2 enumeration/BAR -> H3 C2H/H2C hardware DMA -> H4 stress/recovery.
Lane F (FX): F0 baseline independent regression -> F1 bounded non-stallable source/whole-frame buffer -> F2 on-board two-stream sustained run -> F3 4/8/16 scaling and science checks.
Lane N (NETWORK): N0 offline real-wire protocol contract -> N1 one 100GbE MAC/PCS link -> N2 bounded packet reception/reassembly -> N3 real RFSoC short-run sync/phase.
Lane S (SYSTEM): after H3 + F2 + N2, integrate input -> computation -> DMA, then real field qualification.
Lane G (GOVERNANCE): requirements, source hashes, test evidence, release identity and rollback throughout.

H and F can progress **independently only once user explicitly resumes**. No experiment automatically launches from passing another lane. S and science tests are blocked on component gates.

## 4. Work packages and exit criteria

2026-10-31 execution: H1a-CFG offline round authorized and completed through its actual gates. e5 was rejected at CDC-10 before bitstream; e6已通过离线SIM/ROUTED接受，尚未上板。 [Execution/evidence](lesson05j-pcie-reference-reset.md). Parameter true/false produced identical98 HDL/XDC files and connector-to-core mapping is identity, so do not blindly enable dynamic reversal. Capture provenance acceptance/negative cases added, hardware anomaly still OPEN. M0/FX remain reusable history. Next gate is a concrete e6 BOARD scope if its proof is accepted, never old e4 reset sequencing or automatic restart. Later on 2026-10-31 that BOARD scope was executed: e6 in CPU G5 reached L0 and Windows enumerated `10EE:9034` (BAR/DMA NOT RUN; see the H1 override).

**Current next package after 2026-10-31 audit:** H1a-CFG BUILD_ONLY, detailed [execution contract](pcie-audit-and-next-plan-2026-10-31.md). Reconcile parent lane-reversal intent with child/primitive disable attribute, verify connector-to-core lane0 before narrowing width, add capture provenance fault acceptance, then prepare one official-example-derived candidate. M0 is historical PASS. This user request covers audit/docs only; no implementation started, no new board evidence. Later BOARD requires a concrete single-change candidate/rollback and explicit scope.

### M0 — baseline reconciliation and reproducible repo (FIRST after RESUME; offline only)

2026-10-30 execution: M0 completed under the user's explicit night-development grant; 72 Python tests and bounded existing HDL regressions passed on frozen source `fb7a0d9`. Fresh simulation, historical artifact/source recovery, and read-only retained-e4 observation are reported separately in [the execution report](m0-night-development-2026-10-30.md). H1 latest stop is in the dated H1 override below; the previously requested user-performed restart has completed. No automatic reboot or unrelated RTL/GT sweep.

Inputs: actual Windows worktree, latest GitHub refs and Draft PR #1; previous lesson05A/05C/05I proof, IP regeneration Tcl. Deliver:
1. Reconcile local uncommitted files and remote HEAD; locate every authored source, generated IP dependence, board pin/part, and existing test launcher. No destructive reset/clean. Maintain manifest of SHA, tool versions, constraints, exact historical output directories.
2. Run bounded Python offline tests and self-checking HDL simulations only under approved offline scope; sample any reproducer for exact arithmetic output and negative cases. Mark unavailable tools/models NOT RUN rather than fabricate.
3. Inspect generated IP configuration (FFT v9.1, XDMA 4.2, eventual CMAC), verify no hidden GUI-only source; lock parameters and tested part xcku5p-ffvb676-1-i against actual vendor schematic. Don't commit generated IP.
4. Triage tracked branch vs main, segregate stable F-core from PCIe experiments in reviewable commits/PRs; do not blindly merge the whole 227-file branch into main, do not delete recorded failure history.
5. Add a machine-checkable regression launcher with manifest and statuses (PASS/FAIL/SKIP); put all outputs outside repo.

PASS: clean reproducible source baseline; known tests with exact counts; no secret/vendor leakage; no missing rebuild dependencies or unrecorded assumptions; preserved e4 rollback. HOLD: IP/license or original evidence missing -> report precise blocker, not fake recovery.

### H1 — causal PCIe electrical/clock/reset investigation (BOARD approval separately required)

2026-10-31 later BOARD override: e6 `465805e6` moved to `PCIEX16(G5)` (CPU x16, root port A70D), JTAG-loaded, and given a real PERST by a warm restart. Measured **L0**, `link_up=1`, GT TX/RX/PMA done, QPLL1 lock, negotiated **Gen3 x4**, and Windows enumerated **`10EE:9034`** (problem 28 = no driver). BAR/driver/DMA **NOT RUN**; repeatability PENDING. The GPU on G4_2 (7A44) Gen4 x4 and NVMe on M.2_2 (7A48) Gen4 x4 are working PCH x4 controls, so the previous second-slot failures are now attributed primarily to **PCIEX16(G4)_1 / root port 7A40**, not to the FPGA, reference clock or e6 reset entry. [Report](e6-g5-link-2026-10-31.md). The older second-slot H1 HOLD paragraphs below are preserved history; they no longer mean the FPGA cannot link. H2 remains blocked on a legal Windows XDMA driver.

2026-10-31 latest: retained-e4 restart in corrected second long slot completed. GT TX/RX/PMA done observed, live Polling.Compliance, no L0/10EE; current PLL lock indicators low. Full512 address readback preserved, but event0 timestamp predates prior session, so whole-prefix temporal provenance HOLD; events1..511 span nominal4.92280064s after PERST high. [Current evidence](slot2-e4-restart-2026-10-31.md). Stop H1_HOLD_POSITIVE_CONTROL_AND_RECORDER_PROVENANCE, not another reboot/reset. No program/reset/arm/ILA/new build. Older wait/third-slot paragraphs below are historical.

2026-10-30 evening: user corrected previous FPGA location to the third long slot and explicitly authorized one trial in the now-confirmed second long slot. Same accepted e4 programmed once after host boot; no GT initialization/L0/enum, full new evidence saved, final reset0. WAIT_FOR_USER_WARM_RESTART_SLOT2 before a retained-firmware startup comparison in this new configuration. [Trial and corrected slot history](slot2-e4-trial-2026-10-30.md). Host recovery changed multiple conditions; no single-slot causal verdict.

2026-10-30 retained-e4 restart completed by the user: epoch2/512 new events saved, all four TX/RX reset-done observed and fresh Polling.Compliance; no L0 or enumeration. H1 overall HOLD pending an independent positive control, not another identical reboot/reset. See [the new observation](e4-restart-observation-2026-10-30.md); this does not advance H2/H3 or qualify physical reference quality.

Question: why did retained e0 first show CPLL/GT initialized and live Polling.Compliance, then fail after local reset, while e4 showed intermittent CPLL and no TX/RX done? Preserve these distinct histories.

H1a STATIC/BUILD-only first: audit exact XDMA generator clock/reset/reset bridge, selected CPLL/QPLL for link speed, slot PERSTn and x4 lane reversal/physical pin maps, GTPOWERGOOD validity, REFCLK buffer CE/CLR, reference routing, GT RX termination/idle semantics and clock startup timing. Distinguish PCIe slot reference AB7/AB6 from Si5338 CLK2 V7/V6. Recheck e4 event recorder coverage (512 events, early overflow) and label unknown signals as unknown. Derive one minimal discriminating experiment with original validated rollback and no diagnostic edits to trained GT inputs.

H1b only after explicit BOARD authorization: one controlled experiment with precise initial state, firmware identity, expected clock/PLL transitions, 3 outcomes and abort thresholds. Prefer independent positive reference/validated vendor design/instrument/other host where necessary rather than endlessly changing small counters. No implicit host restart, driver install, RAM clock change, Flash, NVM or automatic reprogramming. Si5338 write is separate high-risk approval after full page backup, complete ClockBuilder plan, output electrical compatibility and reversible RAM-only transaction.

PASS (stable PHY): exact loaded firmware identity, repeated qualified reference and selected PLL lock, all required reset-done, LTSSM progressing to live L0, repeatability after specifically tested local reset / controlled restart; no new CDC Critical or false_path masking true interactions. If no credible positive control, HOLD and state required hardware evidence; do NOT force d6/d7-style ECO observations as proof.

### H2 — Windows device enumeration and BAR contract

Precondition: H1 L0 proven. Validate actual Gen/width, device and subsystem ID, OS enumeration (target test VID:DID 10EE:9034 when configured so), read-only BAR identity/version, separately writable safe scratch registers, AXI-Lite errors, reset conditions and no unintended MMIO side effects.

Drivers: choose legal vendor-compatible Windows XDMA driver or properly authorized development signing environment. No permanent change to test signing/secure boot as a workaround without separate approval. Compare PCI hardware IDs and driver binding; Python simulated device files are not a hardware pass.

PASS: cold/warm enumerations within bounded trials with recorded link speed/width, bidirectional register transaction agreement and negative invalid-register handling. Never call a Windows re-scan a substitute for PCIe physical L0.

### H3 — deterministic C2H / H2C DMA and host APIs

Precondition: H2 PASS. Test on-chip deterministic packets -> XDMA C2H -> Windows user-space checksum and reverse H2C stress pattern -> FPGA counters. Check TLAST/TKEEP, partial last beat, descriptor size, interrupt vs polling, flow control, corruption, duplicate/overrun and host failure/retry. Record actual sustained MB/s and lost-packet counters, not theoretical link speed. Keep visibility packet format versioned, explicitly separated from raw sample frames.

PASS: round-trip known bytes with independent checksum, per-direction counters match, abort/restart controlled, documented Windows API; calibrated throughput and CPU utilization; repeatable DMA under benign and injected backpressure. Need explicit user approval before large/high-rate stress.

### F1 — non-stallable ingress, bounded buffer, integrity accounting

Precondition: M0 baseline and explicit offline RESUME; no PCIe needed. Build a time-driven two-stream synthetic producer with frame-id monotonically incrementing regardless of FX ready, a **whole-frame admission** buffer, missing-frame placeholder mechanism and sink; never overwrite a half accepted frame. Keep internal AXI valid/data/last stable while stalled. Define accepted, committed, dropped, invalid, duplicate, aborted, output and high-water counters.

Tests: normal ~100 MS/s/stream target (simulation measured clocks, no claim of real board rate), random backpressure, 100% stalls, one-cycle bursts, FIFO-full, reset at each phase, discontinuous frame IDs, bad source/epoch/config, multiple windows M=1 and M>1, tag/FIFO wrapping, clip/saturation. Compare independent time/weight contract and all channel visibilities, not only number of output lines.

Invariant: generated frames = delivered valid frames + explicitly lost frames + explicitly pending frames (with consistent abort accounting); planned integration never lengthens; W_ab <= min(W_a,W_b) <= M; no accepted sample repeats or reorders. Data overflow must not deadlock the entire chain silently. Any packet-drop recovery algorithm is versioned and tested rather than assumed.

PASS: exact reference for deterministic/fault tests, no unbounded memory or invalid handshake, proven finite-stall recovery and explicit intentional-loss signatures; resource and clock target budget documented. No BOARD claim yet.

### F2 — two-stream full-board continuous operation

Precondition F1 PASS; exact board timing/CDC and separate BOARD authorization. Use an internal free-running independent clock/traffic generator, not a stallable ROM. Confirm behavior against independent reference and readable error counters with ILA/VIO or DMA after H3.

Initial target: 2 streams each at 100 MS/s (nominal scientific sample rate), 512-bin 4-tap PFB, 1-second planned integration example (epoch not UTC unless mapped), at least one short correctness run plus bounded sustained run. Proposed staged evidence targets: 60 s controlled short run, then 10 min sustained only after explicit stress authorization. If time/temperature/resources prohibit, HOLD and report measured limit. Ensure output drain can be disconnected and loss is reported rather than hidden.

PASS: zero unexpected sample/visibility loss under guaranteed-load case, expected explicit drops when overload is injected, no CDC Critical, routed and board clock closure, source/epoch/bin/phase correctness, bounded latency and resource/timing reports. A nominal 125 MHz OOC result is not proof of full-board 100 MS/s.

### F3 — 4, then 8, then 16-stream X scaling (one stage per approval)

Do resource and memory scheduling before writing 16 copies. Move from two-input prototype to parameterized N source and frequency/channel scheduler. Evaluate fully parallel vs time-multiplexed complex multipliers, BRAM/URAM accumulation banks, output-drain concurrency, F on KU5P vs upstream RFSoC, optional cross-polarization product mapping. Complete 4 streams (10 products) with checked source/polarization mapping, then 8 (36), then 16 (136). Each size has an independent reference matrix, randomized noise/phase, overload, timed route and resource budget.

**Illustrative full-band capacity** (not achieved numbers): 16 x 100 MS/s x 32 bits = 51.2 Gb/s net sample bytes. 16*17/2=136 X products per 512-point frame. For hop=512 and every bin preserved: 136 * 100e6 = 13.6 G complex pair products/s. At 250 MHz this implies ~54.4 products/clock aggregate before overhead; at 125 MHz ~108.8. Minimum state bits for 16 64-bit real autos + 120 (real64+imag64) crosses over 512 bins = (16+240)*512*64 = 8,388,608 bits (=1 MiB), >227 ideal BRAM36 equivalents before banking/port overhead. URAM/BRAM banking and traffic scheduling must be assessed instead of deriving feasibility only from DSP count. If channel selection or hop changes, redo numbers explicitly.

Outputs for 1-second windows: 136*512=69,632 baseline-frequency entries/s. Their *bare* 64-bit auto plus 128-bit cross data total ~1 MiB/s before headers/weights; host result bandwidth can be far below raw 51.2 Gb/s. Do not confuse PCIe output with input transport.

PASS for each N: 136-product (for N16) full matrix vs independent high-precision and bit-exact model, no cross-window contamination, deterministic counts and weights, timing+BRAM/URAM/DSP closure at actual configured clock, sustainable source and drain, explicit pol mapping.

### N0/N1/N2 — source transport protocol and single-port 100GbE

N0: Read actual RFSoC firmware capture BEFORE declaring wire format final. Existing candidate model: two RFSoCs each 8 complex streams, time-domain I/Q16 container; 100 MS/s variant preferred for early scope, 320 MS/s historical path exists. Candidate UDP payload 32-byte metadata + 8192-byte samples, 2048 complex samples/packet, possible padded Ethernet tail; verify with signed test patterns and live capture. Frame rate, endian, sample index, PPS/epoch, overflow and channel mapping must be checked; do not infer shared UTC from packet counter.

N1: Recover one working 100GbE endpoint with correct GT/ref, SR4 optics, MPO polarity, CMAC/FEC, MTU and actual link. This old installation limit was resolved during 2026-10-30 host recovery: ConnectX-5 is installed in the first long slot and both functions were observed at Gen3x16. Optical link/traffic remain unverified; current audit does not operate the NIC. Do not assume another host is mandatory solely from the superseded mechanical report. Validate no link-level or MAC errors with controlled traffic first. One KU5P hard CMAC cannot automatically serve as two independent 100G receivers. For two RFSoC sources, design an external aggregation path or a separately justified second MAC/PCS interface. No assumption that two QSFP cages imply two proven 100GbE receivers. Both RFSoC 320-MS/s streams together would be 163.84 Gb/s net, exceeding one 100GbE port.

N2: Packet parser/reorder/jitter buffer/source time alignment with explicit missing, duplicate and late data handling. Test before FX and then at input. Admit full FFT frames only. Verify long-run ingress counters and passband/noise performance with actual traffic. No real-hardware status from synthetic PCAP tests.

PASS N stages independently: actual optical link/CMAC state, verified raw bytes, exact packet conservation, aligned frame sequences and controlled corruption/overload behavior; host and FPGA physical throughput measured separately.

### S1/S2 — end-to-end visibility and astronomy acceptance

Precondition H3 + F2 + N2, then staged 4/8/16. Couple source -> channelizer -> scheduled X -> visibility record -> actual XDMA -> host archive. Output records must have schema version, source/polarization order, conjugate sign, bin frequencies/FFT order, epoch/frame range, integration length, W, overflow/loss flags, calibration/config ID, scaling units and checksum. Explicitly distinguish delay alignment, gain calibration and noise/RFI science acceptance from hardware “produced some bits”.

Scientific vector suite:
- identical coherent signal with known phase offset: Hermitian symmetry V_ba=conj(V_ab), auto >=0;
- delayed complex tone and chirp: phase slope across bins and FFT sign/sideband;
- complex Gaussian correlated/uncorrelated streams: expectation/variance vs integration length and W;
- amplitude sweep / clipping / RFI tone: distinguish desired signal vs fixed-point overflow and leakage;
- all-zero/one missing stream: W zeros and flagged products, no false positive coherence;
- clock/epoch restart, data reorder and source/polarization swap: explicit mismatch detection and rejection.

PASS: archived raw test fixtures and repeatable visibilities with quantified amplitude/phase/numerical tolerance, full packet/time conservation, host API and safe restart, sustained throughput within declared scope. For astronomical on-sky validation, separately authorize antenna pointing/ADC/RFSoC field test; do not call synthetic-only tests science verified.

## 5. Decision records (must be resolved before major architecture investment)

ADR-001: F location. Keep KU5P local-F for present time-domain RFSoC; decide upstream channelized option only after physical interface/compute trade and preserving complex phase.

ADR-002: transport. Two QSFP28 cages vs one hardened 100G CMAC; choose single-port aggregator, second soft Ethernet stack or different host input only after link/resource/license verification.

ADR-003: per-stream sampling. 100 MS/s candidate for early 16-stream 51.2 Gb/s net path; 320 MS/s would be 163.84 Gb/s for 16 streams, so cannot be silently merged into this plan. 100 MHz effective science passband, anti-alias and decimation must be measured, not assumed from container/sample clock.

ADR-004: accumulation and memory. 64-bit math over M requires provable overflow bound, saturation/rounding policy, W granularity and bank-conflict proof; select RAM architecture against actual KU5P resource reports.

ADR-005: Windows driver. Preserve Windows-first requirement; use qualified XDMA driver only after enum and approved installation path. Do not force Linux as a prerequisite for FPGA RTL design.

ADR-006: polarization/science. 16 voltage streams might be 8 dishes x 2 polarizations, not 16 independent antennas. Require source-to-antenna-pol table before sky interpretation and FFTT.

ADR-007: reset policy. Distinguish local debug reset, PERSTn, FPGA configuration, host warm reboot, GT reset and external Si5338; future production recovery must be measured, not copied from a one-time e0 restart success.

## 6. Evidence and release process

For each package produce:
- one-page contract: exact hypothesis, frozen input manifest/source SHA/IP/part, allowed operations and explicit stop threshold;
- independently derived expected outputs and negative cases;
- test results with command, clock period, actual coverage, exit code and Error/Fatal, report_cdc and constraints;
- if ROUTED, DCP/bitstream hash, WNS/WHS, DRC, routing, clock/I/O coverage, resource report;
- if BOARD/LINK, device identity/firmware signature, reset and host boot state, full raw capture + independently decoded results, rollback/thermal boundaries;
- brief sanitized summary linked to original off-repo evidence;
- explicit status: PASS / HOLD / FAIL / NOT RUN, no cross-level substitution.

Large generated files and raw captures stay under D:\work\build\KU5P_FX_Accelerator or F: archive, never in Git. Authored source and small sanitized summaries can enter focused PR. Main only after review and proven relevant gate; still keep failures recorded.

## 7. Immediate handoff to future local Codex

**LATEST (2026-10-31 BOARD):** e6 in `PCIEX16(G5)` (CPU x16) reached L0; Windows enumerated `10EE:9034`; BAR/driver/DMA NOT RUN; H2 blocked on a legal XDMA driver; `PCIEX16(G4)_1`/root port 7A40 is the primary suspect for the previous failures. See [the G5 report](e6-g5-link-2026-10-31.md). The audit-era handoff below is preserved history.

**EARLIER (2026-10-31 audit):** audit/planning complete; hardware/implementation HOLD. M0 was completed on frozen source and must not be restarted merely because this handoff used to say so.
**WHEN USER AUTHORIZES IMPLEMENTATION:** select H1a-CFG BUILD_ONLY from the dated execution contract, preserve e4 and prior captures, reconcile generated config and evidence acceptance before one candidate build. Stop before BOARD unless separately and concretely authorized. FX/F1 and networking stay deferred under the user's board-first priority. If inputs/tools are unavailable, report the precise blocker rather than fabricate results.

Pointers: [Current state](CURRENT_STATE.md), [Interface contracts](INTERFACE_CONTRACTS.md), [Review backlog](REVIEW_BACKLOG.md), [Last e4 hardware proof](lesson05i-pcie-boot-recorder.md).
