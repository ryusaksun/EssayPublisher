# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概要

**Ogygia** — 将文字和图片发布到 Astro 静态博客（GitHub 仓库）的 iOS 客户端。UI 风格为深色聊天界面（类似 Claude iOS App）。100% Apple 原生技术栈，零第三方依赖。

- **平台**: iOS 17.0+（iPhone only, `TARGETED_DEVICE_FAMILY: "1"`）
- **语言**: Swift 5, SwiftUI
- **项目配置**: XcodeGen（`project.yml` 是唯一真实来源，`.xcodeproj` 由其生成）
- **认证**: GitHub OAuth Web Application Flow（`ASWebAuthenticationSession`）
- **本地化**: 简体中文 / English，运行时切换（`LanguageManager` + `.lproj/Localizable.strings`）

## 构建命令

```bash
xcodegen generate                    # 修改 project.yml 后重新生成 .xcodeproj
xcodebuild -project EssayPublisher.xcodeproj -scheme EssayPublisher -configuration Debug -destination 'generic/platform=iOS' build
open EssayPublisher.xcodeproj        # Xcode 打开
```

安装到真机（先用 `xcrun devicectl list devices` 获取设备 ID）：
```bash
xcrun devicectl device install app --device <DEVICE_ID> /Users/ryuichi/Library/Developer/Xcode/DerivedData/EssayPublisher-eonfxtdmbahiwkgdtraorblmedhw/Build/Products/Debug-iphoneos/EssayPublisher.app
```

`project.yml` 中已定义 `EssayPublisherTests` target，但测试目录 `EssayPublisherTests/` 尚未创建。

## 认证与密钥管理

- **GitHub OAuth**: 通过 `OAuthService`（`ASWebAuthenticationSession`）完成授权，URL Scheme `ogygia://oauth/callback`
- **OAuth 凭据**: 存放在 `Secrets.swift`（已 gitignore），包含 `Secrets.githubClientID` 和 `Secrets.githubClientSecret`
- **新开发者设置**: 复制 `Secrets.example.swift` → `Secrets.swift`，填入从 GitHub OAuth App 获取的凭据
- **Info.plist**: 手动维护（注册 URL Scheme），通过 `INFOPLIST_FILE` 与 `GENERATE_INFOPLIST_FILE: YES` 共存

## 架构（MVVM + Actor）

```
Views (SwiftUI struct)
  ↓ @StateObject / @ObservedObject
ViewModels (@MainActor ObservableObject)
  ↓ await
Services (actor / @MainActor 单例, .shared)
  ↓
Models (struct, Codable, Sendable)
```

- **Views** — 纯声明式 UI，不含业务逻辑
- **ViewModels** — `ComposeViewModel`（发布+聊天历史）、`SettingsViewModel`（配置+OAuth 授权）
- **Services** — `GitHubService`（actor, REST API CRUD）、`ImageService`（actor, HEIC→WebP 转换+压缩）、`EssayService`（actor, 列表拉取+双层缓存）、`OAuthService`（@MainActor, GitHub OAuth 流程）、`LanguageManager`（@MainActor, 运行时语言切换）
- **Models** — 纯值类型：`Essay`、`AppConfig`（含 KeychainHelper）、`Metadata`、`ContentType`、`GitHubModels`

## 本地化（i18n）

- 字符串资源：`Resources/zh-Hans.lproj/Localizable.strings` 和 `Resources/en.lproj/Localizable.strings`
- 所有 UI 字符串使用 `"key".localized` 扩展（定义在 `LanguageManager.swift`）
- `LanguageManager` 通过 `@EnvironmentObject` 注入根视图，语言变更触发 SwiftUI 重新渲染
- **线程安全**：`String.localized` 调用 `LanguageManager.resolve()`（`nonisolated static`），直接从 UserDefaults 读取语言偏好构造 Bundle，可在任意 actor 中安全调用。**不要**在 `nonisolated` 上下文中访问 `LanguageManager.shared` 或其实例属性
- Key 命名规则：`{feature}.{context}`，如 `settings.displayName`、`onboarding.loginWithGitHub`、`error.oauth.tokenFailed`
- 添加新字符串时须同时更新两个 `.strings` 文件

## 核心发布流程

1. 用户输入文字/选图 → `ComposeViewModel.publish()`
2. 乐观插入 pending 气泡 → 清空输入框
3. `ImageService` 转换压缩图片 → `GitHubService` 上传到图床仓库 → 返回 CDN URL
4. 组装 frontmatter + markdown → `GitHubService.publishContent()` 写入内容仓库
5. 更新气泡状态 + 追加系统回执 + 保存本地历史

## 数据存储

| 数据 | 位置 |
|---|---|
| GitHub Token | Keychain（通过 `KeychainHelper`，key: `github_token`） |
| GitHub Username / DisplayName | UserDefaults（`github_username` / `display_name`） |
| Owner/Repo/Branch/ImageRepo/CDN | UserDefaults |
| 语言偏好 | UserDefaults（`app_language`） |
| 发布历史 | Documents/`local_history_v2.json` |
| Essay 列表缓存 | Caches/`essays_cache.json`（内存5min + 磁盘24h）+ `essays_recent_cache.json` |
| Onboarding 状态 | @AppStorage `onboarding_completed` |

## 编码规范

- 4空格缩进，每文件一个主要类型
- `PascalCase` 类型名，`camelCase` 方法/属性名
- UI 状态放 ViewModels，网络/存储放 Services，纯数据放 Models
- 用 `// MARK:` 分隔大文件中的逻辑区块
- iOS 26 Liquid Glass 特性通过 `#available(iOS 26, *)` 检测并降级
- Token 必须走 `KeychainHelper`，禁止硬编码
- `print()` 调试语句须包裹在 `#if DEBUG` 中
- OAuth 凭据放 `Secrets.swift`（gitignore），不得提交到仓库
