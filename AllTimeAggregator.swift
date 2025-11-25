//
//  AllTimeAggregator.swift
//  DynastyStatDrop
//
//  Aggregates multi-season stats per current franchise (ownerId).
//
//  NOTES:
//  - Populates both aggregated H2H summary stats (headToHeadVs) and a per-opponent
//    chronological list of H2H match details (headToHeadDetails).
//  - Deduplicates matchup processing by matchupId so each pairing is counted once.
//  - Uses opponent lineupConfig for opponent max calculation.
//

import Foundation

@MainActor
struct AllTimeAggregator {
    static func buildAllTime(for league: LeagueData, playerCache: [String: RawSleeperPlayer]) -> LeagueData {
        var copy = league
        let currentIds = league.currentSeasonOwnerIds
        guard !currentIds.isEmpty else {
            copy.allTimeOwnerStats = [:]
            return copy
        }
        var result: [String: AggregatedOwnerStats] = [:]
        for ownerId in currentIds {
            // Gather all playoff matchups for this owner
            let allPlayoffMatchups = allPlayoffMatchupsForOwner(ownerId: ownerId, league: league)
            if let agg = aggregate(ownerId: ownerId, league: league, currentIds: currentIds, allPlayoffMatchups: allPlayoffMatchups, playerCache: playerCache) {
                result[ownerId] = agg
            }
        }
        copy.allTimeOwnerStats = result
        return copy
    }

    private static let offensiveFlexSlots: Set<String> = [
        "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE",
        "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX"
    ]

    static let allStatPositions: [String] = ["QB", "RB", "WR", "TE", "K", "DL", "LB", "DB"]
    // Use normalized position sets for offense/defense
    static let offensivePositions: Set<String> = ["QB", "RB", "WR", "TE", "K"]
    static let defensivePositions: Set<String> = ["DL", "LB", "DB"]

