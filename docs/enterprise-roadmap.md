# HyesRead 企业级加固路线

本文档用于区分“已有功能”“已验证能力”和“后续企业级门槛”，避免仅凭功能数量宣称完成。

## 当前技术基线

- 客户端：Next.js + React + Tauri 2，同一前端面向 Windows、Android 与 Web。
- 阅读引擎：继续使用项目现有的 foliate-js/PDF.js 路线，不重写成熟的 EPUB/PDF 渲染层。
- Windows：NSIS `setup.exe`，CI 必须实际安装、启动、卸载后才允许进入发布产物。
- Android：CI 构建 ARM64 APK + AAB；正式 Release 要求同一 keystore 签名，并分别验证 APK 与 AAB。
- 发布完整性：正式 Release 为 EXE、APK、AAB 生成统一 `SHA256SUMS.txt`。
- 数据：默认本地保存；备份 v2 对元数据清单和内嵌书籍分别做 SHA-256 完整性验证；仍兼容旧 v1 备份导入。
- 可诊断性：全局前端异常、本机限额事件记录、原生日志轮换、应用自检和手动诊断报告导出；无自动遥测上传。
- 大书库：搜索采用延迟值避免输入阻塞，书架按 84 本渐进挂载，封面懒加载；浏览器书籍恢复使用单个 IndexedDB 事务批量读取，不再每本书单独打开数据库。
- 数据演进：`hyes_system.json` 维护 schema version；当前 schema 1 只做幂等、非破坏的数据规范化，为后续 SQLite 迁移建立版本边界。
- Windows 目录扫描：后台线程解析、每 32 本提供预览、支持取消；取消与部分失败保留已有记录。范围与限制见 [本机书库扫描](library-scanning.md)。

## 开源参考与采用边界

| 项目 | 用途 | 采用策略 |
| --- | --- | --- |
| [foliate-js](https://github.com/johnfactotum/foliate-js) | EPUB/电子书阅读引擎 | MIT，可继续直接作为技术基础并保留许可证要求。 |
| [Readium Architecture](https://github.com/readium/architecture) | 出版物解析、Streamer/Navigator 解耦 | BSD-3-Clause；吸收模块边界，逐步把解析、书库与阅读导航分离。 |
| [Thorium Reader](https://github.com/edrlab/thorium-reader) | Readium 桌面阅读器、无障碍、恢复与日志实践 | BSD-3-Clause；重点参考 ARIA、屏幕阅读器、键盘导航、Accessibility Metadata 与恢复体验。 |
| [Komga](https://github.com/gotson/komga) | 大书库、OPDS、重复检测、同步设计 | MIT；可直接借鉴书库健康检查、重复项识别和同步协议边界。 |
| [TanStack Virtual](https://github.com/TanStack/virtual) | 大型列表/网格虚拟化 | MIT；当前先采用无依赖渐进挂载，规模继续扩大时再评估正式虚拟化依赖。 |
| [MiniSearch](https://github.com/lucaong/minisearch) | 浏览器本地全文/模糊搜索 | MIT；当前书名作者搜索保持无依赖，多字段/全文索引需求出现后优先评估。 |
| [Tantivy](https://github.com/quickwit-oss/tantivy) | Rust 本地全文索引 | MIT；若未来要给本地大书库建立正文索引，可作为原生层候选，暂不提前引入。 |
| [Readest](https://github.com/readest/readest) | Tauri 跨平台阅读器、阅读体验、同步/书库产品设计 | AGPL；参考产品结构、交互和测试思路，不直接复制源码到当前项目。 |
| [Koodo Reader](https://github.com/koodo-reader/koodo-reader) | 多平台发布、同步/备份、格式覆盖 | AGPL；仅参考产品能力与发布矩阵。 |
| [BookLore](https://github.com/booklore-app/booklore) | 大型书库、元数据、OPDS、多用户服务端设计 | AGPL；仅参考服务端/书库能力边界。 |
| [Calibre-Web](https://github.com/janeczku/calibre-web) / [Librera](https://github.com/foobnix/LibreraReader) / [Kavita](https://github.com/Kareadita/Kavita) | OPDS、Kobo/设备同步、格式覆盖与书库管理 | GPL；只参考功能和协议行为，不复制源码。 |
| [Librum](https://github.com/Librum-Reader/Librum) | 跨设备书库、收藏/标签、阅读统计 | GPL；只参考交互和同步模型，且当前 Android/iOS 尚未作为成熟客户端基线。 |
| [Tauri SQL](https://github.com/tauri-apps/plugins-workspace/tree/v2/plugins/sql) | SQLite schema/migration | 官方 MIT/Apache 插件；是下一阶段结构化持久层首选候选。 |

任何新依赖在引入前必须检查许可证、维护状态、移动端支持和实际体积；AGPL/GPL 源码不得在未明确接受许可证影响前复制进 HyesRead。

## 企业级验收门槛

### P0：发布与数据安全

- Windows EXE 与 Android APK/AAB 在 CI 中可复现构建；正式发布必须原子化，任一平台失败则不发布。
- Android 正式产物必须签名并验签；keystore 不进入仓库或日志。
- 备份导入必须先做结构、清单摘要、内嵌文件摘要验证，再写入用户数据。
- 升级必须保留旧备份兼容策略和数据迁移测试。
- 崩溃/异常不能造成阅读器整页永久白屏；必须有错误边界和本地诊断入口。

### P1：可靠性与性能

- 10k 书目筛选/排序、10k 实际 TXT 文件与 1k 混合文件扫描夹具已加入；仍需复杂大书、冷启动、网络盘和峰值内存测量。
- 扫描与元数据解析已支持取消和批次预览；继续补充超大书解析上限、权限变化与元数据缓存验收。
- 关键持久化数据逐步从松散 JSON/LocalStorage 迁移到带 schema/migration 的存储层；优先评估 Tauri SQL(SQLite)。
- Windows OPDS 凭据通过独立 Vault 边界保存到 Credential Manager，普通 URL/Store 移除账号密码；包含旧 URL 迁移与同源隔离。细节见[目录账号说明](opds-credentials.md)。Android/网页无 OPDS 入口，未来开放时再接入对应平台安全存储。

### P2：可维护与可运营

- 版本升级建立 schema migration、rollback/backup 前置检查及兼容矩阵。
- Windows 建立签名与更新通道；Android 保持 Play AAB 与站外 APK 两条发布路径。
- PR 新增 Dependency Review：高危漏洞或 AGPL/GPL/SSPL 新依赖直接失败；Release 生成 SPDX JSON SBOM，并继续附 SHA-256 校验文件。
- 可访问性覆盖键盘、屏幕阅读器、触控目标和文字缩放；移动端用真实设备补充 WebView 自动化。

## 明确不做的捷径

- 不因为“能生成 EXE/APK”就称为企业级。
- 不复制许可证不兼容项目的源码来快速堆功能。
- 不把密钥、OPDS 密码、书籍内容或诊断报告自动上传到第三方服务。
- 不用未经数据迁移测试的新数据库直接替换现有用户数据。
