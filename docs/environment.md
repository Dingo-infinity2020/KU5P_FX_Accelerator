# 开发环境（已验证）

本文件记录开发机的实际状态，写于环境搭建完成并实测之后。涉及许可证主机标识的信息已做脱敏，不写入仓库。

## 主机

| 项 | 值 |
|---|---|
| OS | Windows 10 专业版 22H2 (19045)，UEFI 启动 |
| CPU | Intel Core i5-14600K（14C/20T） |
| 内存 | 32GB DDR5-5600（2×16GB） |
| GPU | NVIDIA RTX 5060 Ti（与 Vivado 无关） |
| 系统盘 | Samsung 990 PRO 1TB NVMe：C: 256GB（系统）、D: 675.2GB（工具与工程） |
| 备份盘 | F: USB 机械硬盘 1.8TB（只做归档，不承载工程） |

## Vivado

| 项 | 值 |
|---|---|
| 版本 | 2026.1 |
| 安装路径 | `D:\AMDDesignTools\2026.1\Vivado` |
| 启动 | `D:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat` |
| 安装器件族 | Kintex UltraScale+ |
| 已装组件 | Vivado（另含 PDM / Vitis 目录，未使用） |

## 许可证

| 项 | 值 |
|---|---|
| 档位 | Vivado BASIC（node-locked，single seat） |
| 有效期 | 2027-10-27（version limit 2027.10） |
| 文件位置 | `D:\Xilinx\Xilinx.lic` |
| 环境变量 | `XILINXD_LICENSE_FILE=D:\Xilinx\Xilinx.lic`（用户级） |
| 备份 | `F:\Xilinx_2026.1_BASIC.lic` |
| hostid | 已脱敏：绑定本机网卡 MAC，**不写入仓库** |

实测结论：BASIC 档**覆盖 XCKU5P**，综合/实现/bitgen 全流程通过，无需 Enterprise 试用授权。

## 环境变量与目录

| 变量 | 值 |
|---|---|
| `TMP` / `TEMP` | `D:\tmp`（用户级） |
| 工程目录 | `D:\work\<project>` |
| Windows Defender 排除 | `D:\AMDDesignTools`、`D:\work`、`D:\tmp`（避免实时扫描拖慢综合） |

## JTAG

| 项 | 值 |
|---|---|
| 下载器 | Digilent（FTDI，USB Serial Converter A/B） |
| hw_server | `localhost:3121` |
| 目标 | `xilinx_tcf/Digilent/<serial>` → 设备 `xcku5p_0` |
| 驱动 | Vivado 安装时勾选 Install Cable Drivers |

## 已验证项（可复现）

```powershell
# 器件可见性
vivado -mode batch -source <(单行提交)   # get_parts -quiet xcku5p*  -> 36 个
# 全流程（synth -> opt -> place -> route -> write_bitstream）通过
# JTAG: open_hw_target 后 get_hw_devices 得到 xcku5p_0
```

## 已知限制

- 32GB 内存对 KU5P（475K LC）足够；若后续加入大容量 DDR4 控制器 + 多路 ILA，建议加到 64GB。
- Vivado 2026.1 BASIC 的调试范围为一个 ILA、最多五个物理探针、每个最多 1024 位；第五课已将实部/虚部合并为总线以符合该范围。依据 [AMD 授权表](https://www.amd.com/en/products/software/adaptive-socs-and-fpgas/vivado/vivado-buy.html)，不能把支持 KU5P 综合/实现理解为所有调试功能均包含。
- Windows 主机目前未发现已安装的 Xilinx/MicroPhase XDMA 驱动，也未取得兼容、可加载的驱动包；继续 Windows 路线，历史 Windows 参考驱动与当前可用性需区分，见 `docs/workflow.md`。
- 卡未配置时 PCIe 不枚举，属正常现象；需先下载含 PCIe 的 bitstream。
