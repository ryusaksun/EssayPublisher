//
//  Theme.swift
//  EssayPublisher
//
//  Claude iOS App 风格深色主题

import SwiftUI

enum Theme {
    // MARK: - 颜色

    static let background = Color(hex: 0x1A1A1A)
    static let surface = Color(hex: 0x2A2A2A)
    static let surfaceLight = Color(hex: 0x333333)
    static let accent = Color(hex: 0x002FA7)
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0x8A8A8A)
    static let divider = Color(hex: 0x333333)
    static let destructive = Color(hex: 0xE05F5F)

    // MARK: - 尺寸

    static let cornerRadius: CGFloat = 16
    static let bubbleCornerRadius: CGFloat = 18
    static let inputCornerRadius: CGFloat = 24
    static let buttonSize: CGFloat = 36
    static let horizontalPadding: CGFloat = 16
    static let bubblePadding: CGFloat = 14
}

// MARK: - Color Hex 初始化

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
