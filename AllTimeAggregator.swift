//
//  AllTimeAggregator.swift
//  DynastyStatDrop
//
//  Aggregates multi-season stats per current franchise (ownerId).
//
//  NOTES:
//  - Populates both aggregated H2H summary stats (headToHeadVs) and a per-opponent
//    chronological list of H2H match details (headToHeadDetails).
//  - Deduplicates matchup processing by matchupId+week so each pairing/week is counted once.
//  - Uses opponent lineupConfig for opponent max calculation.
//  - Adds champion recompute helpers and debug logging hooks.
//
//  CHANGES IN THIS VERSION (summary):
//  - Removed duplicated function blocks that caused "invalid redeclaration" compile errors.
//  - Ensured helper functions are declared exactly once and in sensible order.
//  - Added computeSeasonChampion (used by recomputeAllChampionships).
//  - Ensured allPlayoffMatchupsForOwner exists and is used by buildAllTime.
//  - Normalized position handling via PositionNormalizer and SlotPositionAssigner usage where appropriate.
//  - Conservative/fault-tolerant computeMaxForEntry implementation to avoid under-counting max totals.
//  - Kept all public APIs & types unchanged to preserve app continuity.
//
//  If you'd like me to instead apply a smaller targeted patch (e.g., only remove duplicates)
//  or to run through specific lines that changed, tell me and I'll proceed carefully.
//

import Foundation

@MainActor
struct AllTimeAggregator {

    // MARK: - Config / Position sets

    private static let offensiveFlexSlots: Set<String> = [
        "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE",
        "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX"
    ]

    static let allStatPositions: [String] = ["QB", "RB", "WR", "TE", "K", "DL", "LB", "DB"]
    static let offensivePositions: Set<String> = ["QB", "RB", "WR", "TE", "K"]
    static let defensivePositions: Set<String> = ["DL", "LB", "DB"]

    // MARK: - Public Entry

    static func buildAllTime(for league: LeagueData, playerCache: [String: RawSleeperPlayer]) -> LeagueData {
        var copy = league
        let currentIds = league.currentSeasonOwnerIds
        guard !currentIds.isEmpty else {
            copy.allTimeOwnerStats = [:]
            return copy
        }

        var result: [String: AggregatedOwnerStats] = [:]
        for ownerId in currentIds {
            let allPlayoffMatchups = allPlayoffMatchupsForOwner(ownerId: ownerId, league: league)
            if let agg = aggregate(ownerId: ownerId, league: league, currentIds: currentIds, allPlayoffMatchups: allPlayoffMatchups, playerCache: playerCache) {
                result[ownerId] = agg
            }
        }
        copy.allTimeOwnerStats = result
        return copy
    }

    // MARK: - Core aggregation (regular season)

