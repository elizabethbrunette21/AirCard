# Apple Watch 卡面研究记录

初始记录日期：2026-10-20；最近更新：2026-10-21。
源码基线：`52ba05dca4bdc590672c19d554701f4438e20338`。
当前结论：**尚无经过实机验证的 Watch 卡面写入或更新方案。**

当前进度：已在 iOS / watchOS 26.5 模拟器运行时定位支付卡同步与导入链，
并用目标 iOS 27.0.1 框架核对目录构造与客户端保存调用。
解锁后的普通 App 登记查询仍为空，尚未取得可用的卡包访问和同步触发入口。
执行顺序及换路条件见 [项目安排](PROJECT.md#当前执行安排2026-10-21)。
具体目录构造、现行与旧版分支、资源清单和权限限制见
[同步入口分析](WATCH-SYNC-ENTRY.md)。这不是目标实机支持声明。

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
| Watch CoreDevice 早期状态快照 | `paired`，传输类型 `localNetwork`，隧道 `disconnected`，开发者模式 `disabled`；不代表手机状态 |
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

## 目标实机仍待确认

1. iOS 27.0.1 中对应接口、目录和处理进程是否与旧版一致。
2. 模拟器中确认的 `PaymentCards` 同步数据源，在目标实机上的实际目录及卡包内容。
3. 模拟器中确认的 `savePaymentPassData` 保存行为与私有权限检查，在目标版本是否一致。
4. 是否存在当前工具能使用的更新触发方式，以及手表是否重新读取图像。
5. 修改后的图像或卡片资料会否被接受、忽略、拒绝或重新下载覆盖。
6. watchOS 26.6 的实际卡面资源格式与刷新方式。

不能从“有保存方法”跳到“能发送任意图片”，也不能从某个普通票券同步接口
推断交通卡等支付卡使用相同流程。本轮已确认模拟器中的同步源明确包含支付卡；
仍需验证武汉交通卡的实机处理结果。

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

## 2026-10-21：手机恢复连接后的只读检查

用户再次确认武汉交通卡在 iPhone。本次 MobileDevice 实时枚举读到
`iPhone14,5` / iOS **27.0.1 / `24A446`**，已有信任会话成功。
CoreDevice 的手机详情为 `paired`、`wired`、隧道 `connected`、开发者模式 `enabled`，
`ddiServicesAvailable` 为真。另以 `ddiServices --no-auto-mount-ddis` 查询，
当前 DDI 的 `isUsable` 和 `contentIsCompatible` 均为真；没有请求挂载或更新镜像。

| 只读请求 | 实机结果 | 能得出的结论 |
| --- | --- | --- |
| `GetDeviceRegistry` | 1 条配对标识记录 | 手机的手表登记可读取 |
| 直接 lockdown 启动 `com.apple.dt.fetchsymbols` | `-402653150` / `0xe8000022`；`AMDCopyErrorText` 为 `The service is invalid.` | 此启动方式未取得服务，尚未查询符号文件；不是连接失败或所有符号入口都不存在的证明 |
| `GetValueFromRegistry` → `productType` | `UnsupportedWatchKey` | 此字段名未获支持 |
| `GetValueFromRegistry` → `systemVersion` | `UnsupportedWatchKey` | 此字段名未获支持 |
| `GetValueFromRegistry` → `localPairingDataStorePath` | `UnsupportedWatchKey` | 未能由此取得手表资料目录 |

后三个键名来自 NanoRegistry 分析线索，不是 companion 服务已公布的支持清单。
请求格式依据
[pymobiledevice3 companion 实现](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/companion.py)。
实验说明不能把“配对登记可枚举”扩展为“任意 NanoRegistry 属性可读取”。
未测试其他命名，不把这三个拒绝结果推广为所有键均不支持。

本次可复现的查询探针是
[companion_values_probe.m](../tools/watch-research/companion_values_probe.m)。
它要求已有信任及恰好一个配对登记标识，每次查询重新开启服务，最长运行 30 秒；
输出固定查询键、结果类型或已知错误，不输出标识、返回字典键或属性值。
`completed: true` 仅表示请求批次执行结束，不表示字段查询成功。

从仓库根目录编译并执行无设备自检：

```sh
mkdir -p build
xcrun clang -fobjc-arc -O2 -Wall -Wextra \
  -framework Foundation -framework CoreFoundation \
  /System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice \
  tools/watch-research/companion_values_probe.m -o build/companion_values_probe
build/companion_values_probe --self-test
```

实际查询以已有信任手机标识作为唯一参数；不要把该参数或原始登记响应提交到仓库。
本轮编译、自检和实际查询均完成，未转卡、未操作钱包文件，也未取得可恢复卡包。
下一步优先查明现代开发连接上的符号访问方式，再核实目标系统的目录及触发条件。

进一步查到 pymobiledevice3 的
[RemoteFetchSymbolsService](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/remote_fetch_symbols.py)
使用 `com.apple.dt.remoteFetchSymbols`，通过 RemoteXPC 查询 DSC 文件清单与大小。
这是不同于旧 lockdown 服务的候选分析入口，尚未在目标设备调用，不能写成已可用。
准备本地隔离客户端时，pymobiledevice3 11.40.2 的依赖下载连续超时，安装未完成；
临时环境和缓存留在 Git 忽略的 `.tmp/` 中，没有增加产品依赖。
下一次先解决客户端准备与受信任的开发服务连接，再做有界的清单请求，不默认下载整个缓存。

## 2026-10-21：新版符号服务实机验证

降低下载并发后，pymobiledevice3 **11.40.2** 的隔离环境安装完成。
使用 [remote_symbols_probe.py](../tools/watch-research/remote_symbols_probe.py)，
通过 `UserspaceRsdTunnel(autopair=False, remotepairing_fallback=False)` 连接既有受信任手机。
它使用 `CoreDeviceProxy` 用户态通道，不停止 Mac 的 `remoted`、不创建新配对、不挂载 DDI。
第三方诊断日志被关闭，临时客户端状态置于 `.tmp/`，连接结束后清理。

实机返回 `iPhone14,5` / iOS **27.0.1 / `24A446`**。
`RemoteFetchSymbolsService.get_dsc_file_list()` 成功返回 **82 个系统文件、
总计 7,209,702,576 字节**。这证明当前系统的分析材料可读，不证明钱包文件可读写。

先复制两个主缓存文件，大小分别为 786,432 与 33,783,808 字节，检查传输长度与缓存文件头。
根据 [Apple 缓存格式定义](https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/dyld_cache_format.h)
读取索引，含目标框架的主缓存登记 4,690 个映像、77 个子缓存，缓存 UUID 为
`3352F765-FFA1-3998-92F4-59A43221A2CF`。

| 框架 | 主缓存索引中的 Mach-O UUID | 代码起始所在子缓存 |
| --- | --- | --- |
| NanoPassKit | `FA1C9659-15F8-3E46-BB12-BACCCC2FE202` | `.61` |
| NanoRegistry | `A091FC1C-866D-33D8-9AC6-98F6D25732A8` | `.42` |
| PassKitCore | `1F6E7BC3-43C0-32D0-907A-497F60A95471` | `.09` |

以上 UUID 属于系统软件，不是设备标识。主缓存索引只能定位框架，不能替代函数实现分析。
现成分析器需要完整配套缓存，82 个文件现已复制到 Git 忽略目录
`.tmp/system-symbols/24A446/`。使用本地 `ipsw v3.1.739` 提取上述三个框架，
`dwarfdump --uuid` 返回值与索引一致。没有提交系统二进制或完整反汇编。

`ipsw` 来自其[官方发布](https://github.com/blacktop/ipsw/releases/tag/v3.1.739)，
Apple Silicon 压缩包 SHA-256 与发布摘要一致：
`c09e8eba02c332f5b50d15f94383e59dd35646d70f6ea9e78d185e9afda6abc2`。
本机 `dyld_info` 对提取产物报告 `__objc_stubs` 对齐错误；改用缓存直接反汇编和
`llvm-objdump`。所有分析均在本机，没有调用在线反编译服务。

从仓库根目录复现：

```sh
# 已有信任、连接的目标手机；只查询清单
.tmp/watch-research-env/bin/python tools/watch-research/remote_symbols_probe.py
# 无设备自检
python3 tools/watch-research/remote_symbols_probe.py --self-test
# 显式复制主缓存，或复制已确认大小的完整系统缓存
.tmp/watch-research-env/bin/python tools/watch-research/remote_symbols_probe.py --fetch-headers
.tmp/watch-research-env/bin/python tools/watch-research/remote_symbols_probe.py --fetch-cache
```

复制模式仅接受目标构建 `24A446`，主缓存上限 128 MiB，完整清单上限 8 GiB；
完整复制前检查本地剩余空间。探针不转卡、不访问卡包、不修改手机文件。
完整复制复用库的下载器，失败后可能留下不完整本地文件；重试会重新下载大小不符的文件。
下载器第二次查询的清单必须与检查过的清单一致，结束后逐个核对本地大小。
不要把本地缓存、工具环境或系统二进制加入 Git。

### 当前 iOS 27.0.1 的静态核对结果

| 函数及缓存地址 | 直接观察到的行为 |
| --- | --- |
| `NPKHomeDirectoryPathForDevice`，`0x293129a50` | `valueForProperty:` 读取 `NRDevicePropertyLocalPairingDataStorePath`，追加 `NanoPasses` |
| `NPKPaymentPassDirectoryPathForDevice`，`0x293129bb0` | 调用前一函数，追加 `PaymentCards` |
| `NPKCompanionAgentConnection._savePaymentPass:atURL:forDevice:completion:`，`0x293113948` | 获取远程代理、卡包 `archiveData`、`uniqueID`、`NRDevicePropertyPairingID`，调用 `savePaymentPassData:withUniqueID:forPairingID:completion:` |
| `NRDataFilePaths._pathToNanoRegistryPairingStorePathDirectory`，`0x23d2ba418` | 查询用户 Library 目录并追加 `DeviceRegistry`；仍未给出具体手表的子目录值 |
| `NRPairedDeviceRegistry.pairingStorePathPairingID:`，`0x23d2da08c` | 从设备属性取得目录和 pairing ID，经回调返回；方法参数不是要查询的 ID |

共享缓存里的 Objective-C 跳板也已解析，确认上述 selector，未仅凭方法名推测调用。
这将目录构造和客户端保存链从旧版线索提升为目标手机构建的静态事实。
服务端守卫与手表导入行为的现有证据仍来自 26.5 模拟器，不能自动外推为 27.0.1 / 26.6 实测。

另查本机 `devicectl device info files --help`，公开域仅有 App 容器、App Group、
临时目录及系统崩溃日志，没有通用的用户 Library 域。
`device pairings list` 返回 `ArgumentParserInternal.ValidationError`，未取得配对列表；
此结果不作为手机目录访问权限的证据。

### 手机本地只读 NanoRegistry 探针

新增 [registry_probe.m](../tools/watch-research/registry_probe.m) 与
[Xcode 项目](../tools/watch-research/RegistryProbe.xcodeproj/project.pbxproj)。
独立标识为 `dev.aircard.WatchRegistryProbe`，使用现有开发团队签署自己的配置，
没有复用或覆盖其他 App。它加载 NanoRegistry、查询活动设备及目录属性，
仅向自己的 `Documents/registry-result.json` 写结果；没有卡包读取或保存 API 调用。
若返回真实目录，结果只能保存在本地忽略目录，不能提交到仓库。

实机过程与结果：

1. 初版启动后收到 `SIGTRAP`，仅分析本探针的崩溃报告。
   故障栈为 `UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption`。
   已改用 UIScene 生命周期，重新构建、签名、安装和运行成功。
2. 修复后的结果文件返回 `status = completed`、`frameworkLoaded = true`、
   `registryAvailable = true`、`activeDeviceFound = false`、`pathFound = false`。
   这是普通开发 App 的首次活动设备查询结果，不是全部目录读取方式被拒绝的证明。
3. 为排除查询时机与活动设备选择的影响，探针增加 `getPairedDevices` / `getAllDevices`
   数量检查及一次 3 秒等待。当前版本已构建、签名和安装，尚未取得这次复核结果：
   启动明确返回 `CoreDeviceError 10002`，底层 `FBSOpenApplicationErrorDomain 7 / Locked`。
   已请用户解锁并暂时保持亮屏；没有要求重连、转卡或开启开发者模式。

编译检查（不签名、不接触手机）：

```sh
xcodebuild -project tools/watch-research/RegistryProbe.xcodeproj \
  -scheme WatchRegistryProbe -configuration Debug -sdk iphoneos \
  -destination generic/platform=iOS -derivedDataPath .tmp/registry-probe-build \
  CODE_SIGNING_ALLOWED=NO build
```

实机签名需使用本机开发团队，并为该独立标识准备配置；团队与配置不写入项目文件。
`devicectl device process launch` 的选项必须放在 bundle identifier 之前。
结果复制限定为此 App 自有容器；原始崩溃报告、签名产物和诊断结果均在 `.tmp/`。

### 用户解锁后的复核与权限边界

用户确认解锁后，已成功重新启动上述探针并从它的自有容器取回结果：

| 检查 | 实机结果 |
| --- | --- |
| `status` | `completed` |
| 框架加载 / 登记对象创建 | 均成功 |
| 首次 `getPairedDevices` 数量 | 0 |
| 等待 3 秒后 `getPairedDevices` 数量 | 0 |
| `getAllDevices` 数量 | 0 |
| 活动设备 / 目录属性 | 均未取得 |
| 同次 Mac `companion_proxy / GetDeviceRegistry` 对照 | 1 条登记记录 |

因此，此结果不能解释为手机没有配对手表；也没有支持继续等待初始化或要求重连的证据。

对同一 **iOS 27.0.1 / `24A446`** NanoRegistry 的进一步静态核对：

- `NRRegistryProxy.xpcGetDeviceCollectionWithBlock:` 位于 `0x23d2eabd8`。
  `0x23d2eac00` 调用的跳板 `0x24005c350` 已解析为 `hasEntitlements`，
  其结果被保存并传入最终回调。
- 最终回调 `0x23d2ead98` 在权限位为真时返回集合；否则在 `0x23d2eadc4` 分支
  把两个集合参数设为 nil，把权限结果设为 false。
- `NRXPCProxy.hasEntitlements`，`0x23d2eec14`，检查权限位掩码是否非零。
  `NRRegistryProxy.entitlements` 登记的权限包含 `com.apple.nano.nanoregistry`、
  `com.apple.nano.nanoregistry.generalaccess` 等；本探针的 `.xcent` 签名输入没有这些权限。
- `NRRegistryProxy.requireAnEntitlement` 返回 false，只涉及连接层要求；
  不能由此认为集合读取没有权限守卫。客户端收到无权限标志后还会进入
  `_warnAboutMissingEntitlement`，但其日志输出受额外条件限制。

以上是**静态代码事实与实机结果的交叉验证**，不是捕获到明确服务端拒绝消息。
一次 18 秒的有限采样中，日志流和探针启动均成功，观察到 4 条本探针的 NanoRegistry 日志，
两个已知缺权限警告均未命中；后续一次采样中探针启动失败，没有取得补充日志。
未保留原始设备日志，未用未命中的日志来证明权限允许或拒绝。

当前判断：普通开发 App 直接查询 NanoRegistry 的路线不具备继续读取目录的条件。
没有尝试添加未被开发配置授予的 Apple 私有权限，未调用登记或卡包写入接口。

后续转向已能读取登记记录的 Mac 服务。已确认本机 MobileDevice 中
`CPXCopyValueFromPairedDevice` 使用 `GetValueFromRegistry` / `GetValueKeyKey`，
与之前的探针属于同一协议，不能把换用此包装函数当成新的数据访问能力。
当前已提取的 `CompanionServices` 与 `liblockdown.dylib` 中未定位到这一请求处理器，
尚无可用字段清单、真实手表目录或已验证的导出命令。
