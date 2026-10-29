# 单通道 CPLL 实板与源 quad 对照

后续更新：本记录的六轮阴性保持不变；原 e0 随后参与了真实主机重启，首次出现 CPLL/GT 初始化完成及实时 Polling.Compliance，但未建链，局部复位后又无法恢复。当前状态以[重启三阶段实测](pcie-restart-observation-2026-10-29.md)为准，下面“尚未重启”是此前实验阶段的时间边界。

2026-10-29。按用户要求集中打通板卡，FX学习暂缓。本轮完成两个独立工程的真实GT仿真、实现、重开DCP审计和实板三轮复位对照。**两者的采集证据有效，但硬件验收均未通过：CPLL未锁、TX初始化未完成。** 随后已恢复哈希相同的e0；没有改Si5338、写Flash或执行主机重启。

## 对照配置

| 项目 | e2：bank225共享参考 | e3：bank224本quad参考 |
|---|---|---|
| 身份 | 465805e2 | 465805e3 |
| 顶层/profile | lesson05g_cpll_top | lesson05h_cpll_source_top |
| GT | GTYE4_CHANNEL_X0Y4 | GTYE4_CHANNEL_X0Y0 |
| 参考输入 | AB7/AB6，IBUF位于COMMON_X0Y0 | 相同AB7/AB6及IBUF位置 |
| 实际物理入口 | 北向NORTHREFCLK1 | 本地MGTREFCLK0，无NORTH路径 |
| 标量RX P/N | Y2/Y1，原连接器lane3 | AF2/AF1，原连接器lane7 |
| 标量TX P/N | AA5/AA4 | AF7/AF6 |
| 路由后WNS/WHS | +5.876/+0.012 ns | +5.284/+0.024 ns |
| 完整路由 | 7187/7187 | 7180/7180 |
| 未豁免CDC Critical | 0 | 0 |

两者都是单GTY、TX/RX 5Gb/s、CPLL、名义100MHz参考及100MHz管理时钟、用户32位/内部40位；无QPLL COMMON和PCIe控制器。TXINHIBIT/TXELECIDLE均永久1。e3的lane7不作为当前电气×4插槽的数据链路使用，测试目的仅是本quad参考下的PLL/TX初始化。

共享的body、diagnostics、SYS_CLK clocking、flags monitor和板级TB五份源码SHA256完全相同。每个工程独立生成同名Wizard/VIO/ILA IP，独立保存inputs、源快照、原生日志、proof和产物；不能把e2的proof用于e3。新增e3后根dispatcher字节改变，e2历史从其source_snapshot核对，不重写历史证明。

## 复位与观察链

使用SYS_CLK独立管理。唯一一组同步后的目标通道GTPOWERGOOD和SYS_CLK MMCM LOCKED有效后，再等待65536个管理周期，约为名义100MHz下655µs，然后释放Wizard reset-all请求。管理请求下降沿启动标准helper初始化。其资格不等于测量过源quad模拟供电质量。

参考观察支路是IBUFDS_GTE4/ODIV2 → BUFG_GT ÷8 → 32位计数 → XPM Gray跨域 → 管理域VIO。只门控观察支路，不门控GT参考O；计数器手动复位时保持而不跳清零，以保留Gray单步变化条件。事件计数器记录CPLL lock与TX helper done的上升、下降沿，配置后累计并饱和，手动复位不抹历史。

CORE模式Wizard没有可直接导出的CPLLRESET/CPLLPD output optional port，未用外部输入覆盖其控制。RTL预留DONT_TOUCH两级观察寄存器；综合后仅把首级D接到实际primitive输入，并将第三位valid接高。接前/接后比较全部GT输入的实际leaf primitive驱动与顶层输入端口，保证功能驱动未变；重开DCP后再次核对两条实际控制、valid与后级连接。

主agent另作独立只读审计，两版报告末行均为 `audit\tPASS`：核对BUFG的DIV111/CEMASK0/CLRMASK1、CE经工具自动插入BUFG_GT_SYNC来自ref_qualified、32个参考计数触发器时钟、64个Gray目的同步触发器、控制观察第二级。源/产物哈希及审计报告SHA见[公开验证摘要](validation/cpll-board-comparison-2026-10-29.json)。

## 仿真和构建结果

每版都用自身新生成的真实GT模型运行相同body：三轮复位，每轮检查请求保持、真实解锁/恢复与TX ready、资格后Gray计数/活动及事件计数，共12项通过，结束于2172900ns。独立诊断单元另有8项通过，结束于43400ns，覆盖停参考超时、持续高不重复计数、手动复位保留历史及mock control-valid打包。

最终Python测试54项通过。生成模型使用 `C_SIM_CPLL_CAL_BYPASS=1`，**硬件CPLL校准没有在该动态仿真中覆盖**；实际GT控制探针的综合后只读挂接也不由RTL里的低电平stub模拟。模拟通过不能代替实板锁定，模型与硬件的区别保留为验证边界。

两版完整native均无ERROR/Critical Warning，内部未约束端点及no_clock为0，完整路由，无自定义CDC waiver；保存/关闭/重开DCP后的四份审计逐字节相同。CDC另保留22项CDC-15 clock-enable warning。报告的IO delay计数1/2对应异步输入和LED输出，不能扩展为外部电气时序验收。GT端子的IOSTANDARD查询产生工具warning，不代表给GT设置了普通IO电压。

