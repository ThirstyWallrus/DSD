//
//  SleeperLeagueManager.swift
//  DynastyStatDrop
//
//  FULL FILE — PATCHED: Robust week/team matchup data population for per-week views.
//  Change: fetchMatchupsByWeek now ensures all teams have a MatchupEntry for every week.
//  Add: per-season playoff overrides persisted and exposed to import UI.
//  Add: recompute championships helpers that populate computedChampionOwnerId / computedChampionships container.
//

import Foundation
import SwiftUI

// MARK: - Import PositionNormalizer for canonical defensive position mapping
import Foundation

// Ensure PositionNormalizer is available to all code in this file.
import Foundation

// Canonical flex slot normalizer (maps legacy tokens to Sleeper’s current set)
private func canonicalFlexSlot(_ slot: String) -> String {
    let u = slot.uppercased()
    switch u {
    case "WRRB", "RBWR": return "WRRB_FLEX"
    case "WRRBTE", "WRRB_TE", "RBWRTE": return "FLEX"
    case "REC_FLEX": return "REC_FLEX"
    case "SUPER_FLEX", "QBRBWRTE", "QBRBWR", "QBSF", "SFLX": return "SUPER_FLEX"
    case "IDP", "IDPFLEX", "IDP_FLEX", "DFLEX", "DL_LB_DB", "DL_LB", "LB_DB", "DL_DB": return "IDP_FLEX"
    default: return u == "FLEX" ? "FLEX" : u
    }
}

// MARK: - Raw Sleeper API Models

struct SleeperUser: Codable {
    let user_id: String
    let username: String?
    let display_name: String?
}

// MARK: - Matchup Entry (from Sleeper matchups endpoint)
struct MatchupEntry: Codable, Equatable {
    let roster_id: Int
    let matchup_id: Int?
    let points: Double?
    let players_points: [String: Double]?
    let players_projected_points: [String: Double]?
    let starters: [String]?
    let players: [String]?

    // NEW: Optional explicit per-player slot mapping for this matchup entry.
    // Key => player id (String), Value => slot token (e.g., "IR", "TAXI", "RB", "WR", "DL_LB", etc.)
    // This field is optional to remain backward compatible with historical data that lacks it.
    let players_slots: [String: String]?
}

struct SleeperRoster: Codable {
    let roster_id: Int
    let owner_id: String?
    let players: [String]?
    let starters: [String]?
    let settings: [String: AnyCodable]?
}

struct AnyCodable: Codable, Equatable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Int.self) { value = v }
        else if let v = try? c.decode(Double.self) { value = v }
        else if let v = try? c.decode(Bool.self) { value = v }
        else if let v = try? c.decode(String.self) { value = v }
        else if let v = try? c.decode([AnyCodable].self) { value = v.map { $0.value } }
        else if let v = try? c.decode([String: AnyCodable].self) { value = v.mapValues { $0.value } }
        else { value = "" }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as Int: try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as Bool: try c.encode(v)
        case let v as String: try c.encode(v)
        case let v as [Any]:
            try c.encode(v.map { AnyCodable($0) })
        case let v as [String: Any]:
            try c.encode(v.mapValues { AnyCodable($0) })
        default:
            try c.encode(String(describing: value))
        }
    }
    static func ==(lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}

struct RawSleeperPlayer: Codable, Equatable {
    let player_id: String
    let full_name: String?
    let position: String?
    let fantasy_positions: [String]?
}

struct SleeperLeague: Codable {
    let league_id: String
    let name: String?
    let season: String?
    let roster_positions: [String]?
    let settings: [String: AnyCodable]?

    var scoringType: String {
        guard let scoring = settings?["scoring_settings"]?.value as? [String: AnyCodable],
              let rec = scoring["rec"]?.value as? Double else { return "custom" }
        if rec == 1.0 { return "ppr" }
        if rec == 0.5 { return "half_ppr" }
        if rec == 0.0 { return "standard" }
        return "custom"
    }

    var currentWeek: Int {
        if let w = settings?["week"]?.value as? Int {
            return w
        }
        return 1
    }
}

struct SleeperTransaction: Codable {
    let transaction_id: String
    let type: String?
    let status: String?
    let roster_ids: [Int]?
    let waiver_bid: Int?
}

// MARK: - Disk Persistence Support

private struct LeagueIndexEntry: Codable, Equatable {
    let id: String
    let name: String
    let season: String
    let lastUpdated: Date
}

// MARK: - Position Normalizer (Global Patch)
import Foundation

@MainActor
class SleeperLeagueManager: ObservableObject {

    @Published var leagues: [LeagueData] = []
    @Published var playoffStartWeek: Int = 14
    @Published var leaguePlayoffStartWeeks: [String: Int] = [:]
    @Published var isRefreshing: Bool = false

    // NEW: per-league per-season overrides persisted in memory and to disk
    // Shape: [leagueId: [seasonId: playoffStartWeek]]
    @Published var leagueSeasonPlayoffOverrides: [String: [String: Int]] = [:]

    // NEW: Global current week reported from Sleeper API (helps views pick the "current" week)
    @Published var globalCurrentWeek: Int = 1

    private var activeUsername: String = "global"
    private let legacySingleFilePrefix = "leagues_"
    private let legacyFilename = "leagues.json"
    private let oldUDKey: String? = nil
    private let rootFolderName = "SleeperLeagues"
    private let indexFileName = "index.json"
    private var indexEntries: [LeagueIndexEntry] = []
    var playerCache: [String: RawSleeperPlayer]? = nil
    var allPlayers: [String: RawSleeperPlayer] = [:]
    private var transactionsCache: [String: [SleeperTransaction]] = [:]
    private var usersCache: [String: [SleeperUser]] = [:]
    private var rostersCache: [String: [SleeperRoster]] = [:]

    private let offensivePositions: Set = ["QB","RB","WR","TE","K"]
    private let defensivePositions: Set = ["DL","LB","DB"]
    private let offensiveFlexSlots: Set = ["FLEX","WRRB_FLEX","REC_FLEX","SUPER_FLEX"]

    private static var _lastRefresh: [String: Date] = [:]
    private var refreshThrottleInterval: TimeInterval { 10 * 60 } // 10 minutes

    var weekRosterMatchupMap: [Int: [Int: Int]] = [:]

    init(autoLoad: Bool = false) {
        if autoLoad {
            loadLeaguesWithMigrationIfNeeded(for: activeUsername)
        }
        loadPersistedOverrides()
    }

    // Persist/load overrides in UserDefaults key
    private let overridesUDKey = "dsd.leagueSeasonPlayoffOverrides.v1"

