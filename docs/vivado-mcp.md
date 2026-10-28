# Vivado MCP 本地集成

日期：2026-10-28。工具接入时 FPGA 主线按用户要求短暂停在第三课；目前已恢复主线，并使用当前聊天的原生 MCP 完成第四课 PFB-FX 仿真与独立综合。

## 1. 安装了什么

采用开源 [Arthurzxy/vivado_mcp_native](https://github.com/Arthurzxy/vivado_mcp_native)，安装包 `vivado-mcp-native==0.2.1`，协议 SDK `mcp==1.30.0`，Python 3.12.14。它通过本机 stdio MCP 管理一个持久的 `Vivado -mode tcl` 子进程，可打开工程、执行 Tcl、读报告和控制 XSIM。

AMD 官方的 [Vivado MCP 配置说明](https://docs.amd.com/r/en-US/ug1400-vitis-embedded/Configuring-the-Vivado-MCP-Server?contentId=BPzsA9iubJSYGknbojzNkQ) 当前将其列为 Early Access，要求联系 FAE 获取版本及包。本机没有找到该服务器，插件目录也未返回现成 Vivado 插件，因此这次实测使用社区方案。

| 项目 | 本机位置 |
|---|---|
| 独立 Python 环境 | `D:/work/tools/vivado-mcp-native/.venv` |
| 下载的原始 wheel 与源码审阅副本 | `D:/work/tools/vivado-mcp-native/downloads`、`review` |
| 本仓库兼容启动器 | [scripts/vivado_mcp_server.py](../scripts/vivado_mcp_server.py) |
| Vivado | `D:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat` |
| MCP 会话工作目录 | `D:/work/build/KU5P_FX_Accelerator/vivado_mcp_session` |
| 报告临时缓存根目录 | `D:/tmp/vivado-mcp-native` |
| 验证工程、报告与 JSON 记录 | `D:/work/build/KU5P_FX_Accelerator/mcp_validation` |

原始 wheel 的 SHA256 为 `20469d6f920f07a2075a420bb04d72bdebf9653137caa7445bfdb7af7bb0b8dd`。第三方包和依赖放在仓库外，启动器和测试由本项目编写；RFSoC 原始工程没有复制或上传。

## 2. 为什么增加兼容层

实测针对 Vivado 2026.1 修正了以下兼容问题，原始安装包保留：

- 资源报告包含 `CLB LUTs*` 及 `Prohibited` 列，上游旧正则可能漏读或错位。现在从表格列解析 Used、Available 和 Util%，无法解析的值返回空值并标记 `parsed=false`。
- 时序摘要是多列表格，上游只匹配带冒号的 WNS/WHS 行。现在解析实际表格，保留 setup、hold、pulse-width 指标及未约束端口统计。
- 上游行为仿真使用 `launch_simulation -mode behav`，本机实际报 Invalid simulation mode。改用 `behavioral`，同时规范其他仿真模式及 `run all`。
- 正常 MCP 连接关闭时，启动器会关闭它自己创建的 Vivado 子进程。

`met=true` 仅表示报告中的已约束路径满足对应检查，不能代替板级时序或缺失约束检查。本次读取的第三课设计仍为独立综合，没有布局布线与上板。

## 3. Codex 配置

已通过本机 `codex mcp add vivado` 注册到用户级 `~/.codex/config.toml`，并设置独立工作目录与超时。原有配置字段已逐项核对保留，原文件备份在该用户目录的 `.codex/backups/`，不入仓库。

主要设置如下，仅示意本机这个服务器的条目：

```toml
[mcp_servers.vivado]
command = "D:/work/tools/vivado-mcp-native/.venv/Scripts/python.exe"
args = ["-u", "-B", "D:/work/KU5P_FX_Accelerator/scripts/vivado_mcp_server.py"]
cwd = "D:/work/build/KU5P_FX_Accelerator/vivado_mcp_session"
startup_timeout_sec = 30
tool_timeout_sec = 7200

[mcp_servers.vivado.env]
PROCESSOR_ARCHITECTURE = "AMD64"
VIVADO_PATH = "D:/AMDDesignTools/2026.1/Vivado/bin/vivado.bat"
VIVADO_MCP_OUTPUT_ENCODING = "cp936"
PYTHONIOENCODING = "utf-8"
TEMP = "D:/tmp/vivado-mcp-native"
TMP = "D:/tmp/vivado-mcp-native"
```

`cp936` 是本机诊断验证通过的 Vivado 文本解码设置；MCP 的 stdio 通信仍用 UTF-8。不要把整个用户配置文件复制进 GitHub，它可能包含其他服务的私有设置。

[OpenAI MCP 文档](https://learn.chatgpt.com/docs/extend/mcp) 说明桌面客户端、CLI 和 IDE 共用相同主机的配置。文档提到 Restart 及 `/mcp`，但本机用户确认当前界面没有刷新连接按钮；这些入口不能假定每个客户端版本都存在。

2026-10-28 最新核查：当前聊天已直接加载 40 个 Vivado 原生 MCP 工具。通过 `start_session`、`run_tcl` 和 `check_session_health` 实际验证，Vivado 返回版本 `2026.1`、Tcl `8.6.13`、表达式结果 `42`，健康检查为 `healthy=true`。不需要新建任务即可在当前聊天继续使用。

此次原生调用也暴露了一个启动环境差异：MCP 进程未继承 `PROCESSOR_ARCHITECTURE`，Vivado 的 `bin/loader.bat` 会静默返回退出码 1。使用该进程的环境复现失败后，仅补入本机架构 `AMD64` 即通过全部 Doctor 检查。因此已在上述服务器 env 中显式配置该变量，备份并逐项核对其余配置保持一致。此设置按本机 Windows x64 环境填写。

已启动的 MCP 服务器进程不会因为修改配置自动获得新环境变量。本次在仓库外生成 `D:/work/build/KU5P_FX_Accelerator/vivado_mcp_session/vivado_mcp_launch.cmd`，只在变量缺失时补入 `AMD64`，再转调原 Vivado 启动脚本；当前原生会话通过该路径启动并保持可用。若仍在同一旧服务器进程内停止后重启会话，也需向 `start_session.vivado_path` 传入此路径；服务器下次重新加载配置后即可直接用正常 Vivado 路径。原生验证记录在 `mcp_validation/native_session_verification.json`，环境对照验证在 `native_environment_doctor.json`。

较早的检查确实曾返回 `unknown MCP server 'vivado'`；这是当时的聊天工具加载状态，现已不再适用。`check_vivado_mcp.py` 仍可用于独立的本机协议测试。

## 4. 本次实际验证

验证通过真实 MCP stdio 客户端完成，未直接调用 Python 处理函数冒充 MCP 调用：

| 检查 | 实际结果 |
|---|---|
| 上游 Doctor | Vivado 2026.1、Tcl 8.6.13、表达式、中文返回、健康检查与正常关闭均通过 |
| MCP initialize / tools/list | 返回 40 个工具描述；这表示可发现工具数，不等于所有工具都已实测 |
| 持久会话 | 多次请求前后 Tcl `pid` 一致，复用同一个 Vivado 进程 |
| 第三课 DCP 副本 | 成功打开，原始 DCP 的 SHA256 未变化 |
| 资源查询 | LUT=6345，FF=11632，DSP=52，BRAM Tile=10，与原始报告一致 |
| 时序查询 | WNS=5.732 ns，WHS=0.039 ns；保留 99 个输入和 334 个输出未设置端口延迟的信息 |
| 工程操作 | 新建独立探针工程，再用 open_project / get_project_info 核对器件与目录 |
| 仿真 | 启动、读信号、运行 100 ns、读取仿真时间、运行至结束、关闭均通过 |
| 仿真数值验收 | 第二课完整 testbench 得到 `PASS windows=289 accepted_pairs=16795` |
| 兼容层回归 | 8 项测试通过，覆盖新旧报告、缺失字段、hold/pulse-width 违例及仿真模式 |

原始证据位于构建目录 `mcp_validation/doctor.json`、`verification.json`、`mcp_trace.json`、`tools.json`。首次试运行发现的旧仿真参数问题已修复，最终验证记录为成功。

本次没有用 MCP 重新综合或实现第三课，也没有生成位流、编程 FPGA 或访问 RFSoC 原始工程；相关流程的实际验证状态仍以各课记录为准。

后续主线验证：第四课通过原生 `run_tcl` 创建独立工程、`launch_simulation` 启动 XSIM、`run_simulation` 分段运行至 PASS，再通过 `run_tcl` 完成独立综合；`get_project_info/get_utilization/get_timing_summary` 查询与落盘报告一致。实际为 50 帧、9216 行结果，7593 LUT、12067 FF、56 DSP、14 BRAM36 等效块。详情见 [第四课](lesson04-pfb-weights.md)；其原生 MCP 调用摘要在该课构建目录的 `mcp_execution.json`。这不等于 40 个工具均已逐一测试。

第五课 A 已进一步经原生 MCP 完成异步板级实现、JTAG SRAM 配置、VIO 复位/启动与两次 ILA 抓取；每次 2048 行完整 650 位匹配整数参考。见[板级回放说明](lesson05-board-replay.md)。长实现使用启动/查询/收集函数，避免单条原始 Tcl 命令的服务器超时；验证记录不依赖持续占住一条 MCP 请求。

## 5. 怎样复测

兼容层单元测试只需标准 Python：

```powershell
python -B -m unittest discover -s tests -p test_vivado_mcp_reports.py -v
```

完整 MCP 验证使用安装 MCP SDK 的独立环境，在项目目录执行：

```powershell
& 'D:/work/tools/vivado-mcp-native/.venv/Scripts/python.exe' -B `
  scripts/check_vivado_mcp.py `
  --build-dir D:/work/build/KU5P_FX_Accelerator/mcp_validation `
  --checkpoint D:/work/build/KU5P_FX_Accelerator/lesson03_fx/two_channel_fft_fx_synth.dcp `
  --lesson02-build D:/work/build/KU5P_FX_Accelerator/lesson02_x
```

[check_vivado_mcp.py](../scripts/check_vivado_mcp.py) 从用户配置读取服务器启动参数，创建独立工程，测试完成后关闭自己的会话。探针工程直接引用现有第二课源码，测试数据和生成文件留在构建目录。

## 6. 后续怎样帮助 FPGA 学习

可以直接提出：“用 Vivado MCP 打开第三课工程，检查 part 和 top”“打开综合检查点，解释 DSP 和 RAM 分别用在哪里”“运行仿真到指定时刻，读取 valid/ready 和相关实部/虚部”“列出最差路径，并解释约束适用范围”。

MCP 负责交互和查询，版本化的 PowerShell/Tcl 脚本仍负责可复现构建。先用 start_session，完成工作后 stop_session。服务器管理自己的 Tcl 会话，当前方案不会接管一个已经打开的 Vivado GUI 窗口。

第三方工具提供原始 Tcl 能力，执行范围取决于实际命令。后续仍按具体任务确定目标工程和输出路径；持续采样、科学精度、跨板相干和板级约束也仍需各自验证。