e2首轮在探针挂接后停止：旧比较集合含层级端口，新增跨层观察会产生新别名，字符串比较失败。该尝试保存在 `attempt_hierarchical_driver_aliases`，没有生成或下载它的位流。第二轮改为实际leaf primitive输出+顶层输入端口，保留原始层级表和差异表。前后实际驱动集合哈希完全相同；层级差异只有CPLLRESET、CPLLPD各新增3个观察别名，无删除。独立观察审计的初版同步器/单元筛选查询也独立保留，最终以实际连接重查通过，不覆盖失败记录。

## 实板结果：六轮均为阴性

每版显式6MHz JTAG下载后做三轮手动请求保持/释放。每轮保持窗口4个VIO样本，释放窗口12个样本，释放观察的主机时间下界均大于2秒，满足至少1秒门槛；计数与时间戳支持采集仍在更新。两份suite分别记录 `evidence_valid=true`、`hardware_passed=false`。

| 释放窗口的观测 | e2 | e3 |
|---|---|---|
| GTPOWERGOOD / SYS_CLK MMCM LOCKED | 1 / 1 | 1 / 1 |
| manual_reset / reset_all | 0 / 0 | 0 / 0 |
| reference_qualified / controls_valid | 1 / 1 | 1 / 1 |
| 实际CPLLRESET / CPLLPD已采样电平 | 0 / 0 | 0 / 0 |
| CPLL lock / TX PMA done / TX helper done | 0 / 0 / 0 | 0 / 0 / 0 |
| 三轮初始化释放序号 | 依次1、2、3 | 依次1、2、3 |
| lock/TXdone四种边沿计数 | 全部0 | 全部0 |
| 参考计数与名义比率比较 | 稀疏进位，不符 | 稀疏进位，不符 |

这排除了“本次只是在读未释放的手动管理请求”这一解释，且没有在采样窗口中看到CPLL被持续reset/power-down。它不排除漏掉窄脉冲、校准过程或其他初始化条件，也不证明模拟供电、绝对参考频率或抖动合格。

每版还有额外的steady_later 8192点ILA，两者心跳周期严格256点，同域采集校验通过；CPLL/TXdone无变化、事件计数仍0。ILA只有名义约81.92µs，不能替代VIO长窗口。三个cycle_release片段触发于已同步的reset_all变为0，即资格等待完成以后；约655µs资格等待发生在触发前，不在此窗口内。短窗口仍不保证覆盖全部GT校准/初始化，长时结论来自suite。

e2的原decoder、测试及helper已保存快照，原suite保留旧decoder SHA；支持e3的新decoder在内存重新解析e2，样本、检查和最终阴性结论完全一致，没有覆盖旧JSON。ILA本身没有嵌入身份，身份取自已验证产物、program记录与VIO来源链，不能只看CSV列名判断固件。

本quade3仍失败，使“仅因跨quad路径未连通而失败”不足以解释两组现象；两版DCP中的物理路径都已核对。没有因此断言板卡损坏、主板缺钟、NVM损坏或插槽物理时钟处于某个测得频率。异常数字计数不被换算成实际物理时钟测量结论。RX数据、BER、PCIe训练/枚举、BAR和DMA均未由这些无PCIe控制器的测试验收。

## 已回退的当前状态与下一步

主agent已从e2目录的 `restore_e0` 恢复哈希完全相同的原e0 bit/LTX/DCP，DONE=1、身份465805e0、局部复位1→0读回一致、JTAG6MHz。`hardware_verification.json`及 `ready_for_optional_restart*` 保存新读数：状态6次、PHY12次、训练12次；PHY均00002c0f0000，训练最后快照Detect.Quiet/sequence1不更新，Windows 10EE:9034数量0。主机DMA未测，不能将回退视为PCIe恢复。

外部目录：`D:/work/build/KU5P_FX_Accelerator/lesson05g_cpll_pcie_ref/restore_e0`。e3回退前最后VIO原始字也保存在其 `hardware/final_before_restore.tcldict`。本阶段没有改Si5338，因此这次回退只涉及FPGA；未来若写Si5338，恢复e0不会自动恢复外部时钟芯片。

下一步准备在保留明确e0身份和复位状态的条件下，做一次受控主机启动/枚举对照；**本阶段尚未执行重启**。只读入口 `tcl/read_cpll_restart_retention.tcl` 已在当前启动会话以 `pre_restart_dry_run` 验证，复位读回0；它是重启前预演，不是重启后证据。重启后先观察实际配置保留情况，再记录相同版本的GT/PHY与枚举，不能把重新下载后的结果冒充已在启动时生效。若仍无改善，需要有效独立参考或其他主机/仪器/厂家工程作为新的正对照，避免重复无区分力的ECO。

Si5338目前只具备[临时配置与恢复离线方案](si5338-configuration-plan.md)：型号grade与图纸差异、实际输出电压证据及完整频率表/回滚覆盖仍待补齐，不以本阶段阴性结果为理由直接试写。后续工作继续集中在板卡打通。

## 复现和保存范围

在新仓库外目录调用 `scripts/run_cpll_board.ps1`（e2）或 `scripts/run_cpll_source.ps1`（e3），显式指定VivadoBin/Python/BuildDir；两者均先冻结源、运行真实模型，再经 `tcl/build.tcl` 构建、验收，不自动上板。`scripts/cpll_board_capture.py` 校验已保存的suite与ILA，允许真实硬件阴性，区分证据格式有效与目标通过。

原始TSV/CSV/ILA、模型/报告、失败尝试、decoder快照、DCP/bit/LTX和原始外部资料留在仓库外的两个阶段目录。公开摘要只记录配置、状态结论、验收边界与原始文件哈希；不上传RFSoC原始工程和生成IP。
