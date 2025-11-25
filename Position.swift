//
//  Position.swift
//  DSD
//
//  Created by Dynasty Stat Drop on 7/8/25.
//

import SwiftUI
import Foundation

// MARK: - Data Models

enum Position: String, CaseIterable {
    case QB, RB, WR, TE, K, DL, LB, DB
}

struct WeeklyPositionStats: Identifiable {
    let id = UUID()
    let week: Int
    let score: Double
    let playersPlayed: Int
    // PATCH: Strict Duel-Designation Display for lineup slot assignment
    // displaySlot is now constructed to reflect:
    //   - Strict slots: join all eligible positions with "/"
    //   - Flex slots: display as "Flex [POSITION(S)]"
    let displaySlot: String?
}

struct PositionSeasonStats {
    let position: Position
    let weeklyStats: [WeeklyPositionStats]

    var totalPoints: Double {
        weeklyStats.reduce(0) { $0 + $1.score }
    }

    var totalPlayersPlayed: Int {
        weeklyStats.reduce(0) { $0 + $1.playersPlayed }
    }

    var numberOfWeeks: Int {
        weeklyStats.count
    }

    var averagePointsPerWeek: Double {
        numberOfWeeks > 0 ? totalPoints / Double(numberOfWeeks) : 0
    }

    var averagePlayersPerWeek: Double {
        numberOfWeeks > 0 ? Double(totalPlayersPlayed) / Double(numberOfWeeks) : 0
    }

    var averagePointsPerPlayer: Double {
        totalPlayersPlayed > 0 ? totalPoints / Double(totalPlayersPlayed) : 0
    }

    func statsForWeek(_ week: Int) -> (playersPlayed: Int, totalPoints: Double, avgPointsPerPlayer: Double)? {
        guard let stat = weeklyStats.first(where: { $0.week == week }) else { return nil }
        let avgPerPlayer = stat.playersPlayed > 0 ? stat.score / Double(stat.playersPlayed) : 0
        return (stat.playersPlayed, stat.score, avgPerPlayer)
    }
}

struct TeamStatsData: Identifiable {
    var id: String { teamName }
    let teamName: String
    let statsByPosition: [Position: [WeeklyPositionStats]]
}

class StatsViewModel: ObservableObject {
    @Published var teams: [TeamStatsData] = []

    func importData(from leagues: [LeagueData]) {
        // Use DSDStatsService and SleeperLeagueManager data
        self.teams = leagues.flatMap { league in
            league.seasons.flatMap { season in
                season.teams.map { team in
                    // Compute statsByPosition using team's roster and DSDStatsService
                    let statsByPosition = computePositionWeeklyStats(for: team, in: season)
                    return TeamStatsData(teamName: team.name, statsByPosition: statsByPosition)
                }
            }
        }
    }
    
    // STRICT LINEUP SLOT DISPLAY & ORDERING PATCH:
    // - Use SlotPositionAssigner.countedPosition for credited position assignment.
    // - For display, join duel-designation positions with slashes from altPositions.
    // - For flex slots, display as "Flex [POSITION(S)]".

