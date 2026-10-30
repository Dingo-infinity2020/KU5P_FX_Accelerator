# Host black-screen triage — 2026-10-30

## 最终记录：内存测试与逐卡恢复

**结论：当前 4000 MT/s 内存配置通过 Windows 内存诊断和 MemTest86 四轮测试，网卡、FPGA、显卡装回后可进入 Windows；黑屏根因未确定，FPGA PCIe 尚未验收。** 本记录覆盖下面的初始排查快照，不修改旧实验历史。所有时间来自主机本地 +08:00 日志；用户报告时钟可能慢几分钟，未独立校准，不用于精确跨设备对时。

### 事故与恢复顺序

1. 用户报告约 15:00 起，显卡与 FPGA 对调位置后黑屏，最初看不到 Logo/BIOS，电源灯快闪；具体闪烁频率未记录，因此不能据此认定 DRAM 故障。最初的准确卡槽及内存条顺序未完整留存。
2. 用户移除可拆卸 PCIe 卡，使用 CPU 核显，内存从 5400 降至 4000 MT/s，并重新调整内存条。后续用户确认两条均在 A2/B2。多个变量一起变化，无法把恢复归因于降频或重插中的某一项。
3. 机器为 PRIME Z790-P / BIOS 1812、i5-14600K、两条 16 GB DDR5。Windows 内存诊断由用户在聊天前手动运行，17:27:44 写入结果：CompletionType=Pass、TestDuration=1759 秒、TestCount=12、NumBadPages=0，各测试项坏页均为 0。1101/1201 是同一次诊断的两条结果，不是两次独立测试。
4. 用户授权用 E: USB 制作 MemTest86 启动盘并恢复原内容。16 个用户文件共 57,845,088 字节先备份到 D:，逐文件 SHA-256 核对；官方镜像写入后原文件恢复，16/16 哈希一致。私人文件、目录名称与原始备份清单不入库。镜像新增的不可读分区出现格式化提示，已告知用户取消，不将它当成损坏证据。
5. 用户运行 MemTest86 V11.7 Free，报告开始时间 18:08:44、耗时 2:58:41，日志 21:07:25 明确完成 pass 4/4，累计错误 0；报告 21:08:40 保存，48/48 项通过（12 项各 4 次，包括 Hammer test）。配置为 DDR5 4000 MT/s、双通道、32-32-32-63、1.100 V；两条内存温度均 27/39/34°C（最低/最高/平均），CPU 43/81/62°C。SPD 显示两条 A-DATA 16 GB、JEDEC 5600 配置；SPD 额定档不等于此次测试速度，也不证明原 5400 配置稳定。
6. 用户在 BIOS 设置 Primary Display=CPU Graphics、iGPU Multi-Monitor=Enabled；这是用户报告，未由工具直接读回 BIOS。显示器保留主板视频输出。
7. 用户按顺序装入 ConnectX-5（最上方 CPU 直连槽）、FPGA（第二长槽，接 USB/JTAG）、RTX 5060 Ti（第三长槽）。插槽位置和正常断电由用户确认，未拍照独立验证。Windows 只读检查依次完成，最终三卡安装状态可启动，内存仍为 32 GB / 4000 MT/s。

### 最终直接测量（主机时间 21:35:35，本次 Windows 启动 21:33:06）

| 项目 | 直接结果 | 验收边界 |
|---|---|---|
| RTX 5060 Ti | Status OK、错误码 0，驱动 32.0.15.8157，当前 PCIe 速率码 4 / 宽度 4（Gen4 x4） | 仅枚举与驱动；未跑游戏/压力测试，不能宣称性能无损 |
| UHD 770 | Status OK、错误码 0 | 核显仍可用 |
| ConnectX-5 | 两个功能/网络接口均 OK，签名驱动 1.90.19240.0；当前/最大速率码 3、宽度 16（Gen3 x16） | 可确认主机 PCIe 正常枚举；两个网络端口 Disconnected，未验收 100G 网络链路或吞吐 |
| FPGA USB | FTDI A/B 与 COM8 均 OK | 仅 USB 桥枚举，不等于 JTAG 扫链或 FPGA 身份确认 |
| FPGA PCIe | PresentOnly 未见 VEN_10EE | 当前 SRAM 镜像、DONE、GT、LTSSM 未读取；不能归责第二槽，也不能宣称 FPGA 链路通过 |
| Windows 硬件错误 | 最终本次启动到检查时 WHEA 事件 0，在场设备无非 OK 状态 | 短时间观察，不等于长期稳定性 |

早期 Kernel-Power 41（BugcheckCode=0）、快速启动失败和三条 WHEA ID 3 保留在下方快照。WHEA 为厂商特定 CPER，未得到具体部件定位；不能把这些事件直接写成电源、内存或 FPGA 损坏。

### 开发影响、边界与下一步

