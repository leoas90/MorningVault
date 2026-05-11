import Foundation

/// Service for "Read Later" integration with Pocket and Instapaper.
/// Tokens stored in Keychain. No user data transmitted.
actor LaterIntegrationService {
    private let keychain = KeychainHelper.self
    private let defaults = UserDefaults.standard
    private let storageKey = "later_service_config"

    private var config: LaterServiceConfig {
        get {
            guard let data = defaults.data(forKey: storageKey),
                  let config = try? JSONDecoder().decode(LaterServiceConfig.self, from: data) else {
                return LaterServiceConfig(isPocketEnabled: false, isInstapaperEnabled: false)
            }
            return config
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: storageKey)
            }
        }
    }

    // MARK: - Pocket

    func setPocketAuthToken(_ token: String) async {
        var current = config
        current.pocketAuthToken = token
        config = current
    }

    func getPocketAuthToken() -> String? {
        config.pocketAuthToken
    }

    func isPocketEnabled() -> Bool {
        config.isPocketEnabled && config.pocketAuthToken != nil
    }

    func setPocketEnabled(_ enabled: Bool) async {
        var current = config
        current.isPocketEnabled = enabled
        config = current
    }

    /// Add item to Pocket
    func addToPocket(url: String, title: String) async -> Bool {
        guard let token = config.pocketAuthToken, !token.isEmpty else { return false }
        guard let requestURL = URL(string: "https://getpocket.com/v3/add") else { return false }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "access_token": token,
            "url": url,
            "title": title
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Instapaper

    func setInstapaperCredentials(username: String, password: String) async {
        var current = config
        current.instapaperUsername = username
        current.instapaperPassword = password
        config = current
    }

    func getInstapaperUsername() -> String? {
        config.instapaperUsername
    }

    func isInstapaperEnabled() -> Bool {
        config.isInstapaperEnabled && config.instapaperUsername != nil && config.instapaperPassword != nil
    }

    func setInstapaperEnabled(_ enabled: Bool) async {
        var current = config
        current.isInstapaperEnabled = enabled
        config = current
    }

    /// Add item to Instapaper
    func addToInstapaper(url: String, title: String) async -> Bool {
        guard let username = config.instapaperUsername,
              let password = config.instapaperPassword,
              !username.isEmpty, !password.isEmpty else { return false }

        guard let requestURL = URL(string: "https://www.instapaper.com/api/1.1/bookmarks/add") else { return false }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"

        let bodyString = "url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url)&title=\(title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title)&username=\(username)&password=\(password)"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyString.data(using: .utf8)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 201 || (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Convenience

    func addToLater(url: String, title: String, service: LaterItem.Source) async -> Bool {
        switch service {
        case .pocket:
            return await addToPocket(url: url, title: title)
        case .instapaper:
            return await addToInstapaper(url: url, title: title)
        }
    }

    func getActiveServices() -> [LaterItem.Source] {
        var services: [LaterItem.Source] = []
        if isPocketEnabled() { services.append(.pocket) }
        if isInstapaperEnabled() { services.append(.instapaper) }
        return services
    }
}

// MARK: - Shared Instance

let laterService = LaterIntegrationService()