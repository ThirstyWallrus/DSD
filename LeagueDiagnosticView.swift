
//
//  LeagueDiagnosticView.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 8/20/25.
//

import SwiftUI

struct LeagueDiagnosticView: View {
    @ObservedObject var manager: SleeperLeagueManager
    @State private var selectedSeasonId: String = ""

    var selectedLeague: LeagueData? { manager.leagues.first }
    var seasons: [SeasonData] { selectedLeague?.seasons ?? [] }
    var selectedSeason: SeasonData? { seasons.first(where: { $0.id == selectedSeasonId }) ?? seasons.last }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("League Diagnostics")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.orange)
                    .padding(.top, 12)
                if let league = selectedLeague {
                    HStack {
                        Text("🏈 🏆 🏈🏈🏈")
                            .font(.title)
                    }
                    Text("ID: \(league.id)")
                        .foregroundColor(.gray)
                    Text("Starting Lineup: \(league.startingLineup.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Divider().background(Color.orange)
                    // Season Picker
                    if !seasons.isEmpty {
                        Picker("Season", selection: $selectedSeasonId) {
                            ForEach(seasons, id: \.id) { season in
                                Text(season.id).tag(season.id)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.vertical, 8)
                        .onAppear {
                            if selectedSeasonId.isEmpty, let firstSeason = seasons.first {
                                selectedSeasonId = firstSeason.id
                            }
                        }
                    }
                    if let season = selectedSeason {
                        Text("Teams in Season \(season.id):")
                            .font(.headline)
                            .foregroundColor(.green)
                        if season.teams.isEmpty {
                            Text("No teams found for selected season.")
                                .foregroundColor(.red)
                        } else {
                            ForEach(season.teams, id: \.id) { team in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Team Username: \(team.name)") // now username!
                                    Text("Points For: \(team.pointsFor, specifier: "%.1f")")
                                    Text("Record: \(team.winLossRecord ?? "-")")
                                    Text("Team ID: \(team.id), Owner: \(team.ownerId)")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                .font(.caption)
                                .padding(.leading, 8)
                            }
                        }
                    } else {
                        Text("No teams found for selected season.")
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            debugPrintTeams()
        }
        .onChange(of: selectedSeasonId) { _ in
            debugPrintTeams()
        }
    }

    private func debugPrintTeams() {
        guard let league = selectedLeague else {
            print("No league loaded.")
            return
        }
        print("League: \(league.name), Seasons count: \(league.seasons.count)")
        for season in league.seasons {
            print("Season \(season.id): \(season.teams.count) teams")
            for team in season.teams {
                print(" - \(team.name) (id: \(team.id), owner: \(team.ownerId)), roster count: \(team.roster.count)")
            }
        }
        if let selSeason = seasons.first(where: { $0.id == selectedSeasonId }) {
            print("Selected season: \(selSeason.id), teams: \(selSeason.teams.count)")
        }
    }
}
