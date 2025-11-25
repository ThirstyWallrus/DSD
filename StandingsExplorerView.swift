//
//  StandingsExplorerView.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 10/20/25.
//

//
//  StandingsExplorerView.swift
//  DynastyStatDrop
//
//  Standings Explorer reusable view (split from DSDDashboard.swift for clarity).
//

import SwiftUI

struct StandingsExplorerView: View {
    // Centralized selection: use AppSelection singleton
    @EnvironmentObject var appSelection: AppSelection

    let categories: [Category]
    let ascendingBetter: Set<Category>
    @Binding var selected: Category
    @Binding var searchText: String
    @Binding var showGrid: Bool
    let statProvider: (Category, TeamStanding) -> String
    let rankProvider: (Category, TeamStanding) -> String
    let colorForCategory: (Category) -> Color
    let onClose: () -> Void

    let isAllTimeMode: Bool
    let ownerAggProvider: (TeamStanding) -> AggregatedOwnerStats?
    let ascendingBetterStandings: Set<Category>

    let allTimeOwnerStats: [String: AggregatedOwnerStats]?
    @State private var internalScrollID = UUID()

    // -- Centralized selection --
    private var league: LeagueData? {
        appSelection.selectedLeague
    }
    private var teams: [TeamStanding] {
        guard let league = league else { return [] }
        if appSelection.selectedSeason == "All Time" {
            return league.seasons.sorted { $0.id < $1.id }.last?.teams ?? league.teams
        }
        return league.seasons.first(where: { $0.id == appSelection.selectedSeason })?.teams
            ?? league.seasons.sorted { $0.id < $1.id }.last?.teams
            ?? league.teams
    }
    private var myTeamId: String? {
        appSelection.selectedTeamId
    }
    private var selectedTeam: TeamStanding? {
        guard let id = myTeamId else { return nil }
        return teams.first(where: { $0.id == id })
    }
    private var selectedTeamRank: String {
        guard let team = selectedTeam else { return "--" }
        return rankProvider(selected, team)
    }
    private var selectedTeamDisplayName: String {
        guard let team = selectedTeam else { return "--" }
        return isAllTimeMode ? (ownerAggProvider(team)?.latestDisplayName ?? team.name) : team.name
    }

    var body: some View {
        VStack(spacing: 10) {
            headerBar
            categoryChips
            if showGrid { gridPlaceholder } else { rankingListView() }
        }
        .padding(10)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var headerBar: some View {
        HStack {
            Spacer()
            Text("Standings Explorer")
                .font(.custom("Phatt", size: 22))
                .foregroundColor(colorForCategory(selected))
                .underline()
            Spacer()
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    let sel = cat == selected
                    Text(cat.abbreviation)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Capsule().fill(sel ? colorForCategory(cat).opacity(0.85) : Color.gray.opacity(0.25)))
                        .overlay(
                            Capsule().stroke(colorForCategory(cat).opacity(sel ? 1 : 0.4), lineWidth: 1)
                        )
                        .foregroundColor(sel ? .black : .white)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                selected = cat
                                internalScrollID = UUID()
                            }
                        }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var filteredTeams: [TeamStanding] {
        teams
    }

