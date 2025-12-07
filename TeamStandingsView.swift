//
//  TeamStandingsView.swift
//  DynastyStatDrop
//
//  NOTE: TeamStanding is now defined in LeagueData.swift (DO NOT redeclare)
//

import SwiftUI
import Foundation

// Limited enum for sorting inside this view only
enum StatCategory: String, CaseIterable {
    case teamName, leagueStanding, playoffStanding, allTimeStanding
    case pointsFor, maxPointsFor, winLossRecord, playoffRecord
    case managementPercentTeam, managementPercentOffense, managementPercentDefense
    case teamPointsPerWeek, offensePointsPerWeek, defensePointsPerWeek, pointsAgainstPerWeek
    case championshipWins
    case qbPointsPerWeek, rbPointsPerWeek, wrPointsPerWeek, tePointsPerWeek, kPointsPerWeek
    case dlPointsPerWeek, lbPointsPerWeek, dbPointsPerWeek
    case headToHeadRecord

    var abbreviation: String {
        switch self {
        case .teamName: return "Team"
        case .leagueStanding: return "Lg"
        case .playoffStanding: return "PO"
        case .allTimeStanding: return "AT"
        case .pointsFor: return "PF"
        case .maxPointsFor: return "MaxPF"
        case .winLossRecord: return "W-L"
        case .playoffRecord: return "PO Rec"
        case .managementPercentTeam: return "Mgmt%"
        case .managementPercentOffense: return "O-Mgmt%"
        case .managementPercentDefense: return "D-Mgmt%"
        case .teamPointsPerWeek: return "PPW"
        case .offensePointsPerWeek: return "OPPW"
        case .defensePointsPerWeek: return "DPPW"
        case .pointsAgainstPerWeek: return "PAPW"
        case .championshipWins: return "🏆"
        case .qbPointsPerWeek: return "QB PW"
        case .rbPointsPerWeek: return "RB PW"
        case .wrPointsPerWeek: return "WR PW"
        case .tePointsPerWeek: return "TE PW"
        case .kPointsPerWeek: return "K PW"
        case .dlPointsPerWeek: return "DL PW"
        case .lbPointsPerWeek: return "LB PW"
        case .dbPointsPerWeek: return "DB PW"
        case .headToHeadRecord: return "H2H"
        }
    }
}

struct TeamStandingsView: View {
    @EnvironmentObject var appSelection: AppSelection
    // NEW: leagueManager required to compute runtime ManagementCalculator values (and to access globalCurrentWeek)
    @EnvironmentObject var leagueManager: SleeperLeagueManager

    @State private var selectedTeam: String = ""
    @State private var selectedSeason = "All Time"
    @State private var selectedLeagueName = ""
    @State private var sortCategory: StatCategory? = nil

    private var league: LeagueData? {
        if selectedLeagueName.isEmpty {
            return appSelection.selectedLeague
        }
        return appSelection.leagues.first { $0.name == selectedLeagueName }
    }

    private var seasonNames: [String] {
        guard let league else { return ["All Time"] }
        let ids = league.seasons.map { $0.id }
        return ids + ["All Time"]
    }

    private var seasonObject: SeasonData? {
        guard let league, selectedSeason != "All Time" else { return nil }
        return league.seasons.first { $0.id == selectedSeason }
    }

    private var teams: [TeamStanding] {
        if let s = seasonObject { return s.teams }
        return league?.seasons.sorted(by: { $0.id > $1.id }).first?.teams ?? []
    }

    private var sortedTeams: [TeamStanding] {
        guard let cat = sortCategory else { return teams }
        return teams.sorted { statValue($0, cat) > statValue($1, cat) }
    }

    private var selectedTeamStanding: TeamStanding? {
        teams.first { $0.name == selectedTeam }
    }