    private static func aggregate(
        ownerId: String,
        league: LeagueData,
        currentIds: [String],
        allPlayoffMatchups: [SleeperMatchup],
        playerCache: [String: RawSleeperPlayer]
    ) -> AggregatedOwnerStats? {
        let seasons = league.seasons.sorted { $0.id < $1.id }
        var teamsPerSeason: [(String, TeamStanding, Int)] = []
        for s in seasons {
            if let t = s.teams.first(where: { $0.ownerId == ownerId }) {
                teamsPerSeason.append((s.id, t, s.playoffStartWeek ?? 14))
            }
        }
        guard !teamsPerSeason.isEmpty else { return nil }

        let latestDisplayName = teamsPerSeason.last?.1.name ?? "Team"

        var totalPF = 0.0, totalMaxPF = 0.0
        var totalOffPF = 0.0, totalMaxOffPF = 0.0
        var totalDefPF = 0.0, totalMaxDefPF = 0.0
        var totalPSA = 0.0

        var championships = 0
        if let computed = league.computedChampionships {
            championships = computed[ownerId] ?? 0
        }

        var wins = 0, losses = 0, ties = 0

        var posTotals: [String: Double] = [:]
        var posStarts: [String: Int] = [:]
        var distinctWeeks: Set<String> = []

        var totalWaiverMoves = 0
        var totalFAAB = 0.0
        var totalTrades = 0

        var actualPosCounts: [String: Int] = [:]
        var actualWeeks = 0

        var headToHead: [String: H2HStats] = [:]
        var headToHeadDetails: [String: [H2HMatchDetail]] = [:]
        let currentIdsSet = Set(currentIds)

        for (seasonId, team, playoffStart) in teamsPerSeason {
            guard let season = seasons.first(where: { $0.id == seasonId }) else { continue }

            // Head-to-head aggregation vs current owners
            for oppTeam in season.teams where oppTeam.ownerId != ownerId && currentIdsSet.contains(oppTeam.ownerId) {
                guard let uRid = Int(team.id), let oRid = Int(oppTeam.id) else { continue }

                let relevant = (season.matchups ?? []).filter { m in m.rosterId == uRid || m.rosterId == oRid }
                var grouped: [String: [SleeperMatchup]] = [:]
                for m in relevant {
                    let wk = m.week ?? inferWeekForMatchup(matchupId: m.matchupId, rosterId: nil, season: season) ?? -999
                    let key = "\(m.matchupId):\(wk)"
                    grouped[key, default: []].append(m)
                }

                func processPair(_ a: SleeperMatchup, _ b: SleeperMatchup) {
                    guard (a.rosterId == uRid && b.rosterId == oRid) || (a.rosterId == oRid && b.rosterId == uRid) else { return }
                    let uEntryPair = (a.rosterId == uRid) ? a : b
                    let oEntryPair = (a.rosterId == oRid) ? a : b
                    let uPts = uEntryPair.points
                    let oPts = oEntryPair.points
                    if uPts == 0 && oPts == 0 { return }

                    var week = uEntryPair.week ?? oEntryPair.week
                    if week == nil {
                        week = inferWeekForMatchup(matchupId: uEntryPair.matchupId, rosterId: nil, season: season)
                    }
                    guard let wk = week else { return }

                    let weekMatchups = season.matchupsByWeek?[wk] ?? []
                    guard let uEntry2 = weekMatchups.first(where: { $0.roster_id == uRid }),
                          let oEntry2 = weekMatchups.first(where: { $0.roster_id == oRid }) else { return }

                    let uMax = computeMaxForEntry(entry: uEntry2, lineupConfig: team.lineupConfig ?? [:], playerCache: playerCache, teamRoster: team.roster, week: wk).total
                    let oMax = computeMaxForEntry(entry: oEntry2, lineupConfig: oppTeam.lineupConfig ?? team.lineupConfig ?? [:], playerCache: playerCache, teamRoster: oppTeam.roster, week: wk).total

                    let uMgmt = uMax > 0 ? (uPts / uMax) * 100 : 0.0
                    let oMgmt = oMax > 0 ? (oPts / oMax) * 100 : 0.0

                    var curr = headToHead[oppTeam.ownerId] ?? H2HStats(wins: 0, losses: 0, ties: 0, pointsFor: 0, pointsAgainst: 0, games: 0, sumMgmtFor: 0.0, sumMgmtAgainst: 0.0)
                    curr = H2HStats(
                        wins: curr.wins,
                        losses: curr.losses,
                        ties: curr.ties,
                        pointsFor: curr.pointsFor + uPts,
                        pointsAgainst: curr.pointsAgainst + oPts,
                        games: curr.games + 1,
                        sumMgmtFor: curr.sumMgmtFor + uMgmt,
                        sumMgmtAgainst: curr.sumMgmtAgainst + oMgmt
                    )
                    if uPts > oPts {
                        curr = H2HStats(wins: curr.wins + 1, losses: curr.losses, ties: curr.ties, pointsFor: curr.pointsFor, pointsAgainst: curr.pointsAgainst, games: curr.games, sumMgmtFor: curr.sumMgmtFor, sumMgmtAgainst: curr.sumMgmtAgainst)
                    } else if uPts < oPts {
                        curr = H2HStats(wins: curr.wins, losses: curr.losses + 1, ties: curr.ties, pointsFor: curr.pointsFor, pointsAgainst: curr.pointsAgainst, games: curr.games, sumMgmtFor: curr.sumMgmtFor, sumMgmtAgainst: curr.sumMgmtAgainst)
                    }
                    headToHead[oppTeam.ownerId] = curr

                    let result: String = {
                        if uPts > oPts { return "W" }
                        if uPts < oPts { return "L" }
                        return "T"
                    }()

                    let detail = H2HMatchDetail(
                        seasonId: seasonId,
                        week: wk,
                        matchupId: uEntryPair.matchupId,
                        userRosterId: uRid,
                        oppRosterId: oRid,
                        userPoints: uPts,
                        oppPoints: oPts,
                        userMax: uMax,
                        oppMax: oMax,
                        userMgmtPct: uMgmt,
                        oppMgmtPct: oMgmt,
                        result: result
                    )
                    var arr = headToHeadDetails[oppTeam.ownerId] ?? []
                    arr.append(detail)
                    headToHeadDetails[oppTeam.ownerId] = arr
                }

                for (_, group) in grouped.sorted(by: { $0.key < $1.key }) {
                    if group.count == 2 {
                        processPair(group[0], group[1])
                    } else if group.count > 2 {
                        let sorted = group.sorted { (a, b) -> Bool in
                            let aw = a.week ?? 0
                            let bw = b.week ?? 0
                            if aw != bw { return aw < bw }
                            return a.rosterId < b.rosterId
                        }
                        var i = 0
                        while i + 1 < sorted.count {
                            processPair(sorted[i], sorted[i+1])
                            i += 2
                        }
                    } else {
                        continue
                    }
                }
            }

            // Championships (if not provided via computed container)
            if league.computedChampionships == nil {
                championships += team.championships ?? 0
            }

            totalWaiverMoves += team.waiverMoves ?? 0
            totalFAAB += team.faabSpent ?? 0
            totalTrades += team.tradesCompleted ?? 0

            if let counts = team.actualStarterPositionCounts, let weeks = team.actualStarterWeeks {
                for (pos, count) in counts {
                    let norm = PositionNormalizer.normalize(pos)
                    actualPosCounts[norm, default: 0] += count
                }
                actualWeeks += weeks
            }

            // Regular season weeks aggregation
            let matchupsByWeek = season.matchupsByWeek ?? [:]
            let rosterId = Int(team.id) ?? -1

            var allWeeks = matchupsByWeek.keys.sorted()
            if let currentWeekCandidate = allWeeks.max(), allWeeks.count > 1 {
                allWeeks = allWeeks.filter { $0 != currentWeekCandidate }
            }
            if allWeeks.isEmpty {
                allWeeks = matchupsByWeek.keys.sorted()
            }

            for week in allWeeks {
                guard week < playoffStart else { continue }
                guard let entries = matchupsByWeek[week],
                      let entry = entries.first(where: { $0.roster_id == rosterId }) else { continue }

                distinctWeeks.insert("\(seasonId)-\(week)")

                let starters = entry.starters ?? []
                var weekPF = 0.0
                var weekOffPF = 0.0
                var weekDefPF = 0.0

                let slots = expandSlots(lineupConfig: team.lineupConfig ?? [:])
                let paddedStarters: [String] = {
                    if starters.count < slots.count {
                        return starters + Array(repeating: "0", count: slots.count - starters.count)
                    } else if starters.count > slots.count {
                        return Array(starters.prefix(slots.count))
                    }
                    return starters
                }()

                for idx in 0..<slots.count {
                    let pid = paddedStarters[idx]
                    guard pid != "0" else { continue }
                    let creditedPosition: String = {
                        if let rawPlayer = playerCache[pid], let pos = rawPlayer.position {
                            let forSlot = slots[idx]
                            let candidatePositions = [PositionNormalizer.normalize(pos)] + (rawPlayer.fantasy_positions?.map { PositionNormalizer.normalize($0) } ?? [])
                            return SlotPositionAssigner.countedPosition(for: forSlot, candidatePositions: candidatePositions, base: PositionNormalizer.normalize(pos))
                        }
                        if let teamPlayer = team.roster.first(where: { $0.id == pid }) {
                            let forSlot = slots[idx]
                            let candidatePositions = [PositionNormalizer.normalize(teamPlayer.position)] + (teamPlayer.altPositions?.map { PositionNormalizer.normalize($0) } ?? [])
                            return SlotPositionAssigner.countedPosition(for: forSlot, candidatePositions: candidatePositions, base: PositionNormalizer.normalize(teamPlayer.position))
                        }
                        let forSlot = slots[idx]
                        return SlotPositionAssigner.countedPosition(for: forSlot, candidatePositions: [], base: PositionNormalizer.normalize(forSlot))
                    }()

                    let point = entry.players_points?[pid] ?? 0.0
                    posTotals[creditedPosition, default: 0.0] += point
                    posStarts[creditedPosition, default: 0] += 1

                    let basePos: String = {
                        if let rawPlayer = playerCache[pid], let pos = rawPlayer.position { return PositionNormalizer.normalize(pos) }
                        if let teamPlayer = team.roster.first(where: { $0.id == pid }) { return PositionNormalizer.normalize(teamPlayer.position) }
                        return creditedPosition
                    }()
                    if offensivePositions.contains(basePos) {
                        weekOffPF += point
                    } else if defensivePositions.contains(basePos) {
                        weekDefPF += point
                    }
                    weekPF += point
                }

                totalPF += weekPF
                totalOffPF += weekOffPF
                totalDefPF += weekDefPF

                let maxes = computeMaxForEntry(entry: entry, lineupConfig: team.lineupConfig ?? [:], playerCache: playerCache, teamRoster: team.roster, week: week)
                totalMaxPF += maxes.total
                totalMaxOffPF += maxes.off
                totalMaxDefPF += maxes.def

                // Points scored against / W-L/T
                if let matchupId = entry.matchup_id,
                   let oppEntry = entries.first(where: { $0.matchup_id == matchupId && $0.roster_id != rosterId }),
                   let oppPoints = oppEntry.points {
                    totalPSA += oppPoints
                    let myPoints = entry.points ?? 0.0
                    if myPoints > oppPoints { wins += 1 }
                    else if myPoints < oppPoints { losses += 1 }
                }
            }
        }

        let weeksPlayed = distinctWeeks.count
        let mgmtPct = totalMaxPF > 0 ? totalPF / totalMaxPF * 100 : 0
        let offMgmt = totalMaxOffPF > 0 ? totalOffPF / totalMaxOffPF * 100 : 0
        let defMgmt = totalMaxDefPF > 0 ? totalDefPF / totalMaxDefPF * 100 : 0

        let ppw = weeksPlayed > 0 ? totalPF / Double(weeksPlayed) : 0
        let offPPW = weeksPlayed > 0 ? totalOffPF / Double(weeksPlayed) : 0
        let defPPW = weeksPlayed > 0 ? totalDefPF / Double(weeksPlayed) : 0

        var posAvgPPW: [String: Double] = [:]
        var indPosPPW: [String: Double] = [:]
        for pos in allStatPositions {
            let total = posTotals[pos] ?? 0
            let starts = posStarts[pos] ?? 0
            posAvgPPW[pos] = weeksPlayed > 0 ? total / Double(weeksPlayed) : 0
            indPosPPW[pos] = starts > 0 ? total / Double(starts) : 0
        }

        let playoffStats = aggregatePlayoffStats(ownerId: ownerId, allPlayoffMatchups: allPlayoffMatchups, league: league, playerCache: playerCache)

        return AggregatedOwnerStats(
            ownerId: ownerId,
            latestDisplayName: latestDisplayName,
            seasonsIncluded: teamsPerSeason.map { $0.0 },
            weeksPlayed: weeksPlayed,
            totalPointsFor: totalPF,
            totalMaxPointsFor: totalMaxPF,
            totalOffensivePointsFor: totalOffPF,
            totalMaxOffensivePointsFor: totalMaxOffPF,
            totalDefensivePointsFor: totalDefPF,
            totalMaxDefensivePointsFor: totalMaxDefPF,
            totalPointsScoredAgainst: totalPSA,
            managementPercent: mgmtPct,
            offensiveManagementPercent: offMgmt,
            defensiveManagementPercent: defMgmt,
            teamPPW: ppw,
            offensivePPW: offPPW,
            defensivePPW: defPPW,
            positionTotals: posTotals,
            positionStartCounts: posStarts,
            positionAvgPPW: posAvgPPW,
            individualPositionPPW: indPosPPW,
            championships: championships,
            totalWins: wins,
            totalLosses: losses,
            totalTies: ties,
            totalWaiverMoves: totalWaiverMoves,
            totalFAABSpent: totalFAAB,
            totalTradesCompleted: totalTrades,
            actualStarterPositionCountsTotals: actualPosCounts,
            actualStarterWeeks: actualWeeks,
            headToHeadVs: headToHead,
            headToHeadDetails: headToHeadDetails,
            playoffStats: playoffStats
        )
    }

