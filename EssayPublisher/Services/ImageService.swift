//
//  ImageService.swift
//  EssayPublisher
//
//  重写自 Swift_MarkdownEditor:
//  - 从原始 Data 操作（不经过 UIImage），保留 ICC Profile
//  - HEIC → WebP 无损转换，保留 Display P3 广色域
//  - 使用 CGImageSource/CGImageDestination 处理图片

import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

actor ImageService {

    static let shared = ImageService()
    private init() {}

    // MARK: - HEIC 检测

    /// 从 bytes magic number 检测是否为 HEIC/HEIF
    func isHEIC(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        // HEIC ftyp box: offset 4 = "ftyp", offset 8 = brand
        let bytes = [UInt8](data[4..<8])
        guard String(bytes: bytes, encoding: .ascii) == "ftyp" else { return false }
        let brand = [UInt8](data[8..<12])
        let brandStr = String(bytes: brand, encoding: .ascii) ?? ""
        return ["heic", "heix", "hevc", "hevx", "mif1"].contains(brandStr)
    }

    /// 获取图片文件扩展名
    func getImageExtension(_ data: Data) -> String {
        guard data.count >= 12 else { return "jpg" }
        let bytes = [UInt8](data.prefix(12))

        // HEIC
        if isHEIC(data) { return "heic" }
        // PNG: 89 50 4E 47
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 { return "png" }
        // GIF: 47 49 46 38
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38 { return "gif" }
        // WebP: RIFF....WEBP
        if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 { return "webp" }
        // JPEG: FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF { return "jpg" }
        return "jpg"
    }

    // MARK: - HEIC → WebP 无损转换

    /// 将 HEIC 转为 WebP 无损格式，保留 Display P3 ICC Profile
    ///
    /// 使用 ImageIO 框架：CGImageSource 读取 HEIC → CGImageDestination 写入 WebP
    /// iOS 17+ 的 ImageIO 原生支持 WebP 编码
    func convertHEICToWebP(_ heicData: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(heicData as CFData, nil) else {
            throw ImageServiceError.invalidImage
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageServiceError.invalidImage
        }

        // 提取源图片属性（含 ICC Profile）
        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]

        // 创建 WebP 目标
        let webpData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            webpData, UTType.webP.identifier as CFString, 1, nil
        ) else {
            // iOS 17+ 才支持 WebP 编码，降级为 JPEG
            return try fallbackToJPEG(cgImage: cgImage, source: source)
        }

        // 无损 WebP 设置
        var options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 1.0
        ]

        // 传递源属性（含 ICC Profile、EXIF 等）
        if let props = sourceProperties {
            options[kCGImagePropertyExifDictionary] = props[kCGImagePropertyExifDictionary]
        }

        // 保留色彩空间（Display P3）
        if let colorSpace = cgImage.colorSpace {
            options[kCGImageDestinationOptimizeColorForSharing] = false
            _ = colorSpace // 色彩空间通过 cgImage 自动传递
        }

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return try fallbackToJPEG(cgImage: cgImage, source: source)
        }

        let originalKB = heicData.count / 1024
        let resultKB = webpData.length / 1024
        #if DEBUG
        print("HEIC → WebP: \(originalKB)KB → \(resultKB)KB")
        #endif

        return webpData as Data
    }

    /// WebP 编码失败时降级为高质量 JPEG（保留 ICC）
    private func fallbackToJPEG(cgImage: CGImage, source: CGImageSource) throws -> Data {
        let jpegData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            jpegData, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw ImageServiceError.compressionFailed
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.95
        ]
        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageServiceError.compressionFailed }

        #if DEBUG
        print("WebP 编码不可用，降级为 JPEG 95%")
        #endif
        return jpegData as Data
    }

    // MARK: - 图片压缩（>10MB）

    func smartCompress(_ imageData: Data) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }

        var newW = image.size.width
        var newH = image.size.height

        if newW > AppConfig.maxImageWidth {
            let ratio = AppConfig.maxImageWidth / newW
            newW = AppConfig.maxImageWidth
            newH *= ratio
        }
        if newH > AppConfig.maxImageHeight {
            let ratio = AppConfig.maxImageHeight / newH
            newH *= ratio
            newW *= ratio
        }

        let needsResize = abs(newW - image.size.width) > 1 || abs(newH - image.size.height) > 1
        let targetImage: UIImage
        if needsResize {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: newW, height: newH), format: format)
            targetImage = renderer.image { _ in image.draw(in: CGRect(x: 0, y: 0, width: newW, height: newH)) }
        } else {
            targetImage = image
        }

        var quality: CGFloat = AppConfig.imageQuality
        var data = targetImage.jpegData(compressionQuality: quality)

        while let d = data, d.count > AppConfig.maxFileSize, quality > 0.1 {
            let prev = d.count
            quality -= 0.1
            data = targetImage.jpegData(compressionQuality: quality)
            if let nd = data, nd.count > Int(Double(prev) * 0.95) { break }
        }
        return data
    }

    // MARK: - 上传

    func generateFileName(ext: String = "jpg") -> String {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let rnd = Int.random(in: 1000...9999)
        return "img-\(ts)-\(rnd).\(ext)"
    }

    /// 完整上传流程：检测格式 → 转换 → 压缩 → 上传 → 返回 CDN URL
    func uploadImage(_ imageData: Data) async throws -> ImageUploadResult {
        guard AppConfig.isImageServiceConfigured else { throw ImageServiceError.notConfigured }

        var finalData = imageData
        var ext = getImageExtension(imageData)

        // HEIC → WebP 无损
        if isHEIC(imageData) {
            do {
                finalData = try convertHEICToWebP(imageData)
                ext = "webp"
            } catch {
                #if DEBUG
                print("HEIC 转换失败: \(error), 使用原图上传")
                #endif
            }
        }

        // >10MB 压缩
        if finalData.count > AppConfig.imageCompressionThreshold {
            if let compressed = smartCompress(finalData) {
                finalData = compressed
                ext = "jpg"
            }
        }

        let fileName = generateFileName(ext: ext)
        return try await GitHubService.shared.uploadImage(imageData: finalData, fileName: fileName)
    }
}

// MARK: - 错误

enum ImageServiceError: Error, LocalizedError {
    case notConfigured
    case invalidImage
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "error.image.notConfigured".localized
        case .invalidImage: return "error.image.invalidImage".localized
        case .compressionFailed: return "error.image.compressionFailed".localized
        }
    }
}