    var body: some View {
        ZStack {
            Image("Background1")
                .resizable()
                .ignoresSafeArea()
            VStack(spacing: 12) {
                topMenus
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 6) {
                        StandingsHeaderRow(sortCategory: $sortCategory)
                        ForEach(sortedTeams, id: \.id) { team in
                            StandingsDataRow(
                                team: team,
                                selectedTeam: selectedTeam,
                                onSelect: { selectedTeam = team.name },
                                teams: teams
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                if let t = selectedTeamStanding {
                    rosterSection(team: t)
                }
                Spacer()
            }
        }
        .onAppear {
            selectedLeagueName = league?.name ?? ""
            selectedTeam = selectedTeamStanding?.name ?? teams.first?.name ?? ""
        }
    }

    private var topMenus: some View {
        HStack(spacing: 24) {
            Menu {
                ForEach(appSelection.leagues) { lg in
                    Button(lg.name) {
                        selectedLeagueName = lg.name
                        selectedSeason = "All Time"
                        selectedTeam = ""
                        sortCategory = nil
                    }
                }
            } label: {
                Text(selectedLeagueName.isEmpty ? "League" : selectedLeagueName)
                    .foregroundColor(.orange).bold()
            }

            Menu {
                ForEach(seasonNames, id: \.self) { s in
                    Button(s) {
                        selectedSeason = s
                        selectedTeam = ""
                        sortCategory = nil
                    }
                }
            } label: {
                Text(selectedSeason)
                    .foregroundColor(.orange).bold()
            }

            Menu {
                ForEach(teams, id: \.id) { t in
                    Button(t.name) { selectedTeam = t.name }
                }
            } label: {
                Text(selectedTeam.isEmpty ? "Team" : selectedTeam)
                    .foregroundColor(.orange).bold()
            }
        }
        .font(.custom("Phatt", size: 16))
        .padding(.top, 20)
    }

    /// Return the numeric stat value used for sorting and display in the standings table.
    /// NOTE: For maxPointsFor we now attempt to prefer the persisted TeamStanding value, and if missing/zero,
    /// compute a run-time max for a representative week (the latest meaningful week for the season) using
    /// ManagementCalculator.computeManagementForWeek(...).
    private func statValue(_ team: TeamStanding, _ category: StatCategory) -> Double {
        switch category {
        case .pointsFor: return team.pointsFor
        case .maxPointsFor:
            // Prefer persisted value if present to avoid expensive recompute for every row,
            // but if it's zero or missing attempt a runtime compute for the most-relevant week.
            if team.maxPointsFor > 0 {
                return team.maxPointsFor
            }
            // Attempt to determine a reasonable week to compute for:
            if let lg = league {
                // Prefer the selectedSeason if set; otherwise use the latest season in `league`.
                let seasonToUse = (selectedSeason != "All Time") ? (lg.seasons.first(where: { $0.id == selectedSeason }) ?? lg.seasons.sorted(by: { $0.id < $1.id }).last) : lg.seasons.sorted(by: { $0.id < $1.id }).last
                // Choose a sensible week: try the latest week key in matchupsByWeek, otherwise fall back to leagueManager.globalCurrentWeek.
                let weekToUse: Int = {
                    if let wkKeys = seasonToUse?.matchupsByWeek?.keys, !wkKeys.isEmpty {
                        // Prefer the most-recent meaningful week (max key)
                        return wkKeys.max() ?? max(1, leagueManager.globalCurrentWeek)
                    }
                    return max(1, leagueManager.globalCurrentWeek)
                }()
                // Compute using ManagementCalculator. This is conservative & best-effort.
                let (_, computedMax, _, _, _, _) = ManagementCalculator.computeManagementForWeek(team: team, week: weekToUse, league: lg, leagueManager: leagueManager)
                return computedMax
            }
            return team.maxPointsFor
        case .managementPercentTeam: return team.managementPercent
        case .teamPointsPerWeek: return team.teamPointsPerWeek
        default: return 0
        }
    }

    private func rosterSection(team: TeamStanding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Roster (positions)")
                .font(.custom("Phatt", size: 16))
                .foregroundColor(.orange)
            ForEach(team.roster, id: \.id) { player in
                Text("• \(player.position)") // no names by design
                    .font(.custom("Phatt", size: 12))
                    .foregroundColor(.white)
            }
        }
        .padding()
    }
}

// MARK: - Header Row
struct StandingsHeaderRow: View {
    @Binding var sortCategory: StatCategory?
    let widths: [CGFloat] = [120, 60, 60, 60, 80, 80, 80, 80, 80, 60, 60, 60, 60, 60,
                             60, 60, 60, 60, 60, 60, 60, 60, 60]
    let categories: [StatCategory] = [
        .teamName, .leagueStanding, .playoffStanding, .allTimeStanding,
        .winLossRecord, .playoffRecord, .managementPercentTeam, .managementPercentOffense,
        .managementPercentDefense, .teamPointsPerWeek, .offensePointsPerWeek,
        .defensePointsPerWeek, .pointsAgainstPerWeek, .championshipWins,
        .qbPointsPerWeek, .rbPointsPerWeek, .wrPointsPerWeek, .tePointsPerWeek,
        .kPointsPerWeek, .dlPointsPerWeek, .lbPointsPerWeek, .dbPointsPerWeek,
        .headToHeadRecord
    ]

