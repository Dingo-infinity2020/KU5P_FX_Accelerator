# H1a-CFG：配置复现、观察验收与e5/e6参考复位候选

2026-10-31。用户明确要求“请按照执行计划，开始一轮开发”，本轮执行离线开发/仿真/IP生成及受限构建，**不上板**。进入工作树 `D:/work/KU5P_FX_Accelerator`，源 `ad6c0928077a3b73d374f7b5fae1dcbaf0e84f8e`，干净且fetch后与远端一致；开发分支 `codex/pcie-cfg-development-2026-10-31`。依据[已审阅计划](pcie-audit-and-next-plan-2026-10-31.md)，复用M0/两路FX与旧e4，不重做算法，不接RFSoC或网卡流量。

## 配置差异的复现与收窄

Vivado2026.1 BASIC / XDMA4.2 / `xcku5p-ffvb676-1-i`，两个空工程分别设置上层lane reversal=false/true，其余Gen3×4、100MHz参考、256bit125MHz、quad225及debug设置完全相同。两次原生生成成功，无Error/Fatal/critical warning；两者的74个.v、8个.sv、4个.vhd及12个.xdc文件逐字一致，子核`PL_DISABLE_LANE_REVERSAL`均TRUE，父model没有该lane-reversal参数。

这确认：**本次配置下父选项开关没有改变生成实现**，不能靠再次设置它修复链路；不是缓存问题，也不能据此泛化所有器件/版本的XDMA行为。一次独立新工程的官方属性接口尝试被Vivado12-1506明确拒绝：scoped IP参数须通过parent修改。未解锁、未编辑生成文件，拒绝日志保留。该负探针有Error，不能因进程exit0或早期通用marker写了PASS就称作干净构建；后续脚本专门标PROBE_ONLY。

进一步只读审计旧e4 DCP：16个差分串行端口与四路双向256个数据位连接检查通过。实际关系为：

| 连接器/顶层lane | RX P/N | TX P/N | 物理GT | 硬核数据lane |
|---|---|---|---|---|
| 0 | P2/P1 | R5/R4 | X0Y7 | PIPETX00/PIPERX00 |
| 1 | T2/T1 | U5/U4 | X0Y6 | PIPETX01/PIPERX01 |
| 2 | V2/V1 | W5/W4 | X0Y5 | PIPETX02/PIPERX02 |
| 3 | Y2/Y1 | AA5/AA4 | X0Y4 | PIPETX03/PIPERX03 |

**物理GT编号倒序不等于连接器相对硬核逻辑lane倒序。** 当前静态路径是0→0、1→1、2→2、3→3，故“必须把硬核动态lane reversal打开”不获该映射支持。保留上轮审计的差异事实，但不再把它当作必需修复或未建链根因。根端口能力、线路电气和实际训练接收仍未证明；不直接转×1。

重建程序：[配置复现Tcl](../tcl/reproduce_xdma_lane_config.tcl)、[生成配置检查器](../scripts/check_xdma_lane_config.py)、[网表lane审计](../tcl/audit_pcie_lane_mapping.tcl)。原始生成IP、官方示例和完整查询留在 `D:/work/build/KU5P_FX_Accelerator/h1a_cfg_20261031`，不上传。

## 首事件验收与仿真

[解析器](../scripts/pcie_boot_capture.py)继续保留格式检查，增加独立temporal_provenance：没有边界为UNKNOWN，仅有上一次观察下界为LOWER_BOUND_ONLY，已知精确捕获起点且满足检查为BOUNDED_TIME_PASS，旧首条/起点不符为FAIL。任何结果都不把e4未存储的逐字epoch补成已证明。晚于读取时刻、错epoch、期望条数变化等结构矛盾直接拒绝。新参数必须来自同一保留配置的独立依据，不能拿首事件自己当独立捕获起点。

保留真实反例：首条244641140、第二条4260663719941，上次已保存时刻10516269668。对未改的512条原文重新分析，仍是格式有效、时间溯源FAIL；不补高位，不改原摘要/原始文件。根因尚未定位。

