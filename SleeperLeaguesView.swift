//
//  SleeperLeaguesView.swift
//  DynastyStatDrop
//
//  PATCHED:
//   • Propagates Sleeper userId and username to AppSelection after import, for correct team selection
//   • Ensures AppSelection picks user’s own team (via ownerId) after importing a league
//   • Prefills the username input with the previously-saved Sleeper username for the current DSD user
//   • No UI/visual changes, preserves all existing logic and continuity
//
//  NEW (Playoff start selection):
//   • Adds a per-season playoff start week selector (sheet) before importing.
//   • Uses SleeperLeagueManager.detectPlayoffStartWeek to prefill and persists overrides through import.
//

import SwiftUI

struct SleeperLeaguesView: View {
    // Optional external context for showing a selected team/roster (if embedded somewhere)
    let selectedTeam: String
    let roster: [(name: String, position: String)]

    // Use the shared manager injected at app root (DO NOT create a new instance here).
    @EnvironmentObject private var manager: SleeperLeagueManager
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var appSelection: AppSelection

    @State private var username: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var fetchedLeagues: [SleeperLeague] = []
    @State private var selectedLeagueId: String = ""

    // NEW: Playoff start overrides UI state
    @State private var showPlayoffOverridesSheet: Bool = false
    @State private var seasonPlayoffOverrides: [String: Int] = [:]   // seasonId -> week
    @State private var previewSeasons: [SleeperLeague] = []

