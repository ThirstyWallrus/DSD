//
// MatchupView.swift
// DynastyStatDrop
//
import SwiftUI

// Canonical flex slot normalizer (maps legacy tokens to Sleeper’s current set)
private func canonicalFlexSlot(_ slot: String) -> String {
    let u = slot.uppercased()
    switch u {
    case "WRRB", "RBWR": return "WRRB_FLEX"
    case "WRRBTE", "WRRB_TE", "RBWRTE": return "FLEX"
    case "REC_FLEX": return "REC_FLEX"
    case "SUPER_FLEX", "QBRBWRTE", "QBRBWR", "QBSF", "SFLX": return "SUPER_FLEX"
    case "IDP", "IDPFLEX", "IDP_FLEX", "DFLEX", "DL_LB_DB", "DL_LB", "LB_DB", "DL_DB": return "IDP_FLEX"
    default: return u == "FLEX" ? "FLEX" : u
    }
}

// Flex slot definitions (canonical)
private let offensiveFlexSlots: Set = ["FLEX", "WRRB_FLEX", "REC_FLEX", "SUPER_FLEX"]
private let idpFlexSlots: Set = ["IDP_FLEX"]

// Helper to determine if slot is offensive flex
private func isOffensiveFlexSlot(_ slot: String) -> Bool {
    offensiveFlexSlots.contains(canonicalFlexSlot(slot))
}
// Helper to determine if slot is defensive flex
private func isDefensiveFlexSlot(_ slot: String) -> Bool {
    canonicalFlexSlot(slot) == "IDP_FLEX"
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

// MARK: - Shared lineup helpers (mirrors MyTeamView behavior)

private func positionColor(_ pos: String) -> Color {
    switch PositionNormalizer.normalize(pos) {
    case "QB": return .red
    case "RB": return .green
    case "WR": return .blue
    case "TE": return .yellow
    case "K":  return .purple.opacity(0.6)
    case "DL": return .orange
    case "LB": return .purple
    case "DB": return .pink
    default: return .white
    }
}

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
    for alt in altPositions { appendIfNew(alt) }
    return parts.isEmpty ? normBase : parts.joined(separator: "/")
}

// Renamed to avoid module-level collisions with MyTeamView
private struct MatchupAssignedSlot: Identifiable {
    let id = UUID()
    let playerId: String
    let slot: String
    let playerPos: String
    let altPositions: [String]
    let displayName: String
    let score: Double
}

private struct MatchupBenchPlayer: Identifiable {
    let id: String
    let pos: String
    let altPositions: [String]
    let displayName: String
    let score: Double
}

struct MatchupView: View {
    enum LineupTab: Hashable {
        case user
        case opponent
        case rol
    }

    @EnvironmentObject var leagueManager: SleeperLeagueManager
    @EnvironmentObject var appSelection: AppSelection
    @EnvironmentObject var authViewModel: AuthViewModel
    @Binding var selectedTab: Tab

    // MARK: - Utility Models (simplified to management stats only)
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
    @State private var lineupTab: LineupTab = .user

