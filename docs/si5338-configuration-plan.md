# Si5338 临时配置与恢复方案

2026-10-29。本文件准备板载参考对照，当前状态是 **离线方案，未具备可执行完整频率表，未写硬件**。优先完成原AB7/AB6输入的单通道CPLL实板实验，再决定是否需要本方案。FX学习暂缓。

## 已核对与新发现

本机 `FNIC-KU5P_SCH_Rev1.0.pdf` 已按PDF第2、12页重渲染目视核对，另参考前一阶段第3、5、6页连接记录。

| 项目 | 已知事实与配置限制 |
|---|---|
| 识别差异 | 已保存两份page0的reg3=0x10，grade code2按官方定义对应 **Si5338B**；图纸U14标Si5338C。reg0=1表示silicon revision B，与型号grade是两个字段。两者均支持100MHz目标，但不能不说明差异而直接套C型号配置 |
| 现有NVM code | reg3 bit0/reg4/reg5组成的代码为0；它不是已验证的频率计划，也不能证明芯片故障 |
| 输入/目的端 | X2为25MHz，经U29选择器到IN3；CLK_SEL=0。CLK2到V7/V6，独立于插槽AB7/AB6 |
| 输出电源证据 | 当前PDF中U14的VDD/VDDO0..3画为裸引脚，没有明确连到电源网络；VCC_3V3_SI5338明确用于I²C/INTR上拉。**上拉3.3V不能证明VDDO2=3.3V**，需更完整电源资料、板上测量或厂家确认 |
| 管理时钟 | X1/100M_OSC产生独立SYS_CLK，经C6到AB21；Si5338 CLK3另到AD21/AE21。不能混用这两对网络 |

型号位定义参见[Si5338 Reference Manual §10.6](https://www.skyworksinc.com/-/media/Skyworks/SL/documents/public/reference-manuals/Si5338-RM.pdf)，型号功能/速率参见[Si5338数据手册 §8](https://www.skyworksinc.com/-/media/SkyWorks/SL/documents/public/data-sheets/Si5338.pdf)。只有来源可核验的电压与连接信息才能成为驱动配置输入，寄存器里编程的电压值不能替代物理电压确认。

## 候选频率与完整表的缺口

候选条件是IN3单端25MHz、内部反馈、CLK2目标100MHz差分输出、关闭扩频/频相调节，其余三输出的启停和电气设置必须逐项规定。整数候选为P=1、PFD=25MHz、VCO=2.5GHz、反馈MultiSynth=100、CLK2 MultiSynth=25、R2=1。它仅证明除数关系可行，不代表PLL环路参数、全部控制位、输出驱动和校准表已经完成。

`scripts/si5338_plan.py` 对现有原始TSV做完整性校验，分别解码型号grade与silicon revision，采用精确分数计算候选，固定输出 `ram_write_ready=false`。它不含I²C接口、不生成写命令。尚未取得适配实际板卡的ClockBuilder导出；常见本机安装目录也未发现可用安装，不据此断言整台机器绝无其他安装。

形成可执行表必须补齐：实际器件/板卡版本、电源/终端、受影响的四路输出；厂商导出的完整表或逐寄存器RM推导及可写掩码；PLL环路参数、杂项要求、页布局；备份与恢复覆盖，以及受限writer的仿真/协议实测。不得从其他板卡复制初始化表。

## 备份、写入与恢复契约

1. 保留原FPGA固件及身份/哈希，同时保留独立SYS_CLK管理和JTAG访问。备份原页选择；确认表涉及的页，逐地址读取至少两份一致快照。现有page0快照不能替代涉及page1的备份。
2. 为每个表项定义地址、页、值、厂商允许mask、读回比较mask及恢复类别。只读、保留、事件/W1C与自清除位不得被当成普通RAM镜像；校准结果和软复位按专门阶段处理。未来writer采用精确白名单，拒绝未审核地址/页及任何NVM编程操作，日志保存每步RMW前值、请求与读回。
3. 按[数据手册Figure9](https://www.skyworksinc.com/-/media/SkyWorks/SL/documents/public/data-sheets/Si5338.pdf)及[AN428](https://www.skyworksinc.com/-/media/SkyWorks/SL/documents/public/application-notes/AN428.pdf)安排：输出禁用、暂停LOL、掩码写频率表、检查所选输入、启动PLL校准/规定等待、恢复LOL、验证报警、转存校准结果、再启用经审核的输出。所有轮询须有超时；不能只检查PLL_LOL而忽略LOS/SYS_CAL。
4. 恢复时先禁用受影响输出，按mask恢复普通配置与原页，按厂商流程重新初始化/校准，再恢复原输出策略并读回验收。原状态本就可能无有效输出，恢复目标是原配置与已记录状态，不应伪称恢复到“原本正常工作”。
5. **重新下载e0只恢复FPGA逻辑，不恢复外部Si5338 RAM；Si5338软复位也不会重载NVM配置。** 两者恢复必须独立验收。未来临时测试只写RAM，不写OTP/NVM。

## 先观察25MHz、绕开合成PLL是否可行

当前X2/U29/IN3网络没有直接接到FPGA输入。只换FPGA位流不能直接对X2计数，现有LOS还是针对当前选择的IN1/IN2。

RM §9.8允许输入经输出mux绕过PLL，形成25MHz缓冲输出。可考虑经CLK2到GT参考观察链，或经CLK3到AD21/AE21普通差分输入后计数；这能先隔离100MHz合成PLL。但它仍要写输入/输出配置和确认VDDO/接收电气，P1输入mux也是共享PLL参考的一部分，不能宣称完全不影响其他输出。它不会提供100MHz给现有CPLL配置，不能把25MHz直接代入100MHz preset后用不锁定作为故障证据。

若原AB7/AB6 CPLL失败，最小下一步是先审核/核对实际源quad的初始化条件或做受控参考对照；本地源只有在上述电气/配置缺口补齐后才能使用。无写入地验证X2本身需要合适仪器在X2/R182/U29附近测量；当前没有这项测量证据。

## 离线复现

```powershell
python scripts/si5338_plan.py --dump D:/work/build/KU5P_FX_Accelerator/lesson05f_si5338_readonly/hardware/dump_a.tsv `
  --output D:/work/build/KU5P_FX_Accelerator/si5338_offline_plan/candidate.json
python -m unittest discover -s tests -p test_si5338_plan.py
```

产物仍标为不可上板；未来完整表/恢复证明应另存版本与输入哈希，不能把此候选算术输出改名后当作已接受频率表。
