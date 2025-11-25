//
//  MgmtColor.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 9/21/25.
//

import SwiftUI

extension Color {
    static let mgmtSilverBlue = Color(red: 162/255, green: 209/255, blue: 241/255) // adjust as needed

    static let mgmtGold = Color(red: 212/255, green: 175/255, blue: 55/255)
    static func mgmtPercentColor(_ percent: Double) -> Color {
        switch percent {
        case 95...100:
            return .mgmtGold
        case 90..<95:
            return .mgmtSilverBlue
        case 85..<90:
            return .green
        case 75..<85:
            return .yellow
        case 0..<75:
            return .red
        default:
            return .gray
        }
    }
}
