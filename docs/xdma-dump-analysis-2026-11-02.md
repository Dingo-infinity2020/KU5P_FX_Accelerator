# 旧 XDMA 蓝屏转储分析与候选源码审查（2026-11-02）

**结论：10 月 31 日 0x50 的直接触发条件已定位为 user BAR 越界读取。** `xdma_rw.exe` 发起 offset=`0x1000`、length=4 的同步读取，实际 user BAR 长度恰为 `0x1000`。旧驱动未拒绝该请求，在 `XDMA!ReadBarToRequest+0xbc` 的寄存器缓冲复制指令处发生读页错误。此结论来自保存转储和匹配符号，不是重新加载驱动后的复现实验。

## 范围、身份与证据

- 当前用户明确授权“分析10月31日转储/PDB，再对照候选仓库”的离线路线。进入工作树 `D:/work/KU5P_FX_Accelerator`，分支 `codex/pcie-cfg-development-2026-10-31`、源 SHA `b8c9392604a864414c350f8ee51f89467f705f30`；初始干净、与远端一致。文档分支 `codex/xdma-dump-analysis-2026-11-02`。
- 本地证据：`D:/work/build/KU5P_FX_Accelerator/xdma_dump_audit_20261102/`。原始受保护文件经管理员只读复制，不改原件或目录ACL；原件/副本SHA-256一致。转储、PDB、厂商二进制、原始调试日志均不入库。
- minidump `103126-5531-01.dmp`：SHA-256 `DF214A8728B2F213DA9F6114484A7A9F63BF7FE4B86D9149A1B2E7A42C546BF7`。
- 内核内存转储 `MEMORY.DMP`：SHA-256 `AACB7E6BCA6793CC2628DC304A05904E80B411131730FCAB1AE76957E7226F35`，1,901,940,077 bytes。
- 原驱动 `XDMA.sys`：SHA-256 `8E0F9A28F1F3BDFDC63FF06454C2F676DAEFD5F5294638F0146B9A6E44DFCEBC`；PDB `4948495FC5848480CF532341058ED8887578663673CD7A373B8EC0D0658EB0AB`。调试器正常加载为 private PDB symbols，未使用忽略不匹配的 `/i` 开关。镜像 timestamp `5A4FBA3D`、ImageSize `B000`，与旧归档匹配。
- 无现成调试器；官方WinDbg直链403后，使用微软NuGet DbgEng/SymSrv包 `20260319.1511.0`，仅解压至证据目录，通过本地 Python/ctypes 调用 DbgEng 的 OpenDumpFile/WaitForEvent/Execute，不附加真实进程、不注册系统调试器。DbgX包 `20251007.1.0`亦下载但最终分析未使用。内核符号从微软符号服务取得，只下载符号，未上传转储。
- 内核 PDB 为 `ntkrnlmp.pdb` / `F57E740B088E5056E8AF0772F1CC5BEB1`；正常匹配加载。`provenance.txt`、`final-proof.txt` 是主要本地证据，`full-local.txt`/`context.txt` 为中间调查。早期缺内核符号的截断栈不能覆盖最终完整栈。

## 直接测量与因果链

| 检查 | 实测 |
|---|---|
| `.bugcheck` | `0x50`，操作类型读，指令在 XDMA 模块 RVA `0x1d40` |
| `.reload /f XDMA.sys; lmvm XDMA` | 旧归档SYS和private PDB匹配 |
| `ln`、反汇编 | `ReadBarToRequest+0xbc`，内联 `READ_REGISTER_BUFFER_ULONG+3`，`rep movs dword ptr [rdi],dword ptr [rsi]` |
| 恢复trap后的栈 | `ReadBarToRequest -> EvtIoRead -> WDF -> IofCallDriver -> IopReadFile -> NtReadFile` |
| 当前进程 `_EPROCESS.ImageFileName` | `xdma_rw.exe` |
| 栈上 `_WDF_REQUEST_PARAMETERS` | Type=Read，Length=4，DeviceOffset=4096（`0x1000`） |
| 驱动 `XDMA_DEVICE_T` | numBars=2，userBarIdx=0，configBarIdx=1，BAR0映射长度`0x1000`，BAR1长度`0x10000` |
| 故障地址与映射关系 | fault VA = user BAR0 virtual base + `0x1000`，不是请求输出buffer地址 |

合法4字节user BAR读取的最高起始偏移为`0xffc`；本次请求区间为`[0x1000,0x1004)`，已经在user BAR之外。通过函数反汇编和结构体还原相互核对，无须从不完整trap frame中的RSI/RDI零值推断空指针（调试器明确警告部分非易失寄存器未保存）。

