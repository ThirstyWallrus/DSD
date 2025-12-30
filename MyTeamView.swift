//
//  MyTeamView.swift (Refactored to AppSelection Single Source of Truth)
//  - Removed local leaguePickerId/seasonPicker/teamPickerId
//  - Uses LeagueSeasonTeamPicker for consistent selection
//  - All derived data now references appSelection.*
//
//  PATCH: All "actual" lineup, bench, and per-position/slot stats for a given week use the historical player pool from weekly matchup data,
//         not just the final team.roster. For missing players, uses canonical player cache (allPlayers).
//
//  PATCHED: All usages of player positions for grouping, filtering, stat aggregation, starter counting, and reporting
//           (especially for DL, LB, DB and their variants) are now passed through PositionNormalizer.normalize(_).
//

import SwiftUI
import UIKit

// MARK: - Position Color Helper (patched to use normalized position)
private func positionColor(_ pos: String) -> Color {
    let norm = PositionNormalizer.normalize(pos)
    switch norm {
    case "QB": return .red
    case "RB": return .green
    case "WR": return .blue
    case "TE": return .yellow
    case "K":  return .purple.opacity(0.6)
    case "DL": return .orange
    case "LB": return .purple
    case "DB": return .pink
    default:   return .white
    }
}

// MARK: - Position display helper (dual designations)
private func positionDisplayLabel(base: String, altPositions: [String]) -> String {
    let normBase = PositionNormalizer.normalize(base)
    var seen = Set<String>()
    var parts: [String] = []

    func appendIfNew(_ pos: String) {
        let norm = PositionNormalizer.normalize(pos)
        guard !norm.isEmpty, norm != "UNK", !seen.contains(norm) else { return }
        seen.insert(norm)
        parts.append(norm)
    }

    appendIfNew(normBase)
    for alt in altPositions {
        appendIfNew(alt)
    }
    return parts.isEmpty ? normBase : parts.joined(separator: "/")
}

struct AssignedSlot: Identifiable {
    let id = UUID()
    let playerId: String
    let slot: String
    let playerPos: String
    let altPositions: [String]
    let displayName: String
    let score: Double
}

struct BenchPlayer: Identifiable {
    let id: String
    let pos: String
    let altPositions: [String]
    let displayName: String
    let score: Double
}

struct MyTeamView: View {
    @EnvironmentObject var appSelection: AppSelection
    @EnvironmentObject var leagueManager: SleeperLeagueManager
    @EnvironmentObject var authViewModel: AuthViewModel
    @Binding var selectedTab: Tab
    @AppStorage("statDropPersonality") var userStatDropPersonality: StatDropPersonality = .classicESPN
    @State private var selectedWeek: String = "SZN"
    @State private var isStatDropActive: Bool = false

    // Layout constants
    fileprivate let horizontalEdgePadding: CGFloat = 16
    fileprivate let menuSpacing: CGFloat = 12
    fileprivate let maxContentWidth: CGFloat = 860

    // Centralized selection via AppSelection
    private var league: LeagueData? { appSelection.selectedLeague }

    private var allSeasonIds: [String] {
        guard let league else { return ["All Time"] }
        let sorted = league.seasons.map { $0.id }.sorted(by: >)
        return ["All Time"] + sorted
    }

    private var currentSeasonTeams: [TeamStanding] {
        league?.seasons.sorted { $0.id < $1.id }.last?.teams ?? league?.teams ?? []
    }

    private var seasonTeams: [TeamStanding] {
        guard let league else { return [] }
        if appSelection.selectedSeason == "All Time" {
            return currentSeasonTeams
        }
        return league.seasons.first(where: { $0.id == appSelection.selectedSeason })?.teams
            ?? currentSeasonTeams
    }

    private var selectedTeamSeason: TeamStanding? {
        appSelection.selectedTeam
    }

    private var aggregated: AggregatedOwnerStats? {
        guard appSelection.selectedSeason == "All Time",
              let league,
              let team = selectedTeamSeason else { return nil }
        return league.allTimeOwnerStats?[team.ownerId]
    }

    private var currentSeasonId: String {
        league?.seasons.sorted { $0.id < $1.id }.last?.id ?? ""
    }

    private var availableWeeks: [String] {
        guard let team = selectedTeamSeason else { return ["SZN"] }
        if let season = league?.seasons.first(where: { $0.id == appSelection.selectedSeason }),
           let mByWeek = season.matchupsByWeek {
            let weeks = mByWeek.keys.sorted()
            if weeks.isEmpty { return ["SZN"] }
            return weeks.map { "Wk \($0)" } + ["SZN"]
        }
        let allWeeks = team.roster.flatMap { $0.weeklyScores }.map { $0.week }
        let uniqueWeeks = Set(allWeeks).sorted()
        if uniqueWeeks.isEmpty { return ["SZN"] }
        return uniqueWeeks.map { "Wk \($0)" } + ["SZN"]
    }

    // PATCH: All stat grouping/aggregation positions are normalized
    private let mainPositions = ["QB","RB","WR","TE","K","DL","LB","DB"]

    private var showEmptyState: Bool {
        leagueManager.leagues.isEmpty || !authViewModel.isLoggedIn
    }

    // MARK: - PHATT / PICK SIX FONT + Gradient Styling Helpers
    private static var phattPostScriptName: String {
        return FontLoader.postScriptName(matching: "Phatt") ?? "Phatt"
    }
    private static var pickSixPostScriptName: String {
        return FontLoader.postScriptName(matching: "Pick Six") ?? "Pick Six"
    }

    private static var fieryGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [Color(hex: "#C24100"), Color(hex: "#F5C200"), Color(hex: "#C24100")]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func phattGradientText(_ text: Text, size: CGFloat) -> some View {
        let styled = text
            .font(.custom(phattPostScriptName, size: size))
            .fontWeight(.bold)

        return styled
            .foregroundColor(.clear)
            .overlay(
                fieryGradient
                    .mask(styled)
            )
    }

    static func pickSixGradientText(_ text: Text, size: CGFloat) -> some View {
        let styled = text
            .font(.custom(pickSixPostScriptName, size: size))
            .fontWeight(.bold)

        return styled
            .foregroundColor(.clear)
            .overlay(
                fieryGradient
                    .mask(styled)
            )
    }

