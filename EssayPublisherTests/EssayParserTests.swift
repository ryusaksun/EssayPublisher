import XCTest
@testable import EssayPublisher

final class EssayParserTests: XCTestCase {

    private let cstTimeZone = TimeZone(secondsFromGMT: 8 * 3600)!

    func testParseFrontmatterDateAndTitle() throws {
        let raw = """
        ---
        pubDate: "2025-10-05 18:43:00"
        ---
        # 标题
        正文
        """

        let essay = try XCTUnwrap(EssayParser.parse(rawContent: raw, fileName: "2025-10-05-note.md"))
        let comps = Calendar(identifier: .gregorian).dateComponents(
            in: cstTimeZone,
            from: essay.pubDate
        )

        XCTAssertEqual(comps.year, 2025)
        XCTAssertEqual(comps.month, 10)
        XCTAssertEqual(comps.day, 5)
        XCTAssertEqual(comps.hour, 18)
        XCTAssertEqual(comps.minute, 43)
        XCTAssertEqual(comps.second, 0)
        XCTAssertEqual(essay.title, "标题")
    }

    func testParseDateFallbackFromFileName() throws {
        let essay = try XCTUnwrap(
            EssayParser.parse(
                rawContent: "无 frontmatter",
                fileName: "2025-10-04-日记-183901.md"
            )
        )

        let comps = Calendar(identifier: .gregorian).dateComponents(
            in: cstTimeZone,
            from: essay.pubDate
        )

        XCTAssertEqual(comps.year, 2025)
        XCTAssertEqual(comps.month, 10)
        XCTAssertEqual(comps.day, 4)
        XCTAssertEqual(comps.hour, 18)
        XCTAssertEqual(comps.minute, 39)
        XCTAssertEqual(comps.second, 1)
    }

    func testPreviewStripsImageAndConvertsLink() throws {
        let raw = """
        ---
        pubDate: "2025-10-05 00:00:00"
        ---
        ![](https://example.com/a.png)

        [链接文字](https://example.com)
        普通文本
        """

        let essay = try XCTUnwrap(EssayParser.parse(rawContent: raw, fileName: "2025-10-05.md"))
        XCTAssertEqual(essay.preview, "链接文字 普通文本")
    }

    func testAllImageURLsExtracted() throws {
        let raw = """
        ![](https://cdn.example.com/1.png)
        ![](https://cdn.example.com/2.webp)
        """

        let essay = try XCTUnwrap(EssayParser.parse(rawContent: raw, fileName: "2025-10-05.md"))
        XCTAssertEqual(essay.allImageURLs.count, 2)
        XCTAssertEqual(essay.allImageURLs[0].absoluteString, "https://cdn.example.com/1.png")
        XCTAssertEqual(essay.allImageURLs[1].absoluteString, "https://cdn.example.com/2.webp")
    }
}