新增[RTL溯源仿真](../sim/tb_pcie_boot_provenance.sv)使用独立计时参考和仿真专用高计数初始值，覆盖连续arm、满缓冲后PERST、非零高32位与低32位进位、同步读延迟、无效旧地址、PERST保持及释放。15项检查通过；导出的8个完整256位字与Python解码、Tcl大整数十六进制格式逐字一致。这里BOUNDED_TIME_PASS的起点来自testbench独立参考；不是板级捕获身份通过，也没有强制实板PLL/时钟。

新Python故障用例13项，加上配置检查器7项及原72项，共92项全通过。没有用新的通过掩盖首条硬件异常：当前行为RTL并未复现异常，原记录器RTL保持不变，未实施推测性RAM修补。

## e5失败及e6修正：同一复位入口工作包

由工具生成并检查的AMD官方示例，与e4一样采用IBUFDS_GTE4/HROW00及共用BUFG_GT同步控制。其复位输入经IBUF直接进入XDMA，不等待独立SYS_CLK的自写释放桥。基于这个明确差异，本轮选择**复位入口**作为唯一功能实验变量。

新顶层[lesson05j_pcie_reference_top.sv](../rtl/lesson05j_pcie_reference_top.sv)，身份`465805e5`。应用、GT/tie-off、×4引脚、参考路径、科学数据处理及事件RAM均保持e4方案；父lane选项明确为false，前述98个生成HDL/约束对照说明这个父选项变化没有改变当前IP实现。没有把“动态反转开关”夹带成第二个PHY实验变量。

[pcie_reference_reset](../rtl/pcie_reference_reset.sv)将`PERSTn AND NOT manual_reset`直接送入XDMA，由vendor逻辑管理内部复位时序；独立SYS_CLK只负责观察。VIO manual初值仍1，arm初值0。新增单元10项通过，包括停SYS_CLK时断言/释放及手动控制；不是完整PCIe/GT模型。

**e5接口差异：** metadata bit95及control bit2表示独立两级同步的复位释放观察，不能当成core输入的原始边沿；PERST观察仍为独立同步链。不同链有采样延迟，不靠这两个位宣布核心复位时序已满足。e4含义和解析器身份约束不被默默改写，旧e4硬件helper会拒绝e5。e5未获接受，不能进入BOARD；此身份只用于保留失败样例。

e5完成一次真实布线，WNS+1.348ns、WHS+0.011ns、48252/48252网布通、route errors0，但未豁免CDC-10 Critical1：monitor域的VIO请求经过组合逻辑进入vendor的异步复位同步器。接受门槛正确拒绝，未写bitstream/接受证明；只保留`diagnostic_routed_before_acceptance.dcp`和失败报告。这个新缺陷是自写手动合并路径的问题，不是板上PLL根因已查明。

按相同复位入口假设作一次因果明确的修正，另用身份`465805e6`和[lesson05k_pcie_perst_top](../rtl/lesson05k_pcie_perst_top.sv)。[PERST-only入口](../rtl/pcie_perst_reference_reset.sv)只把物理PERST经输入缓冲送给XDMA，不再合并VIO请求；源端已不存在monitor→core reset组合路径。没有waiver、force lock或编辑vendor RTL。其独立单元7项通过，使用严格四态比较；同一工作包不开展速率/宽度/参考源的额外扫参。

**e6控制合同：VIO输出0保留、初值0，不能控制PHY复位；manual-reset元数据恒0。** 控制bit2/metadata95为独立两级释放观察，PERST观察为三级。输出1仍用于读址，输出2只arm事件记录，不复位端点。不得执行旧e4/e5的“program后reset held→VIO释放”操作；新镜像配置后若物理PERST已高，会自行启动。若以后获BOARD授权，先保全旧e4再加载e6，加载后先读当前epoch/已捕获事件，不先arm覆盖首次启动证据。旧e4 helper仍按身份拒绝e6，需经审查的专用读回入口。