    private func computePositionWeeklyStats(for team: TeamStanding, in season: SeasonData) -> [Position: [WeeklyPositionStats]] {
        let lineupConfig = team.lineupConfig ?? inferredLineupConfig(from: team.roster)
        var statsByPosition: [Position: [WeeklyPositionStats]] = [:]
        
        // --- PATCH: Exclude current week ONLY if more than one week is present ---
        let allWeeks = season.matchupsByWeek?.keys.sorted() ?? []
        var weeksToInclude = allWeeks
        if let currentWeek = allWeeks.max(), allWeeks.count > 1 {
            weeksToInclude = allWeeks.filter { $0 != currentWeek }
        }
        if weeksToInclude.isEmpty {
            weeksToInclude = allWeeks
        }

        for pos in Position.allCases {
            var weekly: [WeeklyPositionStats] = []
            for week in weeksToInclude {
                guard let weekEntries = season.matchupsByWeek?[week],
                      let rosterId = Int(team.id),
                      let myEntry = weekEntries.first(where: { $0.roster_id == rosterId }),
                      let startedIds = myEntry.starters,
                      !startedIds.isEmpty else {
                    // Fallback to legacy logic if no matchup data
                    let players = team.roster.filter { $0.position == pos.rawValue }
                    let scores = players.compactMap { player in player.weeklyScores.first(where: { $0.week == week })?.points }
                    let totalPoints = scores.reduce(0, +)
                    let playersPlayed = scores.count
                    if playersPlayed > 0 {
                        weekly.append(WeeklyPositionStats(week: week, score: totalPoints, playersPlayed: playersPlayed, displaySlot: pos.rawValue))
                    }
                    continue
                }
                
                let startedPlayers = team.roster.filter { startedIds.contains($0.id) }
                let playersPoints = myEntry.players_points ?? [:]
                
                // STRICT PATCH: Build displaySlot using SlotPositionAssigner and duel-designation logic
                let slots = expandSlots(lineupConfig: lineupConfig)
                var assignment: [Player: String] = [:]
                var availableSlots = slots

                let sortedStarters = startedPlayers.sorted {
                    eligibleSlots(for: $0, availableSlots).count < eligibleSlots(for: $1, availableSlots).count
                }
                for p in sortedStarters {
                    let elig = eligibleSlots(for: p, availableSlots)
                    if elig.isEmpty { continue }
                    let specific = elig.filter { ["QB","RB","WR","TE","K","DL","LB","DB"].contains($0.uppercased()) }
                    let chosenSlot = specific.first ?? elig.first!
                    assignment[p] = chosenSlot
                    if let idx = availableSlots.firstIndex(of: chosenSlot) {
                        availableSlots.remove(at: idx)
                    }
                }

                // For STRICT DISPLAY: Get display name for each assignment
                var posMap: [String: (score: Double, played: Int, displaySlots: [String])] = [:]
                for (player, slot) in assignment {
                    let candidatePositions = ([player.position] + (player.altPositions ?? []))
                    let basePosition = player.position
                    let credited = SlotPositionAssigner.countedPosition(for: slot, candidatePositions: candidatePositions, base: basePosition)

                    // PATCH: DISPLAY SLOT NAME LOGIC
                    // - Strict slots: join all eligible canonical positions with "/"
                    // - Flex slots: display as "Flex [POSITION(S)]"
                    let normalizedSlot = PositionNormalizer.normalize(slot)
                    let isFlex = SlotPositionAssigner.offensiveFlexSlots.contains(slot.uppercased()) || SlotPositionAssigner.idpFlexSlots.contains(slot.uppercased()) || slot.uppercased().contains("IDP")
                    let duelPositions = candidatePositions.map { PositionNormalizer.normalize($0) }
                    let displaySlot: String = {
                        if isFlex {
                            // Flex slot: "Flex [POSITION(S)]"
                            let flexLabel = "Flex " + duelPositions.joined(separator: "/")
                            return flexLabel
                        }
                        if duelPositions.count > 1 {
                            // Strict slot, but player eligible for multiple positions: "DL/LB", "LB/DB", etc.
                            return duelPositions.joined(separator: "/")
                        }
                        // Strict slot, single eligible: just the position
                        return normalizedSlot
                    }()

                    // Only accumulate if credited position matches current loop position
                    if credited == pos.rawValue {
                        let pts = playersPoints[player.id] ?? 0
                        var current = posMap[credited, default: (0, 0, [])]
                        current.score += pts
                        current.played += 1
                        current.displaySlots.append(displaySlot)
                        posMap[credited] = current
                    }
                }

                // For display, join displaySlots by ", " if multiple
                if let (score, played, displaySlots) = posMap[pos.rawValue], played > 0 {
                    let uniqueDisplay = Array(Set(displaySlots))
                    weekly.append(
                        WeeklyPositionStats(
                            week: week,
                            score: score,
                            playersPlayed: played,
                            displaySlot: uniqueDisplay.joined(separator: ", ")
                        )
                    )
                }
            }
            statsByPosition[pos] = weekly
        }
        return statsByPosition
    }
    
    // MARK: Shared Utility Functions
    
    private let offensivePositions: Set<String> = ["QB","RB","WR","TE","K"]
    private let defensivePositions: Set<String> = ["DL","LB","DB"]
    private let offensiveFlexSlots: Set<String> = [
        "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE",
        "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX"
    ]
    
    // Allowed positions for a slot
    private func allowedPositions(for slot: String) -> Set<String> {
        switch slot.uppercased() {
        case "QB","RB","WR","TE","K","DL","LB","DB": return [slot.uppercased()]
        case "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE": return ["RB","WR","TE"]
        case "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX": return ["QB","RB","WR","TE"]
        case "IDP": return ["DL","LB","DB"]
        default:
            if slot.uppercased().contains("IDP") { return ["DL","LB","DB"] }
            return [slot.uppercased()]
        }
    }
    
