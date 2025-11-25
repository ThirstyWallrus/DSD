//
//  TeamStatExpandedView.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 8/25/25.
//
//

import SwiftUI

// Shared icon computation so TeamStatExpandedView and BalanceDetailSheet use identical logic.
private struct EfficiencyIconComputer {
    /// Returns (offIcon, defIcon) using deterministic rules:
    /// - Flame (🔥) appears when offense >= 90.00% (off side), but if defense >= 90.00% the flame is placed on defense instead (defense takes precedence).
    /// - Snowflake (❄️):
    ///     • Offense gets ❄️ if offense < 80.00% (unconditional — it does not depend on defense).
    ///     • Otherwise, if offense >= 80.00% and defense < 80.00% then defense gets ❄️.
    /// - Sun (☀️) appears for values in [80.00%, 90.00%) and overrides other icons for that side.
    /// Each side receives at most one emoji; defense >= 90 wins flame placement.
    static func computeIcons(off: Double, def: Double) -> (offIcon: String, defIcon: String) {
        var offIcon = ""
        var defIcon = ""

        // 1) Flame: defense takes precedence if both >= 90
        if def >= 90.0 {
            defIcon = "🔥"
        } else if off >= 90.0 {
            offIcon = "🔥"
        }

        // 2) Snowflake: OFFENSE-first rule (off < 80 always gets ❄️).
        // If offense is below 80, give offense the snowflake (replacing any previous off icon).
        if off < 80.0 {
            offIcon = "❄️"
        } else {
            // Only consider placing a snowflake on defense if offense is NOT below 80.
            // Do not overwrite an existing flame on defense (defIcon == "🔥").
            if def < 80.0 && defIcon.isEmpty {
                defIcon = "❄️"
            }
        }

        // 3) Sun overrides for each side if in [80, 90)
        if off >= 80.0 && off < 90.0 {
            offIcon = "☀️"
        }
        if def >= 80.0 && def < 90.0 {
            defIcon = "☀️"
        }

        return (offIcon, defIcon)
    }
}

struct TeamStatExpandedView: View {
    @EnvironmentObject var appSelection: AppSelection
    // Add league manager so we can access global player caches when roster lacks a player id.
    @EnvironmentObject var leagueManager: SleeperLeagueManager

    // Closure returns (optional) aggregated all time stats wrapper for this team
    let aggregatedAllTime: (TeamStanding) -> DSDDashboard.AggregatedTeamStats?
    
    @State private var showConsistencyInfo = false
    @State private var showEfficiencyInfo = false
    // New: show detailed balance modal for the Full Team Efficiency Spotlight
    @State private var showBalanceDetail = false
    
    // Positions used for the whole-team breakdown (offense + defense)
    private let teamPositions: [String] = ["QB","RB","WR","TE","K","DL","LB","DB"]
    
    // Position color mapping (normalized tokens)
    private var positionColors: [String: Color] {
        [
            PositionNormalizer.normalize("QB"): .red,
            PositionNormalizer.normalize("RB"): .green,
            PositionNormalizer.normalize("WR"): .blue,
            PositionNormalizer.normalize("TE"): .yellow,
            PositionNormalizer.normalize("K"): Color.purple,
            PositionNormalizer.normalize("DL"): .orange,
            PositionNormalizer.normalize("LB"): .purple.opacity(0.7),
            PositionNormalizer.normalize("DB"): .pink
        ]
    }
    
    // Use selected team from AppSelection
    private var team: TeamStanding? { appSelection.selectedTeam }
    private var league: LeagueData? { appSelection.selectedLeague }
    private var isAllTime: Bool { appSelection.isAllTimeMode }
    private var aggregate: DSDDashboard.AggregatedTeamStats? {
        guard isAllTime, let t = team else { return nil }
        return aggregatedAllTime(t)
    }
    
    // MARK: - Weeks to Include (Exclude Current Week if Incomplete)
    private var validWeeks: [Int] {
        guard let lg = league, let team else { return [] }
        // For season mode, use the selected season
        if !isAllTime, let season = lg.seasons.first(where: { $0.id == appSelection.selectedSeason }) {
            let allWeeks = season.matchupsByWeek?.keys.sorted() ?? []
            if let currentWeek = allWeeks.max(), allWeeks.count > 1 {
                return allWeeks.filter { $0 != currentWeek }
            }
            return allWeeks
        }
        // For all time mode, use the latest season's weeks (continuity)
        if isAllTime {
            let latest = lg.seasons.sorted { $0.id < $1.id }.last
            let allWeeks = latest?.matchupsByWeek?.keys.sorted() ?? []
            if let currentWeek = allWeeks.max(), allWeeks.count > 1 {
                return allWeeks.filter { $0 != currentWeek }
            }
            return allWeeks
        }
        return []
    }
    
