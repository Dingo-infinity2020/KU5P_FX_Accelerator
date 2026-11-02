# 旧 XDMA 包受控重试：安装阶段再次蓝屏

**FAIL / RETEST_ABORTED__PACKAGE_REMOVED__TESTSIGNING_OFF_PENDING_USER_RESTART**。本轮在安装/加载旧驱动时发生新0x50，尚未进入固定BAR/C2H入口。已按授权停止并清理，不再重装该二进制包。现需要用户手动重启后确认恢复。

## 范围与基线

当前用户授权执行[受控计划](xdma-controlled-retry-plan-2026-11-02.md)，并在完成上次提示的人工重启后通知“已重启”。工作树 `D:/work/KU5P_FX_Accelerator`，分支`codex/xdma-bounded-retry-2026-11-02`，进入SHA `b0012f3f09ad3132a9e57a0269f40ee9173dc513`，初始干净并fetch核对远端。上次[准备报告](xdma-bounded-retry-2026-11-02.md)中的8+4项测试只证明用户态护栏和普通文件路径，不是驱动安装或稳定性验收。

Windows重启时间21:05:07。先读保全确认e6/465805e6、DONE1、output0=0/readaddr0/arm0，没有新program、VIO提交或ILA触发；训练快照LTSSM编码0x10（L0）、Windows10EE:9034、Gen3x4、问题码28（未安装驱动）。无新位流、Flash、Si5338或BIOS变更。

本地证据目录：`D:/work/build/KU5P_FX_Accelerator/xdma_bounded_retry_20261102_attempt1/`；新增事故在其`crash_20261102/`子目录。原始转储、主机标识、安装日志/证书与损坏状态文件仅本地保存，旧10月31日转储副本不覆盖。

## 实际操作与失败阶段

管理员脚本先核对原包SYS/INF/CAT哈希、Secure Boot=false、BCD testsigning Yes、单个10EE:9034、精确测试证书指纹与有效期，再执行本轮证书导入/`pnputil /add-driver ... /install`。脚本尚未输出成功结果即遭内核崩溃，部分change-state/install日志在重启后内容为NUL，不能据此推断实际持久化步骤。

固定回读入口的`attempt-consumed.json`不存在，operations/result/capture文件未生成；未运行`xdma_rw.exe`、未执行用户BAR读取、应用控制写入或C2H/H2C。新事件WER1001为21:11:41，BugCheck0x50；主机21:11:26重新启动。6008内的先前时间是Windows记录值，不能替代精确崩溃时刻。

## 新转储定位：驱动初始化自己越界探测小BAR

用前次离线分析工具、同一旧SYS及private PDB与正常匹配的内核符号读取新转储，未加载真实驱动或操作硬件。未使用忽略符号不匹配开关。

| 项目 | 新实测 |
|---|---|
| 崩溃进程 | System |
| 故障指令 | XDMA模块RVA0x2473，`mov eax,dword ptr [rcx+2000h]` |
| 内联路径 | IsConfigBAR -> FindConfigBAR -> IdentifyBars -> XDMA_DeviceOpen+0x15b |
| 调用栈 | EvtDevicePrepareHardware -> WDF PnP硬件准备 -> System工作线程 |
| BAR结构体 | numBars=2，BAR0长度0x1000，BAR1长度0x10000 |
| 现场 | RCX=BAR0映射基址；读取BAR0+0x2000，故障地址与BugCheck参数一致 |

**这与10月31日的ReadBarToRequest越界不是同一个入口。** 此次在驱动识别配置BAR时，尚未检查候选BAR长度，就访问候选+0x2000；其后反汇编还会读取+0x3000。对4KB user BAR，这些探测已超出映射。即使我们的测试程序完全不发读写，安装本身也能触发缺陷。不能再把“避免xdma_rw越界命令”当成该包可安全重试的充分条件。

固定审查的yiyaowen提交1aca897，在`libxdma/device.c`的IsConfigBAR（第182行）也直接构造IRQ_BLOCK_OFFSET/CONFIG_BLOCK_OFFSET指针并读取，FindConfigBAR遍历所有BAR，未先按barLength过滤。候选源码另有先前确认的BAR用户读写范围缺口；两者都未修复、未构建或测试。准确源码构建对应关系仍未证明，不声称该源码能直接修好旧二进制。

直接缺陷为驱动未对映射范围做初始化探测保护；4KB user BAR本身不因此成为非法FPGA设计。本次不排除端点与旧参考驱动存在其他合同不兼容，不能靠放大BAR/换槽掩盖问题。此前曾加载成功也不是当前初始化访问合法的证明。

本轮前置审查关注用户态访问护栏，遗漏了驱动安装初始化中的IsConfigBAR探测，这是准备缺口；应先把所有初始化MMIO访问纳入静态审核，不能因已找到一条触发路径就推断其他路径安全。

新dump身份（原件/本地副本逐一哈希一致）：

- MEMORY.DMP，2,202,785,805 bytes，SHA-256 `44BC889AF85508182E0ED4B3F66074528C18BFD65C197F0EC773942D620B75ED`。
- 110226-5218-01.dmp，2,621,524 bytes，SHA-256 `ABFF1F704AB39C88A17AF3D3DD50256D071BA93708CDA6A7387AF80B239BEC6B`。
- 原SYS仍为`8E0F9A28F1F3BDFDC63FF06454C2F676DAEFD5F5294638F0146B9A6E44DFCEBC`，PDB正常匹配；主要日志为`initial-debug.txt`和`probe-debug.txt`，均不入库。

## 恢复实测与剩余步骤

不依赖损坏的change-state：依据安装前基线和实际DriverStore清单，识别到唯一Xilinx XDMA包`oem58.inf`、版本17.47.34.943；实际执行`pnputil /delete-driver oem58.inf /uninstall`成功，没有force或重复安装。对本轮精确证书指纹检查Root/TrustedPublisher并清理，不触碰其他证书。恢复BCD testsigning off。

21:13:55管理员恢复结果：XDMA服务0、目标DriverStore包0、精确测试证书0；BCD枚举testsigning No。恢复启动以来WHEA0。本轮新转储已先归档；旧证据保持不变。这里只能声称清理命令和当前枚举通过，**仍需用户重启后确认测试签名实际恢复及无驱动残留**。没有新JTAG连接/重下e6；蓝屏后当前FPGA SRAM状态UNKNOWN，不能沿用蓝屏前保留状态。

NEXT仅为用户Windows“重新启动”，回来只读验证清理，不再安装或执行DMA。e6/驱动复测计划结束为FAIL；若未来修复驱动，须另立离线源码/许可/签名及初始化与访问边界回归任务。不能自动转入候选源码安装、改变FPGA BAR大小或再次实机重现。

## 验收与交接

- 新增硬件证据：重启前置L0/枚举观察通过；安装阶段FAIL。BAR/C2H/H2C、两段60秒观察、持续吞吐NOT RUN；无新SIM/SYNTH/ROUTED/CDC。旧8+4项离线测试结果不冒充本次驱动验收。
- 只改本事故报告、CURRENT_STATE与原执行记录的覆盖提示。当前源代码未修改以绕过故障。暂存范围、敏感信息和diff检查后同步文档，不合并main。
- 关闭本轮重复安装路径；不自动启动任何硬件实验。11月1日无XDMA时的冻结仍是独立OPEN问题，不能用这次新0x50代替其原因。
