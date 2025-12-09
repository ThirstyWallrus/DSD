//
//  LeagueData.swift
//  DynastyStatDrop
//
//  Canonical models + All Time aggregation cache
//

import Foundation

// MARK: - Aggregated All Time Franchise Stats (Owner-based)

struct AggregatedOwnerStats: Codable, Equatable {
    let ownerId: String
    let latestDisplayName: String
    let seasonsIncluded: [String]
    let weeksPlayed: Int

    // Totals
    let totalPointsFor: Double
    let totalMaxPointsFor: Double
    let totalOffensivePointsFor: Double
    let totalMaxOffensivePointsFor: Double
    let totalDefensivePointsFor: Double
    let totalMaxDefensivePointsFor: Double
    let totalPointsScoredAgainst: Double

    // Derived %
    let managementPercent: Double
    let offensiveManagementPercent: Double
    let defensiveManagementPercent: Double

    // PPW
    let teamPPW: Double
    let offensivePPW: Double
    let defensivePPW: Double

    // Position aggregates
    let positionTotals: [String: Double]
    let positionStartCounts: [String: Int]
    let positionAvgPPW: [String: Double]
    let individualPositionPPW: [String: Double]

    // Record / championships
    let championships: Int
    let totalWins: Int
    let totalLosses: Int
    let totalTies: Int
    // NEW: Transactions & actual starters aggregation
    let totalWaiverMoves: Int
    let totalFAABSpent: Double
    let totalTradesCompleted: Int
    let actualStarterPositionCountsTotals: [String: Int]   // sum of actual starters counts
    let actualStarterWeeks: Int                            // weeks with actual lineup captured
    //: H2H
    let headToHeadVs: [String: H2HStats]
    // NEW: Per-opponent match detail history (optional for backward compatibility)
    let headToHeadDetails: [String: [H2HMatchDetail]]?

    var recordString: String {
        "\(totalWins)-\(totalLosses)\(totalTies > 0 ? "-\(totalTies)" : "")"
    }
    // MARK: Playoffs
    let playoffStats: PlayoffStats
}

// MARK: - H2H match detail model

struct H2HMatchDetail: Codable, Equatable {
    let seasonId: String
    let week: Int
    let matchupId: Int
    let userRosterId: Int
    let oppRosterId: Int
    let userPoints: Double
    let oppPoints: Double
    let userMax: Double
    let oppMax: Double
    let userMgmtPct: Double
    let oppMgmtPct: Double
    let result: String // "W", "L", "T"
}

// MARK: - Compact per-league player cache (Version B)
//
// Stored inside LeagueData as `ownedPlayers`.
// Purpose: Persist only players that were ever rostered or appeared in matchups for the league.
// Compact: No weeklyScores, only metadata used to resolve name/position and first/last seen timeline.
public struct CompactPlayer: Codable, Equatable {
    let id: String
    let fullName: String?
    let position: String?
    let fantasyPositions: [String]?

    // first/last seen timeline (season id + week)
    let firstSeenSeason: String?
    let firstSeenWeek: Int?
    let lastSeenSeason: String?
    let lastSeenWeek: Int?

    // last known roster id (roster_id from Sleeper) when observed
    let lastKnownRosterId: Int?

    // No Longer On Team flag (NLOT)
    // true => not present on latest-season rosters for the league context
    let nlot: Bool

    // Optional short notes (developer/debug)
    let notes: String?
}

// MARK: - Per-team historical player record (compact)
//
// Purpose: small per-team provenance used to resolve historical starters and quick provenance.
// Stored inside LeagueData as `teamHistoricalPlayers` keyed by teamId -> playerId -> TeamHistoricalPlayer
public struct TeamHistoricalPlayer: Codable, Equatable {
    let playerId: String
    let firstSeenSeason: String?
    let firstSeenWeek: Int?
    let lastSeenSeason: String?
    let lastSeenWeek: Int?
    let lastKnownPosition: String?
    let lastKnownName: String?
    let lastKnownRosterId: Int?
    let nlot: Bool
    // Optional compact appearances timeline (seasonId + week) - omit to save space unless needed
    let appearancesCount: Int?
    let notes: String?
}

