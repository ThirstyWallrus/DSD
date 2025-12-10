//
//  DatabaseManager.swift
//  DynastyStatDrop
//
//  (No structural changes; relies on canonical models from LeagueData.swift)
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
}

// FIXED: matchups array element is SleeperMatchup, with fields: rosterId, matchupId, starters, players, points, customPoints
// Use the explicit .week (if present) as the week key for the map; fall back to matchupId for older persisted data.
func buildWeekRosterMatchupMap(matchups: [SleeperMatchup]) -> [Int: [Int: Int]] {
    var map: [Int: [Int: Int]] = [:]
    for matchup in matchups {
        let weekKey = matchup.week ?? matchup.matchupId
        map[weekKey, default: [:]][matchup.rosterId] = weekKey
    }
    return map
}
