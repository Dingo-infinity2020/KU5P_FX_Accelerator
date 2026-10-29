# 第五课 D：片内已知数据与 Windows PCIe 准备

2026-10-28。当前阶段先建立独立 PCIe 测试端点，之后再接 FX 结果。RFSoC、ConnectX-5 和光链路都不是此阶段的前置条件。当前端点发送自行生成的已知数据；尚未集成 PFB/FFT/X、DDR 或 Ethernet。

最新进展：用户已成功完成管理员重扫描，原 d1 固件仍未建立链路或枚举。下文保留 d1 的实现与首次观察记录；后续 d2 时钟监测及排查见 [重扫描后的诊断记录](lesson05d-pcie-diagnosis.md)。

## 实现范围

`lesson05d_pcie_top` 使用 XDMA 4.2，Gen3×8 能力、启用 lane reversal、256 位/250 MHz AXI Stream、各一个 H2C/C2H 通道。AXI-Lite 用户 BAR 为 4 KiB，DMA 控制 BAR 为 64 KiB；实际 BAR 和协商速率/宽度以主机读回为准。默认 PCI ID 为 `10EE:9038`。当前固件上电后保持测试源空闲，只有用户 BAR 的显式启动写才开始生成数据。

PCIe 引脚按厂家原理图和引脚表核对：参考时钟 AB7/AB6，PERSTn=T19，经电平转换后为 BANK65 的 1.2 V 信号。板上 PCIe lane 排列反向，配置已启用 lane reversal；最终实现额外逐一检查全部 38 个顶层端口的封装引脚。板载 100 MHz 时钟驱动独立只读 VIO，便于 PCIe 未建立时仍观察状态。VIO 的跨时钟输入均为独立诊断位，经两级寄存器同步。

## 应用层协议

每包 4096 字节，共 128 个 256 位 beat；所有 `tkeep` 位有效，最后一拍 `tlast=1`。每次运行可指定 1～4096 包。数据采用小端 32 位字，包头依次为：

| 字索引 | 内容 |
|---|---|
| 0 | `0x35445846`，字节为 `FXD5` |
| 1 | 版本 1 |
| 2 | run_id |
| 3 | 从零开始的包序号 |
| 4 | 本次包数 |
| 5 | 包长 4096 |
| 6 | seed |
| 7 | 保留，零 |

包内字索引 `w=8..1023` 的值为 `(seed + packet_index*1024 + w) mod 2^32`。完整字节内容、包序号和计数分别核对。32 位滚动 signature 仅作诊断，不能代替逐字节比较。

AXI-Lite 地址如下，访问均为对齐的 32 位读写；配置写支持 WSTRB，写只读/未知地址和非法控制返回 SLVERR。

| 偏移 | 含义 |
|---|---|
| 00 / 04 | magic / 版本，只读 |
| 08 | 控制：bit0 启动，bit1 清除 done；忙时拒绝控制写 |
| 0C | 状态：bit0 busy，bit1 done，bit4 link_up |
| 10 / 14 / 18 | 配置包数 / run_id / seed，启动时快照 |
| 1C / 20 / 24 | 已接受 beat 数 / 已完成包数 / signature |
| 28 / 2C | H2C 接受 beat 数 / 包数；H2C 当前只计数并丢弃 |
| 30 / 34 | build_id=`0x465805d1` / 固定包长 4096 |
| 38 / 3C | 非法写次数 / H2C 有效字节数 |

## 已有验证及边界

应用单元仿真独立于 PCIe IP：29 包、3712 beat、118784 字节全部匹配 Python 参考，1114 次阻塞，最大连续接受 1024 beat；覆盖 AW/W 独立先后到达、B/R/Stream 阻塞稳定、WSTRB、配置快照、非法访问、未完成 AW 与包中途复位，以及 H2C keep 字节计数。它没有模拟 PCIe Root Port，不能算作主机 DMA 验收。

`tests/test_xdma_windows.py` 的四项测试覆盖字节契约、模拟端点短读和身份/忙状态保护，还在普通临时文件上实测了 Windows OVERLAPPED I/O 与页对齐分配。这些测试证明用户态代码的相应行为，不能算作 PCIe 驱动或 FPGA DMA 已通过。

板级实现使用 19531 LUT、25116 FF、46 BRAM36 等效块、0 DSP、8 个 GTYE4_CHANNEL 和 1 个 PCIE40E4。实际 `axi_clk` 约束为 4 ns；布线后 WNS=+0.527 ns、WHS=+0.010 ns、WPWS=0，内部未约束端点和无时钟端点均为零。42995 个可布线网络全部完成，路由错误为零；38 个端口引脚审计全部通过，四项 bus skew 约束均通过。

实现日志无 critical warning，DRC 仍有 26 项 warning：3 项调试核 LUT equation、22 项 PCIe IP BRAM collision advisory、1 项调试网无可路由负载。CDC 报告有 148 项 CDC-15 warning，其中 144 项位于生成的 XDMA GT 校准逻辑、4 项位于 dbg_hub，均带 IP 的 false-path 约束；六个自行编写的监测跨域路径均识别为两级 ASYNC_REG 同步。这里保留告警与范围，不把报告写成零告警。缺输入延迟的 1 项是异步 PERSTn，缺输出延迟的 2 项是 LED，均有明确 false path；未虚构板外同步时序来消除提示。

