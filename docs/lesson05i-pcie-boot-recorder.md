# PCIe 独立启动记录器

2026-10-29。针对[e0 重启后的差异](pcie-restart-observation-2026-10-29.md)，新建从 HDL 完整构建的 `lesson05i_pcie_boot_top`，身份 `465805e4`。目标是保留初始化和训练的过程证据，不把终态或旧快照当作原因。FX 学习继续暂缓。

**按用户“最后尝试一次，之后先停下来”的要求，本轮最后一次构建及上板观察已结束，开发暂停。当前 SRAM 为 e4、DONE=1、本地复位=0；Hardware Manager 已关闭，没有进行新的重启或实验。板卡仍未建链、未枚举，BAR/DMA 未测。**

14 项诊断仿真、9 项训练监测仿真、29 包/3712 beat 应用仿真通过；62 项 Python 测试通过。最后一版 WNS=+1.174ns、WHS=+0.010ns，48259/48259 网络布通，no_clock/内部未约束端点为0，未豁免 CDC Critical=0（保留76项生成IP的CDC-15 warning）。59条实际观察、118条VIO/ILA目的连接及保存/重开DCP审计通过；独立审计另外核对了调试核均使用SYS_CLK和两级端点复位。事件存储使用4个RAMB36原语。

## 本轮实板结果与停止点

只下载一次e4到SRAM，先读取reset1保持窗口，再arm并只释放一次本地复位；没有第二组复位实验。随后保存4个held、12个released、12个later样本、4096点ILA以及同一epoch1的完整512条事件。计数和控制VIO持续可读，证明独立观察链活跃；不代表PHY或链路通过。

| 释放后及最终复查 | 观测 |
|---|---|
| 物理PERSTn / 本地复位 / 寄存后的endpoint_reset_n | 1 / 0 / 1 |
| raw GTPOWERGOOD / SYS_CLK监测MMCM | 四路全高 / 已锁定 |
| CPLL / QPLL1 | 长窗口采样时均未稳定锁定 |
| TX/RX/PMA resetdone | 四路均0 |
| 实际CPLLRESET / CPLLPD采样 | 四路均0；QPLL reset/PD保留未知 |
| 接收 | RXELECIDLE全高、RXVALID/COMMA均0；RX未初始化，不能据此判断主机有没有发送训练数据 |
| 参考观察 | 计数有变化，但名义比率门槛不成立；4096点计数差2227，不能换算成可信物理频率 |
| AXI / 训练 | AXI÷8计数固定9；最后Detect.Quiet/sequence1冻结，training_recent=0 |
| Windows10EE:9034 / BAR-DMA | 0个 / 未测 |

完整事件表补充了VIO终态看不到的现象：CPLL mask曾为2（102条）、8（76条），其余334条为0；这些是物理GT X0Y5/X0Y7的采样锁定指示，**不能写成全程所有CPLL均为0，也不能写成初始化成功**。TX/RX resetdone在512条中始终0，AXI÷8计数始终9，没有有效训练进展或L0。

512条仅覆盖名义SYS_CLK下约211.559ms，首个endpoint复位释放事件位于索引137；频繁状态变化使记录提前填满，长窗口已明确报告遗漏事件，不能宣称记录了完整5秒或之后所有过程。完整事件是在同一e4、同一epoch中分批读出，没有重新program/reset/arm。ILA同域心跳严格每256点重复，采样间距检查通过，不校验绝对时钟。

主机读回第一次因9位地址必须补齐3个HEX字符而中断，原失败文件保留；只修正地址格式并在同一固件读回全部512条。每次提交地址前先上传真实VIO输出，最终再次读回reset0、arm0；没有因客户端缓存把端点重新复位。

本次没有写Si5338、Flash、BIOS或驱动，没有主机重启。原e0的精确回退文件保存在最后一次构建目录的restore_e0内。当前e4是已验收的诊断固件，**不是已验收的PCIe工作固件**。按用户要求停在这里，不自动继续构建、变更时钟或安排重启。

原始文件在 `D:/work/build/KU5P_FX_Accelerator/lesson05i_pcie_boot_attempt4`；[公开验证摘要](validation/pcie-boot-final-attempt-2026-10-29.json)保留接受证明、产物哈希、97个证据输入的哈希、实际长窗口状态和完整事件分析。此前失败尝试与源快照均保留。