// MARK: - Full per-player canonical record (Option A)
// Purpose: single source of truth for per-player weekly points across the league context.
// weeklyPoints keys are encoded as "<seasonId>-<week>" (e.g., "2024-3").
// Stored in LeagueData.fullPlayers (optional).
public struct FullPlayerRecord: Codable, Equatable {
    let playerId: String
    let fullName: String?
    let position: String?
    let fantasyPositions: [String]?

    // keyed by "\(seasonId)-\(week)" -> Double
    var weeklyPoints: [String: Double]?

    let firstSeenSeason: String?
    let firstSeenWeek: Int?
    let lastSeenSeason: String?
    let lastSeenWeek: Int?
    let lastKnownRosterId: Int?
    let nlot: Bool?
    let notes: String?
}

// Optional: persisted lightweight free-agent snapshot (minimal fields + timestamp).
// Keep optional and compact (only populated if feature enabled).
public struct FreeAgentSnapshot: Codable, Equatable {
    let timestamp: Date
    let playerIds: [String]    // only ids
    let notes: String?
}

// MARK: - Core League Models

struct LeagueData: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    var season: String
    var teams: [TeamStanding]              // convenience latest season
    let seasons: [SeasonData]
    let startingLineup: [String]

    // All Time ownerId -> AggregatedOwnerStats (current franchises only)
    var allTimeOwnerStats: [String: AggregatedOwnerStats]? = nil

    // Current season ownerIds
    var currentSeasonOwnerIds: [String] {
        guard let latest = seasons.sorted(by: { $0.id < $1.id }).last else { return [] }
        return latest.teams.map { $0.ownerId }
    }

    // NEW: Computed championships container (safe/preserved, doesn't overwrite original TeamStanding.championships)
    // Key: ownerId -> count
    var computedChampionships: [String: Int]? = nil

    // ----------------------------------------------------------------
    // Version B additions (single-file caches)
    //
    // Compact per-league owned players cache (only players that were rostered or appeared in matchups)
    // Key: playerId -> CompactPlayer
    var ownedPlayers: [String: CompactPlayer]? = nil

    // Per-team historical player records (teamId -> playerId -> TeamHistoricalPlayer)
    // teamId corresponds to TeamStanding.id (which is roster_id as a String).
    var teamHistoricalPlayers: [String: [String: TeamHistoricalPlayer]]? = nil

    // NEW (Option A): Canonical full per-player record including weeklyPoints
    // Key: playerId -> FullPlayerRecord
    // Optional: missing on older imports; built gradually by rebuildCachesForLeague / imports.
    var fullPlayers: [String: FullPlayerRecord]? = nil

    // Optional persisted minimal free-agent snapshot for this league (if feature enabled)
    var freeAgentsSnapshot: FreeAgentSnapshot? = nil

    // NEW: Per-team matchup history (teamId -> opponentTeamId -> array of H2HMatchDetail)
    // This stores perspective-specific match detail entries for each matchup encountered for that team.
    // Example: matchupHistories["12"]["34"] = [H2HMatchDetail(...), ...] (team 12 vs opponent 34)
    // This is intentionally stored at the league level to avoid changing TeamStanding shape widely.
    var matchupHistories: [String: [String: [H2HMatchDetail]]]? = nil
    // ----------------------------------------------------------------
}

struct SeasonData: Identifiable, Codable, Equatable {
    let id: String
    var season: String
    let teams: [TeamStanding]
    let playoffStartWeek: Int?
    let playoffTeamsCount: Int?
    let matchups: [SleeperMatchup]?
    let matchupsByWeek: [Int: [MatchupEntry]]?

    // NEW: Computed champion owner id for this season (string ownerId) — populated by recompute routine.
    // Keeps original TeamStanding.championships untouched.
    var computedChampionOwnerId: String? = nil
}

// MARK: - Player Weekly Score

struct PlayerWeeklyScore: Codable, Equatable, Hashable {
    let week: Int
    let points: Double
    let player_id: String
    let points_half_ppr: Double?
    let matchup_id: Int
    let points_ppr: Double
    let points_standard: Double
}

// MARK: - Player

struct Player: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let position: String
    let altPositions: [String]?
    let weeklyScores: [PlayerWeeklyScore]
}

// MARK: - TeamStanding