e6使用Vivado官方OOC IP cache机制尝试读取本轮e5成功综合的IP子模块，缓存DCP哈希已冻结，缓存仅read。**是否实际复用以工具记录为准**；新的顶层综合/实现/route/CDC必须独立进行，不能把缓存DCP当成新的全板ROUTED结果。最终查询XDMA/VIO的cache_was_used均为0，本次实际仍重新综合IP；ILA非OOC，不适用该cache。可不用cache从源码完整重建，不依赖修改失败e5 DCP或生成的vendor文件。

## 本轮验证与构建结果

e6从冻结源 `460fa77888d6b45fe4b7f3c5441df73adf9f6615` 完成BUILD_ONLY接受：WNS=+1.232ns、WHS=+0.010ns、TNS/THS=0；路由48251/48251，errors0；未豁免CDC Critical=0，保留生成IP的CDC-15 Warning。no_clock/内部未约束端点均0，异步输入/LED延迟覆盖限制在proof中列明。59条GT观察/118端到端目的连接、保存重开审计和272行lane断言通过；独立复位只读审计确认核心只由物理PERST驱动，观察链后两级仍timed。

产物SHA256：bit `04c4510f11b72304a42c2bfb0db356f6bfa6aa7e74e99a8b22f181a79e62282d`；LTX `216e37627f096eb3d8c3ba0add56933921d049a572b4d02732e8997703bc4e33`；DCP `b447b6d28bd1b0611abfb4a2dd94fee535c77b731ade69dfe0bb8b4c6229f52b`。构建在 `D:/work/build/KU5P_FX_Accelerator/h1k_ref_attempt1`，原生exit0；源、证明、报告及输入哈希见[本轮摘要](validation/h1a-cfg-development-2026-10-31.json)。新31项输入源被冻结；缓存DCP另记，未把OOC缓存称作新的全板验收。硬件未下载，LINK/枚举/BAR/DMA全部NOT RUN。

完整候选流水线重新运行14项原诊断、9项训练、15项溯源、7项PERST复位单元及29包/3712beat应用仿真，日志Error/Fatal检查通过。Python92项在本轮新源上通过；没有重跑完整PFB-FX/全PCIe-GT动态模型。

重建命令（BUILD_ONLY）：

```powershell
.\scripts\run_pcie_reference.ps1 -Python <python.exe> -VivadoBin D:/AMDDesignTools/2026.1/Vivado/bin -BuildDir D:/work/build/KU5P_FX_Accelerator/<fresh-reference-build> -Profile e6
```

由唯一入口`tcl/build.tcl`执行；快照、哈希、原生exit状态与Error/Fatal、路由/时序/DRC、未豁免CDC、primitive及lane断言均为接受门槛。保留失败目录，不对约束作宽泛豁免。新配置/仿真仅证明各自覆盖层，不升级到BOARD/LINK。

## 失败保留与恢复

最初配置生成因未建立IP子目录在进入生成前停止；脚本修正，另起generation_attempt2完成两组比较，旧日志/源副本保留。首次溯源sim的RTL实际通过15项，但自写runner误把期望数写为14，外层正确拒绝；修正runner后另起目录通过。二者都不是硬件结果。受管子IP修改的拒绝另列为有意的负探针，不计作干净构建PASS。

本轮未连接Hardware Manager、未program/reset/arm/触发ILA，也未写Si5338/Flash/BIOS/驱动或发100G流量。原e4位流/证明/冻结源重新验证不变；上次历史状态仍为e4/DONE1/reset0/arm0/epoch2、GT done高、Polling.Compliance、无L0，本轮没有重新读实板，不能冒充当前复测。

**停止点 BUILD_ONLY_COMPLETE_WAIT_FOR_CONCRETE_BOARD_SCOPE。** 本轮离线开发结束，e6可供审阅但尚未上板；不自动操作SRAM、主机重启或驱动。下一项应是有明确当前授权的一次e6受控上板/识别：先只读保全e4，核对e6产物哈希和专用读回入口，再一次SRAM加载并先读自然启动记录，不执行旧VIO复位释放流程。不重复e4相同重启或把e6布线通过当成PCIe恢复。e4精确文件回退只恢复诊断配置，不能保证恢复当前GT运行瞬间状态。