    // MARK: - Authoritative week points helper
    // Returns playerId -> points for the given team & week using:
    // 1) matchup.players_points if available for that week & roster entry (PREFERRED)
    //    - if matchup.starters exist: returns players_points filtered to starters only
    //    - else returns the full players_points mapping
    // 2) fallback to deduplicated roster.weeklyScores (prefer matchup_id match or highest points)
    private func authoritativePointsForWeek(team: TeamStanding, week: Int) -> [String: Double] {
        // Try matchup.players_points (authoritative)
        if let lg = league {
            // pick season (selected or latest for All Time)
            let season = (!isAllTime)
                ? lg.seasons.first(where: { $0.id == appSelection.selectedSeason })
                : lg.seasons.sorted { $0.id < $1.id }.last
            if let season {
                if let entries = season.matchupsByWeek?[week],
                   let rosterIdInt = Int(team.id),
                   let myEntry = entries.first(where: { $0.roster_id == rosterIdInt }),
                   let playersPoints = myEntry.players_points,
                   !playersPoints.isEmpty {
                    // If starters present, sum only starters (match MatchupView / MyLeagueView)
                    if let starters = myEntry.starters, !starters.isEmpty {
                        var map: [String: Double] = [:]
                        for pid in starters {
                            if let p = playersPoints[pid] {
                                map[pid] = p
                            } else {
                                // if starter id not present in players_points, skip or treat as 0
                                map[pid] = 0.0
                            }
                        }
                        return map
                    } else {
                        // No starters info — fall back to full players_points map
                        return playersPoints.mapValues { $0 }
                    }
                }
                // else fall through to roster fallback
            }
        }
        // Fallback: build mapping from roster.weeklyScores but deduplicate per player/week
        var result: [String: Double] = [:]
        // If we can find the matchup_id for this team/week, prefer that matchup_id when picking entries
        var preferredMatchupId: Int? = nil
        if let lg = league {
            let season = (!isAllTime)
                ? lg.seasons.first(where: { $0.id == appSelection.selectedSeason })
                : lg.seasons.sorted { $0.id < $1.id }.last
            if let season, let entries = season.matchupsByWeek?[week], let rosterIdInt = Int(team.id) {
                if let myEntry = entries.first(where: { $0.roster_id == rosterIdInt }) {
                    preferredMatchupId = myEntry.matchup_id
                }
            }
        }
        // For each player on roster, collect weeklyScores for this week and pick one entry
        for player in team.roster {
            let scores = player.weeklyScores.filter { $0.week == week }
            if scores.isEmpty { continue }
            // If a preferredMatchupId exists, prefer an entry with that matchup_id
            if let mid = preferredMatchupId, let matched = scores.first(where: { $0.matchup_id == mid }) {
                result[player.id] = matched.points_half_ppr ?? matched.points
            } else {
                // otherwise pick the entry with max points to avoid double-counting duplicates
                if let best = scores.max(by: { ($0.points_half_ppr ?? $0.points) < ($1.points_half_ppr ?? $1.points) }) {
                    result[player.id] = best.points_half_ppr ?? best.points
                }
            }
        }
        return result
    }
    
    // MARK: - Stacked Bar Chart Data (whole team)
    private var stackedBarWeekData: [StackedBarWeeklyChart.WeekBarData] {
        guard let team else { return [] }
        let sortedWeeks = validWeeks
        return sortedWeeks.map { week in
            let playerPoints = authoritativePointsForWeek(team: team, week: week)
            // Map playerId -> position and sum by normalized position tokens
            var posSums: [String: Double] = [:]
            for (pid, pts) in playerPoints {
                if let player = team.roster.first(where: { $0.id == pid }) {
                    let norm = PositionNormalizer.normalize(player.position)
                    posSums[norm, default: 0.0] += pts
                } else if let raw = leagueManager.playerCache?[pid] ?? leagueManager.allPlayers[pid] {
                    // If player isn't present in the TeamStanding roster, look up their cached RawSleeperPlayer
                    // (populated by SleeperLeagueManager). Use the cached position when available.
                    let pos = PositionNormalizer.normalize(raw.position ?? "UNK")
                    posSums[pos, default: 0.0] += pts
                } else {
                    // Last-resort fallback: we couldn't resolve position from roster or caches.
                    // To avoid dropping points (which causes chart totals to differ from official matchup total),
                    // attribute to a conservative default bucket (WR) so segments still sum to the matchup total.
                    // TODO: if you prefer a dedicated "Other" bucket, add it to teamPositions and positionColors.
                    posSums["WR", default: 0.0] += pts
                }
            }
            // Ensure positions exist in dict (0 default)
            let segments = teamPositions.map { pos -> StackedBarWeeklyChart.WeekBarData.Segment in
                let norm = PositionNormalizer.normalize(pos)
                return StackedBarWeeklyChart.WeekBarData.Segment(
                    id: pos,
                    position: norm,
                    value: posSums[norm] ?? 0
                )
            }
            return StackedBarWeeklyChart.WeekBarData(id: week, segments: segments)
        }
    }
    
    // Helper: check if a PlayerWeeklyScore's player matches the target normalized position
    private func matchesNormalizedPosition(_ score: PlayerWeeklyScore, pos: String) -> Bool {
        guard let team = team,
              let player = team.roster.first(where: { $0.id == score.player_id }) else { return false }
        return PositionNormalizer.normalize(player.position) == PositionNormalizer.normalize(pos)
    }
    
    // Derived weekly totals (actual roster total per week)
    private var sideWeeklyPoints: [Double] {
        stackedBarWeekData.map { $0.total }
    }
    
    // Fix: compute weekly points that are considered "valid" (non-zero) to avoid dividing by future zero weeks.
    // Use non-zero totals for average calculations. This mirrors how we include only completed weeks in other services.
    private var sideWeeklyPointsNonZero: [Double] {
        // Consider a week valid if total > 0 OR if there's at least one non-zero segment (some leagues may record 0.0 for a real week)
        // stackedBarWeekData already sums segments; treat totals > 0 as valid
        let nonZero = sideWeeklyPoints.filter { $0 > 0.0 }
        // If we don't have any non-zero weeks but team.weeklyActualLineupPoints exists, use those entries
        if nonZero.isEmpty, let team = team, let weekly = team.weeklyActualLineupPoints {
            let vals = weekly.keys.sorted().map { weekly[$0] ?? 0.0 }.filter { $0 > 0.0 }
            if !vals.isEmpty { return vals }
        }
        return nonZero
    }
    
