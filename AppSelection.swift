//
//  AppSelection.swift
//  DynastyStatDrop
//
//  Centralized season selection logic for all views.
//  OwnerId aware All Time selection
//  Added:
//   - Persistence of last selected league per username
//   - Helper to load persisted selection
//   - OwnerId aware team selection (uses Sleeper userId if available)
//   - Centralized season/team selection logic.
//   - Always prefers current year season if present.
//   - Exposes helpers for views to use and sync selection state.
//
//  FIXED: Default team selection after Sleeper league import always matches user's team
//         by username (imported Sleeper username) and, if available, by userId.
//         Only falls back to first team if neither match is found.
//         Selection persists across all main views and only changes on explicit user action.
//

import SwiftUI

final class AppSelection: ObservableObject {
    @Published var userTeam: String = ""              // display name
    @Published var leagues: [LeagueData] = []
    @Published var selectedLeagueId: String? = nil
    @Published var selectedTeamId: String? = nil      // current season team id
    @Published var selectedSeason: String = ""        // season id or "All Time"

    // New: Track if user has manually selected a team
    @Published var userHasManuallySelectedTeam: Bool = false

    // Store the most recent Sleeper username used for import, for team matching
    @Published var lastImportedSleeperUsername: String? = nil
    @Published var lastImportedSleeperUserId: String? = nil
    @Published var currentUsername: String? = nil
    // Helper to get last selected league key
    private func lastSelectedLeagueKey(for username: String) -> String {
        "dsd.lastSelectedLeague.\(username)"
    }

    var selectedLeague: LeagueData? {
        leagues.first { $0.id == selectedLeagueId }
    }

    var isAllTimeMode: Bool { selectedSeason == "All Time" }

    // In All Time mode we still reference the current season’s matching team (latest)
    var selectedOwnerId: String? {
        guard let league = selectedLeague else { return nil }
        let latest = league.seasons.sorted { $0.id < $1.id }.last
        return latest?.teams.first(where: { $0.id == selectedTeamId })?.ownerId
    }

    var selectedTeam: TeamStanding? {
        guard let league = selectedLeague else { return nil }
        if isAllTimeMode {
            let latest = league.seasons.sorted { $0.id < $1.id }.last
            return latest?.teams.first(where: { $0.id == selectedTeamId })
        } else {
            return league.seasons.first(where: { $0.id == selectedSeason })?
                .teams.first(where: { $0.id == selectedTeamId })
        }
    }

    /// Centralized season picking logic.
    /// - If current year present, pick that.
    /// - Otherwise, pick latest season in DB.
    /// - If none, fallback to "All Time".
    func pickDefaultSeason(league: LeagueData?) -> String {
        guard let league else { return "All Time" }
        let currentYear = String(Calendar.current.component(.year, from: Date()))
        if league.seasons.contains(where: { $0.id == currentYear }) {
            return currentYear
        }
        return league.seasons.sorted { $0.id < $1.id }.last?.id ?? "All Time"
    }

    /// Centralized team picking logic.
    /// - Tries to pick by Sleeper userId, Sleeper username (imported), or first team.
    func pickDefaultTeam(league: LeagueData?, seasonId: String, appUsername: String?, sleeperUsername: String?, sleeperUserId: String?) -> (teamId: String?, teamName: String?) {
        guard let league else { return (nil, nil) }
        let teams: [TeamStanding]
        if seasonId == "All Time" {
            teams = league.seasons.sorted { $0.id < $1.id }.last?.teams ?? []
        } else {
            teams = league.seasons.first(where: { $0.id == seasonId })?.teams ?? []
        }

        // 1. Try userId
        if let sleeperId = sleeperUserId,
           let foundTeam = teams.first(where: { $0.ownerId == sleeperId }) {
            return (foundTeam.id, foundTeam.name)
        }
        // 2. Try imported Sleeper username
        if let sleeperUsername = sleeperUsername,
           let foundTeam = teams.first(where: { $0.name == sleeperUsername }) {
            return (foundTeam.id, foundTeam.name)
        }
        // 3. Try app user's username (if different)
        if let appUsername = appUsername,
           let foundTeam = teams.first(where: { $0.name == appUsername }) {
            return (foundTeam.id, foundTeam.name)
        }
        // 4. Fallback to first team
        let firstTeam = teams.first
        return (firstTeam?.id, firstTeam?.name)
    }

