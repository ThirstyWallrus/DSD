//
//  DynastyStatDropApp.swift
//  DynastyStatDrop
//
//  Adds foreground (scenePhase) & post-login throttled refresh
//  while preserving existing per-user league loading.
//

import SwiftUI
import Foundation
import ObjectiveC.runtime

@main
struct DynastyStatDropApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var authViewModel = AuthViewModel()
    @StateObject var appSelection = AppSelection()
    @StateObject var leagueManager = SleeperLeagueManager()
    @StateObject var migrationManager = DataMigrationManager()
    
    @Environment(\.scenePhase) private var scenePhase

    // Resolved PostScript name used as the app default font (if available)
    private let preferredFontFriendlyName = "Phatt"
    private var resolvedPhattPostScriptName: String? = nil

    init() {
        // Register any bundled fonts (falls back if Info.plist/UIAppFonts missing)
        FontLoader.registerAllBundleFonts()

        // Attempt to resolve the PostScript name for the friendly "Phatt" identifier.
        // If FontLoader finds a matching internal name use that; otherwise keep the friendly name
        // (Font.custom will failover to system font if that name is not present).
        resolvedPhattPostScriptName = FontLoader.postScriptName(matching: preferredFontFriendlyName)

        // Apply UIKit appearance defaults as a fallback for UIKit-hosted text.
        applyUIKitAppearanceForPhatt()
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                // FIXED: ContentView is now the root, managing the video intro + sign-in flow
                ContentView()
                    .environmentObject(authViewModel)
                    .environmentObject(appSelection)
                    .environmentObject(leagueManager)
                    .task {
                        // Run migration first
                        migrationManager.runMigrationIfNeeded(leagueManager: leagueManager)

                        // If we have a restored logged-in user, ensure the leagueManager
                        // is made aware of that user and attempts to load their leagues.
                        if let user = authViewModel.currentUsername, authViewModel.isLoggedIn {
                            leagueManager.setActiveUser(username: user)
                            await leagueManager.refreshAllLeaguesIfNeeded(username: user, force: false)
                            await MainActor.run {
                                appSelection.updateLeagues(leagueManager.leagues, username: user)
                            }
                        } else {
                            appSelection.updateLeagues(leagueManager.leagues, username: authViewModel.currentUsername)
                        }
                    }
                    .onChange(of: authViewModel.isLoggedIn) { _, loggedIn in
                        if loggedIn, let user = authViewModel.currentUsername {
                            leagueManager.setActiveUser(username: user)
                            appSelection.updateLeagues(leagueManager.leagues, username: user)
                            Task {
                                await leagueManager.refreshAllLeaguesIfNeeded(username: user, force: false)
                                await MainActor.run {
                                    appSelection.updateLeagues(leagueManager.leagues, username: user)
                                }
                            }
                        }
                    }
                    .onChange(of: authViewModel.currentUsername) { _, user in
                        guard let user else { return }
                        leagueManager.setActiveUser(username: user)
                        appSelection.updateLeagues(leagueManager.leagues, username: user)
                    }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active,
                           authViewModel.isLoggedIn,
                           let user = authViewModel.currentUsername {
                            Task {
                                await leagueManager.refreshAllLeaguesIfNeeded(username: user, force: false)
                                await MainActor.run {
                                    appSelection.updateLeagues(leagueManager.leagues, username: user)
                                }
                            }
                        }
                    }
                    .onChange(of: leagueManager.leagues) { _ in
                        appSelection.updateLeagues(
                            leagueManager.leagues,
                            username: authViewModel.currentUsername
                        )
                    }
                    .onChange(of: appSelection.selectedLeagueId) { _, newLeagueId in
                        guard let leagueId = newLeagueId else { return }
                        Task {
                            await leagueManager.refreshGlobalCurrentWeek(for: leagueId)
                        }
                    }
            }
            // Apply Phatt as default environment font (size 16 default) if we resolved a PostScript name.
            // If we didn't resolve it, fall back to the friendly name (Font.custom will fail silently to system).
            .environment(\.font, Font.custom(resolvedPhattPostScriptName ?? preferredFontFriendlyName, size: 16))
        }
    }
    
    private func applyUIKitAppearanceForPhatt() {
        let candidate = resolvedPhattPostScriptName ?? preferredFontFriendlyName
        if let uiFont = UIFont(name: candidate, size: 16) {
            UILabel.appearance().font = uiFont
            let navAttrs: [NSAttributedString.Key: Any] = [
                .font: uiFont,
                .foregroundColor: UIColor.orange
            ]
            UINavigationBar.appearance().titleTextAttributes = navAttrs
            UINavigationBar.appearance().largeTitleTextAttributes = navAttrs
            print("[DynastyStatDropApp] Applied Phatt ('\(candidate)') to UIKit appearances.")
        } else {
            // If the resolved name failed, print guidance (diagnostics are already printed by FontLoader).
            print("[DynastyStatDropApp] UIFont(name: \"\(candidate)\") returned nil. Check FontLoader logs and Info.plist UIAppFonts entries.")
            // Also print currently available fonts for quick debugging
            FontLoader.logAvailableFonts(prefix: "[DynastyStatDropApp] Available fonts")
        }
    }
}

func checkForNewStatDropAndNotify() {
    // For each team/league/context/personality the user cares about...
    // let statDrop = StatDropPersistence.shared.getOrGenerateStatDrop(for: team, league: league, context: .fullTeam, personality: preferredPersonality)
    // If this was a new generation (i.e., previously not present in UserDefaults), trigger your push/local notification.
    // You can add an additional flag in UserDefaults to track if notification was sent for this week.
}