    private var weeksPlayed: Int { sideWeeklyPointsNonZero.count }
    private var last3Avg: Double {
        guard weeksPlayed > 0 else { return 0 }
        // Use most recent non-zero weeks — stack preserves week order by validWeeks mapping,
        // so take last n elements from sideWeeklyPoints filtered to non-zero.
        let recent = sideWeeklyPointsNonZero.suffix(3)
        return recent.reduce(0,+) / Double(min(3, recent.count))
    }
    private var seasonAvg: Double {
        // Primary: average of non-zero weekly totals (i.e., completed weeks with data)
        if weeksPlayed > 0 {
            return sideWeeklyPointsNonZero.reduce(0,+) / Double(weeksPlayed)
        }
        // Fallback 1: aggregated all-time average if available
        if let agg = aggregate {
            return agg.avgTeamPPW
        }
        // Fallback 2: stored team value (may be precomputed or conservative)
        return team?.teamPointsPerWeek ?? 0
    }
    private var formDelta: Double { last3Avg - seasonAvg }
    private var formDeltaColor: Color {
        if formDelta > 2 { return .green }
        if formDelta < -2 { return .red }
        return .yellow
    }
    
    // MARK: - Team Points and Management %
    private var teamPointsFor: Double {
        if let agg = aggregate { return agg.totalPointsFor }
        return team?.pointsFor ?? 0
    }
    private var teamMaxPointsFor: Double {
        if let agg = aggregate { return agg.totalMaxPointsFor }
        return team?.maxPointsFor ?? 0
    }
    private var managementPercent: Double {
        guard teamMaxPointsFor > 0 else { return 0 }
        return (teamPointsFor / teamMaxPointsFor) * 100
    }
    
    // Compute latest valid week's actual total (if any)
    private var latestValidWeekTotal: Double? {
        guard let team else { return nil }
        // Map weeks to totals from stackedBarWeekData (which uses validWeeks in order)
        let pairs = zip(validWeeks, stackedBarWeekData)
        // Find last week with total > 0
        if let last = pairs.reversed().first(where: { $0.1.total > 0 }) {
            return last.1.total
        }
        // fallback: use weeklyActualLineupPoints last non-zero
        if let weekly = team.weeklyActualLineupPoints {
            let last = weekly.keys.sorted().reversed().first(where: { (weekly[$0] ?? 0) > 0 })
            if let wk = last { return weekly[wk] }
        }
        return nil
    }
    
    // MARK: New helpers to compute a week's optimal (max) points from roster + lineup config
    // This mirrors the greedy week-max logic used in DataMigrationManager, kept local to avoid
    // wide churn. It is used to exclude the latest week entirely (numerator + denominator) when
    // computing the "previous Mgmt%".
    private func inferredLineupConfig(from roster: [Player]) -> [String: Int] {
        var counts: [String:Int] = [:]
        for p in roster {
            // Normalize position for starter slot assignment
            let normalized = PositionNormalizer.normalize(p.position)
            counts[normalized, default: 0] += 1
        }
        return counts.mapValues { min($0, 3) }
    }
    private func expandSlots(lineupConfig: [String:Int]) -> [String] {
        lineupConfig.flatMap { Array(repeating: $0.key, count: $0.value) }
    }
    private func allowedPositions(for slot: String) -> Set<String> {
        switch slot.uppercased() {
        case "QB","RB","WR","TE","K","DL","LB","DB": return [slot.uppercased()]
        case "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE": return ["RB","WR","TE"]
        case "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX": return ["QB","RB","WR","TE"]
        case "IDP": return ["DL","LB","DB"]
        default:
            if slot.uppercased().contains("IDP") { return ["DL","LB","DB"] }
            return [slot.uppercased()]
        }
    }
    private func isEligible(basePos: String, fantasy: [String], allowed: Set<String>) -> Bool {
        let normalizedAllowed = Set(allowed.map { PositionNormalizer.normalize($0) })
        let candidates = ([basePos] + fantasy).map { PositionNormalizer.normalize($0) }
        return candidates.contains(where: { normalizedAllowed.contains($0) })
    }
    /// Compute the optimal (max) points for a given week by greedily selecting the highest-scoring eligible player for each lineup slot.
    /// Returns nil if computation cannot be performed (e.g., no weekly scores available).
    private func computeWeekMax(for week: Int) -> Double? {
        guard let team = team else { return nil }
        let roster = team.roster
        // Determine lineup slots
        let lineupConfig = team.lineupConfig ?? inferredLineupConfig(from: roster)
        let slots = expandSlots(lineupConfig: lineupConfig)
        if slots.isEmpty { return nil }
        // Build candidates from roster (player id -> candidate)
        struct Candidate {
            let playerId: String
            let basePos: String
            let fantasy: [String]
            let points: Double
        }
        var candidates: [Candidate] = []
        for p in roster {
            if let ws = p.weeklyScores.first(where: { $0.week == week }) {
                let pts = ws.points_half_ppr ?? ws.points
                candidates.append(Candidate(playerId: p.id, basePos: p.position, fantasy: p.altPositions ?? [], points: pts))
            }
        }
        if candidates.isEmpty { return nil } // cannot compute
        var used = Set<String>()
        var weekMax: Double = 0.0
        // Greedy: for each slot pick highest points candidate eligible and not used
        for slot in slots {
            let allowed = allowedPositions(for: slot)
            let pick = candidates
                .filter { !used.contains($0.playerId) && isEligible(basePos: $0.basePos, fantasy: $0.fantasy, allowed: allowed) }
                .max(by: { $0.points < $1.points })
            if let p = pick {
                used.insert(p.playerId)
                weekMax += p.points
            }
        }
        // If we managed to fill at least one slot, return weekMax (0 could be legitimate).
        return weekMax
    }
    