- 主机当前配置下未复现黑屏，内存两项测试 PASS；最初黑屏根因保持 OPEN。降频、重插、显示选择及插卡顺序均有变化，没有单变量故障复现实验。
- 下午用户完全断电拆卡，早上的 e4 保留 SRAM 现场不再被视为当前状态。早上 epoch2/512 事件和相应哈希仍是有效历史证据，不得覆盖；新板上镜像身份 UNKNOWN，不能假定已保留或已恢复 e4。Si5338 外部配置也未由本轮读取或修改。
- 当前有主机侧正常枚举的 ConnectX-5，可作为以后经授权的主机 PCIe 对照候选；它不能证明 FPGA 的参考时钟、引脚、复位或链路正常。
- 本次由用户手动执行断电、插卡、BIOS 设置与 MemTest86。助手执行只读 Windows 查询、授权的 USB 制作准备/文件恢复与文档整理；imageUSB 写入由用户手动完成。助手未打开 Vivado、扫 JTAG、program/reset/arm/ILA、写 Si5338/Flash、安装驱动或自行重启。
- SIM / SYNTH / ROUTED / FPGA BOARD / BAR / DMA / 100G traffic / GPU load：本次均 NOT RUN；无新增 FPGA 时序、CDC 或科学正确性结论。H1/H2/H3 未因此升级为 PASS。
- 下一项实现或硬件实验 WAIT_FOR_AUTH；如恢复 FPGA 工作，先明确授权范围并重新确认当前镜像/硬件基线，不能直接沿用早上“保留 e4”的前提。主机先保留 4000 MT/s 与当前位置，恢复 5400 必须另作独立验证。

### 证据与本次文档交接

- 原始 MemTest86 HTML/log 保留在 USB，并复制到 `D:/work/build/KU5P_FX_Accelerator/host_recovery_20261030/`；含设备标识，不上传。原用户文件备份留在 `D:/tmp/memtest86-e-backup-20261030/`，不上传。
- 本地归档 SHA-256：HTML `2F2E3D5EFDBBFE7478E8A72FD7BB25BBB4960A63D6BFD6E504153B20831A4ACD`；log `845BF4EAB59F6ECF9A5884D96C7E23C956094B3559A39733060EEA3540CB24C9`。这是用户已运行测试的证据身份，不是新FPGA构建身份。
- 进入源 SHA：`2ef1d5be06ce4461c80415a812d8bf537b3dcea7`；工作树 `D:/work/KU5P_FX_Accelerator`；提交分支 `codex/host-recovery-history-2026-10-30`。当前用户明确授权“写入开发历史并同步 GitHub”，本次变更限文档。
- 变更范围：本记录、README 当前入口、CURRENT_STATE 最新覆盖段。文档静态校验与暂存敏感信息检查在提交前执行；不为文档修改重跑 RTL 测试。回退只需撤销本次文档提交，不代表硬件或 BIOS 回退；main 不修改、不合并。

## 初始只读排查快照（恢复前历史）

- Worktree: `D:\work\KU5P_FX_Accelerator`; branch `codex/e4-restart-observation-2026-10-30`; inspected HEAD `2ef1d5be06ce4461c80415a812d8bf537b3dcea7`. Initial tree clean, origin fetched without checkout/merge.
- Authorization: current chat request to investigate black screen after exchanging GPU/accelerator slots. Scope used: read-only Windows inventory/event inspection and this handoff note. No implementation or board experiment resumed.
- User reports all removable PCIe cards removed, memory frequency lowered and DIMMs rearranged; original DIMM order uncertain. Physical slot population and failure-stage indicator remain unconfirmed.
- Direct Windows inventory: ASUS PRIME Z790-P, BIOS 1812 (2025-01-21), i5-14600K, Intel UHD Graphics 770; two 16 GB DIMMs, configured 4000 MT/s. SMBIOS locators Controller0-DIMM1 / Controller1-DIMM1 do not independently verify physical A2/B2 placement. Current present-device query returned no non-OK devices.
- Current Windows boot: 2026-10-30 17:27:38 local +08:00. Existing MemoryDiagnostics-Results 1101/1201 at 17:27:44 reports no memory errors. This agent did not start that test; its exact options and coverage are unknown. It does not establish stability at the former frequency.
- Prior Kernel-Power 41 records today: 15:44, 15:54, 15:58, 16:12, 16:53; BugcheckCode zero. These document unclean shutdowns, not a proven PSU or component failure. Kernel-Boot 29 includes fast-startup failure 0xC00000D4.
- WHEA-Logger ID 3 at 15:58:25, 16:16:15, 16:53:45 contains 316-byte vendor-specific CPER data. No component-level root cause established. No WHEA event found after the current boot in the inspected System-log window.
- Hypotheses remain: memory seating/training/configuration, GPU display/initialization or seating/power, accelerator/slot interaction. Multiple simultaneous user changes prevent causal attribution.
- Earlier retained-e4 board observations remain historical. Removed-card SRAM identity/state is UNKNOWN; do not assume preserved e4 configuration after power removal.
- New stress/memory tests, Vivado, FPGA programming/JTAG/VIO, BIOS/driver/power changes and reboot: NOT RUN. No build/timing/CDC claim. No existing evidence overwritten; no hardware/host configuration changed.
- Next: obtain black-screen stage (logo/BIOS versus Windows), original/new card slots, display-cable location, DIMM slots and former frequency. Keep current configuration as the comparison baseline. Any subsequent physical/BIOS/reboot experiment needs a concrete current scope; WAIT_FOR_AUTH for those actions.
- Rollback: documentation-only addition; no hardware rollback required. Repository note intentionally contains no machine serials or raw event dump. Not pushed in this session.