    var body: some View {
        HStack {
            ForEach(Array(categories.enumerated()), id: \.element) { (i, cat) in
                Text(cat.abbreviation)
                    .foregroundColor(.orange)
                    .font(.custom("Phatt", size: 14))
                    .bold()
                    .frame(width: widths[i], alignment: .center)
                    .onTapGesture {
                        sortCategory = (sortCategory == cat) ? nil : cat
                    }
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }
}

// MARK: - Data Row
struct StandingsDataRow: View {
    let team: TeamStanding
    let selectedTeam: String
    let onSelect: () -> Void
    let teams: [TeamStanding]
    let widths: [CGFloat] = [120, 60, 60, 60, 80, 80, 80, 80, 80, 60, 60, 60, 60, 60,
                             60, 60, 60, 60, 60, 60, 60, 60, 60]

    var body: some View {
        HStack {
            cell(team.name, widths[0], true, onSelect)
            cell("\(team.leagueStanding)", widths[1])
            cell("--", widths[2]) // playoff rank placeholder
            cell("--", widths[3]) // all-time rank placeholder
            cell(team.winLossRecord ?? "--", widths[4])
            cell(team.playoffRecord ?? "--", widths[5])
            cell(String(format: "%.2f%%", team.managementPercent), widths[6])
            cell("--", widths[7])  // offense mgmt rank placeholder
            cell("--", widths[8])  // defense mgmt rank placeholder
            cell(String(format: "%.2f", team.teamPointsPerWeek), widths[9])
            cell("--", widths[10]) // offense PPW rank placeholder
            cell("--", widths[11]) // defense PPW rank placeholder
            cell("--", widths[12]) // points against per week rank placeholder
            cell("\(team.championships ?? 0)", widths[13])
            cell("--", widths[14]) // QB PPW rank placeholder
            cell("--", widths[15]) // RB PPW rank placeholder
            cell("--", widths[16]) // WR ...
            cell("--", widths[17])
            cell("--", widths[18])
            cell("--", widths[19])
            cell("--", widths[20])
            cell("--", widths[21])
        }
        .font(.custom("Phatt", size: 12))
        .background(team.name == selectedTeam ? Color.orange.opacity(0.18) : Color.clear)
        .cornerRadius(6)
    }

    private func cell(_ value: String, _ width: CGFloat, _ selectable: Bool = false, _ action: (() -> Void)? = nil) -> some View {
        Text(value)
            .foregroundColor(team.name == selectedTeam ? .yellow : .white)
            .frame(width: width)
            .contentShape(Rectangle())
            .onTapGesture {
                if selectable { action?() }
            }
    }
}
