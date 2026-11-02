# H2/H3 有限测试、XDMA.sys 蓝屏与清理（2026-10-31）

> 2026-11-02转储分析更正：匹配SYS/PDB确认崩溃进程为`xdma_rw.exe`，同步ReadFile读取user BAR offset=0x1000、length=4，而该BAR长度仅0x1000；驱动未拒绝越界，在`ReadBarToRequest+0xbc`崩溃。下文“不是命令执行瞬间、异步/空闲路径”是当时推断，现已被转储栈覆盖，不再作为事实。有限DMA结果与原始故障证据不变，禁止重装旧驱动。见[完整分析](xdma-dump-analysis-2026-11-02.md)。

## 状态

**TEST_DRIVER_REJECTED__HOST_RECOVERED__CLEANUP_VERIFIED__OFFICIAL_DRIVER_REQUIRED**

本轮使用朋友提供的 **Xilinx Answer 65444 Windows XDMA 驱动**（Win10 x64，test-signed）在 CPU 第一长槽（PCIEX16(G5)）的 e6 上完成了 **H2 user BAR 只读**和 **H3 有限已知数据 C2H/H2C**；随后主机发生 **PAGE_FAULT_IN_NONPAGED_AREA (0x50)，失败模块 `XDMA.sys`**。该测试签名驱动已判定为不安全，驱动包/服务/测试证书已删除，test signing 已关闭，主机在重启后验证稳定。

**这不是 H2/H3 的正式验收通过。** 有限 DMA 结果真实，但驱动自身崩溃，不能用于持续/后续工作；必须以 AMD/MicroPhase 的正式签名驱动重做。

## 授权与环境

- 用户明确要求“直接测试”朋友提供的 `D:\work\XDMA_win_driver`。
- 主机：ASUS PRIME Z790-P，BIOS 1812，Windows 10 22H2 x64；Secure Boot **Off**。
- 板卡：e6 `465805e6`，bit SHA256 `04c4510f11b72304a42c2bfb0db356f6bfa6aa7e74e99a8b22f181a79e62282d`，在 `PCIEX16(G5)`（CPU x16，root port A70D），Gen3 x4，`10EE:9034`。
- 驱动包：`Xilinx_Answer_65444_Windows_Files_1607104271358.zip`，SHA256 `487242CB876B16A3866007124B69F70982E6183B5FE0EEEAA865FC08FBE4060A`；Win10 Release `XDMA.sys` SHA256 `8E0F9A28F1F3BDFDC63FF06454C2F676DAEFD5F5294638F0146B9A6E44DFCEBC`；`xdma.cat` SHA256 `ECD462CE869664091D4DCD5B06D3EF77303FCFC113B4238C02FB9FECA8BBB68C`。
- 签名：`CN="WDKTestCert alexande,131577433336737167"`，自签名 WDK 测试证书，NotAfter 2027-12-14；**不是 WHQL**。`DriverVer = 01/05/2018,17.47.34.943`，KMDF 1.15。
- INF 支持 `PCI\VEN_10EE&DEV_9034`；安装为 `oem58.inf`。

## H2：user BAR 只读（测试驱动）

在 `XDMA` 设备 OK、Gen3 x4 时，用 `xdma_rw.exe` 和仓库 `scripts/xdma_windows.py` 的只读路径读取：

| 偏移 | 值 | 含义 |
|---|---|---|
| 0x00 | `0x35445846` | endpoint MAGIC |
| 0x04 | `0x1` | 版本 |
| 0x0c | `0x10` | link_up=1，busy/done=0 |
| 0x10 | `0x2` | cfg_packets 默认 |
| 0x14 | `0x1` | run_id |
| 0x18 | `0x10203040` | seed |
| 0x30 | `0x465805d1` | endpoint ID |
| 0x34 | `0x1000` | 4096 |
| control 0x00 | `0x1fc08006` | XDMA control BAR 可读 |

`xdma_info.exe` 找到 1 个 XDMA 设备，H2C/C2H channel 0 均为 streaming，接口 GUID `{74c7e4a9-6d5d-4a70-bc0d-20691dff9e9d}`。

## H3：有限已知数据 DMA（测试驱动）

### C2H（FPGA → 主机），pattern 独立校验

| 运行 | 包数 | 字节 | signature | accepted_beats | completed_packets |
|---|---|---|---|---|---|
| 1 | 2 | 8192 | `0x0556ac08` | `0x100` | 2 |
| 2 | 16 | 65536 | `0x0199dc00` | `0x800` | 16 |

