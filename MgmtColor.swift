//
//  MgmtColor.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 9/21/25.
//  Centralized management-percent color mapping used across the app.
//

import SwiftUI

public extension Color {
    static let mgmtSilverBlue = Color(red: 162/255, green: 209/255, blue: 241/255)
    static let mgmtGold = Color(red: 212/255, green: 175/255, blue: 55/255)
    static let mgmtLime = Color(red: 50/255, green: 205/255, blue: 50/255)
    static let mgmtAmber = Color(red: 255/255, green: 191/255, blue: 0/255)
    static let mgmtFieryRed = Color(red: 255/255, green: 69/255, blue: 0/255)

    static func mgmtPercentColor(_ percent: Double) -> Color {
        let p = percent
        switch p {
        case 95...100:
            return .mgmtGold
        case 90..<95:
            return .mgmtSilverBlue
        case 80..<90:
            return .mgmtLime
        case 75..<80:
            return .mgmtAmber
        case 0..<60:
            return .mgmtFieryRed
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
