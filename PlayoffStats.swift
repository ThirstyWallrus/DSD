
//
//  PlayoffStats.swift
//  DynastyStatDrop
//
//  Standalone playoff stats model for mapping to franchise/team views
//

import Foundation

struct PlayoffStats: Codable, Equatable {
    var pointsFor: Double
    var maxPointsFor: Double
    var ppw: Double
    var managementPercent: Double?
    var offensivePointsFor: Double?
    var maxOffensivePointsFor: Double?
    var offensivePPW: Double?
    var offensiveManagementPercent: Double?
    var defensivePointsFor: Double?
    var maxDefensivePointsFor: Double?
    var defensivePPW: Double?
    var defensiveManagementPercent: Double?
    var weeks: Int
    var wins: Int
    var losses: Int
    var recordString: String
    var isChampion: Bool
}
