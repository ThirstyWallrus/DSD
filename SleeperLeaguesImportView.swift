//
//  SleeperLeaguesImportView.swift
//  DynastyStatDrop
//
//  Updated to use setActiveUser(username:) now implemented in SleeperLeagueManager.
//
//  PATCHED: After importing a Sleeper league,
//      - AppSelection always selects user's own team using both entered Sleeper username and fetched user_id
//      - Passed both username and user_id to AppSelection.updateLeagues
//      - Persists user_id in AuthViewModel for current user
//      - Guarantees correct team selection after import and sync
//      - Persist and restore per-DSD-user Sleeper username so the Upload text field is prefilled
//

import SwiftUI

enum Platform: String, CaseIterable {
    case sleeper = "Sleeper"
    case yahoo = "Yahoo"
    case espn = "ESPN"
}

struct SleeperLeaguesImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appSelection: AppSelection
    @EnvironmentObject var leagueManager: SleeperLeagueManager
    
    let onLeagueImported: ((String) -> Void)? // Add this callback

    @State private var sleeperUsername: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var fetchedLeagues: [SleeperLeague] = []
    @State private var selectedLeagueId: String = ""
    @State private var selectedPlatform: Platform?

    let menuHeight: CGFloat = 36
    let leagueMenuWidth: CGFloat = 200

    private var activeLeagues: [SleeperLeague] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return fetchedLeagues.filter { $0.season == "\(currentYear)" }
    }

    var body: some View {
        ZStack {
            backgroundImage
            mainContent
        }
        .navigationTitle(Text("Import Leagues"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let dsdUser = authViewModel.currentUsername {
                leagueManager.setActiveUser(username: dsdUser)
                // Prefill the sleeper username for this DSD user if saved
                if let saved = UserDefaults.standard.string(forKey: "sleeperUsername_\(dsdUser)") {
                    sleeperUsername = saved
                }
            }
            fetchedLeagues = []
            selectedLeagueId = ""
        }
    }

    private var backgroundImage: some View {
        Image("Background1")
            .resizable()
            .ignoresSafeArea(edges: .all)
    }

    private var mainContent: some View {
        VStack(spacing: 16) {
            platformSelectionView
            if let platform = selectedPlatform {
                switch platform {
                case .sleeper:
                    sleeperContentView
                default:
                    comingSoonView
                }
            }
            importedLeaguesList
            Spacer()
            Text("swipe down to return to Dashboard")
                .font(.custom("Phatt", size: 12))
                .foregroundColor(.gray)
                .padding(.bottom, 20)
        }
        .padding(.top, 32)
    }

    private var platformSelectionView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 20) {
                ForEach(Platform.allCases, id: \.rawValue) { platform in
                    Button {
                        selectedPlatform = platform
                    } label: {
                        HStack(spacing: 8) {
                            if selectedPlatform == platform {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 12, height: 12)
                                    .shadow(color: .blue, radius: 3)
                            } else {
                                Circle()
                                    .fill(Color.gray)
                                    .frame(width: 12, height: 12)
                            }
                            Text(platform.rawValue)
                                .font(.custom("Phatt", size: 16))
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.blue.opacity(0.5), lineWidth: 2)
                )
                .shadow(color: .blue, radius: 10)
        )
        .padding(.horizontal)
    }

    private var comingSoonView: some View {
        Text("More platform access to come...")
            .font(.custom("Phatt", size: 16))
            .foregroundColor(.orange)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.black)
                    .shadow(color: .blue, radius: 10)
            )
            .padding(.horizontal)
    }

    private var sleeperContentView: some View {
        VStack(spacing: 8) {
            usernameInputView
            Text("Enter Sleeper User Name to view your Leagues")
                .font(.custom("Phatt", size: 14))
                .foregroundColor(.orange)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            loadingAndErrorView
            leaguesPickerView
        }
    }

    private var usernameInputView: some View {
        HStack {
            TextField("Enter Sleeper username", text: $sleeperUsername)
                .padding(10)
                .font(.custom("Phatt", size: 16))
                .foregroundColor(.orange)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.black)
                        .shadow(color: .blue, radius: 10)
                )
                .frame(height: menuHeight)
                .accentColor(.orange)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)

            Button("Fetch Leagues") {
                Task { await fetchLeagues() }
            }
            .bold()
            .font(.custom("Phatt", size: 16))
            .foregroundColor(.orange)
            .padding(.horizontal, 14)
            .frame(height: menuHeight)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.black)
                    .shadow(color: .blue, radius: 10)
            )
            .disabled(sleeperUsername.isEmpty || isLoading)
        }
        .padding(.horizontal)
    }

    private var loadingAndErrorView: some View {
        VStack {
            if isLoading { ProgressView("Loading...") }
            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .font(.custom("Phatt", size: 14))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var leaguesPickerView: some View {
        VStack(spacing: 10) {
            if !activeLeagues.isEmpty {
                Picker("Select League", selection: $selectedLeagueId) {
                    ForEach(activeLeagues, id: \.league_id) { league in
                        Text(league.name ?? "Unnamed League")
                            .font(.custom("Phatt", size: 16))
                            .foregroundColor(.orange)
                            .tag(league.league_id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.horizontal)
                .frame(width: leagueMenuWidth)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black)
                        .shadow(color: .blue, radius: 10)
                )

                Button("Download & Use This League") {
                    Task { await importSelectedLeague() }
                }
                .bold()
                .font(.custom("Phatt", size: 16))
                .foregroundColor(.orange)
                .padding(.horizontal, 14)
                .frame(height: menuHeight)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.black)
                        .shadow(color: .blue, radius: 10)
                )
                .disabled(selectedLeagueId.isEmpty || isLoading)
            } else if !fetchedLeagues.isEmpty {
                Text("No active leagues found for the current season.")
                    .foregroundColor(.orange)
                    .font(.custom("Phatt", size: 14))
            }
        }
    }

    private var importedLeaguesList: some View {
        VStack {
            if leagueManager.leagues.isEmpty {
                Text("No imported leagues yet.")
                    .foregroundColor(.gray)
            } else {
                List(leagueManager.leagues, id: \.id) { league in
                    HStack(spacing: 12) {
                        Button {
                            Task { await syncLeague(leagueId: league.id) }
                        } label: {
                            Image(systemName: "arrow.clockwise.circle")
                                .font(.system(size: 24))
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(PlainButtonStyle())

                        VStack(alignment: .leading) {
                            Text(league.name)
                                .font(.custom("Phatt", size: 18))
                                .foregroundColor(.orange)
                            Text("Teams: \(league.teams.count)")
                                .font(.custom("Phatt", size: 14))
                                .foregroundColor(.white)
                        }
                    }
                    .listRowBackground(Color.black)
                }
                .background(Color.clear)
                .scrollContentBackground(.hidden)
                .cornerRadius(16)
                .shadow(color: .blue.opacity(0.3), radius: 6)
            }
        }
    }

    // MARK: Actions

    private func fetchLeagues() async {
        isLoading = true
        errorMessage = nil
        fetchedLeagues = []
        selectedLeagueId = ""
        do {
            let currentSeason = Calendar.current.component(.year, from: Date())
            let startSeason = currentSeason - 9
            let seasons = (startSeason...currentSeason).map { "\($0)" }
            let leagues = try await leagueManager.fetchAllLeaguesForUser(username: sleeperUsername, seasons: seasons)
            fetchedLeagues = leagues
            if let first = activeLeagues.first {
                selectedLeagueId = first.league_id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func importSelectedLeague() async {
        guard !selectedLeagueId.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            if let dsdUser = authViewModel.currentUsername {
                leagueManager.setActiveUser(username: dsdUser)
            }
            // PATCH: Fetch userId explicitly for correct team selection logic
            let sleeperUser = try await leagueManager.fetchUser(username: sleeperUsername)
            let sleeperUserId = sleeperUser.user_id

            // Persist userId in AuthViewModel if logged in
            if let dsdUser = authViewModel.currentUsername {
                UserDefaults.standard.set(sleeperUserId, forKey: "sleeperUserId_\(dsdUser)")
                authViewModel.sleeperUserId = sleeperUserId
                // Persist the Sleeper username for this DSD user so the field is prefilled next time
                UserDefaults.standard.set(sleeperUsername, forKey: "sleeperUsername_\(dsdUser)")
            }

            // Import league using full userId context
            try await leagueManager.fetchAndImportSingleLeague(
                leagueId: selectedLeagueId,
                username: sleeperUsername
            )
            UserDefaults.standard.set(sleeperUsername, forKey: "sleeperUsername_for_\(selectedLeagueId)")
            if let dsdUser = authViewModel.currentUsername {
                appSelection.updateLeagues(
                    leagueManager.leagues,
                    username: dsdUser,
                    sleeperUserId: sleeperUserId
                )
                UserDefaults.standard.set(true, forKey: "hasImportedLeague_\(dsdUser)")
            } else {
                appSelection.updateLeagues(
                    leagueManager.leagues,
                    sleeperUserId: sleeperUserId
                )
            }

            // Call the callback with the new league ID to auto-select it in the dashboard
            if let callback = onLeagueImported {
                callback(selectedLeagueId)
            }

            // Save the league selection to UserDefaults
            let key = "dsd.lastSelectedLeague.\(authViewModel.currentUsername ?? "anon")"
            UserDefaults.standard.set(selectedLeagueId, forKey: key)

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func syncLeague(leagueId: String) async {
        isLoading = true
        errorMessage = nil
        if let username = UserDefaults.standard.string(forKey: "sleeperUsername_for_\(leagueId)") {
            do {
                if let dsdUser = authViewModel.currentUsername {
                    leagueManager.setActiveUser(username: dsdUser)
                }
                // PATCH: Fetch userId for sync
                let sleeperUser = try await leagueManager.fetchUser(username: username)
                let sleeperUserId = sleeperUser.user_id
                if let dsdUser = authViewModel.currentUsername {
                    UserDefaults.standard.set(sleeperUserId, forKey: "sleeperUserId_\(dsdUser)")
                    authViewModel.sleeperUserId = sleeperUserId
                    // Also save the Sleeper username for this DSD user (helps prefill next time)
                    UserDefaults.standard.set(username, forKey: "sleeperUsername_\(dsdUser)")
                }
                try await leagueManager.fetchAndImportSingleLeague(
                    leagueId: leagueId,
                    username: username
                )
                if let dsdUser = authViewModel.currentUsername {
                    appSelection.updateLeagues(
                        leagueManager.leagues,
                        username: dsdUser,
                        sleeperUserId: sleeperUserId
                    )
                } else {
                    appSelection.updateLeagues(
                        leagueManager.leagues,
                        sleeperUserId: sleeperUserId
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            errorMessage = "No Sleeper username found for this league. Please re-import it."
        }
        isLoading = false
    }
}