    /// Aggregate all-time **regular season** stats for this owner.
    /// Only regular season weeks (before playoffStartWeek) are included.
    private static func aggregate(ownerId: String, league: LeagueData, currentIds: [String], allPlayoffMatchups: [SleeperMatchup], playerCache: [String: RawSleeperPlayer]) -> AggregatedOwnerStats? {
        let seasons = league.seasons.sorted { $0.id < $1.id }
        var teamsPerSeason: [(String, TeamStanding, Int)] = [] // (seasonId, team, playoffStartWeek)
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
        var wins = 0, losses = 0, ties = 0

        // PATCH: Use normalized position for all position-based dictionaries
        var posTotals: [String: Double] = [:]
        var posStarts: [String: Int] = [:]
        var distinctWeeks: Set<String> = []

        var totalWaiverMoves = 0
        var totalFAAB = 0.0
        var totalTrades = 0

        // These are already normalized by upstream code, but ensure normalization for safety
        var actualPosCounts: [String: Int] = [:]
        var actualWeeks = 0

        // NEW: Head-to-head vs other current owners
        var headToHead: [String: H2HStats] = [:]
        // NEW: Per-opponent match detail history
        var headToHeadDetails: [String: [H2HMatchDetail]] = [:]
        let currentIdsSet = Set(currentIds)

        for (seasonId, team, playoffStart) in teamsPerSeason {
            let season = seasons.first { $0.id == seasonId }!

            // Head-to-head aggregation for this season vs other current owners
            for oppTeam in season.teams where oppTeam.ownerId != ownerId && currentIdsSet.contains(oppTeam.ownerId) {
                guard let uRid = Int(team.id), let oRid = Int(oppTeam.id) else { continue }

                // Collect matchups involving either roster id from the flattened season.matchups.
                // IMPORTANT FIX:
                // Previously we deduplicated only by matchupId which could mix entries across different weeks
                // when the same matchupId appears in multiple weeks. That caused cross-week pairing (duplicates
                // and missing matchups). To avoid that we group by the combination of matchupId+week so each
                // distinct pairing/week is handled independently.
                let relevant = (season.matchups ?? []).filter { m in m.rosterId == uRid || m.rosterId == oRid }

                // Group by (matchupId, week) key. If week is not present, attempt to infer it; if inference fails
                // we use a sentinel (-999) so those entries don't get mixed with entries that have an explicit week.
                var grouped: [String: [SleeperMatchup]] = [:]
                for m in relevant {
                    let wk = m.week ?? inferWeekForMatchup(matchupId: m.matchupId, rosterId: nil, season: season) ?? -999
                    let key = "\(m.matchupId):\(wk)"
                    grouped[key, default: []].append(m)
                }

                // Closure to process a pair of SleeperMatchup entries (two entries representing a pairing)
                let processPair: (SleeperMatchup, SleeperMatchup) -> Void = { entryA, entryB in
                    // Map to user/opponent order
                    guard (entryA.rosterId == uRid && entryB.rosterId == oRid) || (entryA.rosterId == oRid && entryB.rosterId == uRid) else { return }
                    let uEntryPair = (entryA.rosterId == uRid) ? entryA : entryB
                    let oEntryPair = (entryA.rosterId == oRid) ? entryA : entryB
                    let uPts = uEntryPair.points
                    let oPts = oEntryPair.points
                    if uPts == 0 && oPts == 0 { return }

                    // Prefer explicit week on any entry for this matchup; fall back to inference by scanning matchupsByWeek
                    var week = uEntryPair.week ?? oEntryPair.week
                    if week == nil {
                        week = inferWeekForMatchup(matchupId: uEntryPair.matchupId, rosterId: nil, season: season)
                    }
                    guard let wk = week else { return }

                    let weekMatchups = season.matchupsByWeek?[wk] ?? []
                    guard let uEntry2 = weekMatchups.first(where: { $0.roster_id == uRid }),
                          let oEntry2 = weekMatchups.first(where: { $0.roster_id == oRid }) else { return }

                    // Compute max with robust fallback: pass team roster and week context
                    // NOTE: sanitize lineupConfig where appropriate inside computeMaxForEntry
                    let uMax = computeMaxForEntry(entry: uEntry2, lineupConfig: team.lineupConfig ?? [:], playerCache: playerCache, teamRoster: team.roster, week: wk).total
                    // IMPORTANT: use the opponent's lineupConfig when computing opponent max
                    let oMax = computeMaxForEntry(entry: oEntry2, lineupConfig: oppTeam.lineupConfig ?? team.lineupConfig ?? [:], playerCache: playerCache, teamRoster: oppTeam.roster, week: wk).total

                    let uMgmt = uMax > 0 ? (uPts / uMax) * 100 : 0.0
                    let oMgmt = oMax > 0 ? (oPts / oMax) * 100 : 0.0

                    // Update aggregate summary H2HStats
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
                    } else {
                        curr = H2HStats(wins: curr.wins, losses: curr.losses, ties: curr.ties + 1, pointsFor: curr.pointsFor, pointsAgainst: curr.pointsAgainst, games: curr.games, sumMgmtFor: curr.sumMgmtFor, sumMgmtAgainst: curr.sumMgmtAgainst)
                    }
                    headToHead[oppTeam.ownerId] = curr

                    // Append per-match detail
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

                // Process each grouped (matchupId, week) group independently.
                for (_, group) in grouped.sorted(by: { $0.key < $1.key }) {
                    if group.count == 2 {
                        processPair(group[0], group[1])
                    } else if group.count > 2 {
                        // If multiple entries exist for the same matchupId+week (rare), pair deterministically by rosterId.
                        let sorted = group.sorted { a, b in
                            let aw = a.week ?? 0
                            let bw = b.week ?? 0
                            if aw != bw { return aw < bw }
                            return a.rosterId < b.rosterId
                        }
                        var i = 0
                        while i + 1 < sorted.count {
                            processPair(sorted[i], sorted[i + 1])
                            i += 2
                        }
                        // If an odd singleton is left, be conservative and skip it.
                    } else {
                        // singleton group — nothing reliable to pair here (week info might be missing); skip
                        continue
                    }
                }
            }

            championships += team.championships ?? 0

            totalWaiverMoves += team.waiverMoves ?? 0
            totalFAAB += team.faabSpent ?? 0
            totalTrades += team.tradesCompleted ?? 0

            if let counts = team.actualStarterPositionCounts, let weeks = team.actualStarterWeeks {
                // PATCH: Normalize actual starter position counts (defensive)
                for (pos, count) in counts {
                    let norm = PositionNormalizer.normalize(pos)
                    actualPosCounts[norm, default: 0] += count
                }
                actualWeeks += weeks
            }

            // Defensive filtering: exclude current week ONLY IF more than one week is present
            let matchupsByWeek = season.matchupsByWeek ?? [:]
            let rosterId = Int(team.id) ?? -1

            let allWeeks = matchupsByWeek.keys.sorted()
            var filteredWeeks = allWeeks
            if let currentWeek = allWeeks.max(), allWeeks.count > 1 {
                filteredWeeks = allWeeks.filter { $0 != currentWeek }
            }
            if filteredWeeks.isEmpty {
                filteredWeeks = allWeeks
            }

            for week in filteredWeeks {
                guard week < playoffStart else { continue }
                guard let entries = matchupsByWeek[week],
                      let entry = entries.first(where: { $0.roster_id == rosterId }) else { continue }

                distinctWeeks.insert("\(seasonId)-\(week)")

                // PF, Off PF, Def PF from starters' points (using players_points and positions from cache)
                let starters = entry.starters ?? []
                var weekPF = 0.0
                var weekOffPF = 0.0
                var weekDefPF = 0.0

                // --- PATCHED: Use SlotPositionAssigner.countedPosition for all-time PPW/individualPPW ---
                let slots = expandSlots(lineupConfig: team.lineupConfig ?? [:])
                let paddedStarters = {
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
                    // --- PATCH: Use SlotPositionAssigner global helper for credited position ---
                    let creditedPosition: String = {
                        if let rawPlayer = playerCache[pid], let pos = rawPlayer.position {
                            // ensure non-optional first-parameter by computing local forSlot
                            let forSlot = slots[idx]
                            let candidatePositions = [PositionNormalizer.normalize(pos)] + (rawPlayer.fantasy_positions?.map { PositionNormalizer.normalize($0) } ?? [])
                            return SlotPositionAssigner.countedPosition(
                                for: forSlot,
                                candidatePositions: candidatePositions,
                                base: PositionNormalizer.normalize(pos)
                            )
                        }
                        if let teamPlayer = team.roster.first(where: { $0.id == pid }) {
                            let forSlot = slots[idx]
                            let candidatePositions = [PositionNormalizer.normalize(teamPlayer.position)] + (teamPlayer.altPositions?.map { PositionNormalizer.normalize($0) } ?? [])
                            return SlotPositionAssigner.countedPosition(
                                for: forSlot,
                                candidatePositions: candidatePositions,
                                base: PositionNormalizer.normalize(teamPlayer.position)
                            )
                        }
                        // fallback: use slot as credited position
                        let forSlot = slots[idx]
                        return SlotPositionAssigner.countedPosition(
                            for: forSlot,
                            candidatePositions: [],
                            base: PositionNormalizer.normalize(forSlot)
                        )
                    }()
                    let point = entry.players_points?[pid] ?? 0.0
                    posTotals[creditedPosition, default: 0.0] += point
                    posStarts[creditedPosition, default: 0] += 1

                    // For overall offense/defense, use normalized base pos if available
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

                // Max PF, Max Off, Max Def from optimal lineup (using historical roster that week)
                // computeMaxForEntry sanitizes lineupConfig internally
                let maxes = computeMaxForEntry(entry: entry, lineupConfig: team.lineupConfig ?? [:], playerCache: playerCache, teamRoster: team.roster, week: week)
                totalMaxPF += maxes.total
                totalMaxOffPF += maxes.off
                totalMaxDefPF += maxes.def

                // PSA, Win/Loss/Tie from opponent
                if let matchupId = entry.matchup_id,
                   let oppEntry = entries.first(where: { $0.matchup_id == matchupId && $0.roster_id != rosterId }),
                   let oppPoints = oppEntry.points {
                    totalPSA += oppPoints
                    let myPoints = entry.points ?? 0.0
                    if myPoints > oppPoints { wins += 1 }
                    else if myPoints < oppPoints { losses += 1 }
                    else { ties += 1 }
                }
            }
        }

        let weeksPlayed = distinctWeeks.count

        // Derived
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

    /// Expands a lineupConfig to array of slot names in order
    private static func expandSlots(lineupConfig: [String: Int]) -> [String] {
        // sanitize lineup config to remove bench-like tokens before expanding
        let sanitized = SlotUtils.sanitizeStartingLineupConfig(lineupConfig)
        return sanitized.flatMap { Array(repeating: $0.key, count: $0.value) }
    }

    // Helper: attempt to infer the week number for a Sleeper pairing id by scanning matchupsByWeek
    // Returns nil if not found.
    private static func inferWeekForMatchup(matchupId: Int, rosterId: Int? = nil, season: SeasonData) -> Int? {
        guard let map = season.matchupsByWeek else { return nil }
        for (wk, entries) in map {
            if entries.contains(where: { $0.matchup_id == matchupId && (rosterId == nil || $0.roster_id == rosterId) }) {
                return wk
            }
        }
        return nil
    }

    // PATCHED: Replace local countedPosition with SlotPositionAssigner global helper
    // **Local countedPosition logic removed in favor of SlotPositionAssigner**

    private static func maxPointsForWeek(team: TeamStanding, week: Int) -> (total: Double, off: Double, def: Double) {
        let playerScores = team.roster.reduce(into: [String: Double]()) { dict, player in
            // PATCH: Normalize position for defense
            let pos = PositionNormalizer.normalize(player.position)
            if let score = player.weeklyScores.first(where: { $0.week == week })?.points {
                dict[player.id] = score
            }
        }

        // Compute max: optimal lineup
        // SANITIZE league starting lineup before using it as "starting slots"
        let startingSlots = SlotUtils.sanitizeStartingSlots(team.league?.startingLineup ?? [])
        let fixedCounts = fixedSlotCounts(startingSlots: startingSlots)

        // Offensive
        var offPlayerList = team.roster.filter { AllTimeAggregator.offensivePositions.contains(PositionNormalizer.normalize($0.position)) }.map {
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

        // Allocate flex slots
        let flexAllowed: Set<String> = ["RB", "WR", "TE"]
        let flexCount = startingSlots.filter { offensiveFlexSlots.contains($0) }.count
        let flexCandidates = offPlayerList.filter { flexAllowed.contains($0.pos) }.sorted { $0.score > $1.score }
        let topFlex = Array(flexCandidates.prefix(flexCount))
        maxOff += topFlex.reduce(0.0) { $0 + $1.score }

        // Defensive
        var defPlayerList = team.roster.filter { AllTimeAggregator.defensivePositions.contains(PositionNormalizer.normalize($0.position)) }.map {
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

    // NEW: Compute max PF for a single historical matchup entry (using players on roster that week)
    // PATCHED: More robust candidate pool construction and lineupConfig fallbacks to avoid under-counting max.
    private static func computeMaxForEntry(
        entry: MatchupEntry,
        lineupConfig: [String: Int],
        playerCache: [String: RawSleeperPlayer],
        teamRoster: [Player]? = nil,        // NEW: optional roster fallback
        week: Int? = nil                   // NEW: week for roster weeklyScores lookup if needed
    ) -> (total: Double, off: Double, def: Double) {
        // Sanitize provided lineup config early to drop bench/IR/taxi slots
        let sanitizedConfig = SlotUtils.sanitizeStartingLineupConfig(lineupConfig)

        // Build playersPoints: prefer entry.players_points, fallback to teamRoster weeklyScores (if week provided)
        var playersPoints: [String: Double] = entry.players_points ?? [:]
        if playersPoints.isEmpty, let roster = teamRoster, let wk = week {
            for p in roster {
                if let ws = p.weeklyScores.first(where: { $0.week == wk }) {
                    playersPoints[p.id] = ws.points_half_ppr ?? ws.points
                }
            }
        }

        // Build candidate IDs: union of entry.players and teamRoster ids (if available) to be robust
        var idSet = Set<String>(entry.players ?? [])
        if let roster = teamRoster {
            for p in roster { idSet.insert(p.id) }
        }

        // Build candidates with normalized positions and available points (0.0 if no points found)
        let candidates: [(id: String, basePos: String, fantasy: [String], points: Double)] = idSet.compactMap { id in
            let pts = playersPoints[id] ?? 0.0
            // Try to get RawSleeperPlayer from cache first, else from teamRoster
            if let raw = playerCache[id] {
                guard let basePosRaw = raw.position else {
                    // If position missing, still include candidate with "UNK" to avoid drop
                    return (id: id, basePos: PositionNormalizer.normalize("UNK"), fantasy: (raw.fantasy_positions ?? []).map { PositionNormalizer.normalize($0) }, points: pts)
                }
                let normBase = PositionNormalizer.normalize(basePosRaw)
                let fantasy = (raw.fantasy_positions ?? [basePosRaw]).map { PositionNormalizer.normalize($0) }
                return (id: id, basePos: normBase, fantasy: fantasy, points: pts)
            } else if let roster = teamRoster, let player = roster.first(where: { $0.id == id }) {
                let normBase = PositionNormalizer.normalize(player.position)
                let fantasy = (player.altPositions ?? [player.position]).map { PositionNormalizer.normalize($0) }
                return (id: id, basePos: normBase, fantasy: fantasy, points: pts)
            } else {
                // Unknown player id and not in roster/playerCache: still include with points if any
                return (id: id, basePos: PositionNormalizer.normalize("UNK"), fantasy: [], points: pts)
            }
        }

        // Expand slots from lineupConfig; if empty, infer fallback
        var expandedSlots: [String] = []
        if !sanitizedConfig.isEmpty {
            for (slot, count) in sanitizedConfig {
                expandedSlots.append(contentsOf: Array(repeating: slot, count: count))
            }
        } else {
            // Fallback: if entry includes starters count, use that; otherwise use number of candidates
            let startersCount = (entry.starters?.count).flatMap { $0 > 0 ? $0 : nil } ?? max(1, candidates.count)
            // If any starter/candidate is QB, prefer SUPER_FLEX (allowing QB), else regular FLEX
            var containsQB = false
            if let starters = entry.starters {
                for pid in starters {
                    if let raw = playerCache[pid], PositionNormalizer.normalize(raw.position) == "QB" { containsQB = true; break }
                    if let roster = teamRoster, roster.first(where: { $0.id == pid })?.position == "QB" { containsQB = true; break }
                }
            } else {
                // look at candidates
                if candidates.contains(where: { $0.basePos == "QB" }) { containsQB = true }
            }
            let flexSlot = containsQB ? "SUPER_FLEX" : "FLEX"
            expandedSlots = Array(repeating: flexSlot, count: startersCount)
        }

        var usedIDs = Set<String>()
        var maxTotal = 0.0
        var maxOff = 0.0
        var maxDef = 0.0

        for slot in expandedSlots {
            // Normalize allowed into a Set for intersection operations
            let allowedSet: Set<String> = Set(allowedPositions(for: slot).map { PositionNormalizer.normalize($0) })
            // pick highest scoring eligible candidate not yet used
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

    private static func isEligible(c: (id: String, basePos: String, fantasy: [String], points: Double), allowed: Set<String>) -> Bool {
        if allowed.contains(PositionNormalizer.normalize(c.basePos)) { return true }
        return !allowed.intersection(Set(c.fantasy.map(PositionNormalizer.normalize))).isEmpty
    }

    private static func fixedSlotCounts(startingSlots: [String]) -> [String: Int] {
        startingSlots.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

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

    // MARK: Playoff Stats Aggregation

    private static func aggregatePlayoffStats(ownerId: String, allPlayoffMatchups: [SleeperMatchup], league: LeagueData, playerCache: [String: RawSleeperPlayer]) -> PlayoffStats {
        var totalPF = 0.0, totalMaxPF = 0.0
        var totalOffPF = 0.0, totalMaxOffPF = 0.0
        var totalDefPF = 0.0, totalMaxDefPF = 0.0
        var wins = 0, losses = 0, ties = 0
        var weeksPlayed = 0

        for matchup in allPlayoffMatchups {
            // Try to find season that contains this pairing id (matchupId)
            guard let season = league.seasons.first(where: { $0.matchups?.contains(where: { $0.matchupId == matchup.matchupId }) ?? false }),
                  let ownerTeam = season.teams.first(where: { $0.ownerId == ownerId }),
                  let myRosterId = Int(ownerTeam.id)
            else { continue }

            // Determine week for this matchup (prefer explicit week)
            var wk = matchup.week
            if wk == nil {
                wk = inferWeekForMatchup(matchupId: matchup.matchupId, rosterId: myRosterId, season: season)
            }
            guard let week = wk else { continue }

            let weekMatchups = season.matchupsByWeek?[week] ?? []
            guard let myEntry = weekMatchups.first(where: { $0.roster_id == myRosterId }) else { continue }

            // PF, Off PF, Def PF from historical starters
            let starters = myEntry.starters ?? []
            var weekPF = 0.0
            var weekOffPF = 0.0
            var weekDefPF = 0.0
            for (idx, starterId) in starters.enumerated() {
                guard let point = myEntry.players_points?[starterId],
                      let rawPlayer = playerCache[starterId],
                      let posRaw = rawPlayer.position else { continue }
                // PATCH: Use SlotPositionAssigner for credited playoff position assignment
                let slots = expandSlots(lineupConfig: ownerTeam.lineupConfig ?? [:])
                // ensure non-optional slot variable for countedPosition call
                let forSlot: String = slots[safe: idx] ?? posRaw
                let candidatePositions = [PositionNormalizer.normalize(posRaw)] + (rawPlayer.fantasy_positions?.map { PositionNormalizer.normalize($0) } ?? [])
                let creditedPos = SlotPositionAssigner.countedPosition(
                    for: forSlot,
                    candidatePositions: candidatePositions,
                    base: PositionNormalizer.normalize(posRaw)
                )
                weekPF += point
                if offensivePositions.contains(PositionNormalizer.normalize(creditedPos)) {
                    weekOffPF += point
                } else if defensivePositions.contains(PositionNormalizer.normalize(creditedPos)) {
                    weekDefPF += point
                }
            }
            totalPF += weekPF
            totalOffPF += weekOffPF
            totalDefPF += weekDefPF

            // Max PF from historical roster that week
            let maxes = computeMaxForEntry(entry: myEntry, lineupConfig: ownerTeam.lineupConfig ?? [:], playerCache: playerCache, teamRoster: ownerTeam.roster, week: week)
            totalMaxPF += maxes.total
            totalMaxOffPF += maxes.off
            totalMaxDefPF += maxes.def

            // Opponent points for win/loss
            if let matchupId = myEntry.matchup_id,
               let oppEntry = weekMatchups.first(where: { $0.matchup_id == matchupId && $0.roster_id != myRosterId }),
               let oppPoints = oppEntry.points {
                if myEntry.points ?? 0.0 > oppPoints { wins += 1 }
                else if myEntry.points ?? 0.0 < oppPoints { losses += 1 }
                else { ties += 1 }
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
            recordString: "\(wins)-\(losses)\(ties > 0 ? "-\(ties)" : "")",
            isChampion: isChampion
        )
    }
}

/// Helper: Gathers all playoff bracket matchups for this owner over all seasons in the league.
/// Must only return playoff bracket games (not consolation), and only for seasons where owner made playoffs.
func allPlayoffMatchupsForOwner(ownerId: String, league: LeagueData) -> [SleeperMatchup] {
    var all: [SleeperMatchup] = []
    for season in league.seasons {
        let playoffTeamsCount = season.playoffTeamsCount ?? 4
        let playoffSeededTeams = season.teams.sorted { $0.leagueStanding < $1.leagueStanding }
            .prefix(playoffTeamsCount)
        guard playoffSeededTeams.contains(where: { $0.ownerId == ownerId }) else { continue }

        let playoffStart = season.playoffStartWeek ?? 14
        let bracketWeeks: Set<Int> = Set(playoffStart..<(playoffStart + Int(ceil(log2(Double(playoffTeamsCount)))))
        )

        let seasonMatchups: [SleeperMatchup] = season.matchups ?? []
        let ownerTeam = season.teams.first(where: { $0.ownerId == ownerId })
        let ownerRosterId = ownerTeam.flatMap { Int($0.id) } ?? -1
        // Prefer matchup.week when available, else infer by matchupId
        let ownerMatchups = seasonMatchups.filter { m in
            let wk = m.week ?? m.matchupId
            return bracketWeeks.contains(wk) && m.rosterId == ownerRosterId
        }
        var eliminated = false
        for matchup in ownerMatchups.sorted(by: { ($0.week ?? $0.matchupId) < ($1.week ?? $1.matchupId) }) {
            if eliminated { break }
            all.append(matchup)
            if didOwnerLoseMatchup(ownerId: ownerId, matchup: matchup, season: season) {
                eliminated = true
            }
        }
    }
    return all
}

func isOwnerRoster(ownerId: String, rosterId: Int, season: SeasonData) -> Bool {
    return season.teams.first(where: { $0.ownerId == ownerId })?.id == String(rosterId)
}
func didOwnerLoseMatchup(ownerId: String, matchup: SleeperMatchup, season: SeasonData) -> Bool {
    guard let ownerTeam = season.teams.first(where: { $0.ownerId == ownerId }) else { return false }
    let myRosterId = Int(ownerTeam.id) ?? -1
    let allEntries = season.matchups?.filter { $0.matchupId == matchup.matchupId } ?? []
    guard allEntries.count == 2 else { return false }
    guard let myEntry = allEntries.first(where: { $0.rosterId == myRosterId }),
          let oppEntry = allEntries.first(where: { $0.rosterId != myRosterId }) else { return false }
    let myPoints = myEntry.points
    let oppPoints = oppEntry.points
    return myPoints < oppPoints
}

extension Collection {
    subscript(safe at: Index) -> Element? {
        indices.contains(at) ? self[at] : nil
    }
}
