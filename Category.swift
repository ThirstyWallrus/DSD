import Foundation

/// Category for dashboard/stat mapping.
/// Add any stat you want to support in DSDDashboard, DSDStatsService, TeamStandingsView, etc.
enum Category: String, CaseIterable, Hashable {
    // Standings (additions)
    case teamStanding = "Team Standing"
    case pointsForStanding = "Points For Standing"
    case averagePointsPerWeekStanding = "Average Points Per Week Standing"
    case averagePointsScoredAgainstPerWeekStanding = "Average Points Scored Against Per Week Standing"
    case maxPointsForStanding = "Max Points For Standing"
    case managementPercentStanding = "Management % Standing"
    case offensiveManagementPercentStanding = "Offensive Management % Standing"
    case defensiveManagementPercentStanding = "Defensive Management % Standing"
    case offensiveStanding = "Offensive Standing"
    case defensiveStanding = "Defensive Standing"
    case pointsScoredAgainstStanding = "Points Scored Against Standing"
    case qbPPWStanding = "QB PPW Standing"
    case individualQBPPWStanding = "Individual QB PPW Standing"
    case rbPPWStanding = "RB PPW Standing"
    case individualRBPPWStanding = "Individual RB PPW Standing"
    case wrPPWStanding = "WR PPW Standing"
    case individualWRPPWStanding = "Individual WR PPW Standing"
    case tePPWStanding = "TE PPW Standing"
    case individualTEPPWStanding = "Individual TE PPW Standing"
    case kickerPPWStanding = "Kicker PPW Standing"
    case individualKickerPPWStanding = "Individual Kicker PPW Standing"
    case dlPPWStanding = "DL PPW Standing"
    case individualDLPPWStanding = "Individual DL PPW Standing"
    case lbPPWStanding = "LB PPW Standing"
    case individualLBPPWStanding = "Individual LB PPW Standing"
    case dbPPWStanding = "DB PPW Standing"
    case individualDBPPWStanding = "Individual DB PPW Standing"
    case grades
    
    // Team Stats (additions)
    case highestPointsInGameAllTime = "Highest Points in Game All Time"
    case highestPointsInGameSeason = "Highest Points in Game Season"
    case recordAllTime = "Record All Time"
    case winLossRecord = "Win Loss Record"
    case recordSeason = "Record Season"
    case mostPointsAgainstAllTime = "Most Points Against All Time"
    case mostPointsAgainstSeason = "Most Points Against Season"
    case playoffBerthsAllTime = "Playoff Berths All Time"
    case playoffRecordAllTime = "Playoff Record All Time"
    case championships = "Championships"

    // Offensive Stats (additions)
    case offensivePointsFor = "Offensive Points For"
    case maxOffensivePointsFor = "Max Offensive Points For"
    case averageOffensivePPW = "Average Offensive Points per Week"
    case offensiveManagementPercent = "Offensive Management %"
    case bestOffensivePositionPPW = "Best Offensive Position PPW"
    case worstOffensivePositionPointsAgainstPPW = "Worst Offensive Position Points Against PPW"
    case individualKickerPPW = "Individual Kicker PPW"

    // Defensive Stats (additions)
    case defensivePointsFor = "Defensive Points For"
    case maxDefensivePointsFor = "Max Defensive Points For"
    case averageDefensivePPW = "Average Defensive Points Scored Per Week"
    case defensiveManagementPercent = "Defensive Management %"
    case bestDefensivePositionPPW = "Best Defensive Position PPW"
    case worstDefensivePositionPointsAgainstPPW = "Worst Defensive Position Points Against PPW"

    // Existing from your file
    case maxPointsFor = "Max Points For"
    case managementPercent = "Management %"
    case teamAveragePPW = "Full Team Average Points Per Week"
    case pointsFor = "Points For"
    case pointsScoredAgainst = "Points Scored Against"
    case qbPositionPPW = "QB Position Average Points Per Week"
    case individualQBPPW = "Individual QB Average Points Per Week"
    case rbPositionPPW = "RB Position Average Points Per Week"
    case individualRBPPW = "Individual RB Average Points Per Week"
    case wrPositionPPW = "WR Position Average Points Per Week"
    case individualWRPPW = "Individual WR Average Points Per Week"
    case tePositionPPW = "TE Position Average Points Per Week"
    case individualTEPPW = "Individual TE Average Points Per Week"
    case kickerPPW = "Kicker Average Points Per Week"
    case dlPositionPPW = "DL Position Average Points Per Week"
    case individualDLPPW = "Individual DL Average Points Per Week"
    case lbPositionPPW = "LB Position Average Points Per Week"
    case individualLBPPW = "Individual LB Average Points Per Week"
    case dbPositionPPW = "DB Position Average Points Per Week"
    case individualDBPPW = "Individual DB Average Points Per Week"

    
    