- 使用 `scripts/xdma_windows.py`，run_id/seed 分别为 1/`0x10203040`、2/`0x0badc0de`；pattern 校验通过，`host_driver_readback_completed=true`。
- 这是**有限已知 pattern 回读**，不是持续吞吐测量；`elapsed_seconds` 仅记录有限传输耗时。

### H2C（主机 → FPGA），计数校验

| 写入 | beats 增量 | packet 计数 | bytes 累计 | bad_writes |
|---|---|---|---|---|
| 4 KB | 128 | 1 | 4096 | 0 |
| 64 KB | 2048（累计 `0x880`） | 2（累计） | `0x11000` | 0 |

- e6 endpoint 只计数，不做 H2C 内容回环；因此 H2C 是**计数级**验证，不是数据内容回读验证。
- `xdma_test.exe` 面向 XDMA 官方 4 KB BRAM 示例，不适用于本 e6 endpoint；未使用。

### 崩溃前链路

VIO 只读快照 `post_h3_link`（`observed_unix 1793434456`）仍显示 L0/GT 正常；随后约 8 分钟后主机在 `XDMA.sys` 崩溃。崩溃不是发生在 H2/H3 命令执行瞬间，而是驱动异步/空闲路径上的内核页错误；具体触发条件未进一步定位。

## 蓝屏与清理

- WER 事件 1001（16:23:03）：**BugCheck `0x00000050` PAGE_FAULT_IN_NONPAGED_AREA**
  - 参数：`0xffffe7818a1e3000, 0x0000000000000000, 0xfffff806859d1d40, 0x0000000000000000`
  - 失败模块：`XDMA.sys`
- 内存转储：`C:\Windows\MEMORY.DMP`，约 1,901,940,077 字节；本地保留，未上传。哈希因权限未取（可用管理员补取）。
- 清理（管理员）：
  - `pnputil /delete-driver oem58.inf /uninstall /force`：驱动包删除
  - `bcdedit /set testsigning off`：测试签名关闭
  - 从 `LocalMachine\Root` 和 `LocalMachine\TrustedPublisher` 删除 `WDKTestCert alexande…`（thumbprint `6F7C791DA2FDDF21693EE850BFE0A92B4C8B4815`）
  - `XDMA` 服务删除
- 重启后验证（16:27:25 启动）：
  - `bcdedit`：`testsigning No`
  - 无 `XDMA` 服务、无 `oem58.inf`、无 WDK 测试证书
  - 无 `10EE` 设备；无非 OK 设备
  - 无新 BSOD（WER 1001 仅 16:23 那条）；无新 WHEA（仅 14:30 GPU 槽 7A44 的旧记录）
  - 主机稳定

## FPGA 当前状态

- BSOD 后 JTAG 只读：**DONE=1，但没有 e6 VIO**；说明 e6 的 SRAM 镜像已丢失，板卡回到**未知 Flash 镜像**。
- Windows 无 `10EE` 设备；没有写 Flash、没有重新加载镜像。
- 需要等正式签名驱动到位后，再重新加载 e6、确认 L0/枚举，然后重做 H2/H3。

## 结论与禁止事项

- **H2/H3 有限功能结果有效**：e6 endpoint 的 user BAR、C2H pattern 校验、H2C 计数通路在测试驱动下确实工作。
- **测试驱动被拒绝**：`XDMA.sys` 0x50 蓝屏说明 2018 年 test-signed 驱动与当前主机/XDMA 4.2 组合不安全；不得用于持续运行、不得重装、不得作为正式验收依据。
- **H2/H3 正式状态仍为 NOT PASS / HOLD**：必须用 AMD/MicroPhase 正式签名驱动，从 e6 重新加载、L0/枚举、BAR、C2H/H2C 逐步重做。
- 测试签名、测试证书、驱动包均已清理；主机已恢复；没有把驱动/转储/证据上传到 GitHub。

## 证据位置

- H2/H3、VIO 快照、Windows 链路状态：`D:\work\build\KU5P_FX_Accelerator\h1_e6_g5_20261031_attempt1`（含 `h3_known_pattern*.bin(.json)`、`h2c_64k.bin`、`hardware/post_h3_link.tsv`、`sha256_after_incident.json`）
- 蓝屏/清理/转储元数据：`D:\work\build\KU5P_FX_Accelerator\bsod_20261031`（`incident_summary.json`、`wer_1001.json`、`memory_dmp.json`、`xdma_cleanup.log`、`post_bsod.log`、`sha256.json`）
- 驱动包与预编译工具（**仅供分析，不得重装**）：`D:\work\build\KU5P_FX_Accelerator\xdma_answer65444_20261031`
- 本地内存转储：`C:\Windows\MEMORY.DMP`
