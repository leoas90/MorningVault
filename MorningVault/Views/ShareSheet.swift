import SwiftUI

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let excludedActivityTypes: [UIActivity.ActivityType]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.excludedActivityTypes = excludedActivityTypes
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Briefing Share View

struct BriefingShareView: View {
    let sections: [BriefingSection]
    let aiSummary: String?
    let highlights: [Highlight]
    let mood: MoodType?

    @Environment(\.dismiss) private var dismiss
    @State private var shareText = ""
    @State private var showMailSheet = false
    @State private var recipientEmail = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Preview
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Preview")
                            .font(.headline)
                            .foregroundStyle(Color.warmTextSecondary)

                        Text(shareText)
                            .font(.body)
                            .foregroundStyle(Color.warmTextPrimary)
                            .padding(16)
                            .background(Color.warmSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 20)
                }

                Divider()

                // Share options
                VStack(spacing: 12) {
                    // Copy
                    Button {
                        UIPasteboard.general.string = shareText
                        dismiss()
                    } label: {
                        ShareOptionRow(icon: "doc.on.doc", title: "Copy to Clipboard", color: .blue)
                    }

                    // AirDrop
                    ShareLink(item: shareText) {
                        ShareOptionRow(icon: "airdrop", title: "AirDrop", color: .purple)
                    }

                    // Email
                    Button {
                        showMailSheet = true
                    } label: {
                        ShareOptionRow(icon: "envelope", title: "Email", color: .red)
                    }

                    // Messages
                    ShareLink(item: shareText) {
                        ShareOptionRow(icon: "message", title: "Messages", color: .green)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 20)
            .background(Color.warmBackground)
            .navigationTitle("Share Briefing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                shareText = await buildShareText()
            }
            .sheet(isPresented: $showMailSheet) {
                MailComposeView(
                    subject: "My Morning Briefing",
                    body: shareText,
                    recipient: recipientEmail
                )
            }
        }
    }

    private func buildShareText() async -> String {
        await teamSharing.buildShareText(
            sections: sections,
            aiSummary: aiSummary,
            highlights: highlights,
            mood: mood
        )
    }
}

// MARK: - Share Option Row

struct ShareOptionRow: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)

            Text(title)
                .font(.body)
                .foregroundStyle(Color.warmTextPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.warmSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Mail Compose View

import MessageUI

struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let recipient: String

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let picker = MFMailComposeViewController()
        picker.setSubject(subject)
        picker.setMessageBody(body, isHTML: false)
        if !recipient.isEmpty {
            picker.setToRecipients([recipient])
        }
        picker.mailComposeDelegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposeView

        init(_ parent: MailComposeView) {
            self.parent = parent
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.dismiss()
        }
    }
}

// MARK: - Later Services View

struct LaterServicesView: View {
    @State private var isPocketEnabled = false
    @State private var isInstapaperEnabled = false
    @State private var pocketToken = ""
    @State private var instapaperUsername = ""
    @State private var instapaperPassword = ""
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            Form {

                // Pocket
                Section {
                    Toggle("Enable Pocket", isOn: $isPocketEnabled)
                        .tint(Color.warmPrimaryAccent)

                    if isPocketEnabled {
                        SecureField("Access Token", text: $pocketToken)
                            .textInputAutocapitalization(.never)
                    }
                } header: {
                    Label("Pocket", systemImage: "bookmark.fill")
                } footer: {
                    Text("Get your access token from getpocket.com/developer")
                }

                // Instapaper
                Section {
                    Toggle("Enable Instapaper", isOn: $isInstapaperEnabled)
                        .tint(Color.warmPrimaryAccent)

                    if isInstapaperEnabled {
                        TextField("Username", text: $instapaperUsername)
                            .textInputAutocapitalization(.never)
                        SecureField("Password", text: $instapaperPassword)
                    }
                } header: {
                    Label("Instapaper", systemImage: "text.book.closed.fill")
                } footer: {
                    Text("Instapaper credentials for bookmark saving")
                }
            }
            .navigationTitle("Later Services")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadSettings()
            }
            .onChange(of: isPocketEnabled) { _, enabled in
                Task { await laterService.setPocketEnabled(enabled) }
            }
            .onChange(of: isInstapaperEnabled) { _, enabled in
                Task { await laterService.setInstapaperEnabled(enabled) }
            }
        }
    }

    private func loadSettings() async {
        isPocketEnabled = await laterService.isPocketEnabled()
        isInstapaperEnabled = await laterService.isInstapaperEnabled()
    }
}

