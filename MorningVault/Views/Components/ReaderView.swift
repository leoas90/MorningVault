import SwiftUI

/// Reading mode for long-form content with TL;DR toggle.
/// Provides a clean, distraction-free reader view with adjustable typography.
struct ReaderView: View {
    let title: String
    let content: String
    let source: String?
    let publishedDate: Date?
    @State private var showTLDR = false
    @State private var isTLDRExpanded = false
    @State private var fontSize: ReaderFontSize = .medium
    @State private var showSettings = false

    @State private var tldrSummary: String?
    @State private var isGeneratingTLDR = false

    enum ReaderFontSize: String, CaseIterable {
        case small = "Small"
        case medium = "Medium"
        case large = "Large"

        var size: CGFloat {
            switch self {
            case .small: return 15
            case .medium: return 18
            case .large: return 22
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    if let source = source {
                        Text(source.uppercased())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.warmPrimaryAccent)
                            .tracking(1)
                    }

                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.warmTextPrimary)
                        .lineLimit(4)

                    if let date = publishedDate {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundStyle(Color.warmTextSecondary)
                    }
                }

                Divider()

                // TL;DR toggle button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if !showTLDR && tldrSummary == nil {
                            isGeneratingTLDR = true
                            generateTLDR()
                        }
                        showTLDR.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.warmAISummary)
                        Text(showTLDR && !isTLDRExpanded ? "Hide TL;DR" : "TL;DR")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.warmAISummary)
                        Spacer()
                        if isGeneratingTLDR {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: showTLDR ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(Color.warmTextSecondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.warmAISummary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isGeneratingTLDR)

                // TL;DR content
                if showTLDR {
                    if let summary = tldrSummary {
                        VStack(alignment: .leading, spacing: 8) {
                            if !isTLDRExpanded {
                                Text(summary)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.warmTextSecondary)
                                    .lineLimit(3)
                                Button {
                                    withAnimation { isTLDRExpanded = true }
                                } label: {
                                    Text("Read more")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.warmAISummary)
                                }
                            } else {
                                Text(summary)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.warmTextSecondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.warmAISummary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                // Article body
                Text(content)
                    .font(.system(size: fontSize.size, design: .serif))
                    .foregroundStyle(Color.warmTextPrimary)
                    .lineSpacing(fontSize == .small ? 4 : 8)
                    .fixedSize(horizontal: false, vertical: true)

                // Source link
                if let source = source {
                    HStack {
                        Image(systemName: "link")
                            .font(.caption)
                        Text("From \(source)")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.warmTextSecondary)
                    .padding(.top, 8)
                }

                // Bottom padding
                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
        .background(Color.warmBackground.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(ReaderFontSize.allCases, id: \.self) { size in
                        Button {
                            fontSize = size
                        } label: {
                            HStack {
                                Text(size.rawValue)
                                if fontSize == size {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "textformat.size")
                        .foregroundStyle(Color.warmPrimaryAccent)
                }
            }
        }
    }

    // MARK: - TL;DR Generation

    private func generateTLDR() {
        Task {
            let points = content.components(separatedBy: ". ")
                .prefix(6)
                .map { "- \($0.trimmingCharacters(in: .whitespacesAndNewlines))." }
                .joined(separator: "\n")

            let summary = "Key points:\n\(points)"

            try? await Task.sleep(nanoseconds: 800_000_000)  // Simulate processing

            await MainActor.run {
                tldrSummary = summary
                isGeneratingTLDR = false
                isTLDRExpanded = true
            }
        }
    }
}

// MARK: - Reader Preview

struct ArticleReaderPreview: View {
    let title: String
    let content: String
    let source: String

    var body: some View {
        NavigationStack {
            ReaderView(
                title: title,
                content: content,
                source: source,
                publishedDate: Date()
            )
            .navigationTitle("Article")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Standalone Reader Card (for RSS articles)

struct ReaderCard: View {
    let article: RSSArticle
    @State private var showFullReader = false

    var previewContent: String {
        article.summary ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(article.title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.warmTextPrimary)
                .lineLimit(3)

            // Summary
            if let summary = article.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(Color.warmTextSecondary)
                    .lineLimit(3)
            }

            // Footer
            HStack {
                if let date = article.publishedAt {
                    Text(date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(Color.warmTextSecondary)
                }
                Spacer()
                Button {
                    showFullReader = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Read")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(Color.warmPrimaryAccent)
                }
            }
        }
        .padding(16)
        .background(Color.warmCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showFullReader) {
            NavigationStack {
                ReaderView(
                    title: article.title,
                    content: article.summary ?? article.title,
                    source: nil,
                    publishedDate: article.publishedAt
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showFullReader = false }
                    }
                }
            }
        }
    }
}