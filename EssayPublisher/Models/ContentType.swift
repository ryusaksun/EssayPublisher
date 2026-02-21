//
//  ContentType.swift
//  EssayPublisher
//

import Foundation

enum ContentType: String, CaseIterable, Identifiable {
    case essay = "essay"
    case blog = "blog"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .essay: return "Essay"
        case .blog: return "Post"
        }
    }

    var pathPrefix: String {
        switch self {
        case .essay: return "src/content/essays"
        case .blog: return "src/content/posts"
        }
    }
}
