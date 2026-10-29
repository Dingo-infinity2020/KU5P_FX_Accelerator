# AGENTS.md — KU5P FX Accelerator local Codex operating contract

> Applicable to the entire repository. Read this file FIRST when entering this worktree.
> This is the canonical Codex instruction file (plural AGENTS.md). AGENT.md is a pointer only.
> Documentation baseline: 2026-10-29, development branch codex/progress-2026-10-28 at b89a5c4. Always refresh branch/state before acting.

## 0. Mission and scope

Develop a reproducible, scientifically trustworthy FPGA FX correlator on the FNIC-KU5P (Kintex UltraScale+ XCKU5P) with a Windows/Vivado 2026.1 development host. Near term: two-input PFB/FFT/X continuous processing, PCIe host readout and then scalable 4/8/16-stream visibility production. Long term: optional FFT telescope demonstration, NOT the next task. The existing two-stream RTL/verification is valuable and must not be discarded without a falsifiable reason.

**CURRENT HOLD:** The latest documented user instruction was to stop hardware/FX implementation after the e4 PCIe startup-recorder attempt (2026-10-29). The present request authorizes ONLY updating repository review/planning/agent documents. Never infer authorization to resume RTL implementation, synthesis, hardware configuration, driver installation or experiments from this file or a roadmap. Obtain new explicit user authorization before executing any paused implementation work. Do not treat a plan or an old permission as a standing execution grant.

## 1. Required reading / source of truth

At EVERY new local Codex session:
1. Check actual working tree and remote, without assuming this machine's checkout is on the correct branch:
       pwd
       git status --short --branch
       git remote -v
       git branch -vv
       git fetch origin --prune
       git log -5 --oneline --decorate
   Verify that local work is not dirty or diverged before checkout, pull, cherry-pick or rebase. Do not overwrite local changes. State the exact working-tree path, branch and commit SHA in the first work report.
2. Read docs/CURRENT_STATE.md (current evidence and STOP point), docs/DEVELOPMENT_PLAN.md (stage gates), docs/INTERFACE_CONTRACTS.md (science and interfaces), docs/REVIEW_BACKLOG.md (known audit tasks).
3. Read README.md, docs/workflow.md, docs/hardware.md, docs/implementation-roadmap.md and the relevant lesson/validation documents cited by the selected task.
4. Read the actual RTL, constraints, build scripts, tests and build manifests before changing any of them. A GitHub snapshot, an old chat conclusion or a saved pass marker cannot replace present source inspection.
5. Report any difference between documentation and actual HEAD/board before using the documented state. The latest evidence wins, but never rewrite old experimental history to make it appear to pass.

Decision hierarchy: explicit CURRENT user authorization and safety constraints > this agent contract > current-state and stage-gated plan > interface contracts > historical experiment notes. When conflicting, stop and report the conflict; do not silently choose a risky interpretation.

## 2. Working directory and repository hygiene

Windows source: D:\work\KU5P_FX_Accelerator
Windows build artifacts: D:\work\build\KU5P_FX_Accelerator\<task-id>\
Vivado: D:\AMDDesignTools\2026.1\Vivado (BASIC node-locked; check actual availability before relying on it).
Temp: D:\tmp. F: is backup/archive only; never use C:, desktop, OneDrive or source root as build output.
Never assume the host has Linux, RFSoC access, 100G NIC or an installed Windows XDMA kernel driver.

- Keep scripts, synthesizable RTL, self-checking testbenches, XDC, reconstruction Tcl, reference models and sanitized compact evidence in Git; keep generated Vivado IP, bitstreams, DCP, waveform dumps, reports, raw captures and vendor package locally.
- Never commit keys, tokens, MAC/serial/host IDs, license files, passwords, confidential vendor IP/document bundles, original RFSoC projects, raw captures or test signing certificates. Use a staged-secret scan and git diff --check.
- Keep original test failures, rollback hashes and older snapshots immutable. Never overwrite the one known-good/last-observed hardware evidence directory.
- One hypothesis/isolated change per experiment; file and top names must identify actual loaded image, not just presumed source.
- Follow docs/workflow.md on branches/PRs; main is NOT current implementation HEAD. The large draft PR #1 is not merged; do not assume main contains the FX design. Favor small focused topic branches and reviewed PRs. No auto-merge or force-push.
- When returning from local Codex to GitHub, push own commits with clear scope and handoff summary; do not amend/reset somebody else's work or silently modify main.

