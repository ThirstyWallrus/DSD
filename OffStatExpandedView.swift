//
//  OffStatExpandedView.swift
//  DynastyStatDrop
//
//  Uses authoritative matchup.players_points when available; sums starters only when starters present.
//  Falls back to deduped roster.weeklyScores when necessary.
//
//  Updated: Top title + 4 stat bubbles (Grade, OPF, OMPF, OPPW) to match TeamStatExpandedView style.
//  PATCH: Use offense-only grading routine (gradeTeamsOffense) from TeamGradeComponents and ensure
//  each TeamGradeComponents instance is populated with offensive values as required.
//  PATCH: Use SleeperLeagueManager player cache to include started-then-dropped players when computing weekly totals.
//  NEW: Add ManagementPill to lineupEfficiency to mirror TeamStatExpandedView but show offense-only Mgmt%.
//  FIX: Avoid counting full players_points (bench + starters) when matchup.players_points exists but starters list is missing.
//       Instead attempt to reconstruct likely starters greedily from players_points + eligible slot logic (greedy) first,
//       then from roster.weeklyScores, and only fall back to returning players_points when reconstruction fails.
//
//  NOTE: This file replaces the previous approach which sometimes returned the entire players_points map
//  (bench + starters) when starters were not present in the matchup entry. That over-counted OPF in many
//  leagues. The new logic reconstructs starters greedily from players_points (works for started-then-dropped players),
//  using roster/league caches to determine positions. This should correct the OPF mismatch you reported.
//

import SwiftUI

struct OffStatExpandedView: View {
    @EnvironmentObject var appSelection: AppSelection
    // Use the global league manager so we can resolve players not present on current roster.
    @EnvironmentObject var leagueManager: SleeperLeagueManager

    @State private var showConsistencyInfo = false
    // Removed showEfficiencyInfo per request (info icon + popup removed)

    // Show detail sheet for offensive position balance (new: OffensiveBalanceInfoSheet)
    @State private var showOffBalanceDetail = false

    // Offensive positions
    private let offPositions: [String] = ["QB", "RB", "WR", "TE", "K"]

    // Position color mapping
    private var positionColors: [String: Color] {
        [
            "QB": .red,
            "RB": .green,
            "WR": .blue,
            "TE": .yellow,
            "K": Color.purple,
            "DL": .orange,
            "LB": .purple,
            "DB": .pink
        ]
    }

    // MARK: - Team/League/Season State

    private var team: TeamStanding? { appSelection.selectedTeam }
    private var league: LeagueData? { appSelection.selectedLeague }
    private var isAllTime: Bool { appSelection.isAllTimeMode }
    private var aggregate: AggregatedOwnerStats? {
        guard isAllTime, let league, let team else { return nil }
        return league.allTimeOwnerStats?[team.ownerId]
    }

    // MARK: - Grade computation (use TeamGradeComponents & gradeTeams for consistency)
    // Build TeamGradeComponents for teams in current league/season (or use all-time owner aggregates when available).
    // PATCH: Use offense-only composite scoring. Each TeamGradeComponents instance will have pointsFor set to
    // the team's OFFENSIVE Points For and ppw set to offensivePPW to satisfy gradeTeamsOffense requirements.
    private var computedGrade: (grade: String, composite: Double)? {
        guard let lg = league else { return nil }
        let teamsToProcess: [TeamStanding] = {
            if !isAllTime, let season = lg.seasons.first(where: { $0.id == appSelection.selectedSeason }) {
                return season.teams
            }
            return lg.seasons.sorted { $0.id < $1.id }.last?.teams ?? lg.teams
        }()
        var comps: [TeamGradeComponents] = []
        for t in teamsToProcess {
            comps.append(createTeamGradeComponent(for: t))
        }

        // Use offense-specific grading helper
        let graded = gradeTeamsOffense(comps)
        if let team = team, let found = graded.first(where: { $0.0 == team.name }) {
            return (found.1, found.2)
        }
        return nil
    }

