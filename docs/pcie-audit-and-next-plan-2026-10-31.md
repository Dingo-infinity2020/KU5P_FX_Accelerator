# PCIe 审计及下一工作包（2026-10-31）

**建议下一步：执行 H1a-CFG 离线配置穿透核对与最小端点对照准备，先 BUILD_ONLY，再单独决定一次上板。** 不重做M0，不继续无变量的重启/复位循环，不进入驱动、DMA、100G或FX扩展。本轮仅审计和规划，未启动实施。

进入工作树 `D:/work/KU5P_FX_Accelerator`，干净分支 `codex/slot2-e4-restart-2026-10-31`，源SHA `43580d31c864939d9444a8e5e13e7b203c752be4`，fetch后与远端一致。本轮文档分支 `codex/pcie-audit-plan-2026-10-31`。授权依据：用户“请做一轮审计和规划工作，结合之前的规划，判断下一步具体如何实施”。完整重读AGENTS及四份治理文档、README、workflow、hardware、implementation-roadmap与相关实验源。原RFSoC工程及生成AMD IP不上传。

## 一、当前证据能说明什么

| 层次 | 可复用事实 | 本轮限制 |
|---|---|---|
| M0 / FX | 历史72项Python及完整PFB-FX回归、05C OOC；05A有限ROM回放曾上板 | 本轮未重跑；没有持续外部100MS/s板级验收，不是从零开发 |
| e4实现 | 原bit/LTX/DCP三哈希及20项构建源重新核对一致 | 只读重开旧DCP，不是新综合/布线/时序验收 |
| 第二槽重启 | 上轮36样本GT TX/RX/PMA done高、AXI及训练更新，Polling.Compliance，无L0/10EE | 历史BOARD，本轮不连JTAG、不复测当前板；PLL/参考没有稳定资格证明 |
| 观察数据 | 上轮35项输入哈希重新匹配，512地址和8字复读原文保留 | 首条时间戳溯源仍HOLD；当前epoch不是逐事件epoch |
| 主机/网卡 | 上轮ConnectX-5两个功能Gen3×16，GPU Gen4×4，WHEA0 | 网卡已安装；不是第二槽FPGA链路正对照，也不是100G光链通过 |
| LINK | 尚无有效L0、Windows FPGA枚举、BAR或实际DMA | 驱动不能代替物理建链，H2/H3仍BLOCKED |

## 二、审计发现

### A-01 / P0：已确认验收缺口，未确认首条异常的硬件根因

[事件字](../rtl/pcie_boot_diagnostics.sv)保存timestamp64，但不保存epoch；`metadata`中的epoch描述当前读口。`read_valid`只检查地址小于entries且不在new_capture周期。原[解析器](../scripts/pcie_boot_capture.py)检查索引连续、当前metadata/epoch一致及时间递增，不核对捕获起点/跨会话时间下界。

本轮用现有解析函数只读分析上轮原文，函数仍返回 `evidence_valid=True`，同时首条244641140早于昨晚已保存的1314341712及10516269668。**确认的是“格式有效不等于新启动时间溯源有效”**，不是已证实某个RAM坏了。原摘要已把完整溯源置HOLD，不回改为PASS。

[14检查仿真](../sim/tb_pcie_boot_diagnostics.sv)第一次arm检查首条不晚于当前时刻；之后arm检查无效地址，最后PERST只检查首条控制位和read_valid，没有检查新首条应晚于上一epoch。总超时100µs，也没有32位低段进位或长时间运行后的新捕获测试。这是覆盖缺口，既有14项通过保留为原覆盖范围的结果。

本轮只读重开原routed DCP，64个timestamp寄存器Q到事件RAM输入全部存在，28个有效字节写使能引脚共用同一驱动。**简单“高32位在静态网表中没接上”解释不获支持**；这不证明运行期写入、VIO读回或存储都正确。没有给原始首条补高位、猜测隔夜PERST时长或制造修复后的时间线。

### A-02 / P0：上层lane reversal选项与最终硬核不一致，必须先查参数传播

可核对的三层事实：

| 层次 | 实际值 |
|---|---|
| 自写生成Tcl / XDMA父XCI | `CONFIG.enable_lane_reversal=true` |
| 生成的pcie4_uscale_plus子XCI及wrapper | `PL_DISABLE_LANE_REVERSAL=TRUE` |
| 原routed DCP中的PCIE40E4 | `PL_DISABLE_LANE_REVERSAL=TRUE` |

这是**配置意图与落实层次的差异**，尚不能宣布它就是未建链根因。必须区分这个父参数在本器件/版本是否适用、是否被子核覆盖、是否有其他静态映射，以及根端口的行为。不得直接编辑生成vendor RTL或给硬核做试探ECO。

