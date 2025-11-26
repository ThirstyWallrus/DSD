//
//  MgmtColor.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 9/21/25.
//  Centralized management-percent color mapping used across the app.
//

import SwiftUI

extension Color {
    // Named colors used by management-percent mapping.
    static let mgmtSilverBlue = Color(red: 162/255, green: 209/255, blue: 241/255)
    static let mgmtGold = Color(red: 212/255, green: 175/255, blue: 55/255)

    /// Centralized mapping from a management percent (0.0 - 100.0) to a Color used throughout the app.
    ///
    /// Thresholds (default):
    ///  - >= 95% : gold (special highlight for near-perfect usage)
    ///  - 90..<95: silver-blue (secondary highlight)
    ///  - 75..<90: green  (good)
    ///  - 60..<75: yellow (okay)
    ///  - 0..<60 : red    (poor)
    ///
    /// Use this function everywhere you need a color representing a mgmt% value so the UI is consistent.
    static func mgmtPercentColor(_ percent: Double) -> Color {
        let p = percent
        switch p {
        case 95..<100:
            return .mgmtGold
        case 90..<95:
            return .mgmtSilverBlue
        case 75..<90:
            return .green
        case 60..<75:
            return .yellow
        case 0..<60:
            return .red
        default:
            return .gray
        }
    }

    /// Alias to match older helper naming used in some files.
    /// Prefer calling mgmtPercentColor(:) directly for clarity.
    static func mgmtColor(for percent: Double) -> Color {
        return mgmtPercentColor(percent)
    }
}
