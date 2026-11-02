# XDMA 受控重试执行记录：离线护栏与首次重启前

> 后续覆盖：用户重启后e6/L0/枚举通过，但原驱动包安装时在IsConfigBAR初始化探测中再次0x50，未运行本报告的固定用户态BAR/C2H入口。重试已终止，驱动/证书已清理、testsigning已恢复No，等待人工重启验证。见[新事故记录](xdma-retry-install-bsod-2026-11-02.md)；下面WAIT_FOR_USER_RESTART指首次重启前历史，不是继续安装授权。

状态：**OFFLINE_GUARDS_PASS__E6_PROGRAMMED_ONCE__WAIT_FOR_USER_RESTART**。

用户在当前聊天明确授权按照[完整计划](xdma-controlled-retry-plan-2026-11-02.md)执行全部受控流程，并确认FPGA仍在CPU第一长槽、JTAG连接。该新授权覆盖旧“禁止重装”对本轮有界实验的限制，不代表驱动已安全或允许持续运行。用户手动完成重启；本轮不自动重启。

## 源码与输出

- 工作树 `D:/work/KU5P_FX_Accelerator`，进入分支 `codex/xdma-retry-plan-2026-11-02`，SHA `a0e7669c45272cf92d7bcca05720862f37888ab2`，初始干净并fetch核对远端。
- 实施分支 `codex/xdma-bounded-retry-2026-11-02`；新增 `scripts/xdma_bounded_retry.py` 和 `tests/test_xdma_bounded_retry.py`，旧通用客户端不修改。没有RTL/XDC/Vivado构建变更。
- 新证据目录：`D:/work/build/KU5P_FX_Accelerator/xdma_bounded_retry_20261102_attempt1/`。含baseline、BCD/DriverStore、受验收e6副本、哈希、测试日志、精确回退脚本和change-state；包含主机标识及证书信息的原始文件不入库。

## 离线护栏结果

入口只执行固定2包8192字节C2H，不暴露任意寄存器地址/包数/H2C命令。BAR访问在lazy factory创建句柄前检查大小、对齐、偏移和写值白名单；身份及link/busy检查失败不打开C2H或写应用控制。原越界0x1000/4、尾部跨界、负数、零长、超大offset、非白名单和非法控制值均不下发。C2H总量8192字节，单请求<=4096字节，最多64次请求以处理短读，错pattern/计数/空读/超量完成停止。正常完成：保持句柄观察60秒，正常关闭一次，再观察60秒。

I/O只使用非阻塞GetOverlappedResult(wait=False)。操作等待5000ms后请求取消，再等待最多2000ms确认；未确认时保留OVERLAPPED、buffer、event/file handle并拒绝后续I/O/close，CLI进入HOLD等待人工恢复，不释放可能仍在使用的DMA缓冲区。底层ReadFile/CancelIoEx/CloseHandle仍可能被坏内核阻塞，无法保证进程或系统有界退出；没有做真实驱动取消负向测试，不把fake测试当成驱动取消能力证明。

命令（实际运行；Python为已有Windows 3.12环境，使用-B不生成源码内缓存）：

```
python -B -m unittest discover -s tests -p test_xdma_bounded_retry.py -v
python -B -m unittest discover -s tests -p test_xdma_windows.py -v
```

- 新增8项独立测试PASS（含原失败范围、身份/busy/link前置拒绝、独立pattern和短读、错误数据/预算耗尽、计数失败、取消确认与未确认内存生命周期、真实Win32普通文件传输）。
- 原Windows客户端4项回归PASS。重复执行用于保存日志不重复计算测试数量；合计12项，0失败、0跳过。
- 固定2包参考signature=`0556ac08`。这里只是fake endpoint/普通文件测试，没有真实DMA结果。

## 主机与板上实际动作

- 管理员只读基线：Windows10 build19045、Secure Boot=false、testsigning No、XDMA服务0、WDK测试证书0；原始BCD、DriverStore、转储设置和WHEA基线已保存。现有其他Xilinx USB/网络驱动不属于XDMA，不删除它们。
- 同一旧驱动包身份按计划核对；SYS SHA-256 `8E0F9A28F1F3BDFDC63FF06454C2F676DAEFD5F5294638F0146B9A6E44DFCEBC`；证书有效期到2027-12-14，但只是测试证书，未导入。
- 用户确认当前FPGA物理位置为第一长槽。Windows尚无10EE枚举。JTAG只读确认KU5P、DONE1，无e6 VIO；不把未知上电镜像认作e6。
- 从旧受验收目录复制bit/LTX/DCP/verification到本轮新目录，逐文件核对原件与副本哈希；verification的build_id=465805e6，源SHA460fa77888d6b45fe4b7f3c5441df73adf9f6615。bit `04C4510F11B72304A42C2BFB0DB356F6BFA6AA7E74E99A8B22F181A79E62282D`、LTX `216E37627F096EB3D8C3BA0ADD56933921D049A572B4D02732E8997703BC4E33`、DCP `B447B6D28BD1B0611ABFB4A2DD94FEE535C77B731ADE69DFE0BB8B4C6229F52B`。
- 实际调用已审阅e6 helper的program一次，读回465805e6/DONE1，保存3条新快照。最终VIO output0=0、read_address=000、arm=0；没有VIO提交/arm/手动PHY复位、ILA触发、Flash或Si5338写入。尚未声称L0/枚举通过。
- 生成并语法检查本轮管理员cleanup.ps1：只按本次实际发布INF及新增证书清理，恢复原testsigning No，失败停止、不自动force；清理后仍需重启验证。脚本在证据目录，无敏感内容入库。历史卸载有成功记录，但本轮脚本尚未实际执行，不冒称已通过恢复测试。
- 用户已授权的临时BCD动作实际完成：testsigning配置改为Yes，记录为PENDING_USER_RESTART；没有导入证书，没有安装驱动，没有DMA，没有重启。不得把BCD已配置当作本次运行内核已加载测试驱动。
- Hardware Manager已关闭，e6 SRAM当前保留供电。Vivado会话未用于构建。不要关闭电源、拔JTAG或改卡槽。

## 交接与恢复

NEXT：用户执行Windows“重新启动”（保持FPGA/JTAG供电）；回来后先确认启动时间、e6身份/输出、L0/Gen3x4/10EE枚举，保全本轮快照再继续受控安装。只剩本轮约定的一次建链人工重启；如需额外加载、异常重复重启或改槽，HOLD重审。

若用户放弃后续：管理员执行本轮目录cleanup.ps1，将testsigning恢复No，然后用户手动重启并验证；当前没有驱动/证书可卸载。不得把pending测试签名状态遗忘为默认配置。

现场BAR、C2H、60秒观察和清理：NOT RUN。无H2C、压力/持续吞吐、内核驱动修复、Driver Verifier、实机越界测试；没有新SIM/SYNTH/ROUTED或CDC结果。旧10月31日蓝屏与11月1日冻结均保持独立历史，不因本轮护栏测试宣布解决。main不修改。回退源码可撤销本次提交，硬件/BCD按上述独立步骤恢复，不能用git回退代替系统恢复。
