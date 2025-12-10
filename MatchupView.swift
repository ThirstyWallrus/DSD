//
// MatchupView.swift
// DynastyStatDrop
//
import SwiftUI

// Flex slot definitions for Sleeper
private let offensiveFlexSlots: Set<String> = [
    "FLEX", "WRRB", "WRRBTE", "WRRB_TE", "RBWR", "RBWRTE",
    "SUPER_FLEX", "QBRBWRTE", "QBRBWR", "QBSF", "SFLX"
]
private let regularFlexSlots: Set<String> = ["FLEX", "WRRB", "WRRBTE", "WRRB_TE", "RBWR", "RBWRTE"]
private let superFlexSlots: Set<String> = ["SUPER_FLEX", "QBRBWRTE", "QBRBWR", "QBSF", "SFLX"]
private let idpFlexSlots: Set<String> = [
    "IDP", "IDPFLEX", "IDP_FLEX", "DFLEX", "DL_LB_DB", "DL_LB", "LB_DB", "DL_DB"
]

// Helper to determine if slot is offensive flex
private func isOffensiveFlexSlot(_ slot: String) -> Bool {
    offensiveFlexSlots.contains(slot.uppercased())
}
// Helper to determine if slot is defensive flex
private func isDefensiveFlexSlot(_ slot: String) -> Bool {
    let s = slot.uppercased()
    return idpFlexSlots.contains(s) || (s.contains("IDP") && s != "DL" && s != "LB" && s != "DB")
}
// Helper to get duel designation for a flex slot
private func duelDesignation(for slot: String) -> String? {
    let s = slot.uppercased()
    if s == "DL_LB" { return "DL/LB" }
    if s == "LB_DB" { return "LB/DB" }
    if s == "DL_DB" { return "DL/DB" }
    if s == "DL_LB_DB" { return "DL/LB/DB" }
    return nil
}

struct MatchupView: View {
    @EnvironmentObject var leagueManager: SleeperLeagueManager
    @EnvironmentObject var appSelection: AppSelection
    @EnvironmentObject var authViewModel: AuthViewModel
    @Binding var selectedTab: Tab

    // MARK: - Utility Models
    struct LineupPlayer: Identifiable {
        let id: String
        let displaySlot: String
        let creditedPosition: String
        let position: String
        let slot: String
        let points: Double
        let isBench: Bool
        let slotColor: Color?
    }
    struct TeamDisplay {
        let id: String
        let name: String
        let lineup: [LineupPlayer]
        let bench: [LineupPlayer]
        let totalPoints: Double
        let maxPoints: Double
        let managementPercent: Double
        let teamStanding: TeamStanding
    }

    // Layout constants
    fileprivate let horizontalEdgePadding: CGFloat = 16
    fileprivate let menuSpacing: CGFloat = 12
    fileprivate let maxContentWidth: CGFloat = 860
    fileprivate let slotLabelWidth: CGFloat = 160
    fileprivate let scoreColumnWidth: CGFloat = 60

    @AppStorage("statDropPersonality") var userStatDropPersonality: StatDropPersonality = .classicESPN
    @State private var selectedWeek: String = ""
    @State private var isStatDropActive: Bool = false
    @State private var isLoading: Bool = false
    @State private var lineupDebugEnabled: Bool = true
    @State private var isH2HActive: Bool = false

    // MARK: - Centralized Selection
    private var league: LeagueData? { appSelection.selectedLeague }

    private var allSeasonIds: [String] {
        guard let league else { return [] }
        let sorted = league.seasons.map { $0.id }.sorted(by: >)
        return sorted
    }
    private var currentSeasonTeams: [TeamStanding] {
        league?.seasons.sorted { $0.id < $1.id }.last?.teams ?? league?.teams ?? []
    }
    private var seasonTeams: [TeamStanding] {
        guard let league else { return [] }
        return league.seasons.first(where: { $0.id == appSelection.selectedSeason })?.teams ?? currentSeasonTeams
    }
    private var selectedSeasonData: SeasonData? {
        league?.seasons.first(where: { $0.id == appSelection.selectedSeason }) ?? league?.seasons.sorted { $0.id < $1.id }.last
    }

    // MARK: - Fonts used for separators
    private var blackKnightPostScriptName: String {
        FontLoader.postScriptName(matching: "Black Knight") ?? "Black Knight"
    }
    private var pickSixPostScriptName: String {
        FontLoader.postScriptName(matching: "Pick Six") ?? "Pick Six"
    }

    // Helper: determine if a matchup week has meaningful data (not solely padded placeholders)
    private func weekHasMeaningfulData(_ entries: [MatchupEntry]) -> Bool {
        return entries.contains { entry in
            if let pp = entry.players_points, !pp.isEmpty { return true }
            if let starters = entry.starters, !starters.isEmpty { return true }
            if let pts = entry.points, pts != 0.0 { return true }
            return false
        }
    }

    // Week menu, use matchupsByWeek if available but only surface weeks that actually have data
    private var availableWeeks: [String] {
        guard let season = selectedSeasonData, let weeksDict = season.matchupsByWeek else {
            return []
        }
        let sortedKeys = weeksDict.keys.sorted()
        let filtered = sortedKeys.filter { wk in
            if let entries = weeksDict[wk] { return weekHasMeaningfulData(entries) }
            return false
        }
        let finalKeys = filtered.isEmpty ? sortedKeys : filtered
        return finalKeys.map { "Week \($0)" }
    }

    private var currentSeasonId: String {
        league?.seasons.sorted { $0.id < $1.id }.last?.id ?? ""
    }

    private var cleanedLeagueName: String {
        league?.name.unicodeScalars.filter { !$0.properties.isEmojiPresentation }.reduce(into: "") { $0 += String($1) } ?? "League"
    }

    private var userTeamStanding: TeamStanding? {
        appSelection.selectedTeam
    }

