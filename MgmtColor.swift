//
//  MgmtColor.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 9/21/25.
//

import SwiftUI

extension Color {
    static let mgmtSilverBlue = Color(red: 162/255, green: 209/255, blue: 241/255) // adjust as needed

    static func mgmtPercentColor(_ percent: Double) -> Color {
        switch percent {
        case 95...100:
            return .mgmtSilverBlue
        case 85..<95:
            return .green
        case 75..<85:
            return .yellow
        default:
            return .red
        }
    }
}
