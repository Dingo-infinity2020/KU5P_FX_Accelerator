# INTERFACE_CONTRACTS — FX, timing, numbers, data, clocks

**Status:** proposed integration contracts (2026-10-29). Not a claim that every field or feature is implemented. Existing lessons remain frozen prototype semantics until an explicit versioned migration with golden vectors.

## A. Stream semantics and science identity

A signal stream = one complex I/Q voltage source. Antenna count and stream count differ when dual polarization is present. Required map key is (run_id, epoch, source_id, antenna_id, polarization, digitizer_id, signal chain, sign/sideband, sample_rate, config_hash). No automatic inference from index ordering. A consumer must never reinterpret 16 signals as 16 separate sky positions.

Versioned input sample group fields to specify:
- protocol version and actual FPGA wire bytes; endian, I/Q order, signed quantization, full-scale;
- source identity and configuration/epoch ID;
- first sample index from a proven common reference plus samples per frame;
- optional PPS/UTC anchor with explicit validity flag, not invented absolute UTC;
- validity (good/flagged), drop/late/corruption reason, irreversible gap identity;
- packet sequence and frame identity both if network packets do not match FFT frames.

Candidate RFSoC UDP format and per-board counters are **not** final. Do not bind production parser until hardware fixture confirms real IQ bytes, PS software state, PPS synchronization and continuous sample conservation.

## B. Temporal Fourier transforms and physical units

Current prototype: 512-point forward time FFT, natural-order output, 4 taps per phase PFB and Q17 coefficient table; existing integer model includes PFB shift 18 and FFT requantize shift 10, ties-to-even rounding and 16-bit saturation after FFT, followed by cross-products/64-bit integration. Those specifics must be verified against actual generated FFT IP and reference model on any IP/version change. Do not recast stored 64-bit integers as calibrated Jansky without gain/scale/effective-bandwidth model.

For each spectral frame define sample start/end, hop (currently candidate H=512, verify), frequency-bin mapping including negative frequencies/sideband, window/taps, input flags and epoch. FFT channel spacing delta-f = f_s / 512; at 100 MS/s nominal = 195312.5 Hz. Valid scientific bandwidth and spectral resolution after PFB are not proven merely by this bin spacing. Time bin/cadence formula and channel frequency lookup must be an explicit tested function, not guessed from bin index.

## C. X convention, frame and weights

Choose canonical X convention for a < b:
    V_ab[k,w] = sum_{m in planned_window(w)} g_ab[m,k] * E_a[k,m] * conj(E_b[k,m])
where g_ab is 1 iff both streams contribute a trusted aligned spectral frame, otherwise 0 (or explicitly documented finer-grained weighting). Autocorrelation a=a is real power. Hermitian direction V_ba=conj(V_ab) is reconstructed or checked. Define whether scaling applies pre- or post-integration; never silently normalize by zero weight.

Plan window start and end are fixed by absolute frame counter in a valid epoch, not by number of accepted frames. For window length M:
    0 <= W_ab <= min(W_a,W_b) <= M.
Do not silently append later frames when a frame was dropped. Window schema must include first/last planned frame, actual good contribution counts, missing-frame spans, overflow/clip flags, and source/config identifiers.

If a 4-tap PFB needs a nonzero warm-up history, ensure effective_valid only after all required samples/historical frames are good. An invalid/missing frame may poison subsequent filter history even if a later frame is present. PFB history validity is a science requirement, not only an AXI bookkeeping detail.

## D. Numerical policies and bounds

- Both I and Q signed fixed point; signed intermediate multiply, add and rounding must have explicit widths and saturation or wrap rule. Synthesize signedness test vectors at max+, max-, -1, zero, noise and clipping.
- For 16-bit post-FFT components, |I| and |Q| <= 32768; auto power fits at most 2*(32768)^2 = 2^31, cross real/imag can also be as high as 2^31 in magnitude (for individual products). Over M frames, conservative exact signed accumulator width = 1 sign + 31 magnitude + ceil(log2 M) or stronger proven bound; 64-bit margin should be formally assessed for configurable M and additions. Never infer indefinite integration safety from width.
- Denominator W=0 -> flagged undefined normalized visibility; do not silently emit a physically meaningful zero. Make overflow/clip bit sticky per window/source/bin with an explicit clearing boundary.
- Independent reference should provide high-precision complex truth and deterministic bit-exact quantized truth; use both to separate algorithm/math mismatch from quantization bias.

