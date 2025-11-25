//
//  SleeperLeaguesView.swift
//  DynastyStatDrop
//
//  PATCHED:
//   • Propagates Sleeper userId and username to AppSelection after import, for correct team selection
//   • Ensures AppSelection picks user's own team (via ownerId) after importing a league
//   • Prefills the username input with the previously-saved Sleeper username for the current DSD user
//   • No UI/visual changes, preserves all existing logic and continuity
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

                Button("Import Selected") {
                    Task { await downloadSelectedLeague() }
                }
                .disabled(!manager.canImportAnother() || selectedLeagueId.isEmpty || isLoading)
                .buttonStyle(.borderedProminent)
                .tint(.orange)

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

    private func downloadSelectedLeague() async {
        guard manager.canImportAnother(),
              !selectedLeagueId.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            // PATCH: Fetch Sleeper userId for correct team selection
            let sleeperUser = try await manager.fetchUser(username: username)
            let sleeperUserId = sleeperUser.user_id

            // Persist userId in AuthViewModel if logged in
            if let dsdUser = authViewModel.currentUsername {
                UserDefaults.standard.set(sleeperUserId, forKey: "sleeperUserId_\(dsdUser)")
                authViewModel.sleeperUserId = sleeperUserId
                // Persist the Sleeper username for this DSD user so it is pre-filled next time
                UserDefaults.standard.set(username, forKey: "sleeperUsername_\(dsdUser)")
            }

            try await manager.fetchAndImportSingleLeague(leagueId: selectedLeagueId, username: username)
            // PATCH: Propagate userId (and username) to AppSelection for correct team selection
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
        isLoading = false
    }

    private func deleteLeague(at offsets: IndexSet) {
        for index in offsets {
            let league = manager.leagues[index]
            manager.removeLeague(leagueId: league.id)
        }
    }
}
