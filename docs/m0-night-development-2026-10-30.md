# 2026-10-30 夜间接手：M0 回归与 e4 保留现场

本次从北京时间 00:15 开始。用户明确授权继续开发、仿真、构建和有依据的可恢复 SRAM 验证，至必须重启或人工操作时停止。该新授权覆盖文档中旧的 documentation-only / HOLD；不包含自动重启、驱动/BIOS/Flash/Si5338 写入。原 RFSoC 工程继续留在本机。

**本次已完成 M0，H1 停在 WAIT_FOR_HOST_RESTART。** 本轮没有改变计算 RTL 或 FPGA 配置，没有复位、arm、触发 ILA 或提交 VIO 输出。没有重新综合/布线；本轮 SIM、历史 ROUTED 文件复核和当前只读 BOARD 观察分别记账。详见[机器可读摘要](validation/m0-night-2026-10-30.json)。

## 接手与 M0 执行

- 工作树 `D:/work/KU5P_FX_Accelerator`，进入时干净，HEAD `b89a5c4`；远端开发分支已新增治理文档提交 `ddf306ec7ae3828a19a594b728f828f16f5bcb77`。先 fetch，再 fast-forward，无 reset/clean。
- 完整阅读 AGENTS.md、CURRENT_STATE、DEVELOPMENT_PLAN、INTERFACE_CONTRACTS、REVIEW_BACKLOG，并核对 workflow、hardware、roadmap、05A/05C/05I 及 e0 重启记录。文档中的旧暂停要求与本次新授权已明确区分。
- 创建专题分支 `codex/m0-nightly-baseline-2026-10-30`，基于 `ddf306e`，不直接改 main，不把原 Draft PR #1 的全部设计混入新 PR。
- 新增 `scripts/run_baseline_regression.py`：冻结 235 项源码/约束/脚本/文档的 SHA256 和副本，记录源提交、工作树、Python/NumPy/Vivado、命令、时限、退出码、嵌套日志哈希和 PASS/FAIL/SKIP；只调用离线脚本，不连接硬件。
- 每次使用新外部目录；拒绝复用旧目录。每个任务有 30–900 秒时限，失败即停并保留记录。模拟器即使退出 0 或留下 PASS，也必须通过 Error/Fatal 审计和精确的检查数校验。
- 本次已审阅的离线入口：`run_pipeline.ps1`、`run_fft_elastic_test.ps1`、`run_pcie_boot_test.ps1`、`run_pcie_training_monitor_test.ps1`、`run_pcie_application_test.ps1` 及相关 Tcl/参考模型。不调用包含板级构建和 program/reset 的入口。

可重跑本次范围（必须换一个尚不存在的目录）：

```powershell
& <Python> -B scripts/run_baseline_regression.py `
  --output-dir D:/work/build/KU5P_FX_Accelerator/<fresh-m0-run> `
  --vivado-bin D:/AMDDesignTools/2026.1/Vivado/bin `
  --history-root D:/work/build/KU5P_FX_Accelerator --hdl
