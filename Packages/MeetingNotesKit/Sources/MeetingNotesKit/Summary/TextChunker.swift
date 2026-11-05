import Foundation

/// Splits long transcripts into pieces a language model can digest.
public enum TextChunker {
    /// Default chunk size, in words.
    public static let defaultChunkSize = 2_500

    /// Splits `text` into chunks of at most `maxWords` words.
    ///
    /// Paragraph and sentence boundaries are preferred so a chunk never cuts a
    /// sentence in half unless a single sentence is longer than the whole budget.
    public static func chunks(for text: String, maxWords: Int = defaultChunkSize) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard maxWords > 0 else { return [trimmed] }

        let paragraphs = trimmed
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current: [String] = []
        var currentWords = 0

        for paragraph in paragraphs {
            let paragraphWords = wordCount(paragraph)
            if paragraphWords > maxWords {
                if !current.isEmpty {
                    chunks.append(current.joined(separator: "\n\n"))
                    current = []
                    currentWords = 0
                }
                chunks.append(contentsOf: splitLongParagraph(paragraph, maxWords: maxWords))
                continue
            }
            if currentWords + paragraphWords > maxWords, !current.isEmpty {
                chunks.append(current.joined(separator: "\n\n"))
                current = []
                currentWords = 0
            }
            current.append(paragraph)
            currentWords += paragraphWords
        }

        if !current.isEmpty {
            chunks.append(current.joined(separator: "\n\n"))
        }
        return chunks
    }

    /// Counts the words in a piece of text.
    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private static func splitLongParagraph(_ paragraph: String, maxWords: Int) -> [String] {
        let sentences = paragraph
            .components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current: [String] = []
        var currentWords = 0

        for sentence in sentences {
            let sentenceWords = wordCount(sentence)
            if currentWords + sentenceWords > maxWords, !current.isEmpty {
                chunks.append(current.joined(separator: ". "))
                current = []
                currentWords = 0
            }
            current.append(sentence)
            currentWords += sentenceWords
        }
        if !current.isEmpty {
            chunks.append(current.joined(separator: ". "))
        }
        return chunks
    }
}
