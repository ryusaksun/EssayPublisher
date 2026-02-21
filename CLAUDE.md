# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概要

**Ogygia** — 将文字和图片发布到 Astro 静态博客（GitHub 仓库）的 iOS 客户端。UI 风格为深色聊天界面（类似 Claude iOS App）。100% Apple 原生技术栈，零第三方依赖。

- **平台**: iOS 17.0+（iPhone + iPad）
- **语言**: Swift 5, SwiftUI
- **项目配置**: XcodeGen（`project.yml` 是唯一真实来源，`.xcodeproj` 由其生成）

## 构建命令

```bash
xcodegen generate                    # 修改 project.yml 后重新生成 .xcodeproj
xcodebuild -project EssayPublisher.xcodeproj -scheme EssayPublisher -configuration Debug build
open EssayPublisher.xcodeproj        # Xcode 打开
```

当前无测试目标。需要时在 `project.yml` 中添加 test target 并创建 `EssayPublisherTests/`。

## 架构（MVVM + Actor）

```
Views (SwiftUI struct)
  ↓ @StateObject / @ObservedObject
ViewModels (@MainActor ObservableObject)
  ↓ await
Services (actor 单例, .shared)
  ↓
Models (struct, Codable, Sendable)
```

- **Views** — 纯声明式 UI，不含业务逻辑
- **ViewModels** — `ComposeViewModel`（发布+聊天历史）、`SettingsViewModel`（配置+Token验证）
- **Services** — 全部为 `actor` 单例保证线程安全：`GitHubService`（REST API CRUD）、`ImageService`（HEIC→WebP 转换+压缩）、`EssayService`（列表拉取+双层缓存）
- **Models** — 纯值类型：`Essay`、`AppConfig`（含 KeychainHelper）、`Metadata`、`ContentType`、`GitHubModels`

## 核心发布流程

1. 用户输入文字/选图 → `ComposeViewModel.publish()`
2. 乐观插入 pending 气泡 → 清空输入框
3. `ImageService` 转换压缩图片 → `GitHubService` 上传到图床仓库 → 返回 CDN URL
4. 组装 frontmatter + markdown → `GitHubService.publishContent()` 写入内容仓库
5. 更新气泡状态 + 追加系统回执 + 保存本地历史

## 数据存储

| 数据 | 位置 |
|---|---|
| GitHub Token | Keychain（通过 `KeychainHelper`） |
| Owner/Repo/Branch/ImageRepo/CDN | UserDefaults |
| 发布历史 | Documents/`local_history_v2.json` |
| Essay 列表缓存 | Caches/`essays_cache.json`（内存5min + 磁盘24h） |
| Onboarding 状态 | @AppStorage `onboarding_completed` |

## 编码规范

- 4空格缩进，每文件一个主要类型
- `PascalCase` 类型名，`camelCase` 方法/属性名
- UI 状态放 ViewModels，网络/存储放 Services，纯数据放 Models
- 用 `// MARK:` 分隔大文件中的逻辑区块
- iOS 26 Liquid Glass 特性通过 `#available(iOS 26, *)` 检测并降级
- Token 必须走 `KeychainHelper`，禁止硬编码
