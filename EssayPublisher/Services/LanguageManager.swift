//
//  LanguageManager.swift
//  EssayPublisher
//
//  应用内语言切换管理器

import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case zhHans = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    /// 固定用原生名字显示（不随语言切换变化），仅 .system 需要本地化
    var displayName: String {
        switch self {
        case .system: return "settings.language.followSystem".localized
        case .zhHans: return "简体中文"
        case .english: return "English"
        }
    }
}

@MainActor
final class LanguageManager: ObservableObject {

    static let shared = LanguageManager()

    private static let userDefaultsKey = "app_language"

    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: Self.userDefaultsKey)
            reloadBundle()
        }
    }

    private(set) var bundle: Bundle = .main

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.userDefaultsKey) ?? "system"
        self.currentLanguage = AppLanguage(rawValue: saved) ?? .system
        reloadBundle()
    }

    private func reloadBundle() {
        switch currentLanguage {
        case .system:
            bundle = .main
        case .zhHans, .english:
            if let path = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj"),
               let langBundle = Bundle(path: path) {
                bundle = langBundle
            } else {
                bundle = .main
            }
        }
    }

    nonisolated func localizedString(_ key: String) -> String {
        Self.resolve(key)
    }

    /// 线程安全：直接从 UserDefaults 读取语言偏好并构造 Bundle，可在任意线程调用
    nonisolated static func resolve(_ key: String) -> String {
        resolveBundle().localizedString(forKey: key, value: nil, table: nil)
    }

    private nonisolated static func resolveBundle() -> Bundle {
        let saved = UserDefaults.standard.string(forKey: "app_language") ?? "system"
        let lang = AppLanguage(rawValue: saved) ?? .system
        switch lang {
        case .system:
            return .main
        case .zhHans, .english:
            if let path = Bundle.main.path(forResource: lang.rawValue, ofType: "lproj"),
               let langBundle = Bundle(path: path) {
                return langBundle
            }
            return .main
        }
    }
}

// MARK: - String 扩展

extension String {
    /// 使用当前语言设置获取本地化字符串（线程安全）
    var localized: String {
        LanguageManager.resolve(self)
    }
}