    /// Updates leagues and (re)selects a league/team/season centrally.
    /// - Persists selectedLeagueId for the given username.
    /// - Owner-aware: Uses Sleeper userId and imported Sleeper username to match team.
    /// - Centralized: Always prefers current year season if present, else latest, else "All Time".
    /// - This is the main entry for updating selection after import.
    func updateLeagues(
        _ newLeagues: [LeagueData],
        username: String? = nil,
        sleeperUsername: String? = nil,
        sleeperUserId: String? = nil
    ) {
        leagues = newLeagues

        guard !newLeagues.isEmpty else {
            selectedLeagueId = nil
            selectedTeamId = nil
            selectedSeason = ""
            userHasManuallySelectedTeam = false
            return
        }

        // Attempt restore of persisted selection
        if let user = username,
           let restored = loadPersistedLeagueSelection(for: user),
           newLeagues.contains(where: { $0.id == restored }) {
            selectedLeagueId = restored
        } else {
            selectedLeagueId = newLeagues.first?.id
        }

        guard let league = selectedLeague else { return }

        // Centralized: Pick default season (prefers current year)
        selectedSeason = pickDefaultSeason(league: league)

        // Centralized: Pick default team, but only if user hasn't manually selected a team
        if !userHasManuallySelectedTeam {
            let teamPick = pickDefaultTeam(
                league: league,
                seasonId: selectedSeason,
                appUsername: username,
                sleeperUsername: sleeperUsername ?? lastImportedSleeperUsername,
                sleeperUserId: sleeperUserId ?? lastImportedSleeperUserId
            )
            selectedTeamId = teamPick.teamId
            self.userTeam = teamPick.teamName ?? ""
        }

        // Remember last imported Sleeper username and userId (for matching in future updates)
        if let sleeperUsername = sleeperUsername {
            lastImportedSleeperUsername = sleeperUsername
        }
        if let sleeperUserId = sleeperUserId {
            lastImportedSleeperUserId = sleeperUserId
        }

        if let user = username {
            persistLeagueSelection(for: user, leagueId: selectedLeagueId)
        }
    }

    /// When league or season changes, update season/team selection centrally.
    /// Now uses last imported Sleeper username and userId for team matching.
    func syncSelectionAfterLeagueChange(username: String?, sleeperUserId: String?) {
        guard let league = selectedLeague else {
            selectedSeason = "All Time"
            selectedTeamId = nil
            userHasManuallySelectedTeam = false
            return
        }
        selectedSeason = pickDefaultSeason(league: league)
        // Only pick default team if user hasn't manually selected one
        if !userHasManuallySelectedTeam {
            let teamPick = pickDefaultTeam(
                league: league,
                seasonId: selectedSeason,
                appUsername: username,
                sleeperUsername: lastImportedSleeperUsername,
                sleeperUserId: sleeperUserId ?? lastImportedSleeperUserId
            )
            selectedTeamId = teamPick.teamId
            self.userTeam = teamPick.teamName ?? ""
        }
    }

    /// When season changes, update team selection centrally.
    /// Now uses last imported Sleeper username and userId for team matching.
    func syncSelectionAfterSeasonChange(username: String?, sleeperUserId: String?) {
        guard let league = selectedLeague else { return }
        // Only pick default team if user hasn't manually selected one
        if !userHasManuallySelectedTeam {
            let teamPick = pickDefaultTeam(
                league: league,
                seasonId: selectedSeason,
                appUsername: username,
                sleeperUsername: lastImportedSleeperUsername,
                sleeperUserId: sleeperUserId ?? lastImportedSleeperUserId
            )
            selectedTeamId = teamPick.teamId
            self.userTeam = teamPick.teamName ?? ""
        }
    }

    /// Call this whenever the user manually picks a team
    func setUserSelectedTeam(teamId: String?, teamName: String?) {
        selectedTeamId = teamId
        userTeam = teamName ?? ""
        userHasManuallySelectedTeam = true
    }

    func persistLeagueSelection(for username: String, leagueId: String?) {
        let key = lastSelectedLeagueKey(for: username)
        if let leagueId {
            UserDefaults.standard.set(leagueId, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func loadPersistedLeagueSelection(for username: String) -> String? {
        let key = lastSelectedLeagueKey(for: username)
        return UserDefaults.standard.string(forKey: key)
    }
}
