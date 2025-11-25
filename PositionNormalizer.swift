//
//  PositionNormalizer.swift
//  DynastyStatDrop
//
//  Provides global normalization for player positions so that all variants map to canonical fantasy positions.
//

import Foundation

public struct PositionNormalizer {
    /// Returns the canonical position string for any variant (DE, DT, NT -> DL; OLB, MLB, ILB -> LB, etc.)
    public static func normalize(_ pos: String) -> String {
        let u = pos.uppercased()
        // Defensive Line
        if ["DL", "DE", "DT", "NT", "EDGE", "LE", "RE"].contains(u) { return "DL" }
        // Linebacker
        if ["LB", "OLB", "MLB", "ILB", "SLB", "WLB"].contains(u) { return "LB" }
        // Defensive Back
        if ["DB", "CB", "S", "FS", "SS", "NB", "DBS"].contains(u) { return "DB" }
        // Canonical offensive positions unchanged
        if ["QB", "RB", "WR", "TE", "K"].contains(u) { return u }
        return u
    }

    /// Convenience overload that accepts an optional String and produces a normalized canonical value.
    /// - If `pos` is nil or empty, returns "UNK".
    /// - Otherwise delegates to normalize(_ pos: String).
    public static func normalize(_ pos: String?) -> String {
        guard let p = pos, !p.isEmpty else { return "UNK" }
        return normalize(p)
    }
}