    // MARK: - Centralized Selection
    private var league: LeagueData?  { appSelection.selectedLeague }

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
        FontLoader.postScriptName(matching: "Black Knight") ??  "Black Knight"
    }
    private var pickSixPostScriptName: String {
        FontLoader.postScriptName(matching: "Pick Six") ?? "Pick Six"
    }

    // Helper:  determine if a matchup week has meaningful data (not solely padded placeholders)
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

    private var userTeamStanding: TeamStanding?  {
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
    private var currentWeekNumber:  Int {
        if let weekNum = Int(selectedWeek.replacingOccurrences(of:  "Week ", with: "")), !selectedWeek.isEmpty {
            return weekNum
        }
        return currentMatchupWeek
    }

    // Week selector default logic:  prefer global current week explicitly (enforced by app)
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
        leagueManager.refreshLeagueData(leagueId:  leagueId) { result in
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

    // MARK: - Layout helpers reused from MyTeamView

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

    private func isEligible(_ c: (id: String, pos: String, altPos: [String], score: Double), allowed: Set<String>) -> Bool {
        let normBase = PositionNormalizer.normalize(c.pos)
        let normAlt = c.altPos.map { PositionNormalizer.normalize($0) }
        if allowed.contains(normBase) { return true }
        return !allowed.intersection(Set(normAlt)).isEmpty
    }

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
        return fallbackId.isEmpty ? position : fallbackId
    }

    private func assignPlayersToSlotsPatched(team: TeamStanding, week: Int, slots: [String], myEntry: MatchupEntry, playerCache: [String: RawSleeperPlayer]) -> [MatchupAssignedSlot] {
        guard let starters = myEntry.starters, let playersPoints = myEntry.players_points, let playersPool = myEntry.players else { return [] }
        var results: [MatchupAssignedSlot] = []
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
            results.append(MatchupAssignedSlot(playerId: player_id, slot: slot, playerPos: p.position, altPositions: altPos, displayName: name, score: score))
        }
        return results
    }

    private func getBenchPlayersPatched(team: TeamStanding, week: Int, starters: [String], myEntry: MatchupEntry, playerCache: [String: RawSleeperPlayer]) -> [MatchupBenchPlayer] {
        guard let playersPoints = myEntry.players_points, let playersPool = myEntry.players else { return [] }
        let starterSet = Set(starters)
        var res: [MatchupBenchPlayer] = []
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
                res.append(MatchupBenchPlayer(id: pid, pos: p.position, altPositions: altPos, displayName: name, score: score))
            }
        }
        return res.sorted { $0.score > $1.score }
    }

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
            for idx in 0..<padded.count {
                let pid = padded[idx]
                guard pid != "0" else { continue }
                let slot = startingSlots[mpSafe: idx] ?? "FLEX"
                let player = team.roster.first(where: { $0.id == pid })
                    ?? (leagueManager.playerCache ?? [:])[pid].map { raw in
                        Player(id: pid, position: raw.position ?? "UNK", altPositions: raw.fantasy_positions, weeklyScores: [])
                    }
                let basePos = PositionNormalizer.normalize(player?.position ?? "UNK")
                let fantasy = (player?.altPositions ?? []).map { PositionNormalizer.normalize($0) }
                let credited = PositionNormalizer.normalize(
                    SlotPositionAssigner.countedPosition(for: slot, candidatePositions: fantasy, base: basePos)
                )
                if credited == normPos {
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

    private func lineupData(for team: TeamStanding, week: Int) -> (assigned: [MatchupAssignedSlot], bench: [MatchupBenchPlayer]) {
        guard let season = league?.seasons.first(where: { $0.id == appSelection.selectedSeason }) ?? league?.seasons.sorted(by: { $0.id < $1.id }).last,
              let slots = league?.startingLineup,
              let myEntry = season.matchupsByWeek?[week]?.first(where: { $0.roster_id == Int(team.id) }) else {
            return ([], [])
        }
        let allPlayers = leagueManager.playerCache ?? [:]
        let startingSlots = slots.filter { !["BN", "IR", "TAXI"].contains($0) }
        let assigned = assignPlayersToSlotsPatched(team: team, week: week, slots: startingSlots, myEntry: myEntry, playerCache: allPlayers)
        let starters = myEntry.starters ?? []
        let benchRaw = getBenchPlayersPatched(team: team, week: week, starters: starters, myEntry: myEntry, playerCache: allPlayers)

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
        return (assigned, bench)
    }

    // MARK: - UI
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if isLoading {
                ProgressView("Loading matchup data...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .tint(.orange)
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
    private var headerBlock:  some View {
        VStack(spacing: 18) {
            Group {
                if let _ = userTeamStanding, let _ = opponentTeamStanding {
                    VStack(spacing: 6) {
                        MyTeamView.phattGradientText(Text(userTeamName), size: 36)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        MyTeamView.phattGradientText(Text("Vs. "), size: 18)
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
        } label:  {
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

    // Placeholder to satisfy missing symbol; keeps UI stable without altering behavior.
    private var headToHeadContent: some View {
        VStack(spacing: 12) {
            Text("Head to Head view is coming soon.")
                .foregroundColor(.white.opacity(0.8))
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Matchup Content (top:  Matchup Stats, below: Lineups)
    private var matchupContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let user = userTeamStanding, let opp = opponentTeamStanding, let _ = league {
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

                    VStack(spacing: 12) {
                        lineupTabBar
                        lineupTabContent
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

    private func lineupTabButton(_ tab: LineupTab, title: String, enabled: Bool = true) -> some View {
        let isSelected = lineupTab == tab
        return Button {
            guard enabled else { return }
            lineupTab = tab
        } label: {
            Text(title)
                .font(.custom("Phatt", size: 14))
                .bold()
                .foregroundColor(enabled ? (isSelected ? .black : .orange) : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.orange : Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.6), lineWidth: isSelected ? 0 : 1)
                        )
                )
        }
        .disabled(!enabled)
    }

    private var lineupTabBar: some View {
        HStack(spacing: 8) {
            lineupTabButton(.user, title: "\(userDisplayName)'s Lineup", enabled: userTeamStanding != nil)
            lineupTabButton(.opponent, title: "\(opponentDisplayName)'s Lineup", enabled: opponentTeamStanding != nil)
            lineupTabButton(.rol, title: "R.O.L.", enabled: true)
        }
    }

    @ViewBuilder
    private var lineupTabContent: some View {
        switch lineupTab {
        case .user:
            teamLineupBox(team: userTeamStanding, title: "\(userDisplayName)'s Lineup")
        case .opponent:
            teamLineupBox(team: opponentTeamStanding, title: "\(opponentDisplayName)'s Lineup")
        case .rol:
            VStack(alignment: .center, spacing: 8) {
                Text("R.O.L.")
                    .font(.headline.bold())
                    .foregroundColor(.orange)
                Text("Placeholder content coming soon.")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
        }
    }

    private func matchupStatsSection(user: TeamStanding, opp: TeamStanding) -> some View {
        let week = currentWeekNumber
        let (uPF, uMax, _, _, _, _) = computeWeeklyLineupPointsPatched(team: user, week: week)
        let (oPF, oMax, _, _, _, _) = computeWeeklyLineupPointsPatched(team: opp, week: week)

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(user.name).foregroundColor(.cyan).bold()
                    Spacer()
                }
                HStack {
                    Text("Points").foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Text(String(format: "%.2f", uPF)).foregroundColor(.green)
                }
                HStack {
                    Text("Max Points").foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Text(String(format: "%.2f", uMax)).foregroundColor(.white.opacity(0.85))
                }
                HStack {
                    Text("Mgmt %").foregroundColor(.white.opacity(0.9))
                    Spacer()
                    let mgmt = uMax > 0 ? (uPF / uMax * 100) : 0
                    Text(String(format: "%.2f%%", mgmt)).foregroundColor(Color.mgmtPercentColor(mgmt))
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .trailing, spacing: 6) {
                HStack {
                    Spacer()
                    Text(opp.name).foregroundColor(.yellow).bold()
                }
                HStack {
                    Text(String(format: "%.2f", oPF)).foregroundColor(.green)
                    Spacer()
                    Text("Points").foregroundColor(.white.opacity(0.9))
                }
                HStack {
                    Text(String(format: "%.2f", oMax)).foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Text("Max Points").foregroundColor(.white.opacity(0.9))
                }
                HStack {
                    let mgmt = oMax > 0 ? (oPF / oMax * 100) : 0
                    Text(String(format: "%.2f%%", mgmt)).foregroundColor(Color.mgmtPercentColor(mgmt))
                    Spacer()
                    Text("Mgmt %").foregroundColor(.white.opacity(0.9))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.25)))
    }

    private func teamLineupBox(team: TeamStanding?, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MyTeamView.phattGradientText(Text(title), size: 18)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            HStack {
                MyTeamView.phattGradientTextDefault(Text("Slot"))
                    .frame(maxWidth: .infinity / 3, alignment: .center)
                MyTeamView.phattGradientTextDefault(Text("Name"))
                    .frame(maxWidth: .infinity / 3, alignment: .center)
                MyTeamView.phattGradientTextDefault(Text("Score"))
                    .frame(maxWidth: .infinity / 3, alignment: .center)
            }

            if let t = team {
                let lineup = lineupData(for: t, week: currentWeekNumber)
                ForEach(lineup.assigned) { item in
                    let creditedPos = PositionNormalizer.normalize(
                        SlotPositionAssigner.countedPosition(
                            for: item.slot,
                            candidatePositions: ([item.playerPos] + item.altPositions).map { PositionNormalizer.normalize($0) },
                            base: PositionNormalizer.normalize(item.playerPos)
                        )
                    )
                    let scoreTint = scoreColor(for: item.score, position: creditedPos, week: currentWeekNumber)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.slot)
                            .frame(maxWidth: .infinity / 3, alignment: .leading)
                        HStack(spacing: 4) {
                            Text(item.displayName)
                                .font(.caption)
                            Text(positionDisplayLabel(base: item.playerPos, altPositions: item.altPositions))
                                .font(.caption2)
                                .foregroundColor(positionColor(creditedPos))
                        }
                        .frame(maxWidth: .infinity / 3, alignment: .leading)
                        Text(String(format: "%.2f", item.score))
                            .foregroundColor(scoreTint)
                            .frame(maxWidth: .infinity / 3, alignment: .trailing)
                    }
                    .font(.caption)
                }

                MyTeamView.pickSixGradientText(Text("-----BENCH-----"), size: 18)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 6)

                ForEach(lineup.bench) { player in
                    let posNorm = PositionNormalizer.normalize(player.pos)
                    let scoreTint = scoreColor(for: player.score, position: posNorm, week: currentWeekNumber)
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

    // MARK: - Helpers for management stats and names
    private func managementTotals(team: TeamStanding, week: Int) -> (Double, Double) {
        let (pf, maxPF, _, _, _, _) = computeWeeklyLineupPointsPatched(team: team, week: week)
        return (pf, maxPF)
    }

    // MARK: - Lineup scoring (aligned with MyTeamView)
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
                !idpFlexSlots.contains(canonicalFlexSlot(slot)) &&
                !offensiveFlexSlots.contains(canonicalFlexSlot(slot)) {
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

    // MARK: - Position groups
    private let offensivePositions: Set = ["QB", "RB", "WR", "TE", "K"]
    private let defensivePositions: Set = ["DL", "LB", "DB"]
}

// MARK: - Safe index helper (renamed to avoid collisions)
private extension Collection {
    subscript(mpSafe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