    // Strengths/Weaknesses
    case strengths = "Strengths"
    case weaknesses = "Weaknesses"
    case offensiveStrengths = "Offensive Strengths"
    case offensiveWeaknesses = "Offensive Weaknesses"
    case defensiveStrengths = "Defensive Strengths"
    case defensiveWeaknesses = "Defensive Weaknesses"
    // Miscellaneous
    case bestGameDescription = "Best Game Description"
    case biggestRival = "Biggest Rival"
    // Average Starters Per Week
    case averageQBStartersPerWeek = "Average QB Starters Per Week"
    case averageRBStartersPerWeek = "Average RB Starters Per Week"
    case averageWRStartersPerWeek = "Average WR Starters Per Week"
    case averageTEStartersPerWeek = "Average TE Starters Per Week"
    case averageKStartersPerWeek = "Average K Starters Per Week"
    case averageDLStartersPerWeek = "Average DL Starters Per Week"
    case averageLBStartersPerWeek = "Average LB Starters Per Week"
    case averageDBStartersPerWeek = "Average DB Starters Per Week"
    // Transactions
    case waiverMovesSeason = "Waiver Moves Season"
    case waiverMovesAllTime = "Waiver Moves All Time"
    case faabSpentSeason = "FAAB Spent Season"
    case faabSpentAllTime = "FAAB Spent All Time"
    case faabAveragePerMoveAllTime = "FAAB Average Per Move All Time"
    case tradesCompletedSeason = "Trades Completed Season"
    case tradesCompletedAllTime = "Trades Completed All Time"
    case tradesPerSeasonAverage = "Trades Per Season Average"
    
