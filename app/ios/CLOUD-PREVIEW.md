# 只有 Windows 和 iPhone，如何查看原生版

可以使用 GitHub Actions 的 macOS runner 编译和运行 iOS 模拟器，不要求自己拥有 Mac。先查看真实 SwiftUI 渲染的截图，不需要签名证书或 Apple Developer Program 会员。安装到实体 iPhone 是后续独立步骤，仍需合适的 Apple 签名与分发配置。

## 此次云端预览会做什么

1. 在 GitHub 提供的 Mac 上调用 Xcode，编译工程及原生测试。
2. 原生测试通过 URLProtocol 在内存中读取合成 API 样本，不连接你的 Windows 后端，也不读取 iPhone 健康数据。
3. 在 iOS 模拟器中实际创建并显示现有 SwiftUI 页面，导出登录、小康、健康、计划、我的、健康授权、病历夹和目标复查八个界面。
4. 将截图作为 XCTest 附件保存在 xcresult，再导出为图片与 `index.html` 图库，供 Windows 下载查看。图库展示原生渲染结果，不提供远程操控。
5. 若编译或测试失败，保留 Xcode 日志，修复后再运行。当前尚未完成首次云端编译，截图不能预先保证生成成功。

没有调用 HealthKit 的授权或读取方法，没有 Apple 账号登录，没有 IPA 签名或 TestFlight 上传。界面中的健康记录和成员均为合成测试资料。

## 仓库和运行

建议新建专用的**私有仓库**，如 `jiahe-ios-preview`，创建时可以勾选添加 README。然后提供仓库链接，便于上传这个原生预览包。此包只包含 `app/ios` 源码、合成测试资源及 `.github/workflows/ios-native.yml`；不包含现有数据库、报告附件、`.env`、论文文档或依赖缓存。

工作流名为 **iPhone native preview**，可在 Actions 中手动运行。上传到专用分支 `codex/ios-native-preview` 时也会触发；其他分支上的普通推送不会触发这条预览。

完成后打开运行记录，在 Artifacts 中下载：

- `iPhone-native-screenshots`：解压后打开 `index.html`，也可直接查看图片。
- `iPhone-native-diagnostics`：Xcode 构建日志和原始测试结果，用于排错。

预览使用 GitHub Actions 计算额度，私有仓库的额度与计费取决于你的 GitHub 套餐和设置。工作流设置了 40 分钟超时，下载文件默认保存七天。

## 本地检查和范围

Windows 可运行 `python ios/verify_project.py` 与 Swift 语法解析，但不能替代 Xcode 的 Apple SDK 类型检查。GitHub 连接只代表可以访问获授权仓库，不代表已经上传源码或启动远程构建。

参考：[GitHub 的 macOS runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)、[XCTest 图片附件](https://developer.apple.com/documentation/xctest/xctattachment)、[下载工作流产物](https://docs.github.com/en/actions/tutorials/store-and-share-data)。
