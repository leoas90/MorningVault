import XCTest

/// MorningVault is a public app. Nothing that ships (code, previews, templates, sample data)
/// may carry the developer's family names; sample members are Sam, Alex, Riley and Jordan.
/// This test greps the source tree and fails on any hit. Bundle identifiers and plists are
/// allowed to carry the developer handle, so plist/yml/pbxproj/entitlements files are skipped.
final class PublicNameGuardTests: XCTestCase {
    private static let forbidden = ["Anna", "Cecilia", "Danilo", "Yezid"]
    private static let scannedDirectories = ["MorningVault", "MorningVaultWidget", "Packages"]
    private static let skippedExtensions: Set<String> = ["plist", "yml", "pbxproj", "entitlements"]
    private static let skippedPathComponents: Set<String> = [".swiftpm", ".build", "xcuserdata", "DerivedData"]

    /// Repo root, derived from this file's location (MorningVaultTests/<file>).
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testNoRealFamilyNamesInShippedSources() throws {
        let pattern = "\\b(" + Self.forbidden.joined(separator: "|") + ")\\b"
        let regex = try NSRegularExpression(pattern: pattern)
        var hits: [String] = []

        for directory in Self.scannedDirectories {
            let base = repoRoot.appendingPathComponent(directory)
            guard let enumerator = FileManager.default.enumerator(
                at: base, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                if Self.skippedPathComponents.contains(where: { url.pathComponents.contains($0) }) {
                    enumerator.skipDescendants()
                    continue
                }
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                if Self.skippedExtensions.contains(url.pathExtension) { continue }
                guard let data = FileManager.default.contents(atPath: url.path),
                      let text = String(data: data, encoding: .utf8) else { continue }

                let range = NSRange(text.startIndex..., in: text)
                for match in regex.matches(in: text, range: range) {
                    guard let r = Range(match.range, in: text) else { continue }
                    let lineNumber = text[..<r.lowerBound].reduce(1) { $0 + ($1 == "\n" ? 1 : 0) }
                    hits.append("\(url.path.replacingOccurrences(of: repoRoot.path + "/", with: "")):\(lineNumber): \(text[r])")
                }
            }
        }

        XCTAssertTrue(hits.isEmpty, "Real names in shipped sources:\n" + hits.joined(separator: "\n"))
    }

    func testGuardScansTheRepo() {
        // Sanity: the directories exist where the guard expects them.
        for directory in Self.scannedDirectories {
            XCTAssertTrue(FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(directory).path), directory)
        }
    }
}
