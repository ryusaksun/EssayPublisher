//
//  OAuthService.swift
//  EssayPublisher
//
//  GitHub OAuth Web Application Flow via ASWebAuthenticationSession

import AuthenticationServices
import Foundation

@MainActor
final class OAuthService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    static let shared = OAuthService()

    // MARK: - OAuth 配置（注册 GitHub OAuth App 后填入）

    private let clientID = "Ov23li8LICF0sB9TEVdW"
    private let clientSecret = "11b83af5e5e52f39142152c04b75d1a59d2e7657"
    private let callbackScheme = "ogygia"
    private let scope = "repo"

    private let authorizeURL = "https://github.com/login/oauth/authorize"
    private let tokenURL = "https://github.com/login/oauth/access_token"

    private override init() { super.init() }

    // MARK: - 授权入口

    /// 完整 OAuth 流程：弹出 GitHub 登录页 → 换取 token → 获取用户名
    func authorize() async throws -> (token: String, username: String) {
        let code = try await requestAuthorizationCode()
        let token = try await exchangeCodeForToken(code)
        let username = try await GitHubService.shared.verifyToken(token)

        // 保存到 Keychain / UserDefaults
        AppConfig.saveGitHubToken(token)
        AppConfig.saveGitHubUsername(username)

        return (token, username)
    }

    // MARK: - Step 1: 获取 Authorization Code

    private func requestAuthorizationCode() async throws -> String {
        let state = UUID().uuidString

        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: "\(callbackScheme)://oauth/callback"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
        ]

        guard let url = components.url else {
            throw OAuthError.invalidURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: OAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: OAuthError.authSessionFailed(error.localizedDescription))
                    }
                    return
                }

                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let returnedCode = components.queryItems?.first(where: { $0.name == "code" })?.value,
                      let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value
                else {
                    continuation.resume(throwing: OAuthError.invalidCallback)
                    return
                }

                guard returnedState == state else {
                    continuation.resume(throwing: OAuthError.stateMismatch)
                    return
                }

                continuation.resume(returning: returnedCode)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    // MARK: - Step 2: 用 Code 换取 Access Token

    private func exchangeCodeForToken(_ code: String) async throws -> String {
        guard let url = URL(string: tokenURL) else {
            throw OAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let body: [String: String] = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "redirect_uri": "\(callbackScheme)://oauth/callback",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OAuthError.tokenExchangeFailed
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let token_type: String
            let scope: String
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return tokenResponse.access_token
    }

    // MARK: - 退出登录

    func signOut() {
        _ = AppConfig.deleteGitHubToken()
        AppConfig.saveGitHubUsername("")
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
        }
    }
}

// MARK: - 错误类型

enum OAuthError: Error, LocalizedError {
    case invalidURL
    case userCancelled
    case authSessionFailed(String)
    case invalidCallback
    case stateMismatch
    case tokenExchangeFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的授权 URL"
        case .userCancelled: return "用户取消了授权"
        case .authSessionFailed(let msg): return "授权失败: \(msg)"
        case .invalidCallback: return "无效的回调"
        case .stateMismatch: return "安全验证失败，请重试"
        case .tokenExchangeFailed: return "获取 Token 失败"
        }
    }
}
