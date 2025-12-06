//
//  DatabaseManager.swift
//  DynastyStatDrop
//
//  (No structural changes; relies on canonical models from LeagueData.swift)
//  Extended with per-league cache accessors & persistence helpers for:
//
//    - ownedPlayers: [String: CompactPlayer]?
//    - teamHistoricalPlayers: [String: [String: TeamHistoricalPlayer]]?
//
//  These helpers are intentionally lightweight and best-effort: they update the
//  in-memory league map and persist the full LeagueData JSON using LeagueDiskStore.
//  This preserves the single-file-per-league model and avoids adding sidecar files.
//

import Foundation

class DatabaseManager {
    @MainActor static let shared = DatabaseManager()
    private var leagues: [String: LeagueData] = [:]

    func saveLeague(_ league: LeagueData) {
        leagues[league.id] = league
    }

    func getLeague(leagueId: String) -> LeagueData? {
        leagues[leagueId]
    }

    func getTeamsForLeague(leagueId: String, season: String) -> [TeamStanding] {
        guard let league = leagues[leagueId] else { return [] }
        return league.seasons.first(where: { $0.id == season })?.teams ?? []
    }

    func getRosterForTeam(leagueId: String, season: String, teamName: String) -> [String] {
        guard
            let league = leagues[leagueId],
            let seasonData = league.seasons.first(where: { $0.id == season }),
            let team = seasonData.teams.first(where: { $0.name == teamName })
        else { return [] }
        return team.roster.map { $0.position }
    }

    func getWeeklyStatsByPosition(leagueId: String, week: Int) -> [String: [PlayerWeeklyScore]] {
        guard let league = leagues[leagueId] else { return [:] }
        var positionScores: [String: [PlayerWeeklyScore]] = [:]
        for season in league.seasons {
            for team in season.teams {
                for player in team.roster {
                    if let score = player.weeklyScores.first(where: { $0.week == week }) {
                        positionScores[player.position, default: []].append(score)
                    }
                }
            }
        }
        return positionScores
    }

    func getWeeklyStatsForPosition(leagueId: String, week: Int, position: String) -> [PlayerWeeklyScore] {
        getWeeklyStatsByPosition(leagueId: leagueId, week: week)[position] ?? []
    }

    // MARK: --- New per-league cache accessors & persistence helpers ---

    /// Returns the compact per-league ownedPlayers map (CompactPlayer) if present.
    /// This is the persisted, compact subset of players that were ever rostered or appeared in matchups for the league.
    @MainActor
    func getOwnedPlayers(leagueId: String) -> [String: CompactPlayer]? {
        return leagues[leagueId]?.ownedPlayers
    }

    /// Returns the teamHistoricalPlayers map for a particular roster/team id (teamId is TeamStanding.id)
    /// keyed by playerId -> TeamHistoricalPlayer. Returns nil if not present.
    @MainActor
    func getTeamHistoricalPlayers(leagueId: String, rosterId: String) -> [String: TeamHistoricalPlayer]? {
        return leagues[leagueId]?.teamHistoricalPlayers?[rosterId]
    }

    /// Returns the full teamHistoricalPlayers container for the league (teamId -> playerId -> TeamHistoricalPlayer)
    @MainActor
    func getAllTeamHistoricalPlayers(leagueId: String) -> [String: [String: TeamHistoricalPlayer]]? {
        return leagues[leagueId]?.teamHistoricalPlayers
    }

