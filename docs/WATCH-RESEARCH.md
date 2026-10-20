# Apple Watch 卡面研究记录

记录日期：2026-10-20。
源码基线：`52ba05dca4bdc590672c19d554701f4438e20338`。
当前结论：**尚无经过实机验证的 Watch 卡面写入或更新方案。**

## 证据口径

- **源码事实**：可定位到本仓库中的具体函数。
- **实机观察**：在记录的系统组合上得到的工具结果，不能推导其他系统的能力。
- **静态分析**：来自指定版本的系统框架，不等于已在目标系统调用成功。
- **用户反馈**：用户描述的现象，尚未由本项目独立复现。
- **假设**：待通过明确实验验证的技术路线。

## 现有 AirCard 如何工作

| 位置 | 确认事实 | 对 Watch 研究的意义 |
| --- | --- | --- |
| [aircard_backend.py](../aircard_backend.py) 的 `cmd_flash` | 目标是所连接设备的 `/var/mobile/Library/Passes/Cards/{card_hash}.pkpass`，随后清理该卡片的渲染缓存 | 当前没有按手表选择资料或调用手表同步的步骤 |
| [Sources/device_helper.m](../Sources/device_helper.m) 的 `TargetGate` | 只接受以 `iPhone` 开头的产品型号 | 当前实现没有 Watch 写入支持；取消检查本身不提供能力 |
| [Sources/airtraffic_host.m](../Sources/airtraffic_host.m) | 通过 AirTraffic 发起 `Book` 数据类同步 | 依赖手机的媒体同步流程，不能假设可原样用于 Watch |
| [apply_card_skin.py](../apply_card_skin.py) 的 `read_file` | 将目标移到 Media，读取后尝试写回 | 不是只读探测，不应拿未知钱包文件试探路径 |
| [wallet_catalog.py](../wallet_catalog.py) | 解析 Mac 的本地钱包缓存 | 缓存中的卡片列表不能代替手机或手表的实时清单 |