## 3. Action authorization gates (no implicit upgrades)

A. Read-only review: inspect repository/logs/board documents, compare sources and evidence; safe without hardware changes.
B. Docs-only editing: allowed for the user's current request; no RTL, Tcl behavior, XDC, synthesis, reset, device reprogramming or host configuration changes.
C. Offline RTL/tests or local Vivado BUILD: only after user explicitly resumes and authorizes the specific development/build scope. First ensure reproducible inputs, output path, bounded resource use and no auto-programming.
D. FPGA SRAM program / VIO reset, ILA, read-only I2C/JTAG, real PCIe test: each requires an explicit current experiment authorization, hardware baseline/rollback and stop conditions. “Read-only I2C” still requires changing/connecting an FPGA image if not already loaded.
E. Si5338 register write, NVM/Flash, BIOS, PC reboot, driver install/test-signing, external RFSoC configuration, 100G high-rate transmission: require separate explicit approval for the concrete change and a tested rollback. Never do these as a side effect of a script.
F. Production/long-running streaming or bandwidth stress: require bounded explicit approval and thermal/clock/host safeguards.

If authorization is missing, deliver the BUILD-only design/plan and wait for authorization; do not simulate success. There is no inherited permission from previous iterations. Never bypass hardware safeguards, force a PLL lock bit, fabricate link state or waive CDC Critical to obtain PASS.

## 4. Engineering verification rules

Evidence levels must be stated separately:
- STATIC: inspected source, calculations or file diff only.
- SIM: Python/golden vectors and self-checking RTL simulation actually run.
- SYNTH/OOC: genuine tool report for exact source, IP version, part and constraints.
- ROUTED: fresh routed DCP timing/DRC/CDC with coverage explicitly described.
- BOARD: identified bitstream, real JTAG/VIO/ILA evidence, independent decoder/expected values.
- LINK: negotiated PCIe L0, OS enumeration, device IDs, BAR and actual hardware DMA.
- SYSTEM/SCIENCE: sustained real data stream, accounting, synchronization and measured scientific correctness.

Do not extrapolate one level to another. Distinguish OOC timing from full board timing, nominal test cycles from real sample rate, relative FPGA cycles from UTC, frozen LTSSM snapshot from live activity, brief CPLL indications from stable lock, source packet candidate from confirmed RFSoC wire format, Python file test from real DMA.

For any implementation change, before calling PASS:
- independent golden/reference vector and negative/fault test where applicable;
- AXI ready/valid stability, reset/flush/epoch and window boundary checks;
- signed arithmetic widths, saturation/round-to-even, complex conjugate sign and FFT bin order;
- source identity, frame number, valid contribution counters and loss/overrun behavior;
- original failing case retained as regression;
- compile/sim exit status AND log Error/Fatal audit; for routed builds check constraints, all routed nets, WNS/WHS, DRC and report_cdc -no_waiver;
- exact git SHA, dependency/IP config, build manifest, file hashes and test report stored outside source, sanitized summary in repo only if warranted.
A test that was not run must be “NOT RUN”; a blocked test must be “BLOCKED,” not PASS.

## 5. Architecture invariants