    private func loadPersistedOverrides() {
        let ud = UserDefaults.standard
        if let data = ud.data(forKey: overridesUDKey),
           let parsed = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            leagueSeasonPlayoffOverrides = parsed
        }
    }

    private func persistOverrides() {
        let ud = UserDefaults.standard
        if let data = try? JSONEncoder().encode(leagueSeasonPlayoffOverrides) {
            ud.set(data, forKey: overridesUDKey)
        }
    }

    private func userRootDir(_ user: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(rootFolderName, isDirectory: true).appendingPathComponent(user, isDirectory: true)
    }

    private func ensureUserDir() {
        var dir = userRootDir(activeUsername)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var rv = URLResourceValues()
            rv.isExcludedFromBackup = true
            try? dir.setResourceValues(rv)
        }
    }

    private func clearCaches() {
        playerCache = nil
        allPlayers = [:]
        transactionsCache = [:]
        usersCache = [:]
        rostersCache = [:]
    }

    private func leagueFileURL(_ leagueId: String) -> URL {
        userRootDir(activeUsername).appendingPathComponent("\(leagueId).json")
    }

    private func indexFileURL() -> URL {
        userRootDir(activeUsername).appendingPathComponent(indexFileName)
    }

    func setActiveUser(username: String) {
        saveLeagues()
        activeUsername = username.isEmpty ? "global" : username
        loadLeaguesWithMigrationIfNeeded(for: activeUsername)
    }

    func clearInMemory() {
        leagues.removeAll()
        indexEntries.removeAll()
    }

    private func loadLeaguesWithMigrationIfNeeded(for user: String) {
        ensureUserDir()
        migrateLegacySingleFileIfNeeded(for: user)
        migrateLegacyUserDefaultsIfNeeded(for: user)
        loadIndex()
        loadAllLeagueFiles()
    }

    private func migrateLegacySingleFileIfNeeded(for user: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let legacyPath = docs.appendingPathComponent("\(legacySingleFilePrefix)\(user).json")
        guard FileManager.default.fileExists(atPath: legacyPath.path) else {
            let fallback = docs.appendingPathComponent(legacyFilename)
            guard FileManager.default.fileExists(atPath: fallback.path) else { return }
            migrateSingleFile(fallback)
            return
        }
        migrateSingleFile(legacyPath)
    }

    private func migrateSingleFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let old = try? JSONDecoder().decode([LeagueData].self, from: data),
              !old.isEmpty else { return }
        print("[LeagueMigration] Migrating \(old.count) leagues from single file \(url.lastPathComponent)")
        ensureUserDir()
        for lg in old {
            persistLeagueFile(lg)
        }
        rebuildIndexFromDisk()
        try? FileManager.default.removeItem(at: url)
        saveIndex()
    }

    private func migrateLegacyUserDefaultsIfNeeded(for user: String) {
        guard let key = oldUDKey else { return }
        let ud = UserDefaults.standard
        guard let data = ud.data(forKey: key),
              let old = try? JSONDecoder().decode([LeagueData].self, from: data),
              !old.isEmpty else { return }
        print("[LeagueMigration] Migrating \(old.count) leagues from UserDefaults key '\(key)'")
        ensureUserDir()
        for lg in old { persistLeagueFile(lg) }
        rebuildIndexFromDisk()
        ud.removeObject(forKey: key)
        saveIndex()
    }

    private func loadIndex() {
        let url = indexFileURL()
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([LeagueIndexEntry].self, from: data) else {
            indexEntries = []
            return
        }
        indexEntries = arr
    }

    private func saveIndex() {
        ensureUserDir()
        guard let data = try? JSONEncoder().encode(indexEntries) else { return }
        try? data.write(to: indexFileURL(), options: .atomic)
    }

    private func upsertIndex(for league: LeagueData) {
        let entry = LeagueIndexEntry(id: league.id,
                                     name: league.name,
                                     season: league.season,
                                     lastUpdated: Date())
        if let i = indexEntries.firstIndex(where: { $0.id == entry.id }) {
            indexEntries[i] = entry
        } else {
            indexEntries.append(entry)
        }
    }

    private func rebuildIndexFromDisk() {
        var newEntries: [LeagueIndexEntry] = []
        let dir = userRootDir(activeUsername)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "json" && f.lastPathComponent != indexFileName {
            if let data = try? Data(contentsOf: f),
               let lg = try? JSONDecoder().decode(LeagueData.self, from: data) {
                let e = LeagueIndexEntry(id: lg.id, name: lg.name, season: lg.season, lastUpdated: Date())
                newEntries.append(e)
            }
        }
        indexEntries = newEntries
    }

    private func persistLeagueFile(_ league: LeagueData) {
        ensureUserDir()
        if var lg = try? deepCopy(league) {
            // Ensure we persist any computed championships container as well
            if let data = try? JSONEncoder().encode(lg) {
                try? data.write(to: leagueFileURL(league.id), options: .atomic)
                upsertIndex(for: lg)
            }
        } else {
            if let data = try? JSONEncoder().encode(league) {
                try? data.write(to: leagueFileURL(league.id), options: .atomic)
                upsertIndex(for: league)
            }
        }
    }

    // Helper deep copy via encode/decode to avoid accidental reference sharing
    private func deepCopy<T: Codable>(_ val: T) throws -> T {
        let d = try JSONEncoder().encode(val)
        return try JSONDecoder().decode(T.self, from: d)
    }

    private func loadLeagueFile(id: String) -> LeagueData? {
        let url = leagueFileURL(id)
        guard let data = try? Data(contentsOf: url),
              let lg = try? JSONDecoder().decode(LeagueData.self, from: data) else { return nil }
        if lg.allTimeOwnerStats == nil {
            return AllTimeAggregator.buildAllTime(for: lg, playerCache: allPlayers)
        }
        return lg
    }

    private func loadAllLeagueFiles() {
        leagues = indexEntries.compactMap { loadLeagueFile(id: $0.id) }
        leagues.forEach { DatabaseManager.shared.saveLeague($0) }
    }

    // PATCH: Helper to get valid weeks for season stat aggregation

    private func validWeeksForSeason(_ season: SeasonData, currentWeek: Int) -> [Int] {
        let allWeeks = season.matchupsByWeek?.keys.sorted() ?? []
        return allWeeks.filter { $0 < currentWeek }
    }

    // Public Import

    // Existing import entrypoint (keeps previous signature)
    func fetchAndImportSingleLeague(leagueId: String, username: String) async throws {
        try await fetchAndImportSingleLeague(leagueId: leagueId, username: username, seasonPlayoffOverrides: nil)
    }

    // Overload that accepts per-season overrides
    func fetchAndImportSingleLeague(leagueId: String, username: String, seasonPlayoffOverrides: [String: Int]?) async throws {
        clearCaches()
        let user = try await fetchUser(username: username)
        let baseLeague = try await fetchLeague(leagueId: leagueId)
        // Update the global current week when we fetch league metadata
        self.globalCurrentWeek = max(self.globalCurrentWeek, baseLeague.currentWeek)

        // Persist per-season overrides for this league if provided
        if let overrides = seasonPlayoffOverrides {
            leagueSeasonPlayoffOverrides[leagueId] = overrides
            persistOverrides()
        }

        // Determine top-level fallback playoffStart for backwards compatibility
        let playoffStart = detectPlayoffStartWeek(from: baseLeague)
        leaguePlayoffStartWeeks[leagueId] = playoffStart
        playoffStartWeek = playoffStart

        // Use fetchAllSeasonsForLeague but pass per-season overrides map for this league
        var leagueData = try await fetchAllSeasonsForLeague(league: baseLeague, userId: user.user_id, playoffStartWeek: playoffStart, perSeasonOverrides: seasonPlayoffOverrides)
        // Optionally recompute championships on import if recompute container desired. We leave it untouched here.
        leagueData = AllTimeAggregator.buildAllTime(for: leagueData, playerCache: allPlayers)

        await MainActor.run {
            if let idx = leagues.firstIndex(where: { $0.id == leagueData.id }) {
                leagues[idx] = leagueData
            } else {
                leagues.append(leagueData)
            }
            persistLeagueFile(leagueData)
            saveIndex()
            DatabaseManager.shared.saveLeague(leagueData)
        }
    }

    private func fetchLeague(leagueId: String) async throws -> SleeperLeague {
        let url = URL(string: "https://api.sleeper.app/v1/league/\(leagueId)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(SleeperLeague.self, from: data)
    }

    // NEW public helper to compute detectPlayoffStartWeek from a SleeperLeague (exposed for UI)
    func detectPlayoffStartWeek(from league: SleeperLeague) -> Int {
        if let settings = league.settings,
           let val = settings["playoff_start_week"]?.value as? Int {
            return min(max(13, val), 18)
        }
        return 14
    }

    // NEW: Expose fetchAllLeaguesForUser (already present below) - reused by UI
    func fetchLeagues(userId: String, season: String) async throws -> [SleeperLeague] {
        let url = URL(string: "https://api.sleeper.app/v1/user/\(userId)/leagues/nfl/\(season)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([SleeperLeague].self, from: data)
    }

    func fetchUser(username: String) async throws -> SleeperUser {
        let url = URL(string: "https://api.sleeper.app/v1/user/\(username)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(SleeperUser.self, from: data)
    }

    // NOTE: fetchLeagues(userId:season:) is the single canonical implementation and is defined above (no duplicates)

    func fetchAllLeaguesForUser(username: String, seasons: [String]) async throws -> [SleeperLeague] {
        var out: [SleeperLeague] = []
        let user = try await fetchUser(username: username)
        for s in seasons {
            let list = try await fetchLeagues(userId: user.user_id, season: s)
            out.append(contentsOf: list)
        }
        return out
    }

    private func fetchRosters(leagueId: String) async throws -> [SleeperRoster] {
        if let cached = rostersCache[leagueId] { return cached }
        let url = URL(string: "https://api.sleeper.app/v1/league/\(leagueId)/rosters")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let rosters = try JSONDecoder().decode([SleeperRoster].self, from: data)
        rostersCache[leagueId] = rosters
        return rosters
    }

    private func fetchLeagueUsers(leagueId: String) async throws -> [SleeperUser] {
        if let cached = usersCache[leagueId] { return cached }
        let url = URL(string: "https://api.sleeper.app/v1/league/\(leagueId)/users")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let users = try JSONDecoder().decode([SleeperUser].self, from: data)
        usersCache[leagueId] = users
        return users
    }

    private func fetchPlayersDict() async throws -> [String: RawSleeperPlayer] {
        if playerCache == nil {
            let url = URL(string: "https://api.sleeper.app/v1/players/nfl")!
            let (data, _) = try await URLSession.shared.data(from: url)
            playerCache = try? JSONDecoder().decode([String: RawSleeperPlayer].self, from: data)
        }
        return playerCache ?? [:]
    }

    private func fetchPlayers(ids: [String]) async throws -> [RawSleeperPlayer] {
        if allPlayers.isEmpty {
            allPlayers = try await fetchPlayersDict()
        }
        return ids.compactMap { allPlayers[$0] }
    }

    // --- PATCHED: Ensure every team has a matchup entry for every week played ---
    private func fetchMatchupsByWeek(leagueId: String) async throws -> [Int: [MatchupEntry]] {
        var out: [Int: [MatchupEntry]] = [:]
        var allRosterIds: Set = []

        // Heuristic / dynamic detection:
        //  - Try to fetch league metadata to learn currentWeek (if available).
        //  - Iterate weeks starting at 1 until we see a short run of consecutive empty results
        //    (consecutiveThreshold) OR until we reach a safe cap (maxCap).
        //  - This avoids hardcoding 1...18 and reduces wasted network calls while still capturing
        //    leagues with more or fewer weeks.
        let maxCap = 26                   // safety cap for worst case leagues
        let consecutiveThreshold = 3     // stop after this many empty weeks in a row (heuristic)
        var consecutiveEmpty = 0
        var lastNonEmptyWeek: Int? = nil

        // Try to fetch league metadata for heuristic currentWeek
        let leagueInfo: SleeperLeague? = try? await fetchLeague(leagueId: leagueId)
        let heuristicCurrentWeek = leagueInfo?.currentWeek ?? 1
        // Update the global current week on the manager so views can observe it
        self.globalCurrentWeek = max(self.globalCurrentWeek, heuristicCurrentWeek)

        // searchMax is at least 18 and includes a small buffer beyond currentWeek
        let searchMax = max(18, heuristicCurrentWeek + 2)
        let cap = min(maxCap, searchMax)

        var week = 1
        while week <= cap && consecutiveEmpty < consecutiveThreshold {
            let url = URL(string: "https://api.sleeper.app/v1/league/\(leagueId)/matchups/\(week)")!
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let entries = try? JSONDecoder().decode([MatchupEntry].self, from: data), !entries.isEmpty {
                    out[week] = entries
                    allRosterIds.formUnion(entries.map { $0.roster_id })
                    consecutiveEmpty = 0
                    lastNonEmptyWeek = week
                } else {
                    // empty array returned -> increment empty counter
                    consecutiveEmpty += 1
                }
            } catch {
                // network or decode error -> treat as an empty result for heuristics
                consecutiveEmpty += 1
            }
            week += 1
        }

        // If we still have no roster IDs, fallback to the rosters endpoint
        if allRosterIds.isEmpty {
            if let rosters = try? await fetchRosters(leagueId: leagueId) {
                allRosterIds = Set(rosters.map { $0.roster_id })
            }
        }

        // Determine effective last week to ensure we cover all played weeks.
        // Prefer lastNonEmptyWeek, else use heuristicCurrentWeek, otherwise fallback to 18.
        let effectiveLastWeek: Int = {
            if let last = lastNonEmptyWeek { return last }
            if heuristicCurrentWeek > 1 { return heuristicCurrentWeek - 1 } // if currentWeek points to in-progress week, use previous
            return 18
        }()

        // Ensure each roster has an entry for every week up to effectiveLastWeek
        for wk in 1...effectiveLastWeek {
            var completedEntries = out[wk] ?? []
            let existingIds = Set(completedEntries.map { $0.roster_id })
            let missingIds = allRosterIds.subtracting(existingIds)
            for rid in missingIds {
                // Create placeholder entry but DO NOT assign matchup_id = wk (that collides with real pairing ids).
                // Leave matchup_id nil so conversion/pairing logic can decide correct pairing per-week.
                // NOTE: players_slots should be nil for placeholders so populatePlayersSlots can inject authoritative mappings later.
                completedEntries.append(
                    MatchupEntry(
                        roster_id: rid,
                        matchup_id: nil,
                        points: 0.0,
                        players_points: [:],
                        players_projected_points: [:],
                        starters: [],
                        players: [],
                        players_slots: nil // set to nil so populatePlayersSlots can inject only when appropriate
                    )
                )
            }
            out[wk] = completedEntries
        }

        return out
    }

    private func fetchTransactions(for leagueId: String) async throws -> [SleeperTransaction] {
        if let cached = transactionsCache[leagueId] { return cached }
        var txs: [SleeperTransaction] = []
        for week in 1...18 {
            let url = URL(string: "https://api.sleeper.app/v1/league/\(leagueId)/transactions/\(week)")!
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let parsed = try? JSONDecoder().decode([SleeperTransaction].self, from: data),
               !parsed.isEmpty {
                txs.append(contentsOf: parsed)
            }
        }
        transactionsCache[leagueId] = txs
        return txs
    }

    // Extract playoff start from SleeperLeague settings (kept public as detect helper)
    private func extractPlayoffStartWeek(from league: SleeperLeague) -> Int {
        if let settings = league.settings,
           let val = settings["playoff_start_week"]?.value as? Int {
            return min(max(13, val), 18)
        }
        return 14
    }

    // Public wrapper that actually returns the same detection — kept for backward compatibility
    func detectPlayoffStartWeekJson(from league: SleeperLeague) -> Int {
        return extractPlayoffStartWeek(from: league)
    }

    func setPlayoffStartWeek(_ week: Int) { playoffStartWeek = max(13, min(18, week)) }


    // --- PATCHED SECTION: Robust position assignment for per-season PPW/individualPPW ---
    private func buildTeams(
        leagueId: String,
        rosters: [SleeperRoster],
        users: [SleeperUser],
        parentLeague: LeagueData?,
        lineupPositions: [String],
        transactions: [SleeperTransaction],
        playoffStartWeek: Int,
        matchupsByWeek: [Int: [MatchupEntry]],
        sleeperLeague: SleeperLeague
    ) async throws -> [TeamStanding] {

        let userDisplay: [String: String] = users.reduce(into: [:]) { dict, u in
            let disp = (u.display_name ?? u.username ?? "").trimmingCharacters(in: .whitespaces)
            dict[u.user_id] = disp.isEmpty ? "Owner \(u.user_id)" : disp
        }

        // CENTRALIZED sanitization of lineup positions using SlotUtils
        let startingPositions = SlotUtils.sanitizeStartingSlots(lineupPositions).map(canonicalFlexSlot)
        if lineupPositions.contains(where: { SlotUtils.nonStartingTokens.contains($0.uppercased()) }) {
            // Log the original tokens for telemetry
            let offending = lineupPositions.filter { SlotUtils.nonStartingTokens.contains($0.uppercased()) }
            print("[RosterPositionsWarning] league \(leagueId) roster_positions contains bench/IR/taxi tokens: \(offending)")
        }
        // Debug log of sanitized starting positions
        print("[SlotSanitize] using starting positions: \(startingPositions) for league \(leagueId)")

        let orderedSlots = startingPositions
        let lineupConfig = Dictionary(grouping: startingPositions, by: { $0 }).mapValues { $0.count }

        var results: [TeamStanding] = []

        for roster in rosters {
            let ownerId = roster.owner_id ?? ""
            let teamName = userDisplay[ownerId] ?? "Owner \(ownerId)"

            let rawPlayers = try await fetchPlayers(ids: roster.players ?? [])
            let players: [Player] = rawPlayers.map {
                Player(
                    id: $0.player_id,
                    position: $0.position ?? "UNK",
                    altPositions: $0.fantasy_positions,
                    weeklyScores: weeklyScores(
                        playerId: $0.player_id,
                        rosterId: roster.roster_id,
                        matchups: matchupsByWeek
                    )
                )
            }

            let settings = roster.settings ?? [:]
            let wins = (settings["wins"]?.value as? Int) ?? 0
            let losses = (settings["losses"]?.value as? Int) ?? 0
            let ties = (settings["ties"]?.value as? Int) ?? 0
            let standing = (settings["rank"]?.value as? Int) ?? 0

            var actualTotal = 0.0, actualOff = 0.0, actualDef = 0.0
            var maxTotal = 0.0, maxOff = 0.0, maxDef = 0.0

            var posTotals: [String: Double] = [:]
            var posStartCounts: [String: Int] = [:]

            var weeklyActualLineupPoints: [Int: Double] = [:]
            var actualStarterPosTotals: [String: Int] = [:]
            var actualStarterWeeks = 0

            var actualStartersByWeek: [Int: [String]] = [:]

            let allWeeks = matchupsByWeek.keys.sorted()
            let currentWeek = sleeperLeague.currentWeek
            let completedWeeks = currentWeek > 1
                ? allWeeks.filter { $0 < currentWeek }
                : allWeeks
            let weeksToUse = completedWeeks
            var weeksCounted = 0
            var actualPosTotals: [String: Double] = [:]
            var actualPosStartCounts: [String: Int] = [:]
            var actualPosWeeks: [String: Set<Int>] = [:]

            // --- MAIN PATCHED SECTION: Use robust credited position for per-week actual lineup ---
            for week in weeksToUse {
                guard let allEntries = matchupsByWeek[week],
                      let myEntry = allEntries.first(where: { $0.roster_id == roster.roster_id })
                else { continue }

                var weekHadValidScore = false
                var thisWeekActual = 0.0

                if let starters = myEntry.starters, let playersPoints = myEntry.players_points {
                    let slots = orderedSlots
                    let paddedStarters: [String] = {
                        if starters.count < slots.count {
                            return starters + Array(repeating: "0", count: slots.count - starters.count)
                        } else if starters.count > slots.count {
                            return Array(starters.prefix(slots.count))
                        }
                        return starters
                    }()

                    var startersForThisWeek: [String] = []
                    // --- PATCH: Assign only ONE start per slot (not per eligible position!) ---
                    for idx in 0..()
                var strictSlots: [String] = []
                var flexSlots: [String] = []
                for slot in orderedSlots {
                    let allowed = allowedPositions(for: slot)
                    if allowed.count == 1 &&
                        !isIDPFlex(slot) &&
                        !offensiveFlexSlots.contains(canonicalFlexSlot(slot)) {
                        strictSlots.append(slot)
                    } else {
                        flexSlots.append(slot)
                    }
                }
                let optimalOrder = strictSlots + flexSlots

                var used = Set()
                var weekMax = 0.0, weekOff = 0.0, weekDef = 0.0

                for slot in optimalOrder {
                    let allowed = allowedPositions(for: slot)
                    let pick = candidates
                        .filter { !used.contains($0.id) && isEligible($0, allowed: allowed) }
                        .max(by: { $0.points < $1.points })

                    guard let best = pick else { continue }
                    used.insert(best.id)
                    weekMax += best.points
                    // --- PATCH: Use global SlotPositionAssigner for credited position ---
                    let counted = SlotPositionAssigner.countedPosition(for: slot, candidatePositions: best.fantasy, base: best.basePos)
                    let credited = PositionNormalizer.normalize(counted)
                    if offensivePositions.contains(credited) { weekOff += best.points }
                    else if defensivePositions.contains(credited) { weekDef += best.points }
                    posTotals[credited, default: 0] += best.points
                    posStartCounts[credited, default: 0] += 1
                }

                maxTotal += weekMax
                maxOff += weekOff
                maxDef += weekDef
            }

            let managementPercent = maxTotal > 0 ? (actualTotal / maxTotal) * 100 : 0
            let offensiveMgmt = maxOff > 0 ? (actualOff / maxOff * 100) : 0
            let defensiveMgmt = maxDef > 0 ? (actualDef / maxDef) * 100 : 0
            let teamPPW = weeksCounted > 0 ? actualTotal / Double(weeksCounted) : 0

            // --- PATCHED SECTION: Use robust credited position counts for individualPPW/positionPPW ---
            var positionPPW: [String: Double] = [:]
            var individualPPW: [String: Double] = [:]
            for (pos, total) in actualPosTotals {
                let starts = Double(actualPosStartCounts[pos] ?? 0)
                individualPPW[pos] = starts > 0 ? total / starts : 0
                positionPPW[pos] = weeksCounted > 0 ? total / Double(weeksCounted) : 0
            }

            var strengths: [String] = []
            if managementPercent >= 85 { strengths.append("Efficient lineup mgmt") }
            if actualOff > actualDef + 75 { strengths.append("Strong offense") }
            if actualDef > actualOff + 75 { strengths.append("Strong defense") }

            var weaknesses: [String] = []
            if managementPercent < 65 { weaknesses.append("Lineup efficiency low") }

            let playoffRec = playoffRecord(settings)
            let champCount = championships(settings)
            let pointsAgainst = ((settings["fpts_against"]?.value as? Double) ?? 0)
                              + (((settings["fpts_against_decimal"]?.value as? Double) ?? 0)/100)

            let txs = try await fetchTransactions(for: leagueId)
            let waiverMoves = waiverMoveCount(rosterId: roster.roster_id, in: txs)
            let faabSpentVal = faabSpent(rosterId: roster.roster_id, in: txs)
            let trades = tradeCount(rosterId: roster.roster_id, in: txs)


            let standingModel = TeamStanding(
                id: String(roster.roster_id),
                name: teamName,
                positionStats: [],
                ownerId: ownerId,
                roster: players,
                leagueStanding: standing,
                pointsFor: actualTotal,
                maxPointsFor: maxTotal,
                managementPercent: managementPercent,
                teamPointsPerWeek: teamPPW,
                winLossRecord: "\(wins)-\(losses)-\(ties)",
                bestGameDescription: nil,
                biggestRival: nil,
                strengths: strengths,
                weaknesses: weaknesses,
                playoffRecord: playoffRec,
                championships: champCount,
                winStreak: nil,
                lossStreak: nil,
                offensivePointsFor: actualOff,
                maxOffensivePointsFor: maxOff,
                offensiveManagementPercent: offensiveMgmt,
                averageOffensivePPW: weeksCounted > 0 ? actualOff / Double(weeksCounted) : 0,
                offensiveStrengths: strengths.filter { $0.lowercased().contains("offense") },
                offensiveWeaknesses: weaknesses.filter { $0.lowercased().contains("offense") },
                positionAverages: positionPPW,
                individualPositionAverages: individualPPW,
                defensivePointsFor: actualDef,
                maxDefensivePointsFor: maxDef,
                defensiveManagementPercent: defensiveMgmt,
                averageDefensivePPW: weeksCounted > 0 ? actualDef / Double(weeksCounted) : 0,
                defensiveStrengths: strengths.filter { $0.lowercased().contains("defense") },
                defensiveWeaknesses: weaknesses.filter { $0.lowercased().contains("defense") },
                pointsScoredAgainst: pointsAgainst,
                league: parentLeague,
                lineupConfig: lineupConfig,
                weeklyActualLineupPoints: weeklyActualLineupPoints.isEmpty ? nil : weeklyActualLineupPoints,
                actualStartersByWeek: actualStartersByWeek.isEmpty ? nil : actualStartersByWeek,
                actualStarterPositionCounts: actualStarterPosTotals.isEmpty ? nil : actualStarterPosTotals,
                actualStarterWeeks: actualStarterWeeks == 0 ? nil : actualStarterWeeks,
                waiverMoves: waiverMoves,
                faabSpent: faabSpentVal,
                tradesCompleted: trades
            )

            results.append(standingModel)
        }
        return results
    }

    private func weeklyScores(
        playerId: String,
        rosterId: Int,
        matchups: [Int: [MatchupEntry]]
    ) -> [PlayerWeeklyScore] {
        var scores: [PlayerWeeklyScore] = []
        for (week, entries) in matchups {
            guard let me = entries.first(where: { $0.roster_id == rosterId }),
                  let pts = me.players_points?[playerId] else { continue }
            scores.append(PlayerWeeklyScore(
                week: week,
                points: pts,
                player_id: playerId,
                points_half_ppr: pts,
                matchup_id: me.matchup_id ?? 0,
                points_ppr: pts,
                points_standard: pts
            ))
        }
        return scores.sorted { $0.week < $1.week }
    }
    
    // MARK: - Transactions Helpers

        private func waiverMoveCount(rosterId: Int, in tx: [SleeperTransaction]) -> Int {
            tx.filter {
                let t = ($0.type ?? "").lowercased()
                return (t == "waiver" || t == "free_agent")
                    && ($0.status ?? "").lowercased() == "complete"
                    && ($0.roster_ids?.contains(rosterId) ?? false)
            }.count
        }

        private func faabSpent(rosterId: Int, in tx: [SleeperTransaction]) -> Double {
            tx.reduce(0.0) { acc, tr in
                let t = (tr.type ?? "").lowercased()
                guard t == "waiver",
                      (tr.status ?? "").lowercased() == "complete",
                      (tr.roster_ids?.contains(rosterId) ?? false) else { return acc }
                return acc + Double(tr.waiver_bid ?? 0)
            }
        }

        private func tradeCount(rosterId: Int, in tx: [SleeperTransaction]) -> Int {
            tx.filter {
                ($0.type ?? "").lowercased() == "trade"
                && ($0.status ?? "").lowercased() == "complete"
                && ($0.roster_ids?.contains(rosterId) ?? false)
            }.count
        }

    private struct Candidate {
        let id: String
        let basePos: String
        let fantasy: [String]
        let points: Double
    }

    // --- PATCH: Normalize allowed position set before checking eligibility
    private func isEligible(_ c: Candidate, allowed: Set<String>) -> Bool {
        // Defensive normalization of both sides
        let normalizedAllowed = Set(allowed.map { PositionNormalizer.normalize($0) })
        if normalizedAllowed.contains(PositionNormalizer.normalize(c.basePos)) { return true }
        return !normalizedAllowed.intersection(Set(c.fantasy.map { PositionNormalizer.normalize($0) })).isEmpty
    }

    private func playoffRecord(_ settings: [String: AnyCodable]) -> String? {
        let w = (settings["playoff_wins"]?.value as? Int) ?? 0
        let l = (settings["playoff_losses"]?.value as? Int) ?? 0
        return (w + l) > 0 ? "\(w)-\(l)" : nil
    }

    private func championships(_ settings: [String: AnyCodable]) -> Int? {
        if let champ = settings["champion"]?.value as? Bool, champ { return 1 }
        if let c = settings["championships"]?.value as? Int { return c }
        if let arr = settings["championship_seasons"]?.value as? [String], !arr.isEmpty { return arr.count }
        return nil
    }

    // --- PATCH: Normalize all allowed positions for slot assignment
    private func allowedPositions(for slot: String) -> Set<String> {
        switch canonicalFlexSlot(slot) {
        case "QB","RB","WR","TE","K","DL","LB","DB":
            return Set([PositionNormalizer.normalize(canonicalFlexSlot(slot))])
        case "FLEX":
            return Set(["RB","WR","TE"].map { PositionNormalizer.normalize($0) })
        case "WRRB_FLEX":
            return Set(["WR","RB"].map { PositionNormalizer.normalize($0) })
        case "REC_FLEX":
            return Set(["WR","TE"].map { PositionNormalizer.normalize($0) })
        case "SUPER_FLEX":
            return Set(["QB","RB","WR","TE"].map { PositionNormalizer.normalize($0) })
        case "IDP_FLEX":
            return Set(["DL","LB","DB"].map { PositionNormalizer.normalize($0) })
        default:
            return Set([PositionNormalizer.normalize(canonicalFlexSlot(slot))])
        }
    }

    private func isIDPFlex(_ slot: String) -> Bool {
        canonicalFlexSlot(slot) == "IDP_FLEX"
    }

    // --- PATCH: Remove local countedPosition function, use global SlotPositionAssigner instead

    // --- PATCH: Remove local mappedPositionForStarter, use SlotPositionAssigner if needed elsewhere ---

    private func baseLeagueName(_ name: String) -> String {
        let pattern = "[\\p{Emoji}\\p{Emoji_Presentation}\\p{Emoji_Modifier_Base}\\p{Emoji_Component}\\p{Symbol}\\p{Punctuation}]"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: name.utf16.count)
        let stripped = regex?.stringByReplacingMatches(in: name, options: [], range: range, withTemplate: "") ?? name
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Updated to accept per-season overrides map; uses override when building SeasonData.playoffStartWeek
    private func fetchAllSeasonsForLeague(league: SleeperLeague, userId: String, playoffStartWeek: Int, perSeasonOverrides: [String: Int]?) async throws -> LeagueData {
        let currentYear = Calendar.current.component(.year, from: Date())
        let startYear = currentYear - 9
        let base = baseLeagueName(league.name ?? "")
        var seasonData: [SeasonData] = []

        for yr in startYear...currentYear {
            let seasonId = "\(yr)"
            let userLeagues = try await fetchLeagues(userId: userId, season: seasonId)
            if let seasonLeague = userLeagues.first(where: { baseLeagueName($0.name ?? "") == base }) {
                let rosters = try await fetchRosters(leagueId: seasonLeague.league_id)
                let users = try await fetchLeagueUsers(leagueId: seasonLeague.league_id)
                let tx = try await fetchTransactions(for: seasonLeague.league_id)
                var matchupsByWeek = try await fetchMatchupsByWeek(leagueId: seasonLeague.league_id)

                // NEW: Populate players_slots from roster settings if present so downstream logic can
                // rely on authoritative per-player tokens (IR, TAXI, etc.)
                populatePlayersSlots(&matchupsByWeek, rosters: rosters)

                // SANITIZE roster_positions early and log if bench-like tokens are present
                let rawRosterPositions = seasonLeague.roster_positions ?? []
                if rawRosterPositions.contains(where: { SlotUtils.nonStartingTokens.contains($0.uppercased()) }) {
                    let offending = rawRosterPositions.filter { SlotUtils.nonStartingTokens.contains($0.uppercased()) }
                    print("[RosterPositionsWarning] league \(seasonLeague.league_id) roster_positions contains bench/IR/taxi tokens: \(offending)")
                }
                let sanitizedPositions = SlotUtils.sanitizeStartingSlots(seasonLeague.roster_positions ?? []).map(canonicalFlexSlot)
                print("[SlotSanitize] using starting positions: \(sanitizedPositions) for league \(seasonLeague.league_id)")

                // Auto-detect playoff start
                let autoDetected = detectPlayoffStartWeek(from: seasonLeague)
                let seasonOverride = perSeasonOverrides?[seasonId]
                let seasonPlayoffStart = seasonOverride ?? autoDetected
                let source = seasonOverride != nil ? "explicit" : "auto"
                print("[PlayoffDetect] season=\(seasonId) league=\(seasonLeague.league_id) detectedPlayoffStart=\(seasonPlayoffStart) source=\(source)")

                // Pass sanitized lineup positions into buildTeams
                let teams = try await buildTeams(
                    leagueId: seasonLeague.league_id,
                    rosters: rosters,
                    users: users,
                    parentLeague: nil,
                    lineupPositions: sanitizedPositions,
                    transactions: tx,
                    playoffStartWeek: seasonPlayoffStart,
                    matchupsByWeek: matchupsByWeek,
                    sleeperLeague: seasonLeague
                )
                let matchups = convertToSleeperMatchups(matchupsByWeek)
                // Use season-specific playoff start here (was incorrectly using outer playoffStartWeek)
                seasonData.append(SeasonData(id: seasonId, season: seasonId, teams: teams, playoffStartWeek: seasonPlayoffStart, playoffTeamsCount: nil, matchups: matchups, matchupsByWeek: matchupsByWeek))
            }
        }

        let latestSeason = seasonData.last?.season ?? league.season ?? "\(currentYear)"
        let latestTeams = seasonData.last?.teams ?? []

        return LeagueData(
            id: league.league_id,
            name: league.name ?? "Unnamed League",
            season: latestSeason,
            teams: latestTeams,
            seasons: seasonData,
            startingLineup: league.roster_positions ?? []
        )
    }

    // New helper: populate players_slots in matchupsByWeek using any per-roster settings that contain per-player mappings.
    // This function is conservative: it only writes players_slots when it finds an obvious mapping of (playerId -> token string)
    // inside a roster.settings entry. Many Sleeper import payloads do not include such mappings; in those cases no changes occur.
    private func populatePlayersSlots(_ matchupsByWeek: inout [Int: [MatchupEntry]], rosters: [SleeperRoster]) {
        for roster in rosters {
            guard let settings = roster.settings, !settings.isEmpty else { continue }

            // Attempt to find any dictionary-like value whose keys look like player ids (strings) and values are strings.
            var discovered: [String: String] = [:]
            for (k, any) in settings {
                // Prefer a mapping typed as [String: AnyCodable]
                if let map = any.value as? [String: AnyCodable] {
                    var candidate: [String: String] = [:]
                    for (pid, v) in map {
                        if let str = v.value as? String, !str.isEmpty {
                            candidate[pid] = canonicalFlexSlot(str)
                        } else if let num = v.value as? Int {
                            candidate[pid] = String(num)
                        }
                    }
                    if !candidate.isEmpty {
                        // Merge into discovered if keys look like player IDs (heuristic: all numeric or length >= 3)
                        for (pid, token) in candidate {
                            if pid.count >= 3 { discovered[pid] = token }
                        }
                    }
                } else if let map2 = any.value as? [String: String] {
                    for (pid, token) in map2 {
                        if pid.count >= 3 { discovered[pid] = canonicalFlexSlot(token) }
                    }
                } else if let mapAny = any.value as? [String: Any] {
                    var candidate: [String: String] = [:]
                    for (pid, v) in mapAny {
                        if let s = v as? String { candidate[pid] = canonicalFlexSlot(s) }
                        else if let n = v as? Int { candidate[pid] = String(n) }
                    }
                    if !candidate.isEmpty {
                        for (pid, token) in candidate where pid.count >= 3 {
                            discovered[pid] = token
                        }
                    }
                }
                // If we found something, we prefer the first meaningful mapping (break)
                if !discovered.isEmpty { break }
            }

            if discovered.isEmpty { continue }

            // Now inject discovered mapping into any MatchupEntry rows for this roster that lack players_slots.
            var appliedCount = 0
            for (wk, entries) in matchupsByWeek {
                var copy = entries
                for i in 0..<copy.count where copy[i].roster_id == roster.roster_id && copy[i].players_slots == nil {
                    copy[i] = MatchupEntry(
                        roster_id: copy[i].roster_id,
                        matchup_id: copy[i].matchup_id,
                        points: copy[i].points,
                        players_points: copy[i].players_points,
                        players_projected_points: copy[i].players_projected_points,
                        starters: copy[i].starters,
                        players: copy[i].players,
                        players_slots: discovered
                    )
                    appliedCount += 1
                }
                matchupsByWeek[wk] = copy
            }

            if appliedCount > 0 {
                print("[PlayersSlotsMigration] roster \(roster.roster_id): populated players_slots for \(appliedCount) matchup entries (source: roster.settings)")
                // Print up to 10 sample mappings for verification
                let sample = discovered.prefix(10).map { "\($0.key)->\($0.value)" }.joined(separator: ", ")
                print("[PlayersSlotsMigration] sample mappings: \(sample)")
            }
        }
    }

    func saveLeagues() {
        for lg in leagues {
            persistLeagueFile(lg)
        }
        saveIndex()
    }

    func loadLeagues() {
        loadIndex()
        loadAllLeagueFiles()
    }

    func rebuildAllTime(leagueId: String) {
        guard let idx = leagues.firstIndex(where: { $0.id == leagueId }) else { return }
        leagues[idx] = AllTimeAggregator.buildAllTime(for: leagues[idx], playerCache: allPlayers)
        persistLeagueFile(leagues[idx])
        saveIndex()
    }

    // MARK: — New: recompute + persist computed championships (safe, non-destructive by default)

    /// Recompute championships from final bracket winners for a single league, optionally persist into
    /// LeagueData.computedChampionships and SeasonData.computedChampionOwnerId.
    ///
    /// - Parameters:
    ///   - leagueId: league id to operate on (must be already imported into the active user's store)
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

        // Build updated LeagueData with computed container + per-season computedChampionOwnerId
        var newSeasons = league.seasons
        for i in 0..<newSeasons.count {
            let sid = newSeasons[i].id
            var updated = newSeasons[i]
            updated.computedChampionOwnerId = seasonChampions[sid] ?? nil
            newSeasons[i] = updated
        }

        var newLeague = league
        newLeague.seasons = newSeasons
        if persistComputedContainer {
            newLeague.computedChampionships = aggregated
        }

        if overwriteTeamStanding {
            for i in 0..<newLeague.seasons.count {
                for j in 0..<newLeague.seasons[i].teams.count {
                    let oid = newLeague.seasons[i].teams[j].ownerId
                    let comp = aggregated[oid] ?? 0
                    newLeague.seasons[i].teams[j] = TeamStanding(
                        id: newLeague.seasons[i].teams[j].id,
                        name: newLeague.seasons[i].teams[j].name,
                        positionStats: newLeague.seasons[i].teams[j].positionStats,
                        ownerId: oid,
                        roster: newLeague.seasons[i].teams[j].roster,
                        leagueStanding: newLeague.seasons[i].teams[j].leagueStanding,
                        pointsFor: newLeague.seasons[i].teams[j].pointsFor,
                        maxPointsFor: newLeague.seasons[i].teams[j].maxPointsFor,
                        managementPercent: newLeague.seasons[i].teams[j].managementPercent,
                        teamPointsPerWeek: newLeague.seasons[i].teams[j].teamPointsPerWeek,
                        winLossRecord: newLeague.seasons[i].teams[j].winLossRecord,
                        bestGameDescription: newLeague.seasons[i].teams[j].bestGameDescription,
                        biggestRival: newLeague.seasons[i].teams[j].biggestRival,
                        strengths: newLeague.seasons[i].teams[j].strengths,
                        weaknesses: newLeague.seasons[i].teams[j].weaknesses,
                        playoffRecord: newLeague.seasons[i].teams[j].playoffRecord,
                        championships: comp,
                        winStreak: newLeague.seasons[i].teams[j].winStreak,
                        lossStreak: newLeague.seasons[i].teams[j].lossStreak,
                        offensivePointsFor: newLeague.seasons[i].teams[j].offensivePointsFor,
                        maxOffensivePointsFor: newLeague.seasons[i].teams[j].maxOffensivePointsFor,
                        offensiveManagementPercent: newLeague.seasons[i].teams[j].offensiveManagementPercent,
                        averageOffensivePPW: newLeague.seasons[i].teams[j].averageOffensivePPW,
                        offensiveStrengths: newLeague.seasons[i].teams[j].offensiveStrengths,
                        offensiveWeaknesses: newLeague.seasons[i].teams[j].offensiveWeaknesses,
                        positionAverages: newLeague.seasons[i].teams[j].positionAverages,
                        individualPositionAverages: newLeague.seasons[i].teams[j].individualPositionAverages,
                        defensivePointsFor: newLeague.seasons[i].teams[j].defensivePointsFor,
                        maxDefensivePointsFor: newLeague.seasons[i].teams[j].maxDefensivePointsFor,
                        defensiveManagementPercent: newLeague.seasons[i].teams[j].defensiveManagementPercent,
                        averageDefensivePPW: newLeague.seasons[i].teams[j].averageDefensivePPW,
                        defensiveStrengths: newLeague.seasons[i].teams[j].defensiveStrengths,
                        defensiveWeaknesses: newLeague.seasons[i].teams[j].defensiveWeaknesses,
                        pointsScoredAgainst: newLeague.seasons[i].teams[j].pointsScoredAgainst,
                        league: newLeague.seasons[i].teams[j].league,
                        lineupConfig: newLeague.seasons[i].teams[j].lineupConfig,
                        weeklyActualLineupPoints: newLeague.seasons[i].teams[j].weeklyActualLineupPoints,
                        actualStartersByWeek: newLeague.seasons[i].teams[j].actualStartersByWeek,
                        actualStarterPositionCounts: newLeague.seasons[i].teams[j].actualStarterPositionCounts,
                        actualStarterWeeks: newLeague.seasons[i].teams[j].actualStarterWeeks,
                        waiverMoves: newLeague.seasons[i].teams[j].waiverMoves,
                        faabSpent: newLeague.seasons[i].teams[j].faabSpent,
                        tradesCompleted: newLeague.seasons[i].teams[j].tradesCompleted
                    )
                }
            }
        }

        // Persist changes
        if let data = try? JSONEncoder().encode(newLeague) {
            try data.write(to: leagueFileURL(leagueId), options: .atomic)
        }
        await MainActor.run {
            if let idx = leagues.firstIndex(where: { $0.id == leagueId }) {
                leagues[idx] = AllTimeAggregator.buildAllTime(for: newLeague, playerCache: allPlayers)
                persistLeagueFile(leagues[idx])
                saveIndex()
            }
        }

        // Emit aggregated summary
        for (owner, cnt) in aggregated {
            print("[ChampionRecompute] owner=\(owner) computedChampionships=\(cnt)")
        }

        return (report, aggregated)
    }

    private func backupLeagueFile(_ leagueId: String) throws -> URL {
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

    // MARK: - Bulk Fetch / Refresh Helpers (kept as methods on class)

    func refreshAllLeaguesIfNeeded(username: String?, force: Bool = false) async {
        guard !leagues.isEmpty else { return }
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        let targets = leagues.filter {
            let last = Self._lastRefresh[$0.id] ?? .distantPast
            return force || now.timeIntervalSince(last) >= refreshThrottleInterval
        }
        guard !targets.isEmpty else { return }

        let maxConcurrent = 3
        var updated: [LeagueData] = []
        var active = 0

        for league in targets {
            while active >= maxConcurrent {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            active += 1
            Task {
                defer { active -= 1 }
                do {
                    if let refreshed = try await refreshLatestSeason(for: league) {
                        await MainActor.run {
                            updated.append(refreshed)
                            Self._lastRefresh[league.id] = now
                        }
                    }
                } catch {
                    // swallow and continue; individual league refresh errors should not abort whole batch
                    print("[Refresh] failed refresh for \(league.id): \(error)")
                }
            }
        }

        while active > 0 {
            try? await Task.sleep(nanoseconds: 60_000_000)
        }

        guard !updated.isEmpty else { return }
        for newLeague in updated {
            if let idx = leagues.firstIndex(where: { $0.id == newLeague.id }) {
                leagues[idx] = newLeague
                persistLeagueFile(newLeague)
            }
        }
        saveIndex()
    }

    func forceRefreshAllLeagues(username: String?) async {
        await refreshAllLeaguesIfNeeded(username: username, force: true)
    }

    private func refreshLatestSeason(for league: LeagueData) async throws -> LeagueData? {
        guard let latestSeason = league.seasons.sorted(by: { $0.id < $1.id }).last else { return nil }

        let baseLeague = try await fetchLeague(leagueId: league.id)
        // update global week when refreshing
        self.globalCurrentWeek = max(self.globalCurrentWeek, baseLeague.currentWeek)

        let rosters = try await fetchRosters(leagueId: league.id)
        let users = try await fetchLeagueUsers(leagueId: league.id)
        let tx = try await fetchTransactions(for: league.id)
        var matchupsByWeek = try await fetchMatchupsByWeek(leagueId: league.id)

        // Populate players_slots from roster settings where possible
        populatePlayersSlots(&matchupsByWeek, rosters: rosters)

        let playoffStart = leagueSeasonPlayoffOverrides[league.id]?[latestSeason.id] ?? leaguePlayoffStartWeeks[league.id] ?? playoffStartWeek

        // Sanitize lineup positions from league.startingLineup before passing to buildTeams
        let sanitized = SlotUtils.sanitizeStartingSlots(league.startingLineup).map(canonicalFlexSlot)
        if league.startingLineup.contains(where: { SlotUtils.nonStartingTokens.contains($0.uppercased()) }) {
            let offending = league.startingLineup.filter { SlotUtils.nonStartingTokens.contains($0.uppercased()) }
            print("[RosterPositionsWarning] league \(league.id) startingLineup contains bench/IR/taxi tokens: \(offending)")
        }
        print("[SlotSanitize] using starting positions: \(sanitized) for refresh of league \(league.id)")

        let teams = try await buildTeams(
            leagueId: league.id,
            rosters: rosters,
            users: users,
            parentLeague: nil,
            lineupPositions: sanitized,
            transactions: tx,
            playoffStartWeek: playoffStart,
            matchupsByWeek: matchupsByWeek,
            sleeperLeague: baseLeague
        )
        var newSeasons = league.seasons
        if let i = newSeasons.firstIndex(where: { $0.id == latestSeason.id }) {
            let matchups = convertToSleeperMatchups(matchupsByWeek)
            // Use the local playoffStart variable (was incorrectly using property playoffStartWeek)
            newSeasons[i] = SeasonData(id: latestSeason.id, season: latestSeason.season, teams: teams, playoffStartWeek: playoffStart, playoffTeamsCount: nil, matchups: matchups, matchupsByWeek: matchupsByWeek)
        }

        let updated = LeagueData(
            id: league.id,
            name: league.name,
            season: league.season,
            teams: teams,
            seasons: newSeasons,
            startingLineup: league.startingLineup
        )

        return AllTimeAggregator.buildAllTime(for: updated, playerCache: allPlayers)
    }

    func refreshLeagueData(leagueId: String, completion: @escaping (Result<LeagueData, Error>) -> Void) {
        if let existingLeague = leagues.first(where: { $0.id == leagueId }) {
            completion(.success(existingLeague))
        } else {
            completion(.failure(NSError(domain: "LeagueManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "League not found"])))
        }
    }

    /// CONVERT TO SLEEPER MATCHUPS — robust pairing logic
    /// Ensures that for each week we produce pairs of entries that share the same matchupId.
    /// - existing groups with two entries are preserved
    /// - singleton groups and nil-mid entries are paired deterministically by roster_id (adjacent pair)
    /// - synthetic negative matchupIds are used when no existing matchup_id is available for the pair
    private func convertToSleeperMatchups(_ matchupsByWeek: [Int: [MatchupEntry]]) -> [SleeperMatchup] {
        var result: [SleeperMatchup] = []
        var syntheticId = -1

        // Process each week independently
        for (week, entries) in matchupsByWeek.sorted(by: { $0.key < $1.key }) {
            // Group entries by explicit matchup_id (non-nil)
            var groupsByMid: [Int: [MatchupEntry]] = [:]
            var nilMidEntries: [MatchupEntry] = []

            for entry in entries {
                if let mid = entry.matchup_id {
                    groupsByMid[mid, default: []].append(entry)
                } else {
                    nilMidEntries.append(entry)
                }
            }

            var syntheticAssignedCount = 0

            // Keep groups that already have exactly 2 entries
            for (mid, group) in groupsByMid {
                if group.count == 2 {
                    for entry in group {
                        result.append(SleeperMatchup(
                            starters: entry.starters ?? [],
                            rosterId: entry.roster_id,
                            players: entry.players ?? [],
                            matchupId: mid,
                            points: entry.points ?? 0.0,
                            customPoints: nil,
                            week: week
                        ))
                    }
                } else if group.count > 2 {
                    // If more than 2 entries share a matchup_id (rare), pair them sequentially by roster_id
                    let sortedGroup = group.sorted { $0.roster_id < $1.roster_id }
                    var i = 0
                    while i < sortedGroup.count {
                        if i + 1 < sortedGroup.count {
                            let a = sortedGroup[i], b = sortedGroup[i+1]
                            for entry in [a, b] {
                                result.append(SleeperMatchup(
                                    starters: entry.starters ?? [],
                                    rosterId: entry.roster_id,
                                    players: entry.players ?? [],
                                    matchupId: mid,
                                    points: entry.points ?? 0.0,
                                    customPoints: nil,
                                    week: week
                                ))
                            }
                            i += 2
                        } else {
                            // leftover singleton — treat as nil-mid entry (pair later)
                            nilMidEntries.append(sortedGroup[i])
                            i += 1
                        }
                    }
                } else {
                    // singleton — collect for pairing
                    nilMidEntries.append(group[0])
                }
            }

            // Now pair all nil-mid entries deterministically by roster_id (adjacent pairs)
            let sortedNil = nilMidEntries.sorted { $0.roster_id < $1.roster_id }
            var idx = 0
            while idx < sortedNil.count {
                if idx + 1 < sortedNil.count {
                    let a = sortedNil[idx]
                    let b = sortedNil[idx + 1]

                    // Prefer to use an existing mid if either entry had one (should be unlikely here),
                    // otherwise assign a synthetic negative id so both entries share the same id.
                    let midToUse: Int
                    if let ma = a.matchup_id { midToUse = ma }
                    else if let mb = b.matchup_id { midToUse = mb }
                    else { midToUse = syntheticId; syntheticId -= 1; syntheticAssignedCount += 1 }

                    for entry in [a, b] {
                        result.append(SleeperMatchup(
                            starters: entry.starters ?? [],
                            rosterId: entry.roster_id,
                            players: entry.players ?? [],
                            matchupId: midToUse,
                            points: entry.points ?? 0.0,
                            customPoints: nil,
                            week: week
                        ))
                    }
                    idx += 2
                } else {
                    // odd leftover — create a single SleeperMatchup with synthetic id (no opponent)
                    let a = sortedNil[idx]
                    let midToUse = syntheticId; syntheticId -= 1; syntheticAssignedCount += 1
                    result.append(SleeperMatchup(
                        starters: a.starters ?? [],
                        rosterId: a.roster_id,
                        players: a.players ?? [],
                        matchupId: midToUse,
                        points: a.points ?? 0.0,
                        customPoints: nil,
                        week: week
                    ))
                    idx += 1
                }
            }

            // Emit a diagnostic for this week
            print("[MatchupConvert] league=unknown week=\(week) entries=\(entries.count) syntheticAssigned=\(syntheticAssignedCount)")
        }

        // Sort result by matchupId for deterministic ordering
        return result.sorted { $0.matchupId < $1.matchupId }
    }

    // NEW: Small helper to refresh the manager's globalCurrentWeek from the Sleeper API for a specific league.
    // Non-destructive: only updates published properties (globalCurrentWeek and leaguePlayoffStartWeeks[leagueId]).
    // Safe to call from UI .onChange handlers; failure is logged but does not throw.
    func refreshGlobalCurrentWeek(for leagueId: String) async {
        do {
            let leagueMeta = try await fetchLeague(leagueId: leagueId)
            let current = leagueMeta.currentWeek
            // detectPlayoffStartWeek(from:) is non-mutating; store a per-league fallback for downstream use.
            let detectedPlayoffStart = detectPlayoffStartWeek(from: leagueMeta)
            await MainActor.run {
                // Keep globalCurrentWeek monotonic upwards to avoid regressions if older data is fetched.
                self.globalCurrentWeek = max(self.globalCurrentWeek, current)
                // Record the detected playoff start week for the league (non-destructive)
                self.leaguePlayoffStartWeeks[leagueId] = detectedPlayoffStart
            }
            print("[GlobalWeekRefresh] league=\(leagueId) currentWeek=\(current) detectedPlayoffStart=\(detectedPlayoffStart)")
        } catch {
            print("[GlobalWeekRefresh] league=\(leagueId) failed to refresh global week: \(error)")
        }
    }
}