## E. Continuous ingress and backpressure

Distinct timing regimes:
1. real-time producer (sample clock/PPS) MUST advance even if compute is busy;
2. frame buffer admission only if the full framed record fits; record whole-frame drops and holes;
3. stallable internal AXI: keep VALID, DATA, LAST and metadata stable while VALID && !READY;
4. output host consumer may stall and must be buffered or accounted for.

Counters: generated, admitted, dropped, committed, aborted, emitted, pending, invalid-placeholder, malformed, duplicated, missing, late, FIFO high-water. Use disjoint and documented counting units (sample/packet/frame/window). Assert conservation over a completed run; resetting counters is versioned and must not erase identities of emitted loss.

Do not make time-driven input use s_axis_tready to stop its own sample clock, and do not allow a partial accepted frame to contaminate a valid FFT frame. Holding data in the testbench until ready is fine as a *protocol test*, not a true time-driven throughput acceptance.

## F. Visibility packet/host API (future versioned schema)

Each result packet shall ultimately carry version, run/epoch/config IDs, integration sequence, planned first/last input frame, PFB/FFT/hop/sample-rate config, source/antenna/polarization mapping or map ID, bin/physical frequency reference, pair ordering & conjugation convention, signed real/imag accumulation and scaling exponent, W_a/W_b/W_ab or corresponding granular valid counts, overflow/loss flags, payload byte count, checksum/CRC and monotonic output record sequence.

A standalone record must not require host guessing the global source map or original RFSoC network arrival order. Distinguish diagnostic DMA test pattern from science packet. A user-level Windows file or emulated endpoint pass does not prove hardware DMA.

## G. PCIe/100G and CDC contracts

PCIe link dependent milestones: GT/reference qualified -> correct reset sequencing -> LTSSM L0 -> host enumeration -> BAR identity -> one-direction DMA -> two-direction DMA -> FX readout -> recovery. If link is not L0, host-driver debugging is not the first root-cause fix.

Hardware expected: XCKU5P -1 FFVB676I from schematic, target xcku5p-ffvb676-1-i; actual marking and GT mappings must be independently checked. Slot PCIe ref AB7/AB6 and PERSTn T19 are separate from board SYS_CLK and Si5338 CLK2 V7/V6. Do not declare stable refclk from BUFG count/MMCM lock alone; do not assume independent Si5338 output is compatible with common-clock PCIe architecture.

Ethernet: a real link, correct RS-FEC/CMAC and optical module pinout, verified MTU, CRC/UDP integrity and application sequence, and bounded RX buffering are separate stages. Two QSFP28 cages are not two proven 100GbE endpoints. At 100 MS/s x16 x32bit = 51.2 Gb/s before Ethernet overhead; at 320 MS/s = 163.84 Gb/s. One physical 100GbE line can carry the 100 MS/s net *if* an actual aggregation topology and required protocol/IP overhead are qualified; it cannot by itself receive two independent direct Ethernet cables.

Clock domains must have explicit owners, reset assertion/release strategy, proper metastability synchronizers, async FIFOs/handshakes for data and cross-domain counters with coherent capture; only first-stage paths get justified exceptions. Report clock/no-clock/IO coverage; no arbitrary CDC waivers. Some older experimental e0/d images had CDC Critical, while final e4 diagnostic reports zero unwaived Critical; do not mix them.

## H. Failure taxonomy and acceptance

Failures classify as INVALID_SOURCE, FRAME_GAP, DUPLICATE, LATE, CRC_BAD, FIFO_OVERRUN, FFT_PROTOCOL, NUMERIC_CLIP, EPOCH_MISMATCH, CLOCK_RESET_LOSS, PCIe_LINK_LOST, DMA_ABORT. Each must specify a visible flag/counter, unit, frame/window/epoch effect, recovery boundary and regression vector. Unknown signals must be “unknown,” not low.

For science PASS: independent phase/delay, spectral bin, uncorrelated and correlated-noise, RFI/clip, all-invalid, boundary loss, epoch restart tests, plus actual sustained board/network/host evidence appropriate to the milestone.