    private var activeSeasonLeagues: [SleeperLeague] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return fetchedLeagues.filter { $0.season == "\(currentYear)" }
    }

    private var remainingSlots: Int {
        manager.remainingSlots()
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                headerRow
                limitsRow
                fetchResultsBlock
                importedLeaguesList
                selectedTeamBlock
                Spacer()
            }
            .navigationTitle("Sleeper Leagues")
            .onAppear {
                // Ensure persisted leagues are loaded (safe idempotent)
                manager.loadLeagues()

                // Prefill the Sleeper username input if the logged-in DSD user has one saved
                if let dsdUser = authViewModel.currentUsername,
                   let saved = UserDefaults.standard.string(forKey: "sleeperUsername_\(dsdUser)") {
                    username = saved
                }
            }
            // Playoff overrides sheet
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
                                    ForEach(previewSeasons.sorted(by: { ($0.season ?? "") < ($1.season ?? "") }), id: \.league_id) { sl in
                                        let seasonId = sl.season ?? "\(Calendar.current.component(.year, from: Date()))"
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text("Season: \(seasonId)")
                                                    .font(.subheadline.bold())
                                                let auto = manager.detectPlayoffStartWeek(from: sl)
                                                let used = seasonPlayoffOverrides[seasonId] ?? auto
                                                Text("Detected: Week \(used) (source: \(seasonPlayoffOverrides[seasonId] != nil ? "override" : "auto"))")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                            Spacer()
                                            Stepper("\(seasonPlayoffOverrides[seasonId] ?? manager.detectPlayoffStartWeek(from: sl))",
                                                    value: Binding(
                                                        get: { seasonPlayoffOverrides[seasonId] ?? manager.detectPlayoffStartWeek(from: sl) },
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
                            Button("Cancel") { showPlayoffOverridesSheet = false }
                                .padding()
                            Spacer()
                            Button("Import with overrides") {
                                Task {
                                    showPlayoffOverridesSheet = false
                                    await importSelectedLeague(useOverrides: true)
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
        }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(spacing: 10) {
            TextField("Enter Sleeper username", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)

            Button("Fetch") {
                Task { await fetchLeagues() }
            }
            .disabled(username.isEmpty || isLoading)
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private var limitsRow: some View {
        HStack {
            Text("Imported: \(manager.leagues.count)/\(manager.currentLimit()) • Remaining: \(remainingSlots)")
                .font(.footnote.monospaced())
                .foregroundColor(remainingSlots == 0 ? .yellow : .white.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal)
    }

    private var fetchResultsBlock: some View {
        VStack(spacing: 14) {
            if isLoading { ProgressView("Loading leagues...") }

            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            if !activeSeasonLeagues.isEmpty {
                Picker("Select League", selection: $selectedLeagueId) {
                    ForEach(activeSeasonLeagues, id: \.league_id) { league in
                        Text(league.name ?? "Unnamed League")
                            .tag(league.league_id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.horizontal)

                HStack(spacing: 10) {
                    Button("Set Playoff Settings & Import") {
                        preparePreviewSeasonsAndShowSheet()
                    }
                    .disabled(selectedLeagueId.isEmpty || isLoading)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }

                if !manager.canImportAnother() {
                    Text("League limit reached. Remove one to import another.")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
            } else if !fetchedLeagues.isEmpty {
                Text("No active (current season) leagues found.")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
        }
    }

    private var importedLeaguesList: some View {
        List {
            Section(header: Text("Imported Leagues")) {
                if manager.leagues.isEmpty {
                    Text("None imported yet.")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(manager.leagues) { league in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(league.name)
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Seasons: \(league.seasons.count)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .onDelete(perform: deleteLeague)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }

    private var selectedTeamBlock: some View {
        Group {
            if !selectedTeam.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Selected Team: \(selectedTeam)")
                        .font(.headline)
                        .foregroundColor(.orange)
                    Text("Roster")
                        .font(.subheadline.bold())
                        .foregroundColor(.white.opacity(0.85))
                    ForEach(roster, id: \.name) { player in
                        Text("• \(player.name) – \(player.position)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Bindings/defaults

    private func binding(for seasonId: String) -> (
        playoffStartWeek: Binding<String>,
        championshipWeek: Binding<String>,
        championshipLength: Binding<String>,
        playoffTeams: Binding<String>
    ) {
        let form = seasonForms[seasonId] ?? SeasonInputForm()
        return (
            playoffStartWeek: Binding(
                get: { form.playoffStartWeek },
                set: { seasonForms[seasonId, default: SeasonInputForm()].playoffStartWeek = $0 }
            ),
            championshipWeek: Binding(
                get: { form.championshipWeek },
                set: { seasonForms[seasonId, default: SeasonInputForm()].championshipWeek = $0 }
            ),
            championshipLength: Binding(
                get: { form.championshipLength },
                set: { seasonForms[seasonId, default: SeasonInputForm()].championshipLength = $0 }
            ),
            playoffTeams: Binding(
                get: { form.playoffTeams },
                set: { seasonForms[seasonId, default: SeasonInputForm()].playoffTeams = $0 }
            )
        )
    }

    private func requiredStatus(form: SeasonInputForm) -> String {
        if form.playoffStartWeek.isEmpty || form.championshipWeek.isEmpty || form.championshipLength.isEmpty || form.playoffTeams.isEmpty {
            return "All fields required."
        }
        return "Ready."
    }

    // MARK: - Actions

    private func fetchLeagues() async {
        isLoading = true
        errorMessage = nil
        fetchedLeagues = []
        selectedLeagueId = ""
        do {
            let currentSeason = Calendar.current.component(.year, from: Date())
            let seasons = (currentSeason - 9 ... currentSeason).map { "\($0)" }
            let leagues = try await manager.fetchAllLeaguesForUser(username: username, seasons: seasons)
            fetchedLeagues = leagues
            selectedLeagueId = activeSeasonLeagues.first?.league_id ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func preparePreviewSeasonsAndShowSheet() {
        guard !selectedLeagueId.isEmpty else { return }
        guard let selected = fetchedLeagues.first(where: { $0.league_id == selectedLeagueId }) else {
            previewSeasons = []
            return
        }

        let base = baseLeagueName(selected.name)
        let matches = fetchedLeagues.filter { baseLeagueName($0.name) == base }
        previewSeasons = matches

        var map: [String: SeasonInputForm] = [:]
        for sl in previewSeasons {
            let sid = sl.season ?? "\(Calendar.current.component(.year, from: Date()))"
            if let persisted = manager.leagueSeasonOverrides[selectedLeagueId]?[sid] {
                map[sid] = SeasonInputForm(
                    playoffStartWeek: persisted.playoffStartWeek.map(String.init) ?? "",
                    championshipWeek: persisted.championshipWeek.map(String.init) ?? "",
                    championshipLength: persisted.championshipIsTwoWeeks == true ? "2" : (persisted.championshipIsTwoWeeks == false ? "1" : ""),
                    playoffTeams: persisted.playoffTeamsCount.map(String.init) ?? ""
                )
            } else {
                map[sid] = SeasonInputForm()
            }
        }
        seasonForms = map
        showPlayoffOverridesSheet = true
    }

    private func importSelectedLeague() async {
        guard manager.canImportAnother() || true, !selectedLeagueId.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let sleeperUser = try await manager.fetchUser(username: username)
            let sleeperUserId = sleeperUser.user_id

            if let dsdUser = authViewModel.currentUsername {
                UserDefaults.standard.set(sleeperUserId, forKey: "sleeperUserId_\(dsdUser)")
                authViewModel.sleeperUserId = sleeperUserId
                UserDefaults.standard.set(username, forKey: "sleeperUsername_\(dsdUser)")
            }

            guard let overrides = buildOverrides() else {
                errorMessage = "Please fill all playoff settings for every season."
                return
            }

            try await manager.fetchAndImportSingleLeague(
                leagueId: selectedLeagueId,
                username: username,
                seasonOverrides: overrides
            )

            if let dsdUser = authViewModel.currentUsername {
                appSelection.updateLeagues(
                    manager.leagues,
                    username: dsdUser,
                    sleeperUserId: sleeperUserId
                )
                UserDefaults.standard.set(true, forKey: "hasImportedLeague_\(dsdUser)")
            } else {
                appSelection.updateLeagues(
                    manager.leagues,
                    sleeperUserId: sleeperUserId
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildOverrides() -> [String: SeasonImportOverrides]? {
        guard !seasonForms.isEmpty else { return nil }
        var result: [String: SeasonImportOverrides] = [:]
        for (sid, form) in seasonForms {
            guard
                let ps = Int(form.playoffStartWeek), (13...18).contains(ps),
                let cw = Int(form.championshipWeek), (13...21).contains(cw),
                let len = Int(form.championshipLength), (1...2).contains(len),
                let teams = Int(form.playoffTeams), (2...16).contains(teams)
            else {
                return nil
            }
            result[sid] = SeasonImportOverrides(
                playoffStartWeek: ps,
                championshipWeek: cw,
                championshipIsTwoWeeks: (len == 2),
                playoffTeamsCount: teams
            )
        }
        return result
    }

    private func deleteLeague(at offsets: IndexSet) {
        for index in offsets {
            let league = manager.leagues[index]
            manager.removeLeague(leagueId: league.id)
        }
    }

    // MARK: - Helpers

    private func baseLeagueName(_ name: String?) -> String {
        guard let name = name else { return "" }
        let pattern = "[\\p{Emoji}\\p{Emoji_Presentation}\\p{Emoji_Modifier_Base}\\p{Emoji_Component}\\p{Symbol}\\p{Punctuation}]"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(location: 0, length: name.utf16.count)
            let stripped = regex.stringByReplacingMatches(in: name, options: [], range: range, withTemplate: "")
            return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