- Near-term processing: timestamped complex time-domain baseband -> packet/samples admission and alignment -> 512-bin 4-tap PFB + forward FFT -> complex X and fixed planned-window integration -> weighted visibility records -> PCIe DMA. F-engine relocation to RFSoC is an OPEN architectural option; do not assume upstream provides channelized data.
- Correlator convention V_ab = sum over valid shared frames of E_a * conj(E_b); self correlations real. Sixteen complex voltage streams => 16 autos + 120 unique crosses = 136 baseline products, not sixteen independent sky antennas when streams are 8 dual-pol dishes.
- Missing/late/duplicate/corrupt frames must be explicit. Keep planned time bins fixed; never silently stretch integration to reach a target sample count. Preserve W_a and W_ab (or precise equivalent), source/pol mapping, epoch/config IDs, frame and frequency IDs.
- Do not silently stop an externally clocked sampler because internal ready is low. Separate time-driven ingress, bounded frame admission and loss accounting from stallable AXI processing. No partial-frame delivery disguised as valid.
- Never discard complex voltage phase before cross multiplication; do not label FFTT/spatial-FFT results as achieved by temporal FFT alone.
- Treat CDC, GT reference clock, PERSTn and reset sequencing as first-class design contracts. Clock activity alone is not calibrated reference quality.
- Formal numeric and interface requirements live in docs/INTERFACE_CONTRACTS.md; conflicting legacy prototype semantics must be explicitly versioned.

## 6. Recommended local workflow when work is resumed

1. Choose exactly ONE eligible milestone/work package in docs/DEVELOPMENT_PLAN.md; state hypothesis, scope, inputs, outputs, artifacts, acceptance and abort criteria.
2. Work in a fresh topic branch/worktree without destroying the stopped e4 hardware baseline.
3. Implement the smallest reviewable change. For research, use STATIC first, then SIM, then SYNTH/OOC, then board only after separate approval. Do not run a long sweep without a causally testable question.
4. Use stable scripts. Examples for a resumed offline task (NOT an instruction to execute now):
       python -B -m unittest discover -s tests -v
       .\scripts\run_pipeline.ps1 -Python python -VivadoBin D:/AMDDesignTools/2026.1/Vivado/bin -BuildDir D:/work/build/KU5P_FX_Accelerator/<fresh-test> -Route
   Inspect each script first to ensure it does not automatically interact with hardware, write configuration, call GUI or reuse stale build results.
5. Review and summarize: exact file list/diffs, independent test count, numeric outputs, unresolved warning/CDC, evidence paths, rollback, and task's PASS / HOLD / FAIL. Push a focused commit/PR; never claim full acceptance on partial evidence.
6. End at next authorization boundary. Do not pre-empt the next task just because the previous task passed.

## 7. Hardware baseline / fault-recovery safety

Latest recorded state on 2026-10-29: e4 boot-recorder SRAM image, DONE=1, local reset=0, Hardware Manager closed; no PCIe L0/OS enumeration/BAR/DMA. It is a diagnostic image, NOT a proven operational endpoint. Earlier e0 after one retained-configuration host restart briefly reached Polling.Compliance with GT reset-done and a CPLL indicator; local reset subsequently failed to recover. The e4 event recorder captured transient CPLL indications but no completed TX/RX initialization. These episodes are different evidence sets; never flatten to “PLL permanently broken” or “PLL fixed.” See docs/lesson05i-pcie-boot-recorder.md and docs/pcie-restart-observation-2026-10-29.md.

Never presume SRAM state survives power cycles, nor that local GitHub reports reflect current hardware. Before a future BOARD action: verify loaded identity and current VIO outputs, backup original bit/LTX/DCP and full evidence with hashes, plan rollback, isolate controls from debug probes, document limits of the event recorder (512 entries can fill early). Si5338 registers are external state: changing FPGA bitstream does NOT restore them. No automatic register/page/NVM writes.

## 8. Session handoff template

At the end of every local Codex session, write a short GitHub-visible PR summary or docs/current-task note with:
- worktree path, branch, exact source SHA, user authorization ID/scope;
- task goal and changed files;
- direct measurements vs prior recorded observations vs hypotheses;
- test commands and actual PASS/FAIL/NOT RUN counts, timing, CDC, output location and hashed build identity;
- current board/host state, explicitly including anything NOT touched;
- unresolved P0/P1 issues and NEXT single authorized action / WAIT_FOR_AUTH;
- migration/rollback notes for another Codex instance.

Do NOT overwrite docs/CURRENT_STATE.md as if an experiment succeeded without actual new evidence. Change that file only alongside source-of-truth experiment/report updates.