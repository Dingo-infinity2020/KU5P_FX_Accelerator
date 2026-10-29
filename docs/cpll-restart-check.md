# 当前 e0 的保留配置启动对照

2026-10-29。准备已完成，**本次启动对照尚未执行，由用户选择何时手动进行**。两版CPLL实板各三轮均未锁，当前恢复了哈希相同的e0、VIO本地复位0、JTAG6MHz。没有改Si5338、BIOS或Flash。

目的：检查重新插牢后的当前e0能否在主机启动期间完成初始化/枚举，并区分运行中JTAG配置与主机启动时序。它不是保证修复，也不证明本机一定门控了参考时钟。[AMD PG213系统启动说明](https://docs.amd.com/r/en-US/pg213-pcie4-ultrascale-plus/System-Bring-Up)包含JTAG配置后主机重新启动的场景。

历史上已在2026-10-28的d3做过一次配置和reset0保留的真实重启，结果阴性；当时早于重新插牢，不能当成本次e0对照，也不能把它从历史中抹去。

## 用户操作

在工程提交和独立备份确认完成后，使用Windows菜单的**“重新启动”**，保持供电。回来告诉助手“已重启”。不需要先运行重扫设备命令，也不用先重新下载FPGA。

若选择暂不重启，板卡仍停留在已记录的e0/reset0；本次启动对照继续标为未执行。

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

该过程已用 `pre_restart_dry_run` 在当前启动会话只读试跑成功；这不是重启后的证据。真正的 `after_current_host_restart` 标签尚未使用，程序拒绝覆盖已有记录。

基线与精确回退文件在 `D:/work/build/KU5P_FX_Accelerator/lesson05g_cpll_pcie_ref/restore_e0`：

- bit/LTX/routed DCP及原始verification、冻结source_snapshot。
- `ready_for_optional_restart` 状态/PHY/训练及解析，PHY当前字00002c0f0000，训练最后快照Detect.Quiet/sequence1不更新。
- Windows9034数量0、启动时间、reset1→0读回日志及最后只读确认0。

未建立有效GT条件前，不把安装Windows驱动、切换操作系统或反复重扫当作PLL修复方法。本次后续仍优先取得参考时钟/启动条件的有效对照；Si5338输出配置需先补齐电气与完整恢复条件，见[配置方案](si5338-configuration-plan.md)。
