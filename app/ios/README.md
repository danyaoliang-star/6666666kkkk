# 家和 · 完全原生 iPhone App

用户已选择完全原生方案。本目录的 App 使用 SwiftUI 编写界面，Swift Charts 绘制趋势，PDFKit 显示 PDF，系统相机/PhotosPicker/文件选择器导入报告，HealthKit 读取健康数据，URLSession 直接访问既有 FastAPI。App 目标中没有 WebKit、WKWebView 或网页资源，不依赖 Node.js/Vite 运行界面。

**当前状态：原生源码与 Xcode 工程已迁移；Windows 上完成源码语法解析、工程结构和后端接口集成检查。尚未在 Xcode 编译、运行模拟器或安装 iPhone，不应视为已验收的可安装成品。**

## 打开与运行

1. 将整个 `app/ios` 文件夹复制到 Mac，使用 Xcode 16 或更新版本打开 `FamilyHealth.xcodeproj`。工程无第三方 Swift 包和 CocoaPods 依赖，最低系统为 iOS 16。
2. 选择 FamilyHealth scheme。在 Signing & Capabilities 中选择自己的开发团队，将 Bundle Identifier 改成自己拥有的唯一标识，确认 HealthKit capability 已开启。真机健康功能需要支持 HealthKit 的开发者账号及签名配置。
3. 后端继续运行在电脑或服务器上。后端启动方式见下文；正式使用应提供自己的 HTTPS 服务根地址。
4. 在 Xcode 选择 iPhone 模拟器或已连接的真机，点击 Run。首次在登录页「服务器设置」填入家和服务根地址，再用账号密码登录；地址保存后默认收起这项设置。App 不加载该网址的网页界面，仅请求 `/api/v1` 数据接口。部署者也可在 Xcode 的 `HEALTH_API_BASE_URL` 构建设置中预置服务地址，让用户直接登录。
5. 默认优先选择关系为“本人”的档案。若没有成员，在「我的 → 家庭成员」中添加。
6. 在「健康 → 右上角设备与授权」连接 Apple 健康。选择项目并明确同意保存摘要后，才调用 iOS 系统授权；首次流程完成后尝试同步，其后可手动“立即同步”。

Windows 无法运行 Xcode 或完成 iPhone 签名。可先编写与检查源码，最终的 Apple SDK 类型检查、模拟器运行、真机授权和分发需在 Mac 上完成。工程本身不包含签名证书、配置文件或 IPA。

只有 Windows 和 iPhone 时，可以使用 GitHub 的云端 Mac 先编译并生成真实原生界面的截图，不需要先购买 Apple 开发者会员；操作范围和仓库准备见 [云端原生预览](CLOUD-PREVIEW.md)。实体 iPhone 安装仍需单独处理签名。

## 后端和网络

原生 App 复用现有账号、成员、数据库、文件、OCR、模型配置及 `/api/v1` 接口。无需重新上传既有报告或重建档案。原 Vue 网页保留为开发对照，不再是 iPhone 的界面实现。

原生开发可使用新增的 `app/start-backend.ps1`，只启动后端，不构建 Vue 或启动 Vite。脚本默认只监听 `127.0.0.1`，适合本机；iPhone 访问局域网开发服务时，需部署者显式选择 `-LocalNetwork`，手机和电脑位于同一网络，并自行允许相应网络访问。本次工作未修改防火墙或开放网络端口。

已有依赖安装完成时，可在 `app` 目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\start-backend.ps1 -LocalNetwork
```

App 的 Debug 构建允许 `http://192.168.x.x:8000` 等私有地址；Release 构建只接受 HTTPS。**iPhone 上的 `127.0.0.1` 指向手机自己，不能指向 Windows。** Mac 模拟器访问 Windows 时也应使用 Windows 的可达地址。

Debug 的 `Info-Debug.plist` 仅为 URLSession 局域网开发放宽 ATS；Release 的 `Info.plist` 不含 `NSAllowsArbitraryLoads`。客户端拒绝带账号密码、额外路径或查询参数的服务地址，跨来源 HTTP 重定向会被阻止。

服务地址保存在 UserDefaults。账号密码不写入本地持久存储。每次登录创建独立的内存 Cookie 会话，App 进程结束后需要重新登录；正常退出会调用后端注销接口并清空本地会话。网络不可用时退出会提示错误并允许重试。

## 原生迁移清单

下表表示源码与接口连接已编写；各项 iOS UI 与系统交互仍需在 Mac/真机验收。

| 模块 | 原生实现 |
| --- | --- |
| 登录与导航 | SwiftUI 登录、四个底部入口、当前成员切换、会话失效回登录 |
| 家庭成员与授权 | 建档与编辑、独立 read/write/supervise/export 授权和撤销 |
| 健康总览 | 活动、运动、睡眠卡片，步数/心率/体重，复查提醒和健康入口 |
| Apple 健康 | 六类数据的选择、保存同意、系统授权、七天同步、范围修改、停止同步并删除摘要 |
| 健康记录与趋势 | 指标手录、条件筛选、Swift Charts、同条件比较、来源报告链接 |
| 病历夹 | 拍照、照片、文件导入；搜索、OCR 状态更新、回收站和恢复 |
| 原件与报告校对 | PDFKit/原生图片、日期和检测名称修改、候选逐项编辑、人工补充、批量确认入档 |
| 小康 | 历史会话、新会话、问答、报告解读入口、附件回原件、待确认健康记忆 |
| 目标与复查 | 医生目标创建/编辑/停用，复查创建/编辑/完成/取消/恢复 |
| 生活计划与周报 | 制定、逐日打卡、每周统计、可选模型执行建议、下周草稿编辑及确认 |
| 生活建议 | 选择已确认报告、核对活动情况和健康记忆、可选模型筛选、确认七天计划 |
| 健康记忆 | 分类、搜索、有效期、生效/停用/回收站/恢复、逐条模型发送许可 |
| 家庭 Lp(a) 对照 | 成员选择、来源记录选择、关系核实、原有后端提示与参考资料 |
| 复诊导出 | 日期与内容筛选、生成 PDF、iPhone 分享面板选择保存或分享 |