    private func rankingListView() -> some View {
        let sorted = sortedTeams(for: selected, in: filteredTeams)
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 6) {
                    listHeader
                    ForEach(Array(sorted.enumerated()), id: \.1.id) { (idx, team) in
                        row(team: team, rank: idx + 1).id(team.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selected) { _, _ in
                let fresh = sortedTeams(for: selected, in: filteredTeams)
                if let my = myTeamId, fresh.contains(where: { $0.id == my }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation { proxy.scrollTo(my, anchor: .center) }
                    }
                }
            }
        }
    }

    private var listHeader: some View {
        HStack(spacing: 0) {
            Text("Rank")
                .frame(width: 46, alignment: .leading)
            Text("Team")
                .frame(minWidth: 70, maxWidth: .infinity, alignment: .leading)
            Text("Value")
                .frame(width: 70, alignment: .trailing)
        }
        .font(.caption.bold())
        .foregroundColor(colorForCategory(selected).opacity(0.9))
        .padding(.horizontal, 6)
    }

    private func row(team: TeamStanding, rank: Int) -> some View {
        let isMine = team.id == myTeamId

        // If "Record" category selected, show the W-L(-T) string directly.
        let val: String = {
            if selected == .teamStanding {
                // Prefer season/team record; for All Time fallback to aggregated owner record if present.
                if isAllTimeMode {
                    if let agg = ownerAggProvider(team) {
                        return agg.recordString
                    }
                    return team.winLossRecord ?? "--"
                } else {
                    return team.winLossRecord ?? "--"
                }
            } else {
                return statProvider(selected, team)
            }
        }()

        let displayName = isAllTimeMode ? (ownerAggProvider(team)?.latestDisplayName ?? team.name) : team.name
        return HStack(spacing: 0) {
            rankBadge(rank).frame(width: 46, alignment: .leading)
            Text(displayName)
                .font(.system(size: 13, weight: isMine ? .bold : .regular))
                .foregroundColor(isMine ? colorForCategory(selected) : .white.opacity(0.85))
                .lineLimit(1)
                .frame(minWidth: 70, maxWidth: .infinity, alignment: .leading)
            Text(val)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.cyan)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isMine ? colorForCategory(selected).opacity(0.12) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isMine ? colorForCategory(selected).opacity(0.6) : Color.clear, lineWidth: 1)
        )
        .onTapGesture {
            // Centralized update, select team in appSelection
            appSelection.selectedTeamId = team.id
        }
    }

    private func rankBadge(_ rank: Int) -> some View {
        let (bg, fg): (Color, Color) = {
            switch rank {
            case 1: return (.yellow, .black)
            case 2: return (.gray, .black)
            case 3: return (.orange, .black)
            default: return (.black.opacity(0.5), .white)
            }
        }()
        return Text("\(rank)")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Capsule().fill(bg.opacity(rank <= 3 ? 1 : 0.6)))
            .foregroundColor(fg)
    }

    private var gridPlaceholder: some View {
        VStack {
            Text("Grid mode coming soon")
                .foregroundColor(.white.opacity(0.6))
                .font(.caption)
            Spacer()
        }
    }

    private func sortedTeams(for cat: Category, in teams: [TeamStanding]) -> [TeamStanding] {
        // Special-case: when the selected category is "Record" (Category.teamStanding),
        // sort by win percentage (best-first). Tie-breaker: season Points For (higher PF wins).
        if cat == .teamStanding {
            return teams.sorted { a, b in
                // Compute win pct from season record if available, else from aggregated owner stats when in All Time
                func winInfo(for t: TeamStanding) -> (pct: Double, pf: Double) {
                    if let rec = t.winLossRecord, !rec.isEmpty {
                        let (w, l, tie) = parseRecord(rec)
                        let games = Double(w + l + tie)
                        let pct = games > 0 ? (Double(w) + 0.5 * Double(tie)) / games : 0.0
                        return (pct, t.pointsFor)
                    } else if isAllTimeMode, let agg = ownerAggProvider(t) {
                        let games = Double(max(1, agg.totalWins + agg.totalLosses + agg.totalTies))
                        let pct = games > 0 ? (Double(agg.totalWins) + 0.5 * Double(agg.totalTies)) / games : 0.0
                        return (pct, agg.totalPointsFor)
                    }
                    // Fallback: zero pct and use pointsFor if available
                    return (0.0, t.pointsFor)
                }

                let ai = winInfo(for: a)
                let bi = winInfo(for: b)

                if ai.pct != bi.pct { return ai.pct > bi.pct }        // higher win pct first
                if ai.pf != bi.pf { return ai.pf > bi.pf }            // higher PF breaks ties
                let an = isAllTimeMode ? (ownerAggProvider(a)?.latestDisplayName ?? a.name) : a.name
                let bn = isAllTimeMode ? (ownerAggProvider(b)?.latestDisplayName ?? b.name) : b.name
                return an < bn
            }
        }

        // Existing behavior preserved for other categories
        if isAllTimeMode && cat == .teamStanding {
            if let cache = teams.first?.league?.allTimeOwnerStats {
                return teams.sorted { allTimeStandingSort(a: $0, b: $1, cache: cache) }
            }
        }
        let asc = ascendingBetter.contains(cat)
        return teams.sorted { a, b in
            let av = numericValue(cat, a)
            let bv = numericValue(cat, b)
            if av == bv {
                let an = isAllTimeMode ? (ownerAggProvider(a)?.latestDisplayName ?? a.name) : a.name
                let bn = isAllTimeMode ? (ownerAggProvider(b)?.latestDisplayName ?? b.name) : b.name
                return an < bn
            }
            return asc ? av < bv : av > bv
        }
    }

    private func numericValue(_ category: Category, _ team: TeamStanding) -> Double {
        if isAllTimeMode, let agg = ownerAggProvider(team) {
            switch category {
            case .teamStanding: return Double(-team.leagueStanding)
            case .pointsForStanding: return agg.totalPointsFor
            case .averagePointsPerWeekStanding: return agg.teamPPW
            case .averagePointsScoredAgainstPerWeekStanding:
                let weeks = max(1, agg.weeksPlayed)
                return agg.totalPointsScoredAgainst / Double(weeks)
            case .maxPointsForStanding: return agg.totalMaxPointsFor
            case .managementPercentStanding: return agg.managementPercent
            case .offensiveManagementPercentStanding: return agg.offensiveManagementPercent
            case .defensiveManagementPercentStanding: return agg.defensiveManagementPercent
            case .offensiveStanding: return agg.totalOffensivePointsFor
            case .defensiveStanding: return agg.totalDefensivePointsFor
            case .pointsScoredAgainstStanding: return agg.totalPointsScoredAgainst
            case .qbPPWStanding: return agg.positionAvgPPW["QB"] ?? 0
            case .rbPPWStanding: return agg.positionAvgPPW["RB"] ?? 0
            case .wrPPWStanding: return agg.positionAvgPPW["WR"] ?? 0
            case .tePPWStanding: return agg.positionAvgPPW["TE"] ?? 0
            case .kickerPPWStanding: return agg.positionAvgPPW["K"] ?? 0
            case .dlPPWStanding: return agg.positionAvgPPW["DL"] ?? 0
            case .lbPPWStanding: return agg.positionAvgPPW["LB"] ?? 0
            case .dbPPWStanding: return agg.positionAvgPPW["DB"] ?? 0
            case .individualQBPPWStanding: return agg.individualPositionPPW["QB"] ?? 0
            case .individualRBPPWStanding: return agg.individualPositionPPW["RB"] ?? 0
            case .individualWRPPWStanding: return agg.individualPositionPPW["WR"] ?? 0
            case .individualTEPPWStanding: return agg.individualPositionPPW["TE"] ?? 0
            case .individualKickerPPWStanding: return agg.individualPositionPPW["K"] ?? 0
            case .individualDLPPWStanding: return agg.individualPositionPPW["DL"] ?? 0
            case .individualLBPPWStanding: return agg.individualPositionPPW["LB"] ?? 0
            case .individualDBPPWStanding: return agg.individualPositionPPW["DB"] ?? 0
            default: return 0
            }
        }
        switch category {
        case .teamStanding: return Double(-team.leagueStanding)
        case .pointsForStanding: return team.pointsFor
        case .averagePointsPerWeekStanding: return team.teamPointsPerWeek
        case .averagePointsScoredAgainstPerWeekStanding:
            let val = averagePointsAgainstPerWeek(team)
            return val.isFinite ? val : .greatestFiniteMagnitude
        case .maxPointsForStanding: return team.maxPointsFor
        case .managementPercentStanding:
            return team.maxPointsFor > 0 ? (team.pointsFor / team.maxPointsFor) * 100 : 0
        case .offensiveManagementPercentStanding:
            return team.offensiveManagementPercent ?? 0
        case .defensiveManagementPercentStanding:
            return team.defensiveManagementPercent ?? 0
        case .offensiveStanding: return team.offensivePointsFor ?? 0
        case .defensiveStanding: return team.defensivePointsFor ?? 0
        case .pointsScoredAgainstStanding: return team.pointsScoredAgainst ?? 0
        case .qbPPWStanding: return pos(team, .qbPositionPPW)
        case .rbPPWStanding: return pos(team, .rbPositionPPW)
        case .wrPPWStanding: return pos(team, .wrPositionPPW)
        case .tePPWStanding: return pos(team, .tePositionPPW)
        case .kickerPPWStanding: return pos(team, .kickerPPW)
        case .dlPPWStanding: return pos(team, .dlPositionPPW)
        case .lbPPWStanding: return pos(team, .lbPositionPPW)
        case .dbPPWStanding: return pos(team, .dbPositionPPW)
        case .individualQBPPWStanding: return pos(team, .individualQBPPW)
        case .individualRBPPWStanding: return pos(team, .individualRBPPW)
        case .individualWRPPWStanding: return pos(team, .individualWRPPW)
        case .individualTEPPWStanding: return pos(team, .individualTEPPW)
        case .individualKickerPPWStanding: return pos(team, .individualKickerPPW)
        case .individualDLPPWStanding: return pos(team, .individualDLPPW)
        case .individualLBPPWStanding: return pos(team, .individualLBPPW)
        case .individualDBPPWStanding: return pos(team, .individualDBPPW)
        default: return 0
        }
    }

    private func pos(_ team: TeamStanding, _ t: DSDStatsService.StatType) -> Double {
        (DSDStatsService.shared.stat(for: team, type: t) as? Double) ?? 0
    }

    // MARK: - Helpers for Record parsing and win pct

    /// Parses "W-L" or "W-L-T" style strings into (wins, losses, ties).
    private func parseRecord(_ record: String) -> (Int, Int, Int) {
        let parts = record.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return (0, 0, 0) }
        let w = Int(parts.indices.contains(0) ? parts[0] : "0") ?? 0
        let l = Int(parts.indices.contains(1) ? parts[1] : "0") ?? 0
        let t = Int(parts.indices.contains(2) ? parts[2] : "0") ?? 0
        return (w, l, t)
    }
}

