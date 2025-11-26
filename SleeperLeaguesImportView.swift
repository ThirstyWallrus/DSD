//
//  SleeperLeaguesImportView.swift
//  DynastyStatDrop
//
//  Import UI for Sleeper leagues.
//  - Allows user to fetch their Sleeper leagues by username
//  - Presents a per-season "Playoff start week" override UI prior to importing a league
//  - Passes per-season overrides into SleeperLeagueManager.fetchAndImportSingleLeague(..., seasonPlayoffOverrides:)
//  - Persists the chosen sleeper username per DSD user (UserDefaults) to prefill later
//
//  Notes:
//  - This file intentionally contains all import/UI wiring for per-season overrides.
//  - The manager is responsible for persisting the overrides to disk when fetchAndImportSingleLeague is called.
//  - The UI presents a sheet that lists all seasons we discovered that seem to belong to the same base league
//    and allows adjusting a week integer between 13 and 18 per season.
//  - No destructive changes are performed in this view; it only calls manager APIs.
//

import SwiftUI

struct SleeperLeaguesImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appSelection: AppSelection
    @EnvironmentObject var leagueManager: SleeperLeagueManager

    /// Optional callback so the caller (Dashboard) can auto-select the imported league
    let onLeagueImported: ((String) -> Void)?

    // MARK: - UI state
    @State private var sleeperUsername: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    // Raw fetched Sleeper league objects (multi-season results for the entered username)
    @State private var fetchedLeagues: [SleeperLeague] = []

    // Selected league (the user picks from current-season leagues)
    @State private var selectedLeagueId: String = ""
    @State private var selectedPlatform: Platform? = nil

    // Per-season overrides (seasonId -> selected playoff start week)
    // This is the map we populate prior to calling the manager's import overload.
    @State private var seasonPlayoffOverrides: [String: Int] = [:]

    // Preview seasons that belong to the selected base league (used to show the sheet)
    @State private var previewSeasons: [SleeperLeague] = []

    // Controls sheet presentation
    @State private var showPlayoffOverridesSheet: Bool = false

    // UI constants
    private let menuHeight: CGFloat = 36
    private let leagueMenuWidth: CGFloat = 220

    var body: some View {
        ZStack {
            Image("Background1")
                .resizable()
                .ignoresSafeArea(edges: .all)
            content
        }
        .navigationTitle("Import Leagues")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPlayoffOverridesSheet) {
            NavigationView {
                VStack(spacing: 12) {
                    Text("Playoff start weeks (per season)")
                        .font(.headline)
                        .padding(.top, 8)

                    ScrollView {
                        VStack(spacing: 12) {
                            if previewSeasons.isEmpty {
                                Text("No seasons found to override.")
                                    .foregroundColor(.gray)
                                    .padding()
                            } else {
                                // Sort seasons ascending by year for nicer ordering
                                ForEach(previewSeasons.sorted(by: { ($0.season ?? "") < ($1.season ?? "") }), id: \.league_id) { sl in
                                    let seasonId = sl.season ?? "\(Calendar.current.component(.year, from: Date()))"
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text("Season: \(seasonId)")
                                                .font(.subheadline.bold())
                                            // Show detected/default value and whether override exists
                                            let auto = leagueManager.detectPlayoffStartWeek(from: sl)
                                            let used = seasonPlayoffOverrides[seasonId] ?? auto
                                            Text("Detected: Week \(used) (source: \(seasonPlayoffOverrides[seasonId] != nil ? "override" : "auto"))")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        Spacer()
                                        Stepper("\(seasonPlayoffOverrides[seasonId] ?? leagueManager.detectPlayoffStartWeek(from: sl))",
                                                value: Binding(
                                                    get: { seasonPlayoffOverrides[seasonId] ?? leagueManager.detectPlayoffStartWeek(from: sl) },
                                                    set: { seasonPlayoffOverrides[seasonId] = max(13, min(18, $0)) }
                                                ),
                                                in: 13...18)
                                            .labelsHidden()
                                    }
                                    .padding()
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.35)))
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    HStack {
                        Button("Cancel") {
                            showPlayoffOverridesSheet = false
                        }
                        .padding()
                        Spacer()
                        Button("Import with overrides") {
                            Task {
                                showPlayoffOverridesSheet = false
                                await performImportWithOverrides()
                            }
                        }
                        .disabled(selectedLeagueId.isEmpty || isLoading)
                        .padding()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
                .navigationBarTitle("Playoff Overrides", displayMode: .inline)
            }
        }
        .onAppear {
            if let dsdUser = authViewModel.currentUsername {
                // Pre-fill Sleeper username persisted per DSD user
                if let saved = UserDefaults.standard.string(forKey: "sleeperUsername_\(dsdUser)") {
                    sleeperUsername = saved
                }
                // Ensure manager is set to current DSD user context
                leagueManager.setActiveUser(username: dsdUser)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            platformSelectionView
            if selectedPlatform == .sleeper {
                sleeperContent
            } else {
                Text("Select a platform to continue")
                    .foregroundColor(.orange)
            }
            Spacer()
        }
        .padding(.top, 28)
    }

    private var platformSelectionView: some View {
        HStack(spacing: 20) {
            ForEach(Platform.allCases, id: \.rawValue) { platform in
                Button {
                    selectedPlatform = platform
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(selectedPlatform == platform ? Color.blue : Color.gray)
                            .frame(width: 12, height: 12)
                        Text(platform.rawValue)
                            .font(.custom("Phatt", size: 16))
                            .foregroundColor(.orange)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.4)))
                }
            }
        }
        .padding(.horizontal)
    }

    private var sleeperContent: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Enter Sleeper username", text: $sleeperUsername)
                    .padding(10)
                    .font(.custom("Phatt", size: 16))
                    .foregroundColor(.orange)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.black))
                    .frame(height: menuHeight)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)

                Button("Fetch Leagues") {
                    Task { await fetchLeagues() }
                }
                .disabled(sleeperUsername.isEmpty || isLoading)
                .bold()
                .font(.custom("Phatt", size: 16))
                .padding(.horizontal, 12)
                .frame(height: menuHeight)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black))
            }
            .padding(.horizontal)

            if isLoading {
                ProgressView("Loading…")
            }
            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .font(.custom("Phatt", size: 13))
                    .padding(.horizontal)
            }

            leaguesPicker
                .padding(.horizontal)
        }
    }

    private var leaguesPicker: some View {
        VStack(spacing: 8) {
            let currentYear = Calendar.current.component(.year, from: Date())
            let active = fetchedLeagues.filter { $0.season == "\(currentYear)" }
            if !active.isEmpty {
                Picker("Select League", selection: $selectedLeagueId) {
                    ForEach(active, id: \.league_id) { lg in
                        Text(lg.name ?? "Unnamed League")
                            .tag(lg.league_id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: leagueMenuWidth)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.35)))

                HStack(spacing: 12) {
                    Button("Preview / Set Playoff Weeks") {
                        preparePreviewSeasonsAndShowSheet()
                    }
                    .disabled(selectedLeagueId.isEmpty)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.4)))

                    Button("Import using detected defaults") {
                        Task { await importSelectedLeague(useOverrides: false) }
                    }
                    .disabled(selectedLeagueId.isEmpty || isLoading)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.4)))
                }
            } else if !fetchedLeagues.isEmpty {
                Text("No active leagues found for the current season.")
                    .foregroundColor(.orange)
            } else {
                Text("Enter a Sleeper username and tap Fetch Leagues.")
                    .foregroundColor(.gray)
            }
        }
    }

    // MARK: - Actions

    /// Fetch leagues for the provided Sleeper username across recent seasons (uses manager helper)
    private func fetchLeagues() async {
        isLoading = true
        errorMessage = nil
        fetchedLeagues = []
        selectedLeagueId = ""
        do {
            let currentYear = Calendar.current.component(.year, from: Date())
            let startYear = currentYear - 9
            let seasons = (startYear...currentYear).map { "\($0)" }
            let leagues = try await leagueManager.fetchAllLeaguesForUser(username: sleeperUsername, seasons: seasons)
            fetchedLeagues = leagues
            // preselect first current-season league if any
            if let first = fetchedLeagues.first(where: { $0.season == "\(currentYear)" }) {
                selectedLeagueId = first.league_id
            } else {
                selectedLeagueId = fetchedLeagues.first?.league_id ?? ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Prepares previewSeasons by grouping all fetchedLeagues that share the same base league name
    /// and initializes seasonPlayoffOverrides with detected values.
    private func preparePreviewSeasonsAndShowSheet() {
        guard !selectedLeagueId.isEmpty else { return }
        // Find the selected league object (current-season)
        guard let selected = fetchedLeagues.first(where: { $0.league_id == selectedLeagueId }) else {
            // Fallback: use any league with the same id (shouldn't happen)
            previewSeasons = []
            return
        }

        // Determine base name (strip emoji/punctuation similar to manager's baseLeagueName)
        func baseLeagueName(_ name: String?) -> String {
            guard let name = name else { return "" }
            let pattern = "[\\p{Emoji}\\p{Emoji_Presentation}\\p{Emoji_Modifier_Base}\\p{Emoji_Component}\\p{Symbol}\\p{Punctuation}]"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(location: 0, length: name.utf16.count)
                let stripped = regex.stringByReplacingMatches(in: name, options: [], range: range, withTemplate: "")
                return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let base = baseLeagueName(selected.name)
        // Keep any fetched league whose base name equals the selected one (cross-season)
        let matches = fetchedLeagues.filter { baseLeagueName($0.name) == base }

        previewSeasons = matches

        // Initialize overrides for each season (prefill with either previously persisted override or auto-detected)
        var map: [String: Int] = [:]
        for sl in previewSeasons {
            let sid = sl.season ?? "\(Calendar.current.component(.year, from: Date()))"
            // If manager has a persisted override for this league+season, prefer it
            if let persisted = leagueManager.leagueSeasonPlayoffOverrides[selectedLeagueId]?[sid] {
                map[sid] = persisted
            } else {
                // Otherwise auto-detect using manager helper
                let auto = leagueManager.detectPlayoffStartWeek(from: sl)
                map[sid] = auto
            }
        }
        seasonPlayoffOverrides = map
        showPlayoffOverridesSheet = true
    }

    /// Import selected league. If useOverrides==true this will use existing seasonPlayoffOverrides map
    /// otherwise it will call the manager overload with nil overrides (defaults are used).
    private func importSelectedLeague(useOverrides: Bool) async {
        guard !selectedLeagueId.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        do {
            // Ensure manager context set
            if let dsdUser = authViewModel.currentUsername {
                leagueManager.setActiveUser(username: dsdUser)
            }

            // Fetch Sleeper user to obtain user_id (used to update appSelection)
            let sleeperUser = try await leagueManager.fetchUser(username: sleeperUsername)
            let sleeperUserId = sleeperUser.user_id

            // Persist userId and username per DSD user if logged in
            if let dsdUser = authViewModel.currentUsername {
                UserDefaults.standard.set(sleeperUserId, forKey: "sleeperUserId_\(dsdUser)")
                authViewModel.sleeperUserId = sleeperUserId
                // Persist username for this DSD user so field is prefilled later
                UserDefaults.standard.set(sleeperUsername, forKey: "sleeperUsername_\(dsdUser)")
            }

            if useOverrides {
                // Pass per-season overrides to manager; manager will persist them for the league.
                try await leagueManager.fetchAndImportSingleLeague(leagueId: selectedLeagueId, username: sleeperUsername, seasonPlayoffOverrides: seasonPlayoffOverrides)
            } else {
                // No overrides param => manager will auto-detect per season
                try await leagueManager.fetchAndImportSingleLeague(leagueId: selectedLeagueId, username: sleeperUsername, seasonPlayoffOverrides: nil)
            }

            // Persist a quick mapping of the username to league id for convenience on re-sync
            UserDefaults.standard.set(sleeperUsername, forKey: "sleeperUsername_for_\(selectedLeagueId)")

            // Update the appSelection and notify caller
            if let dsdUser = authViewModel.currentUsername {
                appSelection.updateLeagues(leagueManager.leagues, username: dsdUser, sleeperUserId: sleeperUserId)
                UserDefaults.standard.set(true, forKey: "hasImportedLeague_\(dsdUser)")
            } else {
                appSelection.updateLeagues(leagueManager.leagues, sleeperUserId: sleeperUserId)
            }

            // Callback to parent (dashboard) so it can auto-select the imported league
            onLeagueImported?(selectedLeagueId)

            // Persist last selected league for this DSD user
            let key = "dsd.lastSelectedLeague.\(authViewModel.currentUsername ?? "anon")"
            UserDefaults.standard.set(selectedLeagueId, forKey: key)

            // Dismiss UI
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Called from the "Import with overrides" button in the Sheet
    private func performImportWithOverrides() async {
        // showPlayoffOverridesSheet already dismissed by caller
        await importSelectedLeague(useOverrides: true)
    }
}

// MARK: - Platform enum (same as other files)
enum Platform: String, CaseIterable {
    case sleeper = "Sleeper"
    case yahoo = "Yahoo"
    case espn = "ESPN"
}

// MARK: - Previews
struct SleeperLeaguesImportView_Previews: PreviewProvider {
    static var previews: some View {
        // Minimal preview harness: create dummy environment objects to avoid crashes in preview.
        let auth = AuthViewModel()
        let appSel = AppSelection()
        let mgr = SleeperLeagueManager(autoLoad: false)
        SleeperLeaguesImportView(onLeagueImported: nil)
            .environmentObject(auth)
            .environmentObject(appSel)
            .environmentObject(mgr)
    }
}