    private func eligibleSlots(for player: Player, _ slots: [String]) -> [String] {
        let candidatePositions = ([player.position] + (player.altPositions ?? [])).map { PositionNormalizer.normalize($0) }
        return slots.filter { slot in
            let allowed = allowedPositions(for: slot)
            return !allowed.intersection(Set(candidatePositions)).isEmpty
        }
    }
    
    private func expandSlots(lineupConfig: [String:Int]) -> [String] {
        lineupConfig.flatMap { Array(repeating: $0.key, count: $0.value) }
    }
    
    private func inferredLineupConfig(from roster: [Player]) -> [String:Int] {
        var counts: [String:Int] = [:]
        for p in roster { counts[p.position, default: 0] += 1 }
        return counts.mapValues { min($0, 3) }
    }
}

// MARK: - Views

struct PositionStatsView: View {
    let position: Position
    let teams: [TeamStatsData]

    var body: some View {
        List {
            ForEach(teams) { team in
                if let weeklyStats = team.statsByPosition[position], !weeklyStats.isEmpty {
                    let seasonStats = PositionSeasonStats(position: position, weeklyStats: weeklyStats)
                    Section(header: Text(team.teamName).font(.headline)) {
                        HStack {
                            Text("Week")
                                .frame(width: 60, alignment: .leading)
                            Spacer()
                            Text("Score")
                                .frame(width: 60, alignment: .center)
                            Spacer()
                            Text("Players")
                                .frame(width: 60, alignment: .center)
                            Spacer()
                            Text("Slot")
                                .frame(width: 120, alignment: .leading)
                        }
                        .font(.subheadline)
                        .foregroundColor(.gray)

                        ForEach(weeklyStats.sorted(by: { $0.week < $1.week })) { stat in
                            HStack {
                                Text("\(stat.week)")
                                    .frame(width: 60, alignment: .leading)
                                Spacer()
                                Text(String(format: "%.1f", stat.score))
                                    .frame(width: 60, alignment: .center)
                                Spacer()
                                Text("\(stat.playersPlayed)")
                                    .frame(width: 60, alignment: .center)
                                Spacer()
                                Text(stat.displaySlot ?? position.rawValue)
                                    .frame(width: 120, alignment: .leading)
                            }
                            .font(.body)
                        }

                        HStack {
                            Text("Total")
                                .font(.subheadline.bold())
                                .frame(width: 60, alignment: .leading)
                            Spacer()
                            Text(String(format: "%.1f", seasonStats.totalPoints))
                                .frame(width: 60, alignment: .center)
                            Spacer()
                            Text("\(seasonStats.totalPlayersPlayed)")
                                .frame(width: 60, alignment: .center)
                            Spacer()
                            Text("")
                                .frame(width: 120)
                        }

                        HStack {
                            Text("Avg/Week")
                                .font(.subheadline.bold())
                                .frame(width: 60, alignment: .leading)
                            Spacer()
                            Text(String(format: "%.1f", seasonStats.averagePointsPerWeek))
                                .frame(width: 60, alignment: .center)
                            Spacer()
                            Text(String(format: "%.1f", seasonStats.averagePlayersPerWeek))
                                .frame(width: 60, alignment: .center)
                            Spacer()
                            Text("")
                                .frame(width: 120)
                        }

                        HStack {
                            Text("Avg/Player")
                                .font(.subheadline.bold())
                                .frame(width: 60, alignment: .leading)
                            Spacer()
                            Text(String(format: "%.1f", seasonStats.averagePointsPerPlayer))
                                .frame(width: 60, alignment: .center)
                            Spacer()
                            Text("")
                                .frame(width: 60)
                            Spacer()
                            Text("")
                                .frame(width: 120)
                        }
                    }
                }
            }
        }
        .navigationTitle("\(position.rawValue) Stats")
    }
}

struct FantasyStatsView: View {
    @StateObject private var viewModel = StatsViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appSelection: AppSelection
    @State private var selectedPosition: Position = .QB

    var body: some View {
        NavigationView {
            VStack {
                Picker("Position", selection: $selectedPosition) {
                    ForEach(Position.allCases, id: \.self) { position in
                        Text(position.rawValue).tag(position)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                PositionStatsView(position: selectedPosition, teams: viewModel.teams)
            }
            .navigationTitle("Fantasy Stats")
        }
        .onAppear {
            // Use leagues from appSelection, which are in sync with SleeperLeagueManager
            if authViewModel.hasImportedLeague {
                viewModel.importData(from: appSelection.leagues)
            }
        }
    }
}