## 保持的接口与明确变化

仍为 XDMA 4.2、Gen3×4 能力、GTY quad225、lane reversal、256 位/125 MHz AXI Stream、设备 ID 10EE:9034。原 AB7/AB6、T19 及连接器 lane0..3 的 22 个引脚保持。应用仍默认空闲，只有主机明确启动才产生数据。

功能参考路径保持 IBUFDS_GTE4 → 共享 BUFG_GT_SYNC/BUFG_GT → XDMA；没有替换为 Si5338。新增的参考观察缓冲与功能缓冲共用输入和 CE/CLR 网，观察支路掩蔽 CE/CLR 并 ÷8；它不驱动 GT 参考或核心。`REFCLK_HROW_CK_SEL=00` 时 ODIV2 与 O 同频，依据 [UG578 表2-2](https://www.amd.com/content/dam/xilinx/support/documents/user_guides/ug578-ultrascale-gty-transceivers.pdf)，不能因名称 ODIV2 再假设除2。

本地复位先寄存到独立 SYS_CLK 域，再进入 XDMA 的复位同步器；物理 PERSTn 异步拉低，释放经过 SYS_CLK 同步。SYS_CLK 监测 MMCM 不再随本地复位清零。该复位桥是相对 e0 的功能变化，需单独验收；本实验不能宣称只改了观察器。GT 的 PRBS、loopback 和额外 reset 控制仍使用生成 wrapper 的正常禁用值，未改变硬核训练状态或强制 done。

## 不依赖 PCIe 用户时钟的记录

- 64 位 SYS_CLK 计数为相对时间戳，配置后累计，端点复位不清零；名义 100 MHz，不能标为校准 UTC。
- 参考计数从 ÷8 支路经 XPM Gray 传入；AXI 活性计数先每8个 AXI 周期加1再跨域，保证 Gray 输入值可被目的域重复采样。两者仅在 FPGA 配置时初始化，停钟/复位时不跳清零。
- 每 1,000,000 个 SYS_CLK 周期（名义10ms）记录参考计数差；117187–132813 只作为宽松的名义比率门槛，不代表抖动、ppm 或电气质量验收。
- 参考/AXI 计数或训练序号连续 4096 个管理周期不变后标为不活跃。训练快照仍用原相干握手；valid 与“最近更新”分别给出。
- 512 条、每条 256 位事件：时间戳64、控制32、参考窗口差32、实际GT状态64、参考计数32、AXI÷8计数32。控制变化或每个参考窗口结束时记录。
- 记录满后停止覆盖，继续累计遗漏事件数。稳定条件下约能保留5秒，频繁变化会缩短；溢出后不能宣称覆盖了整个启动。
- 物理 PERSTn 下降沿或显式 recorder-arm 上升沿开启新 epoch；保留断言时刻条目，PERSTn 保持低期间暂停周期日志。手动端点复位不会清日志。

## GT 观察与有效性

RTL 中为实际 GT 观察预留两级同步器。综合后只增加观察负载，不编辑生成的 AMD RTL；比较全部 GTYE4_CHANNEL/COMMON 和 PCIE40E4 输入的叶级驱动，挂接前后必须相同。保存、关闭、重开 DCP 后再次核对连接、有效位和两级同步器。

`raw_current` 的每组四位按物理 GT X0Y4..7 排列，对应连接器 lane3..0。以下信号为独立位同步，窄脉冲可能漏采，不能拼成相干高速数据。

| 位 | 观察 |
|---|---|
| 3:0 / 7:4 | raw GTPOWERGOOD / CPLLLOCK |
| 11:8 / 15:12 | TXRESETDONE / RXRESETDONE |
| 19:16 / 23:20 | TXPMARESETDONE / RXPMARESETDONE |
| 27:24 / 31:28 | RXELECIDLE / RXVALID |
| 35:32 / 39:36 | RXCOMMADET / RXCDRLOCK |
| 43:40 / 47:44 | 实际 TXELECIDLE / TXINHIBIT 输入 |
| 51:48 / 55:52 | 实际 CPLLRESET / CPLLPD 输入 |
| 56 / 59 | QPLL1LOCK / QPLL0LOCK |
| 57 / 58 | 保留为0；QPLL1RESET/PD 未观测，解码为未知 |
| 60 / 61 / 62 | PHY rst_idle / rrst_n / prst_n |
| 63 | 实际观察挂接有效；RTL 仿真为0 |

RXVALID、COMMA 或 RXCDRLOCK 高不证明收到有效 TS1/TS2，更不证明数据 BER 或链路已通；本版没有逐字节解码训练有序集。PHY 编码状态保留在原相干训练快照中，未独立同步多位 RXSTATUS 后冒充相干编码。

该 IP 的 QPLL1RESET/PD 驱动含组合逻辑，直接加异步观察器会产生 CDC-10；本版删除这两条观察，保留未知，不改变功能控制、不豁免告警。CPLL 实际 RESET/PD 和 QPLL lock 仍观测。最终以59条原语观察挂接及其端到端审计为准。

## 读回契约

VIO 输入依次为身份32、当前GT64、曾高64、曾低64、控制及计数128、训练快照128、事件读口256、元数据128。计数输入从高到低为控制32/参考窗口差32/AXI÷8计数32/参考÷8计数32。

VIO 输出0是本地复位（初值1），输出1是事件地址9位，输出2是 recorder-arm。读取事件地址需要提交 VIO 输出；helper 在每次提交前先读取所有实际输出值，提交后检查其他输出未变，避免重启后用旧缓存把复位重新拉高。元数据的 read_valid 与 epoch 校验防止把上一个记录段的 RAM 残留当成新记录。

独立 SYS_CLK ILA 保存4096点：控制32、实际GT64、两类计数64。控制 bit31 是同域时间戳 bit7，校验采样间距应每256点重复；它不是 AXI 活性位，也不校验绝对 SYS_CLK。

## 构建与验证边界

```powershell
.\scripts\run_pcie_boot.ps1 -Python <python.exe> -VivadoBin <Vivado/bin> -BuildDir <new_external_directory>
```

脚本冻结输入源并运行仿真，经唯一入口 `tcl/build.tcl` 构建；检查时序、全路由、未豁免 CDC Critical=0、实际 RAM 推断、封装引脚与重开审计后才产生接受证明。不自动上板或重启主机。

新增诊断的14项仿真覆盖异步 PERST 断言、独立时钟停转、端点局部复位、Gray 活性、冻结训练、事件读回/溢出和新 epoch。Python 新增8项故障输入检查，拒绝混用固件、冻结管理时间、跨 epoch、无效读口和缺失/非顺序记录。完整 GT/PCIe 根端口动态模型仍受现有许可/规模限制，以上仿真不是全链路模拟。

第一次诊断单元尝试触发了 Gray 输入更新过快的运行期错误；现已对 AXI 计数加 ÷8，并把运行日志 Error/Fatal 纳入门槛。第一版完整综合发现事件存储未推断为 RAM，已在生成位流前停止，改为唯一写端口及同步读口后重新构建。失败日志和冻结源分别保留，不能只靠 simulator 退出0或出现 PASS 字符串忽略错误。

第二版的检查顺序错误地把优化前的Debug Hub占位和未布局common当作失败；按[UG835 implement_debug_core](https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/implement_debug_core)修正至正确阶段。离线CDC检查另发现复位链及QPLL组合观察问题，已用真实同步链和删除不可靠观察处理。第三版CDC已清零，但13条跨独立时钟的第一级观察路径被误按同步setup检查，WNS=-0.232ns；最后一版只给68个明确的第一级D加针对性false_path，验证第二级仍timed、Gray的max-delay/bus-skew检查仍保留。上述失败版本均未上板。

## 下一次主机启动的先读要求

本轮已按用户要求暂停，当前不安排此步骤。以后仅在用户要求继续并明确需要新启动对照时，返回后先用 `lesson05i_attach_readonly` 记录 DONE、实际身份、epoch、记录条数和 VIO 输出；不先 program/reset/arm。身份或复位不符就记录实际失败，不自动修复并冒充保留配置。随后读当前状态、完整已捕获事件和 Windows 枚举，再按时间戳分析参考、PLL、GT 与训练的先后关系。
