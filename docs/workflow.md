# 仓库与开发流程

## 分支

- `main`：可构建、可上板的状态。
- `feat/<topic>`：功能开发，通过 PR 合入 `main`。
- `fix/<topic>`：缺陷修复。

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

需要分发大文件（bitstream、测试数据）时用 GitHub Releases，不用 Git LFS 以外的自定义方式。

## 构建约定

- 工具版本固定在 **Vivado 2026.1**；升级版本需在 PR 描述中说明原因并更新 `docs/environment.md`。
- 构建方式唯一来源是 `tcl/build.tcl`，禁止依赖手工点击生成的工程状态。
- IDE 里创建的工程只用于本地临时实验，不作为交付物。

## 主机侧软件路线

| 主机 | 可行性 | 说明 |
|---|---|---|
| Linux | 推荐 | XDMA/QDMA 官方驱动、`lspci`/`setpci`、开发调试工具齐全 |
| Windows | 可行但成本高 | 无官方 XDMA 驱动；需厂商提供或自写 KMDF 驱动（EV 证书 + 微软签名，测试期只能开 test signing） |

结论：FPGA 侧（RTL/综合/实现/ILA）全部在 Windows 完成；主机驱动与应用优先考虑 Linux 服务器，
Windows 作为客户端远程使用。

## 上板检查清单

1. BIOS：`Above 4G Decoding = Enabled`（大 BAR 必需）。
2. 板卡外接供电已接。
3. JTAG 能识别 `xcku5p_0`。
4. 下载含 PCIe 端点的 bitstream 后，主机侧才应出现 Xilinx PCIe 设备。
5. 首次联通先用寄存器回读（BAR 访问）验证链路，再上 DMA。