    // MARK: - Helpers (single declarations only)

    /// Expands a lineupConfig to array of slot names in order
    private static func expandSlots(lineupConfig: [String: Int]) -> [String] {
        let sanitized = SlotUtils.sanitizeStartingLineupConfig(lineupConfig)
        return sanitized.flatMap { Array(repeating: $0.key, count: $0.value) }
    }

    /// Attempt to infer week for a matchupId by scanning season.matchupsByWeek
    private static func inferWeekForMatchup(matchupId: Int, rosterId: Int? = nil, season: SeasonData) -> Int? {
        guard let map = season.matchupsByWeek else { return nil }
        for (wk, entries) in map {
            if entries.contains(where: { $0.matchup_id == matchupId && (rosterId == nil || $0.roster_id == rosterId) }) {
                return wk
            }
        }
        return nil
    }

    /// Compute max points for a team for a given week using roster weeklyScores + lineup rules
    private static func maxPointsForWeek(team: TeamStanding, week: Int) -> (total: Double, off: Double, def: Double) {
        let playerScores = team.roster.reduce(into: [String: Double]()) { dict, player in
            if let score = player.weeklyScores.first(where: { $0.week == week })?.points {
                dict[player.id] = score
            }
        }

        let startingSlots = SlotUtils.sanitizeStartingSlots(team.league?.startingLineup ?? [])
        let fixedCounts = fixedSlotCounts(startingSlots: startingSlots)

        var offPlayerList = team.roster.filter { offensivePositions.contains(PositionNormalizer.normalize($0.position)) }.map {
            (id: $0.id, pos: PositionNormalizer.normalize($0.position), score: playerScores[$0.id] ?? 0.0)
        }
        var maxOff = 0.0
        for pos in Array(offensivePositions) {
            if let count = fixedCounts[pos] {
                let candidates = offPlayerList.filter { $0.pos == pos }.sorted { $0.score > $1.score }
                let top = Array(candidates.prefix(count))
                maxOff += top.reduce(0.0) { $0 + $1.score }
                offPlayerList.removeAll { used in top.contains { $0.id == used.id } }
            }
        }

        let flexAllowed: Set<String> = ["RB", "WR", "TE"]
        let flexCount = startingSlots.filter { offensiveFlexSlots.contains($0) }.count
        let flexCandidates = offPlayerList.filter { flexAllowed.contains($0.pos) }.sorted { $0.score > $1.score }
        maxOff += flexCandidates.prefix(flexCount).reduce(0.0) { $0 + $1.score }

        var defPlayerList = team.roster.filter { defensivePositions.contains(PositionNormalizer.normalize($0.position)) }.map {
            (id: $0.id, pos: PositionNormalizer.normalize($0.position), score: playerScores[$0.id] ?? 0.0)
        }
        var maxDef = 0.0
        for pos in Array(defensivePositions) {
            if let count = fixedCounts[pos] {
                let candidates = defPlayerList.filter { $0.pos == pos }.sorted { $0.score > $1.score }
                let top = Array(candidates.prefix(count))
                maxDef += top.reduce(0.0) { $0 + $1.score }
                defPlayerList.removeAll { used in top.contains { $0.id == used.id } }
            }
        }

        let maxTotal = maxOff + maxDef
        return (maxTotal, maxOff, maxDef)
    }

