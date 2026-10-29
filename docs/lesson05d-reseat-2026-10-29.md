# 重新插牢后的同位流对照（2026-10-29）

用户报告发现 PCIe 卡先前没有插好，现已重新插好并启动，确认 FPGA 仍在显卡下方原来的长槽。本轮检查没有移动插槽或修改 FPGA 功能设计。

## 初始状态与恢复

首次 JTAG 检查显示 KU5P 的 DONE=1，但未识别到 VIO/ILA，探针文件为空。只能确定当时没有识别到 dd 诊断核，不能认定保留了旧 SRAM 位流，也没有将该配置猜测为某个厂家版本。

随后以 6 MHz JTAG 下载**完全相同**的 dd Gen3×4 位流，校验 bit/LTX/DCP 哈希和归档源字节后复制到独立目录 `D:/work/build/KU5P_FX_Accelerator/lesson05d_pcie_reseat_20261029_1003`。没有重新综合、修改参考时钟选路、写 Flash 或安装驱动。恢复后读到身份 `465805dd`，本地复位保持 1 后释放并读回 0。

bit SHA-256：`a0d8ac037e052b5068a022fbbcb9f57855b51b2104552131bd84b6158e18f19d`，与前一天 dd 相同。原始 dd 目录及其历史文件保持不变。

## 实测结果

| 检查 | 重新插牢后的读数 |
|---|---|
| VIO 状态字 | 6 次均为 `f0`；bit7 在本版本是心跳，不能解释为 AXI 活动 |
| PHY 当前字 | 12 次均为 `0000240f0000` |
| GTYE4_CHANNEL_X0Y4..7 原始 GTPOWERGOOD | 全部为 1 |
| CPLL / QPLL1 lock | 0 / 0 |
| TX / RX reset-done | 均为 0 |
| PHY rrst_n / prst_n / rst_idle | 1 / 0 / 0 |
| 训练历史 | 只有 Detect.Quiet，跳转 0；快照序号为 1，不能声称持续更新 |
| 两次 ILA 同域校验 | 均通过，心跳上升沿间隔严格 256 点 |
| 两次参考计数上升沿间隔 | A：245–847 点；B：615–1194 点；不满足稳定周期筛选，不报告单一频率 |
| Windows `10EE:9034` | 下载前与释放后均为 0 个端点 |

因此，**目前没有测到“重新插牢后 PLL/PHY 已恢复”**。这不否认用户发现的插接问题，只表示该操作尚未使当前诊断位流完成初始化。采集结果也不能直接证明主板差分时钟频率、模拟供电质量或板卡故障。

本轮通过既有解析器核验源归档、位流/LTX/DCP 哈希、身份、复位日志、6 个状态样本、12 个 PHY/训练样本及两次 4096 点采集；硬件对照无需重跑没有改动的数学 RTL 测试。

## 启动方式与下一项对照

系统日志记录：2026-10-29 09:55:34 的 Kernel-Boot Event 27 中 `BootType=1`；Win32_OperatingSystem 的 LastBootUpTime 和最近 Kernel-General Event 12 仍为 2026-10-28 18:38:06 左右。结合这些字段，本次启动符合快速启动恢复的表现，不能只因 LastBootUpTime 未变就断言用户没有重新开机。

[Microsoft 的说明](https://learn.microsoft.com/en-us/troubleshoot/windows-client/setup-upgrade-and-drivers/fast-startup-causes-system-hibernation-shutdown-fail) 指出，快速启动会保存内核/驱动会话，而选择 Windows“重新启动”会执行完整启动流程。本轮不修改快速启动设置。

下一项条件已准备好：dd 位流已加载、本地复位为 0。由用户在 Windows 开始菜单选择**重新启动**，保持主机电源与板卡连接，不关机断电、不再移卡，测试启动枚举时已有这份诊断位流的情况。SRAM 是否保留需在回来后实际读验，不能保证每种主板重启过程都保持插槽供电。

回来后先记录新的启动日志、Windows 枚举、DONE、调试核和身份；**先不重新下载或操作复位**。如果 dd 保留，直接读取 PLL/PHY/训练及校验波形；如未保留，先如实记录，再决定恢复动作。这项完整重启对照尚未实施，不能写成已通过。

当前工具进程没有管理员权限，未运行 PnP 扫描、根端口复位或关机/重启命令。系统重启由用户自行执行。

可公开结果见[同位流对照证据](validation/lesson05d-reseat-2026-10-29.json)；完整历史见[PLL/时钟排查](lesson05d-pll-clock.md)。RFSoC 原工程、生成 IP、位流及原始本机日志继续不入 Git。
