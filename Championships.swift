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
    ///   - leagueId: league id to operate on (must be already imported into the active user's store)
    ///   - persistComputedContainer: if true, write aggregated computed results into LeagueData.computedChampionships and SeasonData.computedChampionOwnerId
    ///   - overwriteTeamStanding: retained for API compatibility; currently non-destructive to TeamStanding.
    /// - Returns: per-season report and aggregated computed counts
    ///
    /// This method makes a timestamped backup of the current league file before writing (best-effort).
    @discardableResult
    func recomputeAndPersistChampionships(
        for leagueId: String,
        persistComputedContainer: Bool = true,
        overwriteTeamStanding: Bool = false
    ) async throws -> (seasonReport: [String: (stored: String?, computed: String?)], aggregated: [String: Int]) {

        guard let idx = leagues.firstIndex(where: { $0.id == leagueId }) else {
            throw NSError(domain: "SleeperLeagueManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "League not found for id \(leagueId)"])
        }

        let league = leagues[idx]
        let (seasonChampions, aggregated) = AllTimeAggregator.recomputeAllChampionships(for: league)

        // Build season-level stored vs computed report
        var report: [String: (stored: String?, computed: String?)] = [:]
        for season in league.seasons {
            let storedOwner = season.teams.first(where: { ($0.championships ?? 0) > 0 })?.ownerId
            let computedOwner = seasonChampions[season.id] ?? nil
            report[season.id] = (stored: storedOwner, computed: computedOwner)
            print("[ChampionRecompute] season=\(season.id) storedChampionOwnerId=\(storedOwner ?? "null") computedChampionOwnerId=\(computedOwner ?? "null")")
        }

        guard persistComputedContainer else {
            for (owner, cnt) in aggregated {
                print("[ChampionRecompute] owner=\(owner) computedChampionships=\(cnt)")
            }
            return (report, aggregated)
        }

        // Best-effort backup
        do {
            let backupURL = try backupLeagueFilePublic(leagueId)
            print("[ChampionPersist] Backup created at \(backupURL.path)")
        } catch {
            print("[ChampionPersist] Warning: failed to create backup for league \(leagueId): \(error)")
        }

        // Update seasons with computedChampionOwnerId (immutable copy)
        let newSeasons: [SeasonData] = league.seasons.map { season in
            SeasonData(
                id: season.id,
                season: season.season,
                teams: season.teams,
                playoffStartWeek: season.playoffStartWeek,
                playoffTeamsCount: season.playoffTeamsCount,
                matchups: season.matchups,
                matchupsByWeek: season.matchupsByWeek,
                computedChampionOwnerId: seasonChampions[season.id] ?? nil
            )
        }

        // Build updated league with computed championships container
        var updatedLeague = LeagueData(
            id: league.id,
            name: league.name,
            season: league.season,
            teams: newSeasons.last?.teams ?? league.teams,
            seasons: newSeasons,
            startingLineup: league.startingLineup,
            allTimeOwnerStats: league.allTimeOwnerStats,
            computedChampionships: aggregated
        )

        // Rebuild all-time aggregates to keep caches in sync
        updatedLeague = AllTimeAggregator.buildAllTime(for: updatedLeague, playerCache: allPlayers)

        leagues[idx] = updatedLeague
        persistLeagueFile(updatedLeague)
        saveIndex()

        return (report, aggregated)
    }

    // Local, best-effort backup helper (since the main helper is private to its file)
    private func backupLeagueFilePublic(_ leagueId: String) throws -> URL {
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