    /// Compute max PF for a single historical matchup entry using a robust candidate pool
    private static func computeMaxForEntry(
        entry: MatchupEntry,
        lineupConfig: [String: Int],
        playerCache: [String: RawSleeperPlayer],
        teamRoster: [Player]? = nil,
        week: Int? = nil
    ) -> (total: Double, off: Double, def: Double) {
        let sanitizedConfig = SlotUtils.sanitizeStartingLineupConfig(lineupConfig)

        var playersPoints: [String: Double] = entry.players_points ?? [:]
        if playersPoints.isEmpty, let roster = teamRoster, let wk = week {
            for p in roster {
                if let ws = p.weeklyScores.first(where: { $0.week == wk }) {
                    playersPoints[p.id] = ws.points_half_ppr ?? ws.points
                }
            }
        }

        var idSet = Set<String>(entry.players ?? [])
        if let starters = entry.starters { idSet.formUnion(starters) }
        idSet.formUnion(playersPoints.keys)
        if let roster = teamRoster { for p in roster { idSet.insert(p.id) } }

        let candidates: [(id: String, basePos: String, fantasy: [String], points: Double)] = idSet.compactMap { id in
            let pts = playersPoints[id] ?? 0.0
            if let raw = playerCache[id] {
                let normBase = PositionNormalizer.normalize(raw.position)
                let fantasy = (raw.fantasy_positions ?? []).map { PositionNormalizer.normalize($0) }
                return (id: id, basePos: normBase, fantasy: fantasy, points: pts)
            } else if let roster = teamRoster, let player = roster.first(where: { $0.id == id }) {
                let normBase = PositionNormalizer.normalize(player.position)
                let fantasy = (player.altPositions ?? []).map { PositionNormalizer.normalize($0) }
                return (id: id, basePos: normBase, fantasy: fantasy, points: pts)
            } else {
                return (id: id, basePos: PositionNormalizer.normalize("UNK"), fantasy: [], points: pts)
            }
        }

        var expandedSlots: [String] = []
        if !sanitizedConfig.isEmpty {
            for (slot, count) in sanitizedConfig {
                expandedSlots.append(contentsOf: Array(repeating: slot, count: count))
            }
        } else {
            let startersCount = (entry.starters?.count).flatMap { $0 > 0 ? $0 : nil } ?? max(1, candidates.count)
            var containsQB = false
            if let starters = entry.starters {
                for pid in starters {
                    if let raw = playerCache[pid], PositionNormalizer.normalize(raw.position) == "QB" { containsQB = true; break }
                    if let roster = teamRoster, roster.first(where: { $0.id == pid })?.position == "QB" { containsQB = true; break }
                }
            } else {
                if candidates.contains(where: { $0.basePos == "QB" }) { containsQB = true }
            }
            let flexSlot = containsQB ? "SUPER_FLEX" : "FLEX"
            expandedSlots = Array(repeating: flexSlot, count: startersCount)
        }

        var usedIDs = Set<String>()
        var maxTotal = 0.0, maxOff = 0.0, maxDef = 0.0

        for slot in expandedSlots {
            let allowedSet: Set<String> = Set(allowedPositions(for: slot).map { PositionNormalizer.normalize($0) })
            let pick = candidates
                .filter { !usedIDs.contains($0.id) && (allowedSet.contains($0.basePos) || !allowedSet.intersection(Set($0.fantasy)).isEmpty) }
                .max { $0.points < $1.points }
            guard let cand = pick else { continue }
            usedIDs.insert(cand.id)
            maxTotal += cand.points
            if offensivePositions.contains(PositionNormalizer.normalize(cand.basePos)) { maxOff += cand.points }
            else if defensivePositions.contains(PositionNormalizer.normalize(cand.basePos)) { maxDef += cand.points }
        }

        return (maxTotal, maxOff, maxDef)
    }

