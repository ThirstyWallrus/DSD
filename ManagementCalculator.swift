//
//  ManagementCalculator.swift
//  DynastyStatDrop
//
//  Shared helper to compute management% and related totals for a team/week or matchup entry.
//  This centralizes the greedy slot-assignment algorithm used by MatchupView and HeadToHead
//  to ensure parity and to reduce duplicated recomputation across the app.
//
//  NOTE: Marked @MainActor so this helper can safely reference SleeperLeagueManager.playerCache
//  and other main-actor-isolated properties without requiring callers to await/escape actor context.
//  MatchupView and HeadToHeadStatsSection are SwiftUI Views (main actor) so this is a compatible model.
//
import Foundation

@MainActor
struct ManagementCalculator {

    /// Compute actual/max/off/def totals for a TeamStanding for a given week.
    /// Mirrors the logic previously embedded in MatchupView.computeManagementForWeek.
    /// - Parameters:
    ///   - team: historical team snapshot
    ///   - week: week number
    ///   - league: optional league data (used for league.startingLineup). If nil, uses team.lineupConfig fallback.
    ///   - leagueManager: for player cache resolution when roster snapshots don't contain position info.
    /// - Returns: (actualTotal, maxTotal, actualOff, maxOff, actualDef, maxDef)
    static func computeManagementForWeek(team: TeamStanding, week: Int, league: LeagueData?, leagueManager: SleeperLeagueManager) -> (Double, Double, Double, Double, Double, Double) {
        // If a league is provided, prioritize the season that contains the TeamStanding passed in.
        if let lg = league {
            // Build ordered seasons with the season containing the team first (if any).
            var seasonsOrdered: [SeasonData] = []
            if let containingSeason = lg.seasons.first(where: { season in
                season.teams.contains(where: { $0.id == team.id })
            }) {
                seasonsOrdered.append(containingSeason)
                // Append the rest preserving existing order but without duplicating the containingSeason
                seasonsOrdered.append(contentsOf: lg.seasons.filter { $0.id != containingSeason.id })
            } else {
                seasonsOrdered = lg.seasons
            }

            for season in seasonsOrdered {
                if let weeks = season.matchupsByWeek, let entries = weeks[week] {
                    if let entry = entries.first(where: { $0.roster_id == Int(team.id) }) {
                        // Found a matchup entry -> compute using entry players_points preferentially
                        if let playersPoints = entry.players_points, !playersPoints.isEmpty {
                            // AUGMENT playersPoints but ONLY for IDs that are relevant to this matchup/team.
                            var augmented = playersPoints // copy to mutate

                            // Build targeted id set to avoid pulling in whole-season players
                            var idsToCheck = Set<String>()
                            if let ps = entry.players { idsToCheck.formUnion(ps) }
                            if let sts = entry.starters { idsToCheck.formUnion(sts) }
                            idsToCheck.formUnion(team.roster.map { $0.id })
                            if let ownedKeys = lg.ownedPlayers?.keys { idsToCheck.formUnion(ownedKeys) }
                            if let thKeys = lg.teamHistoricalPlayers?[team.id]?.keys { idsToCheck.formUnion(thKeys) }

                            // Scan the containing season first (best chance to find historical/IR/taxi snapshots)
                            for sTeam in season.teams {
                                for p in sTeam.roster {
                                    if augmented[p.id] == nil, idsToCheck.contains(p.id) {
                                        if let ws = p.weeklyScores.first(where: { $0.week == week }) {
                                            augmented[p.id] = ws.points_half_ppr ?? ws.points
                                        }
                                    }
                                }
                            }

                            // Then scan other seasons only for ids in idsToCheck
                            for s in lg.seasons where s.id != season.id {
                                for sTeam in s.teams {
                                    for p in sTeam.roster {
                                        if augmented[p.id] == nil, idsToCheck.contains(p.id) {
                                            if let ws = p.weeklyScores.first(where: { $0.week == week }) {
                                                augmented[p.id] = ws.points_half_ppr ?? ws.points
                                            }
                                        }
                                    }
                                }
                            }

                            return computeUsingMatchupEntry(team: team, entry: entry, playersPoints: augmented, league: lg, leagueManager: leagueManager, week: week)
                        } else {
                            // No players_points present: build fallback but LIMIT to ids that make sense to consider.
                            // We will include:
                            // - starters list
                            // - entry.players list (if present)
                            // - team's current roster
                            // - league ownedPlayers & teamHistoricalPlayers for this team
                            var idsToCheck = Set<String>()
                            if let ps = entry.players { idsToCheck.formUnion(ps) }
                            if let sts = entry.starters { idsToCheck.formUnion(sts) }
                            idsToCheck.formUnion(team.roster.map { $0.id })
                            if let ownedKeys = lg.ownedPlayers?.keys { idsToCheck.formUnion(ownedKeys) }
                            if let thKeys = lg.teamHistoricalPlayers?[team.id]?.keys { idsToCheck.formUnion(thKeys) }

                            var fallback: [String: Double] = [:]
                            // Scan season teams but only add weeklyScores for idsToCheck
                            for sTeam in season.teams {
                                for p in sTeam.roster {
                                    if idsToCheck.contains(p.id), fallback[p.id] == nil {
                                        if let ws = p.weeklyScores.first(where: { $0.week == week }) {
                                            fallback[p.id] = ws.points_half_ppr ?? ws.points
                                        }
                                    }
                                }
                            }

                            // If we still missing some ids (e.g., historical snapshots in other seasons), scan other seasons but still limited
                            if !idsToCheck.isEmpty {
                                for s in lg.seasons where s.id != season.id {
                                    for sTeam in s.teams {
                                        for p in sTeam.roster {
                                            if idsToCheck.contains(p.id), fallback[p.id] == nil {
                                                if let ws = p.weeklyScores.first(where: { $0.week == week }) {
                                                    fallback[p.id] = ws.points_half_ppr ?? ws.points
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            if !fallback.isEmpty {
                                return computeUsingMatchupEntry(team: team, entry: entry, playersPoints: fallback, league: lg, leagueManager: leagueManager, week: week)
                            }
                        }
                        // If this season had a matching entry but we couldn't compute using players_points or targeted fallback,
                        // break and fall back to legacy roster-based computation below.
                        break
                    }
                }
            }
        }

        // Legacy roster-based computation (fallback)
        return legacyRosterBasedManagement(team: team, week: week, league: league, leagueManager: leagueManager)
    }

    /// Compute mgmt% for a raw MatchupEntry (single entry).
    /// Uses players_points when available, otherwise tries to construct players_points from seasonTeam.roster weeklyScores.
    static func computeManagementPercentForEntry(entry: MatchupEntry, seasonTeam: TeamStanding?, week: Int, league: LeagueData?, leagueManager: SleeperLeagueManager) -> Double? {
        var playersPoints: [String: Double] = entry.players_points ?? [:]

        // If no players_points, try to build fallback from seasonTeam roster weeklyScores (only that roster)
        if playersPoints.isEmpty {
            if let team = seasonTeam {
                for p in team.roster {
                    if let s = p.weeklyScores.first(where: { $0.week == week }) {
                        playersPoints[p.id] = s.points_half_ppr ?? s.points
                    }
                }
            }
        }

        // EXTENDED FALLBACK: If still empty and we have a league, scan season team rosters but LIMIT to relevant ids
        if playersPoints.isEmpty, let lg = league {
            // Build idsToCheck from entry + seasonTeam + league caches
            var idsToCheck = Set<String>()
            if let ps = entry.players { idsToCheck.formUnion(ps) }
            if let sts = entry.starters { idsToCheck.formUnion(sts) }
            if let t = seasonTeam { idsToCheck.formUnion(t.roster.map { $0.id }) }
            if let owned = lg.ownedPlayers?.keys { idsToCheck.formUnion(owned) }
            if let th = lg.teamHistoricalPlayers?[seasonTeam?.id ?? ""]?.keys { idsToCheck.formUnion(th) }

            for season in lg.seasons {
                for sTeam in season.teams {
                    for p in sTeam.roster {
                        if playersPoints[p.id] == nil, idsToCheck.contains(p.id) {
                            if let s = p.weeklyScores.first(where: { $0.week == week }) {
                                playersPoints[p.id] = s.points_half_ppr ?? s.points
                            }
                        }
                    }
                }
            }
        }

        guard !playersPoints.isEmpty else { return nil }

        // Determine starting slots
        var startingSlots: [String] = SlotUtils.sanitizeStartingSlots(league?.startingLineup ?? [])
        if startingSlots.isEmpty {
            if let cfg = seasonTeam?.lineupConfig, !cfg.isEmpty {
                startingSlots = expandSlots(cfg)
            }
        }
        if startingSlots.isEmpty {
            // Give up if unknown starter slots
            return nil
        }

        let playerCache = leagueManager.playerCache ?? [:]

        // Build candidate pool using a safe lookup order:
        // 1) seasonTeam.roster
        // 2) league.ownedPlayers (CompactPlayer)
        // 3) league.teamHistoricalPlayers for this roster/team
        // 4) global playerCache (full RawSleeperPlayer)
        // 5) fallback "UNK"
        var candidates: [(id: String, basePos: String, altPos: [String], score: Double)] = []
        for pid in Set(Array(playersPoints.keys) + (seasonTeam?.roster.map { $0.id } ?? [])) {
            if let p = seasonTeam?.roster.first(where: { $0.id == pid }) {
                candidates.append((id: pid, basePos: PositionNormalizer.normalize(p.position), altPos: (p.altPositions ?? []).map { PositionNormalizer.normalize($0) }, score: playersPoints[pid] ?? 0.0))
                continue
            }
            if let compact = league?.ownedPlayers?[pid] {
                let base = PositionNormalizer.normalize(compact.position ?? "UNK")
                let alts = (compact.fantasyPositions ?? []).map { PositionNormalizer.normalize($0) }
                candidates.append((id: pid, basePos: base, altPos: alts, score: playersPoints[pid] ?? 0.0))
                continue
            }
            if let teamHist = league?.teamHistoricalPlayers?[seasonTeam?.id ?? ""]?[pid] {
                let base = PositionNormalizer.normalize(teamHist.lastKnownPosition ?? "UNK")
                candidates.append((id: pid, basePos: base, altPos: [], score: playersPoints[pid] ?? 0.0))
                continue
            }
            if let raw = playerCache[pid] {
                let base = PositionNormalizer.normalize(raw.position ?? "UNK")
                let alts = (raw.fantasy_positions ?? []).map { PositionNormalizer.normalize($0) }
                candidates.append((id: pid, basePos: base, altPos: alts, score: playersPoints[pid] ?? 0.0))
                continue
            }
            candidates.append((id: pid, basePos: PositionNormalizer.normalize("UNK"), altPos: [], score: playersPoints[pid] ?? 0.0))
        }

        var strictSlots: [String] = []
        var flexSlots: [String] = []
        for slot in startingSlots {
            let allowed = allowedPositions(for: slot)
            if allowed.count == 1 && !isIDPFlex(slot) && !offensiveFlexSlots.contains(slot.uppercased()) {
                strictSlots.append(slot)
            } else {
                flexSlots.append(slot)
            }
        }
        let optimalOrder = strictSlots + flexSlots

        var used = Set<String>()
        var maxTotal = 0.0
        var actualTotal = 0.0

        // Attempt to compute actualTotal using entry.players_points for starters preferentially.
        // We will attempt to augment playersPoints when starter ids missing (limited search).
        var mutablePlayersPoints = playersPoints
        var unresolvedStarterIds: [String] = []
        if let starters = entry.starters {
            for pid in starters where pid != "0" {
                if let val = mutablePlayersPoints[pid] {
                    actualTotal += val
                } else {
                    // try to find weeklyScores across league seasons but limited to this pid only
                    var found = false
                    if let lg = league {
                        for season in lg.seasons {
                            for sTeam in season.teams {
                                if let p = sTeam.roster.first(where: { $0.id == pid }),
                                   let ws = p.weeklyScores.first(where: { $0.week == week }) {
                                    let v = ws.points_half_ppr ?? ws.points
                                    mutablePlayersPoints[pid] = v
                                    actualTotal += v
                                    found = true
                                    break
                                }
                            }
                            if found { break }
                        }
                    }
                    if !found { unresolvedStarterIds.append(pid) }
                }
            }
        }

        // If unresolved starters remain but the entry scalar points is present, prefer the authoritative scalar
        if !unresolvedStarterIds.isEmpty, let entryScalar = entry.points {
            let epsilon = 0.01
            let diff = abs(entryScalar - actualTotal)
            if diff > epsilon {
                // Use entryScalar as actual total to guarantee parity with Sleeper
                actualTotal = entryScalar
            }
        }

        for slot in optimalOrder {
            let allowed = allowedPositions(for: slot)
            let pool = candidates.filter { c in !used.contains(c.id) && (allowed.contains(c.basePos) || !allowed.intersection(Set(c.altPos)).isEmpty) }
            if let pick = pool.max(by: { $0.score < $1.score }) {
                used.insert(pick.id)
                maxTotal += pick.score
            }
        }

        // If maxTotal is zero (no usable candidates), return nil-like behavior by returning zeros
        if maxTotal <= 0 { return (actualTotal, 0, 0, 0, 0, 0) }
        // We return mgmt% in older API, but here callers expect totals; keep consistent
        return (actualTotal / maxTotal) * 100.0
    }

    // MARK: - Private helpers (encapsulated)

    /// Main worker: compute totals using a provided playersPoints map.
    /// IMPORTANT: do not let playersPoints.keys expand to entire-season players unless those ids are relevant.
    private static func computeUsingMatchupEntry(team: TeamStanding, entry: MatchupEntry, playersPoints: [String: Double], league: LeagueData?, leagueManager: SleeperLeagueManager, week: Int) -> (Double, Double, Double, Double, Double, Double) {
        let playerCache = leagueManager.playerCache ?? [:]

        // Build idSet targeted to the matchup/team context
        var idSet = Set<String>()
        if let players = entry.players { idSet.formUnion(players) }
        if let starters = entry.starters { idSet.formUnion(starters) }
        idSet.formUnion(team.roster.map { $0.id })
        // Include keys of playersPoints if they were supplied intentionally (but be careful)
        // We'll only use playersPoints keys if they seem relevant: intersection with team/entry/league caches
        // This prevents a full-season playersPoints map from expanding idSet blindly.
        let playersPointsKeys = Set(playersPoints.keys)
        // If there's any overlap with our known caches, include only those overlaps; otherwise include playersPoints keys
        // but prefer to limit — pragmatic compromise:
        var includePPKeys = Set<String>()
        includePPKeys.formUnion(playersPointsKeys.intersection(idSet))
        if includePPKeys.isEmpty {
            // Try intersection with league compact caches
            if let owned = league?.ownedPlayers?.keys {
                includePPKeys.formUnion(playersPointsKeys.intersection(Set(owned)))
            }
            if includePPKeys.isEmpty {
                if let th = league?.teamHistoricalPlayers?[team.id]?.keys {
                    includePPKeys.formUnion(playersPointsKeys.intersection(Set(th)))
                }
            }
            // Last resort: if playersPointsKeys are starters/entry players, include them
            includePPKeys.formUnion(playersPointsKeys.intersection((entry.players ?? []) + (entry.starters ?? [])))
        }
        idSet.formUnion(includePPKeys)

        // Local mutable copy we may augment for missing ids in idSet (only those ids)
        var mutablePlayersPoints = playersPoints

        // AUGMENT playersPoints for any ids in idSet that are missing a score by scanning league seasons
        if let lg = league {
            // Preference: scan season that likely contains the matchup (season that includes team first)
            var seasonsToScan = lg.seasons
            if let containing = lg.seasons.first(where: { $0.teams.contains(where: { $0.id == team.id }) }) {
                seasonsToScan.removeAll { $0.id == containing.id }
                seasonsToScan.insert(containing, at: 0)
            }

            for season in seasonsToScan {
                for sTeam in season.teams {
                    for p in sTeam.roster {
                        if mutablePlayersPoints[p.id] == nil && idSet.contains(p.id) {
                            if let ws = p.weeklyScores.first(where: { $0.week == week }) {
                                mutablePlayersPoints[p.id] = ws.points_half_ppr ?? ws.points
                            }
                        }
                    }
                }
            }
        }

        // Build candidates using compact cache-aware lookup order
        let candidates: [(id: String, basePos: String, altPos: [String], score: Double)] = idSet.map { pid in
            if let p = team.roster.first(where: { $0.id == pid }) {
                return (id: pid, basePos: PositionNormalizer.normalize(p.position), altPos: (p.altPositions ?? []).map { PositionNormalizer.normalize($0) }, score: mutablePlayersPoints[pid] ?? 0.0)
            }
            if let compact = league?.ownedPlayers?[pid] {
                return (id: pid, basePos: PositionNormalizer.normalize(compact.position ?? "UNK"), altPos: (compact.fantasyPositions ?? []).map { PositionNormalizer.normalize($0) }, score: mutablePlayersPoints[pid] ?? 0.0)
            }
            if let teamHist = league?.teamHistoricalPlayers?[team.id]?[pid] {
                return (id: pid, basePos: PositionNormalizer.normalize(teamHist.lastKnownPosition ?? "UNK"), altPos: [], score: mutablePlayersPoints[pid] ?? 0.0)
            }
            if let raw = playerCache[pid] {
                return (id: pid, basePos: PositionNormalizer.normalize(raw.position ?? "UNK"), altPos: (raw.fantasy_positions ?? []).map { PositionNormalizer.normalize($0) }, score: mutablePlayersPoints[pid] ?? 0.0)
            }
            return (id: pid, basePos: PositionNormalizer.normalize("UNK"), altPos: [], score: mutablePlayersPoints[pid] ?? 0.0)
        }

        // Build starting slots
        var startingSlots: [String] = SlotUtils.sanitizeStartingSlots(league?.startingLineup ?? [])
        if startingSlots.isEmpty, let cfg = team.lineupConfig, !cfg.isEmpty {
            startingSlots = expandSlots(cfg)
        }

        var strictSlots: [String] = []
        var flexSlots: [String] = []
        for slot in startingSlots {
            let allowed = allowedPositions(for: slot)
            if allowed.count == 1 && !isIDPFlex(slot) && !offensiveFlexSlots.contains(slot.uppercased()) {
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
        var actualTotal = 0.0
        var actualOff = 0.0
        var actualDef = 0.0

        // Actual totals from starters: try playersPoints first, augment from seasons for missing starter ids
        var unresolvedStarterIds: [String] = []
        var mutableForActual = mutablePlayersPoints
        if let starters = entry.starters {
            for pid in starters where pid != "0" {
                if let score = mutableForActual[pid] {
                    actualTotal += score
                    // find position
                    let pPos: String = {
                        if let p = team.roster.first(where: { $0.id == pid }) { return p.position }
                        if let compact = league?.ownedPlayers?[pid], let pos = compact.position { return pos }
                        if let th = league?.teamHistoricalPlayers?[team.id]?[pid], let pos = th.lastKnownPosition { return pos }
                        if let raw = playerCache[pid], let pos = raw.position { return pos }
                        return "UNK"
                    }()
                    let norm = PositionNormalizer.normalize(pPos)
                    if ["QB","RB","WR","TE","K"].contains(norm) { actualOff += score }
                    else if ["DL","LB","DB"].contains(norm) { actualDef += score }
                    continue
                }

                // Try to find weeklyScores in seasons for this single pid
                var found = false
                if let lg = league {
                    for s in lg.seasons {
                        for sTeam in s.teams {
                            if let p = sTeam.roster.first(where: { $0.id == pid }), let ws = p.weeklyScores.first(where: { $0.week == week }) {
                                let v = ws.points_half_ppr ?? ws.points
                                mutableForActual[pid] = v
                                actualTotal += v
                                let norm = PositionNormalizer.normalize(p.position)
                                if ["QB","RB","WR","TE","K"].contains(norm) { actualOff += v }
                                else if ["DL","LB","DB"].contains(norm) { actualDef += v }
                                found = true
                                break
                            }
                        }
                        if found { break }
                    }
                }
                if !found { unresolvedStarterIds.append(pid) }
            }
        }

        // If unresolved starters and entry.points present, prefer entry.points
        if !unresolvedStarterIds.isEmpty, let entryScalar = entry.points {
            let epsilon = 0.01
            let diff = abs(entryScalar - actualTotal)
            if diff > epsilon {
                actualTotal = entryScalar
                // scale split proportionally if we had any known split
                let known = actualOff + actualDef
                if known > 0 {
                    let scale = actualTotal / known
                    actualOff *= scale
                    actualDef *= scale
                } else {
                    actualOff = actualTotal
                    actualDef = 0.0
                }
            }
        }

        // Greedy selection for max
        for slot in optimalOrder {
            let allowed = allowedPositions(for: slot)
            let pool = candidates.filter { c in !used.contains(c.id) && (allowed.contains(c.basePos) || !allowed.intersection(Set(c.altPos)).isEmpty) }
            if let pick = pool.max(by: { $0.score < $1.score }) {
                used.insert(pick.id)
                maxTotal += pick.score
                if ["QB","RB","WR","TE","K"].contains(pick.basePos) { maxOff += pick.score }
                else if ["DL","LB","DB"].contains(pick.basePos) { maxDef += pick.score }
            }
        }

        return (actualTotal, maxTotal, actualOff, maxOff, actualDef, maxDef)
    }

    private static func legacyRosterBasedManagement(team: TeamStanding, week: Int, league: LeagueData?, leagueManager: SleeperLeagueManager) -> (Double, Double, Double, Double, Double, Double) {
        // Build playerScores from roster weeklyScores
        var playerScores: [String: Double] = [:]
        for p in team.roster {
            if let s = p.weeklyScores.first(where: { $0.week == week }) {
                playerScores[p.id] = s.points_half_ppr ?? s.points
            }
        }
        let actualStarters = team.actualStartersByWeek?[week] ?? []
        let actualTotal = actualStarters.reduce(0.0) { $0 + (playerScores[$1] ?? 0.0) }

        let offPositions: Set<String> = ["QB","RB","WR","TE","K"]
        let actualOff = actualStarters.reduce(0.0) { sum, id in
            if let player = team.roster.first(where: { $0.id == id }), offPositions.contains(PositionNormalizer.normalize(player.position)) {
                return sum + (playerScores[id] ?? 0.0)
            } else {
                return sum
            }
        }
        let actualDef = actualTotal - actualOff

        var startingSlots = SlotUtils.sanitizeStartingSlots(league?.startingLineup ?? [])
        if startingSlots.isEmpty, let cfg = team.lineupConfig, !cfg.isEmpty {
            startingSlots = expandSlots(cfg)
        }

        let fixedCounts = fixedSlotCounts(startingSlots: startingSlots)
        let offPosSet: Set<String> = ["QB","RB","WR","TE","K"]
        var offPlayerList = team.roster.filter { offPosSet.contains(PositionNormalizer.normalize($0.position)) }.map {
            (id: $0.id, pos: PositionNormalizer.normalize($0.position), score: playerScores[$0.id] ?? 0.0)
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
        var defPlayerList = team.roster.filter { defPosSet.contains(PositionNormalizer.normalize($0.position)) }.map {
            (id: $0.id, pos: PositionNormalizer.normalize($0.position), score: playerScores[$0.id] ?? 0.0)
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

    // Small util helpers duplicated/embedded to avoid coupling
    private static func allowedPositions(for slot: String) -> Set<String> {
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

    private static func isIDPFlex(_ slot: String) -> Bool {
        let s = slot.uppercased()
        return s.contains("IDP") && s != "DL" && s != "LB" && s != "DB"
    }

    private static let offensiveFlexSlots: Set<String> = [
        "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE",
        "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX"
    ]

    private static let regularFlexSlots: Set<String> = ["FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE"]
    private static let superFlexSlots: Set<String> = ["SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX"]
    private static let idpFlexSlots: Set<String> = [
        "IDP", "IDPFLEX", "IDP_FLEX", "DFLEX", "DL_LB_DB", "DL_LB", "LB_DB", "DL_DB"
    ]

    private static func expandSlots(_ config: [String: Int]) -> [String] {
        let sanitized = SlotUtils.sanitizeStartingLineupConfig(config)
        return sanitized.flatMap { Array(repeating: $0.key, count: $0.value) }
    }

    private static func fixedSlotCounts(startingSlots: [String]) -> [String: Int] {
        startingSlots.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }
}
