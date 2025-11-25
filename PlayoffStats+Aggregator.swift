//
//  PlayoffStats+Aggregator.swift
//
//  PATCHED: All defensive position usages now pass through PositionNormalizer.normalize(_).
//  FIXED: Use SleeperMatchup.week when available (fallback to inference when nil).
//

import Foundation

// MARK: - Import PositionNormalizer globally
import Foundation

private let offensivePositions: Set<String> = ["QB", "RB", "WR", "TE", "K"]
private let defensivePositions: Set<String> = ["DL", "LB", "DB"]

private func isOffensiveSlot(_ slot: String) -> Bool {
    let u = PositionNormalizer.normalize(slot)
    let defSlots: Set<String> = ["DL", "LB", "DB", "IDP", "DEF"]
    return !defSlots.contains(u)
}

// Helper: infer week for a SleeperMatchup within a SeasonData (returns nil if not found)
private func inferWeekForMatchup(_ matchup: SleeperMatchup, in season: SeasonData) -> Int? {
    if let w = matchup.week { return w }
    guard let map = season.matchupsByWeek else { return nil }
    for (wk, entries) in map {
        if entries.contains(where: { $0.matchup_id == matchup.matchupId }) {
            return wk
        }
    }
    return nil
}

// MARK: - Main Bracket Playoff Matchup Helper
private func mainBracketPlayoffMatchups(
    for ownerId: String,
    in season: SeasonData,
    matchups: [SleeperMatchup]
) -> [SleeperMatchup] {
    guard let team = season.teams.first(where: { $0.ownerId == ownerId }),
          let playoffTeamsCount = season.playoffTeamsCount,
          let playoffStartWeek = season.playoffStartWeek else {
        return []
    }
    let playoffSeededTeams = season.teams
        .sorted { $0.leagueStanding < $1.leagueStanding }
        .prefix(playoffTeamsCount)
        .compactMap { Int($0.id) }
    let teamRosterId = Int(team.id) ?? -1

    // Number of rounds (ceil log2 for cases with byes)
    let rounds = Int(ceil(log2(Double(playoffTeamsCount))))
    let playoffWeeks = Set(playoffStartWeek..<(playoffStartWeek + rounds))

    var result: [SleeperMatchup] = []
    var eliminated = false

    // Updated for correct SleeperMatchup model
    let candidateMatchups = matchups
        .filter {
            let wk = $0.week ?? $0.matchupId
            return playoffWeeks.contains(wk)
        }
        .filter { $0.rosterId == teamRosterId || ($0.starters.contains { _ in true }) }
        // NOTE: if your SleeperMatchup model has a `week` property, you should use that instead of matchupId above

    // Sorting by explicit week (if present) then matchupId
    let sortedMatchups = candidateMatchups.sorted {
        let a = $0.week ?? $0.matchupId
        let b = $1.week ?? $1.matchupId
        if a != b { return a < b }
        return $0.matchupId < $1.matchupId
    }

    for matchup in sortedMatchups {
        if eliminated { break }
        result.append(matchup)
        // WIN/LOSS detection --
        // If you have points as a Double (not [Double]), use direct comparison
        let myPoints = matchup.points
        let oppPoints = matchup.customPoints ?? 0.0 // Use customPoints if present, or 0 as placeholder
        if myPoints < oppPoints { eliminated = true }
    }
    return result
}

