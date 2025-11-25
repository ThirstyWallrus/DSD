
//
//  SleeperLeagueManager+Limits.swift
//  DynastyStatDrop
//
//  Lightweight league limit utilities & removal helper expected by SleeperLeaguesView
//  (Restored to resolve missing symbol compile errors: remainingSlots(), removeLeague(...))
//  Non‑intrusive: does not alter core lineup / management % logic.
//
//  Make sure this file is added to the target so the extension is visible.
//

import Foundation

extension SleeperLeagueManager {

    // Adjust to desired cap (example: free tier 3)
    private var _defaultLeagueLimit: Int { 3 }

    /// Maximum leagues allowed for the active user (stub / can be enhanced with entitlements).
    func currentLimit() -> Int {
        _defaultLeagueLimit
    }

    /// Remaining import slots (never negative).
    func remainingSlots() -> Int {
        max(0, currentLimit() - leagues.count)
    }

    /// Flag to quickly gate UI import controls.
    func canImportAnother() -> Bool {
        remainingSlots() > 0
    }

    /// Remove a league by id, persist, and snapshot to in‑memory DB.
    func removeLeague(leagueId: String) {
        guard let idx = leagues.firstIndex(where: { $0.id == leagueId }) else { return }
        leagues.remove(at: idx)
        saveLeagues()
        DatabaseManager.shared.saveLeagueSnapshot(leagues)
    }
}

// MARK: - Database snapshot helper (used by removeLeague)
extension DatabaseManager {
    func saveLeagueSnapshot(_ leagues: [LeagueData]) {
        leagues.forEach { saveLeague($0) }
    }
}