2026-10-28 15:22 左右，已将该位流经 JTAG 下载到真实 KU5P 的 SRAM，DONE 高、一个只读 VIO 可见，重组出的 build_id 为 `465805d1`。六次状态采样均为 `0x10`：PERSTn 高，link_up=0、AXI reset 未释放，未观察到 AXI heartbeat。Windows 三次只读检查均未枚举到 `10EE:9038`。主机设备重扫描命令实际尝试了一次，但返回 Access is denied，因此**没有完成管理员重扫描**。该状态尚不能区分参考时钟/根端口状态、训练或其他板级原因；不能只归因于缺少 DMA 驱动，也没有读回实际协商代数/宽度。

独立证据保存在仓库外的 `lesson05d_pcie/verification.json`、`hardware_verification.json`、`baseline_and_cdc_audit.json` 和 `reports/`。构建证明与硬件观察分开记录；真实 BAR 和 DMA 均未测试。

| 产物 | SHA-256 |
|---|---|
| bit | `5ae1c0139ed9eff848ce69b63228a5fb5d5983f43ca07017384998211b93ef5e` |
| LTX | `c73fee6db89720fdd40f744cea60868ef1d91e181c206df83a9b48301dff1578` |
| routed DCP | `84e78b78cd3eddb10f433a7a3b14dfb251e07c0315efb4a96d8ea452bb57af71` |

第四课和 05C 的所有验证源哈希保持一致；05A 只有公共入口 `tcl/build.tcl` 因增加新 top 分支而变化，旧入口已另存并匹配原证明，其余 17 项源及原 bit/LTX 未变。旧硬件抓取仍是历史有效证据；不能声称当前公共入口与旧证明完全同一哈希。当前 SRAM 已由 05A 换为 PCIe 测试设计，Flash 未写入。

## Windows 驱动结论

用户已确认继续 Windows，厂家暂未提供额外资料或驱动包。本机未发现已安装的 Xilinx/MicroPhase XDMA 驱动。

- [AMD 的公开 DMA 驱动仓库](https://github.com/Xilinx/dma_ip_drivers/tree/master/XDMA) 的 XDMA 目录提供 Linux 实现；QDMA Windows 实现对应不同 IP。
- AMD 历史支持帖讨论过 Windows XDMA 参考驱动与 2018.2 版本，见 [Win10 XDMA performance](https://adaptivesupport.amd.com/s/question/0D52E00006hpk8VSAQ/win10-xdma-performance?language=en_US)。这不证明该旧包已经适配当前 Windows 和 XDMA 版本。
- [AR 65444](https://adaptivesupport.amd.com/s/article/65444?language=en_US) 是后续查找入口；本次页面只返回 Loading/CSS Error，未取得其中的驱动附件。

因此不能写“Windows 从未有官方 XDMA 驱动”，也不能把互联网上的第三方镜像当作已验证的配套签名驱动。当前可完成 FPGA、物理链路和用户态准备，真实 BAR 与 DMA 验收仍等待兼容内核驱动。未安装第三方内核包、开启测试签名、修改安全启动/BIOS，未切换 Linux。

## 复现入口

```powershell
$py = 'python'
$bin = 'D:\AMDDesignTools\2026.1\Vivado\bin'
$out = 'D:\work\build\KU5P_FX_Accelerator\lesson05d_pcie'
# 应用仿真、冻结输入、唯一板级入口构建和报告校验；不自动上板
.\scripts\run_lesson05d.ps1 -Python $py -VivadoBin $bin -BuildDir $out
# 只读 Windows PCI 枚举与驱动检查；不安装驱动
.\scripts\inspect_pcie_windows.ps1 -Report "$out\windows_inventory.json"
# 用户态测试，不访问实际设备
& $py -B -m unittest discover -s tests -p test_xdma_windows.py -v
```

取得兼容驱动并确认其节点协议后，`scripts/xdma_windows.py` 需要显式提供 Windows 设备接口基础路径和仓库外输出文件。它先验证四个身份寄存器及 link/busy，再写启动命令，逐包读回并比较完整内容。暂不猜测设备接口 GUID 或自动对未知设备写寄存器。

硬件动作在 `tcl/lesson05d_hardware.tcl` 中显式调用；只使用 JTAG SRAM，不写 Flash。VIO 的常量端口会被拆成多个具名 net，脚本按实际 `PROBE_PORT/BITS/COUNT` 重组并核对完整身份，不能假定硬件探针名等于 `probe_in0/1`。

以下管理员重扫描步骤已由用户完成；后续 JTAG 和 Windows 检查仍未发现链路或端点，已转入独立时钟诊断。第二条脚本仅保存只读结果，不安装驱动。

```powershell
pnputil /scan-devices
& 'D:\work\KU5P_FX_Accelerator\scripts\inspect_pcie_windows.ps1' `
  -Report 'D:\work\build\KU5P_FX_Accelerator\lesson05d_pcie\windows_admin_rescan.json'
```

若仍无链路，下一轮先增强 PCIe 参考时钟/复位/训练状态观测，再决定是否需要保持 FPGA 配置的主机重新启动。普通断电会丢失当前 SRAM 测试固件，不能把断电再开机当作这个设计已经参与启动枚举。尚未自动重启、禁用根端口或改写 Flash。

所有 AMD 生成 IP、工程、位流、报告、捕获及本地原理图继续留在仓库外。RFSoC 原始工程没有复制进本仓库。
