//
//  SleeperLeagueManager+Championships.swift
//  DynastyStatDrop
//
//  Championship-related helpers extracted from SleeperLeagueManager.
//

import Foundation

extension SleeperLeagueManager {

    /// Recompute championships from final bracket winners for a single league, optionally persist into
    /// LeagueData.computedChampionships and SeasonData.computedChampionOwnerId.
    ///
    /// - Parameters:
    ///   - leagueId: league id to operate on (must be already imported into the active user’s store)
    ///   - persistComputedContainer: if true, write aggregated computed results into LeagueData.computedChampionships and SeasonData.computedChampionOwnerId
    ///   - overwriteTeamStanding: if true, also overwrite TeamStanding.championships (destructive). Default: false.
    /// - Returns: per-season report and aggregated computed counts
    ///
    /// This method makes a timestamped backup of the current league file before writing.
    func recomputeAndPersistChampionships(
        for leagueId: String,
        persistComputedContainer: Bool = true,
        overwriteTeamStanding: Bool = false
    ) async throws -> (seasonReport: [String: (stored: String?, computed: String?)], aggregated: [String: Int]) {
        // Load the league (from disk so we have the persisted pre-change state)
        let url = leagueFileURL(leagueId)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let league = try? JSONDecoder().decode(LeagueData.self, from: data) else {
            throw NSError(domain: "SleeperLeagueManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "League file not found for id \(leagueId)"])
        }

        // Compute champions
        let (seasonChampions, aggregated) = AllTimeAggregator.recomputeAllChampionships(for: league)

        // Build season-level stored vs computed report
        var report: [String: (stored: String?, computed: String?)] = [:]
        for season in league.seasons {
            // Attempt to discover stored champion ownerId from imported TeamStanding.championships
            // Strategy:
            //  - Find first team whose TeamStanding.championships ?? 0 > 0 and use its ownerId (best-effort)
            //  - If none found, nil
            let storedOwner: String? = {
                if let t = season.teams.first(where: { ($0.championships ?? 0) > 0 }) {
                    return t.ownerId
                }
                return nil
            }()

            let computedOwner = seasonChampions[season.id] ?? nil
            report[season.id] = (stored: storedOwner, computed: computedOwner)

            // Emit a diagnostic line for greppable logs
            print("[ChampionRecompute] season=\(season.id) storedChampionOwnerId=\(storedOwner ?? "null") computedChampionOwnerId=\(computedOwner ?? "null")")
        }

        // If not persisting, return results now
        if !persistComputedContainer {
            // Also emit aggregated summary
            for (owner, cnt) in aggregated {
                print("[ChampionRecompute] owner=\(owner) computedChampionships=\(cnt)")
            }
            return (report, aggregated)
        }

        // Persist: create a backup of the existing league file
        do {
            let backupURL = try backupLeagueFile(leagueId)
            print("[ChampionPersist] Backup created at \(backupURL.path)")
        } catch {
            print("[ChampionPersist] Warning: failed to create backup for league \(leagueId): \(error)")
            // proceed but log warning
        }

        // Build updated seasons with computedChampionOwnerId (and optional TeamStanding.championships increment)
        var updatedSeasons = league.seasons
        for i in 0..<updatedSeasons.count {
            var season = updatedSeasons[i]
            let sid = season.id
            let computedOwner = seasonChampions[sid] ?? nil
            season.computedChampionOwnerId = computedOwner

            if overwriteTeamStanding, let ownerId = computedOwner {
                var teams = season.teams
                if let tidx = teams.firstIndex(where: { $0.ownerId == ownerId }) {
                    let t = teams[tidx]
                    teams[tidx] = TeamStanding(
                        id: t.id,
                        name: t.name,
                        positionStats: t.positionStats,
                        ownerId: t.ownerId,
                        roster: t.roster,
                        leagueStanding: t.leagueStanding,
                        pointsFor: t.pointsFor,
                        maxPointsFor: t.maxPointsFor,
                        managementPercent: t.managementPercent,
                        teamPointsPerWeek: t.teamPointsPerWeek,
                        winLossRecord: t.winLossRecord,
                        bestGameDescription: t.bestGameDescription,
                        biggestRival: t.biggestRival,
                        strengths: t.strengths,
                        weaknesses: t.weaknesses,
                        playoffRecord: t.playoffRecord,
                        championships: (t.championships ?? 0) + 1,
                        winStreak: t.winStreak,
                        lossStreak: t.lossStreak,
                        offensivePointsFor: t.offensivePointsFor,
                        maxOffensivePointsFor: t.maxOffensivePointsFor,
                        offensiveManagementPercent: t.offensiveManagementPercent,
                        averageOffensivePPW: t.averageOffensivePPW,
                        offensiveStrengths: t.offensiveStrengths,
                        offensiveWeaknesses: t.offensiveWeaknesses,
                        positionAverages: t.positionAverages,
                        individualPositionAverages: t.individualPositionAverages,
                        defensivePointsFor: t.defensivePointsFor,
                        maxDefensivePointsFor: t.maxDefensivePointsFor,
                        defensiveManagementPercent: t.defensiveManagementPercent,
                        averageDefensivePPW: t.averageDefensivePPW,
                        defensiveStrengths: t.defensiveStrengths,
                        defensiveWeaknesses: t.defensiveWeaknesses,
                        pointsScoredAgainst: t.pointsScoredAgainst,
                        league: t.league,
                        lineupConfig: t.lineupConfig,
                        weeklyActualLineupPoints: t.weeklyActualLineupPoints,
                        actualStartersByWeek: t.actualStartersByWeek,
                        actualStarterPositionCounts: t.actualStarterPositionCounts,
                        actualStarterWeeks: t.actualStarterWeeks,
                        waiverMoves: t.waiverMoves,
                        faabSpent: t.faabSpent,
                        tradesCompleted: t.tradesCompleted
                    )
                    season = SeasonData(
                        id: season.id,
                        season: season.season,
                        teams: teams,
                        playoffStartWeek: season.playoffStartWeek,
                        playoffTeamsCount: season.playoffTeamsCount,
                        matchups: season.matchups,
                        matchupsByWeek: season.matchupsByWeek,
                        computedChampionOwnerId: season.computedChampionOwnerId
                    )
                }
            }

            updatedSeasons[i] = season
        }

        // Build new LeagueData immutably (respecting let properties)
        var newLeague = LeagueData(
            id: league.id,
            name: league.name,
            season: league.season,
            teams: updatedSeasons.last?.teams ?? league.teams,
            seasons: updatedSeasons,
            startingLineup: league.startingLineup,
            allTimeOwnerStats: league.allTimeOwnerStats,
            computedChampionships: aggregated
        )
        // Rebuild all-time cache to reflect computed championships
        newLeague = AllTimeAggregator.buildAllTime(for: newLeague, playerCache: allPlayers)

        await MainActor.run {
            if let idx = leagues.firstIndex(where: { $0.id == newLeague.id }) {
                leagues[idx] = newLeague
            } else {
                leagues.append(newLeague)
            }
            persistLeagueFile(newLeague)
            saveIndex()
        }

        for (owner, cnt) in aggregated {
            print("[ChampionRecompute] owner=\(owner) computedChampionships=\(cnt)")
        }
        return (report, aggregated)
    }

    // MARK: - Backup Helper

    fileprivate func backupLeagueFile(_ leagueId: String) throws -> URL {
        let src = leagueFileURL(leagueId)
        guard FileManager.default.fileExists(atPath: src.path) else {
            throw NSError(domain: "SleeperLeagueManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "No file to backup for \(leagueId)"])
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupName = "\(leagueId)-pre-recompute-\(ts).json"
        let dest = userRootDir(activeUsername).appendingPathComponent(backupName)
        try FileManager.default.copyItem(at: src, to: dest)
        return dest
    }
}