// MARK: - Team Sharing View

struct TeamSharingView: View {
    @State private var teamName = ""
    @State private var teamMembers: [String] = []
    @State private var newMemberEmail = ""
    @State private var shareHighlights = true
    @State private var shareCalendar = false
    @State private var shareMarketPositions = false
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            Form {

                // Team info
                Section("Team") {
                    TextField("Team Name", text: $teamName)
                        .onChange(of: teamName) { _, name in
                            Task { await teamSharing.setTeamName(name) }
                        }
                }

                // Team members
                Section("Members") {
                    ForEach(teamMembers, id: \.self) { email in
                        HStack {
                            Text(email)
                            Spacer()
                            Button {
                                Task { await teamSharing.removeTeamMember(email: email) }
                                teamMembers.removeAll { $0 == email }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    HStack {
                        TextField("Add member email", text: $newMemberEmail)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)

                        Button {
                            Task {
                                await teamSharing.addTeamMember(email: newMemberEmail)
                                teamMembers = await teamSharing.getTeamMembers()
                                newMemberEmail = ""
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.warmPrimaryAccent)
                        }
                        .disabled(newMemberEmail.isEmpty)
                    }
                }

                // Sharing preferences
                Section("What to Share") {
                    Toggle("Highlights", isOn: $shareHighlights)
                        .tint(Color.warmPrimaryAccent)
                        .onChange(of: shareHighlights) { _, enabled in
                            Task { await teamSharing.setShareHighlights(enabled) }
                        }

                    Toggle("Calendar Events", isOn: $shareCalendar)
                        .tint(Color.warmPrimaryAccent)
                        .onChange(of: shareCalendar) { _, enabled in
                            Task { await teamSharing.setShareCalendar(enabled) }
                        }

                    Toggle("Market Positions", isOn: $shareMarketPositions)
                        .tint(Color.warmPrimaryAccent)
                        .onChange(of: shareMarketPositions) { _, enabled in
                            Task { await teamSharing.setShareMarketPositions(enabled) }
                        }
                }
            }
            .navigationTitle("Team Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                teamName = await teamSharing.getTeamName() ?? ""
                teamMembers = await teamSharing.getTeamMembers()
                let config = await getTeamConfig()
                shareHighlights = config.shareHighlights
                shareCalendar = config.shareCalendar
                shareMarketPositions = config.shareMarketPositions
            }
        }
    }

    private func getTeamConfig() async -> TeamSharingService.TeamConfig {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "team_share_config"),
              let config = try? JSONDecoder().decode(TeamSharingService.TeamConfig.self, from: data) else {
            return TeamSharingService.TeamConfig(sharedWithEmails: [], shareHighlights: true, shareCalendar: false, shareMarketPositions: false)
        }
        return config
    }
}

// MARK: - Send Email View

struct SendEmailView: View {
    let sections: [BriefingSection]
    let aiSummary: String?
    let mood: MoodType?

    @Environment(\.dismiss) private var dismiss
    @State private var recipient = ""
    @State private var subject = "My Morning Briefing"
    @State private var emailBody = ""
    @State private var isSending = false
    @State private var sendSuccess = false
    @State private var sendError: String?

    var body: some View {
        NavigationStack {
            Form {

                Section("Recipient") {
                    TextField("Email address", text: $recipient)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }

                Section("Subject") {
                    TextField("Subject", text: $subject)
                }

                Section("Message") {
                    TextEditor(text: $emailBody)
                        .frame(minHeight: 200)
                }

                if sendSuccess {
                    Section {
                        Label("Email sent successfully!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if let error = sendError {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Email Briefing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send") {
                        sendEmail()
                    }
                    .disabled(recipient.isEmpty || isSending)
                }
            }
            .task {
                emailBody = await buildEmailBody()
            }
        }
    }

    private func buildEmailBody() async -> String {
        await emailService.buildEmailBody(
            sections: sections,
            aiSummary: aiSummary,
            highlights: [],
            mood: mood,
            includeHighlights: true
        )
    }

    private func sendEmail() {
        isSending = true
        sendError = nil

        // In a real implementation, this would use a backend service
        // or MFComposeViewController for actual email sending
        // For now, we simulate the send
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isSending = false
            sendSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        }
    }
}

#Preview {
    ShareSheet(items: ["Test"])
}