    /// Returns the current week by preferring the league's most-recent meaningful week (in-progress or most recent with data).
    /// Falls back to the largest key in matchupsByWeek, or to the leagueManager.globalCurrentWeek when appropriate.
    private var currentMatchupWeek: Int {
        guard let season = selectedSeasonData, let weeksDict = season.matchupsByWeek, !weeksDict.isEmpty else {
            return max(1, leagueManager.globalCurrentWeek)
        }
        let weekKeys = weeksDict.keys.sorted()
        let meaningfulWeeks = weekKeys.filter { wk in
            if let entries = weeksDict[wk] { return weekHasMeaningfulData(entries) }
            return false
        }
        let gw = leagueManager.globalCurrentWeek
        if gw > 0 {
            if meaningfulWeeks.contains(gw) { return gw }
            if let nearestPast = meaningfulWeeks.filter({ $0 <= gw }).max() { return nearestPast }
            if let nearestPastAny = weekKeys.filter({ $0 <= gw }).max() { return nearestPastAny }
        }
        if let maxMeaningful = meaningfulWeeks.max() { return maxMeaningful }
        return weekKeys.max() ?? max(1, leagueManager.globalCurrentWeek)
    }

    /// Determines the currently selected week number, defaults to currentMatchupWeek if not set
    private var currentWeekNumber: Int {
        if let weekNum = Int(selectedWeek.replacingOccurrences(of: "Week ", with: "")), !selectedWeek.isEmpty {
            return weekNum
        }
        return currentMatchupWeek
    }

    // Week selector default logic: prefer global current week explicitly (enforced by app)
    private func setDefaultWeekSelection() {
        DispatchQueue.main.async {
            guard let _ = self.league else {
                self.selectedWeek = ""
                return
            }

            let desiredWeek = max(1, leagueManager.globalCurrentWeek) // explicit preference for globalCurrentWeek
            let availableNums = self.availableWeeks
                .compactMap { Int($0.replacingOccurrences(of: "Week ", with: "")) }
                .sorted()

            if availableNums.contains(desiredWeek) {
                self.selectedWeek = "Week \(desiredWeek)"; return
            }
            if let nearestPast = availableNums.filter({ $0 <= desiredWeek }).max() {
                self.selectedWeek = "Week \(nearestPast)"; return
            }
            if let first = availableNums.first {
                self.selectedWeek = "Week \(first)"; return
            }
            // Fallback to computed currentMatchupWeek if nothing else found
            let fallback = self.currentMatchupWeek
            if fallback > 0 {
                self.selectedWeek = "Week \(fallback)"; return
            }
            self.selectedWeek = ""
        }
    }