```

Python 需 NumPy，本机为 2.3.5。FFT C 模型由当前 Vivado 安装中的原始压缩包提取到外部目录，压缩包及 DLL 哈希留在向量证明中；没有复制 vendor IP 入库。`--hdl` 仅运行现有自检查仿真，省略时明确记录 HDL SKIP。

## 新跑的验证，不是旧 PASS 复用

正式通过目录：`D:/work/build/KU5P_FX_Accelerator/m0_20261030_attempt3`，冻结源提交 `fb7a0d90c472a60578a4bcc4974d1fb31b37138f`，执行前后源清单相同；后续提交仅保全历史源码和更新本轮文档。

| 本次实际执行 | 结果与范围 |
|---|---|
| Python unittest | 72 PASS / 0 FAIL / 0 SKIP；包括原 62 项和 10 项回归入口反例 |
| e4 诊断单元仿真 | 14 项 PASS；包括物理复位、停钟、记录溢出等；不是实际 GT 模型 |
| 训练监测仿真 | 9 项 PASS；不证明物理 PCIe 训练 |
| PCIe 应用仿真 | 29 包、3712 beat，AXI-Lite/AXI Stream 自检查 PASS；不证明 DMA |
| FFT 弹性配对 | 4096 对；1116 拍独立 pending、2985 次替换、1329 拍输出等待 |
| 真实 AMD FFT + 两路 PFB-FX 仿真 | 10 场景、226 帧、90 窗口；115712 对 PFB/FFT 样本、46080 行完整结果逐位一致；8 类协议故障通过 |
| 128 帧有限吞吐场景 | 每路 65536 样本，输入 65921 拍，排空共 67085 拍；名义 125MHz 折算约 122.114 MS/s/路，不是实板持续速率 |
| 运行日志审计 | 包括嵌套 xsim/Vivado 日志，未检出 Error/Fatal；完整 FX 任务约 508 秒 |
| 新综合 / 新 ROUTED / 新位流 | NOT RUN；当前没有需要重新构建的 RTL 改动 |

前两次回归入口调试失败保留：attempt1 在 `vivado -version` 的 Windows 信息型退出码 1 处 HOLD；仅对精确版本探测允许该行为，仿真和构建仍要求退出 0。attempt2 因入口漏生成应用测试向量而失败，产生的 Error/Fatal 已如实记录；修正入口先生成 `cases.txt`/`expected.mem` 后，使用全新 attempt3 全部重跑通过。未修改原应用 RTL 来绕过失败。

这些既有测试通过不关闭 R-004..R-007 的全部专项审计，也不证明 F1 整帧准入、持续真实输入或 16 路已经完成。

## 历史证据与依赖

05A、05C、05I 原证明及共 8 个 bit/LTX/DCP 文件重新计算哈希，全部匹配；e0 精确回退的 bit/LTX/DCP 也匹配。e4 的 WNS +1.174ns、CDC Critical 0 是历史实现证明，本次没有重新测得这些数值。

复核实际生成配置：FFT 9.1，512 点、16 位输入、24 位相位、流水/不缩放/收敛舍入/自然序；本轮新生成的 FFT 数学参数与历史一致。XDMA 4.2 为 Gen3×4 能力、256 位/125MHz、100MHz 参考、quad225、lane reversal、外部时钟缓冲。CMAC 未构建或验收。目标 `xcku5p-ffvb676-1-i` 来自现有厂家依据，实物完整丝印仍未读取。

历史 05A 的 `tcl/build.tcl` 哈希与现行脚本不同，按可达提交仍找不到原字节。通过只读 Git 对象检索找回未被分支引用的 blob `d6eca1e531723d7ae83e1dedd230e0ffb5a6aa71`，SHA256 恰为原证明要求的 `be3321abb98191cfc39e8c281a37bd7b997b19c274b7d9a447b1d36846efcaf6`。现将其自写源码保存为 [归档脚本](validation/source_archive/lesson05a-build.tcl)，避免垃圾回收后丢失；不是新的构建入口，不可直接在归档路径执行。归档保留原字节及当时的注释，重建旧环境须还原到原相对路径并搭配该证明的其余源码。

三份历史证明列出的所有输入源码均已找到当前或 Git 中的匹配字节；差异与定位记录在本地 `h1_20261030_retention/reconciliation.json`。原始证明、失败历史和抓取没有覆盖。

## H1 静态复核与当前 BOARD 观察

只读重开已保存的 e4 routed DCP，核对器件/primitive 位置、参考输入、PLL 参数、时钟选择与控制驱动及端点复位桥，保存 `static_netlist.tsv`；没有 synth、route 或 ECO。参考输入位置仍为 COMMON_X0Y0，四路 GT 位于 X0Y4..7，COMMON 位于 X0Y1，复位来源是已记录的两级 FDCE 桥。这个检查不能证明模拟参考频率、抖动或 PLL 校准。

00:19 首次及 00:29 最终只读观察均确认：

- DONE=1、身份 `465805e4`，本地复位=0、arm=0、RAM 地址=1ff，epoch=1、entries=512。
- 当前地址读出的最后一个事件与原 511 号事件字节相同；没有重新读写记录段、重新 arm 或提交地址。
- raw 为 `a0000f000f00000f`：PG 四路高、SYS MMCM 已锁，最终 CPLL/QPLL 和 TX/RX 初始化仍不成立；AXI÷8 计数仍为 9，训练快照未近期更新，不能当实时训练进展。
- 本次 Windows PresentOnly 10EE:9034 为 0；LastBootUpTime 仍为 2026-10-29 18:45:52.5+08:00。
- 参考窗口门槛仍不成立，不推导物理频率或主板门控；QPLL reset/PD 仍未知。原事件里的短暂 CPLL 高与此次终态分开保存。

本轮初始/最终读数及当前现场在 `D:/work/build/KU5P_FX_Accelerator/h1_20261030_retention`。Hardware Manager 已关闭，没有构建、仿真或抓取运行。Si5338、Flash、BIOS、驱动均未触碰。

## 下一步与人工操作边界

**需要用户手动进行一次 Windows“重新启动”，保持板卡外接电源和 JTAG 连接，不要先关机断电、重下位流或切换 VIO 复位。** 这是首次 e4 保留配置的主机启动对照；此前 e0 已做过的重启不冒充 e4 的结果，也不再重复没有新记录的局部复位。

返回后先记录 Windows 启动时间与 PresentOnly 设备；使用正确 e4 LTX，先只读 DONE、身份、全部真实 VIO 输出、epoch 和记录条数。严禁先 program/reset/arm。若 DONE 或身份改变，记录丢失/不同基线并停止，不能自动修复现场。

验收与分支：

1. **记录有效**：e4/reset0 保留；若检测到 PERSTn 下降，epoch 应更新。若仍为 epoch1，不能把旧记录称为新启动记录。按实际条数分批读事件，地址提交前必须刷新全部真实输出并确认 reset/arm 未变。记录满及漏事件须报告，512 条不保证覆盖完整启动。
2. **PHY 改善但链路失败**：若必要初始化完成且有新鲜训练，继续区分 Polling.Compliance/训练与 L0；不以短暂 CPLL 指示宣告通过。仍无 L0 时不进入驱动安装。
3. **链路通过**：只有实时 L0 与 OS 枚举均成立才进入 H2，随后才讨论 BAR/驱动/DMA；不跳过层级。
4. **没有改善或证据不足**：保存新启动记录，停止重复本地复位/无区分力的 GT 改动；需要厂商已验证工程、独立参考测量或另一台合适主机作为正对照。Si5338 仍受完整频率表、电气与恢复门槛约束。

本次任务停在上述人工重启节点，不自动执行重启，不继续排队硬件实验。一次性定时跟进完成后删除；后续从本报告及 CURRENT_STATE 续接。
