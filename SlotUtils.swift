//
//  SlotUtils.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 11/24/25.
//


// Filename: SlotUtils.swift
// Simple helper to consistently sanitize a starting slots list for use in lineup/max calculations.
// Call this whenever you derive an expanded starting slots array from league.startingLineup or team.lineupConfig.

import Foundation

struct SlotUtils {
    // canonical list of tokens that should be excluded from the "starting lineup" when computing starters,
    // max lineup, or ordering for starters. Keep this list in sync with buildTeams.nonStartingTokens.
    static let nonStartingTokens: Set<String> = [
        "BN", "BENCH", "TAXI", "TAXI_SLOT", "TAXI-SLOT", "TAXI SLOT",
        "IR", "RESERVE", "RESERVED", "PUP", "OUT"
    ]

    static func sanitizeStartingSlots(_ slots: [String]) -> [String] {
        return slots.filter { !nonStartingTokens.contains($0.uppercased()) }
    }

    static func sanitizeStartingLineupConfig(_ config: [String: Int]) -> [String: Int] {
        var out: [String: Int] = [:]
        for (slot, count) in config {
            if !nonStartingTokens.contains(slot.uppercased()) {
                out[slot] = (out[slot] ?? 0) + count
            }
        }
        return out
    }
}