AMD [PG213 lane reversal说明](https://docs.amd.com/r/en-US/pg213-pcie4-ultrascale-plus/Lane-Reversal)对宽度、downshift及两端反转有使用限制。因此也不能直接把当前×4改成×1，沿用原lane0约束就上板；必须先证明连接器lane0→封装→GT→PIPE/硬核lane0的完整关系。根端口是否承担反转目前未核实，不由ConnectX成功推断。

同一DCP中 `PF0_LINK_STATUS_SLOT_CLOCK_CONFIG=TRUE`，所以“Slot Clock漏开”暂不支持为本基线的简单解释。`PL_LINK_CAP_MAX_LINK_SPEED=4`是生成层编码，结合父配置8.0GT/s与生成器位解释应按本版本核对，不能把数字4读成已配置或协商Gen4。

### A-03 / P2：资源记述有具体错误

原文多处写“4个RAMB36”。此次实际DCP事件存储为 **3个RAMB36E2 + 1个RAMB18E2**，共四个原语；旧audit只数RAMB*数量，不校验类型。原失败历史不改写，本审计作为勘误；不影响现有数值/GT读数，也不把勘误称硬件修复。

### A-04 / P1：计划需要更新，不能把已完成步骤继续作为待办

M0已完成，第二槽保留配置重启也已完成；不再等同样重启。主机恢复后ConnectX-5已装第一槽，旧N1“网卡装不上、必须另一主机”不再是当前事实。用户仍优先打通板卡，F1持续源、16流及FFTT继续后排，不因网卡就绪自动切100G主线。

## 三、下一工作包具体实施顺序

以下为实施合同，**不是本轮已执行内容或自动上板授权**。只选H1a-CFG这一个主工作包，观察链修补为其证据验收子项。

### 1. 先做离线配置最小复现，不先改PHY或换时钟

在新的外部目录、独立topic分支，固定Vivado2026.1、XDMA4.2、part `xcku5p-ffvb676-1-i` 和现有Gen3×4/100MHz/256bit125MHz配置。

1. 从全新IP输出生成一份当前配置；再在另一全新目录仅改变lane reversal上层选项，检查父XCI、子XCI、生成wrapper的实际差异。不得复用旧工程缓存，也不得修改旧接受文件。
2. 依据本机IP支持的公开参数/Tcl接口与官方示例，查明最终硬核属性的受支持配置入口；若参数无效或子核不传播，先出具复现和适用版本依据，停止盲目全量构建。需要修复时只改自写重建Tcl/配置检查，不编辑生成文件。
3. 建立连接器0..3→封装引脚→GT X0Y4..7→PIPE/硬核lane的TX/RX双向表，核对是否反序/极性，以及×4向更窄链路时lane0实际在哪里。若无法证明，停止×1方案，保留现有×4范围。
4. 导出完整“意图→父IP→子IP→最终primitive”断言清单，包括参考时钟、Slot Clock、位宽速率、PLL配置、lane reversal及固定GT位置，避免以后只检查父级GUI属性。

**退出条件：** 明确一致的配置，或一个可复现的参数传播缺陷与受支持修法；所有无法核对的值为UNKNOWN。此时仍不宣称LINK已修复。

### 2. 补观察验收最小回归，先定位再决定是否改记录器

使用原word和新的独立期望，保留原解析接口的“格式有效”语义，另设“capture时间溯源”结论；不能静默把旧证据升级。

必须覆盖：原异常首条/混入旧字、事件时间晚于读取时间、跨epoch/错地址、连续两次arm、full后PERST重捕获、PERST保持与再次释放、timestamp低32位进位、非零高32位、地址变化后同步RAM读延迟、读取中epoch变化、旧数据虽按时间递增仍不属于捕获段。高计数测试可在仿真环境设置初始状态缩短运行，不能靠实板等42.95秒、强制PLL lock或修改真实时钟来“通过”。

**验收：** 正常向量通过，全部故障向量被拒绝或明确PROVENANCE_UNKNOWN；同一记录跨RTL、独立Python和Tcl大整数十六进制逐位一致。先复现具体问题，再做最小修复。如果确需新记录协议，才定义新build ID、capture起点、读址回显/确认及逐条身份字段；不默认扩大RAM深度或堆更多探针。不得以重跑旧14项替代新增覆盖。

### 3. 准备一个官方最小端点对照，离线构建后停下

仅在第1步配置闭合后，以相同IP版本/part/×4引脚/插槽参考为基础，重建AMD生成的最小example endpoint，比较其参考缓冲、复位释放和标准tie-off与e4的差异。自行移植的官方示例仍是**待验证对照候选**，不是厂家已跑通固件。

一轮实验只选择有明确假设的一项功能差异：若证明lane reversal传播错误，先测该配置；若它符合预期，再选择官方参考/复位集成差异。不能同时改速率、位宽、参考源、复位和应用，把阳性变成无从归因。

BUILD_ONLY交付：重建Tcl、最少RTL/约束、独立检查、完整hash manifest、原e4回退、时序/DRC/route/CDC报告。必须无新增未豁免CDC Critical、WNS/WHS满足、路由完整、关键primitive配置断言成立；有错误/许可阻塞即HOLD。原e4的历史ROUTED通过不能代替候选的新报告。全PCIe/GT模型若仍受许可限制，准确标BLOCKED并说明仿真实际边界。

### 4. 后续一次受控板上A/B，另立授权边界

通过离线门槛后才提出**具体候选哈希、单一变化、预期结果和回退**供执行。先只读保存当前e4身份/真实输出/已有证据；新候选只做一次SRAM加载和既定一次复位释放、有限观察，不自动重启。

| 结果 | 下一决定 |
|---|---|
| live L0且Windows在场VID:DID | 保存当前现场，核对实际协商速率/宽度，再开H2驱动/BAR工作包；本步不顺带装驱动 |
| GT初始化成功但仍Polling.Compliance | 保留负证据，不增加相同重启/复位；优先取得板卡厂家已验证端点/另一主机/仪器之一作独立对照 |
| 初始化失败、身份/控制不符或主机异常 | 停止；按已验证文件/流程恢复诊断基线或等待人工，保留失败日志，不用多次试写寻找“偶然成功” |

若确实需固件预加载后的Windows重新启动，先保存并说明具体差异，由用户另行操作；此次已完成的e4重启不能无限重复。Si5338、Flash、BIOS、驱动、接线和100G压力均不在该试验范围。

## 四、外部条件、授权与原计划关系

**现在不需要买设备或再次插拔。** 第1至3步可在当前主机离线推进，但本轮只审计规划；执行需要明确恢复离线开发/仿真/IP生成及构建的范围。它们在有用输出可审阅后止于BOARD边界，不能由“继续计划”自动扩为时钟写入/重启。

若随后需要外部条件，优先向厂家索取：同FNIC-KU5P Rev1.0/FFVB676适配的PCIe示例、真实验证主机/宽度速率、参考与PERST连接、重建脚本/约束和运行记录。仅有bit文件而无兼容性/引脚/运行证明不能直接加载。其他选择是兼容PCIe主机，或由有条件人员进行差分参考/电源与接收训练测量；本轮不代用户联系厂家或测量。

AMD [调试指南](https://xilinx.github.io/pcie-debug-kmap/pciedebug/build/html/docs/PCIe_Debug_General_Techniques/Link_Training/general_debug_checklist_reasons_questions.html)支持从官方示例、引脚、低宽度/低速率及不同主机对照切入；本项目需先满足反序lane0映射。AMD [时钟说明](https://docs.amd.com/r/en-US/pg213-pcie4-ultrascale-plus/Clocking)要求插卡时考虑共享参考/SSC及Slot Clock，并说明参考缓冲共享控制条件，因此Si5338不是现在可直接替换插槽参考的修法。

原路线继续：**H1配置/参考/训练闭合 → H2枚举和BAR → H3已知数据DMA → FX结果读回 → 单口100G与持续处理 → 16流；FFTT长期。** M0复用，FX核心保留，F1不作为本次优先任务。不要把修好观察器本身当作PCIe恢复，也不必在没有复现时重做整个观察器。

## 五、本轮交付与停止点

本轮为STATIC审计：原20源/3产物/35条上轮证据输入哈希匹配；64位timestamp输入、28写使能及实际PCIe属性核对。没有新增单元/RTL仿真、综合、实现、bitstream、BOARD或LINK测试；新SIM/SYNTH/ROUTED/BOARD均NOT RUN。原DCP已关闭，未打开Hardware Manager，未改主机或外部时钟。

整理后的[审计摘要](validation/pcie-audit-plan-2026-10-31.json)包含原始查询/输入哈希；本机查询及分析在 `D:/work/build/KU5P_FX_Accelerator/audit_plan_20261031_attempt1`。本轮没有重读实板；上次已保存状态仍是e4/DONE1/reset0/arm0/epoch2、GT done高、Polling.Compliance，无L0，不能当作本次现测。

**下一单项建议：H1a-CFG BUILD_ONLY；当前 WAIT_FOR_IMPLEMENTATION_AUTH。** 这次审计规划任务已完成，板卡主线仍HOLD。原停止点及首条疑点保留，原实验和备份不可覆盖。
