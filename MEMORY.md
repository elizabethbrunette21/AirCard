# 项目记忆

更新日期：2026-10-21。本文是衔接工作的状态快照，不代表设备此刻仍处于相同状态。

## 目标与范围

唯一当前交付目标：让 Apple Watch 原生钱包中的武汉交通卡显示新卡面。
用户已明确缩小范围：暂不研究卡片在 iPhone / Watch 之间转移后的自动保持或重新应用。
用户要求使用普通功能命名；分支已统一为 `watch-card-artwork`。

## 仓库

- 个人 fork：[elizabethbrunette21/AirCard](https://github.com/elizabethbrunette21/AirCard)，对应 `origin`。
- 上游：[Mak5er/AirCard](https://github.com/Mak5er/AirCard)，对应 `upstream`。
- 开发分支：`watch-card-artwork`，已建立远端跟踪关系。
- 开始研究时的上游基线：`52ba05dca4bdc590672c19d554701f4438e20338`。
- Watch 功能尚未实现、尚未实机验收，没有向上游提交 Watch 功能 PR。
- 本轮建立了项目文档；原有产品代码尚未因 Watch 研究而修改。

## 首个验证环境

| 项目 | 记录 |
| --- | --- |
| iPhone | iPhone 13，设备型号 `iPhone14,5` |
| iOS | 27.0.1，构建号 `24A446` |
| Apple Watch | Series 10，设备型号 `Watch7,9` |
| watchOS | 26.6，构建号 `23U67` |
| 交通卡 | 武汉交通卡 |
| 卡片位置 | 用户于 2026-10-21 再次确认在 iPhone；本轮没有转卡 |

## 已确认

- `device_helper` 构建成功；iPhone USB 连接及系统版本已读取。
- 最初设备枚举失败与沙箱内访问限制有关，后续设备服务访问成功；不能据此反复要求用户换线。
- `com.apple.companion_proxy` 的 `GetDeviceRegistry` 返回一个配对设备记录。
  这只证明登记信息可读，不证明手表文件可读写。
- 用户打开过 iPhone 的 Watch → 钱包与 Apple Pay 页面。
  日志采样观察到 `Bridge` / `passd` 活动，没有得到已验证的手表卡面路径。
- AirCard 的写入器只接受 `iPhone` 产品类型，写入流程依赖 Books 同步。
- 本机缓存的 iOS **26.6.1** NanoPassKit 框架提供了按手表保存支付卡资料的线索；
  保存函数会取得 `archiveData`，再调用远程对象的
  `savePaymentPassData:withUniqueID:forPairingID:completion:`。
  后续已核实 **27.0.1** 客户端的同一调用，见下；调用权限及手表实际采用图片仍未验证。
- 后续对 **iOS / watchOS 26.5 模拟器运行时**的静态分析，定位了支付卡的现行同步链：
  手机 `NPDCompanionPassSyncService` 读取按手表保存的 `NanoPasses/PaymentCards`，
  经同步引擎发送卡包；手表 `NPKStandaloneWatchPassSyncService` 将完整卡包交给
  `PKPassLibrary.addUnsignedPassesAtURLs`。这还不是目标实机的可调用入口。
- 直接保存和 unsigned 导入均有 Apple 私有权限检查。
  数据库变化通知为进程内 `NSNotificationCenter` 通知，不能用 Darwin 通知替代。
- 同步状态包含资源清单哈希；只替换 PNG 可能不触发更新。
  `_handleUpdateAndSendToGizmoForPass` 是会被 standalone 分支跳过的旧发送路径，
  不再将它作为当前 Watch 的实现依据。
- 2026-10-20 后半段获得设备服务访问权限后的两次枚举均为空，当时未运行符号清单请求。
  没有把原因断定为线缆断开；后续连接结果见下。
- 2026-10-21 在独立 Watch 模拟器上调用实际 NanoPassKit 同步引擎，验证了：
  同业务版本的新资源清单哈希被识别为更新，无冲突时允许应用；更高的本地业务版本会阻止覆盖。
  保留旧哈希的对照组不会被识别为更新。仅使用合成内存对象，没有导入钱包或发送 IDS 消息。
  工具位于 `tools/watch-research/`；临时模拟器已清理。
- 2026-10-21 较早一次检查没有检测到 iPhone；本机备份元数据访问被系统拒绝，未读取备份内容。
- 2026-10-21 用户再次询问后，已恢复实时检测：iPhone 13 / iOS 27.0.1 / `24A446`，
  CoreDevice 为 `wired` / `connected` / `paired`，手机开发者模式已开启。
  只读 `ddiServices --no-auto-mount-ddis` 返回当前 DDI 可用且兼容。
  配对登记查询仍返回 1 条记录。无需再要求用户换线或开启手机开发者模式。
- 同次实机检查，直接 lockdown 启动 `com.apple.dt.fetchsymbols` 返回
  `-402653150` / `0xe8000022`，系统错误文本为 `The service is invalid.`。
  未取得符号清单；不能据此排除通过现代开发服务获取符号的方式。
- 新增只读 `tools/watch-research/companion_values_probe.m`，编译、自检和实机查询均完成。
  `GetValueFromRegistry` 查询 `productType`、`systemVersion`、`localPairingDataStorePath`
  均收到 `UnsupportedWatchKey`。这条按 NanoRegistry 字段名查询的路线没有提供目录。
- 2026-10-21 后续推进：pymobiledevice3 11.40.2 已安装到隔离环境，降低下载并发后安装成功。
  新探针 `tools/watch-research/remote_symbols_probe.py` 通过已有信任的用户态开发通道，
  在目标 iOS 27.0.1 上成功调用 `com.apple.dt.remoteFetchSymbols`，读到 82 个文件、
  共 7,209,702,576 字节。完整缓存已复制到 Git 忽略目录，三个目标框架已提取并核对软件 UUID。
  此结果只证明系统分析材料可读，不是手表卡面更新入口。
- 当前 iOS 27.0.1 的 `NPKHomeDirectoryPathForDevice` 仍读取
  `NRDevicePropertyLocalPairingDataStorePath` 并追加 `NanoPasses`，支付卡目录再追加 `PaymentCards`。
  `_savePaymentPass:atURL:forDevice:completion:` 仍获取 `archiveData`、`uniqueID` 和手表 pairing ID，
  交给远程保存对象。这里只验证了当前手机框架的客户端实现，没有取得真实目录或服务端权限。
- 已构建、签名并在手机安装独立只读 App `dev.aircard.WatchRegistryProbe`。
  修复 iOS 27 对 UIScene 生命周期的要求后，首次查询正常结束：框架和登记对象可用，
  `getActivePairedDevice` 返回空，未取得目录。不能据此认定手机没有配对手表或所有读取方式均无权限。
  新版增加配对列表数量和一次 3 秒初始化等待，用户解锁后已完成复核：初始配对、等待后配对、
  全部设备数量均为 0，活动设备与目录仍为空。同次 Mac companion 查询返回 1 条登记记录。
  App 只向自身容器写诊断结果，没有读卡包或调用保存接口。
- 已核对当前 NanoRegistry 的 `NRRegistryProxy.xpcGetDeviceCollectionWithBlock:`：
  它把 `hasEntitlements` 的结果带入回调；无权限分支返回空集合及 false。
  本探针的签名输入没有 NanoRegistry 权限。此静态证据与实机空结果一致，
  但有限日志采样没有捕获到明确权限拒绝文本，不把静态判断写成已收到服务错误。
  普通开发 App 直接读取登记目录的路线未打通，继续重复启动或等待没有新依据。

## 当前阻碍与下一步

已定位部分系统内部更新链，仍缺少经过目标实机验证、AirCard 能触发的入口。
用户要求明确安排，已将步骤、验收和停止条件写入
[当前执行安排](docs/PROJECT.md#当前执行安排2026-10-21)。按以下顺序推进：

1. 下一轮限于两项检查：从 Mac companion 的实际调用与请求构造寻找有依据的数据访问候选；
   核对当前 iOS 的保存、库变化和初始化扫描，寻找可触发同步的动作。先给具体依据，再运行相应探针。
   每项产出服务与请求、权限、返回或观察结果以及剩余缺口；目录字符串不等于文件可读写。
   `CPXCopyValueFromPairedDevice` 已确认使用相同 `GetValueFromRegistry` 协议，换封装不是新入口。
   不重复已拒绝的三个字段、普通 App 的空登记查询，不自填 Apple 私有权限。
   当前系统缓存已取得，隔离客户端位于 `.tmp/watch-research-env`，不必重新下载。
2. 候选成立后，验证访问范围、工具恢复语义和同步观察方法。具备前置条件后才安排转卡，
   并取得转卡后属于当前手表的原始卡包与恢复副本；不能用手机卡包或历史缓存代替。
3. 完成单卡、单图实验：图片及必要清单更新、读回、触发同步、手表原生钱包验收。
   不改业务版本或支付资料；未取得原始资料和恢复依据前不写入。
4. 实机成功后才整合 AirCard、打包和准备功能补丁。

如果第一项检查范围内没有得到可用访问候选，就将手机侧路线标为暂时受阻，
评估有具体服务依据的直接 Watch 访问。备选也没有入口时，明确交付阻碍与重新研究的条件，
停止无依据的重复实验；缺少材料不等于已经证明所有版本不可行。

用户解锁后的关键复核已经完成；当前缺口是可用的数据访问入口，不再等待解锁或初始化。
卡片保留在手机，无需重复打开钱包页面、转卡或重启。
详细调用链、版本依据和限制见 [同步入口分析](docs/WATCH-SYNC-ENTRY.md)，
历史实验见 [研究记录](docs/WATCH-RESEARCH.md)。

## 本地研究材料

当前仓库的 Git 忽略目录还保存：

- `.tmp/system-symbols/24A446/`：目标系统缓存、已提取框架及局部反汇编。
  `cache-path.txt` 记录本机主缓存路径；无需再次下载完整缓存。
- `.tmp/tools/ipsw`：已校验摘要的本地分析器。
- `.tmp/registry-probe-build/`：签名后的独立 iPhone 探针；手机当前已安装最新版。
- `.tmp/registry-probe-result.json`：解锁后的有效复核结果，包含三项设备数量均为 0。

原工作区在仓库外的 `../watch-research/` 留有：

- `companion_probe.m`：配对登记查询及响应校验，不含卡面写入。
- `observe_watch.py`：有限时长的手机日志摘要采集。
- `findings.json`：已脱敏的环境、观察结果与静态分析摘要。
- `symbols_probe.m`：只查询设备可提供的符号文件清单，已编译并执行服务请求；
  当前直接 lockdown 启动方式返回 InvalidService，未进入清单读取。

这些材料没有纳入本 fork，新克隆不保证存在。可共享的事实已整理到研究记录。
尚未通过这些工具转移卡片、修改卡面或验证 Watch 文件访问；原始设备日志未保存。
