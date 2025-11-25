//
//  Tab 2.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 7/14/25.
//


import Foundation

enum Tab: CaseIterable {
    case dashboard, deck, myTeam, myLeague, matchup

    var label: String {
        switch self {
        case .dashboard: return "DSDDash"
        case .deck: return "TheDeck"
        case .myTeam: return "MyTeam"
        case .myLeague: return "MyLeague"
        case .matchup: return "Matchup"
        }
    }

    var customImage: String {
        switch self {
        case .dashboard: return "dashboard_icon"
        case .deck: return "deck_icon"
        case .myTeam: return "myteam_icon"
        case .myLeague: return "myleague_icon"
        case .matchup: return "matchup_icon"
        }
    }
}
