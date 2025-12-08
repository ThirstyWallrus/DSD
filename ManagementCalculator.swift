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
        // If a league is provided, prefer the season containing the matchup/week for augmentation and candidate pool.
        if let lg = league {
            // Build an ordered seasons list that places the containing season first when possible.
            var seasonsOrdered: [SeasonData] = []
            if let containingSeason = lg.seasons.first(where: { season in
                // include seasons that have matchups for the requested week and include this team id
                (season.matchupsByWeek?[week] != nil) && season.teams.contains(where: { $0.id == team.id })
            }) {
                seasonsOrdered.append(containingSeason)
                seasonsOrdered.append(contentsOf: lg.seasons.filter { $0.id != containingSeason.id })
            } else {
                seasonsOrdered = lg.seasons
            }

            for season in seasonsOrdered {
                if let weeks = season.matchupsByWeek, let entries = weeks[week] {
                    if let entry = entries.first(where: { $0.roster_id == Int(team.id) }) {
                        // Found a matchup entry -> compute using entry.players_points preferentially
                        if let playersPoints = entry.players_points, !playersPoints.isEmpty {
                            // AUGMENT playersPoints but ONLY using the season-team roster for that matchup/week.
                            // ENFORCE: Only include players that were on this roster snapshot during this season/week.
                            var augmented = playersPoints // copy to mutate

                            // Determine the seasonTeam snapshot corresponding to this team in this season
                            guard let seasonTeam = season.teams.first(where: { $0.id == String(entry.roster_id) }) else {
                                // Fall back to computeUsingMatchupEntry which will itself try to be conservative.
                                return computeUsingMatchupEntry(team: team, entry: entry, playersPoints: augmented, league: lg, leagueManager: leagueManager, week: week)
                            }

                            // Build roster ids for this season/team (these are the only eligible players for MAX)
                            let rosterIds = Set(seasonTeam.roster.map { $0.id })
                            let startersSet = Set(entry.starters ?? [])

                            // Augment: only take weeklyScores from the seasonTeam's roster and only for rosterIds.
                            for p in seasonTeam.roster {
                                if augmented[p.id] == nil {
                                    // If player marked IR/TAXI and NOT a starter, skip augmenting them for max eligibility.
                                    // => USE NEW explicitIRorTaxiFromRoster helper so IR and TAXI detection are distinct and explicit
                                    let isIRorTaxi = explicitIRorTaxiFromRoster(player: p, entry: entry, league: lg, leagueManager: leagueManager)
                                    if isIRorTaxi && !startersSet.contains(p.id) { continue }
                                    if let ws = p.weeklyScores.first(where: { $0.week == week }) {
                                        augmented[p.id] = ws.points_half_ppr ?? ws.points
                                    }
                                }
                            }

                            // IMPORTANT: do NOT scan other seasons for augmentation. The requirement is strict:
                            // Only players that were on that roster during that matchup/week are eligible for Max.
                            return computeUsingMatchupEntry(team: team, entry: entry, playersPoints: augmented, league: lg, leagueManager: leagueManager, week: week)
                        } else {
                            // No players_points present: build a fallback map from THIS season's team roster ONLY.
                            // Only include players who were on that roster snapshot during the week.
                            var fallback: [String: Double] = [:]
                            guard let seasonTeam = season.teams.first(where: { $0.id == String(entry.roster_id) }) else {
                                break
                            }
                            let startersSet = Set(entry.starters ?? [])
                            for p in seasonTeam.roster {
                                // Exclude IR/TAXI players from fallback unless they are starters
                                let isIRorTaxi = explicitIRorTaxiFromRoster(player: p, entry: entry, league: lg, leagueManager: leagueManager)
                                if isIRorTaxi && !startersSet.contains(p.id) { continue }
                                if let ws = p.weeklyScores.first(where: { $0.week == week }) {
                                    fallback[p.id] = ws.points_half_ppr ?? ws.points
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

        // Legacy roster-based computation (fallback) — uses the TeamStanding.roster as best-effort
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

        // EXTENDED FALLBACK: If still empty and we have a league, scan seasons but LIMIT to the season/team roster that contains this matchup.
        if playersPoints.isEmpty, let lg = league {
            // Find the season that contains this matchup entry (if any)
            if let seasonContaining = lg.seasons.first(where: { season in
                season.matchupsByWeek?[week]?.contains(where: { $0.roster_id == entry.roster_id }) ?? false
            }), let seasonTeam = seasonContaining.teams.first(where: { $0.id == String(entry.roster_id) }) {
                let startersSet = Set(entry.starters ?? [])
                for p in seasonTeam.roster {
                    // Exclude IR/TAXI unless starter
                    let isIRorTaxi = explicitIRorTaxiFromRoster(player: p, entry: entry, league: lg, leagueManager: leagueManager)
                    if isIRorTaxi && !startersSet.contains(p.id) { continue }
                    if playersPoints[p.id] == nil, let s = p.weeklyScores.first(where: { $0.week == week }) {
                        playersPoints[p.id] = s.points_half_ppr ?? s.points
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
        // IMPORTANT: Only include players that were on the seasonTeam roster for that matchup/week.
        // We assemble pidSet from playersPoints keys intersected with seasonTeam.roster (if available), else fallback to playersPoints keys.
        var pidSet = Set(playersPoints.keys)
        if let lg = league {
            if let seasonContaining = lg.seasons.first(where: { season in
                season.matchupsByWeek?[week]?.contains(where: { $0.roster_id == entry.roster_id }) ?? false
            }), let seasonTeam = seasonContaining.teams.first(where: { $0.id == String(entry.roster_id) }) {
                let rosterIds = Set(seasonTeam.roster.map { $0.id })
                pidSet.formIntersection(rosterIds)
                // If intersection empties but starters are listed, prefer starters restricted to roster
                let startersInRoster = Set(entry.starters ?? []).intersection(rosterIds)
                pidSet.formUnion(startersInRoster)
            }
        }

        // Fallback: if pidSet ended empty (odd case), use playersPoints keys directly (defensive)
        if pidSet.isEmpty { pidSet = Set(playersPoints.keys) }

        // Build candidate array restricted to pidSet
        var candidates: [(id: String, basePos: String, altPos: [String], score: Double)] = []
        for pid in pidSet {
            if let p = seasonTeamFor(entry: entry, league: league)?.roster.first(where: { $0.id == pid }) {
                candidates.append((id: pid, basePos: PositionNormalizer.normalize(p.position), altPos: (p.altPositions ?? []).map { PositionNormalizer.normalize($0) }, score: playersPoints[pid] ?? 0.0))
                continue
            }
            if let compact = league?.ownedPlayers?[pid] {
                let base = PositionNormalizer.normalize(compact.position ?? "UNK")
                let alts = (compact.fantasyPositions ?? []).map { PositionNormalizer.normalize($0) }
                candidates.append((id: pid, basePos: base, altPos: alts, score: playersPoints[pid] ?? 0.0))
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
        // We will attempt to augment playersPoints for missing starter ids only from the seasonTeam roster.
        var mutablePlayersPoints = playersPoints
        var unresolvedStarterIds: [String] = []
        if let starters = entry.starters {
            for pid in starters where pid != "0" {
                if let val = mutablePlayersPoints[pid] {
                    actualTotal += val
                } else {
                    // try to find weeklyScores in seasonTeam roster only
                    var found = false
                    if let lg = league {
                        if let seasonContaining = lg.seasons.first(where: { season in
                            season.matchupsByWeek?[week]?.contains(where: { $0.roster_id == entry.roster_id }) ?? false
                        }), let seasonTeam = seasonContaining.teams.first(where: { $0.id == String(entry.roster_id) }) {
                            if let p = seasonTeam.roster.first(where: { $0.id == pid }), let ws = p.weeklyScores.first(where: { $0.week == week }) {
                                let v = ws.points_half_ppr ?? ws.points
                                mutablePlayersPoints[pid] = v
                                actualTotal += v
                                found = true
                            }
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

        // If maxTotal is zero (no usable candidates), return nil so caller knows percent couldn't be computed
        if maxTotal <= 0 { return nil }
        // Return management percentage
        return (actualTotal / maxTotal) * 100.0
    }

    // MARK: - Private helpers (encapsulated)

    /// Main worker: compute totals using a provided playersPoints map.
    /// IMPORTANT: Candidate pool is strictly limited to players that were on the seasonTeam roster
    /// for the matchup/week. Do not include players from other teams or other seasons.
    private static func computeUsingMatchupEntry(team: TeamStanding, entry: MatchupEntry, playersPoints: [String: Double], league: LeagueData?, leagueManager: SleeperLeagueManager, week: Int) -> (Double, Double, Double, Double, Double, Double) {
        let playerCache = leagueManager.playerCache ?? [:]

        // Determine seasonTeam (season snapshot) containing this matchup entry if possible
        let seasonContaining = league.flatMap { lg in
            lg.seasons.first(where: { season in
                season.matchupsByWeek?[week]?.contains(where: { $0.roster_id == entry.roster_id }) ?? false
            })
        }
        let seasonTeam = seasonContaining?.teams.first(where: { $0.id == String(entry.roster_id) })

        // If we have a seasonTeam, eligible roster IDs for MAX are exactly that roster's player ids.
        var eligibleRosterIds: Set<String> = []
        if let sTeam = seasonTeam {
            eligibleRosterIds = Set(sTeam.roster.map { $0.id })
        } else {
            // Fallback: use the provided TeamStanding.roster (best-effort)
            eligibleRosterIds = Set(team.roster.map { $0.id })
        }

        // Build idSet targeted to the roster snapshot --- ONLY players present on that roster snapshot are eligible.
        // Also allow inclusion of starters from entry if they are present in eligibleRosterIds.
        var idSet = eligibleRosterIds
        if let starters = entry.starters {
            idSet.formUnion(starters.filter { eligibleRosterIds.contains($0) })
        }
        if let players = entry.players {
            idSet.formUnion(players.filter { eligibleRosterIds.contains($0) })
        }
        // Also include any playersPoints keys that appear in the roster (defensive)
        idSet.formUnion(Set(playersPoints.keys).intersection(eligibleRosterIds))

        // Local mutable copy we may augment for missing ids in idSet (only those ids)
        var mutablePlayersPoints = playersPoints

        // AUGMENT playersPoints for any ids in idSet that are missing a score by scanning the seasonTeam roster only
        if let sTeam = seasonTeam {
            let startersSet = Set(entry.starters ?? [])
            for p in sTeam.roster {
                if idSet.contains(p.id), mutablePlayersPoints[p.id] == nil {
                    // Skip augment for Taxi/IR players unless they are starters (policy)
                    if explicitIRorTaxiFromRoster(player: p, entry: entry, league: league, leagueManager: leagueManager) && !startersSet.contains(p.id) {
                        continue
                    }
                    if let ws = p.weeklyScores.first(where: { $0.week == week }) {
                        mutablePlayersPoints[p.id] = ws.points_half_ppr ?? ws.points
                    }
                }
            }
        } else {
            // If no seasonTeam available, attempt to augment from provided team.roster but still limit to idSet
            for p in team.roster where idSet.contains(p.id) {
                if mutablePlayersPoints[p.id] == nil, let ws = p.weeklyScores.first(where: { $0.week == week }) {
                    mutablePlayersPoints[p.id] = ws.points_half_ppr ?? ws.points
                }
            }
        }

        // Build candidates using compact cache-aware lookup order, but only for ids in idSet
        let candidates: [(id: String, basePos: String, altPos: [String], score: Double)] = idSet.compactMap { pid in
            // Exclude IR/TAXI players from candidates unless they are starters (this preserves earlier policy)
            let startersSet = Set(entry.starters ?? [])
            if explicitIRorTaxi(pid: pid, entry: entry, seasonTeam: seasonTeam, league: league, leagueManager: leagueManager) && !startersSet.contains(pid) {
                return nil
            }

            if let p = seasonTeam?.roster.first(where: { $0.id == pid }) {
                return (id: pid, basePos: PositionNormalizer.normalize(p.position), altPos: (p.altPositions ?? []).map { PositionNormalizer.normalize($0) }, score: mutablePlayersPoints[pid] ?? 0.0)
            }
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

        // Actual totals from starters: try playersPoints first, augment from seasonTeam roster for missing starter ids
        var unresolvedStarterIds: [String] = []
        var mutableForActual = mutablePlayersPoints
        if let starters = entry.starters {
            for pid in starters where pid != "0" {
                if let score = mutableForActual[pid] {
                    actualTotal += score
                    // find position using compact caches before global cache
                    let pPos: String = {
                        if let p = seasonTeam?.roster.first(where: { $0.id == pid }) { return p.position }
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

                // Secondary: try to augment playersPoints from seasonTeam roster only
                var found = false
                if let sTeam = seasonTeam {
                    if let p = sTeam.roster.first(where: { $0.id == pid }), let ws = p.weeklyScores.first(where: { $0.week == week }) {
                        let v = ws.points_half_ppr ?? ws.points
                        mutablePlayersPoints[pid] = v
                        actualTotal += v
                        let norm = PositionNormalizer.normalize(p.position)
                        if ["QB","RB","WR","TE","K"].contains(norm) { actualOff += v }
                        else if ["DL","LB","DB"].contains(norm) { actualDef += v }
                        found = true
                    }
                }
                if !found {
                    unresolvedStarterIds.append(pid)
                }
            }
        }

        // If unresolved starters remain but the entry scalar points exists, prefer entry.points as authoritative for actualTotal.
        if !unresolvedStarterIds.isEmpty, let entryScalar = entry.points {
            let epsilon = 0.01
            let diff = abs(entryScalar - actualTotal)
            if diff > epsilon {
                let formattedResolved = String(format: "%.2f", actualTotal)
                let formattedEntry = String(format: "%.2f", entryScalar)
                print("[ManagementCalculator] WARNING: incomplete players_points for matchup; using entry.points as authoritative. week=\(week) team=\(team.name) roster=\(team.id) unresolvedStarterIds=\(unresolvedStarterIds) sumResolved=\(formattedResolved) entry.points=\(formattedEntry)")
                // Replace actualTotal with the authoritative entry scalar
                actualTotal = entryScalar

                // To preserve the offensive/defensive split as best-effort:
                // - If we have any resolved actualOff/actualDef we will scale them proportionally
                //   such that actualOff + actualDef == actualTotal while preserving known ratio.
                let knownSplit = actualOff + actualDef
                if knownSplit > 0 {
                    let scale = actualTotal / knownSplit
                    actualOff *= scale
                    actualDef *= scale
                } else {
                    // No resolved split information (all starters missing positions/scores). Best-effort default:
                    // assign entire actualTotal to actualOff (conservative) then actualDef = 0
                    actualOff = actualTotal
                    actualDef = 0.0
                }

                // Log the adjustment
                let fmtOff = String(format: "%.2f", actualOff)
                let fmtDef = String(format: "%.2f", actualDef)
                print("[ManagementCalculator] INFO: adjusted actualOff=\(fmtOff) actualDef=\(fmtDef) to match authoritative total")
            }
        }

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

    // MARK: - Helper utilities used above

    /// Return the SeasonData.team snapshot that contains `entry` if available
    private static func seasonTeamFor(entry: MatchupEntry, league: LeagueData?) -> TeamStanding? {
        guard let lg = league else { return nil }
        for season in lg.seasons {
            if let weeks = season.matchupsByWeek, weeks.keys.contains(where: { _ in true }) {
                if let entries = season.matchupsByWeek?.values.flatMap({ $0 }), entries.contains(where: { $0.roster_id == entry.roster_id }) {
                    return season.teams.first(where: { $0.id == String(entry.roster_id) })
                }
            }
        }
        return nil
    }

    // ---- NEW: Explicit IR / TAXI detection helpers ----
    // These helpers intentionally distinguish IR and TAXI tokens so callers can treat them differently.
    // They search (in order):
    //   1) entry.players_slots mapping (if present) — most authoritative for a given matchup
    //   2) player's altPositions / position tokens (roster snapshot)
    //   3) compact league caches and teamHistoricalPlayers as a last resort
    //
    // All token checks are case-insensitive. They look for substring matches ("IR", "INJ", "TAXI") to be robust.

    /// Detect if a Player (roster snapshot) is an IR-designated player for this matchup entry.
    private static func explicitIRFromRoster(player: Player, entry: MatchupEntry, league: LeagueData?, leagueManager: SleeperLeagueManager) -> Bool {
        // 1) entry.players_slots
        if let rawMap = entry.players_slots, let token = rawMap[player.id] {
            let up = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if up.contains("IR") || up.contains("INJ") { return true }
        }
        // 2) player's own altPositions / position tokens
        let checks = ([player.position] + (player.altPositions ?? [])).compactMap { $0 }.map { $0.uppercased() }
        for c in checks {
            if c.contains("IR") || c.contains("INJ") { return true }
        }
        // 3) fallthrough to caches is not performed here because we operate strictly from roster snapshot
        return false
    }

    /// Detect if a Player (roster snapshot) is a TAXI-designated (taxi squad) player for this matchup entry.
    private static func explicitTaxiFromRoster(player: Player, entry: MatchupEntry, league: LeagueData?, leagueManager: SleeperLeagueManager) -> Bool {
        // 1) entry.players_slots
        if let rawMap = entry.players_slots, let token = rawMap[player.id] {
            let up = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if up.contains("TAXI") || up.contains("TAX") { return true }
        }
        // 2) player's own altPositions / position tokens
        let checks = ([player.position] + (player.altPositions ?? [])).compactMap { $0 }.map { $0.uppercased() }
        for c in checks {
            if c.contains("TAXI") || c.contains("TAX") { return true }
        }
        return false
    }

    /// Wrapper: returns true if player is IR or TAXI according to roster snapshot / entry mapping.
    private static func explicitIRorTaxiFromRoster(player: Player, entry: MatchupEntry, league: LeagueData?, leagueManager: SleeperLeagueManager) -> Bool {
        return explicitIRFromRoster(player: player, entry: entry, league: league, leagueManager: leagueManager)
            || explicitTaxiFromRoster(player: player, entry: entry, league: league, leagueManager: leagueManager)
    }

    /// Slightly more general check by id (used when we only have id and not Player).
    /// Checks (in order):
    ///   1) entry.players_slots mapping
    ///   2) seasonTeam roster altPositions
    ///   3) league compact caches
    ///   4) global player cache
    private static func explicitIR(pid: String, entry: MatchupEntry, seasonTeam: TeamStanding?, league: LeagueData?, leagueManager: SleeperLeagueManager) -> Bool {
        // 1) entry.players_slots
        if let map = entry.players_slots, let raw = map[pid] {
            let up = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if up.contains("IR") || up.contains("INJ") { return true }
        }
        // 2) seasonTeam roster altPositions
        if let sTeam = seasonTeam, let p = sTeam.roster.first(where: { $0.id == pid }) {
            let checks = ([p.position] + (p.altPositions ?? [])).compactMap { $0 }.map { $0.uppercased() }
            for c in checks { if c.contains("IR") || c.contains("INJ") { return true } }
        }
        // 3) league compact caches
        if let lg = league {
            if let comp = lg.ownedPlayers?[pid], let pos = comp.position?.uppercased(), pos.contains("IR") || pos.contains("INJ") { return true }
            if let th = lg.teamHistoricalPlayers?[String(entry.roster_id)]?[pid], let pos = th.lastKnownPosition?.uppercased(), (pos.contains("IR") || pos.contains("INJ")) { return true }
        }
        // 4) global player cache
        if let raw = leagueManager.playerCache?[pid], let pos = raw.position?.uppercased(), pos.contains("IR") || pos.contains("INJ") { return true }
        return false
    }

    private static func explicitTaxi(pid: String, entry: MatchupEntry, seasonTeam: TeamStanding?, league: LeagueData?, leagueManager: SleeperLeagueManager) -> Bool {
        // 1) entry.players_slots
        if let map = entry.players_slots, let raw = map[pid] {
            let up = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if up.contains("TAXI") || up.contains("TAX") { return true }
        }
        // 2) seasonTeam roster altPositions
        if let sTeam = seasonTeam, let p = sTeam.roster.first(where: { $0.id == pid }) {
            let checks = ([p.position] + (p.altPositions ?? [])).compactMap { $0 }.map { $0.uppercased() }
            for c in checks { if c.contains("TAXI") || c.contains("TAX") { return true } }
        }
        // 3) league compact caches
        if let lg = league {
            if let comp = lg.ownedPlayers?[pid], let pos = comp.position?.uppercased(), pos.contains("TAXI") || pos.contains("TAX") { return true }
            if let th = lg.teamHistoricalPlayers?[String(entry.roster_id)]?[pid], let pos = th.lastKnownPosition?.uppercased(), (pos.contains("TAXI") || pos.contains("TAX")) { return true }
        }
        // 4) global player cache
        if let raw = leagueManager.playerCache?[pid], let pos = raw.position?.uppercased(), pos.contains("TAXI") || pos.contains("TAX") { return true }
        return false
    }

    /// Wrapper: true if pid is either IR or TAXI using the id-based checks
    private static func explicitIRorTaxi(pid: String, entry: MatchupEntry, seasonTeam: TeamStanding?, league: LeagueData?, leagueManager: SleeperLeagueManager) -> Bool {
        return explicitIR(pid: pid, entry: entry, seasonTeam: seasonTeam, league: league, leagueManager: leagueManager)
            || explicitTaxi(pid: pid, entry: entry, seasonTeam: seasonTeam, league: league, leagueManager: leagueManager)
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
