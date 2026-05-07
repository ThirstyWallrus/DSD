//
//  AuthViewModel.swift
//  DynastyStatDrop
//
//  Added "Remember Me" support (username persistence).
//  Auto-login when "Remember Me" was previously selected.
//

import SwiftUI

class AuthViewModel: ObservableObject {
    let instanceID = UUID().uuidString
    // Auth state
    @Published var isLoggedIn: Bool = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var registrationCompleted = false
    @Published var currentUsername: String? = nil
    @Published var hasImportedLeague = false
    @Published var userTeam: String?
    @Published var oauthTokens: [Platform: String] = [:]

    // Remember‑me (persisted in UserDefaults)
    @Published var rememberedUsername: String?

    // Sleeper userId (for team matching after import)
    @Published var sleeperUserId: String?

    enum Platform: String, CaseIterable, Codable {
        case sleeper = "Sleeper"
        case yahoo = "Yahoo"
    }

    private let rememberedKey = "lastRememberedUsername"

    init() {
        // Restore login state from UserDefaults
        let storedIsLoggedIn = UserDefaults.standard.bool(forKey: "isLoggedIn")
        let storedUsername = UserDefaults.standard.string(forKey: "currentUsername")
        
        // Check if "Remember Me" was previously enabled for this username
        var shouldAutoLogin = false
        if let username = storedUsername,
           UserDefaults.standard.bool(forKey: "rememberMe_\(username)") {
            shouldAutoLogin = true
            self.rememberedUsername = username
            print("[AuthViewModel] Remember Me detected for user: \(username)")
        }

        // NEW: Auto-login if both conditions are met:
        // 1. isLoggedIn was true on last app close
        // 2. "Remember Me" was enabled for the stored username
        if storedIsLoggedIn && shouldAutoLogin {
            self.isLoggedIn = true
            self.currentUsername = storedUsername
            print("[AuthViewModel] Auto-login enabled for: \(storedUsername ?? "unknown")")
            loadUserData(username: storedUsername ?? "")
        } else {
            // Otherwise, show SignIn screen
            self.isLoggedIn = false
            self.currentUsername = nil
            print("[AuthViewModel] No auto-login; user must sign in")
        }

        // Load Sleeper userId if present
        if let username = self.currentUsername {
            self.sleeperUserId = UserDefaults.standard.string(forKey: "sleeperUserId_\(username)")
        }
    }

    // MARK: Public API

    /// Sign in normal user path (validates empty fields, sets errors) with remember flag.
    func signIn(username: String, password: String, remember: Bool) {
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Username and password are required."
            showError = true
            isLoggedIn = false
            return
        }
        login(identifier: username, password: password, remember: remember)
    }

    /// Legacy signature kept for backward compatibility (assumes remember=false).
    func signIn(username: String, password: String) {
        signIn(username: username, password: password, remember: false)
    }

    /// Login with remember preference (persists to UserDefaults).
    func login(identifier: String, password: String, remember: Bool) {
        isLoggedIn = true
        UserDefaults.standard.set(true, forKey: "isLoggedIn")
        currentUsername = identifier
        UserDefaults.standard.set(identifier, forKey: "currentUsername")
        storeRememberPreference(username: identifier, remember: remember)
        loadUserData(username: identifier)
        // Attempt to fetch Sleeper user id if missing
        if sleeperUserId == nil {
            fetchAndPersistSleeperUserId(for: identifier)
        }
    }

    func register(email: String, username: String, password: String) {
        registrationCompleted = true
    }

    func loadUserData(username: String) {
        currentUsername = username
        hasImportedLeague = UserDefaults.standard.bool(forKey: "hasImportedLeague_\(username)")
        userTeam = UserDefaults.standard.string(forKey: "userTeam_\(username)")
        sleeperUserId = UserDefaults.standard.string(forKey: "sleeperUserId_\(username)")
    }

    func storeOAuthToken(platform: Platform, token: String) {
        oauthTokens[platform] = token
    }

    func logout() {
        isLoggedIn = false
        UserDefaults.standard.set(false, forKey: "isLoggedIn")
        if let username = currentUsername {
            UserDefaults.standard.removeObject(forKey: "currentUsername")
            UserDefaults.standard.removeObject(forKey: "sleeperUserId_\(username)")
            // Keep rememberMe preference so username pre-fills on next SignIn
        }
        currentUsername = nil
        sleeperUserId = nil
    }

    // MARK: Remember Me

    private func storeRememberPreference(username: String, remember: Bool) {
        if remember {
            UserDefaults.standard.set(true, forKey: "rememberMe_\(username)")
            UserDefaults.standard.set(username, forKey: rememberedKey)
            rememberedUsername = username
            print("[AuthViewModel] Remember Me enabled for: \(username)")
        } else {
            UserDefaults.standard.set(false, forKey: "rememberMe_\(username)")
            if let stored = UserDefaults.standard.string(forKey: rememberedKey),
               stored == username {
                // Only clear the global pointer if it points to this user
                UserDefaults.standard.removeObject(forKey: rememberedKey)
            }
            rememberedUsername = nil
            print("[AuthViewModel] Remember Me disabled for: \(username)")
        }
    }

    /// External setter if UI wants to toggle after login.
    func setRememberPreference(_ remember: Bool) {
        guard let user = currentUsername else { return }
        storeRememberPreference(username: user, remember: remember)
    }

    // MARK: Sleeper userId fetch and persist

    /// Fetches the Sleeper user_id and persists it for later team matching.
    private func fetchAndPersistSleeperUserId(for username: String) {
        guard !username.isEmpty else { return }
        let url = URL(string: "https://api.sleeper.app/v1/user/\(username)")!
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self,
                  let data = data,
                  error == nil,
                  let sleeperUser = try? JSONDecoder().decode(SleeperUserResponse.self, from: data) else { return }
            DispatchQueue.main.async {
                self.sleeperUserId = sleeperUser.user_id
                if let currentUsername = self.currentUsername {
                    UserDefaults.standard.set(sleeperUser.user_id, forKey: "sleeperUserId_\(currentUsername)")
                }
            }
        }
        task.resume()
    }

    // MARK: Entitlement Helpers

    func grantPro(for username: String) {
        UserDefaults.standard.set(true, forKey: "dsd.entitlement.pro.\(username)")
    }

    func revokePro(for username: String) {
        UserDefaults.standard.set(false, forKey: "dsd.entitlement.pro.\(username)")
    }

    func isProUser(_ username: String?) -> Bool {
        guard let u = username else { return false }
        return UserDefaults.standard.bool(forKey: "dsd.entitlement.pro.\(u)")
    }
}

// MARK: - SleeperUserResponse

private struct SleeperUserResponse: Codable {
    let user_id: String
    let username: String?
    let display_name: String?
}
