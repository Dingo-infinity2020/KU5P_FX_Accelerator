# 仓库与开发流程

## 本地工作区

源码与构建产物分离，全部放在 NVMe（D 盘），不要放在 C 盘、桌面、OneDrive 或 `Documents` 下。

```
D:\work\
├─ KU5P_FX_Accelerator\                      # git 仓库，只放源码/脚本/文档
│  ├─ rtl\
│  ├─ constr\
│  ├─ tcl\
│  └─ docs\
├─ build\
│  └─ KU5P_FX_Accelerator\                   # 构建产物，不入库
│     └─ <top>_<part>\                       # 一次构建一个目录
│        ├─ project\                         # Vivado 工程
│        ├─ reports\
│        ├─ <top>_routed.dcp
│        └─ <top>.bit
└─ (旧版本/归档可另建 archive\)
```

约定：

- 仓库目录内**不产生任何构建输出**，`build_dir` 永远指向 `D:\work\build\...`。
- 路径不含空格与中文；`LongPathsEnabled` 已开启（Vivado 深层路径易超 260 字符）。
- 临时目录统一 `D:\tmp`，已加入 Defender 排除项。
- F: 移动硬盘只做归档备份，不承载工程或构建。

## 分支

- `main`：可构建、可上板的状态。
- `feat/<topic>`：功能开发，通过 PR 合入 `main`。
- `fix/<topic>`：缺陷修复。
- `codex/<topic>`：Codex 协作开发或进度快照，同样通过 PR 审阅合入。

## 提交信息

采用 Conventional Commits：

```
feat(pcie): add xdma wrapper
fix(tcl): pass part explicitly to synth_design
docs(hw): fill PCIe lane width
chore(gitignore): ignore vivado sim artifacts
```

## 入库规则

**入库**：`rtl/`、`tcl/`、`docs/`、`scripts/`、约束文件、必要的 IP 配置（`.xci`）。

**不入库**（见 `.gitignore`）：

- 构建产物：`.Xil/`、`*.dcp`、`*.bit`、`*.ltx`、`*.rpt`、`*.jou`、`*.log`、`*.str`
- Vivado 工程目录：`*.runs/`、`*.cache/`、`*.gen/`、`*.hw/`、`*.sim/`、`*.ip_user_files/`
- 许可证文件：`*.lic`（**严禁提交**）
- 本机配置、绝对路径脚本

RFSoC 原始工程、厂家资料包和原始采样/抓包留在仓库外；只同步经整理的总结与自写派生程序。本机恢复笔记 `docs/restart-checkpoint.md` 不入库；跨机器续接进度使用已发布的进度快照。文档中的本地路径是示例，构建脚本应接受显式路径参数。

需要分发大文件（bitstream、测试数据）时用 GitHub Releases，不用 Git LFS 以外的自定义方式。

## 构建约定

- 工具版本固定在 **Vivado 2026.1**；升级版本需在 PR 描述中说明原因并更新 `docs/environment.md`。
- 板级 bitstream 构建的唯一来源是 `tcl/build.tcl`，禁止依赖手工点击生成的工程状态。
- 课堂算术模块的仿真与独立综合由 `scripts/run_lesson01.ps1`、`scripts/run_lesson02.ps1` 复现；第二课还能从脚本生成 GUI 工程，供学习和本地实验。
- 第三课 `scripts/run_lesson03.ps1` 重建本机 FFT IP，运行 GUI 工程同源的完整链路仿真与可选独立综合；使用 Python/NumPy 及本地 Vivado 的 FFT 定点模型，模型和生成 IP 均留在构建目录。
- 第四课 `scripts/run_lesson04.ps1` 生成自行定义的 PFB 系数与逐位参考，冻结源码/数据哈希后运行仿真和可选独立综合；`tcl/run_lesson04.tcl` 的 prepare 模式也可在 MCP 会话中驱动相同工程，再由 `lesson04_manifest.py finish` 验证新结果。
- 第五课 `scripts/run_lesson05.ps1 -Implement` 经唯一入口 `tcl/build.tcl` 构建 `lesson05_board_top`。`lesson05_project.tcl` 提供同源的 MCP 分段启动/收集函数；`lesson05_manifest.py` 核对构建，`lesson05_hardware.tcl` 显式执行 JTAG SRAM 配置与抓取，`check_lesson05_hardware.py` 独立验证真实 CSV 和 VIO 状态。
- 05D 的 `scripts/run_lesson05d.ps1` 经同一入口构建 `lesson05d_pcie_top`；应用仿真、物理实现证明和真实硬件观察分别保存。Windows 用户态测试及其模拟端点不计为 PCIe DMA 验收。
- GUI 工程本身不入库；交付的是能重建它的源码、参考模型、脚本和说明。GUI 中的实验结果不自动替换脚本验证记录。
- 板级构建读取 `constr/`；课堂脚本显式读取各课 `constraints/lesson*_ooc.xdc`，其中只有算术模块时钟目标。

## 主机侧软件路线

| 主机 | 可行性 | 说明 |
|---|---|---|
| Windows | 当前用户选择 | 继续在现有主机开发。尚未取得与本板、XDMA 4.2 和 Windows 10 匹配的可信、可加载驱动包 |
| Linux | 备选，不自动切换 | AMD 的公开 `dma_ip_drivers/XDMA` 仓库提供 Linux 驱动；以后如用户需要可另行采用 |

FPGA、主机应用和链路检查均继续在 Windows 完成。AMD 历史上发布过 Windows XDMA 参考驱动，因此不能笼统写成“没有官方 Windows 驱动”。目前没有拿到并验证适配当前系统的驱动包；QDMA 的 Windows 驱动不能直接替代 XDMA 驱动。第五课 D 的用户态程序按常见 XDMA `user` / `c2h_0` 接口准备，真实 BAR/DMA 测试仍以取得兼容内核驱动为前提，见 [PCIe 阶段记录](lesson05d-pcie.md)。

## 上板检查清单

1. 按实际 BAR 和系统资源分配结果判断 BIOS 设置；本课小 BAR 不要求预先改变 BIOS。
2. 板卡外接供电已接。
3. JTAG 能识别 `xcku5p_0`。
4. 下载含 PCIe 端点的 bitstream 后，主机侧才应出现 Xilinx PCIe 设备。
5. 首次联通先用寄存器回读（BAR 访问）验证链路，再上 DMA。
