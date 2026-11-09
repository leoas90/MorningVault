import SafariServices
import SwiftUI

// MARK: - SafariView
//
// In-app reader for a headline: SFSafariViewController in a sheet, opening in Reader
// view when the page offers one. The system share button comes with the controller.
// Only http(s) URLs are accepted; callers should check `SafariView.isOpenable` first and
// do nothing for anything else.

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    /// True for the URLs SFSafariViewController can load (http or https).
    static func isOpenable(_ string: String) -> Bool {
        openableURL(from: string) != nil
    }

    /// The URL to open, or nil for an empty, malformed or non-web string.
    static func openableURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor(Color.appAccentColor)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

#Preview("Safari view") {
    SafariView(url: URL(string: "https://www.apple.com/newsroom/")!)
        .ignoresSafeArea()
}
