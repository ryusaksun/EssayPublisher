//
//  GitHubModels.swift
//  EssayPublisher
//

import Foundation

// MARK: - API 响应模型

struct GHErrorResponse: Decodable, Sendable {
    let message: String
}

struct GHFileResponse: Decodable, Sendable {
    let name: String
    let path: String
    let sha: String
    let content: String
    let encoding: String
}

struct GHCreateFileResponse: Decodable, Sendable {
    let content: FileInfo

    struct FileInfo: Decodable, Sendable {
        let name: String
        let path: String
        let sha: String
        let htmlUrl: String

        enum CodingKeys: String, CodingKey {
            case name, path, sha
            case htmlUrl = "html_url"
        }
    }
}

struct GHDeleteResponse: Decodable, Sendable {
    let commit: CommitInfo
    struct CommitInfo: Decodable, Sendable {
        let sha: String
    }
}

struct GHCommitSummary: Decodable, Sendable {
    let sha: String
}

struct GHCommitDetailResponse: Decodable, Sendable {
    let files: [GHCommitChangedFile]?
}

struct GHCommitChangedFile: Decodable, Sendable {
    let filename: String
    let status: String?
}

// MARK: - 业务模型

struct FileContent: Sendable {
    let content: String
    let sha: String
}

struct PublishResult: Sendable {
    let success: Bool
    let filePath: String
    let url: String
    let action: String
}

struct ImageUploadResult: Sendable {
    let success: Bool
    let path: String
    let url: String
    let sha: String
}
