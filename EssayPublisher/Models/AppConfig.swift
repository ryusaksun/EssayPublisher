//
//  AppConfig.swift
//  EssayPublisher
//

import Foundation
import Security

/// 应用配置
struct AppConfig: Sendable {

    // MARK: - GitHub 配置（内容仓库）

    nonisolated static var githubToken: String {
        KeychainHelper.get(key: "github_token") ?? ""
    }

    nonisolated static var githubOwner: String {
        UserDefaults.standard.string(forKey: "github_owner") ?? "ryusaksun"
    }

    nonisolated static var githubRepo: String {
        UserDefaults.standard.string(forKey: "github_repo") ?? "astro_blog"
    }

    nonisolated static var githubBranch: String {
        UserDefaults.standard.string(forKey: "github_branch") ?? "main"
    }

    // MARK: - 图床配置（图片仓库）

    nonisolated static var imageRepo: String {
        UserDefaults.standard.string(forKey: "image_repo") ?? "picx-images-hosting"
    }

    nonisolated static var imageBranch: String {
        let value = UserDefaults.standard.string(forKey: "image_branch")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty {
            return githubBranch
        }
        return value
    }
    nonisolated static let imagePath = "images"

    nonisolated static var cdnType: String {
        UserDefaults.standard.string(forKey: "cdn_type") ?? "jsdelivr"
    }

    // MARK: - 图片压缩配置

    nonisolated static let maxImageWidth: CGFloat = 1920
    nonisolated static let maxImageHeight: CGFloat = 1080
    nonisolated static let imageQuality: CGFloat = 0.85
    nonisolated static let maxFileSize: Int = 5 * 1024 * 1024
    nonisolated static let imageCompressionThreshold: Int = 10 * 1024 * 1024

    // MARK: - 缓存配置

    nonisolated static let essayCacheValidity: TimeInterval = 5 * 60
    nonisolated static let essayLocalCacheValidity: TimeInterval = 24 * 60 * 60

    // MARK: - API

    nonisolated static let githubAPIBaseURL = "https://api.github.com"

    // MARK: - 辅助方法

    nonisolated static var isGitHubConfigured: Bool {
        let token = githubToken
        return !token.isEmpty &&
        token != "YOUR_GITHUB_TOKEN_HERE" &&
        !githubOwner.isEmpty &&
        !githubRepo.isEmpty
    }

    nonisolated static var isImageServiceConfigured: Bool {
        isGitHubConfigured && !imageRepo.isEmpty
    }

    nonisolated static func generateImageCDNUrl(path: String) -> String {
        switch cdnType {
        case "jsdelivr":
            return "https://cdn.jsdelivr.net/gh/\(githubOwner)/\(imageRepo)@\(imageBranch)/\(path)"
        case "statically":
            return "https://cdn.statically.io/gh/\(githubOwner)/\(imageRepo)/\(imageBranch)/\(path)"
        default:
            return "https://raw.githubusercontent.com/\(githubOwner)/\(imageRepo)/\(imageBranch)/\(path)"
        }
    }

    @discardableResult
    nonisolated static func saveGitHubToken(_ token: String) -> Bool {
        KeychainHelper.save(key: "github_token", value: token)
    }

    @discardableResult
    nonisolated static func deleteGitHubToken() -> Bool {
        KeychainHelper.delete(key: "github_token")
    }

    nonisolated static func saveRepoConfig(owner: String, repo: String, branch: String) {
        UserDefaults.standard.set(owner, forKey: "github_owner")
        UserDefaults.standard.set(repo, forKey: "github_repo")
        UserDefaults.standard.set(branch, forKey: "github_branch")
    }

    nonisolated static func saveImageConfig(imageRepo: String, cdnType: String, imageBranch: String? = nil) {
        UserDefaults.standard.set(imageRepo, forKey: "image_repo")
        UserDefaults.standard.set(cdnType, forKey: "cdn_type")
        if let imageBranch {
            let clean = imageBranch.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty {
                UserDefaults.standard.removeObject(forKey: "image_branch")
            } else {
                UserDefaults.standard.set(clean, forKey: "image_branch")
            }
        }
    }

    nonisolated static func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: "github_owner")
        UserDefaults.standard.removeObject(forKey: "github_repo")
        UserDefaults.standard.removeObject(forKey: "github_branch")
        UserDefaults.standard.removeObject(forKey: "image_repo")
        UserDefaults.standard.removeObject(forKey: "image_branch")
        UserDefaults.standard.removeObject(forKey: "cdn_type")
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {

    @discardableResult
    nonisolated static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.ryuichi.essaypublisher",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    nonisolated static func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.ryuichi.essaypublisher",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    @discardableResult
    nonisolated static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.ryuichi.essaypublisher"
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