    // Prior management percent approximated by removing the latest completed week's contribution.
    // UPDATED: Exclude the most recent week from BOTH numerator (points) and denominator (season max).
    // If we can compute latestWeekMax we subtract it from teamMaxPointsFor. If not computable, fall back to
    // old behavior (subtract numerator only) but log a debug note. This preserves continuity when roster scores
    // are incomplete while honoring the user's requirement where possible.
    private var priorManagementPercent: Double {
        guard let last = latestValidWeekTotal else { return 0 }
        guard teamMaxPointsFor > 0 else { return 0 }
        let priorPoints = max(0, teamPointsFor - last)
        // find the week index corresponding to latestValidWeekTotal
        guard let lastWeek = findLatestValidWeek() else {
            // can't find week index — fallback to original behavior
            return (priorPoints / teamMaxPointsFor) * 100
        }
        if let lastWeekMax = computeWeekMax(for: lastWeek), lastWeekMax > 0 {
            let priorMax = teamMaxPointsFor - lastWeekMax
            if priorMax > 0 {
                return (priorPoints / priorMax) * 100
            } else {
                // priorMax non-positive (unexpected) — fallback
                return (priorPoints / teamMaxPointsFor) * 100
            }
        } else {
            // Could not compute week max (missing weekly scores) — fallback to original behavior
            // NOTE: This is only reached when we cannot reconstruct the week's optimal lineup from roster data.
            return (priorPoints / teamMaxPointsFor) * 100
        }
    }
    
    // Helper to find the week number corresponding to latestValidWeekTotal (if any)
    private func findLatestValidWeek() -> Int? {
        guard let team else { return nil }
        let pairs = zip(validWeeks, stackedBarWeekData)
        if let last = pairs.reversed().first(where: { $0.1.total > 0 }) {
            return last.0
        }
        // fallback: check weeklyActualLineupPoints if available
        if let weekly = team.weeklyActualLineupPoints {
            let lastKey = weekly.keys.sorted().reversed().first(where: { (weekly[$0] ?? 0) > 0 })
            if let wk = lastKey { return wk }
        }
        return nil
    }
    
    private var managementDelta: Double {
        managementPercent - priorManagementPercent
    }
    
    // MARK: - Full Team Efficiency Spotlight (offense vs defense)
    // Prefer aggregated all-time values in All Time mode, otherwise prefer season fields on TeamStanding.
    private var offenseMgmtPercent: Double {
        if isAllTime {
            if let agg = aggregate, let aggOff = agg.avgOffPPW { // avgOffPPW is PPW — but prefer management percent if available
                // If aggregated offensiveManagementPercent exists, use it; otherwise attempt compute percent via totals
                if let a = aggregate?.aggregatedManagementPercent { return a } // fallback to overall mgmt
                return aggOff // this is PPW, not percent; keep it as fallback
            }
            return team?.offensiveManagementPercent ?? 0
        } else {
            if let t = team {
                if let offMgmt = t.offensiveManagementPercent { return offMgmt }
                // Fallback: try compute via offensivePointsFor / maxOffensivePointsFor
                if let offPF = t.offensivePointsFor, let maxOff = t.maxOffensivePointsFor, maxOff > 0 {
                    return (offPF / maxOff) * 100
                }
            }
            return 0
        }
    }
    private var defenseMgmtPercent: Double {
        if isAllTime {
            if let agg = aggregate, let aggDef = agg.avgDefPPW {
                if let a = aggregate?.aggregatedManagementPercent { return a } // fallback to overall mgmt
                return aggDef
            }
            return team?.defensiveManagementPercent ?? 0
        } else {
            if let t = team {
                if let defMgmt = t.defensiveManagementPercent { return defMgmt }
                if let defPF = t.defensivePointsFor, let maxDef = t.maxDefensivePointsFor, maxDef > 0 {
                    return (defPF / maxDef) * 100
                }
            }
            return 0
        }
    }
    private var balancePercent: Double {
        abs(offenseMgmtPercent - defenseMgmtPercent)
    }
    