上游 [AirLift](https://github.com/0xjohnnydev/airlift) 描述的是配对 Mac 与 iPhone 的媒体服务边界突破，
并未提供本项目所需的 Watch 卡面实测依据。其说明还区分 API 调用返回与文件实际生效，
因此本项目必须以设备上的实际结果验收。

## 社区背景

上游 [Issue #118](https://github.com/Mak5er/AirCard/issues/118) 报告了
iPhone 新卡面生效、配对 Watch 仍显示默认图片的现象。
2026-10-20 查看时，该问题仍开放，讨论中没有已验证的修复方案。
评论提到的 `Bridge`、独立同步通路和 `com.apple.nanopassbook` 候选位置
属于研究线索，不能直接作为当前设备的写入依据。

## 设备与观察

| 项目 | 实机记录 |
| --- | --- |
| iPhone | `iPhone14,5`，iOS 27.0.1 / `24A446` |
| Watch | `Watch7,9`，watchOS 26.6 / `23U67` |
| CoreDevice 状态快照 | `paired`，传输类型 `localNetwork`，隧道 `disconnected`，开发者模式 `disabled` |
| 手机连接 | 获得设备服务访问后，USB 枚举与手机日志流成功 |
| 配对登记查询 | `com.apple.companion_proxy` / `GetDeviceRegistry` 返回 1 条记录 |
| 日志采样 | 35 秒初次采样；用户打开 Watch 钱包页面后的 30 秒采样；25 秒补充采样 |
| 卡面路径 | 采样中未获得可用且经过验证的 Watch 卡面资源路径 |
| 卡片转移与卡面写入 | 本项目尚未执行 |

配对登记查询协议参考
[pymobiledevice3 的 companion 服务实现](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/companion.py)。
它返回的登记信息不授予文件访问权限。CoreDevice 也可能返回缓存详情；
`paired` 或命令退出码为 0 不能证明实时开发连接可用。

日志摘要显示过 `Bridge` 和 `passd` 活动，部分字段被系统替换为 `<private>`。
没有发现路径只表示这些采样没有提供路径，不证明文件不存在。
不继续以重复的泛化日志采样替代具体假设验证。

用户反馈卡片转移后恢复默认卡面；这个现象未在本项目独立复现，
也不属于当前需要实现自动修复的范围。

## NanoPassKit 静态分析

分析材料来自本机 Xcode DeviceSupport 留存的 **iOS 26.6.1 / `23G83`**
`NanoPassKit.framework/NanoPassKit`，不是当前手机的 iOS 27.0.1。
以下符号及调用关系是旧版本中的线索：

| 符号或方法 | 观察 |
| --- | --- |
| `NPKHomeDirectoryPathForDevice` | 按设备取得目录的函数 |
| `NPKPaymentPassDirectoryPathForDevice` | 在按设备取得的目录下追加路径组件 |
| `NPKStorePathForPaymentPassWithUniqueID` | 与指定支付卡存储路径有关的函数 |
| `savePaymentPass:forDevice:completion:` | 存在按设备保存支付卡的接口 |
| `_savePaymentPass:atURL:forDevice:completion:` | 获取卡片的 `archiveData`，经远程对象调用 `savePaymentPassData:withUniqueID:forPairingID:completion:` |

符号由 `nm` / `strings` 检查，调用关系通过 `llvm-objdump` 的指定符号反汇编观察。
仅分析本地文件，没有调用这些接口或修改设备。未将系统二进制纳入仓库。
文件路径常量尚未完整解析，不能据此生成真实卡片写入路径。

公开的旧版
[NPKCompanionAgentConnection 接口](https://github.com/nst/iOS-Runtime-Headers/blob/master/PrivateFrameworks/NanoPassKit.framework/NPKCompanionAgentConnection.h)
可用于定位研究对象，不能证明当前系统的接口行为或第三方调用权限。

## 未知项

1. iOS 27.0.1 中对应接口、目录和处理进程是否与旧版一致。
2. 手机上的手表卡片资料是向 Watch 发送的源，还是从 Watch 获取的镜像。
3. `savePaymentPassData` 服务端究竟做什么，要求哪些调用权限。
4. 是否存在当前工具能使用的更新触发方式，以及手表是否重新读取图像。
5. 修改后的图像或卡片资料会否被接受、忽略、拒绝或重新下载覆盖。
6. watchOS 26.6 的实际卡面资源格式与刷新方式。

不能从“有保存方法”跳到“能发送任意图片”，也不能从某个普通票券同步接口
推断交通卡等支付卡使用相同流程。

## 下一轮实验

| 顺序 | 要回答的问题 | 取证方式 | 通过或停止条件 |
| --- | --- | --- | --- |
| 1 | 当前系统用什么入口保存手表支付卡资料？ | 获取与目标构建匹配的合法分析材料，定位相关目录函数与服务处理函数 | 能将结论绑定到 iOS 27.0.1；若仍只有旧版资料，明确保留缺口 |
| 2 | 数据流向哪里，如何触发更新？ | 跟踪保存调用、服务接收端、资源读取与刷新条件 | 确认到 Watch 的更新链及调用条件；若只是手机缓存，不将其当作成功路线 |
| 3 | 能否针对单卡提交图像更新？ | 明确设备和卡片，验证恢复方法后，准备一次最小实验 | 服务可接受目标更新；权限或签名校验无法满足时记录阻碍，不盲目覆盖文件 |
| 4 | 手表最终显示了什么？ | 在原生钱包查看并重新打开，记录脱敏结果 | 显示指定图片才通过；手机预览或返回码不作为替代 |

直接访问 Watch 文件系统是备选路线。采用前需要独立验证连接、访问范围及写入能力，
不能将现有配对登记探针直接改名为“手表写入支持”。

## 实验记录格式

每次有效实验在本文追加精简记录；结论改变时同步更新 [MEMORY.md](../MEMORY.md)。

```text
日期 / 源码提交：
目标设备型号、系统版本与构建号：
待验证假设：
前置条件（卡片所在设备、连接状态）：
操作性质（只读 / 创建临时资源 / 修改既有资源）：
具体步骤和检查命令：
预期结果：
实际观察（脱敏）：
恢复与清理结果：
结论：通过 / 失败 / 证据不足
适用范围与下一步：
```

现有本地探针和日志摘要工具保存在原工作区的仓库外目录，没有随本 fork 发布。
本文件保存可共享的结果；新环境复现时应先确认工具与系统条件，不能假定本机材料存在。
