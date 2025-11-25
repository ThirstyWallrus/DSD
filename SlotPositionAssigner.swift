//
//  SlotPositionAssigner.swift
//  DynastyStatDrop
//
//  Provides global utility for credited position assignment based on lineup slot and eligible player positions.
//  Use everywhere you compute starter stats, management %, or per-position splits.
//  Supports all custom leagues: standard, superflex, dual-flex, IDP-heavy, and more.
//  Patch all local countedPosition logic to call SlotPositionAssigner.countedPosition(for:candidatePositions:base:)
//

import Foundation

public struct SlotPositionAssigner {
    // Strict slots: always credit as slot name (normalized)
    public static let strictSlots: Set<String> = ["QB", "RB", "WR", "TE", "K", "DL", "LB", "DB"]

    // Offensive flex slots
    public static let offensiveFlexSlots: Set<String> = [
        "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE","WRRBTEFLEX",
        "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX"
    ]

    // IDP flex slots
    public static let idpFlexSlots: Set<String> = [
        "IDPFLEX","IDP_FLEX","DFLEX","DL_LB_DB","DL_LB","LB_DB","DL_DB","DP","D","DEF"
    ]

    /// Helper: Is this slot an offensive flex?
    public static func isOffensiveFlex(slot: String) -> Bool {
        offensiveFlexSlots.contains(slot.uppercased())
    }

    /// Helper: Is this slot a defensive flex?
    public static func isDefensiveFlex(slot: String) -> Bool {
        let s = slot.uppercased()
        return idpFlexSlots.contains(s) || (s.contains("IDP") && !strictSlots.contains(s))
    }

    /// Helper: Is this slot a strict slot? (QB, RB, WR, TE, K, DL, LB, DB)
    public static func isStrictSlot(slot: String) -> Bool {
        strictSlots.contains(slot.uppercased())
    }

    /// Returns the credited (canonical) position for a player in a given slot.
    /// - If slot is strict, returns slot name (normalized).
    /// - If slot is flex or IDP flex, returns first eligible position from candidatePositions.
    /// - Fallback: returns first candidate or base.
    public static func countedPosition(for slot: String, candidatePositions: [String], base: String) -> String {
        let s = slot.uppercased()
        let normalizedCandidates = candidatePositions.map { PositionNormalizer.normalize($0) }
        let normalizedBase = PositionNormalizer.normalize(base)
        if strictSlots.contains(s) {
            return PositionNormalizer.normalize(s)
        }
        if offensiveFlexSlots.contains(s) {
            // Credit as first eligible position (RB/WR/TE for FLEX and variants)
            // PATCH: For display, always allow duel-designation for flex slots if multiple eligible
            for pos in ["QB", "RB", "WR", "TE"] {
                if normalizedCandidates.contains(PositionNormalizer.normalize(pos)) {
                    return PositionNormalizer.normalize(pos)
                }
            }
            return normalizedCandidates.first ?? normalizedBase
        }
        if idpFlexSlots.contains(s) || s.contains("IDP") {
            // Credit as first eligible position among DL/LB/DB
            for pos in ["DL", "LB", "DB"] {
                if normalizedCandidates.contains(PositionNormalizer.normalize(pos)) {
                    return PositionNormalizer.normalize(pos)
                }
            }
            return normalizedCandidates.first ?? normalizedBase
        }
        if ["SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX"].contains(s) {
            for pos in ["QB", "RB", "WR", "TE"] {
                if normalizedCandidates.contains(PositionNormalizer.normalize(pos)) {
                    return PositionNormalizer.normalize(pos)
                }
            }
            return normalizedCandidates.first ?? normalizedBase
        }
        // Fallback: use first candidate or base position
        return normalizedCandidates.first ?? normalizedBase
    }
}