    private func refreshData() {
        guard let leagueId = appSelection.selectedLeagueId else { return }
        isLoading = true
        leagueManager.refreshLeagueData(leagueId: leagueId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updatedLeague):
                    if let index = appSelection.leagues.firstIndex(where: { $0.id == leagueId }) {
                        appSelection.leagues[index] = updatedLeague
                    }
                    self.setDefaultWeekSelection()
                case .failure(let error):
                    print("Failed to refresh league data: \(error.localizedDescription)")
                }
                isLoading = false
            }
        }
    }

    // MARK: - Opponent Logic
    private func opponentTeamStandingForWeek(_ week: Int) -> TeamStanding? {
        guard let season = selectedSeasonData,
              let matchups = season.matchupsByWeek?[week],
              let userTeam = userTeamStanding,
              let userRosterId = Int(userTeam.id)
        else { return nil }
        let userEntry = matchups.first(where: { $0.roster_id == userRosterId })
        guard let matchupId = userEntry?.matchup_id else { return nil }
        if let oppEntry = matchups.first(where: { $0.matchup_id == matchupId && $0.roster_id != userRosterId }) {
            return season.teams.first(where: { $0.id == String(oppEntry.roster_id) })
        }
        return nil
    }
    private var opponentTeamStanding: TeamStanding? {
        opponentTeamStandingForWeek(currentWeekNumber)
    }

    // MARK: - Lineup ordering & helpers

    // Formats a player's display name as "F. Lastname" using playerCache if available.
    private func formatPlayerDisplayName(pid: String, team: TeamStanding?) -> String {
        if let raw = leagueManager.playerCache?[pid], let full = raw.full_name, !full.isEmpty {
            let parts = full.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            if parts.count == 1 {
                let name = parts[0]
                let initial = name.prefix(1)
                return "\(initial). \(name)"
            } else {
                let first = parts.first ?? ""
                let last = parts.last ?? ""
                let initial = first.prefix(1)
                return "\(initial). \(last)"
            }
        }
        // No full name in cache — try to find in TeamStanding roster? Team.Player doesn't contain name in our model.
        // Fallback to pid
        return pid
    }

    // Returns starters ordered according to requested slot sequence while being tolerant of actual slots.
    private func startersOrdered(for team: TeamStanding, week: Int) -> [LineupPlayer] {
        // Resolve slots for this team
        let resolvedSlots: [String] = {
            if let lg = self.league, !lg.startingLineup.isEmpty {
                return SlotUtils.sanitizeStartingSlots(lg.startingLineup)
            }
            if let cfg = team.lineupConfig, !cfg.isEmpty {
                return expandSlots(cfg)
            }
            return []
        }()

        let season = selectedSeasonData
        let entriesForWeek = season?.matchupsByWeek?[week]
        let rosterId = Int(team.id) ?? -1
        let myEntry = entriesForWeek?.first(where: { $0.roster_id == rosterId })
        let startersFromEntry: [String]? = myEntry?.starters
        var starters = startersFromEntry ?? team.actualStartersByWeek?[week] ?? []
        if starters.isEmpty {
            // nothing to order
            return []
        }

        // Build player score map (players_points preferred, else weeklyScores)
        var playerScores: [String: Double] = [:]
        if let pp = myEntry?.players_points, !pp.isEmpty {
            playerScores = pp
        } else {
            for p in team.roster {
                if let s = p.weeklyScores.first(where: { $0.week == week }) {
                    playerScores[p.id] = s.points_half_ppr ?? s.points
                }
            }
        }

        // Candidate metadata: base pos, fantasy positions
        struct C {
            let id: String
            let basePos: String
            let fantasy: [String]
            let points: Double
            let slotPlayed: String? // slot token if we can map by position index
        }

        // Build map for quick lookup from team roster or player cache
        var rosterMap: [String: Player] = [:]
        for p in team.roster { rosterMap[p.id] = p }

        // Map starters to candidate list
        var candidates: [C] = []
        for pid in starters {
            let pts = playerScores[pid] ?? 0.0
            if let raw = leagueManager.playerCache?[pid] {
                let base = PositionNormalizer.normalize(raw.position ?? "UNK")
                let fantasy = (raw.fantasy_positions ?? []).map { PositionNormalizer.normalize($0) }
                candidates.append(C(id: pid, basePos: base, fantasy: fantasy, points: pts, slotPlayed: nil))
            } else if let p = rosterMap[pid] {
                let base = PositionNormalizer.normalize(p.position)
                let fantasy = (p.altPositions ?? []).map { PositionNormalizer.normalize($0) }
                candidates.append(C(id: pid, basePos: base, fantasy: fantasy, points: pts, slotPlayed: nil))
            } else {
                candidates.append(C(id: pid, basePos: PositionNormalizer.normalize("UNK"), fantasy: [], points: pts, slotPlayed: nil))
            }
        }

        // Build pools
        var qbPool = candidates.filter { $0.basePos == "QB" }
        var rbPool = candidates.filter { $0.basePos == "RB" }
        var wrPool = candidates.filter { $0.basePos == "WR" }
        var tePool = candidates.filter { $0.basePos == "TE" }
        var kPool = candidates.filter { $0.basePos == "K" }
        var dlPool = candidates.filter { $0.basePos == "DL" }
        var lbPool = candidates.filter { $0.basePos == "LB" }
        var dbPool = candidates.filter { $0.basePos == "DB" }

        // Offensive flex pools: players eligible RB/WR/TE but not already used
        var offensiveFlexPool = candidates.filter { ["RB","WR","TE"].contains($0.basePos) || !$0.fantasy.isEmpty && !$0.fantasy.filter({ ["RB","WR","TE"].contains($0) }).isEmpty }

        // Super flex candidates: include QBs too
        var superFlexPool = candidates.filter { ["QB","RB","WR","TE"].contains($0.basePos) || !$0.fantasy.isEmpty && !$0.fantasy.filter({ ["QB","RB","WR","TE"].contains($0) }).isEmpty }

        // IDP flex: defensive candidates beyond DL/LB/DB fixed starters
        var idpFlexPool = candidates.filter { ["DL","LB","DB"].contains($0.basePos) }

        // Helper to pop a best candidate from a pool (highest points)
        func popBest(from pool: inout [C]) -> C? {
            if pool.isEmpty { return nil }
            pool.sort { $0.points > $1.points }
            return pool.removeFirst()
        }

        // Sequence defined by request; some tokens map to pools
        let sequenceTokens: [String] = [
            "QB",
            "RB","RB",
            "WR","WR",
            "TE",
            "FLEX","FLEX",
            "SUPER_FLEX",
            "K",
            "DL","DL","DL",
            "LB","LB","LB",
            "DB","DB","DB",
            "IDP_FLEX"
        ]

        var ordered: [LineupPlayer] = []
        var usedIds = Set<String>()

        for token in sequenceTokens {
            var picked: C? = nil
            switch token {
            case "QB": picked = popBest(from: &qbPool)
            case "RB": picked = popBest(from: &rbPool)
            case "WR": picked = popBest(from: &wrPool)
            case "TE": picked = popBest(from: &tePool)
            case "K": picked = popBest(from: &kPool)
            case "DL": picked = popBest(from: &dlPool)
            case "LB": picked = popBest(from: &lbPool)
            case "DB": picked = popBest(from: &dbPool)
            case "FLEX":
                // pick best from offensiveFlexPool that isn't used
                picked = popBest(from: &offensiveFlexPool)
                if picked == nil {
                    // try any remaining candidate
                    picked = popBest(from: &superFlexPool)
                }
            case "SUPER_FLEX":
                picked = popBest(from: &superFlexPool)
                if picked == nil {
                    picked = popBest(from: &offensiveFlexPool)
                }
            case "IDP_FLEX":
                picked = popBest(from: &idpFlexPool)
            default:
                break
            }
            if let p = picked, !usedIds.contains(p.id) {
                usedIds.insert(p.id)
                let credited = SlotPositionAssigner.countedPosition(for: token, candidatePositions: p.fantasy, base: p.basePos)
                let displaySlot = credited
                let name = formatPlayerDisplayName(pid: p.id, team: team)
                let points = p.points
                ordered.append(LineupPlayer(id: p.id, displaySlot: "\(credited) \(name)", creditedPosition: credited, position: p.basePos, slot: token, points: points, isBench: false, slotColor: positionColor(credited)))
            }
        }

        // Append any starters not yet included (fallthrough)
        for c in candidates where !usedIds.contains(c.id) {
            usedIds.insert(c.id)
            let credited = SlotPositionAssigner.countedPosition(for: "FLEX", candidatePositions: c.fantasy, base: c.basePos)
            let name = formatPlayerDisplayName(pid: c.id, team: team)
            ordered.append(LineupPlayer(id: c.id, displaySlot: "\(credited) \(name)", creditedPosition: credited, position: c.basePos, slot: "FLEX", points: c.points, isBench: false, slotColor: positionColor(credited)))
        }

        // debug logging retained
        if lineupDebugEnabled {
            let slotAssignmentsForDebug: [(slot: String, player: Player?)] = ordered.map { lp in
                if let p = team.roster.first(where: { $0.id == lp.id }) {
                    return (slot: lp.slot, player: p)
                }
                return (slot: lp.slot, player: nil)
            }
            debugLogTeamLineup(team: team, week: week, slots: resolvedSlots, starters: starters, slotAssignments: slotAssignmentsForDebug, finalOrdered: ordered)
        }

        return ordered
    }

    // Categorize bench into bench / IR / TAXI using explicit tokens and playerCache heuristics
    private func categorizedBench(for team: TeamStanding, week: Int) -> (bench: [LineupPlayer], ir: [LineupPlayer], taxi: [LineupPlayer]) {
        let season = selectedSeasonData
        let entriesForWeek = season?.matchupsByWeek?[week]
        let rosterId = Int(team.id) ?? -1
        let myEntry = entriesForWeek?.first(where: { $0.roster_id == rosterId })

        // build playerScores map
        var playerScores: [String: Double] = [:]
        if let pp = myEntry?.players_points, !pp.isEmpty {
            playerScores = pp
        } else {
            for p in team.roster {
                if let s = p.weeklyScores.first(where: { $0.week == week }) {
                    playerScores[p.id] = s.points_half_ppr ?? s.points
                }
            }
        }

        // Determine starters set
        let startersSet = Set(myEntry?.starters ?? team.actualStartersByWeek?[week] ?? [])

        var benchPlayers: [Player] = team.roster.filter { !startersSet.contains($0.id) }

        var benchList: [LineupPlayer] = []
        var irList: [LineupPlayer] = []
        var taxiList: [LineupPlayer] = []

        for player in benchPlayers {
            let pid = player.id
            let name = formatPlayerDisplayName(pid: pid, team: team)
            let pts = playerScores[pid] ?? 0.0
            let normPos = PositionNormalizer.normalize(player.position)
            let displaySlotBase = normPos

            // Determine explicit slot token if any
            let token = explicitSlotTokenForBenchPlayer(playerId: pid, team: team, week: week, myEntry: myEntry)
            if let t = token {
                if t.uppercased() == "IR" {
                    irList.append(LineupPlayer(id: pid, displaySlot: "IR \(displaySlotBase) \(name)", creditedPosition: displaySlotBase, position: displaySlotBase, slot: "IR", points: pts, isBench: true, slotColor: .gray))
                    continue
                } else if t.uppercased() == "TAXI" || t.uppercased().contains("TAXI") {
                    taxiList.append(LineupPlayer(id: pid, displaySlot: "Taxi \(displaySlotBase) \(name)", creditedPosition: displaySlotBase, position: displaySlotBase, slot: "TAXI", points: pts, isBench: true, slotColor: .gray))
                    continue
                }
            }

            // If no explicit token, but playerCache indicates IR/TAXI-like token in fantasy_positions or position, detect heuristically
            if let raw = leagueManager.playerCache?[pid] {
                if let pos = raw.position?.uppercased(), pos.contains("IR") {
                    irList.append(LineupPlayer(id: pid, displaySlot: "IR \(displaySlotBase) \(name)", creditedPosition: displaySlotBase, position: displaySlotBase, slot: "IR", points: pts, isBench: true, slotColor: .gray))
                    continue
                }
                if let fantasy = raw.fantasy_positions {
                    if fantasy.contains(where: { $0.uppercased().contains("TAXI") }) {
                        taxiList.append(LineupPlayer(id: pid, displaySlot: "Taxi \(displaySlotBase) \(name)", creditedPosition: displaySlotBase, position: displaySlotBase, slot: "TAXI", points: pts, isBench: true, slotColor: .gray))
                        continue
                    }
                }
            }

            // Default to bench
            benchList.append(LineupPlayer(id: pid, displaySlot: "\(displaySlotBase) \(name)", creditedPosition: displaySlotBase, position: displaySlotBase, slot: "BN", points: pts, isBench: true, slotColor: .white))
        }

        // Sort bench by position ordering for readability: QB, RB, WR, TE, K, DL, LB, DB
        let benchOrder = ["QB","RB","WR","TE","K","DL","LB","DB"]
        benchList.sort { a, b in
            let ai = benchOrder.firstIndex(of: a.creditedPosition) ?? benchOrder.count
            let bi = benchOrder.firstIndex(of: b.creditedPosition) ?? benchOrder.count
            if ai != bi { return ai < bi }
            // tie-breaker by points desc
            return a.points > b.points
        }

        // Sort IR/TAXI by points desc
        irList.sort { $0.points > $1.points }
        taxiList.sort { $0.points > $1.points }

        return (bench: benchList, ir: irList, taxi: taxiList)
    }

    /// Returns the full ordered lineup for a team for a given week.
    private func orderedLineup(for team: TeamStanding, week: Int) -> [LineupPlayer] {
        return startersOrdered(for: team, week: week)
    }

    /// Returns the bench, ordered as specified (legacy usage compatible)
    private func orderedBench(for team: TeamStanding, week: Int) -> [LineupPlayer] {
        // Keep the original simple bench order for compatibility (unused by the new combined layout)
        let season = selectedSeasonData
        let entriesForWeek = season?.matchupsByWeek?[week]
        let rosterId = Int(team.id) ?? -1
        let myEntry = entriesForWeek?.first(where: { $0.roster_id == rosterId })
        let startersSet = Set(myEntry?.starters ?? team.actualStartersByWeek?[week] ?? [])
        var playerScores: [String: Double] = [:]
        if let pp = myEntry?.players_points, !pp.isEmpty {
            playerScores = pp
        } else {
            for p in team.roster {
                if let s = p.weeklyScores.first(where: { $0.week == week }) {
                    playerScores[p.id] = s.points_half_ppr ?? s.points
                }
            }
        }
        let benchPlayers = team.roster.filter { !startersSet.contains($0.id) }
        var bench: [LineupPlayer] = benchPlayers.map { player in
            let normPos = PositionNormalizer.normalize(player.position)
            let name = formatPlayerDisplayName(pid: player.id, team: team)
            return LineupPlayer(
                id: player.id,
                displaySlot: "\(normPos) \(name)",
                creditedPosition: normPos,
                position: normPos,
                slot: "BN",
                points: playerScores[player.id] ?? 0,
                isBench: true,
                slotColor: nil
            )
        }
        bench.sort { a, b in
            let ai = ["QB", "RB", "WR", "TE", "K", "DL", "LB", "DB"].firstIndex(of: a.creditedPosition) ?? 99
            let bi = ["QB", "RB", "WR", "TE", "K", "DL", "LB", "DB"].firstIndex(of: b.creditedPosition) ?? 99
            if ai != bi { return ai < bi }
            return a.points > b.points
        }
        return bench
    }

    // MARK: - TeamDisplay construction
    private func teamDisplay(for team: TeamStanding, week: Int) -> TeamDisplay {
        let lineup = orderedLineup(for: team, week: week)
        let bench = orderedBench(for: team, week: week)
        let (actualTotal, maxTotal, _, _, _, _) = ManagementCalculator.computeManagementForWeek(team: team, week: week, league: self.league ?? team.league, leagueManager: leagueManager)
        let managementPercent = maxTotal > 0 ? (actualTotal / maxTotal * 100) : 0.0
        return TeamDisplay(
            id: team.id,
            name: team.name,
            lineup: lineup,
            bench: bench,
            totalPoints: actualTotal,
            maxPoints: maxTotal,
            managementPercent: managementPercent,
            teamStanding: team
        )
    }
    private var userTeam: TeamDisplay? {
        userTeamStanding.map { teamDisplay(for: $0, week: currentWeekNumber) }
    }
    private var opponentTeam: TeamDisplay? {
        opponentTeamStanding.map { teamDisplay(for: $0, week: currentWeekNumber) }
    }

    // MARK: - Username Extraction
    private var userDisplayName: String {
        if let dsdUser = authViewModel.currentUsername,
           let sleeper = UserDefaults.standard.string(forKey: "sleeperUsername_\(dsdUser)"),
           !sleeper.isEmpty {
            return sleeper
        }
        if let currentUsername = appSelection.selectedTeam?.name, !currentUsername.isEmpty {
            return currentUsername
        }
        if let leagueName = appSelection.selectedLeague?.name, !leagueName.isEmpty {
            return leagueName
        }
        return "Your"
    }
    private var userTeamName: String {
        if let team = userTeamStanding { return team.name }
        return "Team"
    }
    private var opponentDisplayName: String {
        if let opp = opponentTeamStanding {
            if let stats = opp.league?.allTimeOwnerStats?[opp.ownerId], !stats.latestDisplayName.isEmpty {
                return stats.latestDisplayName
            } else if !opp.name.isEmpty {
                return opp.name
            }
        }
        return "Opponent"
    }
    private var opponentTeamName: String {
        if let team = opponentTeamStanding { return team.name }
        return "Team"
    }

    // MARK: - UI
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if isLoading {
                ProgressView("Loading matchup data...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 36) {
                        headerBlock
                        if isStatDropActive {
                            statDropContent
                        } else if isH2HActive {
                            headToHeadContent
                        } else {
                            matchupContent
                        }
                    }
                    .frame(maxWidth: maxContentWidth)
                    .padding(.horizontal, horizontalEdgePadding)
                    .padding(.top, 32)
                    .padding(.bottom, 120)
                }
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 0)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            setDefaultWeekSelection()
            refreshData()
        }
        .onChange(of: appSelection.selectedSeason) { _ in setDefaultWeekSelection() }
        .onChange(of: appSelection.selectedLeagueId) { _ in setDefaultWeekSelection() }
        .onChange(of: appSelection.leagues) { _ in setDefaultWeekSelection() }
        .onChange(of: leagueManager.globalCurrentWeek) { _ in setDefaultWeekSelection() }
    }

    // MARK: - Header & Menus
    private var headerBlock: some View {
        VStack(spacing: 18) {
            Group {
                if let _ = userTeamStanding, let _ = opponentTeamStanding {
                    VStack(spacing: 6) {
                        MyTeamView.phattGradientText(Text(userTeamName), size: 36)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        MyTeamView.phattGradientText(Text("Vs."), size: 18)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        MyTeamView.phattGradientText(Text(opponentTeamName), size: 36)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                } else {
                    MyTeamView.phattGradientText(Text("Matchup"), size: 36)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .accessibilityHidden(false)
            selectionMenus
        }
    }

    private var selectionMenus: some View {
        VStack(spacing: 10) {
            HStack {
                leagueMenu
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 50)
            HStack(spacing: menuSpacing) {
                seasonMenu
                    .frame(maxWidth: .infinity)
                weekMenu
                    .frame(maxWidth: .infinity)
                h2hButton
                    .frame(maxWidth: .infinity)
                statDropMenu
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 50)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, horizontalEdgePadding)
    }

    private var leagueMenu: some View {
        Menu {
            ForEach(appSelection.leagues, id: \.id) { lg in
                Button(lg.name) {
                    appSelection.selectedLeagueId = lg.id
                    appSelection.selectedSeason = lg.seasons.sorted { $0.id < $1.id }.last?.id ?? ""
                    appSelection.userHasManuallySelectedTeam = false
                    appSelection.syncSelectionAfterLeagueChange(username: nil, sleeperUserId: nil)
                    setDefaultWeekSelection()
                }
            }
        } label: {
            menuLabel(appSelection.selectedLeague?.name ?? "League")
        }
    }

    private var seasonMenu: some View {
        Group {
            if isH2HActive {
                menuLabel("H2H")
            } else {
                Menu {
                    ForEach(allSeasonIds, id: \.self) { sid in
                        Button(sid) {
                            appSelection.selectedSeason = sid
                            appSelection.syncSelectionAfterSeasonChange(username: nil, sleeperUserId: nil)
                            setDefaultWeekSelection()
                        }
                    }
                } label: {
                    menuLabel(appSelection.selectedSeason.isEmpty ? "Year" : appSelection.selectedSeason)
                }
            }
        }
    }

    private var weekMenu: some View {
        Menu {
            ForEach(availableWeeks, id: \.self) { wk in
                weekMenuRow(for: wk)
            }
        } label: {
            menuLabel(selectedWeek.isEmpty ? "Week \(currentMatchupWeek)" : selectedWeek)
        }
    }

    @ViewBuilder
    private func weekMenuRow(for weekLabel: String) -> some View {
        let weekNum = Int(weekLabel.replacingOccurrences(of: "Week ", with: "")) ?? 0
        let pf = userTeamStanding.flatMap { userTeam in
            userTeam.roster.reduce(0.0) { sum, player in
                let score = player.weeklyScores.first(where: { $0.week == weekNum })?.points_half_ppr ?? 0
                return sum + score
            }
        } ?? 0.0
        let pfString = String(format: "%.1f", pf)
        Button(action: { selectedWeek = weekLabel }) {
            HStack(spacing: 10) {
                Text(weekLabel).foregroundColor(.white)
                Text("-").foregroundColor(.white.opacity(0.7))
                Text(pfString).foregroundColor(.cyan)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var h2hButton: some View {
        Button {
            withAnimation {
                isH2HActive.toggle()
                if isH2HActive { isStatDropActive = false }
            }
        } label: {
            Text(isH2HActive ? "Vs." : "H2H")
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
        .accessibilityLabel(isH2HActive ? "Return to Matchup view" : "Open Head to Head view")
    }

    private var statDropMenu: some View {
        Menu {
            if isStatDropActive {
                Button("Back to Matchup") { isStatDropActive = false }
            } else {
                Button("View DSD") { isStatDropActive = true }
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

    private var statDropContent: some View {
        Group {
            if let team = userTeamStanding, let lg = league {
                StatDropAnalysisBox(
                    team: team,
                    league: lg,
                    context: .matchup,
                    personality: userStatDropPersonality,
                    opponent: opponentTeamStanding,
                    explicitWeek: currentWeekNumber
                )
            } else {
                Text("No data available for Stat Drop.")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.body)
            }
        }
    }

    // MARK: - Matchup Content (top: Matchup Stats, below: Lineups)
    private var matchupContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let user = userTeamStanding, let opp = opponentTeamStanding, let lg = league {
                VStack(spacing: 8) {
                    MyTeamView.phattGradientText(Text("Matchup Stats"), size: 18)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    matchupStatsSection(user: user, opp: opp)
                }

                VStack(spacing: 8) {
                    MyTeamView.phattGradientText(Text("Lineups"), size: 18)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)

                    let spacing: CGFloat = 16
                    let totalAvailable = min(maxContentWidth, UIScreen.main.bounds.width - horizontalEdgePadding * 2)
                    let perTeam = max(220, (totalAvailable - spacing) / 2.0)
                    let slotW = max(80, min(160, perTeam * 0.55))
                    let scoreW = max(44, min(80, perTeam * 0.18))

                    HStack(spacing: spacing) {
                        teamCombinedLineupBenchBox(team: userTeam, accent: Color.cyan, title: "\(userDisplayName)'s Lineup", slotLabelWidth: slotW, scoreColumnWidth: scoreW)
                            .frame(width: perTeam, alignment: .leading)
                        teamCombinedLineupBenchBox(team: opponentTeam, accent: Color.yellow, title: "\(opponentDisplayName)'s Lineup", slotLabelWidth: slotW, scoreColumnWidth: scoreW)
                            .frame(width: perTeam, alignment: .leading)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
                    )
                }
            } else {
                Text("No matchup data available.")
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private func matchupStatsSection(user: TeamStanding, opp: TeamStanding) -> some View {
        HStack(spacing: 16) {
            // Left column: user
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(user.name).foregroundColor(.cyan).bold()
                    Spacer()
                }
                let week = currentWeekNumber
                let uDisplay = teamDisplay(for: user, week: week)
                HStack {
                    Text("Points").foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Text(String(format: "%.2f", uDisplay.totalPoints)).foregroundColor(.green)
                }
                HStack {
                    Text("Max Points").foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Text(String(format: "%.2f", uDisplay.maxPoints)).foregroundColor(.white.opacity(0.85))
                }
                HStack {
                    Text("Mgmt %").foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Text(String(format: "%.2f%%", uDisplay.managementPercent)).foregroundColor(Color.mgmtPercentColor(uDisplay.managementPercent))
                }
            }
            .frame(maxWidth: .infinity)
            // Right column: opponent
            VStack(alignment: .trailing, spacing: 6) {
                HStack {
                    Spacer()
                    Text(opp.name).foregroundColor(.yellow).bold()
                }
                let week = currentWeekNumber
                let oDisplay = teamDisplay(for: opp, week: week)
                HStack {
                    Text(String(format: "%.2f", oDisplay.totalPoints)).foregroundColor(.green)
                    Spacer()
                    Text("Points").foregroundColor(.white.opacity(0.9))
                }
                HStack {
                    Text(String(format: "%.2f", oDisplay.maxPoints)).foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Text("Max Points").foregroundColor(.white.opacity(0.9))
                }
                HStack {
                    Text(String(format: "%.2f%%", oDisplay.managementPercent)).foregroundColor(Color.mgmtPercentColor(oDisplay.managementPercent))
                    Spacer()
                    Text("Mgmt %").foregroundColor(.white.opacity(0.9))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.25)))
    }

    // MARK: — Adaptive combined lineup & bench box (renders starters in requested order and separated bench/IR/TAXI)
    private func teamCombinedLineupBenchBox(team: TeamDisplay?, accent: Color, title: String, slotLabelWidth: CGFloat = 160, scoreColumnWidth: CGFloat = 60) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let (head, tail) = splitTitle(title)
            VStack(spacing: 2) {
                Text(head)
                    .font(.headline.bold())
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                Text(tail)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            if let lineup = team?.lineup, !lineup.isEmpty {
                ForEach(lineup) { player in
                    HStack {
                        Text(player.displaySlot)
                            .foregroundColor(player.slotColor ?? positionColor(player.creditedPosition))
                            .frame(width: slotLabelWidth, alignment: .leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer()
                        Text(String(format: "%.2f", player.points))
                            .foregroundColor(.green)
                            .frame(width: scoreColumnWidth, alignment: .trailing)
                    }
                    .font(.caption)
                }
            } else {
                Text("No lineup data").foregroundColor(.gray)
            }

            // Bench / IR / TAXI separators and lists using Pick Six font for separators
            let benchBlocks = team.flatMap { categorizedBench(for: $0.teamStanding, week: currentWeekNumber) }

            Text("-----BENCH-----")
                .font(.custom(pickSixPostScriptName, size: 14))
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.vertical, 6)

            if let bench = benchBlocks?.bench, !bench.isEmpty {
                ForEach(bench) { player in
                    HStack {
                        Text(player.displaySlot)
                            .foregroundColor(positionColor(player.creditedPosition))
                            .frame(width: slotLabelWidth, alignment: .leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer()
                        Text(String(format: "%.2f", player.points))
                            .foregroundColor(.green.opacity(0.7))
                            .frame(width: scoreColumnWidth, alignment: .trailing)
                    }
                    .font(.caption)
                }
            } else {
                Text("No bench players").foregroundColor(.gray)
            }

            Text("-----IR-----")
                .font(.custom(pickSixPostScriptName, size: 14))
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.vertical, 6)

            if let ir = benchBlocks?.ir, !ir.isEmpty {
                ForEach(ir) { player in
                    HStack {
                        Text(player.displaySlot)
                            .foregroundColor(.gray)
                            .frame(width: slotLabelWidth, alignment: .leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer()
                        Text(String(format: "%.2f", player.points))
                            .foregroundColor(.green.opacity(0.7))
                            .frame(width: scoreColumnWidth, alignment: .trailing)
                    }
                    .font(.caption)
                }
            } else {
                Text("No IR players").foregroundColor(.gray)
            }

            Text("-----TAXI-----")
                .font(.custom(pickSixPostScriptName, size: 14))
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.vertical, 6)

            if let taxi = benchBlocks?.taxi, !taxi.isEmpty {
                ForEach(taxi) { player in
                    HStack {
                        Text(player.displaySlot)
                            .foregroundColor(.gray)
                            .frame(width: slotLabelWidth, alignment: .leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer()
                        Text(String(format: "%.2f", player.points))
                            .foregroundColor(.green.opacity(0.7))
                            .frame(width: scoreColumnWidth, alignment: .trailing)
                    }
                    .font(.caption)
                }
            } else {
                Text("No Taxi players").foregroundColor(.gray)
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func splitTitle(_ title: String) -> (String, String) {
        let parts = title.split(separator: " ")
        guard parts.count >= 2 else { return (title, "") }
        let suffix = String(parts.last!)
        let head = parts.dropLast().joined(separator: " ")
        return (head, suffix)
    }

    // MARK: - Helper implementations reused from earlier file parts

    private func explicitSlotTokenForBenchPlayer(playerId: String, team: TeamStanding, week: Int, myEntry: MatchupEntry?) -> String? {
        let taxiTokens: Set<String> = ["TAXI", "TAXI_SLOT", "TAXI-SLOT", "TAXI SLOT"]
        let irToken = "IR"
        func canonicalizeToken(_ raw: String) -> String {
            let up = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if up.contains("IR") { return irToken }
            if up.contains("TAXI") || taxiTokens.contains(up) { return "TAXI" }
            return up
        }
        if let entry = myEntry, let slotsMap = entry.players_slots, !slotsMap.isEmpty {
            if let rawToken = slotsMap[playerId] {
                let canonical = canonicalizeToken(rawToken)
                if lineupDebugEnabled {
                    print("[BenchSlotDetect] players_slots -> player:\(playerId) token:'\(rawToken)' canonical:'\(canonical)' (team: \(team.name), week: \(week))")
                }
                if canonical == irToken { return irToken }
                if canonical == "TAXI" { return "TAXI" }
                return canonical
            } else {
                if lineupDebugEnabled {
                    print("[BenchSlotDetect] players_slots present for team \(team.name) week \(week) but no entry for player \(playerId)")
                }
            }
        }
        if let p = team.roster.first(where: { $0.id == playerId }) {
            let checks = ([p.position] + (p.altPositions ?? [])).compactMap { $0 }.map { $0.uppercased() }
            for c in checks {
                let canonical = canonicalizeToken(c)
                if canonical == irToken {
                    if lineupDebugEnabled { print("[BenchSlotDetect] roster.altPositions -> player:\(playerId) matched IR via '\(c)'") }
                    return irToken
                }
                if canonical == "TAXI" {
                    if lineupDebugEnabled { print("[BenchSlotDetect] roster.altPositions -> player:\(playerId) matched TAXI via '\(c)'") }
                    return "TAXI"
                }
            }
        }
        if let raw = leagueManager.playerCache?[playerId] {
            if let pos = raw.position?.uppercased(), pos.contains("IR") {
                if lineupDebugEnabled { print("[BenchSlotDetect] playerCache.position -> player:\(playerId) matched IR via '\(pos)'") }
                return irToken
            }
            if let fantasy = raw.fantasy_positions {
                for alt in fantasy {
                    let canonical = canonicalizeToken(alt)
                    if canonical == irToken {
                        if lineupDebugEnabled { print("[BenchSlotDetect] playerCache.fantasy_positions -> player:\(playerId) matched IR via '\(alt)'") }
                        return irToken
                    }
                    if canonical == "TAXI" {
                        if lineupDebugEnabled { print("[BenchSlotDetect] playerCache.fantasy_positions -> player:\(playerId) matched TAXI via '\(alt)'") }
                        return "TAXI"
                    }
                }
            }
        }
        if lineupDebugEnabled {
            print("[BenchSlotDetect] No explicit IR/TAXI token detected for player \(playerId) (team: \(team.name), week: \(week))")
        }
        return nil
    }

    private func positionColor(_ pos: String) -> Color {
        switch pos {
        case "QB": return .red
        case "RB": return .green
        case "WR": return .blue
        case "TE": return .yellow
        case "K": return .purple.opacity(0.6)
        case "DL": return .orange
        case "LB": return .purple
        case "DB": return .pink
        default: return .white
        }
    }

    // MARK: - Head-to-Head mini view content (shows HeadToHeadStatsSection)
    private var headToHeadContent: some View {
        Group {
            if let user = userTeamStanding, let opp = opponentTeamStanding, let lg = league {
                VStack(spacing: 8) {
                    MyTeamView.phattGradientText(Text("Head-To-Head"), size: 18)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)

                    let userSnap: H2HTeamSnapshot? = {
                        if let td = userTeam {
                            return H2HTeamSnapshot(
                                rosterId: td.id,
                                ownerId: td.teamStanding.ownerId,
                                name: td.name,
                                totalPoints: td.totalPoints,
                                maxPoints: td.maxPoints,
                                managementPercent: td.managementPercent
                            )
                        }
                        return nil
                    }()

                    let oppSnap: H2HTeamSnapshot? = {
                        if let td = opponentTeam {
                            return H2HTeamSnapshot(
                                rosterId: td.id,
                                ownerId: td.teamStanding.ownerId,
                                name: td.name,
                                totalPoints: td.totalPoints,
                                maxPoints: td.maxPoints,
                                managementPercent: td.managementPercent
                            )
                        }
                        return nil
                    }()

                    // Build historical match snapshots for seasons where these two rosters faced each other.
                    let matchSnapshots: [H2HMatchSnapshot] = {
                        var accum: [H2HMatchSnapshot] = []
                        guard let league = lg as LeagueData? else { return [] }
                        var userRosterIdStr: Int? = Int(user.id)
                        var oppRosterIdStr: Int? = Int(opp.id)

                        for season in league.seasons {
                            guard let byWeek = season.matchupsByWeek else { continue }
                            for wk in byWeek.keys.sorted() {
                                let entries = byWeek[wk] ?? []
                                let seasonUserRosterId = season.teams.first(where: { $0.ownerId == user.ownerId }) .flatMap { Int($0.id) } ?? userRosterIdStr
                                let seasonOppRosterId = season.teams.first(where: { $0.ownerId == opp.ownerId }) .flatMap { Int($0.id) } ?? oppRosterIdStr
                                guard let uRid = seasonUserRosterId, let oRid = seasonOppRosterId else { continue }
                                guard let uEntry = entries.first(where: { $0.roster_id == uRid }) else { continue }
                                guard let oEntry = entries.first(where: { $0.roster_id == oRid }) else { continue }
                                let seasonUserTeam = season.teams.first(where: { $0.id == String(uRid) })
                                let seasonOppTeam = season.teams.first(where: { $0.id == String(oRid) })
                                if let sut = seasonUserTeam {
                                    let tdUser = teamDisplay(for: sut, week: wk)
                                    if let sot = seasonOppTeam {
                                        let tdOpp = teamDisplay(for: sot, week: wk)
                                        let snapshot = H2HMatchSnapshot(
                                            seasonId: season.id,
                                            week: wk,
                                            matchupId: uEntry.matchup_id ?? oEntry.matchup_id,
                                            userRosterId: uRid,
                                            oppRosterId: oRid,
                                            userPoints: tdUser.totalPoints,
                                            oppPoints: tdOpp.totalPoints,
                                            userMgmtPct: tdUser.managementPercent,
                                            oppMgmtPct: tdOpp.managementPercent,
                                            missingPlayerIds: []
                                        )
                                        accum.append(snapshot)
                                    } else {
                                        let ptsUser = uEntry.points ?? (uEntry.players_points?.values.reduce(0.0, +) ?? 0.0)
                                        let ptsOpp = oEntry.points ?? (oEntry.players_points?.values.reduce(0.0, +) ?? 0.0)
                                        let snapshot = H2HMatchSnapshot(
                                            seasonId: season.id,
                                            week: wk,
                                            matchupId: uEntry.matchup_id ?? oEntry.matchup_id,
                                            userRosterId: uRid,
                                            oppRosterId: oRid,
                                            userPoints: ptsUser,
                                            oppPoints: ptsOpp,
                                            userMgmtPct: nil,
                                            oppMgmtPct: nil,
                                            missingPlayerIds: []
                                        )
                                        accum.append(snapshot)
                                    }
                                }
                            }
                        }
                        return accum
                    }()

                    HeadToHeadStatsSection(
                        user: user,
                        opp: opp,
                        league: lg,
                        userSnapshot: userSnap,
                        oppSnapshot: oppSnap,
                        matchSnapshots: matchSnapshots,
                        currentSeasonId: appSelection.selectedSeason.isEmpty ? currentSeasonId : appSelection.selectedSeason,
                        currentWeekNumber: currentWeekNumber
                    )
                }
            } else {
                Text("No head-to-head data available.")
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Debug helpers
    private func debugLogTeamLineup(
        team: TeamStanding,
        week: Int,
        slots: [String],
        starters: [String],
        slotAssignments: [(slot: String, player: Player?)],
        finalOrdered: [LineupPlayer]
    ) {
        let prefix = "DSD::LineupDebug"
        print("\(prefix) Team: \(team.name) (id=\(team.id)) week=\(week)")
        let sanitizedLeagueSlots = SlotUtils.sanitizeStartingSlots(team.league?.startingLineup ?? [])
        if !sanitizedLeagueSlots.isEmpty {
            print("\(prefix) league.startingLineup count=\(sanitizedLeagueSlots.count) -> \(sanitizedLeagueSlots)")
        } else {
            print("\(prefix) league.startingLineup: none")
        }
        print("\(prefix) team.lineupConfig: \(team.lineupConfig ?? [:])")
        print("\(prefix) expanded slots (used here) count=\(slots.count) -> \(slots)")
        print("\(prefix) actualStartersByWeek[\(week)]: \(team.actualStartersByWeek?[week] ?? [])")
        print("\(prefix) starters from actualStartersByWeek used in orderedLineup: \(starters) (count: \(starters.count))")
        let paddedStarters: [String] = {
            if starters.count < slots.count {
                return starters + Array(repeating: "0", count: slots.count - starters.count)
            } else if starters.count > slots.count {
                return Array(starters.prefix(slots.count))
            }
            return starters
        }()
        print("\(prefix) paddedStarters count=\(paddedStarters.count) -> \(paddedStarters)")
        if paddedStarters.contains("0") {
            print("\(prefix) WARNING: paddedStarters contains placeholder(s) '0' (some starters are missing or matchup data incomplete)")
        }
        let rosterIds = Set(team.roster.map { $0.id })
        let missingInRoster = starters.filter { $0 != "0" && !rosterIds.contains($0) && leagueManager.playerCache?[$0] == nil }
        if !missingInRoster.isEmpty {
            print("\(prefix) NOTE: starter IDs not found in team's roster (they may have been traded/released or otherwise not present locally): \(missingInRoster)")
        }
        print("\(prefix) Slot assignments (slot -> playerId/name or nil):")
        for (slot, player) in slotAssignments {
            if let p = player {
                print("\(prefix) \(slot) -> \(p.id) / \(p.position) / \(p.id)")
            } else {
                print("\(prefix) \(slot) -> (unassigned)")
            }
        }
        let assignedPlayerIds = slotAssignments.compactMap { $0.player?.id }
        let unassignedStarters = starters.filter { !assignedPlayerIds.contains($0) && $0 != "0" }
        if !unassignedStarters.isEmpty {
            print("\(prefix) UNASSIGNED starter ids after slot assignment: \(unassignedStarters)")
        }
        print("\(prefix) final ordered lineup count=\(finalOrdered.count) (expected slots: \(slots.count))")
        print("\(prefix) final ordered lineup player ids: \(finalOrdered.map { $0.id })")
        if finalOrdered.count != slots.count {
            print("\(prefix) WARNING: final ordered lineup count (\(finalOrdered.count)) != expected slots count (\(slots.count))")
        } else {
            print("\(prefix) final ordered lineup length matches expected slots")
        }
        print("\(prefix) roster size=\(team.roster.count), bench candidates (non-starters) count=\(team.roster.filter { !(team.actualStartersByWeek?[week] ?? []).contains($0.id) }.count)")
    }
}
