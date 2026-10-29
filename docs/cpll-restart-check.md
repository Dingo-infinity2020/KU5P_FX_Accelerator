# 当前 e0 的保留配置启动对照

2026-10-29，**本次启动对照已完成**：保留 e0/reset0，首次只读观察到 CPLL mask0001、四路 TX/RX 初始化完成，实时训练到达 Polling.Compliance，但未枚举；随后一次局部复位后初始化未恢复。见[本次实测与最终状态](pcie-restart-observation-2026-10-29.md)。以下操作步骤保留作实验方案，不代表仍等待用户重启，也不要原标签重跑。

目的：检查重新插牢后的当前e0能否在主机启动期间完成初始化/枚举，并区分运行中JTAG配置与主机启动时序。它不是保证修复，也不证明本机一定门控了参考时钟。[AMD PG213系统启动说明](https://docs.amd.com/r/en-US/pg213-pcie4-ultrascale-plus/System-Bring-Up)包含JTAG配置后主机重新启动的场景。

历史上已在2026-10-28的d3做过一次配置和reset0保留的真实重启，结果阴性；当时早于重新插牢，不能当成本次e0对照，也不能把它从历史中抹去。

## 用户操作

在工程提交和独立备份确认完成后，使用Windows菜单的**“重新启动”**，保持供电。回来告诉助手“已重启”。不需要先运行重扫设备命令，也不用先重新下载FPGA。

该步骤本次已经完成，Windows 启动时间读回为 2026-10-29 18:45:52.5（UTC+8）。

## 助手返回后的先读规则

1. 先记录Windows启动时间与PresentOnly枚举；不把内核启动时间单独当作所有硬件上电次数的证据。
2. 如果Vivado MCP进程已结束，只恢复会话/Hardware Manager，先观察DONE。关联已验证LTX只是恢复探针描述，不是重新program。
3. source下方Tcl仅定义过程，显式调用后记录DONE、实际固件身份及VIO复位输出；**不program、不commit VIO、不先写复位**。
4. 若DONE低、身份不是e0、reset不是0或调试核无法匹配，记录实际情况并停止“保留配置”的判断，不自动修复。
5. 若e0/reset0确实保留，再读取6次状态、12次PHY与12次训练快照，比较此前基线、检查快照序号活性和Windows枚举。PLL/链路失败仍如实记阴性；BAR/DMA是后续独立验收。

```tcl
source -notrace {D:/work/KU5P_FX_Accelerator/tcl/read_cpll_restart_retention.tcl}
lesson05gh_read_restart_retention {D:/work/build/KU5P_FX_Accelerator/lesson05g_cpll_pcie_ref/restore_e0} after_current_host_restart
```

该过程此前用 `pre_restart_dry_run` 在重启前会话只读试跑成功；它不是重启后证据。真正的 `after_current_host_restart` 标签本次已经使用，保留记录确认 DONE1/e0/reset0；程序拒绝覆盖已有记录。

基线与精确回退文件在 `D:/work/build/KU5P_FX_Accelerator/lesson05g_cpll_pcie_ref/restore_e0`：

- bit/LTX/routed DCP及原始verification、冻结source_snapshot。
- `ready_for_optional_restart` 状态/PHY/训练及解析，PHY当前字00002c0f0000，训练最后快照Detect.Quiet/sequence1不更新。
- Windows9034数量0、启动时间、reset1→0读回日志及最后只读确认0。

未建立有效GT条件前，不把安装Windows驱动、切换操作系统或反复重扫当作PLL修复方法。本次后续仍优先取得参考时钟/启动条件的有效对照；Si5338输出配置需先补齐电气与完整恢复条件，见[配置方案](si5338-configuration-plan.md)。
