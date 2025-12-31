//
//  SleeperLeaguesImportView.swift
//  DynastyStatDrop
//
//  Updated: Playoff settings are mandatory for every season before import.
//  No auto-detected defaults; user must enter all four fields per season.
//

import SwiftUI

private struct SeasonInputForm: Equatable {
    var playoffStartWeek: Int? = nil
    var championshipWeek: Int? = nil
    var championshipLength: String = "" // "1" or "2"
    var playoffTeams: Int? = nil
}

struct SleeperLeaguesImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appSelection: AppSelection
    @EnvironmentObject var leagueManager: SleeperLeagueManager

    let onLeagueImported: ((String) -> Void)?

    @State private var sleeperUsername: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    @State private var fetchedLeagues: [SleeperLeague] = []
    @State private var selectedLeagueId: String = ""
    @State private var selectedPlatform: Platform? = nil

    @State private var seasonForms: [String: SeasonInputForm] = [:]
    @State private var previewSeasons: [SleeperLeague] = []
    @State private var showPlayoffOverridesSheet: Bool = false

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
                    Text("Playoff settings (required per season)")
                        .font(.headline)
                        .padding(.top, 8)

                    ScrollView {
                        VStack(spacing: 12) {
                            if previewSeasons.isEmpty {
                                Text("No seasons found.")
                                    .foregroundColor(.gray)
                                    .padding()
                            } else {
                                ForEach(previewSeasons.sorted(by: { ($0.season ?? "") < ($1.season ?? "") }), id: \.league_id) { sl in
                                    let seasonId = sl.season ?? "\(Calendar.current.component(.year, from: Date()))"
                                    let form = seasonForms[seasonId] ?? SeasonInputForm()
                                    let champBinding = Binding<Int>(
                                        get: { form.championshipWeek ?? 15 },
                                        set: { seasonForms[seasonId, default: SeasonInputForm()].championshipWeek = max(1, min(18, $0)) }
                                    )
                                    let teamsBinding = Binding<Int>(
                                        get: { form.playoffTeams ?? defaultPlayoffTeams(for: sl) },
                                        set: { seasonForms[seasonId, default: SeasonInputForm()].playoffTeams = max(2, min(16, $0)) }
                                    )
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Season: \(seasonId)")
                                            .font(.subheadline.bold())

                                        TextField("Playoff Start Week (13-18)", text: Binding(
                                            get: { (seasonForms[seasonId]?.playoffStartWeek).map(String.init) ?? "" },
                                            set: { seasonForms[seasonId, default: SeasonInputForm()].playoffStartWeek = Int($0) }
                                        ))
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())

                                        HStack {
                                            Text("Championship Week")
                                                .font(.custom("Phatt", size: 15))
                                                .foregroundColor(.orange)
                                            Spacer()
                                            Stepper(value: champBinding, in: 1...18) {
                                                Text("Week \(champBinding.wrappedValue)")
                                                    .font(.custom("Phatt", size: 15))
                                                    .foregroundColor(.orange)
                                            }
                                            .tint(.orange)
                                        }

                                        Picker("Championship length", selection: Binding(
                                            get: { seasonForms[seasonId]?.championshipLength ?? "" },
                                            set: { seasonForms[seasonId, default: SeasonInputForm()].championshipLength = $0 }
                                        )) {
                                            Text("Select").tag("")
                                            Text("1 week").tag("1")
                                            Text("2 weeks").tag("2")
                                        }
                                        .pickerStyle(SegmentedPickerStyle())

                                        HStack {
                                            Text("Playoff Teams")
                                                .font(.custom("Phatt", size: 15))
                                                .foregroundColor(.orange)
                                            Spacer()
                                            Stepper(value: teamsBinding, in: 2...16) {
                                                Text("\(teamsBinding.wrappedValue)")
                                                    .font(.custom("Phatt", size: 15))
                                                    .foregroundColor(.orange)
                                            }
                                            .tint(.orange)
                                        }

                                        Text(requiredStatus(form: seasonForms[seasonId] ?? SeasonInputForm()))
                                            .font(.caption2)
                                            .foregroundColor(.gray)
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
                        Button("Save & Import") {
                            Task {
                                showPlayoffOverridesSheet = false
                                await performImport()
                            }
                        }
                        .disabled(selectedLeagueId.isEmpty || isLoading)
                        .padding()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
                .navigationBarTitle("Playoff Settings", displayMode: .inline)
            }
        }
        .onAppear {
            if let dsdUser = authViewModel.currentUsername {
                if let saved = UserDefaults.standard.string(forKey: "sleeperUsername_\(dsdUser)") {
                    sleeperUsername = saved
                }
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
                    Button("Set Playoff Settings & Import") {
                        preparePreviewSeasonsAndShowSheet()
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

    // MARK: - Helpers / Bindings

    private func requiredStatus(form: SeasonInputForm) -> String {
        if form.playoffStartWeek == nil || form.championshipWeek == nil || form.championshipLength.isEmpty || form.playoffTeams == nil {
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
            let currentYear = Calendar.current.component(.year, from: Date())
            let startYear = currentYear - 9
            let seasons = (startYear...currentYear).map { "\( $0)" }
            let leagues = try await leagueManager.fetchAllLeaguesForUser(username: sleeperUsername, seasons: seasons)
            fetchedLeagues = leagues
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
            if let persisted = leagueManager.leagueSeasonOverrides[selectedLeagueId]?[sid] {
                map[sid] = SeasonInputForm(
                    playoffStartWeek: persisted.playoffStartWeek,
                    championshipWeek: persisted.championshipWeek ?? 15,
                    championshipLength: persisted.championshipIsTwoWeeks == true ? "2" : (persisted.championshipIsTwoWeeks == false ? "1" : ""),
                    playoffTeams: persisted.playoffTeamsCount ?? defaultPlayoffTeams(for: sl)
                )
            } else {
                map[sid] = SeasonInputForm(
                    playoffStartWeek: nil,
                    championshipWeek: 15,
                    championshipLength: "",
                    playoffTeams: defaultPlayoffTeams(for: sl)
                )
            }
        }
        seasonForms = map
        showPlayoffOverridesSheet = true
    }

    private func performImport() async {
        guard !selectedLeagueId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            if let dsdUser = authViewModel.currentUsername {
                leagueManager.setActiveUser(username: dsdUser)
            }

            let sleeperUser = try await leagueManager.fetchUser(username: sleeperUsername)
            let sleeperUserId = sleeperUser.user_id

            if let dsdUser = authViewModel.currentUsername {
                UserDefaults.standard.set(sleeperUserId, forKey: "sleeperUserId_\(dsdUser)")
                authViewModel.sleeperUserId = sleeperUserId
                UserDefaults.standard.set(sleeperUsername, forKey: "sleeperUsername_\(dsdUser)")
            }

            guard let overrides = buildOverrides() else {
                errorMessage = "Please fill all playoff settings for every season."
                return
            }

            try await leagueManager.fetchAndImportSingleLeague(leagueId: selectedLeagueId, username: sleeperUsername, seasonOverrides: overrides)

            UserDefaults.standard.set(sleeperUsername, forKey: "sleeperUsername_for_\(selectedLeagueId)")

            if let dsdUser = authViewModel.currentUsername {
                appSelection.updateLeagues(leagueManager.leagues, username: dsdUser, sleeperUserId: sleeperUserId)
                UserDefaults.standard.set(true, forKey: "hasImportedLeague_\(dsdUser)")
            } else {
                appSelection.updateLeagues(leagueManager.leagues, sleeperUserId: sleeperUserId)
            }

            onLeagueImported?(selectedLeagueId)
            let key = "dsd.lastSelectedLeague.\(authViewModel.currentUsername ?? "anon")"
            UserDefaults.standard.set(selectedLeagueId, forKey: key)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildOverrides() -> [String: SeasonImportOverrides]? {
        guard !seasonForms.isEmpty else { return nil }
        var result: [String: SeasonImportOverrides] = [:]
        for (sid, form) in seasonForms {
            guard
                let ps = form.playoffStartWeek, (13...18).contains(ps),
                let cw = form.championshipWeek, (1...18).contains(cw),
                let len = Int(form.championshipLength), (1...2).contains(len),
                let teams = form.playoffTeams, (2...16).contains(teams)
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

    private func defaultPlayoffTeams(for league: SleeperLeague) -> Int {
        let count = league.total_rosters ?? 10
        return count >= 10 ? 6 : 4
    }
}

// MARK: - Helpers (local)
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

// MARK: - Platform enum
enum Platform: String, CaseIterable {
    case sleeper = "Sleeper"
    case yahoo = "Yahoo"
    case espn = "ESPN"
}