    /// Persist updated compact caches into the single LeagueData file for `leagueId`.
    /// - Updates the in-memory copy and writes the full LeagueData JSON using LeagueDiskStore.shared.saveLeague(_:)
    /// - Returns true on success (best-effort), false otherwise.
    /// - This function does not mutate other parts of the league; it only attaches the provided cache maps.
    @MainActor
    @discardableResult
    func persistLeagueCaches(
        leagueId: String,
        ownedPlayers: [String: CompactPlayer]?,
        teamHistoricalPlayers: [String: [String: TeamHistoricalPlayer]]?
    ) -> Bool {
        guard var league = leagues[leagueId] ?? LeagueDiskStore.shared.loadLeague(id: leagueId) else {
            print("[DatabaseManager] persistLeagueCaches: league not loaded: \(leagueId)")
            return false
        }

        // Attach caches (nil clears)
        league.ownedPlayers = ownedPlayers
        league.teamHistoricalPlayers = teamHistoricalPlayers

        // Update in-memory map
        leagues[leagueId] = league

        // Persist to disk via the canonical disk store (atomic write inside)
        do {
            LeagueDiskStore.shared.saveLeague(league)
            // Also keep the in-memory DBManager copy consistent (already set above)
            print("[DatabaseManager] persisted caches for league \(leagueId) (ownedPlayers=\(ownedPlayers?.count ?? 0), teamHistoricalTeams=\(teamHistoricalPlayers?.count ?? 0))")
            return true
        } catch {
            // LeagueDiskStore.saveLeague doesn't currently throw, but defensive logging retained
            print("[DatabaseManager] failed to persist caches for league \(leagueId): \(error)")
            return false
        }
    }

    // NEW: Build roster->matchup map for a stored season (derived from stored matchups).
    // This provides a single computed view so callers don't need to keep a separate map in memory.
    /// - Parameters:
    ///   - leagueId: id of the league to read from the in-memory map
    ///   - seasonId: optional season id; if nil the latest season is used
    /// - Returns: [week: [rosterId: matchupWeekKey]] mapping
    @MainActor
    func getWeekRosterMatchupMap(leagueId: String, seasonId: String? = nil) -> [Int: [Int: Int]] {
        guard let league = leagues[leagueId] else { return [:] }
        let season: SeasonData? = {
            if let sid = seasonId { return league.seasons.first(where: { $0.id == sid }) }
            return league.seasons.sorted(by: { $0.id < $1.id }).last
        }()
        guard let matchups = season?.matchups else { return [:] }
        return buildWeekRosterMatchupMap(matchups: matchups)
    }
}

// FIXED: matchups array element is SleeperMatchup, with fields: rosterId, matchupId, starters, players, points, customPoints
// Use the explicit .week (if present) as the week key for the map; fall back to matchupId for older persisted data.
func buildWeekRosterMatchupMap(matchups: [SleeperMatchup]) -> [Int: [Int: Int]] {
    // New behavior: prefer explicit week when present.
    // If any matchups are missing .week, create a deterministic mapping from unique matchupId -> sequential week number
    // (sorted ascending). This normalizes older persisted data that used matchupId as the key.
    var map: [Int: [Int: Int]] = [:]

    // Determine whether any matchups are missing explicit weeks
    let anyMissingWeek = matchups.contains { $0.week == nil }

    // If any are missing, build a mapping from unique matchupId to sequential week number (1-based).
    // We sort unique matchupId values ascending to make the mapping deterministic.
    var matchupIdToWeek: [Int: Int] = [:]
    if anyMissingWeek {
        let uniqueIds = Array(Set(matchups.map { $0.matchupId })).sorted()
        // Map each unique matchupId to a 1-based index
        for (idx, mid) in uniqueIds.enumerated() {
            matchupIdToWeek[mid] = idx + 1
        }
        // Debugging aid (non-sensitive)
        print("[DatabaseManager] buildWeekRosterMatchupMap: found matchups with missing .week; mapping matchupId -> week sample: \(Array(matchupIdToWeek.prefix(10)))")
    }

    for matchup in matchups {
        // Use explicit week when present; otherwise use derived mapping if available, otherwise fallback to matchupId as last resort.
        let weekKey: Int = matchup.week ?? matchupIdToWeek[matchup.matchupId] ?? matchup.matchupId
        map[weekKey, default: [:]][matchup.rosterId] = weekKey
    }
    return map
}
