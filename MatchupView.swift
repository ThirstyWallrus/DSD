//
//  MatchupView.swift
//  DynastyStatDrop
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

    // NOTE: These legacy constants remain as defaults but we now compute adaptive widths
    // at runtime using GeometryReader to avoid overflow on narrow screens.
    fileprivate let slotLabelWidth: CGFloat = 160
    fileprivate let scoreColumnWidth: CGFloat = 60

    @AppStorage("statDropPersonality") var userStatDropPersonality: StatDropPersonality = .classicESPN
    @State private var selectedWeek: String = ""
    @State private var isStatDropActive: Bool = false
    @State private var isLoading: Bool = false

    // Debug toggle for lineup diagnostics. Set to true to enable console logs.
    @State private var lineupDebugEnabled: Bool = true

    // MARK: - Centralized Selection

    private var league: LeagueData? { appSelection.selectedLeague }

    // Only show real seasons for the selected league
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

    // Small cached accessor to avoid repeatedly searching the seasons array
    private var selectedSeasonData: SeasonData? {
        league?.seasons.first(where: { $0.id == appSelection.selectedSeason }) ?? league?.seasons.sorted { $0.id < $1.id }.last
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

    // Week selector default logic
    private func setDefaultWeekSelection() {
        DispatchQueue.main.async {
            guard let _ = self.league else {
                self.selectedWeek = ""
                return
            }

            let desiredWeek = self.currentMatchupWeek
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
            if desiredWeek > 0 {
                self.selectedWeek = "Week \(desiredWeek)"; return
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

    // MARK: - Lineup & Bench Sorting Helpers

    private let strictDisplayOrder: [String] = [
        "QB", "RB", "WR", "TE",
        "OFF_FLEX",
        "K",
        "DL", "LB", "DB",
        "DEF_FLEX"
    ]

    private let benchOrder: [String] = ["QB", "RB", "WR", "TE", "K", "DL", "LB", "DB"]

    /// Returns the full ordered lineup for a team for a given week.
    private func orderedLineup(for team: TeamStanding, week: Int) -> [LineupPlayer] {
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

        var slots = resolvedSlots
        if slots.isEmpty && !starters.isEmpty {
            slots = Array(repeating: "FLEX", count: starters.count)
        }

        let paddedStarters: [String] = {
            if starters.count < slots.count {
                return starters + Array(repeating: "0", count: slots.count - starters.count)
            } else if starters.count > slots.count && slots.count > 0 {
                return Array(starters.prefix(slots.count))
            }
            return starters
        }()

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

        func lookupPlayerInfo(_ pid: String) -> (id: String, position: String, altPositions: [String]?) {
            if let p = team.roster.first(where: { $0.id == pid }) {
                return (p.id, p.position, p.altPositions)
            }
            if let raw = leagueManager.playerCache?[pid] {
                return (raw.player_id, raw.position ?? "UNK", raw.fantasy_positions)
            }
            return (pid, "UNK", nil)
        }

        var lineup: [LineupPlayer] = []
        var usedPlayers: Set<String> = []
        var availableStarters = paddedStarters

        var slotAssignments: [(slot: String, playerId: String?)] = []
        for slot in slots {
            let allowed = allowedPositions(for: slot)
            if let pid = availableStarters.first(where: { playerId in
                if playerId == "0" { return false }
                if usedPlayers.contains(playerId) { return false }
                let info = lookupPlayerInfo(playerId)
                let normPos = PositionNormalizer.normalize(info.position)
                let normAlts = (info.altPositions ?? []).map { PositionNormalizer.normalize($0) }
                return allowed.contains(normPos) || !allowed.intersection(Set(normAlts)).isEmpty
            }) {
                slotAssignments.append((slot: slot, playerId: pid))
                usedPlayers.insert(pid)
                availableStarters.removeAll { $0 == pid }
            } else {
                slotAssignments.append((slot: slot, playerId: nil))
            }
        }

        for pid in availableStarters where pid != "0" {
            slotAssignments.append((slot: "FLEX", playerId: pid))
        }

        for (slot, pidOpt) in slotAssignments {
            guard let pid = pidOpt else { continue }
            let info = lookupPlayerInfo(pid)
            let normPos = PositionNormalizer.normalize(info.position)
            let normAlts = (info.altPositions ?? []).map { PositionNormalizer.normalize($0) }

            let eligiblePositions: [String] = {
                if !normAlts.isEmpty {
                    let all = ([info.position] + (info.altPositions ?? [])).map { PositionNormalizer.normalize($0) }
                    var seen = Set<String>(); var arr: [String] = []
                    for s in all where !seen.contains(s) {
                        seen.insert(s); arr.append(s)
                    }
                    return arr
                } else {
                    return [normPos]
                }
            }()

            let displaySlot: String
            var slotColor: Color? = nil
            if isOffensiveFlexSlot(slot) || isDefensiveFlexSlot(slot) {
                displaySlot = "Flex " + eligiblePositions.joined(separator: "/")
                slotColor = colorForPosition(eligiblePositions.first ?? normPos)
            } else if ["QB","RB","WR","TE","K","DL","LB","DB"].contains(slot.uppercased()) {
                if eligiblePositions.count > 1 { displaySlot = eligiblePositions.joined(separator: "/") }
                else { displaySlot = normPos }
                slotColor = colorForPosition(eligiblePositions.first ?? normPos)
            } else {
                if eligiblePositions.count > 1 { displaySlot = eligiblePositions.joined(separator: "/") }
                else { displaySlot = normPos }
                slotColor = colorForPosition(eligiblePositions.first ?? normPos)
            }

            let creditedPosition = SlotPositionAssigner.countedPosition(
                for: slot,
                candidatePositions: eligiblePositions,
                base: info.position
            )

            let points = playerScores[pid] ?? 0.0

            lineup.append(LineupPlayer(
                id: pid,
                displaySlot: displaySlot,
                creditedPosition: creditedPosition,
                position: normPos,
                slot: slot,
                points: points,
                isBench: false,
                slotColor: slotColor
            ))
        }

        var qbSlots: [LineupPlayer] = []
        var rbSlots: [LineupPlayer] = []
        var wrSlots: [LineupPlayer] = []
        var teSlots: [LineupPlayer] = []
        var offensiveFlexSlotsArr: [LineupPlayer] = []
        var kickerSlots: [LineupPlayer] = []
        var dlSlots: [LineupPlayer] = []
        var lbSlots: [LineupPlayer] = []
        var dbSlots: [LineupPlayer] = []
        var defensiveFlexSlotsArr: [LineupPlayer] = []

        for playerObj in lineup {
            switch playerObj.creditedPosition {
            case "QB": qbSlots.append(playerObj)
            case "RB": rbSlots.append(playerObj)
            case "WR": wrSlots.append(playerObj)
            case "TE": teSlots.append(playerObj)
            case "K": kickerSlots.append(playerObj)
            case "DL": dlSlots.append(playerObj)
            case "LB": lbSlots.append(playerObj)
            case "DB": dbSlots.append(playerObj)
            default:
                if isOffensiveFlexSlot(playerObj.slot) {
                    offensiveFlexSlotsArr.append(playerObj)
                } else if isDefensiveFlexSlot(playerObj.slot) {
                    defensiveFlexSlotsArr.append(playerObj)
                }
            }
        }

        var ordered: [LineupPlayer] = []
        ordered.append(contentsOf: qbSlots)
        ordered.append(contentsOf: rbSlots)
        ordered.append(contentsOf: wrSlots)
        ordered.append(contentsOf: teSlots)
        ordered.append(contentsOf: offensiveFlexSlotsArr)
        ordered.append(contentsOf: kickerSlots)
        ordered.append(contentsOf: dlSlots)
        ordered.append(contentsOf: lbSlots)
        ordered.append(contentsOf: dbSlots)
        ordered.append(contentsOf: defensiveFlexSlotsArr)

        if lineupDebugEnabled {
            debugLogTeamLineup(team: team, week: week, slots: slots, starters: starters, slotAssignments: slotAssignments.map { (slot: $0.slot, player: $0.playerId.flatMap { id in team.roster.first { $0.id == id } }) }, finalOrdered: ordered)
        }

        return ordered
    }

    /// Returns the bench, ordered as specified
    private func orderedBench(for team: TeamStanding, week: Int) -> [LineupPlayer] {
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
            let eligiblePositions: [String] = {
                if let alt = player.altPositions, !alt.isEmpty {
                    let all = ([player.position] + alt).map { PositionNormalizer.normalize($0) }
                    return Array(NSOrderedSet(array: all)) as? [String] ?? [normPos]
                } else {
                    return [normPos]
                }
            }()

            var displaySlot = eligiblePositions.count > 1 ? eligiblePositions.joined(separator: "/") : normPos

            if let explicitToken = explicitSlotTokenForBenchPlayer(playerId: player.id, team: team, week: week, myEntry: myEntry) {
                if explicitToken.caseInsensitiveCompare("IR") == .orderedSame {
                    if !displaySlot.uppercased().hasPrefix("IR ") {
                        if lineupDebugEnabled {
                            print("[BenchSlotDetect] Applying 'IR' prefix for player \(player.id) (\(player.position)) in team '\(team.name)' week \(week)")
                        }
                        displaySlot = "IR " + displaySlot
                    }
                } else {
                    if !displaySlot.hasPrefix("Taxi ") {
                        if lineupDebugEnabled {
                            print("[BenchSlotDetect] Applying 'Taxi' prefix for player \(player.id) (\(player.position)) in team '\(team.name)' week \(week) (token: \(explicitToken))")
                        }
                        displaySlot = "Taxi " + displaySlot
                    }
                }
            } else {
                if lineupDebugEnabled {
                    if let entry = myEntry, let slotsMap = entry.players_slots, !slotsMap.isEmpty {
                        if let mapped = slotsMap[player.id] {
                            print("[BenchSlotDetect] Found players_slots for player \(player.id) = '\(mapped)' but token not recognized as IR/TAXI (team: \(team.name) week: \(week))")
                        }
                    }
                }
            }

            return LineupPlayer(
                id: player.id,
                displaySlot: displaySlot,
                creditedPosition: normPos,
                position: normPos,
                slot: normPos,
                points: playerScores[player.id] ?? 0,
                isBench: true,
                slotColor: nil
            )
        }

        bench.sort { a, b in
            let ai = benchOrder.firstIndex(of: a.creditedPosition) ?? 99
            let bi = benchOrder.firstIndex(of: b.creditedPosition) ?? 99
            return ai < bi
        }
        return bench
    }

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

    /// Helper to get allowed positions for a slot
    private func allowedPositions(for slot: String) -> Set<String> {
        switch slot.uppercased() {
        case "QB","RB","WR","TE","K","DL","LB","DB": return Set([PositionNormalizer.normalize(slot)])
        case "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE": return Set(["RB","WR","TE"].map(PositionNormalizer.normalize))
        case "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX": return Set(["QB","RB","WR","TE"].map(PositionNormalizer.normalize))
        case "IDP", "IDPFLEX", "IDP_FLEX", "DFLEX", "DL_LB_DB", "DL_LB", "LB_DB", "DL_DB": return Set(["DL","LB","DB"])
        default:
            if slot.uppercased().contains("IDP") { return Set(["DL","LB","DB"]) }
            return Set([PositionNormalizer.normalize(slot)])
        }
    }

    // MARK: - TeamDisplay construction

    private func teamDisplay(for team: TeamStanding, week: Int) -> TeamDisplay {
        let lineup = orderedLineup(for: team, week: week)
        let bench = orderedBench(for: team, week: week)
        let (actualTotal, maxTotal, _, _, _, _) = computeManagementForWeek(team: team, week: week)
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

    // MARK: - Helper: Username Extraction

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
                    Color.clear.frame(height: 160)
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
            GeometryReader { geo in
                HStack {
                    leagueMenu
                        .frame(width: geo.size.width)
                }
            }
            .frame(height: 50)
            GeometryReader { geo in
                let virtualSpacing: CGFloat = menuSpacing * 3
                let virtualTotal = geo.size.width - virtualSpacing
                let tabWidth = virtualTotal / 4
                let actualSpacing = (geo.size.width - 3 * tabWidth) / 2
                HStack(spacing: actualSpacing) {
                    seasonMenu
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

    // MARK: - Matchup Content

    private var matchupContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let user = userTeamStanding, let opp = opponentTeamStanding, let lg = league {
                VStack(spacing: 8) {
                    MyTeamView.phattGradientText(Text("Head-To-Head Stats"), size: 18)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    headToHeadStatsSection(user: user, opp: opp, league: lg)
                }

                VStack(spacing: 8) {
                    MyTeamView.phattGradientText(Text("Matchup Stats"), size: 18)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    scoresSection
                }

                VStack(spacing: 8) {
                    MyTeamView.phattGradientText(Text("Lineups"), size: 18)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)

                    GeometryReader { geo in
                        let spacing: CGFloat = 16
                        let total = geo.size.width
                        let perTeam = max(140, (total - spacing) / 2.0)
                        let slotW = max(80, min(160, perTeam * 0.55))
                        let scoreW = max(44, min(80, perTeam * 0.18))

                        VStack(spacing: 16) {
                            HStack(spacing: spacing) {
                                teamLineupBox(team: userTeam, accent: Color.cyan, title: "\(userDisplayName)'s Lineup", slotLabelWidth: slotW, scoreColumnWidth: scoreW)
                                    .frame(width: perTeam, alignment: .leading)
                                teamLineupBox(team: opponentTeam, accent: Color.yellow, title: "\(opponentDisplayName)'s Lineup", slotLabelWidth: slotW, scoreColumnWidth: scoreW)
                                    .frame(width: perTeam, alignment: .leading)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.04))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
                            )

                            HStack(spacing: spacing) {
                                teamBenchBox(team: userTeam, accent: Color.cyan, title: "\(userDisplayName)'s Bench", slotLabelWidth: slotW, scoreColumnWidth: scoreW)
                                    .frame(width: perTeam, alignment: .leading)
                                teamBenchBox(team: opponentTeam, accent: Color.yellow, title: "\(opponentDisplayName)'s Bench", slotLabelWidth: slotW, scoreColumnWidth: scoreW)
                                    .frame(width: perTeam, alignment: .leading)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.04))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
                            )
                        }
                        .frame(width: geo.size.width)
                    }
                    .frame(minHeight: 240)
                }
            } else {
                Text("No matchup data available.")
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private var scoresSection: some View {
        HStack(spacing: 16) {
            teamScoreBox(team: userTeam, accent: Color.cyan, isUser: true)
            teamScoreBox(team: opponentTeam, accent: Color.yellow, isUser: false)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    private func splitTitle(_ title: String) -> (String, String) {
        let parts = title.split(separator: " ")
        guard parts.count >= 2 else { return (title, "") }
        let suffix = String(parts.last!)
        let head = parts.dropLast().joined(separator: " ")
        return (head, suffix)
    }

    private func teamScoreBox(team: TeamDisplay?, accent: Color, isUser: Bool) -> some View {
        VStack(alignment: .center, spacing: 8) {
            let rawTitle = isUser ? "\(userDisplayName)'s Team" : "\(opponentDisplayName)'s Team"
            let (head, tail) = splitTitle(rawTitle)
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

            if let team = team {
                HStack {
                    Text("Points").frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                    Text(String(format: "%.1f", team.totalPoints))
                        .foregroundColor(.green)
                        .frame(width: 80, alignment: .trailing)
                }
                HStack {
                    Text("Max Points").frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                    Text(String(format: "%.1f", team.maxPoints))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 80, alignment: .trailing)
                }
                HStack {
                    Text("Mgmt %").frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                    Text(String(format: "%.2f%%", team.managementPercent))
                        .foregroundColor(Color.mgmtPercentColor(team.managementPercent))
                        .frame(width: 80, alignment: .trailing)
                }
            } else {
                Text("No data available").foregroundColor(.red)
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
    }

    // MARK: — Adaptive lineup & bench sections

    private func teamLineupBox(team: TeamDisplay?, accent: Color, title: String, slotLabelWidth: CGFloat = 160, scoreColumnWidth: CGFloat = 60) -> some View {
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

            if let lineup = team?.lineup {
                ForEach(lineup) { player in
                    HStack {
                        Group {
                            if let slotColor = player.slotColor {
                                Text(player.displaySlot)
                                    .foregroundColor(slotColor)
                                    .frame(width: slotLabelWidth, alignment: .leading)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            } else {
                                Text(player.displaySlot)
                                    .foregroundColor(positionColor(player.creditedPosition))
                                    .frame(width: slotLabelWidth, alignment: .leading)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        Spacer()
                        Text(String(format: "%.1f", player.points))
                            .foregroundColor(.green)
                            .frame(width: scoreColumnWidth, alignment: .trailing)
                    }
                }
            } else {
                Text("No lineup data").foregroundColor(.gray)
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func teamBenchBox(team: TeamDisplay?, accent: Color, title: String, slotLabelWidth: CGFloat = 160, scoreColumnWidth: CGFloat = 60) -> some View {
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

            if let bench = team?.bench {
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
                }
            } else {
                Text("No bench data").foregroundColor(.gray)
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headToHeadStatsSection(user: TeamStanding, opp: TeamStanding, league: LeagueData) -> some View {
        HeadToHeadStatsSection(user: user, opp: opp, league: league)
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

    private func colorForPosition(_ pos: String) -> Color {
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

    private func fixedSlotCounts(startingSlots: [String]) -> [String: Int] {
        startingSlots.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private func expandSlots(_ config: [String: Int]) -> [String] {
        let sanitized = SlotUtils.sanitizeStartingLineupConfig(config)
        return sanitized.flatMap { Array(repeating: $0.key, count: $0.value) }
    }

    // Management calculation for TeamDisplay
    private func computeManagementForWeek(team: TeamStanding, week: Int) -> (Double, Double, Double, Double, Double, Double) {
        if let season = selectedSeasonData,
           let entries = season.matchupsByWeek?[week],
           let myEntry = entries.first(where: { $0.roster_id == Int(team.id) }),
           let playersPool = myEntry.players,
           let playersPoints = myEntry.players_points {
            let playerCache = leagueManager.playerCache ?? [:]

            let starters = myEntry.starters ?? []
            var actualTotal = 0.0
            var actualOff = 0.0
            var actualDef = 0.0
            for pid in starters {
                let raw = team.roster.first(where: { $0.id == pid }) ??
                    playerCache[pid].map { raw in
                        Player(id: pid, position: raw.position ?? "UNK", altPositions: raw.fantasy_positions, weeklyScores: [])
                    }
                let pos = PositionNormalizer.normalize(raw?.position ?? "UNK")
                let score = playersPoints[pid] ?? 0.0
                actualTotal += score
                if ["QB","RB","WR","TE","K"].contains(pos) { actualOff += score }
                else if ["DL","LB","DB"].contains(pos) { actualDef += score }
            }

            var startingSlots: [String] = SlotUtils.sanitizeStartingSlots(league?.startingLineup ?? [])
            if startingSlots.isEmpty, let cfg = team.lineupConfig, !cfg.isEmpty {
                startingSlots = expandSlots(cfg)
            }

            let candidates: [(id: String, basePos: String, altPos: [String], score: Double)] = playersPool.compactMap { pid in
                let p = team.roster.first(where: { $0.id == pid })
                    ?? playerCache[pid].map { raw in
                        Player(id: pid, position: raw.position ?? "UNK", altPositions: raw.fantasy_positions, weeklyScores: [])
                    }
                guard let p = p else { return nil }
                let basePos = PositionNormalizer.normalize(p.position)
                let alt = (p.altPositions ?? []).map { PositionNormalizer.normalize($0) }
                return (id: pid, basePos: basePos, altPos: alt, score: myEntry.players_points?[pid] ?? 0.0)
            }

            var strictSlots: [String] = []
            var flexSlots: [String] = []
            for slot in startingSlots {
                let allowed = allowedPositions(for: slot)
                if allowed.count == 1 &&
                    !isDefensiveFlexSlot(slot) &&
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
                if let pick = candidates
                    .filter({ !used.contains($0.id) && (allowed.contains($0.basePos) || !allowed.intersection(Set($0.altPos)).isEmpty) })
                    .max(by: { $0.score < $1.score }) {
                    used.insert(pick.id)
                    maxTotal += pick.score
                    if ["QB","RB","WR","TE","K"].contains(pick.basePos) { maxOff += pick.score }
                    else if ["DL","LB","DB"].contains(pick.basePos) { maxDef += pick.score }
                }
            }

            return (actualTotal, maxTotal, actualOff, maxOff, actualDef, maxDef)
        }

        // Fallback: legacy roster-based computation
        let playerScores = team.roster.reduce(into: [String: Double]()) { dict, player in
            if let score = player.weeklyScores.first(where: { $0.week == week }) {
                dict[player.id] = score.points_half_ppr ?? score.points
            }
        }
        let actualStarters = team.actualStartersByWeek?[week] ?? []
        let actualTotal = actualStarters.reduce(0.0) { $0 + (playerScores[$1] ?? 0.0) }
        let offPositions: Set<String> = ["QB", "RB", "WR", "TE", "K"]
        let actualOff = actualStarters.reduce(0.0) { sum, id in
            if let player = team.roster.first(where: { $0.id == id }), offPositions.contains(player.position) {
                return sum + (playerScores[id] ?? 0.0)
            } else {
                return sum
            }
        }
        let actualDef = actualTotal - actualOff

        var startingSlots = team.league?.startingLineup ?? []
        if startingSlots.isEmpty, let config = team.lineupConfig, !config.isEmpty {
            startingSlots = expandSlots(config)
        }
        let fixedCounts = fixedSlotCounts(startingSlots: startingSlots)

        let offPosSet: Set<String> = ["QB", "RB", "WR", "TE", "K"]
        var offPlayerList = team.roster.filter { offPosSet.contains($0.position) }.map {
            (id: $0.id, pos: $0.position, score: playerScores[$0.id] ?? 0.0)
        }
        var maxOff = 0.0
        for pos in Array(offPosSet) {
            if let count = fixedCounts[pos] {
                let candidates = offPlayerList.filter { $0.pos == pos }.sorted { $0.score > $1.score }
                maxOff += candidates.prefix(count).reduce(0.0) { $0 + $1.score }
                let usedIds = candidates.prefix(count).map { $0.id }
                offPlayerList.removeAll { usedIds.contains($0.id) }
            }
        }
        let regFlexCount = startingSlots.reduce(0) { $0 + (regularFlexSlots.contains($1.uppercased()) ? 1 : 0) }
        let supFlexCount = startingSlots.reduce(0) { $0 + (superFlexSlots.contains($1.uppercased()) ? 1 : 0) }
        let regAllowed: Set<String> = ["RB", "WR", "TE"]
        let regCandidates = offPlayerList.filter { regAllowed.contains($0.pos) }.sorted { $0.score > $1.score }
        maxOff += regCandidates.prefix(regFlexCount).reduce(0.0) { $0 + $1.score }
        let usedReg = regCandidates.prefix(regFlexCount).map { $0.id }
        offPlayerList.removeAll { usedReg.contains($0.id) }
        let supAllowed: Set<String> = ["QB", "RB", "WR", "TE"]
        let supCandidates = offPlayerList.filter { supAllowed.contains($0.pos) }.sorted { $0.score > $1.score }
        maxOff += supCandidates.prefix(supFlexCount).reduce(0.0) { $0 + $1.score }

        let defPosSet: Set<String> = ["DL", "LB", "DB"]
        var defPlayerList = team.roster.filter { defPosSet.contains($0.position) }.map {
            (id: $0.id, pos: $0.position, score: playerScores[$0.id] ?? 0.0)
        }
        var maxDef = 0.0
        for pos in Array(defPosSet) {
            if let count = fixedCounts[pos] {
                let candidates = defPlayerList.filter { $0.pos == pos }.sorted { $0.score > $1.score }
                maxDef += candidates.prefix(count).reduce(0.0) { $0 + $1.score }
                let usedIds = candidates.prefix(count).map { $0.id }
                defPlayerList.removeAll { usedIds.contains($0.id) }
            }
        }
        let idpFlexCount = startingSlots.reduce(0) { $0 + (idpFlexSlots.contains($1.uppercased()) ? 1 : 0) }
        let idpCandidates = defPlayerList.sorted { $0.score > $1.score }
        maxDef += idpCandidates.prefix(idpFlexCount).reduce(0.0) { $0 + $1.score }

        let maxTotal = maxOff + maxDef
        return (actualTotal, maxTotal, actualOff, maxOff, actualDef, maxDef)
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
        let missingInRoster = starters.filter { !rosterIds.contains($0) && $0 != "0" }
        if !missingInRoster.isEmpty {
            print("\(prefix) NOTE: starter IDs not found in team's roster (they may have been traded/released): \(missingInRoster)")
        }

        print("\(prefix) Slot assignments (slot -> playerId/name or nil):")
        for (slot, player) in slotAssignments {
            if let p = player {
                print("\(prefix)    \(slot) -> \(p.id) / \(p.position) / \(p.id)")
            } else {
                print("\(prefix)    \(slot) -> (unassigned)")
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