    /// Allowed positions for a slot (canonical, not normalized here)
    private static func allowedPositions(for slot: String) -> Set<String> {
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

    /// Fixed slot counts helper
    private static func fixedSlotCounts(startingSlots: [String]) -> [String: Int] {
        startingSlots.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    /// Actual points for a set of positions for a team that week
    private static func actualPointsForWeek(team: TeamStanding, week: Int, positions: Set<String>) -> Double {
        guard let starters = team.actualStartersByWeek?[week] else { return 0.0 }
        var total = 0.0
        for id in starters {
            if let player = team.roster.first(where: { $0.id == id }),
               positions.contains(PositionNormalizer.normalize(player.position)),
               let score = player.weeklyScores.first(where: { $0.week == week })?.points {
                total += score
            }
        }
        return total
    }

    // MARK: - Playoff aggregation + helpers

    private static func aggregatePlayoffStats(ownerId: String, allPlayoffMatchups: [SleeperMatchup], league: LeagueData, playerCache: [String: RawSleeperPlayer]) -> PlayoffStats {
        var totalPF = 0.0, totalMaxPF = 0.0
        var totalOffPF = 0.0, totalMaxOffPF = 0.0
        var totalDefPF = 0.0, totalMaxDefPF = 0.0
        var wins = 0, losses = 0, weeksPlayed = 0

        for matchup in allPlayoffMatchups {
            guard let season = league.seasons.first(where: { $0.matchups?.contains(where: { $0.matchupId == matchup.matchupId }) ?? false }),
                  let ownerTeam = season.teams.first(where: { $0.ownerId == ownerId }),
                  let myRosterId = Int(ownerTeam.id)
            else { continue }

            var wk = matchup.week
            if wk == nil {
                wk = inferWeekForMatchup(matchupId: matchup.matchupId, rosterId: myRosterId, season: season)
            }
            guard let week = wk else { continue }

            let weekMatchups = season.matchupsByWeek?[week] ?? []
            guard let myEntry = weekMatchups.first(where: { $0.roster_id == myRosterId }) else { continue }

            let starters = myEntry.starters ?? []
            var weekPF = 0.0, weekOffPF = 0.0, weekDefPF = 0.0
            for (idx, starterId) in starters.enumerated() {
                guard let point = myEntry.players_points?[starterId] else { continue }
                let rawPlayer = playerCache[starterId]
                let posRaw = rawPlayer?.position ?? ""
                let slots = expandSlots(lineupConfig: ownerTeam.lineupConfig ?? [:])
                let forSlot: String = slots[safe: idx] ?? posRaw
                let candidatePositions = ([posRaw] + (rawPlayer?.fantasy_positions ?? [])).map { PositionNormalizer.normalize($0) }
                let creditedPos = SlotPositionAssigner.countedPosition(for: forSlot, candidatePositions: candidatePositions, base: PositionNormalizer.normalize(posRaw))
                if offensivePositions.contains(PositionNormalizer.normalize(creditedPos)) { weekOffPF += point }
                else if defensivePositions.contains(PositionNormalizer.normalize(creditedPos)) { weekDefPF += point }
                weekPF += point
            }

            totalPF += weekPF
            totalOffPF += weekOffPF
            totalDefPF += weekDefPF

            let maxes = computeMaxForEntry(entry: myEntry, lineupConfig: ownerTeam.lineupConfig ?? [:], playerCache: playerCache, teamRoster: ownerTeam.roster, week: week)
            totalMaxPF += maxes.total
            totalMaxOffPF += maxes.off
            totalMaxDefPF += maxes.def

            if let matchupId = myEntry.matchup_id,
               let oppEntry = weekMatchups.first(where: { $0.matchup_id == matchupId && $0.roster_id != myRosterId }),
               let oppPoints = oppEntry.points {
                if myEntry.points ?? 0.0 > oppPoints { wins += 1 }
                else if myEntry.points ?? 0.0 < oppPoints { losses += 1 }
            }

            weeksPlayed += 1
        }

        let mgmtPct = totalMaxPF > 0 ? (totalPF / totalMaxPF) * 100 : 0
        let offMgmt = totalMaxOffPF > 0 ? (totalOffPF / totalMaxOffPF) * 100 : 0
        let defMgmt = totalMaxDefPF > 0 ? (totalDefPF / totalMaxDefPF) * 100 : 0

        let ppw = weeksPlayed > 0 ? totalPF / Double(weeksPlayed) : 0
        let offPPW = weeksPlayed > 0 ? totalOffPF / Double(weeksPlayed) : 0
        let defPPW = weeksPlayed > 0 ? totalDefPF / Double(weeksPlayed) : 0

        let isChampion = (weeksPlayed > 0 && losses == 0)

        return PlayoffStats(
            pointsFor: totalPF,
            maxPointsFor: totalMaxPF,
            ppw: ppw,
            managementPercent: mgmtPct,
            offensivePointsFor: totalOffPF,
            maxOffensivePointsFor: totalMaxOffPF,
            offensivePPW: offPPW,
            offensiveManagementPercent: offMgmt,
            defensivePointsFor: totalDefPF,
            maxDefensivePointsFor: totalMaxDefPF,
            defensivePPW: defPPW,
            defensiveManagementPercent: defMgmt,
            weeks: weeksPlayed,
            wins: wins,
            losses: losses,
            recordString: "\(wins)-\(losses)",
            isChampion: isChampion
        )
    }

    /// Gathers playoff bracket matchups for owner across seasons (best-effort).
    static func allPlayoffMatchupsForOwner(ownerId: String, league: LeagueData) -> [SleeperMatchup] {
        var all: [SleeperMatchup] = []
        for season in league.seasons {
            let playoffTeamsCount = season.playoffTeamsCount ?? 4
            let seeded = season.teams.sorted { $0.leagueStanding < $1.leagueStanding }.prefix(playoffTeamsCount)
            guard seeded.contains(where: { $0.ownerId == ownerId }) else { continue }

            let playoffStart = season.playoffStartWeek ?? 14
            let rounds = Int(ceil(log2(Double(playoffTeamsCount))))
            let bracketWeeks = Set(playoffStart..<(playoffStart + rounds))

            let matchups = season.matchups ?? []
            guard let ownerTeam = season.teams.first(where: { $0.ownerId == ownerId }), let ownerRosterId = Int(ownerTeam.id) else { continue }

            var ownerMatchupsWithWeek: [(SleeperMatchup, Int)] = []
            for m in matchups where m.rosterId == ownerRosterId {
                if let wk = m.week {
                    if bracketWeeks.contains(wk) { ownerMatchupsWithWeek.append((m, wk)) }
                } else if let inferred = inferWeekForMatchup(matchupId: m.matchupId, rosterId: ownerRosterId, season: season) {
                    if bracketWeeks.contains(inferred) { ownerMatchupsWithWeek.append((m, inferred)) }
                }
            }

            ownerMatchupsWithWeek.sort { a, b in a.1 < b.1 }

            var eliminated = false
            for (matchup, _) in ownerMatchupsWithWeek {
                if eliminated { break }
                all.append(matchup)
                if didOwnerLoseMatchup(ownerId: ownerId, matchup: matchup, season: season) {
                    eliminated = true
                }
            }
        }
        return all
    }

    // MARK: - Championship recompute

    /// Compute season champion deterministically (final main-bracket matchup winner)
    static func computeSeasonChampion(season: SeasonData) -> (rosterId: Int?, ownerId: String?) {
        let playoffTeamsCount = season.playoffTeamsCount ?? 4
        let playoffStart = season.playoffStartWeek ?? 14
        let rounds = Int(ceil(log2(Double(playoffTeamsCount))))
        let playoffWeeks = Set(playoffStart..<(playoffStart + rounds))

        guard let map = season.matchupsByWeek else {
            print("[ChampionDetect] season=\(season.id) no matchupsByWeek")
            return (nil, nil)
        }
        let presentWeeks = Set(map.keys).intersection(playoffWeeks)
        guard let finalWeek = presentWeeks.max() else {
            print("[ChampionDetect] season=\(season.id) no playoff weeks present")
            return (nil, nil)
        }

        let entries = map[finalWeek] ?? []
        var groups: [Int: [MatchupEntry]] = [:]
        var synthetic = -1
        for e in entries {
            if let mid = e.matchup_id {
                groups[mid, default: []].append(e)
            } else {
                groups[synthetic, default: []].append(e)
                synthetic -= 1
            }
        }

        for (_, group) in groups.sorted(by: { $0.key < $1.key }) {
            guard group.count == 2 else { continue }
            let a = group[0], b = group[1]
            let ptsA = a.points ?? 0.0
            let ptsB = b.points ?? 0.0
            guard ptsA != ptsB else { continue }
            let winnerRosterId = ptsA > ptsB ? a.roster_id : b.roster_id
            if let team = season.teams.first(where: { $0.id == String(winnerRosterId) }) {
                print("[ChampionDetect] season=\(season.id) winnerRoster=\(winnerRosterId) ownerId=\(team.ownerId)")
                return (winnerRosterId, team.ownerId)
            } else {
                print("[ChampionDetect] season=\(season.id) winnerRoster=\(winnerRosterId) ownerId=nil (lookup failed)")
                return (winnerRosterId, nil)
            }
        }

        print("[ChampionDetect] season=\(season.id) no valid final pairing")
        return (nil, nil)
    }

    /// Recompute champions across seasons and aggregated counts
    static func recomputeAllChampionships(for league: LeagueData) -> (seasonChampions: [String: String?], aggregated: [String: Int]) {
        var seasonChampions: [String: String?] = [:]
        var aggregated: [String: Int] = [:]

        for season in league.seasons {
            let (rosterOpt, ownerOpt) = computeSeasonChampion(season: season)
            seasonChampions[season.id] = ownerOpt
            if let oid = ownerOpt { aggregated[oid, default: 0] += 1 }
        }

        for (sid, oid) in seasonChampions.sorted(by: { $0.key < $1.key }) {
            print("[ChampionRecompute] season=\(sid) computedChampionOwnerId=\(oid ?? "null")")
        }
        for (owner, cnt) in aggregated {
            print("[ChampionRecompute] owner=\(owner) computedChampionships=\(cnt)")
        }
        return (seasonChampions, aggregated)
    }

    // MARK: - Misc helpers

    private static func isOwnerRoster(ownerId: String, rosterId: Int, season: SeasonData) -> Bool {
        return season.teams.first(where: { $0.ownerId == ownerId })?.id == String(rosterId)
    }

    private static func didOwnerLoseMatchup(ownerId: String, matchup: SleeperMatchup, season: SeasonData) -> Bool {
        guard let ownerTeam = season.teams.first(where: { $0.ownerId == ownerId }) else { return false }
        let myRosterId = Int(ownerTeam.id) ?? -1

        let wk = matchup.week ?? inferWeekForMatchup(matchupId: matchup.matchupId, rosterId: myRosterId, season: season)
        guard let week = wk else { return false }

        let allEntries = season.matchups?.filter { $0.matchupId == matchup.matchupId && ($0.week ?? week) == week } ?? []
        guard allEntries.count == 2 else { return false }
        guard let myEntry = allEntries.first(where: { $0.rosterId == myRosterId }),
              let oppEntry = allEntries.first(where: { $0.rosterId != myRosterId }) else { return false }
        let myPoints = myEntry.points
        let oppPoints = oppEntry.points
        return (myPoints ?? 0.0) < (oppPoints ?? 0.0)
    }
}

// Simple safe-subscripting extension used in several places
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