    private func createTeamGradeComponent(for t: TeamStanding) -> TeamGradeComponents {
        // Prefer aggregated owner stats in all-time mode
        let aggOwner: AggregatedOwnerStats? = {
            if isAllTime { return league?.allTimeOwnerStats?[t.ownerId] }
            return nil
        }()

        // Offensive-specific values to populate TeamGradeComponents correctly for offense-only grading
        let offPF: Double = {
            if isAllTime {
                return aggOwner?.totalOffensivePointsFor ?? (t.offensivePointsFor ?? 0)
            }
            return t.offensivePointsFor ?? 0
        }()

        let offPPW: Double = {
            if isAllTime {
                return aggOwner?.offensivePPW ?? (t.averageOffensivePPW ?? 0)
            }
            // Use stored averageOffensivePPW when available; fallback to teamPointsPerWeek if missing
            return t.averageOffensivePPW ?? t.teamPointsPerWeek
        }()

        // Overall mgmt — keep existing behavior (season/all-time fallback)
        let pf: Double = {
            if isAllTime { return aggOwner?.totalPointsFor ?? t.pointsFor }
            return t.pointsFor
        }()
        let mpf: Double = {
            if isAllTime { return aggOwner?.totalMaxPointsFor ?? t.maxPointsFor }
            return t.maxPointsFor
        }()
        let mgmt = (mpf > 0) ? (pf / mpf * 100) : (t.managementPercent)

        // Off/Def mgmt (keep previous logic)
        let offMgmt: Double = {
            if isAllTime {
                if let agg = aggOwner, agg.totalMaxOffensivePointsFor > 0 {
                    return (agg.totalOffensivePointsFor / agg.totalMaxOffensivePointsFor) * 100
                }
                return t.offensiveManagementPercent ?? 0
            } else {
                return t.offensiveManagementPercent ?? 0
            }
        }()

        let defMgmt: Double = {
            if isAllTime {
                if let agg = aggOwner, agg.totalMaxDefensivePointsFor > 0 {
                    return (agg.totalDefensivePointsFor / agg.totalMaxDefensivePointsFor) * 100
                }
                return t.defensiveManagementPercent ?? 0
            } else {
                return t.defensiveManagementPercent ?? 0
            }
        }()

        // Position averages (fallback to 0)
        let qb = (t.positionAverages?[PositionNormalizer.normalize("QB")] ?? 0)
        let rb = (t.positionAverages?[PositionNormalizer.normalize("RB")] ?? 0)
        let wr = (t.positionAverages?[PositionNormalizer.normalize("WR")] ?? 0)
        let te = (t.positionAverages?[PositionNormalizer.normalize("TE")] ?? 0)
        let k  = (t.positionAverages?[PositionNormalizer.normalize("K")]  ?? 0)
        let dl = (t.positionAverages?[PositionNormalizer.normalize("DL")] ?? 0)
        let lb = (t.positionAverages?[PositionNormalizer.normalize("LB")] ?? 0)
        let db = (t.positionAverages?[PositionNormalizer.normalize("DB")] ?? 0)

        let (w,l,ties) = TeamGradeComponents.parseRecord(t.winLossRecord)
        let recordPct = (w + l + ties) > 0 ? Double(w) / Double(max(1, w + l + ties)) : 0.0

        // IMPORTANT: For offense grading, set pointsFor = offensive points for and ppw = offensivePPW
        return TeamGradeComponents(
            pointsFor: offPF,
            ppw: offPPW,
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
    }

    // MARK: - Weeks to Include (Exclude Current Week if Incomplete)

    private var validWeeks: [Int] {
        guard let league, let team else { return [] }
        // For season mode, use the selected season
        if !isAllTime, let season = league.seasons.first(where: { $0.id == appSelection.selectedSeason }) {
            let allWeeks = season.matchupsByWeek?.keys.sorted() ?? []
            if let currentWeek = allWeeks.max(), allWeeks.count > 1 {
                return allWeeks.filter { $0 != currentWeek }
            }
            return allWeeks
        }
        // For all time mode, use the latest season's weeks (for continuity in charts)
        if isAllTime {
            let latest = league.seasons.sorted { $0.id < $1.id }.last
            let allWeeks = latest?.matchupsByWeek?.keys.sorted() ?? []
            if let currentWeek = allWeeks.max(), allWeeks.count > 1 {
                return allWeeks.filter { $0 != currentWeek }
            }
            return allWeeks
        }
        return []
    }

    // MARK: - Authoritative week points helper
    private func authoritativePointsForWeek(team: TeamStanding, week: Int) -> [String: Double] {
        // 1) players_points from matchup entry if available (prefer starters only)
        if let league = league {
            let season = (!isAllTime)
            ? league.seasons.first(where: { $0.id == appSelection.selectedSeason })
            : league.seasons.sorted { $0.id < $1.id }.last
            if let season {
                if let entries = season.matchupsByWeek?[week],
                   let rosterIdInt = Int(team.id),
                   let myEntry = entries.first(where: { $0.roster_id == rosterIdInt }),
                   let playersPoints = myEntry.players_points, !playersPoints.isEmpty {
                    if let starters = myEntry.starters, !starters.isEmpty {
                        return reconstructFromStarters(starters: starters, playersPoints: playersPoints)
                    } else {
                        return reconstructWithoutStarters(team: team, playersPoints: playersPoints, myEntry: myEntry, week: week)
                    }
                }
            }
        }
        // 2) fallback: deduplicated roster.weeklyScores
        return fallbackFromRoster(team: team, week: week)
    }

    private func reconstructFromStarters(starters: [String], playersPoints: [String: Double]) -> [String: Double] {
        var map: [String: Double] = [:]
        for pid in starters {
            map[pid] = playersPoints[pid] ?? 0.0
        }
        return map
    }

    private func reconstructWithoutStarters(team: TeamStanding, playersPoints: [String: Double], myEntry: MatchupEntry, week: Int) -> [String: Double] {
        // IMPORTANT PATCH:
        // When players_points exists but starters list is missing, do NOT blindly return all players_points
        // (bench + starters). That overcounts OPF. Instead:
        //  1) Attempt to reconstruct starters greedily using players_points with position resolution
        //     (this handles started-then-dropped players since players_points contains the actual starters' ids).
        //  2) If greedy reconstruction from players_points fails (e.g., cannot resolve eligible picks),
        //     fall back to reconstructing from roster.weeklyScores (legacy).
        //  3) Only if both reconstructions fail, return the raw playersPoints as last resort.
        //
        // Greedy reconstruction from players_points:
        struct Candidate {
            let playerId: String
            let basePos: String
            let fantasy: [String]
            let points: Double
        }

        var candidates: [Candidate] = []
        for (pid, pts) in playersPoints {
            var basePos = "UNK"
            var alt: [String] = []
            if let p = team.roster.first(where: { $0.id == pid }) {
                basePos = p.position
                alt = p.altPositions ?? []
            } else if let raw = leagueManager.playerCache?[pid] ?? leagueManager.allPlayers[pid] {
                // raw likely has `position` optional
                basePos = raw.position ?? "WR"
                // no altPositions in raw cache typically
            } else {
                // Unknown player — assume WR fallback to avoid dropping offensive points entirely
                basePos = "WR"
            }
            candidates.append(Candidate(playerId: pid, basePos: basePos, fantasy: alt, points: pts))
        }

        // Determine lineup slots for greedy assignment (infer if missing)
        let lineupConfig = team.lineupConfig ?? inferredLineupConfig(from: team.roster)
        let slots = expandSlots(lineupConfig: lineupConfig)
        var usedIds = Set<String>()
        var selected: [String: Double] = [:]

        if !slots.isEmpty && !candidates.isEmpty {
            // Greedy selection: for each slot pick highest-scoring eligible candidate not already used
            for slot in slots {
                let allowed = allowedPositions(for: slot)
                let pick = candidates
                    .filter { !usedIds.contains($0.playerId) && isEligible(basePos: $0.basePos, fantasy: $0.fantasy, allowed: allowed) }
                    .max(by: { $0.points < $1.points })
                if let p = pick {
                    usedIds.insert(p.playerId)
                    selected[p.playerId] = p.points
                }
            }
        }

        if !selected.isEmpty {
            return selected
        }

        // Fallback reconstruction using roster.weeklyScores (legacy behavior) — prefer matchup_id when available
        var reconstructedFromRoster: [String: Double] = [:]
        let preferredMid = myEntry.matchup_id
        for player in team.roster {
            let scores = player.weeklyScores.filter { $0.week == week }
            if scores.isEmpty { continue }
            if let matched = scores.first(where: { $0.matchup_id == preferredMid }) {
                reconstructedFromRoster[player.id] = matched.points_half_ppr ?? matched.points
            } else if let best = scores.max(by: { ($0.points_half_ppr ?? $0.points) < ($1.points_half_ppr ?? $1.points) }) {
                reconstructedFromRoster[player.id] = best.points_half_ppr ?? best.points
            }
        }

        if !reconstructedFromRoster.isEmpty {
            return reconstructedFromRoster
        } else {
            // as a last resort return playersPoints (preserve information)
            return playersPoints.mapValues { $0 }
        }
    }

    private func fallbackFromRoster(team: TeamStanding, week: Int) -> [String: Double] {
        var result: [String: Double] = [:]
        var preferredMatchupId: Int? = nil
        if let league = league {
            let season = (!isAllTime)
            ? league.seasons.first(where: { $0.id == appSelection.selectedSeason })
            : league.seasons.sorted { $0.id < $1.id }.last
            if let season, let entries = season.matchupsByWeek?[week], let rosterIdInt = Int(team.id) {
                preferredMatchupId = entries.first(where: { $0.roster_id == rosterIdInt })?.matchup_id
            }
        }
        for player in team.roster {
            let scores = player.weeklyScores.filter { $0.week == week }
            if scores.isEmpty { continue }
            if let mid = preferredMatchupId, let matched = scores.first(where: { $0.matchup_id == mid }) {
                result[player.id] = matched.points_half_ppr ?? matched.points
            } else {
                if let best = scores.max(by: { ($0.points_half_ppr ?? $0.points) < ($1.points_half_ppr ?? $1.points) }) {
                    result[player.id] = best.points_half_ppr ?? best.points
                }
            }
        }
        return result
    }

    // MARK: - Stacked Bar Chart Data

    private var stackedBarWeekData: [StackedBarWeeklyChart.WeekBarData] {
        guard let team else { return [] }
        let sortedWeeks = validWeeks
        return sortedWeeks.map { week in
            let playerPoints = authoritativePointsForWeek(team: team, week: week)
            var posSums: [String: Double] = [:]
            for (pid, pts) in playerPoints {
                // Prefer position from team roster if present
                if let player = team.roster.first(where: { $0.id == pid }) {
                    let norm = PositionNormalizer.normalize(player.position)
                    if ["QB","RB","WR","TE","K"].contains(norm) {
                        posSums[norm, default: 0.0] += pts
                    }
                } else {
                    // Player not on current roster (likely started then dropped). Try to resolve via global player caches.
                    if let raw = leagueManager.playerCache?[pid] ?? leagueManager.allPlayers[pid] {
                        let norm = PositionNormalizer.normalize(raw.position ?? "WR")
                        if ["QB","RB","WR","TE","K"].contains(norm) {
                            posSums[norm, default: 0.0] += pts
                        } else {
                            // started player had defensive position — ignore for offense chart
                        }
                    } else {
                        // Fallback: couldn't resolve position; to preserve chart totals attribute to conservative bucket
                        posSums["WR", default: 0.0] += pts
                    }
                }
            }
            // Build segments with explicit type to avoid ambiguous/failed casts
            let segments: [StackedBarWeeklyChart.WeekBarData.Segment] = offPositions.map { pos in
                let norm = PositionNormalizer.normalize(pos)
                return StackedBarWeeklyChart.WeekBarData.Segment(id: pos, position: norm, value: posSums[norm] ?? 0)
            }
            return StackedBarWeeklyChart.WeekBarData(id: week, segments: segments)
        }
    }

    // Helper: check if a PlayerWeeklyScore's player matches the target normalized position
    private func matchesNormalizedPosition(_ score: PlayerWeeklyScore, pos: String) -> Bool {
        guard let team else { return false }
        if let player = team.roster.first(where: { $0.id == score.player_id }) {
            return PositionNormalizer.normalize(player.position) == PositionNormalizer.normalize(pos)
        }
        // Try global caches (covers started players later dropped from roster)
        if let raw = leagueManager.playerCache?[score.player_id] ?? leagueManager.allPlayers[score.player_id] {
            return PositionNormalizer.normalize(raw.position ?? "") == PositionNormalizer.normalize(pos)
        }
        return false
    }

    private var sideWeeklyPoints: [Double] {
        stackedBarWeekData.map { $0.total }
    }

    // --- FIX: Use non-zero completed weeks for averages instead of naive week count (e.g., 18) ---
    private var sideWeeklyPointsNonZero: [Double] {
        let nonZero = sideWeeklyPoints.filter { $0 > 0.0 }
        // Fallback: if nothing found in stacked data, use team's recorded weeklyActualLineupPoints if available
        if nonZero.isEmpty, let team = team, let weekly = team.weeklyActualLineupPoints {
            let vals = weekly.keys.sorted().map { weekly[$0] ?? 0.0 }.filter { $0 > 0.0 }
            if !vals.isEmpty { return vals }
        }
        return nonZero
    }

    private var weeksPlayed: Int { sideWeeklyPointsNonZero.count }
    private var last3Avg: Double {
        guard weeksPlayed > 0 else { return 0 }
        let recent = sideWeeklyPointsNonZero.suffix(3)
        return recent.reduce(0,+) / Double(min(3, recent.count))
    }

    // seasonAvg is computed as average of the authoritative weekly totals (non-zero completed weeks)
    private var seasonAvg: Double {
        // FIX: Prefer authoritative stored average when present to match other views and persisted values.
        // Many parts of the app and persisted imports use TeamStanding.averageOffensivePPW as the canonical value.
        // Use stored value first (keeps continuity), then all-time aggregate, then computed weekly average as fallback.
        if let t = team, let stored = t.averageOffensivePPW, stored > 0 {
            return stored
        }
        if let agg = aggregate { return agg.offensivePPW }
        if weeksPlayed > 0 {
            return sideWeeklyPointsNonZero.reduce(0, +) / Double(weeksPlayed)
        }
        return 0
    }
    private var formDelta: Double { last3Avg - seasonAvg }
    private var formDeltaColor: Color {
        if formDelta > 2 { return .green }
        if formDelta < -2 { return .red }
        return .yellow
    }

    // MARK: - Offensive Points and Management %

    // Recompute OPF from the exact same weekly totals used to compute OPPW.
    // This prevents mismatch caused by using team.offensivePointsFor while seasonAvg uses stackedBarWeekData.
    // NOTE: To maintain continuity with other views & persisted values we prefer authoritative stored fields
    // (team.offensivePointsFor, team.maxOffensivePointsFor) when available. Only when those are missing
    // do we fall back to a recomputed sum from stackedBarWeekData. This prevents divergence (e.g. OPF shown
    // in OffStat differing from Team view / imported Sleeper values) while still allowing recompute when
    // stored fields are not present.
    private var sidePointsComputed: Double {
        let sum = stackedBarWeekData.map { $0.total }.reduce(0, +)
        if sum > 0 { return sum }
        if let agg = aggregate { return agg.totalOffensivePointsFor }
        return team?.offensivePointsFor ?? 0
    }

    // Expose sidePoints (preferred to show authoritative stored sum; aggregate wins in all-time)
    private var sidePoints: Double {
        if let agg = aggregate { return agg.totalOffensivePointsFor }
        // Prefer TeamStanding.offensivePointsFor when present to keep continuity with other views / persisted data.
        if let t = team, let stored = t.offensivePointsFor, stored > 0 {
            return stored
        }
        return sidePointsComputed
    }

    private var sideMaxPoints: Double {
        if let agg = aggregate { return agg.totalMaxOffensivePointsFor }
        if let t = team, let stored = t.maxOffensivePointsFor, stored > 0 {
            return stored
        }
        return team?.maxOffensivePointsFor ?? 0
    }
    private var managementPercent: Double {
        guard sideMaxPoints > 0 else { return 0 }
        return (sidePoints / sideMaxPoints) * 100
    }

    // --- NEW: Prior Management % helpers (mirror TeamStatExpandedView behavior)
    // Compute latest valid week's actual total (if any)
    private var latestValidWeekTotal: Double? {
        guard let team else { return nil }
        let pairs = zip(validWeeks, stackedBarWeekData)
        if let last = pairs.reversed().first(where: { $0.1.total > 0 }) {
            return last.1.total
        }
        if let weekly = team.weeklyActualLineupPoints {
            let last = weekly.keys.sorted().reversed().first(where: { (weekly[$0] ?? 0) > 0 })
            if let wk = last { return weekly[wk] }
        }
        return nil
    }

    // Helper to find the week number corresponding to latestValidWeekTotal (if any)
    private func findLatestValidWeek() -> Int? {
        guard let team else { return nil }
        let pairs = zip(validWeeks, stackedBarWeekData)
        if let last = pairs.reversed().first(where: { $0.1.total > 0 }) {
            return last.0
        }
        if let weekly = team.weeklyActualLineupPoints {
            let lastKey = weekly.keys.sorted().reversed().first(where: { (weekly[$0] ?? 0) > 0 })
            if let wk = lastKey { return wk }
        }
        return nil
    }

    // New helpers to compute a week's optimal (max) points for offense (mirrors other views)
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
    // Exclude the most recent week from BOTH numerator (points) and denominator (season max) when possible.
    private var priorManagementPercent: Double {
        guard let last = latestValidWeekTotal else { return 0 }
        guard sideMaxPoints > 0 else { return 0 }
        let priorPoints = max(0, sidePoints - last)
        guard let lastWeek = findLatestValidWeek() else {
            // can't find week index — fallback to original behavior
            return (priorPoints / sideMaxPoints) * 100
        }
        if let lastWeekMax = computeWeekMax(for: lastWeek), lastWeekMax > 0 {
            let priorMax = sideMaxPoints - lastWeekMax
            if priorMax > 0 {
                return (priorPoints / priorMax) * 100
            } else {
                return (priorPoints / sideMaxPoints) * 100
            }
        } else {
            return (priorPoints / sideMaxPoints) * 100
        }
    }

    private var managementDelta: Double {
        managementPercent - priorManagementPercent
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
            if agg.offensiveManagementPercent >= 75 { arr.append("Efficient Usage") }
            if stdDev < 15 && weeksPlayed >= 4 { arr.append("Reliable Output") }
            if arr.isEmpty { arr.append("Developing Unit") }
            return arr
        }
        var arr: [String] = []
        if managementPercent >= 75 { arr.append("Efficient Usage") }
        if stdDev < 15 && weeksPlayed >= 4 { arr.append("Reliable Output") }
        if arr.isEmpty { arr.append("Developing Unit") }
        return arr
    }
    private var weaknesses: [String] {
        if let agg = aggregate {
            var arr: [String] = []
            if agg.offensiveManagementPercent < 55 { arr.append("Usage Inefficiency") }
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

    // MARK: - UI: Top Title + 4 stat bubbles (Grade, OPF, OMPF, OPPW)

    /// A generic stat bubble builder: identical to TeamStatExpandedView style for consistency.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Title + bubble row (grade, OPF, OMPF, OPPW)
            VStack(spacing: 8) {
                // Title uses selected team name like TeamStatExpandedView
                let viewerName: String = {
                    if let team = team {
                        return team.name
                    }
                    if let uname = appSelection.currentUsername, !uname.isEmpty { return uname }
                    return appSelection.userTeam.isEmpty ? "Team" : appSelection.userTeam
                }()
                Text("\(viewerName)'s Offense Drop")
                    .font(.custom("Phatt", size: 20))
                    .bold()
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                GeometryReader { geo in
                    let horizontalPadding: CGFloat = 8
                    let spacing: CGFloat = 10
                    let itemCount: CGFloat = 4 // Grade, OPF, OMPF, OPPW
                    let available = max(0, geo.size.width - horizontalPadding * 2 - (spacing * (itemCount - 1)))
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

                        // 2) OPF (Offensive Points For) - prefer authoritative stored team value for continuity
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            Text(String(format: "%.2f", sidePoints))
                                .font(.system(size: bubbleSize * 0.30, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78)
                        } caption: {
                            Text("OPF")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        // 3) OMPF (Offensive Max Points For)
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            Text(String(format: "%.2f", sideMaxPoints))
                                .font(.system(size: bubbleSize * 0.30, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78)
                        } caption: {
                            Text("OMPF")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        // 4) OPPW (Offensive PPW)
                        // Uses seasonAvg computed from non-zero completed weeks derived from the same weekly totals.
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            Text(String(format: "%.2f", seasonAvg))
                                .font(.system(size: bubbleSize * 0.36, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                                .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78, alignment: .center)
                        } caption: {
                            Text("OPPW")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .frame(width: geo.size.width, height: bubbleSize + 26, alignment: .center)
                }
                .frame(height: 96)
            }

            sectionHeader("Offensive Weekly Trend")
            StackedBarWeeklyChart(
                weekBars: stackedBarWeekData,
                positionColors: positionColors,
                showPositions: Set(offPositions),
                gridIncrement: 25,
                barSpacing: 4,
                tooltipFont: .caption2.bold(),
                showWeekLabels: true,
                aggregateToOffDef: false,
                showAggregateLegend: false,
                showOffensePositionsLegend: true,
                showDefensePositionsLegend: false
            )
            .frame(height: 140)

            sectionHeader("Lineup Efficiency")
            lineupEfficiency

            // NEW: Offensive Efficiency Spotlight (position-level Mgmt% gauges)
            sectionHeader("Offensive Efficiency Spotlight")
            offensiveEfficiencySpotlight

            sectionHeader("Recent Form")
            recentForm

            sectionHeader("Consistency Score")
            consistencyRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .sheet(isPresented: $showConsistencyInfo) {
            ConsistencyInfoSheet(stdDev: stdDev, descriptor: consistencyDescriptor)
                .presentationDetents([PresentationDetent.fraction(0.40)])
        }
        // Present the OffensiveBalanceInfoSheet when user taps the center Balance element
        .sheet(isPresented: $showOffBalanceDetail) {
            // Use OffensiveBalanceInfoSheet (the explanatory popup you added to the project)
            // NOTE: the OffensiveBalanceInfoSheet initializer expects the label 'balancedPercent'
            // and an optional 'tagline' parameter. Provide the tagline for better UX.
            OffensiveBalanceInfoSheet(
                positionPercents: positionMgmtPercents,
                balancedPercent: positionBalancePercent,
                tagline: generatePositionBalanceTagline()
            )
            .presentationDetents([PresentationDetent.fraction(0.40)])
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.yellow)
            .padding(.top, 4)
    }

    // REPLACED: The old statBlock + EfficiencyBar combo is now replaced by a ManagementPill identical to TeamStatExpandedView,
    // but showing the offense-only Mgmt% (managementPercent), with delta computed by priorManagementPercent.
    private var lineupEfficiency: some View {
        VStack(alignment: .leading, spacing: 10) {
            ManagementPill(
                ratio: max(0.0, min(1.0, managementPercent / 100.0)),
                mgmtPercent: managementPercent,
                delta: managementDelta,
                mgmtColor: mgmtColor(for: managementPercent)
            )
            .padding(.vertical, 2)

            // Removed info button per request (no popup for Mgmt%).
        }
    }

    // MARK: - Offensive Efficiency Spotlight helpers

    // Returns per-position mgmt% using DSDStatsService (season vs all-time)
    private var positionMgmtPercents: [String: Double] {
        guard let team = team else { return [:] }
        var dict: [String: Double] = [:]
        for pos in offPositions {
            let mgmt: Double
            if isAllTime {
                if let agg = aggregate {
                    mgmt = DSDStatsService.shared.managementPercentForPosition(allTimeAgg: agg, position: pos)
                } else {
                    // Fallback to TeamStanding field if present
                    mgmt = team.positionAverages?[PositionNormalizer.normalize(pos)] ?? 0
                }
            } else {
                mgmt = DSDStatsService.shared.managementPercentForPosition(
                    team: team,
                    position: pos,
                    league: league,
                    selectedSeason: appSelection.selectedSeason,
                    leagueManager: leagueManager
                )
            }
            dict[pos] = mgmt
        }
        return dict
    }

    // Compute coefficient-of-variation based balance percent for the five offense positions.
    // balancePercent = (stdDev(mgmtPercents) / mean(mgmtPercents)) * 100
    // Lower = more balanced. We clamp and handle zero mean gracefully.
    private var positionBalancePercent: Double {
        let vals = offPositions.compactMap { positionMgmtPercents[$0] }
        guard !vals.isEmpty else { return 0 }
        let mean = vals.reduce(0, +) / Double(vals.count)
        guard mean > 0 else { return 0 }
        let variance = vals.reduce(0) { $0 + pow($1 - mean, 2) } / Double(vals.count)
        let sd = sqrt(variance)
        return (sd / mean) * 100
    }

    // Tagline generator for the position balance
    private func generatePositionBalanceTagline() -> String {
        let balance = positionBalancePercent
        if balance < 8 { return "Nicely balanced offense — usage is well distributed." }
        if balance < 16 { return "Moderate positional skew — a couple spots are carrying the load." }
        // Determine heavy positions (significantly above mean)
        let mgmts = positionMgmtPercents
        let mean = mgmts.values.reduce(0, +) / Double(max(1, mgmts.count))
        let heavy = mgmts.filter { $0.value > mean + 10 }.map { $0.key }
        if !heavy.isEmpty {
            return "Skewed towards: \(heavy.joined(separator: ", ")). Consider diversifying."
        }
        return "Unbalanced — offense relies heavily on specific positions."
    }

    // View: Offensive Efficiency Spotlight
    // REWORKED LAYOUT:
    // - 3 equal columns
    // - Top row: QB (left), RB (center), WR (right)
    // - Bottom row: TE (left, under QB), Balance (center, under RB), K (right, under WR)
    // This will ensure RB and Balance are vertically aligned/centered and QB/TE align left, WR/K align right.
    private var offensiveEfficiencySpotlight: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let spacing: CGFloat = 12
            let columnWidth = max(80, (totalWidth - spacing * 2) / 3)

            HStack(alignment: .top, spacing: spacing) {
                // LEFT COLUMN: QB (top) / TE (bottom)
                VStack(spacing: 12) {
                    positionGauge(position: "QB", percent: positionMgmtPercents["QB"] ?? 0)
                    Spacer()
                    positionGauge(position: "TE", percent: positionMgmtPercents["TE"] ?? 0)
                }
                .frame(width: columnWidth, alignment: .center)

                // CENTER COLUMN: RB (top) / Balance (bottom) — Balance centered under RB
                VStack(spacing: 12) {
                    positionGauge(position: "RB", percent: positionMgmtPercents["RB"] ?? 0)
                    Spacer()
                    VStack(spacing: 6) {
                        Text("⚖️ \(String(format: "%.2f%%", positionBalancePercent))")
                            .font(.subheadline).bold()
                            .foregroundColor(positionBalancePercent < 8 ? .green : (positionBalancePercent < 16 ? .yellow : .red))
                            .accessibilityLabel("Offensive balance")
                            .accessibilityValue(String(format: "%.2f percent balance score", positionBalancePercent))
                        Text(generatePositionBalanceTagline())
                            .font(.caption2)
                            .foregroundColor(.yellow)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: columnWidth * 0.95)
                    }
                    // Make the balance area tappable to show the detailed OffensiveBalanceInfoSheet
                    .onTapGesture {
                        showOffBalanceDetail = true
                    }
                }
                .frame(width: columnWidth, alignment: .center)

                // RIGHT COLUMN: WR (top) / K (bottom)
                VStack(spacing: 12) {
                    positionGauge(position: "WR", percent: positionMgmtPercents["WR"] ?? 0)
                    Spacer()
                    positionGauge(position: "K", percent: positionMgmtPercents["K"] ?? 0)
                }
                .frame(width: columnWidth, alignment: .center)
            }
            .frame(width: totalWidth, height: geo.size.height)
        }
        // Provide a reasonable fixed height that matches previous two-row visual density.
        .frame(height: 170)
        .padding(.vertical, 4)
    }

    // Single position gauge builder (matches TeamStatExpandedView gauge style exactly)
    @ViewBuilder
    private func positionGauge(position: String, percent: Double) -> some View {
        VStack(spacing: 6) {
            Gauge(value: max(0.0, min(1.0, percent/100.0))) {
                EmptyView()
            } currentValueLabel: {
                Text(String(format: "%.2f%%", percent))
                    .font(.caption2).bold()
                    .foregroundColor(.white)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [Color(red: 0.7, green: 0.0, blue: 0.0), Color(red: 0.0, green: 1.0, blue: 0.0)]))
            .frame(width: 56, height: 56)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(position) Usage Efficiency")
            .accessibilityValue(String(format: "%.2f percent", percent))

            // Caption shows position + small color dot
            HStack(spacing: 6) {
                Circle().fill(positionColors[position] ?? .white).frame(width: 8, height: 8)
                Text(position)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: 90)
    }

    // MARK: - Remaining UI (recentForm, consistencyRow, small helpers)

    private var recentForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            let arrow = formDelta > 0.5 ? "↑" : (formDelta < -0.5 ? "↓" : "→")
            HStack(alignment: .top, spacing: 12) {
                formStatBlock("Last 3", last3Avg)
                formStatBlock("Season", seasonAvg)
                formDeltaBlock(arrow: arrow, delta: formDelta)
            }
            Text("Compares recent 3 weeks to season average for this unit.")
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
            Text(String(format: "%.1f%%", value))
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

    // Small components (copied/consistent with TeamStatExpandedView)

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

    // Reuse existing EfficiencyBar (kept for consistency but not used in lineupEfficiency anymore)
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

    // MANAGEMENT PILL: closely matches TeamStatExpandedView's pill but applied to offense-only mgmt%
    private struct ManagementPill: View {
        let ratio: Double       // 0.0 - 1.0
        let mgmtPercent: Double // 0-100
        let delta: Double       // mgmt change since prior week (percentage points)
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

    // Helper to determine mgmt color (attempt to match existing MgmtColor semantics)
    private func mgmtColor(for pct: Double) -> Color {
        // Reasonable mapping: >75 green, 60-75 yellow, <60 red
        switch pct {
        case let x where x >= 75: return .green
        case let x where x >= 60: return .yellow
        default: return .red
        }
    }
}