    // UI helpers for the Full Team Efficiency Spotlight
    private var offenseGradient: LinearGradient {
        LinearGradient(colors: [Color.red, Color.yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var defenseGradient: LinearGradient {
        LinearGradient(colors: [Color.green, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    // Use shared icon computation
    private func computeIcons() -> (off: String, def: String) {
        let icons = EfficiencyIconComputer.computeIcons(off: offenseMgmtPercent, def: defenseMgmtPercent)
        return (icons.offIcon, icons.defIcon)
    }
    private var offIcon: String { computeIcons().off }
    private var defIcon: String { computeIcons().def }
    
    private func generateBalanceTagline(off: Double, def: Double, balance: Double) -> String {
        if balance < 5 { return "Perfectly synced! Your team is a well-oiled machine." }
        if off > def + 10 { return "Offense is dominating—beef up that D before playoffs!" }
        if def > off + 10 { return "Defense wins championships? Yours is carrying—time for offensive firepower." }
        return "Rough on both sides—roster revamp incoming?"
    }
    
    // MARK: - Consistency (StdDev)
    private var stdDev: Double {
        guard weeksPlayed > 1 else { return 0 }
        let mean = seasonAvg
        let variance = sideWeeklyPointsNonZero.reduce(0) { $0 + pow($1 - mean, 2) } / Double(weeksPlayed)
        return sqrt(variance)
    }
    private var consistencyDescriptor: String {
        switch stdDev {
        case 0..<15: return "Steady"
        case 15..<35: return "Average"
        case 35..<55: return "Swingy"
        default: return "Boom-Bust"
        }
    }
    
    // MARK: - Strengths/Weaknesses
    private var strengths: [String] {
        if let agg = aggregate {
            var arr: [String] = []
            if agg.aggregatedManagementPercent >= 75 { arr.append("Efficient Usage") }
            if stdDev < 15 && weeksPlayed >= 4 { arr.append("Reliable Output") }
            if arr.isEmpty { arr.append("Balanced Roster") }
            return arr
        }
        var arr: [String] = []
        if managementPercent >= 75 { arr.append("Efficient Usage") }
        if stdDev < 15 && weeksPlayed >= 4 { arr.append("Reliable Output") }
        if arr.isEmpty { arr.append("Balanced Roster") }
        return arr
    }
    private var weaknesses: [String] {
        if let agg = aggregate {
            var arr: [String] = []
            if agg.aggregatedManagementPercent < 55 { arr.append("Usage Inefficiency") }
            if stdDev > 40 { arr.append("Volatility") }
            if weeksPlayed >= 3 && last3Avg < seasonAvg - 5 { arr.append("Recent Dip") }
            if arr.isEmpty { arr.append("No Major Weakness") }
            return arr
        }
        var arr: [String] = []
        if managementPercent < 55 { arr.append("Usage Inefficiency") }
        if stdDev > 40 { arr.append("Volatility") }
        if weeksPlayed >= 3 && last3Avg < seasonAvg - 5 { arr.append("Recent Dip") }
        if arr.isEmpty { arr.append("No Major Weakness") }
        return arr
    }
    
    // MARK: - Grade computation (using TeamGradeComponents + gradeTeams)
    // Build TeamGradeComponents for all teams in the current league (selected season or all-time mapping)
    private var computedGrade: (grade: String, composite: Double)? {
        guard let lg = league else { return nil }
        // Build components for season mode using season-level values (or aggregatedAllTime when appropriate)
        let teamsToProcess: [TeamStanding] = {
            // If we have a seasons array and we're in season mode, try to target selectedSeason
            if !isAllTime, let season = lg.seasons.first(where: { $0.id == appSelection.selectedSeason }) {
                return season.teams
            }
            // Fallback to league latest teams
            return lg.seasons.sorted { $0.id < $1.id }.last?.teams ?? lg.teams
        }()
        var comps: [TeamGradeComponents] = []
        for t in teamsToProcess {
            // For the given team, get pointsFor, ppw, mgmt, offMgmt, defMgmt, recordPct, positional ppw
            let aggForTeam: DSDDashboard.AggregatedTeamStats? = {
                if isAllTime { return aggregatedAllTime(t) }
                return nil
            }()
            // Points for / max points for (season vs all-time)
            let pf = isAllTime ? (aggForTeam?.totalPointsFor ?? t.pointsFor) : (t.pointsFor)
            let mpf = isAllTime ? (aggForTeam?.totalMaxPointsFor ?? t.maxPointsFor) : (t.maxPointsFor)
            // Management percent
            let mgmt = (mpf > 0) ? (pf / mpf * 100) : (t.managementPercent)
            // Off/Def management percent: prefer aggregated fields when in all-time mode; otherwise use season values on TeamStanding
            let offMgmt: Double = {
                if isAllTime {
                    if let agg = aggForTeam,
                       let maxOff = agg.totalMaxOffensivePointsFor,
                       maxOff > 0 {
                        return (agg.offensivePointsFor ?? 0) / maxOff * 100
                    }
                    return t.offensiveManagementPercent ?? 0
                } else {
                    return t.offensiveManagementPercent ?? 0
                }
            }()
            let defMgmt: Double = {
                if isAllTime {
                    if let agg = aggForTeam,
                       let maxDef = agg.totalMaxDefensivePointsFor,
                       maxDef > 0 {
                        return (agg.defensivePointsFor ?? 0) / maxDef * 100
                    }
                    return t.defensiveManagementPercent ?? 0
                } else {
                    return t.defensiveManagementPercent ?? 0
                }
            }()
            // PPW value (season vs all-time) — IMPORTANT: use DSDStatsService filtered helper when available
            let ppwVal: Double = {
                if isAllTime { return aggForTeam?.avgTeamPPW ?? t.teamPointsPerWeek }
                // compute season average via DSDStatsService filtered helper (use shared)
                if let lg2 = lg as LeagueData? {
                    return (DSDStatsService.shared.stat(for: t, type: .teamAveragePPW, league: lg2, selectedSeason: appSelection.selectedSeason) as? Double) ?? t.teamPointsPerWeek
                }
                return t.teamPointsPerWeek
            }()
            // Position averages (fallback to 0)
            let qb = (t.positionAverages?[PositionNormalizer.normalize("QB")] ?? 0)
            let rb = (t.positionAverages?[PositionNormalizer.normalize("RB")] ?? 0)
            let wr = (t.positionAverages?[PositionNormalizer.normalize("WR")] ?? 0)
            let te = (t.positionAverages?[PositionNormalizer.normalize("TE")] ?? 0)
            let k = (t.positionAverages?[PositionNormalizer.normalize("K")] ?? 0)
            let dl = (t.positionAverages?[PositionNormalizer.normalize("DL")] ?? 0)
            let lb = (t.positionAverages?[PositionNormalizer.normalize("LB")] ?? 0)
            let db = (t.positionAverages?[PositionNormalizer.normalize("DB")] ?? 0)
            // Record percent
            let (w,l,ties) = TeamGradeComponents.parseRecord(t.winLossRecord)
            let recordPct = (w + l + ties) > 0 ? Double(w) / Double(max(1, w + l + ties)) : 0.0
            let comp = TeamGradeComponents(
                pointsFor: pf,
                ppw: ppwVal,
                mgmt: mgmt,
                offMgmt: offMgmt,
                defMgmt: defMgmt,
                recordPct: recordPct,
                qbPPW: qb,
                rbPPW: rb,
                wrPPW: wr,
                tePPW: te,
                kPPW: k,
                dlPPW: dl,
                lbPPW: lb,
                dbPPW: db,
                teamName: t.name,
                teamId: t.id
            )
            comps.append(comp)
        }
        // Compute grades
        let graded = gradeTeams(comps)
        // Find this team's grade
        if let team = team, let found = graded.first(where: { $0.0 == team.name }) {
            return (found.1, found.2)
        }
        return nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Top: keep everything contained inside the card (Title centered + stat bubble row).
            // Use GeometryReader locally to size bubbles to available width so they never overflow.
            VStack(spacing: 8) {
                // IMPORTANT CHANGE:
                // Prefer showing the team being viewed in the title. Previously we prioritized
                // displaying the uploader username which led to confusion when viewing other teams.
                // Now the title uses the selected team's display name (aggregated when All Time)
                // and falls back to the uploader username or userTeam when no team is selected.
                let viewerName: String = {
                    if let team = team {
                        if isAllTime {
                            return aggregatedAllTime(team)?.teamName ?? team.name
                        }
                        return team.name
                    }
                    if let uname = appSelection.currentUsername, !uname.isEmpty { return uname }
                    return appSelection.userTeam.isEmpty ? "Team" : appSelection.userTeam
                }()
                
                Text("\(viewerName)'s Team Drop")
                    .font(.custom("Phatt", size: 20))
                    .bold()
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                
                GeometryReader { geo in
                    let horizontalPadding: CGFloat = 8
                    let spacing: CGFloat = 10
                    // We now show 4 bubbles: Grade, PF, MPF, PPW (Mgmt% removed from top row)
                    let itemCount: CGFloat = 4
                    // compute available width inside the geometry reader
                    let available = max(0, geo.size.width - horizontalPadding * 2 - (spacing * (itemCount - 1)))
                    // keep bubble size reasonable and cap it
                    let bubbleSize = min(72, floor(available / itemCount))
                    HStack(spacing: spacing) {
                        // 1) Grade
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            if let g = computedGrade?.grade {
                                ElectrifiedGrade(grade: g, fontSize: min(28, bubbleSize * 0.6))
                                    .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78)
                            } else {
                                Text("--")
                                    .font(.system(size: bubbleSize * 0.32, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78)
                            }
                        } caption: {
                            Text("Grade")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        // 2) PF
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            // Changed to show two decimal places
                            Text(String(format: "%.2f", teamPointsFor))
                                .font(.system(size: bubbleSize * 0.30, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78)
                        } caption: {
                            Text("PF")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        // 3) MPF (Max Points For) - REPLACED the previous Management% bubble
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            // Show max points for with two decimal places
                            Text(String(format: "%.2f", teamMaxPointsFor))
                                .font(.system(size: bubbleSize * 0.30, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78)
                        } caption: {
                            Text("MPF")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        // 4) PPW — RESTORED RESPONSIVE FONT BEHAVIOR:
                        // Use a large base font but allow minimumScaleFactor and single-line truncation so
                        // multi-digit numbers shrink to fit rather than wrap or overflow.
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            // We'll use a fairly large base size but allow the text to scale down
                            // to fit the bubble when necessary.
                            Text(String(format: "%.2f", seasonAvg))
                                .font(.system(size: bubbleSize * 0.36, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.4) // allow shrinking down to 40% of base size
                                .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78, alignment: .center)
                        } caption: {
                            Text("PPW")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    // Fix the geometry height so parent layout is stable
                    .frame(width: geo.size.width, height: bubbleSize + 26, alignment: .center)
                }
                .frame(height: 96) // conservative fixed height to keep inside card and avoid overflow
            }
            
            sectionHeader("Team Weekly Trend")
            // Chart: Excludes current week if incomplete, uses normalized positions
            // UPDATED: aggregateToOffDef = true so each weekly bar shows Offense (red) and Defense (blue) only.
                StackedBarWeeklyChart(
                                weekBars: stackedBarWeekData,
                                positionColors: positionColors,
                                showPositions: Set(teamPositions),
                                gridIncrement: 50,
                                barSpacing: 4,
                                tooltipFont: .caption2.bold(),
                                showWeekLabels: true,
                                aggregateToOffDef: true,
                                showAggregateLegend: true,            // show the Offense / Defense header
                                showOffensePositionsLegend: false,    // do NOT show QB/RB/WR/TE/K rows here
                                showDefensePositionsLegend: false     // do NOT show DL/LB/DB rows here
                            )
            .frame(height: 160)
            
            sectionHeader("Lineup Efficiency")
            lineupEfficiency
            sectionHeader("Recent Form")
            recentForm

            sectionHeader("Consistency Score")
            consistencyRow
            // Strengths / Weaknesses sections removed per user request.
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .sheet(isPresented: $showConsistencyInfo) {
            ConsistencyInfoSheet(stdDev: stdDev, descriptor: consistencyDescriptor)
                .presentationDetents([PresentationDetent.fraction(0.40)])
        }
        .sheet(isPresented: $showEfficiencyInfo) {
            EfficiencyInfoSheet(managementPercent: managementPercent,
                                pointsFor: team?.pointsFor ?? 0,
                                maxPointsFor: team?.maxPointsFor ?? 0)
            .presentationDetents([PresentationDetent.fraction(0.35)])
        }
        .sheet(isPresented: $showBalanceDetail) {
            BalanceDetailSheet(
                offensePct: offenseMgmtPercent,
                defensePct: defenseMgmtPercent,
                balancePct: balancePercent,
                tagline: generateBalanceTagline(off: offenseMgmtPercent, def: defenseMgmtPercent, balance: balancePercent)
            )
            .presentationDetents([PresentationDetent.fraction(0.40)])
        }
    }
    
    // MARK: - UI helpers for the stat bubble row
    
    /// A generic stat bubble builder: content is the visual bubble content, caption is the small label beneath.
    @ViewBuilder
    private func statBubble<Content: View, Caption: View>(width: CGFloat, height: CGFloat, @ViewBuilder content: @escaping () -> Content, @ViewBuilder caption: @escaping () -> Caption) -> some View {
        VStack(spacing: 6) {
            ZStack {
                // Slight glass/bubble effect background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.03))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors: [Color.white.opacity(0.02), Color.white.opacity(0.01)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.45), radius: 6, x: 0, y: 2)
                    .frame(width: width, height: height)
                    .overlay(
                        // subtle specular shine
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.0)]), startPoint: .top, endPoint: .center))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    )
                content()
            }
            caption()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var header: some View {
        HStack(spacing: 12) {
            Text(team?.winLossRecord ?? "--")
            Divider().frame(height: 10).background(Color.white.opacity(0.3))
            Text("PF \(String(format: "%.2f", teamPointsFor))")
            Divider().frame(height: 10).background(Color.white.opacity(0.3))
            Text("PPW \(String(format: "%.2f", seasonAvg))")
        }
        .font(.caption)
        .foregroundColor(.white.opacity(0.85))
    }
    
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.yellow)
            .padding(.top, 4)
    }
    
    // // MARK: - UPDATED: lineupEfficiency -> Full Team Efficiency Spotlight + Management Pill
    private var lineupEfficiency: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Re-insert ManagementPill above the full-team efficiency content.
            // This is the UI element you reported missing.
            ManagementPill(
                ratio: max(0.0, min(1.0, managementPercent / 100.0)),
                mgmtPercent: managementPercent,
                delta: managementDelta,
                mgmtColor: mgmtColor(for: managementPercent)
            )
            .padding(.vertical, 2)
            
            // Full Team Efficiency Spotlight title row (compact)
            HStack {
                Text("Full Team Efficiency Spotlight")
                    .font(.subheadline).bold()
                    .foregroundColor(.yellow)
                Spacer()
            }
            
            // Gauges row (compact single-row height ~56)
            HStack(spacing: 12) {
                // Offense Gauge
                VStack(spacing: 4) {
                    Gauge(value: offenseMgmtPercent / 100.0) {
                        // Empty label area (we render custom caption below)
                        EmptyView()
                    } currentValueLabel: {
                        Text(String(format: "%.2f%%", offenseMgmtPercent))
                            .font(.caption2).bold()
                            .foregroundColor(.white)
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(Gradient(colors: [Color(red: 0.7, green: 0.0, blue: 0.0), Color(red: 0.0, green: 1.0, blue: 0.0)]))
                    .frame(width: 52, height: 52)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(offIcon) Offense Efficiency")
                    .accessibilityValue(String(format: "%.2f percent", offenseMgmtPercent))
                    
                    Text("\(offIcon) Offense")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.9))
                }
                
                // Balance center
                VStack(spacing: 2) {
                    Text("⚖️ \(String(format: "%.2f%%", balancePercent))")
                        .font(.subheadline).bold()
                        .foregroundColor(balancePercent < 5 ? .green : .red)
                        .accessibilityLabel("Balance Score")
                        .accessibilityValue(String(format: "%.2f percent imbalance", balancePercent))
                    Text(generateBalanceTagline(off: offenseMgmtPercent, def: defenseMgmtPercent, balance: balancePercent))
                        .font(.caption2)
                        .foregroundColor(.yellow)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 220)
                }
                .onTapGesture {
                    showBalanceDetail = true
                }
                
                // Defense Gauge
                VStack(spacing: 4) {
                    Gauge(value: defenseMgmtPercent / 100.0) {
                        EmptyView()
                    } currentValueLabel: {
                        Text(String(format: "%.2F%%", defenseMgmtPercent))
                            .font(.caption2).bold()
                            .foregroundColor(.white)
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(Gradient(colors: [Color(red: 0.7, green: 0.0, blue: 0.0), Color(red: 0.0, green: 1.0, blue: 0.0)]))
                    .frame(width: 52, height: 52)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(defIcon) Defense Efficiency")
                    .accessibilityValue(String(format: "%.2f percent", defenseMgmtPercent))
                    
                    Text("\(defIcon) Defense")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.9))
                }
                
                Spacer()
                
                // Info button (keeps existing EfficiencyInfoSheet as quick reference)
                Button { showEfficiencyInfo = true } label: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.white.opacity(0.75))
                        .font(.caption)
                }
                .accessibilityLabel("More on Lineup Efficiency")
            }
            .frame(height: 60)
            
            // NOTE: The lower EfficiencyBar was intentionally removed per request since ManagementPill is now shown above.
        }
        .onChange(of: offenseMgmtPercent) { _ in /* animate or react if needed */ }
        .onChange(of: defenseMgmtPercent) { _ in /* animate or react if needed */ }
        .animation(.easeInOut, value: offenseMgmtPercent)
        .animation(.easeInOut, value: defenseMgmtPercent)
    }
    
    // MARK: - Management Pill View
    // Reintroduced this struct (previously present in earlier edits). It intentionally keeps rendering purely
    // local to the view, uses the managementDelta computed above, and formats delta as percentage-points (pp).
    private struct ManagementPill: View {
        let ratio: Double        // 0.0 - 1.0
        let mgmtPercent: Double  // 0-100
        let delta: Double        // mgmt change since prior week (percentage points)
        let mgmtColor: Color
        
        private let pillHeight: CGFloat = 24
        private let dotSize: CGFloat = 10
        private let horizontalPadding: CGFloat = 8
        
        var body: some View {
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: pillHeight/2)
                            .fill(LinearGradient(
                                colors: [Color(red: 0.6, green: 0.0, blue: 0.0), Color(red: 0.9, green: 0.95, blue: 0.0), Color.green],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(height: pillHeight)
                        
                        // subtle overlay to keep pill "filled" look consistent
                        RoundedRectangle(cornerRadius: pillHeight/2)
                            .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
                            .frame(height: pillHeight)
                        
                        // Dot marker
                        let x = clampedX(for: geo.size.width)
                        Circle()
                            .fill(Color.white)
                            .frame(width: dotSize, height: dotSize)
                            .shadow(color: Color.black.opacity(0.6), radius: 2, x: 0, y: 1)
                            .position(x: x, y: pillHeight/2)
                    }
                }
                .frame(height: pillHeight)
                
                // Percentage and delta aligned under dot marker
                GeometryReader { geo in
                    let x = clampedX(for: geo.size.width)
                    ZStack {
                        // full-width clear background so ZStack fills parent and we can use .position
                        Color.clear
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%.2f%%", mgmtPercent))
                                .font(.subheadline).bold()
                                .foregroundColor(mgmtColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            // Delta to right in smaller font
                            Text(deltaText)
                                .font(.caption2)
                                .foregroundColor(delta >= 0 ? Color.green : Color.red)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .padding(.top, 2)
                        }
                        .fixedSize()                 // keep intrinsic width, do not compress
                        .position(x: x, y: 11)      // center the HStack at the dot's x and mid of the 22pt row
                    }
                }
                .frame(height: 22)
            }
        }
        
        private func clampedX(for totalWidth: CGFloat) -> CGFloat {
            // leave horizontalPadding from edges
            let leftBound = horizontalPadding + dotSize/2
            let rightBound = max(leftBound, totalWidth - horizontalPadding - dotSize/2)
            let raw = totalWidth * CGFloat(ratio)
            return min(max(raw, leftBound), rightBound)
        }
        
        // Option C: show signed absolute percentage-point difference with "pp" suffix (e.g. "+0.71 pp", "-0.61 pp")
        private var deltaText: String {
            if delta == 0 { return "0.00 pp" }
            return String(format: "%+.2f pp", delta)
        }
    }
    
    // Small reusable components (mirrored from Off/Def)
    private struct EfficiencyBar: View {
        let ratio: Double
        let height: CGFloat
        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height/2)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: height/2)
                        .fill(LinearGradient(colors: [.red, .orange, .yellow, .green],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, min(geo.size.width, geo.size.width * ratio)))
                        .animation(.easeInOut(duration: 0.5), value: ratio)
                }
            }
        }
    }
    
    private struct ConsistencyMeter: View {
        let stdDev: Double
        private var norm: Double { max(0, min(1, stdDev / 60.0)) }
        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .yellow, .orange, .red],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * norm)
                }
            }
            .clipShape(Capsule())
        }
    }
    
    private struct Pill: View {
        let text: String
        let bg: Color
        let stroke: Color
        var body: some View {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(bg))
                .overlay(Capsule().stroke(stroke.opacity(0.7), lineWidth: 1))
                .foregroundColor(.white)
        }
    }
    
    // Helper to determine mgmt color (attempt to match existing MgmtColor semantics)
    private func mgmtColor(for pct: Double) -> Color {
        // Reasonable mapping: >75 green, 60-75 yellow, <60 red
        switch pct {
        case let x where x >= 75: return .green
        case let x where x >= 60: return .yellow
        default: return .red
        }
    }
    
    // MARK: - Recent Form + Consistency Row (these were reported missing by compiler)
    private var recentForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            let arrow = formDelta > 0.5 ? "↑" : (formDelta < -0.5 ? "↓" : "→")
            HStack(alignment: .top, spacing: 12) {
                formStatBlock("Last 3", last3Avg)
                formStatBlock("Season", seasonAvg)
                formDeltaBlock(arrow: arrow, delta: formDelta)
            }
            Text("Compares recent 3 weeks to season average for this team.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))
        }
    }
    
    private var consistencyRow: some View {
        HStack {
            HStack(spacing: 8) {
                Text(consistencyDescriptor)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Button { showConsistencyInfo = true } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            Spacer()
            ConsistencyMeter(stdDev: stdDev)
                .frame(width: 110, height: 12)
        }
    }
    
    // MARK: - small stat helpers used by recentForm
    private func statBlock(title: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.2f", value))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func statBlockPercent(title: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.2f%%", value))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formStatBlock(_ name: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.2f", value))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Text(name)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formDeltaBlock(arrow: String, delta: Double) -> some View {
        VStack(spacing: 2) {
            Text("\(arrow) \(String(format: "%+.2f", delta))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(formDeltaColor)
            Text("Delta")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Balance Detail Sheet
private struct BalanceDetailSheet: View {
    let offensePct: Double
    let defensePct: Double
    let balancePct: Double
    let tagline: String
    
    // Use the same shared icon computation so rules match TeamStatExpandedView exactly
    private var icons: (off: String, def: String) {
        let i = EfficiencyIconComputer.computeIcons(off: offensePct, def: defensePct)
        return (i.offIcon, i.defIcon)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.white.opacity(0.15))
                .frame(width: 40, height: 6)
                .padding(.top, 8)
            Text("Full Team Efficiency — Breakdown")
                .font(.headline)
                .foregroundColor(.yellow)
            HStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("\(icons.off) Offense")
                        .font(.subheadline).bold()
                        .foregroundColor(.white)
                    // Use .tint(Color) instead of attempting to pass a LinearGradient (which is not a Color)
                    ProgressView(value: min(max(offensePct/100.0, 0.0), 1.0))
                        .progressViewStyle(LinearProgressViewStyle(tint: Color.red))
                        .frame(height: 10)
                    Text(String(format: "%.2f%% Efficient", offensePct))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
                VStack(spacing: 6) {
                    Text("\(icons.def) Defense")
                        .font(.subheadline).bold()
                        .foregroundColor(.white)
                    // Use a solid Color tint for compatibility with the API
                    ProgressView(value: min(max(defensePct/100.0, 0.0), 1.0))
                        .progressViewStyle(LinearProgressViewStyle(tint: Color.green))
                        .frame(height: 10)
                    Text(String(format: "%.2f%% Efficient", defensePct))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal)
            
            HStack {
                Text("⚖️ Balance")
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: "%.2f%% Imbalance", balancePct))
                    .font(.subheadline).bold()
                    .foregroundColor(balancePct < 5 ? .green : .red)
            }
            .padding(.horizontal)
            
            Text(tagline)
                .font(.caption2)
                .foregroundColor(.yellow)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer(minLength: 8)
        }
        .padding(.bottom, 12)
        .background(Color.black)
    }
}