导出 PDF 先写入 App 临时目录并开启文件保护，关闭分享面板时尝试清理。报告预览仅通过已登录 URLSession 读取，未打开另一个浏览器或共享 Cookie。不同账号、成员和权限变化会刷新原生页面上下文，旧响应不得写入新上下文。

## HealthKit 数据约定

- 步数、活动能量、运动时长使用 `HKStatisticsCollectionQuery` 按设备当地日历日累计，避免直接累加手机与手表的原始样本。
- 心率与体重取每日最近一次样本，不表示全天平均值或静息心率。
- 睡眠只计实际睡眠阶段，不计卧床和清醒；按当地零点至次日零点裁剪，并合并重叠时段。与「健康」App 的睡眠日归属可能不同。
- 无数据和读取未允许均保留为空。`errorNoData` 视为空查询结果；其他查询错误不上传新快照。系统授权完成不能用于判断某一类型是否允许读取。
- 最近七天摘要独立保存在现有数据库；不保存逐条 HealthKit 样本，不进入模型问答、检查指标趋势或复诊 PDF。仅导入的本人账号查看，不随家人查看权限共享。
- 一个账号只连接一份由其管理、关系为“本人”的档案。保存同意记录使用版本 `2026-11-16`。每次上传需当前许可标识，修改范围或停止同步会使旧标识失效。
- 同步成功后用所查询窗口替换旧摘要；空读取会移除该窗口旧结果。停止同步会删除本系统摘要，不删除 Apple 健康原件。系统读取许可须由用户在「健康 → 个人头像 → App 和服务 → 家和」中关闭。
- 当前按用户操作同步，未实现后台更新、HealthKit 增量锚点、蓝牙设备直连或华为/小米等厂商授权。

## 验证

### Windows 上已执行

在 `app` 目录使用已安装依赖的 Python：

```powershell
$env:PYTHONPATH = (Join-Path $PWD '.runtime')
python backend/verify_native_contract.py --write-fixtures
python ios/verify_project.py
```

接口集成检查使用独立临时数据库和合成资料，覆盖登录与退出、报告上传/原件/批量入档、目标与复查、打卡与周报、健康记忆、聊天、生活建议、家庭对照、健康同步与撤销、家人权限隔离及复诊 PDF；生成 20 份合成接口响应。不会读取真实资料或请求外部模型。

可选的语法解析工具只装在 `.runtime`，不是 App 依赖：

```powershell
npm.cmd install --prefix .runtime/native-validation --no-save --package-lock=false --ignore-scripts web-tree-sitter@0.20.8 tree-sitter-wasms@0.1.13
node --no-opt --liftoff-only ios/check_swift.mjs
```

`--no-opt --liftoff-only` 避免当前 Node 24 与该旧 WebAssembly 语法包在优化阶段的崩溃。语法解析不验证 SwiftUI/HealthKit 等 Apple SDK 类型，不能当作 Xcode 编译通过。

### Mac 上待执行

```sh
cd app/ios
bash test-ios.sh
```

脚本检查工程、调用 `plutil`，自动选择已安装的 iPhone 模拟器，并运行 `xcodebuild test`。也可通过环境变量 `IOS_SIMULATOR_ID` 指定模拟器。测试包含原生 Codable 与真实后端合成响应的兼容性、动态证据字段、服务地址约束、空值与零值区分、401 会话失效处理。**这些 XCTest 目前未在本 Windows 环境执行。**

仓库另提供 `.github/workflows/ios-native.yml`，支持手动触发，以及专用分支 `codex/ios-native-preview` 上的预览源码推送；可使用 Mac runner 编译、执行原生测试、导出真实 SwiftUI 截图。准备文件本身不会推送或启动构建，首次云端运行仍待执行。重复本地测试时，可通过 `IOS_RESULT_BUNDLE` 指定尚不存在的结果目录。

真机重点验收：相机拒绝/允许、照片及文件导入、PDF 原件、分享导出、网络断开与重试、账号退出和成员切换、逐项健康授权/拒绝全部/没有样本、跨午夜睡眠、重复来源步数、系统撤权、锁屏失败、重复同步和停止后重新连接。

## 维护工程

新增 Swift 或测试 JSON 后执行 `python3 generate_project.py`，即可更新源码引用、测试资源与共享 scheme。该脚本会重新生成工程的构建配置；若你已手动修改开发团队或 Bundle Identifier，重新生成后需重新设置。

官方参考：[SwiftUI](https://developer.apple.com/documentation/swiftui)、[PhotosPicker](https://developer.apple.com/documentation/photosui/photospicker)、[Swift Charts](https://developer.apple.com/documentation/charts)、[HealthKit 授权](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)、[Xcode 运行与签名](https://developer.apple.com/documentation/xcode/building-and-running-an-app)。
