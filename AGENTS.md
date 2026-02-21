# Repository Guidelines

## Project Structure & Module Organization
- `EssayPublisher/` is the app source root, split by responsibility:
  - `App/` app entry and theme (`EssayPublisherApp.swift`, `Theme.swift`)
  - `Models/` domain/config models (`Essay`, `Metadata`, `AppConfig`)
  - `ViewModels/` state + orchestration logic (`ComposeViewModel`, `SettingsViewModel`)
  - `Views/` SwiftUI screens/components
  - `Services/` side-effect boundaries (GitHub API, image upload, parsing)
  - `Resources/Assets.xcassets/` app icons and colors
- `project.yml` is the source of truth for project configuration (XcodeGen).
- `EssayPublisher.xcodeproj` is generated/maintained project metadata.
- `build/` contains local build artifacts and should stay out of commits.

## Build, Test, and Development Commands
- `xcodegen generate` regenerates `EssayPublisher.xcodeproj` after editing `project.yml`.
- `xcodebuild -project EssayPublisher.xcodeproj -scheme EssayPublisher -configuration Debug build` builds from CLI.
- `xcodebuild -project EssayPublisher.xcodeproj -scheme EssayPublisher -destination 'platform=iOS Simulator,name=iPhone 16' test` runs tests once a test target exists.
- `open EssayPublisher.xcodeproj` opens the project in Xcode for interactive run/debug.

## Coding Style & Naming Conventions
- Swift 5 + SwiftUI, 4-space indentation, one primary type per file.
- Use `PascalCase` for types (`GitHubService`), `camelCase` for methods/properties (`publishContent`).
- Keep UI state in `ViewModels`, network/storage in `Services`, and pure data in `Models`.
- Use `// MARK:` to separate sections in larger files.

## Testing Guidelines
- No XCTest target is currently present; add `EssayPublisherTests/` when introducing tests.
- Mirror production paths in tests (e.g., `Services/GitHubService.swift` -> `EssayPublisherTests/Services/GitHubServiceTests.swift`).
- Prefer behavior-first names like `test_generateFilePath_addsRandomSuffix()`.
- Prioritize coverage for path generation, metadata/frontmatter assembly, and GitHub request error handling.

## Commit & Pull Request Guidelines
- Git history is unavailable in this workspace snapshot (`.git` missing), so follow Conventional Commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`.
- Keep commits focused and scoped to one change set.
- PRs should include: purpose, user-visible changes, manual test steps, and screenshots for UI updates.
- If permissions/config are touched (camera, photos, token storage), call that out explicitly in the PR description.

## Security & Configuration Tips
- Never hardcode GitHub tokens; use `KeychainHelper` via `AppConfig`.
- Treat `UserDefaults` repo/branch settings as environment-specific and document defaults in PRs when changed.
- Do not commit provisioning data, derived files, or anything under `build/`.