    var abbreviation: String {
        switch self {
        // Standings
        case .teamStanding: return "Stand"
        case .pointsForStanding: return "PF Stand"
        case .averagePointsPerWeekStanding: return "PPW Stand"
        case .averagePointsScoredAgainstPerWeekStanding: return "PA PW Stand"
        case .maxPointsForStanding: return "MPF Stand"
        case .managementPercentStanding: return "M% Stand"
        case .offensiveManagementPercentStanding: return "Off M% Stand"
        case .defensiveManagementPercentStanding: return "Def M% Stand"
        case .offensiveStanding: return "Off Stand"
        case .defensiveStanding: return "Def Stand"
        case .pointsScoredAgainstStanding: return "PA Stand"
        case .qbPPWStanding: return "QB PPW Stand"
        case .individualQBPPWStanding: return "QB IND PPW Stand"
        case .rbPPWStanding: return "RB PPW Stand"
        case .individualRBPPWStanding: return "RB IND PPW Stand"
        case .wrPPWStanding: return "WR PPW Stand"
        case .individualWRPPWStanding: return "WR IND PPW Stand"
        case .tePPWStanding: return "TE PPW Stand"
        case .individualTEPPWStanding: return "TE IND PPW Stand"
        case .kickerPPWStanding: return "K PPW Stand"
        case .individualKickerPPWStanding: return "K IND PPW Stand"
        case .dlPPWStanding: return "DL PPW Stand"
        case .individualDLPPWStanding: return "DL IND PPW Stand"
        case .lbPPWStanding: return "LB PPW Stand"
        case .individualLBPPWStanding: return "LB IND PPW Stand"
        case .dbPPWStanding: return "DB PPW Stand"
        case .individualDBPPWStanding: return "DB IND PPW Stand"
        case .grades: return "Grades"
            
        // Team Stats
        case .highestPointsInGameAllTime: return "HighPts All"
        case .highestPointsInGameSeason: return "HighPts Szn"
        case .recordAllTime: return "W-L All"
        case .winLossRecord: return "W-L"
        case .recordSeason: return "W-L Szn"
        case .mostPointsAgainstAllTime: return "MostPA All"
        case .mostPointsAgainstSeason: return "MostPA Szn"
        case .playoffBerthsAllTime: return "Playoff Berths"
        case .playoffRecordAllTime: return "Playoff Rec"
        case .championships: return "CH"
        // Offensive Stats
        case .offensivePointsFor: return "OPF"
        case .maxOffensivePointsFor: return "Max OPF"
        case .averageOffensivePPW: return "OPPW"
        case .offensiveManagementPercent: return "Off M%"
        case .bestOffensivePositionPPW: return "Best Off Pos"
        case .worstOffensivePositionPointsAgainstPPW: return "Worst Off Pos"
        case .individualKickerPPW: return "K IND PPW"
        // Defensive Stats
        case .defensivePointsFor: return "DPF"
        case .maxDefensivePointsFor: return "Max DPF"
        case .averageDefensivePPW: return "DPPW"
        case .defensiveManagementPercent: return "Def M%"
        case .bestDefensivePositionPPW: return "Best Def Pos"
        case .worstDefensivePositionPointsAgainstPPW: return "Worst Def Pos"
        // Existing
        case .maxPointsFor: return "MPF"
        case .managementPercent: return "M%"
        case .teamAveragePPW: return "TPPW"
        case .pointsFor: return "PF"
        case .pointsScoredAgainst: return "PSA"
        case .qbPositionPPW: return "QB PW"
        case .individualQBPPW: return "QB IND PW"
        case .rbPositionPPW: return "RB PW"
        case .individualRBPPW: return "RB IND PW"
        case .wrPositionPPW: return "WR PW"
        case .individualWRPPW: return "WR IND PW"
        case .tePositionPPW: return "TE PW"
        case .individualTEPPW: return "TE IND PW"
        case .kickerPPW: return "K PW"
        case .dlPositionPPW: return "DL PW"
        case .individualDLPPW: return "DL IND PW"
        case .lbPositionPPW: return "LB PW"
        case .individualLBPPW: return "LB IND PW"
        case .dbPositionPPW: return "DB PW"
        case .individualDBPPW: return "DB IND PW"
        // Strengths/Weaknesses
        case .strengths: return "STR"
        case .weaknesses: return "WKS"
        case .offensiveStrengths: return "Off STR"
        case .offensiveWeaknesses: return "Off WKS"
        case .defensiveStrengths: return "Def STR"
        case .defensiveWeaknesses: return "Def WKS"
        // Miscellaneous
        case .bestGameDescription: return "Best Game"
        case .biggestRival: return "Rival"
        //starters per week
        case .averageQBStartersPerWeek: return "Avg QB"
        case .averageRBStartersPerWeek: return "Avg RB"
        case .averageWRStartersPerWeek: return "Avg WR"
        case .averageTEStartersPerWeek: return "Avg TE"
        case .averageKStartersPerWeek:  return "Avg K"
        case .averageDLStartersPerWeek: return "Avg DL"
        case .averageLBStartersPerWeek: return "Avg LB"
        case .averageDBStartersPerWeek: return "Avg DB"
        case .waiverMovesSeason: return "Waivers Szn"
        case .waiverMovesAllTime: return "Waivers All"
        case .faabSpentSeason: return "FAAB Szn"
        case .faabSpentAllTime: return "FAAB All"
        case .faabAveragePerMoveAllTime: return "FAAB/Move"
        case .tradesCompletedSeason: return "Trades Szn"
        case .tradesCompletedAllTime: return "Trades All"
        case .tradesPerSeasonAverage: return "Trades/Season"        }
    }

    /// Optional: Full readable name for tooltips or info popups
    var fullName: String { self.rawValue }
}

// MARK: - Team Model

/// Use this struct throughout the app for team data.
/// The stats dictionary uses Category for type safety and easy integration.
struct Team {
    let name: String
    let allTimeWins: Int
    let allTimeLosses: Int
    let championshipsWon: [Int]
    let stats: [Category: [String: Double]] // e.g. [.pointsFor: ["2024": 1234.5]]
    let recordsAgainst: [String: (wins: Int, losses: Int)] // Head-to-head records
}