    // New: gradient text using current text-style size to avoid size changes
    static func phattGradientTextDefault(_ text: Text, size: CGFloat? = nil) -> some View {
        let resolvedSize = size ?? UIFont.preferredFont(forTextStyle: .body).pointSize
        let styled = text
            .font(.custom(phattPostScriptName, size: resolvedSize))
            .fontWeight(.bold)

        return styled
            .foregroundColor(.clear)
            .overlay(
                fieryGradient
                    .mask(styled)
            )
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if showEmptyState {
                emptyState
            } else {
                mainContent
            }
        }
        .onAppear {
            validateSelection()
        }
        .onChange(of: appSelection.leagues) {
            validateSelection()
        }
        .onChange(of: appSelection.selectedSeason) {
            selectedWeek = "SZN"
        }
        .onChange(of: appSelection.selectedTeamId) {
            selectedWeek = "SZN"
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func validateSelection() {
        guard !showEmptyState else { return }
        // Ensure selectedLeagueId is valid
        if appSelection.selectedLeagueId == nil || !appSelection.leagues.contains(where: { $0.id == appSelection.selectedLeagueId }) {
            appSelection.selectedLeagueId = appSelection.leagues.first?.id
        }
        // Ensure selectedSeason is valid
        if let league = appSelection.selectedLeague,
            !league.seasons.contains(where: { $0.id == appSelection.selectedSeason }) && appSelection.selectedSeason != "All Time" {
            appSelection.selectedSeason = league.seasons.sorted { $0.id < $1.id }.last?.id ?? "All Time"
        }
        // Ensure selectedTeamId is valid
        let validTeams = seasonTeams
        if let currentTeamId = appSelection.selectedTeamId,
           !validTeams.contains(where: { $0.id == currentTeamId }) {
            appSelection.selectedTeamId = validTeams.first?.id
        }
        // Ensure selectedWeek is valid
        if !availableWeeks.contains(selectedWeek) {
            selectedWeek = "SZN"
        }
    }

    // MARK: Empty
    private var emptyState: some View {
        VStack(spacing: 18) {
            Text(authViewModel.isLoggedIn ? "No League Imported" : "Please Sign In")
                .font(.title2.bold())
                .foregroundColor(.orange)
            Text(authViewModel.isLoggedIn
                ? "Go to the Dashboard and import your Sleeper league."
                : "Sign in and import a Sleeper league to begin.")
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 40)
            Button {
                selectedTab = .dashboard
            } label: {
                Text("Go to Dashboard")
                    .bold()
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 24).fill(Color.orange))
                    .foregroundColor(.black)
            }
        }
        .padding()
    }

    // MARK: Main
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 36) {
                headerBlock
                contentStack
            }
            .adaptiveWidth(max: maxContentWidth, padding: horizontalEdgePadding)
            .padding(.top, 32)
            .padding(.bottom, 120)
        }
    }

    // --- NEW MENU LAYOUT HERE ---
    private var headerBlock: some View {
        VStack(spacing: 18) {
            MyTeamView.phattGradientText(Text(displayTeamName()), size: 36)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            selectionMenus
        }
    }

    // --- DSDDashboard-style Menu Geometry ---
    private var selectionMenus: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                HStack {
                    leagueMenu
                        .frame(width: geo.size.width)
                }
            }
            .frame(height: 50)

            GeometryReader { geo in
                let spacing: CGFloat = menuSpacing * 3
                let totalAvailable = geo.size.width - spacing
                let tabWidth = totalAvailable / 4
                HStack(spacing: menuSpacing) {
                    seasonMenu
                        .frame(width: tabWidth)
                    teamMenu
                        .frame(width: tabWidth)
                    weekMenu
                        .frame(width: tabWidth)
                    statDropMenu
                        .frame(width: tabWidth)
                }
            }
            .frame(height: 50)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, horizontalEdgePadding)
    }

    // --- Individual Menus ---
    private var leagueMenu: some View {
        Menu {
            ForEach(appSelection.leagues, id: \.id) { lg in
                Button(lg.name) {
                    appSelection.selectedLeagueId = lg.id
                    appSelection.selectedSeason = lg.seasons.sorted { $0.id < $1.id }.last?.id ?? "All Time"
                    appSelection.selectedTeamId = lg.teams.first?.id
                }
            }
        } label: {
            menuLabel(appSelection.selectedLeague?.name ?? "League")
        }
    }

    private var seasonMenu: some View {
        Menu {
            ForEach(allSeasonIds, id: \.self) { sid in
                Button(sid) {
                    appSelection.selectedSeason = sid
                    appSelection.syncSelectionAfterSeasonChange(username: nil, sleeperUserId: nil)
                }
            }
        } label: {
            menuLabel(appSelection.selectedSeason.isEmpty ? "Year" : appSelection.selectedSeason)
        }
    }

    private var teamMenu: some View {
        Menu {
            ForEach(seasonTeams, id: \.id) { tm in
                Button(tm.name) { appSelection.setUserSelectedTeam(teamId: tm.id, teamName: tm.name) }
            }
        } label: {
            menuLabel("Team")
        }
    }

    private var weekMenu: some View {
        Menu {
            ForEach(availableWeeks, id: \.self) { wk in
                Button(wk) { selectedWeek = wk }
            }
        } label: {
            menuLabel(selectedWeek)
        }
    }

    private var statDropMenu: some View {
        Menu {
            if isStatDropActive {
                Button(action: { isStatDropActive = false }) {
                    Text("Back to Stats")
                }
            } else {
                Button(action: { isStatDropActive = true }) {
                    Text("View DSD")
                }
            }
        } label: {
            menuLabel("DSD")
        }
    }

    private func menuLabel(_ text: String) -> some View {
        Text(text)
            .bold()
            .foregroundColor(.orange)
            .font(.custom("Phatt", size: 16))
            .frame(minHeight: 36)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 30)
                    .fill(Color.black)
                    .shadow(color: .blue.opacity(0.7), radius: 8, y: 2)
            )
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 24) {
            if isStatDropActive {
                if appSelection.selectedSeason == "All Time" || (appSelection.selectedSeason != currentSeasonId && selectedWeek != "SZN") {
                    Text("Weekly Stat Drops are only available for the current season.")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.body)
                } else if let team = selectedTeamSeason, let league = league {
                    StatDropAnalysisBox(
                        team: team,
                        league: league,
                        context: .myTeam,
                        personality: userStatDropPersonality,
                        opponent: nil,
                        explicitWeek: getSelectedWeekNumber()
                    )
                } else {
                    Text("No data available.")
                }
            } else {
                managementSection
                if selectedWeek == "SZN" {
                    ppwCombinedSection
                } else {
                    positionPPWSection
                    lineupSection
                }
                transactionSection
                totalsSection
                strengthsWeaknessesSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var topHeader: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            MyTeamView.phattGradientText(Text(displayTeamName()), size: 30)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 12)
            Text(appSelection.selectedSeason)
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Sections (same logic as prior version but referencing appSelection)
    private var managementSection: some View {
        sectionBox {
            MyTeamView.phattGradientText(Text("Management %"), size: 20)
                .frame(maxWidth: .infinity, alignment: .center)
            let (f, o, d) = managementTriplet()
            VStack(spacing: 12) {
                HStack {
                    Text("Full Team")
                        .foregroundColor(.green.opacity(0.8))
                    Spacer()
                    Text(String(format: "%.1f%%", f))
                        .foregroundColor(Color.mgmtPercentColor(f))
                }
                PillProgress(percent: f, color: Color.mgmtPercentColor(f))
                HStack {
                    Text("Offense")
                        .foregroundColor(.red.opacity(0.8))
                    Spacer()
                    Text(String(format: "%.1f%%", o))
                        .foregroundColor(Color.mgmtPercentColor(o))
                }
                PillProgress(percent: o, color: Color.mgmtPercentColor(o))
                HStack {
                    Text("Defense")
                        .foregroundColor(.blue.opacity(0.8))
                    Spacer()
                    Text(String(format: "%.1f%%", d))
                        .foregroundColor(Color.mgmtPercentColor(d))
                }
                PillProgress(percent: d, color: Color.mgmtPercentColor(d))
            }
        }
    }

    private func valueLine(_ text: String, _ color: Color) -> some View {
        Text(text)
            .foregroundColor(color)
            .accessibilityLabel(text)
    }

    // MARK: Combined PPW + IPPW (SZN only)
    private var ppwCombinedSection: some View {
        sectionBox {
            MyTeamView.phattGradientText(Text("PPW Averages"), size: 18)
                .frame(maxWidth: .infinity, alignment: .center)

            // Header row
            HStack(spacing: 8) {
                Text("Pos")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("PPW")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                Text("Lg PPW")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                Text("IPPW")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                Text("Lg IPPW")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Divider().background(Color.white.opacity(0.2))

            VStack(spacing: 10) {
                ForEach(mainPositions, id: \.self) { pos in
                    let stats = combinedPositionStats(pos: pos)
                    let ppwColor = tightColorVsLeague(stats.ppw, leagueAvg: stats.leaguePPW)
                    let ippwColor = tightColorVsLeague(stats.ippw, leagueAvg: stats.leagueIPPW)
                    HStack(spacing: 8) {
                        Text(pos)
                            .foregroundColor(positionColor(pos))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(format: "%.2f", stats.ppw))
                            .foregroundColor(ppwColor)
                            .frame(maxWidth: .infinity)
                        Text(String(format: "%.2f", stats.leaguePPW))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                        Text(String(format: "%.2f", stats.ippw))
                            .foregroundColor(ippwColor)
                            .frame(maxWidth: .infinity)
                        Text(String(format: "%.2f", stats.leagueIPPW))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.caption.bold())
                }
            }
        }
        // Stretch to screen edges (counter outer padding) without GeometryReader
        .padding(.horizontal, -horizontalEdgePadding)
        .frame(maxWidth: .infinity)
    }

    // MARK: Weekly position section (non-SZN)
    private var positionPPWSection: some View {
        sectionBox {
            let wkText = selectedWeek.replacingOccurrences(of: "Wk ", with: "")
            MyTeamView.phattGradientText(Text("Position Averages (Week \(wkText))"), size: 18)
                .frame(maxWidth: .infinity, alignment: .center)
            gridForPositions(valueProvider: positionAvg, leagueAvgProvider: leaguePosPPW)
        }
    }

    // MARK: Starter/Bench score coloring helpers
    private func leagueStarterAverageForPosition(week: Int, pos: String) -> Double {
        guard let league = league,
              let season = league.seasons.first(where: { $0.id == appSelection.selectedSeason }),
              let map = season.matchupsByWeek else { return 0 }
        let normPos = PositionNormalizer.normalize(pos)
        let startingSlots = league.startingLineup.filter { !["BN","IR","TAXI"].contains($0) }
        var total: Double = 0
        var count: Int = 0
        for team in seasonTeams {
            guard let entry = map[week]?.first(where: { $0.roster_id == Int(team.id) }) else { continue }
            let starters = entry.starters ?? []
            let playersPoints = entry.players_points ?? [:]
            let padded: [String] = {
                if starters.count < startingSlots.count {
                    return starters + Array(repeating: "0", count: startingSlots.count - starters.count)
                } else if starters.count > startingSlots.count {
                    return Array(starters.prefix(startingSlots.count))
                }
                return starters
            }()
            for idx in 0..<startingSlots.count {
                let slot = startingSlots[idx]
                let allowed = allowedPositions(for: slot)
                let pid = padded[idx]
                guard pid != "0" else { continue }
                let playerPos: String
                if let rosterPlayer = team.roster.first(where: { $0.id == pid }) {
                    playerPos = PositionNormalizer.normalize(rosterPlayer.position)
                } else if let raw = leagueManager.playerCache?[pid] ?? leagueManager.allPlayers[pid] {
                    playerPos = PositionNormalizer.normalize(raw.position ?? "UNK")
                } else {
                    continue
                }
                if allowed.contains(playerPos) {
                    total += playersPoints[pid] ?? 0
                    count += 1
                }
            }
        }
        return count > 0 ? total / Double(count) : 0
    }

    private func scoreColor(for score: Double, position: String, week: Int) -> Color {
        let avg = leagueStarterAverageForPosition(week: week, pos: position)
        if avg == 0 { return .white }
        if score > avg + 1 { return .green }
        if score < avg - 1 { return .red }
        return .yellow
    }

    private var lineupSection: some View {
        sectionBox {
            MyTeamView.phattGradientText(Text("Lineup (Week \(selectedWeek.replacingOccurrences(of: "Wk ", with: "")))"), size: 18)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack {
                MyTeamView.phattGradientTextDefault(Text("Slot"))
                    .frame(maxWidth: .infinity / 3, alignment: .center)
                MyTeamView.phattGradientTextDefault(Text("Name"))
                    .frame(maxWidth: .infinity / 3, alignment: .center)
                MyTeamView.phattGradientTextDefault(Text("Score"))
                    .frame(maxWidth: .infinity / 3, alignment: .center)
            }
            if let week = getSelectedWeekNumber(),
               let t = selectedTeamSeason,
               let season = league?.seasons.first(where: { $0.id == appSelection.selectedSeason }) ?? league?.seasons.sorted(by: { $0.id < $1.id }).last,
               let slots = league?.startingLineup,
               let myEntry = season.matchupsByWeek?[week]?.first(where: { $0.roster_id == Int(t.id) }) {
                // PATCH: Use weekly player pool for assigned slots & bench
                let allPlayers = leagueManager.playerCache ?? [:]
                let startingSlots = slots.filter { !["BN", "IR", "TAXI"].contains($0) }
                let assigned = assignPlayersToSlotsPatched(team: t, week: week, slots: startingSlots, myEntry: myEntry, playerCache: allPlayers)
                ForEach(assigned) { item in
                    let creditedPos = PositionNormalizer.normalize(
                        SlotPositionAssigner.countedPosition(
                            for: item.slot,
                            candidatePositions: ([item.playerPos] + item.altPositions).map { PositionNormalizer.normalize($0) },
                            base: PositionNormalizer.normalize(item.playerPos)
                        )
                    )
                    let scoreTint = scoreColor(for: item.score, position: creditedPos, week: week)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.slot)
                            .frame(maxWidth: .infinity / 3, alignment: .leading)
                        HStack(spacing: 4) {
                            Text(item.displayName)
                                .font(.caption)
                            Text(positionDisplayLabel(base: item.playerPos, altPositions: item.altPositions))
                                .font(.caption2)
                                .foregroundColor(positionColor(creditedPos)) // slot-based color
                        }
                        .frame(maxWidth: .infinity / 3, alignment: .leading)
                        Text(String(format: "%.2f", item.score))
                            .foregroundColor(scoreTint)
                            .frame(maxWidth: .infinity / 3, alignment: .trailing)
                    }
                    .font(.caption)
                }

                // Bench separator
                MyTeamView.pickSixGradientText(Text("-----BENCH-----"), size: 18)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 6)

                let starters = myEntry.starters ?? []
                let benchRaw = getBenchPlayersPatched(team: t, week: week, starters: starters, myEntry: myEntry, playerCache: allPlayers)

                let positionPriority: [String: Int] = [
                    "QB": 0, "RB": 1, "WR": 2, "TE": 3, "DL": 4, "LB": 5, "DB": 6
                ]
                let bench = benchRaw.sorted { lhs, rhs in
                    let lPos = PositionNormalizer.normalize(lhs.pos)
                    let rPos = PositionNormalizer.normalize(rhs.pos)
                    let lRank = positionPriority[lPos] ?? Int.max
                    let rRank = positionPriority[rPos] ?? Int.max
                    if lRank == rRank {
                        return lhs.score > rhs.score
                    }
                    return lRank < rRank
                }

                ForEach(bench) { player in
                    let posNorm = PositionNormalizer.normalize(player.pos)
                    let scoreTint = scoreColor(for: player.score, position: posNorm, week: week)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("BN")
                            .frame(maxWidth: .infinity / 3, alignment: .leading)
                        HStack(spacing: 4) {
                            Text(player.displayName)
                                .font(.caption)
                            Text(positionDisplayLabel(base: player.pos, altPositions: player.altPositions))
                                .font(.caption2)
                                .foregroundColor(positionColor(player.pos))
                        }
                        .frame(maxWidth: .infinity / 3, alignment: .leading)
                        Text(String(format: "%.2f", player.score))
                            .foregroundColor(scoreTint)
                            .frame(maxWidth: .infinity / 3, alignment: .trailing)
                    }
                    .font(.caption)
                }
            } else {
                Text("No data available.")
                    .foregroundColor(.white.opacity(0.5))
                    .font(.caption)
            }
        }
    }
    private var transactionSection: some View {
        sectionBox {
            MyTeamView.phattGradientText(Text("Transactions"), size: 18)
                .frame(maxWidth: .infinity, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                if appSelection.selectedSeason == "All Time", let agg = aggregated {
                    let waiverAll = agg.totalWaiverMoves
                    let faabAll = agg.totalFAABSpent
                    let tradesAll = agg.totalTradesCompleted
                    let seasons = max(1, agg.seasonsIncluded.count)
                    let faabPer = waiverAll > 0 ? faabAll / Double(waiverAll) : 0
                    let tradesPerSeason = Double(tradesAll) / Double(seasons)
                    transactionLine("Waiver Moves (All)", "\(waiverAll)")
                    transactionLine("FAAB Spent (All)", String(format: "%.0f", faabAll))
                    transactionLine("FAAB / Move", String(format: "%.2f", faabPer))
                    transactionLine("Trades (All)", "\(tradesAll)")
                    transactionLine("Trades / Season", String(format: "%.2f", tradesPerSeason))
                } else if let t = selectedTeamSeason {
                    transactionLine("Waiver Moves", "\(t.waiverMoves ?? 0)")
                    transactionLine("FAAB Spent", String(format: "%.0f", t.faabSpent ?? 0))
                    transactionLine("Trades", "\(t.tradesCompleted ?? 0)")
                } else {
                    Text("No transaction data")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.caption)
                }
            }
        }
    }
    private func transactionLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.68))
            Spacer()
            Text(value)
                .foregroundColor(.yellow)
        }
        .font(.caption.bold())
    }
    private var totalsSection: some View {
        sectionBox {
            MyTeamView.phattGradientText(Text("Totals"), size: 18)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(pointsSummary())
                .foregroundColor(.white)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var strengthsWeaknessesSection: some View {
        sectionBox {
            MyTeamView.phattGradientText(Text("Profile"), size: 18)
                .frame(maxWidth: .infinity, alignment: .center)
            if let a = aggregated {
                profileLines(record: a.recordString,
                            seasons: a.seasonsIncluded.count,
                            championships: a.championships)
            } else if let t = selectedTeamSeason {
                profileLines(record: t.winLossRecord ?? "--",
                            seasons: nil,
                            championships: t.championships ?? 0)
            } else {
                Text("Select a team for details.")
                    .foregroundColor(.white.opacity(0.5))
                    .font(.caption)
            }
        }
    }
    private func profileLines(record: String, seasons: Int?, championships: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Record: \(record)")
                .foregroundColor(.green)
            if let seasons {
                Text("Seasons: \(seasons)")
                    .foregroundColor(.white.opacity(0.7))
            }
            Text("Championships: \(championships)")
                .foregroundColor(championships > 0 ? .yellow : .white.opacity(0.5))
        }
        .font(.caption)
    }

    // MARK: Data Helpers
    private func displayTeamName() -> String {
        if let agg = aggregated { return agg.latestDisplayName }
        return selectedTeamSeason?.name ?? "Your Team"
    }
    private func managementTriplet() -> (Double, Double, Double) {
        if selectedWeek == "SZN" {
            if let a = aggregated {
                return (a.managementPercent,
                        a.offensiveManagementPercent,
                        a.defensiveManagementPercent)
            }
            if let t = selectedTeamSeason {
                return (t.managementPercent,
                        t.offensiveManagementPercent ?? 0,
                        t.defensiveManagementPercent ?? 0)
            }
            return (0,0,0)
        } else if let week = getSelectedWeekNumber(), let t = selectedTeamSeason {
            let (_, _, offAct, offMax, defAct, defMax) = computeWeeklyLineupPointsPatched(team: t, week: week)
            let actual = offAct + defAct
            let maxPF = offMax + defMax
            let mgmt = maxPF > 0 ? (actual / maxPF * 100) : 0
            let off = offMax > 0 ? (offAct / offMax * 100) : 0
            let defMgmt = defMax > 0 ? (defAct / defMax * 100) : 0
            return (mgmt, off, defMgmt)
        } else {
            return (0,0,0)
        }
    }

    // Helper: credited starts for a week (slot -> counted position)
    private func creditedStarts(team: TeamStanding, week: Int) -> [(pos: String, points: Double)] {
        guard let league = league,
              let season = league.seasons.first(where: { $0.id == appSelection.selectedSeason }),
              let myEntry = season.matchupsByWeek?[week]?.first(where: { $0.roster_id == Int(team.id) }),
              let starters = myEntry.starters,
              let playersPoints = myEntry.players_points else {
            return []
        }

        let slots = league.startingLineup.filter { !["BN","IR","TAXI"].contains($0) }
        let paddedStarters: [String] = {
            if starters.count < slots.count {
                return starters + Array(repeating: "0", count: slots.count - starters.count)
            } else if starters.count > slots.count {
                return Array(starters.prefix(slots.count))
            }
            return starters
        }()

        let cache = leagueManager.playerCache ?? [:]
        var credited: [(pos: String, points: Double)] = []

        for idx in 0..<slots.count {
            let slot = slots[idx]
            let pid = paddedStarters[idx]
            guard pid != "0" else { continue }
            let raw = cache[pid]
            let rosterPlayer = team.roster.first(where: { $0.id == pid })
            let candidatePositions = ([rosterPlayer?.position ?? raw?.position ?? "UNK"] + (rosterPlayer?.altPositions ?? raw?.fantasy_positions ?? []))
                .map { PositionNormalizer.normalize($0) }
            let creditedPos = SlotPositionAssigner.countedPosition(for: slot, candidatePositions: candidatePositions, base: candidatePositions.first ?? "UNK")
            let score = playersPoints[pid] ?? 0
            credited.append((pos: PositionNormalizer.normalize(creditedPos), points: score))
        }
        return credited
    }

    private func positionPoints(in team: TeamStanding, week: Int, pos: String) -> Double {
        let normPos = PositionNormalizer.normalize(pos)
        return creditedStarts(team: team, week: week)
            .filter { $0.pos == normPos }
            .reduce(0.0) { $0 + $1.points }
    }
    private func numberOfStarters(in team: TeamStanding, week: Int, pos: String) -> Int {
        let normPos = PositionNormalizer.normalize(pos)
        return creditedStarts(team: team, week: week)
            .filter { $0.pos == normPos }
            .count
    }

    // Added: per-position PPW helper (restored)
    private func positionPPW(_ pos: String) -> Double {
        let normPos = PositionNormalizer.normalize(pos)
        if let a = aggregated { return a.positionAvgPPW[normPos] ?? 0 }
        if selectedWeek == "SZN" {
            return selectedTeamSeason?.positionAverages?[normPos] ?? 0
        } else if let week = getSelectedWeekNumber(), let t = selectedTeamSeason {
            return positionPoints(in: t, week: week, pos: normPos)
        } else {
            return 0
        }
    }

    // Starter-based position average for current selection
    private func positionAvg(_ pos: String) -> Double {
        let normPos = PositionNormalizer.normalize(pos)
        if selectedWeek == "SZN" {
            // Season-long starter average
            return seasonPositionAverage(pos: normPos, teamOverride: selectedTeamSeason)
        } else if let week = getSelectedWeekNumber() {
            return weeklyPositionAverage(pos: normPos, week: week, teamOverride: selectedTeamSeason)
        } else if let a = aggregated {
            return a.positionAvgPPW[normPos] ?? 0
        } else {
            return 0
        }
    }

    // Starter average for a specific week (this team or override) using credited positions
    private func weeklyPositionAverage(pos: String, week: Int, teamOverride: TeamStanding? = nil) -> Double {
        guard let t = teamOverride ?? selectedTeamSeason else { return 0 }
        let credited = creditedStarts(team: t, week: week).filter { $0.pos == pos }
        guard !credited.isEmpty else { return 0 }
        let total = credited.reduce(0.0) { $0 + $1.points }
        return total / Double(credited.count)
    }

    // Starter average across the season (this team or override) using credited positions
    private func seasonPositionAverage(pos: String, teamOverride: TeamStanding? = nil) -> Double {
        guard let t = teamOverride ?? selectedTeamSeason,
              let league = league,
              let season = league.seasons.first(where: { $0.id == appSelection.selectedSeason }),
              let map = season.matchupsByWeek else {
            return teamOverride?.positionAverages?[pos] ?? selectedTeamSeason?.positionAverages?[pos] ?? 0
        }

        var total: Double = 0
        var count: Int = 0
        for (week, _) in map {
            let credited = creditedStarts(team: t, week: week).filter { $0.pos == pos }
            total += credited.reduce(0.0) { $0 + $1.points }
            count += credited.count
        }
        if count > 0 { return total / Double(count) }
        return t.positionAverages?[pos] ?? 0
    }

    private func individualPPW(_ pos: String) -> Double {
        // NOTE: Weekly calculation changed to use slot‑credited positions (SlotPositionAssigner)
        // to match how season/all-time individual PPW is computed. This ensures numerator and denominator
        // use the same credited position mapping rather than raw player.position.
        let normPos = PositionNormalizer.normalize(pos)
        // All-time aggregated path (unchanged)
        if let a = aggregated { return a.individualPositionPPW[normPos] ?? 0 }
        // Season path (unchanged)
        if selectedWeek == "SZN" {
            return selectedTeamSeason?.individualPositionAverages?[normPos] ?? 0
        }
        // Weekly path: compute credited totals & counts using slot assignment
        else if let week = getSelectedWeekNumber(), let t = selectedTeamSeason, let league = league {
            guard let season = league.seasons.first(where: { $0.id == appSelection.selectedSeason }),
                  let myEntry = season.matchupsByWeek?[week]?.first(where: { $0.roster_id == Int(t.id) }) else {
                // Fallback to previous behavior if matchup entry missing
                let posPoints = positionPPW(normPos)
                let numStarters = numberOfStarters(in: t, week: week, pos: normPos)
                return numStarters > 0 ? posPoints / Double(numStarters) : 0
            }

            // Use starting lineup / slots sanitized similarly to other places
            let slots = league.startingLineup.filter { !["BN", "IR", "TAXI"].contains($0) }
            let starters = myEntry.starters ?? []
            // padded starters: ensure same length as slots
            let paddedStarters: [String] = {
                if starters.count < slots.count {
                    return starters + Array(repeating: "0", count: slots.count - starters.count)
                } else if starters.count > slots.count {
                    return Array(starters.prefix(slots.count))
                }
                return starters
            }()

            let allPlayers = leagueManager.playerCache ?? [:]
            var perPosTotals: [String: Double] = [:]
            var perPosCounts: [String: Int] = [:]

            // If players_points present, prefer to use it; otherwise fallback to 0 values for starts
            let playersPoints = myEntry.players_points ?? [:]

            for idx in 0..<slots.count {
                let slot = slots[idx]
                let pid = paddedStarters[idx]
                guard pid != "0" else { continue }

                let raw = allPlayers[pid]
                let rosterPlayer = t.roster.first(where: { $0.id == pid })
                let candidatePositions = ([rosterPlayer?.position ?? raw?.position ?? "UNK"] + (rosterPlayer?.altPositions ?? raw?.fantasy_positions ?? []))
                    .map { PositionNormalizer.normalize($0) }
                let credited = SlotPositionAssigner.countedPosition(for: slot, candidatePositions: candidatePositions, base: candidatePositions.first ?? "UNK")
                let normCredited = PositionNormalizer.normalize(credited)
                let pts = playersPoints[pid] ?? 0
                perPosTotals[normCredited, default: 0] += pts
                perPosCounts[normCredited, default: 0] += 1
            }

            if let starts = perPosCounts[normPos], starts > 0, let total = perPosTotals[normPos] {
                return total / Double(starts)
            }

            // Final fallback: preserve old logic if no credited starts matched
            let posPoints = positionPPW(normPos)
            let numStarters = numberOfStarters(in: t, week: week, pos: normPos)
            return numStarters > 0 ? posPoints / Double(numStarters) : 0
        } else {
            return 0
        }
    }

    private func pointsSummary() -> String {
        if selectedWeek == "SZN" {
            if let a = aggregated {
                return String(
                    format: "PF %.0f • PPW %.2f • MaxPF %.0f • Mgmt %.1f%% (Off %.1f%% / Def %.1f%%)",
                    a.totalPointsFor, a.teamPPW, a.totalMaxPointsFor, a.managementPercent,
                    a.offensiveManagementPercent, a.defensiveManagementPercent
                )
            }
            if let t = selectedTeamSeason {
                return String(
                    format: "PF %.0f • PPW %.2f • MaxPF %.0f • Mgmt %.1f%%",
                    t.pointsFor, t.teamPointsPerWeek, t.maxPointsFor, t.managementPercent
                )
            }
            return "--"
        } else if let week = getSelectedWeekNumber(), let t = selectedTeamSeason {
            let (pf, maxPF, offAct, offMax, defAct, defMax) = computeWeeklyLineupPointsPatched(team: t, week: week)
            let mgmt = maxPF > 0 ? (pf / maxPF * 100) : 0
            let offMgmt = offMax > 0 ? (offAct / offMax * 100) : 0
            let defMgmt = defMax > 0 ? (defAct / defMax * 100) : 0
            return String(
                format: "PF %.0f • MaxPF %.0f • Mgmt %.1f%% (Off %.1f%% / Def %.1f%%)",
                pf, maxPF, mgmt, offMgmt, defMgmt
            )
        } else {
            return "--"
        }
    }
    private func leagueAvgMgmt() -> Double {
        if selectedWeek == "SZN" {
            return baseLeagueAvg { $0.managementPercent }
        } else {
            // No weekly management
            return 0
        }
    }
    private func leagueAvgOffMgmt() -> Double {
        if selectedWeek == "SZN" {
            return baseLeagueAvg { $0.offensiveManagementPercent ?? 0 }
        } else {
            // No weekly management
            return 0
        }
    }
    private func leagueAvgDefMgmt() -> Double {
        if selectedWeek == "SZN" {
            return baseLeagueAvg { $0.defensiveManagementPercent ?? 0 }
        } else {
            // No weekly management
            return 0
        }
    }
    // League average using starter-based position averages
    private func leaguePosPPW(_ pos: String) -> Double {
        let normPos = PositionNormalizer.normalize(pos)
        if selectedWeek == "SZN" {
            let vals: [Double] = seasonTeams.map { team in
                seasonPositionAverage(pos: normPos, teamOverride: team)
            }
            return average(vals)
        } else if let week = getSelectedWeekNumber() {
            let vals: [Double] = seasonTeams.map { team in
                weeklyPositionAverage(pos: normPos, week: week, teamOverride: team)
            }
            return average(vals)
        } else {
            return 0
        }
    }
    private func leagueIndividualPPW(_ pos: String) -> Double {
        let normPos = PositionNormalizer.normalize(pos)
        if selectedWeek == "SZN" {
            return average(seasonTeams.compactMap { $0.individualPositionAverages?[normPos] })
        } else if let week = getSelectedWeekNumber() {
            let teamIndPPW = seasonTeams.map { team in
                let posPoints = positionPPW(normPos)
                let numStarters = numberOfStarters(in: team, week: week, pos: normPos)
                return numStarters > 0 ? posPoints / Double(numStarters) : 0
            }
            return average(teamIndPPW)
        } else {
            return 0
        }
    }
    private func baseLeagueAvg(_ selector: (TeamStanding) -> Double) -> Double { average(seasonTeams.map(selector)) }
    private func colorVsLeague(_ value: Double, leagueAvg: Double) -> Color {
        if value > leagueAvg + 3 { return .green }
        if value < leagueAvg - 3 { return .red }
        return .yellow
    }
    private func gridForPositions(valueProvider: @escaping (String) -> Double,
                                  leagueAvgProvider: @escaping (String) -> Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(mainPositions, id: \.self) { pos in
                let val = valueProvider(pos)
                let avg = leagueAvgProvider(pos)
                HStack {
                    Text(pos)
                        .foregroundColor(positionColor(pos))
                        .frame(width: 40, alignment: .leading)
                    Text(String(format: "%.2f", val))
                        .foregroundColor(colorVsLeague(val, leagueAvg: avg))
                        .frame(width: 70, alignment: .leading)
                    Text("Lg \(String(format: "%.2f", avg))")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.caption2)
                    Spacer()
                }
                .font(.caption.bold())
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }
    private func average(_ arr: [Double]) -> Double {
        guard !arr.isEmpty else { return 0 }
        return arr.reduce(0,+) / Double(arr.count)
    }
    private func sectionBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Weekly Computation Helpers
    private func getSelectedWeekNumber() -> Int? {
        if selectedWeek == "SZN" {
            return nil
        }
        let numStr = selectedWeek.replacingOccurrences(of: "Wk ", with: "")
        return Int(numStr)
    }

    private func allowedPositions(for slot: String) -> Set<String> {
        switch slot.uppercased() {
        case "QB","RB","WR","TE","K","DL","LB","DB": return Set([PositionNormalizer.normalize(slot)])
        case "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE": return Set(["RB","WR","TE"].map(PositionNormalizer.normalize))
        case "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX": return Set(["QB","RB","WR","TE"].map(PositionNormalizer.normalize))
        case "IDP": return Set(["DL","LB","DB"])
        default:
            if slot.uppercased().contains("IDP") { return Set(["DL","LB","DB"]) }
            return Set([PositionNormalizer.normalize(slot)])
        }
    }

    private func isIDPFlex(_ slot: String) -> Bool {
        let s = slot.uppercased()
        return s.contains("IDP") && s != "DL" && s != "LB" && s != "DB"
    }

    private func isEligible(_ c: (id: String, pos: String, altPos: [String], score: Double), allowed: Set<String>) -> Bool {
        let normBase = PositionNormalizer.normalize(c.pos)
        let normAlt = c.altPos.map { PositionNormalizer.normalize($0) }
        if allowed.contains(normBase) { return true }
        return !allowed.intersection(Set(normAlt)).isEmpty
    }

    // MARK: Display Name Helper
    private func displayName(for player: Player?, raw: RawSleeperPlayer?, fallbackId: String, position: String) -> String {
        let full = raw?.full_name
        if let full, !full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parts = full.split(separator: " ").map(String.init)
            if let first = parts.first {
                let initial = first.first.map { String($0) } ?? ""
                let last = parts.dropFirst().last ?? ""
                if !last.isEmpty {
                    return "\(initial). \(last)"
                } else {
                    return full
                }
            }
        }
        // If no raw full name, try to synthesize from id or position
        return fallbackId.isEmpty ? position : fallbackId
    }

    // MARK: Combined stats helpers (SZN)
    private func combinedPositionStats(pos: String) -> (ppw: Double, leaguePPW: Double, ippw: Double, leagueIPPW: Double) {
        let normPos = PositionNormalizer.normalize(pos)

        // All Time mode uses aggregated caches when available
        if let agg = aggregated, appSelection.selectedSeason == "All Time" {
            let teamPPW = agg.positionAvgPPW[normPos] ?? 0
            let teamIPPW = agg.individualPositionPPW[normPos] ?? 0

            // League averages (weighted by weeks / starts when possible)
            if let league = league, let allAgg = league.allTimeOwnerStats?.values {
                var totalPPWPoints = 0.0
                var totalPPWWeeks = 0.0
                var totalIPPWPoints = 0.0
                var totalStarts = 0.0

                for entry in allAgg {
                    let ppw = entry.positionAvgPPW[normPos] ?? 0
                    let weeks = Double(max(entry.weeksPlayed, 0))
                    totalPPWPoints += ppw * weeks
                    totalPPWWeeks += weeks

                    let ippw = entry.individualPositionPPW[normPos] ?? 0
                    let starts = Double(entry.positionStartCounts[normPos] ?? 0)
                    totalIPPWPoints += ippw * starts
                    totalStarts += starts
                }

                let leaguePPW = totalPPWWeeks > 0 ? totalPPWPoints / totalPPWWeeks : 0
                let leagueIPPW = totalStarts > 0 ? totalIPPWPoints / totalStarts : 0
                return (teamPPW, leaguePPW, teamIPPW, leagueIPPW)
            }
            return (teamPPW, 0, teamIPPW, 0)
        }

        guard let league = league,
              let season = league.seasons.first(where: { $0.id == appSelection.selectedSeason }),
              let team = selectedTeamSeason else {
            return (0,0,0,0)
        }

        // Team season aggregates
        let teamTotals = seasonPositionTotals(for: team, season: season, pos: normPos)
        let teamPPW = teamTotals.weekCount > 0 ? teamTotals.totalPoints / Double(teamTotals.weekCount) : 0
        let teamIPPW = teamTotals.startCount > 0 ? teamTotals.totalPoints / Double(teamTotals.startCount) : 0

        // League season aggregates
        var leagueTotalPoints = 0.0
        var leagueWeekCount = 0
        var leagueStartPoints = 0.0
        var leagueStartCount = 0

        for t in seasonTeams {
            let totals = seasonPositionTotals(for: t, season: season, pos: normPos)
            leagueTotalPoints += totals.totalPoints
            leagueWeekCount += totals.weekCount
            leagueStartPoints += totals.totalPoints
            leagueStartCount += totals.startCount
        }

        let leaguePPW = leagueWeekCount > 0 ? leagueTotalPoints / Double(leagueWeekCount) : 0
        let leagueIPPW = leagueStartCount > 0 ? leagueStartPoints / Double(leagueStartCount) : 0

        return (teamPPW, leaguePPW, teamIPPW, leagueIPPW)
    }

    private func seasonPositionTotals(for team: TeamStanding, season: SeasonData, pos: String) -> (totalPoints: Double, weekCount: Int, startCount: Int) {
        var totalPoints = 0.0
        var weeksWithStarts = 0
        var totalStarts = 0

        let weeks = season.matchupsByWeek?.keys.sorted() ?? []
        for week in weeks {
            let starts = creditedStarts(team: team, week: week).filter { $0.pos == pos }
            guard !starts.isEmpty else { continue }
            let weekPoints = starts.reduce(0.0) { $0 + $1.points }
            totalPoints += weekPoints
            weeksWithStarts += 1
            totalStarts += starts.count
        }

        return (totalPoints, weeksWithStarts, totalStarts)
    }

    private func tightColorVsLeague(_ value: Double, leagueAvg: Double) -> Color {
        if value > leagueAvg + 1.0 { return .green }
        if value < leagueAvg - 1.0 { return .red }
        return .yellow
    }

    // MARK: Weekly Computation Helpers continued
    private func allowedPositions(for slot: String) -> Set<String> {
        switch slot.uppercased() {
        case "QB","RB","WR","TE","K","DL","LB","DB": return Set([PositionNormalizer.normalize(slot)])
        case "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE": return Set(["RB","WR","TE"].map(PositionNormalizer.normalize))
        case "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX": return Set(["QB","RB","WR","TE"].map(PositionNormalizer.normalize))
        case "IDP": return Set(["DL","LB","DB"])
        default:
            if slot.uppercased().contains("IDP") { return Set(["DL","LB","DB"]) }
            return Set([PositionNormalizer.normalize(slot)])
        }
    }

    private func isIDPFlex(_ slot: String) -> Bool {
        let s = slot.uppercased()
        return s.contains("IDP") && s != "DL" && s != "LB" && s != "DB"
    }

    private func isEligible(_ c: (id: String, pos: String, altPos: [String], score: Double), allowed: Set<String>) -> Bool {
        let normBase = PositionNormalizer.normalize(c.pos)
        let normAlt = c.altPos.map { PositionNormalizer.normalize($0) }
        if allowed.contains(normBase) { return true }
        return !allowed.intersection(Set(normAlt)).isEmpty
    }

    // MARK: PATCHED: Use weekly player pool, not just team.roster, for all per-week actual lineup and bench logic.

    private func assignPlayersToSlotsPatched(team: TeamStanding, week: Int, slots: [String], myEntry: MatchupEntry, playerCache: [String: RawSleeperPlayer]) -> [AssignedSlot] {
        guard let starters = myEntry.starters, let playersPoints = myEntry.players_points, let playersPool = myEntry.players else { return [] }
        var results: [AssignedSlot] = []
        let playerDict: [String: Player] = {
            var dict = [String: Player]()
            for pid in playersPool {
                if let player = team.roster.first(where: { $0.id == pid }) {
                    dict[pid] = player
                } else if let raw = playerCache[pid] {
                    dict[pid] = Player(id: pid, position: raw.position ?? "UNK", altPositions: raw.fantasy_positions, weeklyScores: [])
                }
            }
            return dict
        }()
        let paddedStarters: [String] = {
            if starters.count < slots.count {
                return starters + Array(repeating: "0", count: slots.count - starters.count)
            } else if starters.count > slots.count {
                return Array(starters.prefix(slots.count))
            }
            return starters
        }()
        for (index, slot) in slots.enumerated() {
            let player_id = paddedStarters[index]
            guard player_id != "0", let p = playerDict[player_id] else { continue }
            let raw = playerCache[player_id]
            let name = displayName(for: p, raw: raw, fallbackId: player_id, position: p.position)
            let score = playersPoints[player_id] ?? 0
            let altPos = p.altPositions ?? raw?.fantasy_positions ?? []
            results.append(AssignedSlot(playerId: player_id, slot: slot, playerPos: p.position, altPositions: altPos, displayName: name, score: score))
        }
        return results
    }

    private func getBenchPlayersPatched(team: TeamStanding, week: Int, starters: [String], myEntry: MatchupEntry, playerCache: [String: RawSleeperPlayer]) -> [BenchPlayer] {
        guard let playersPoints = myEntry.players_points, let playersPool = myEntry.players else { return [] }
        let starterSet = Set(starters)
        var res: [BenchPlayer] = []
        for pid in playersPool where !starterSet.contains(pid) {
            let p = team.roster.first(where: { $0.id == pid })
                ?? playerCache[pid].map { raw in
                    Player(id: pid, position: raw.position ?? "UNK", altPositions: raw.fantasy_positions, weeklyScores: [])
                }
            let raw = playerCache[pid]
            if let p = p {
                let name = displayName(for: p, raw: raw, fallbackId: pid, position: p.position)
                let score = playersPoints[pid] ?? 0
                let altPos = p.altPositions ?? raw?.fantasy_positions ?? []
                res.append(BenchPlayer(id: pid, pos: p.position, altPositions: altPos, displayName: name, score: score))
            }
        }
        return res.sorted { $0.score > $1.score }
    }

    private func computeWeeklyLineupPointsPatched(team: TeamStanding, week: Int) -> (Double, Double, Double, Double, Double, Double) {
        guard let league = league,
              let season = league.seasons.first(where: { $0.id == appSelection.selectedSeason }),
              let myEntry = season.matchupsByWeek?[week]?.first(where: { $0.roster_id == Int(team.id) }),
              let playersPool = myEntry.players,
              let playersPoints = myEntry.players_points
        else {
            return (0,0,0,0,0,0)
        }
        let playerCache = leagueManager.playerCache ?? [:]
        let startingSlots = league.startingLineup.filter { !["BN","IR","TAXI"].contains($0) }
        // --- ACTUAL ---
        let starters = myEntry.starters ?? []
        var actualTotal = 0.0
        var actualOff = 0.0
        var actualDef = 0.0
        for pid in starters {
            let p = team.roster.first(where: { $0.id == pid })
                ?? playerCache[pid].map { raw in
                    Player(id: pid, position: raw.position ?? "UNK", altPositions: raw.fantasy_positions, weeklyScores: [])
                }
            let pos = PositionNormalizer.normalize(p?.position ?? "UNK")
            let score = playersPoints[pid] ?? 0
            actualTotal += score
            if offensivePositions.contains(pos) {
                actualOff += score
            } else if defensivePositions.contains(pos) {
                actualDef += score
            }
        }
        // --- MAX/OPTIMAL ---
        let candidates: [(id: String, pos: String, altPos: [String], score: Double)] = playersPool.compactMap { pid in
            let p = team.roster.first(where: { $0.id == pid })
                ?? playerCache[pid].map { raw in
                    Player(id: pid, position: raw.position ?? "UNK", altPositions: raw.fantasy_positions, weeklyScores: [])
                }
            guard let p = p else { return nil }
            let basePos = PositionNormalizer.normalize(p.position)
            let altPos = (p.altPositions ?? []).map { PositionNormalizer.normalize($0) }
            return (id: pid, pos: basePos, altPos: altPos, score: playersPoints[pid] ?? 0)
        }
        var strictSlots: [String] = []
        var flexSlots: [String] = []
        for slot in startingSlots {
            let allowed = allowedPositions(for: slot)
            if allowed.count == 1 &&
                !isIDPFlex(slot) &&
                !offensiveFlexSlots.contains(slot.uppercased()) {
                strictSlots.append(slot)
            } else {
                flexSlots.append(slot)
            }
        }
        let optimalOrder = strictSlots + flexSlots
        var used = Set<String>()
        var maxTotal = 0.0
        var maxOff = 0.0
        var maxDef = 0.0
        for slot in optimalOrder {
            let allowed = allowedPositions(for: slot)
            let pick = candidates
                .filter { !used.contains($0.id) && isEligible($0, allowed: allowed) }
                .max { $0.score < $1.score }
            guard let best = pick else { continue }
            used.insert(best.id)
            maxTotal += best.score
            if offensivePositions.contains(best.pos) { maxOff += best.score }
            else if defensivePositions.contains(best.pos) { maxDef += best.score }
        }
        return (actualTotal, maxTotal, actualOff, maxOff, actualDef, maxDef)
    }

    // PATCH: All offensive/defensive groupings use normalized positions
    private let offensivePositions: Set<String> = ["QB", "RB", "WR", "TE", "K"]
    private let defensivePositions: Set<String> = ["DL", "LB", "DB"]
    private let offensiveFlexSlots: Set<String> = [
        "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE",
        "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX"
    ]
}

// MARK: Text Style Helpers
private extension Text {
    @MainActor func sectionTitleStyle() -> some View {
        MyTeamView.phattGradientText(self, size: 18)
    }
    @MainActor func sectionSubtitleStyle() -> some View {
        MyTeamView.phattGradientText(self, size: 16)
    }
}

struct PillProgress: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.white.opacity(0.2))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * (percent / 100))
                }
        }
        .frame(height: 8)
    }
}

// MARK: - Color hex init helper (small utility added locally)
private extension Color {
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch trimmed.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RRGGBB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // AARRGGBB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
