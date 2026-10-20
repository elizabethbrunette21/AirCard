# 项目记忆

更新日期：2026-10-20。本文是衔接工作的状态快照，不代表设备此刻仍处于相同状态。

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
| 卡片位置 | 用户最后报告在 iPhone；实机写入前需重新确认 |

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
  尚未验证这个流程在 **27.0.1** 上的实现、调用权限及向手表更新图片的效果。
- 后续对 **iOS / watchOS 26.5 模拟器运行时**的静态分析，定位了支付卡的现行同步链：
  手机 `NPDCompanionPassSyncService` 读取按手表保存的 `NanoPasses/PaymentCards`，
  经同步引擎发送卡包；手表 `NPKStandaloneWatchPassSyncService` 将完整卡包交给
  `PKPassLibrary.addUnsignedPassesAtURLs`。这还不是目标实机的可调用入口。
- 直接保存和 unsigned 导入均有 Apple 私有权限检查。
  数据库变化通知为进程内 `NSNotificationCenter` 通知，不能用 Darwin 通知替代。
- 同步状态包含资源清单哈希；只替换 PNG 可能不触发更新。
  `_handleUpdateAndSendToGizmoForPass` 是会被 standalone 分支跳过的旧发送路径，
  不再将它作为当前 Watch 的实现依据。
- 本轮后半段获得设备服务访问权限后的两次枚举均为空，尚未运行当前系统的符号清单请求。
  已请求用户确认实时连接与解锁；没有把原因断定为线缆断开。

## 当前阻碍与下一步

已定位系统内部更新链，仍缺少经过目标实机验证、AirCard 能触发的入口。下一步依次确认：

1. 恢复手机实时连接，核实 iOS 27.0.1 的对应实现和配对设备目录值。
2. 取得属于手表的卡包副本与恢复依据；不能用手机卡包覆盖手表卡包。
3. 验证图像及资源清单的变更能否经系统正常的库变化事件或服务初始化扫描触发同步。
4. 前三项具备条件后，开展单卡、单图的最小实机验证；不改业务版本或支付资料。

目前需要恢复实时连接；无需重复打开钱包页面、转卡或重启。
详细调用链、版本依据和限制见 [同步入口分析](docs/WATCH-SYNC-ENTRY.md)，
历史实验见 [研究记录](docs/WATCH-RESEARCH.md)。

## 本地研究材料

原工作区在仓库外的 `../watch-research/` 留有：

- `companion_probe.m`：配对登记查询及响应校验，不含卡面写入。
- `observe_watch.py`：有限时长的手机日志摘要采集。
- `findings.json`：已脱敏的环境、观察结果与静态分析摘要。
- `symbols_probe.m`：只查询设备可提供的符号文件清单，已编译；尚未执行服务请求。

这些材料没有纳入本 fork，新克隆不保证存在。可共享的事实已整理到研究记录。
尚未通过这些工具转移卡片、修改卡面或验证 Watch 文件访问；原始设备日志未保存。