extension PlayoffStats {
    static func aggregate(
        ownerId: String,
        league: LeagueData,
        allMatchups: [SleeperMatchup],
        playoffStartWeekDefault: Int = 14,
        playerCache: [String: RawSleeperPlayer]
    ) -> PlayoffStats {
        var pointsFor = 0.0
        var maxPointsFor = 0.0
        var offensivePointsFor = 0.0
        var maxOffensivePointsFor = 0.0
        var defensivePointsFor = 0.0
        var maxDefensivePointsFor = 0.0
        var gamesPlayed = 0
        var wins = 0
        var losses = 0
        var isChampion = false

        for season in league.seasons {
            guard let team = season.teams.first(where: { $0.ownerId == ownerId }) else { continue }
            let playoffTeamsCount = season.playoffTeamsCount ?? 4
            let playoffSeededTeams = season.teams.sorted { $0.leagueStanding < $1.leagueStanding }
                .prefix(playoffTeamsCount)
            guard playoffSeededTeams.contains(where: { $0.ownerId == ownerId }) else { continue }

            // Determine playoff start week as before
            let allWeeks = team.weeklyActualLineupPoints?.keys.sorted() ?? []
            let maxWeek = allWeeks.max() ?? 13
            let assumedPlayoffRounds = Int(log2(Double(playoffTeamsCount)))
            let fallbackPlayoffStartWeek = maxWeek - (assumedPlayoffRounds - 1)
            _ = season.playoffStartWeek ?? fallbackPlayoffStartWeek

            let lineupConfig = team.lineupConfig ?? [:]
            var expandedSlots: [String] = []
            for (key, value) in lineupConfig {
                expandedSlots.append(contentsOf: Array(repeating: key, count: value))
            }

            let teamRosterId = Int(team.id) ?? -1

            // --- PATCH: Use only main bracket playoff games for this team/season ---
            let seasonMatchups = mainBracketPlayoffMatchups(
                for: ownerId,
                in: season,
                matchups: allMatchups
            )

            // Sorting by week (prefer explicit week when available)
            let playoffMatchups = seasonMatchups.sorted { ($0.week ?? $0.matchupId) < ($1.week ?? $1.matchupId) }

            var eliminated = false // Defensive, but already handled in helper

            for matchup in playoffMatchups {
                // If already eliminated, skip further games
                if eliminated { break }

                // Determine the week for this matchup (prefer explicit week)
                let week = matchup.week ?? inferWeekForMatchup(matchup, in: season) ?? matchup.matchupId

                // Fetch myEntry
                let weekMatchups = season.matchupsByWeek?[week] ?? []
                guard let myEntry = weekMatchups.first(where: { $0.roster_id == teamRosterId }) else { continue }

                // Points for (total)
                let pf = myEntry.points ?? 0.0
                pointsFor += pf
                gamesPlayed += 1

                // Compute opf and dpf using slots primarily
                guard let starters = myEntry.starters,
                      let playersPoints = myEntry.players_points else { continue }
                let starterPoints: [Double] = starters.compactMap { playersPoints[$0] }
                guard starters.count == starterPoints.count else { continue }

                var opf = 0.0
                var dpf = 0.0
                let slots = expandedSlots
                if slots.count == starters.count {
                    for i in 0..<starters.count {
                        let pts = starterPoints[i]
                        let normalizedSlot = PositionNormalizer.normalize(slots[i])
                        if isOffensiveSlot(slots[i]) {
                            opf += pts
                        } else if defensivePositions.contains(normalizedSlot) {
                            dpf += pts
                        }
                    }
                } else {
                    // Fallback to position
                    for i in 0..<starters.count {
                        let pid = starters[i]
                        let pts = starterPoints[i]
                        let player: Player? = {
                            if let rawPlayer = playerCache[pid], let pos = rawPlayer.position {
                                // Map from RawSleeperPlayer to Player model
                                return Player(
                                    id: pid,
                                    position: pos,
                                    altPositions: rawPlayer.fantasy_positions,
                                    weeklyScores: []
                                )
                            }
                            return team.roster.first { $0.id == pid }
                        }()
                        if let pos = player?.position {
                            let normalizedPos = PositionNormalizer.normalize(pos)
                            if offensivePositions.contains(normalizedPos) {
                                opf += pts
                            } else if defensivePositions.contains(normalizedPos) {
                                dpf += pts
                            }
                        }
                    }
                }
                offensivePointsFor += opf
                defensivePointsFor += dpf

                // --- OPTIMALS ---
                let candidates: [(
                    id: String,
                    basePos: String,
                    altPositions: [String],
                    points: Double
                )] = team.roster.compactMap { player in
                    guard let ws = player.weeklyScores.first(where: { $0.week == week }) else { return nil }
                    let normBase = PositionNormalizer.normalize(player.position)
                    let normAlt = (player.altPositions ?? []).map { PositionNormalizer.normalize($0) }
                    return (
                        id: player.id,
                        basePos: normBase,
                        altPositions: normAlt,
                        points: ws.points_half_ppr ?? ws.points
                    )
                }
                var usedPlayerIDs = Set<String>()
                var weekMaxTotal = 0.0
                var weekMaxOff = 0.0
                var weekMaxDef = 0.0

                for slot in slots {
                    let allowed: Set<String>
                    switch PositionNormalizer.normalize(slot) {
                        case "QB", "RB", "WR", "TE", "K", "DL", "LB", "DB": allowed = [PositionNormalizer.normalize(slot)]
                        case "FLEX", "WRRB", "WRRBTE", "WRRB_TE", "RBWR", "RBWRTE": allowed = ["RB", "WR", "TE"]
                        case "SUPER_FLEX", "QBRBWRTE", "QBRBWR", "QBSF", "SFLX": allowed = ["QB", "RB", "WR", "TE"]
                        case "IDP": allowed = ["DL", "LB", "DB"]
                        default: allowed = [PositionNormalizer.normalize(slot)]
                    }
                    let pick = candidates
                        .filter { !usedPlayerIDs.contains($0.id) && (allowed.contains($0.basePos) || !Set($0.altPositions).intersection(allowed).isEmpty) }
                        .max(by: { $0.points < $1.points })
                    guard let cand = pick else { continue }
                    usedPlayerIDs.insert(cand.id)
                    weekMaxTotal += cand.points
                    if offensivePositions.contains(cand.basePos) { weekMaxOff += cand.points }
                    else if defensivePositions.contains(cand.basePos) { weekMaxDef += cand.points }
                }
                maxPointsFor += weekMaxTotal
                maxOffensivePointsFor += weekMaxOff
                maxDefensivePointsFor += weekMaxDef

                // --- WIN/LOSS Detection ---
                let myPoints = matchup.points
                let oppPoints = matchup.customPoints ?? 0.0
                if myPoints > oppPoints { wins += 1 }
                else { losses += 1 }

                // If team lost this round, they're eliminated from the main bracket
                if myPoints < oppPoints { eliminated = true }
            }

            // Champion: Use explicit Sleeper field
            if let champ = team.championships, champ > 0 {
                isChampion = true
            } else if gamesPlayed > 0 && losses == 0 {
                isChampion = true
            }
        }

        let mgmtPercent = maxPointsFor > 0 ? (pointsFor / maxPointsFor) * 100 : nil
        let offMgmtPercent = maxOffensivePointsFor > 0 ? (offensivePointsFor / maxOffensivePointsFor) * 100 : nil
        let defMgmtPercent = maxDefensivePointsFor > 0 ? (defensivePointsFor / maxDefensivePointsFor) * 100 : nil
        let ppw = gamesPlayed > 0 ? pointsFor / Double(gamesPlayed) : 0
        let oppw = gamesPlayed > 0 ? offensivePointsFor / Double(gamesPlayed) : 0
        let dppw = gamesPlayed > 0 ? defensivePointsFor / Double(gamesPlayed) : 0

        return PlayoffStats(
            pointsFor: pointsFor,
            maxPointsFor: maxPointsFor,
            ppw: ppw,
            managementPercent: mgmtPercent,
            offensivePointsFor: offensivePointsFor,
            maxOffensivePointsFor: maxOffensivePointsFor,
            offensivePPW: oppw,
            offensiveManagementPercent: offMgmtPercent,
            defensivePointsFor: defensivePointsFor,
            maxDefensivePointsFor: maxDefensivePointsFor,
            defensivePPW: dppw,
            defensiveManagementPercent: defMgmtPercent,
            weeks: gamesPlayed,
            wins: wins,
            losses: losses,
            recordString: "\(wins)-\(losses)",
            isChampion: isChampion
        )
    }
}

extension TeamStanding {
    func offensivePointsForPlayoffWeek(_ week: Int) -> Double {
        roster.flatMap { player in
            player.weeklyScores.filter { $0.week == week }
                .compactMap { ws in
                    let pos = PositionNormalizer.normalize(player.position)
                    if offensivePositions.contains(pos) {
                        return ws.points_half_ppr ?? ws.points
                    }
                    return nil
                }
        }.reduce(0, +)
    }
    func defensivePointsForPlayoffWeek(_ week: Int) -> Double {
        roster.flatMap { player in
            player.weeklyScores.filter { $0.week == week }
                .compactMap { ws in
                    let pos = PositionNormalizer.normalize(player.position)
                    if defensivePositions.contains(pos) {
                        return ws.points_half_ppr ?? ws.points
                    }
                    return nil
                }
        }.reduce(0, +)
    }
}