struct TeamStanding: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let positionStats: [PositionStat]
    let ownerId: String
    let roster: [Player]
    let leagueStanding: Int
   
    // Basic
    let pointsFor: Double
    let maxPointsFor: Double
    let managementPercent: Double
    let teamPointsPerWeek: Double
   
    // Advanced
    let winLossRecord: String?
    let bestGameDescription: String?
    let biggestRival: String?
    let strengths: [String]?
    let weaknesses: [String]?
    let playoffRecord: String?
    let championships: Int?
    let winStreak: Int?
    let lossStreak: Int?
   
    // Offensive
    let offensivePointsFor: Double?
    let maxOffensivePointsFor: Double?
    let offensiveManagementPercent: Double?
    let averageOffensivePPW: Double?
    let offensiveStrengths: [String]?
    let offensiveWeaknesses: [String]?
    let positionAverages: [String: Double]?            // per-position PPW (weeks)
    let individualPositionAverages: [String: Double]?  // per-start PPW
   
    // Defensive
    let defensivePointsFor: Double?
    let maxDefensivePointsFor: Double?
    let defensiveManagementPercent: Double?
    let averageDefensivePPW: Double?
    let defensiveStrengths: [String]?
    let defensiveWeaknesses: [String]?
   
    // Ancillary
    let pointsScoredAgainst: Double?
    let league: LeagueData?
    let lineupConfig: [String: Int]?
   
    // NEW: Actual weekly starter lineup totals (week -> points) - used for volatility only (NOT for management % calculations)
    let weeklyActualLineupPoints: [Int: Double]?   // Optional for backward compatibility with saved data
    let actualStartersByWeek: [Int: [String]]?
   
    // NEW season-level tracking
    let actualStarterPositionCounts: [String: Int]?   // total counts per position across weeks (actual lineup)
    let actualStarterWeeks: Int?                      // number of weeks with a starters list
    let waiverMoves: Int?                             // season waiver claim count
    let faabSpent: Double?                            // season FAAB spent
    let tradesCompleted: Int?                         // season trades completed
}

// MARK: - PositionStat

struct PositionStat: Identifiable, Codable, Equatable {
    let id: String
    let position: String
    let average: Double
    let leagueAverage: Double
    let rank: Int

    init(
        id: String = UUID().uuidString,
        position: String,
        average: Double,
        leagueAverage: Double,
        rank: Int
    ) {
        self.id = id
        self.position = position
        self.average = average
        self.leagueAverage = leagueAverage
        self.rank = rank
    }
}

// MARK: - H2HStats

struct H2HStats: Codable, Equatable {
    let wins: Int
    let losses: Int
    let ties: Int
    let pointsFor: Double
    let pointsAgainst: Double
    let games: Int
    let sumMgmtFor: Double
    let sumMgmtAgainst: Double

    var record: String {
        "\(wins)-\(losses)\(ties > 0 ? "-\(ties)" : "")"
    }

    var reverseRecord: String {
        "\(losses)-\(wins)\(ties > 0 ? "-\(ties)" : "")"
    }

    var avgPointsFor: Double {
        games > 0 ? pointsFor / Double(games) : 0.0
    }

    var avgPointsAgainst: Double {
        games > 0 ? pointsAgainst / Double(games) : 0.0
    }

    var avgMgmtFor: Double {
        games > 0 ? sumMgmtFor / Double(games) : 0.0
    }

    var avgMgmtAgainst: Double {
        games > 0 ? sumMgmtAgainst / Double(games) : 0.0
    }
}

// MARK: - Sleeper Reference

struct SleeperMatchup: Codable, Equatable {
    let starters: [String]
    let rosterId: Int
    let players: [String]
    let matchupId: Int     // pairing id from Sleeper API (matchup_id)
    let points: Double
    let customPoints: Double?
    let week: Int?        // NEW: the season week number that this matchup entry corresponds to (may be nil for older persisted data)

    enum CodingKeys: String, CodingKey {
        case starters
        case rosterId = "roster_id"
        case players
        case matchupId = "matchup_id"
        case points
        case customPoints = "custom_points"
        case week
    }
}

struct SleeperPlayer: Codable {
    let player_id: String
    let full_name: String?
    let position: String?
}