**更正旧解释：** [10月31日报告](h2-h3-driver-bsod-2026-10-31.md)中“不是命令执行瞬间、异步/空闲路径”的描述没有转储支持，现由同步BAR ReadFile栈覆盖。有限H2/H3成功与随后越界BAR读取是不同事件；本次没有证据认定DMA中断、空闲清理或PLL引起该0x50。完整命令行未恢复，不能声称已知道操作者或原命令所有参数。越界请求应由驱动返回错误，而非导致主机蓝屏；应用访问范围与内核边界保护均需约束。

## yiyaowen 候选仓库是否解决问题

固定审查提交：[1aca897096ff16e1bf17aab837a270036b3539f3](https://github.com/yiyaowen/xdma_driver_win/tree/1aca897096ff16e1bf17aab837a270036b3539f3)，默认分支2020.5；2018.2为`7a02dfa9abc8803c274bc5d4104dac90944d9ce8`。源码副本在仓库外 `D:/tmp/xdma-driver-yiyaowen-static-20261102/`，不编译、不安装。

- [sys/file_io.c](https://github.com/yiyaowen/xdma_driver_win/blob/1aca897096ff16e1bf17aab837a270036b3539f3/sys/file_io.c) 的 `ValidateBarParams` 在第251行定义；全文检索仅找到定义和注释，未找到调用。`EvtIoRead` 的user/control/bypass分支直接调用`ReadBarToRequest(request,file->u.bar)`；后者只检查零长度，再用bar+offset复制，没有检查BAR映射长度。写路径也缺少对应入口验证。
- 同一文件的既有validator即使接入也不应原样照搬：`offset+length >= barLength` 会拒绝合法的恰好到尾部访问，且没有避免加法溢出。这是STATIC源码发现，未运行候选驱动。
- 2018.2分支同样存在未接入的validator。2020.5相对2018.2确有其他功能变更，但这不能证明修复当前缺陷。原二进制包没有源码，不能把仓库版本冒认为原SYS的精确构建源。
- README自述参考驱动、Win10支持及测试签名；未提供本机Win10/XDMA4.2组合验收或正式签名成品。公开源码头保留Xilinx权利，许可证需另核验；不把第三方源复制入本仓库。

**判断：这个仓库仍可作为离线修复研究起点，但原样安装不能解决已查出的BAR边界保护缺口。** 更换签名也不会改变越界逻辑。旧驱动禁止重装，候选驱动也没有获得本次安装授权。

## 后续最小修复设计（仅建议，未实施）

1. 在user/control/bypass读写入口保留真实BAR索引和长度，验证BAR已映射且设备可访问；范围检查采用不溢出的减法形式：长度非零、offset不超过barLength、length不超过barLength-offset。不能把节点地址空间或寄存器偏移混用。
2. 核对输出/输入缓冲区长度、地址/访问宽度对齐及实际内核API可表示长度；请求失败不得继续MMIO或报告成功。用户程序也需识别BAR边界，禁止盲扫。
3. 独立离线边界回归至少覆盖：size=0x1000时offset=0/0xffc长度4合法；offset=0x1000长度4、0xfff长度4、零长度、超大offset加法回绕及无效BAR均拒绝。未授权前不在真实主机重现越界。
4. 此缺陷修复后仍要独立审查DMA请求取消、IRQ/描述符生命周期、关闭/电源/PnP路径和签名发布。修一个越界缺陷不等于全驱动可持续运行。

## 状态与交接

- PASS：原件与副本2/2哈希一致；SYS/PDB匹配；内核符号匹配；转储中的user BAR越界因果链与候选源码缺口已STATIC确认。
- NOT RUN：候选驱动编译、修复、驱动单元/负向运行测试、Driver Verifier、驱动安装、测试签名、硬件重现、BAR/DMA/100G/GPU压力、Vivado/JTAG及FPGA重配置。无新SIM/SYNTH/ROUTED/CDC/BOARD验收；H2/H3仍HOLD。
- 本轮未改变BIOS/驱动/证书/网络/时钟/电源/FPGA状态，没有重启。11月1日冻结时XDMA已卸载，且没有新转储；本次旧蓝屏分析不能解释那次冻结。
- P0：Windows驱动缺少BAR边界保护已确认；正式可维护驱动仍未取得。NEXT单项为审查并明确授权离线修复/边界回归范围，或向厂商提交本摘要；不自动发送消息，不自动继续实现。WAIT_FOR_AUTH。
- 文档只新增本报告、CURRENT_STATE覆盖段、旧事故报告更正及REVIEW_BACKLOG追加。回退仅撤销文档提交；本地原始证据保留不覆盖。敏感内容与暂存范围检查后同步文档分支，不自动合并main。
