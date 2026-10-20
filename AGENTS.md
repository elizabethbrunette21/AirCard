# 项目协作规则

## 开始工作

先读 [MEMORY.md](MEMORY.md)，了解当前状态；涉及范围和路线时读
[项目简介](docs/PROJECT.md)，涉及设备或同步机制时读
[研究记录](docs/WATCH-RESEARCH.md)。
历史记录用于衔接工作，不能覆盖用户最新的指示。

## 项目目标

让 Apple Watch 原生钱包中的武汉交通卡显示用户选择的新卡面。
当前处于可行性研究阶段，尚无已验证的手表卡面写入方案。

- 首个验证组合是 iPhone 13 / iOS 27.0.1 与 Apple Watch Series 10 / watchOS 26.6。
- 优先验证 iPhone 端面向手表的支付卡资料保存与更新通路。
- 先完成一次最小实机验证，再将已验证的流程整合进 AirCard。
- 自动保持跨设备转移后的卡面、批量管理、多设备兼容不属于当前交付范围。
- 独立图片展示、表盘图片、App 内预览不能代替原生钱包中的真实卡面。

## 协作方式

- 默认用中文沟通，直接说明结果、证据和下一步。
- 使用普通、与功能有关的命名，不给分支、文件或产品擅自加助手品牌前缀。
- 当前开发分支为 `watch-card-artwork`；`origin` 是个人 fork，`upstream` 是原项目。
- 在已有授权范围内推进；发现缺少必要信息时，只问影响下一步的问题。
- 复用现有实现。不要在通路尚未验证时搭建大规模抽象、兼容层或产品界面。
- 保留上游署名和许可证；描述本分支能力时区分上游功能与本分支实测结果。

## 证据与设备操作

- 将结论标为源码事实、实机观察、用户反馈或待验证假设，并注明系统版本。
- 识别到手表、读到配对记录、API 返回成功，都不能单独证明卡面已更新。
- 旧版系统框架只提供线索；方法名存在不代表第三方进程有权调用。
- 不把猜测路径写成确认路径，不以移除 `TargetGate` 的机型检查代替 Watch 支持。
- 注意：`apply_card_skin.read_file()` 会移动原文件，再尝试恢复，**不是只读读取**。
  不用它对未知的真实钱包文件进行“只读探测”。
- 设备写入前，应明确目标设备、目标卡片、已验证的路径及失败恢复方式。
  仅修改实现卡面功能所需的图像资源，不扩展到余额、支付凭证或 Secure Element 数据。
- 设备连接状态会变化。沙箱内枚举失败时，区分工具访问受限与设备实际断开。
- 不提交 UDID、序列号、卡片唯一标识、配对文件、令牌、完整设备日志或 Apple 系统二进制。
  实验记录保留必要的版本、步骤、脱敏结果和限制。

## 代码入口

| 文件 | 职责 |
| --- | --- |
| [AirCardApp.swift](AirCardApp.swift) | macOS 界面、卡片选择和换卡面调用 |
| [aircard_backend.py](aircard_backend.py) | 图片准备、资源写入和缓存清理 |
| [card_assets.py](card_assets.py) | 卡面资源生成 |
| [apply_card_skin.py](apply_card_skin.py) | AirLift 文件操作；包括带移动和恢复语义的读取 |
| [Sources/device_helper.m](Sources/device_helper.m) | 设备发现、会话、日志与文件操作 |
| [Sources/airtraffic_host.m](Sources/airtraffic_host.m) | AirTraffic Books 同步流程 |
| [wallet_catalog.py](wallet_catalog.py) | Mac 本地钱包缓存解析，不是设备实时清单 |

## 验证与交接

从仓库根目录执行与改动对应的检查：

```sh
# 仅构建设备辅助程序
make build/device_helper

# 修改卡面写入流程时，运行对应的离线测试
python3 -m unittest discover -s tests -p 'test_card_flash.py'

# 修改设备发现逻辑时，运行对应测试
python3 -m unittest discover -s tests -p 'test_device_discovery.py'
```

这些单元测试不能证明 Watch 实机支持。新增底层非平凡逻辑时提供能检出实际失败的最小检查。
只改文档时检查链接、事实一致性、敏感信息和 `git diff --check`，不为此运行整套设备实验。
完整打包用 `bash build.sh`；该脚本先清理 `build/`，只在需要验证打包时运行。

每次取得新证据或改变路线后，更新研究记录和 `MEMORY.md` 中的状态、限制与下一步。
不要把计划写成完成，不把失败样本推广成所有版本都不支持。