// MARK: - Global Helpers (must be in scope for StandingsExplorerView)

private func formatNumber(_ value: Double?, decimals: Int = 2) -> String {
    guard let v = value else { return "—" }
    return String(format: "%.\(decimals)f", v)
}
private func ordinal(_ n: Int) -> String { "\(n)\(ordinalSuffix(n))" }

private func ordinalSuffix(_ n: Int) -> String {
    let mod10 = n % 10, mod100 = n % 100
    if (11...13).contains(mod100) { return "th" }
    switch mod10 {
    case 1: return "st"
    case 2: return "nd"
    case 3: return "rd"
    default: return "th"
    }
}

private func averagePointsAgainstPerWeek(_ team: TeamStanding) -> Double {
    guard let pa = team.pointsScoredAgainst, team.teamPointsPerWeek > 0 else {
        return .greatestFiniteMagnitude
    }
    let approxWeeks = team.pointsFor / max(0.01, team.teamPointsPerWeek)
    return pa / max(1, approxWeeks)
}

private func allTimeStandingSort(a: TeamStanding, b: TeamStanding, cache: [String: AggregatedOwnerStats]) -> Bool {
    let aggA = cache[a.ownerId]
    let aggB = cache[b.ownerId]
    if (aggA?.championships ?? 0) != (aggB?.championships ?? 0) {
        return (aggA?.championships ?? 0) > (aggB?.championships ?? 0)
    }
    if (aggA?.totalWins ?? 0) != (aggB?.totalWins ?? 0) {
        return (aggA?.totalWins ?? 0) > (aggB?.totalWins ?? 0)
    }
    if (aggA?.totalLosses ?? 0) != (aggB?.totalLosses ?? 0) {
        return (aggA?.totalLosses ?? 0) < (aggB?.totalLosses ?? 0)
    }
    if (aggA?.totalPointsFor ?? 0) != (aggB?.totalPointsFor ?? 0) {
        return (aggA?.totalPointsFor ?? 0) > (aggB?.totalPointsFor ?? 0)
    }
    if (aggA?.managementPercent ?? 0) != (aggB?.managementPercent ?? 0) {
        return (aggA?.managementPercent ?? 0) > (aggB?.managementPercent ?? 0)
    }
    let nameA = aggA?.latestDisplayName ?? a.name
    let nameB = aggB?.latestDisplayName ?? b.name
    return nameA < nameB
}
