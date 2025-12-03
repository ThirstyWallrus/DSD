//
//  FantasyPayoutCalculator.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 12/3/25.
//

import SwiftUI

// MARK: - League Settings Model

@MainActor
final class LeagueSettings: ObservableObject {
    // League basics
    @Published var dues: Double = 100.0
    @Published var isWinnerTakeAll: Bool = false
    @Published var hasPlacesPayout: Bool = true
    @Published var regularSeasonWeeks: Int = 13
    @Published var hasMultiplePayouts: Bool = false

    // Multiple payouts sub-options
    @Published var hasSeasonHighScore: Bool = false
    @Published var hasSeasonBestRecord: Bool = false
    @Published var hasWeeklyHighScore: Bool = false

    // Weekly sub-sub-options
    @Published var weeklyFullTeam: Bool = false
    @Published var weeklyOffensive: Bool = false
    @Published var weeklyDefensive: Bool = false

    // Percentages
    @Published var firstPlacePct: Double = 0.0
    @Published var secondPlacePct: Double = 0.0
    @Published var thirdPlacePct: Double = 0.0
    @Published var seasonHSPct: Double = 0.0
    @Published var seasonBRPct: Double = 0.0
    @Published var weeklyTeamHSPct: Double = 0.0
    @Published var weeklyOffHSPct: Double = 0.0
    @Published var weeklyDefHSPct: Double = 0.0

    // Computed
    var totalPercentage: Double {
        firstPlacePct + secondPlacePct + thirdPlacePct +
        seasonHSPct + seasonBRPct +
        weeklyTeamHSPct + weeklyOffHSPct + weeklyDefHSPct
    }

    // Provide recommended defaults based on selections
    func setRecommendedPercentages() {
        // If everything selected, use a full recommendation
        if dues >= 100 && hasPlacesPayout && hasMultiplePayouts &&
            hasSeasonHighScore && hasSeasonBestRecord && hasWeeklyHighScore &&
            weeklyFullTeam && weeklyOffensive && weeklyDefensive
        {
            firstPlacePct = 40.0
            secondPlacePct = 20.0
            thirdPlacePct = 10.0
            seasonHSPct = 5.0
            seasonBRPct = 4.0
            weeklyTeamHSPct = 7.0
            weeklyOffHSPct = 7.0
            weeklyDefHSPct = 7.0
            return
        }

        // Fallback logic: distribute across active buckets with modest place weighting
        var bucketCount = 0.0
        if hasPlacesPayout { bucketCount += 3 } // 1st/2nd/3rd
        if hasSeasonHighScore { bucketCount += 1 }
        if hasSeasonBestRecord { bucketCount += 1 }
        if hasWeeklyHighScore {
            if weeklyFullTeam { bucketCount += 1 }
            if weeklyOffensive { bucketCount += 1 }
            if weeklyDefensive { bucketCount += 1 }
        }

        if bucketCount == 0 {
            // Default: basic places
            firstPlacePct = 40.0
            secondPlacePct = 30.0
            thirdPlacePct = 30.0
            return
        }

        if hasPlacesPayout {
            // Give places a baseline, distribute remaining evenly to the rest
            firstPlacePct = 40.0
            secondPlacePct = 30.0
            thirdPlacePct = 20.0
            let otherBuckets = max(0.0, bucketCount - 3.0)
            if otherBuckets > 0 {
                let remaining = max(0.0, 100.0 - (firstPlacePct + secondPlacePct + thirdPlacePct))
                let evenOther = remaining / otherBuckets
                if hasSeasonHighScore { seasonHSPct = evenOther }
                if hasSeasonBestRecord { seasonBRPct = evenOther }
                if hasWeeklyHighScore {
                    if weeklyFullTeam { weeklyTeamHSPct = evenOther }
                    if weeklyOffensive { weeklyOffHSPct = evenOther }
                    if weeklyDefensive { weeklyDefHSPct = evenOther }
                }
            }
        } else {
            // Even split between all active buckets
            let even = 100.0 / bucketCount
            if hasSeasonHighScore { seasonHSPct = even }
            if hasSeasonBestRecord { seasonBRPct = even }
            if hasWeeklyHighScore {
                if weeklyFullTeam { weeklyTeamHSPct = even }
                if weeklyOffensive { weeklyOffHSPct = even }
                if weeklyDefensive { weeklyDefHSPct = even }
            }
        }
    }

    // Payout calculation (purely local)
    func calculatePayouts(numberOfTeams: Int) -> (breakdown: [String: Double], notes: [String]) {
        var notes: [String] = []
        let teams = max(1, numberOfTeams)
        let totalPot = dues * Double(teams)

        if numberOfTeams <= 0 {
            notes.append("No teams found in league; using 0 teams assumed.")
        }

        func pctAmount(_ pct: Double) -> Double {
            (pct / 100.0) * totalPot
        }

        var result: [String: Double] = [:]

        if hasPlacesPayout {
            result["1st Place"] = pctAmount(firstPlacePct)
            result["2nd Place"] = pctAmount(secondPlacePct)
            result["3rd Place"] = pctAmount(thirdPlacePct)
        } else if isWinnerTakeAll {
            result["Winner (WTA)"] = totalPot
        }

        if hasMultiplePayouts {
            if hasSeasonHighScore {
                result["Season High Score"] = pctAmount(seasonHSPct)
            }
            if hasSeasonBestRecord {
                result["Season Best Record"] = pctAmount(seasonBRPct)
            }
            if hasWeeklyHighScore {
                let weeks = max(1, regularSeasonWeeks)
                if weeklyFullTeam && weeklyTeamHSPct > 0 {
                    let totalWeeklyTeam = pctAmount(weeklyTeamHSPct)
                    result["Weekly Team HS (Total)"] = totalWeeklyTeam
                    result["Weekly Team HS (Per Week)"] = totalWeeklyTeam / Double(weeks)
                }
                if weeklyOffensive && weeklyOffHSPct > 0 {
                    let totalWeeklyOff = pctAmount(weeklyOffHSPct)
                    result["Weekly Offensive HS (Total)"] = totalWeeklyOff
                    result["Weekly Offensive HS (Per Week)"] = totalWeeklyOff / Double(weeks)
                }
                if weeklyDefensive && weeklyDefHSPct > 0 {
                    let totalWeeklyDef = pctAmount(weeklyDefHSPct)
                    result["Weekly Defensive HS (Total)"] = totalWeeklyDef
                    result["Weekly Defensive HS (Per Week)"] = totalWeeklyDef / Double(weeks)
                }
            }
        }

        // Add a concise diagnostic if totals don't sum to 100%
        let totalPct = totalPercentage
        if abs(totalPct - 100.0) > 0.01 {
            let msg = String(format: "Configured payouts total %.2f%% of pot; this may leave an unallocated amount of $%.2f.",
                             totalPct, totalPot * max(0.0, (100.0 - totalPct) / 100.0))
            notes.append(msg)
        }

        if result.isEmpty {
            result["Unallocated Pot"] = totalPot
            notes.append("No payout buckets selected — the full pot is currently unallocated.")
        }

        return (result, notes)
    }
}

// MARK: - Views

struct InitialSetupView: View {
    @ObservedObject var settings: LeagueSettings
    @Binding var path: [String]

    var body: some View {
        Form {
            Section(header: Text("League Basics")) {
                HStack {
                    Text("League Dues ($)")
                    Spacer()
                    TextField("Dues", value: $settings.dues, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 80)
                }
                Toggle("Winner Take All?", isOn: $settings.isWinnerTakeAll)
                Toggle("1st, 2nd, 3rd Place Payouts?", isOn: $settings.hasPlacesPayout)
                Stepper("Regular Season Weeks: \(settings.regularSeasonWeeks)", value: $settings.regularSeasonWeeks, in: 1...18)
            }

            Section(header: Text("Multiple Payouts")) {
                Toggle("Enable Multiple Payouts?", isOn: $settings.hasMultiplePayouts)
                if settings.hasMultiplePayouts {
                    DisclosureGroup("Payout Options") {
                        Toggle("Season High Score", isOn: $settings.hasSeasonHighScore)
                        Toggle("Season Best Record", isOn: $settings.hasSeasonBestRecord)
                        Toggle("Weekly High Score", isOn: $settings.hasWeeklyHighScore)
                        if settings.hasWeeklyHighScore {
                            DisclosureGroup("Weekly Categories") {
                                Toggle("Full Team", isOn: $settings.weeklyFullTeam)
                                Toggle("Offensive Team", isOn: $settings.weeklyOffensive)
                                Toggle("Defensive Team", isOn: $settings.weeklyDefensive)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Payout Setup")
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button("Accept Settings") {
                    settings.setRecommendedPercentages()
                    path.append("percentages")
                }
                .buttonStyle(.borderedProminent)
                .disabled(settings.dues <= 0 || settings.regularSeasonWeeks <= 0)
            }
        }
    }
}

struct PercentagesView: View {
    @ObservedObject var settings: LeagueSettings
    @Binding var path: [String]
    
    var body: some View {
        Form {
            Section(header: Text("Set Percentages (Total: \(settings.totalPercentage, specifier: "%.2f")%)")) {
                if settings.totalPercentage > 100 {
                    Text("Warning: Total exceeds 100%!").foregroundColor(.red)
                }
                
                if settings.hasPlacesPayout {
                    VStack(alignment: .leading) {
                        Text("1st Place: \(settings.firstPlacePct, specifier: "%.2f")%")
                            Slider(value: $settings.firstPlacePct, in: 0...100, step: 0.5)
                    }
                    VStack(alignment: .leading) {
                        Text("2nd Place: \(settings.secondPlacePct, specifier: "%.2f")%")
                            Slider(value: $settings.secondPlacePct, in: 0...100, step: 0.5)
                    }
                    VStack(alignment: .leading) {
                        Text("3rd Place: \(settings.thirdPlacePct, specifier: "%.2f")%")
                            Slider(value: $settings.thirdPlacePct, in: 0...100, step: 0.5)
                    }
                }
                
                if settings.hasMultiplePayouts {
                    if settings.hasSeasonHighScore {
                        VStack(alignment: .leading) {
                            Text("Season High Score: \(settings.seasonHSPct, specifier: "%.2f")%")
                                Slider(value: $settings.seasonHSPct, in: 0...100, step: 0.5)
                        }
                    }
                    if settings.hasSeasonBestRecord {
                        VStack(alignment: .leading) {
                            Text("Season Best Record: \(settings.seasonBRPct, specifier: "%.2f")%")
                                Slider(value: $settings.seasonBRPct, in: 0...100, step: 0.5)
                        }
                    }
                    if settings.hasWeeklyHighScore {
                        if settings.weeklyFullTeam {
                            VStack(alignment: .leading) {
                                Text("Weekly Team HS (Total for \(settings.regularSeasonWeeks) weeks): \(settings.weeklyTeamHSPct, specifier: "%.2f")%")
                                    Slider(value: $settings.weeklyTeamHSPct, in: 0...100, step: 0.5)
                            }
                        }
                        if settings.weeklyOffensive {
                            VStack(alignment: .leading) {
                                Text("Weekly Offensive HS (Total): \(settings.weeklyOffHSPct, specifier: "%.2f")%")
                                    Slider(value: $settings.weeklyOffHSPct, in: 0...100, step: 0.5)
                            }
                        }
                        if settings.weeklyDefensive {
                            VStack(alignment: .leading) {
                                Text("Weekly Defensive HS (Total): \(settings.weeklyDefHSPct, specifier: "%.2f")%")
                                    Slider(value: $settings.weeklyDefHSPct, in: 0...100, step: 0.5)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Payout Percentages")
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button("Accept Settings") {
                    path.append("calculator")
                }
                .buttonStyle(.borderedProminent)
                .disabled(settings.totalPercentage > 100)
            }
        }
    }
}
    
    
    struct CalculatorView: View {
        @ObservedObject var settings: LeagueSettings
        
        @EnvironmentObject var appSelection: AppSelection
        @EnvironmentObject var leagueManager: SleeperLeagueManager
        
        var body: some View {
            let teamsCount = numberOfTeams()
            let (breakdown, notes) = settings.calculatePayouts(numberOfTeams: teamsCount)
            let totalPot = settings.dues * Double(max(1, teamsCount))
            
            List {
                Section(header: Text("Summary")) {
                    HStack {
                        Text("Teams in League")
                        Spacer()
                        Text("\(teamsCount)")
                    }
                    HStack {
                        Text("League Dues")
                        Spacer()
                        // Removed invalid Xcode placeholder and use a valid Text interpolation
                        Text("$\(settings.dues, specifier: "%.2f")")
                    }
                    HStack {
                        Text("Total Pot")
                        Spacer()
                        Text("$\(totalPot, specifier: "%.2f")")
                    }
                    HStack {
                        Text("Configured Payout %")
                        Spacer()
                        Text("\(settings.totalPercentage, specifier: "%.2f")%")
                    }
                }
                
                Section(header: Text("Breakdown")) {
                    ForEach(breakdown.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key)
                            Spacer()
                            Text("$\(breakdown[key] ?? 0.0, specifier: "%.2f")")
                        }
                    }
                }
                
                if !notes.isEmpty {
                    Section(header: Text("Notes")) {
                        ForEach(notes, id: \.self) { n in
                            Text(n).font(.footnote)
                        }
                    }
                }
                
                Section {
                    Text("Tip: Weekly payouts that are configured as a season total are shown as both a total and a per-week amount (Total / Weeks).")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Payout Calculator")
        }
        
        // Determine number of teams using AppSelection & league data
        private func numberOfTeams() -> Int {
            if let league = appSelection.selectedLeague {
                if appSelection.selectedSeason == "All Time" || appSelection.selectedSeason.isEmpty {
                    return league.seasons.sorted { $0.id < $1.id }.last?.teams.count ?? max(0, league.teams.count)
                } else {
                    return league.seasons.first(where: { $0.id == appSelection.selectedSeason })?.teams.count
                    ?? league.seasons.sorted { $0.id < $1.id }.last?.teams.count
                    ?? league.teams.count
                }
            }
            if let first = appSelection.leagues.first {
                return first.seasons.sorted { $0.id < $1.id }.last?.teams.count ?? first.teams.count
            }
            return 10
        }
    }
    
    // MARK: - Container View
    
    struct FantasyPayoutCalculator: View {
        @StateObject var settings = LeagueSettings()
        @State var path: [String] = []
        
        @EnvironmentObject var appSelection: AppSelection
        @EnvironmentObject var leagueManager: SleeperLeagueManager
        
        var body: some View {
            NavigationStack(path: $path) {
                InitialSetupView(settings: settings, path: $path)
                    .navigationDestination(for: String.self) { destination in
                        if destination == "percentages" {
                            PercentagesView(settings: settings, path: $path)
                        } else if destination == "calculator" {
                            CalculatorView(settings: settings)
                                .environmentObject(appSelection)
                                .environmentObject(leagueManager)
                        }
                    }
            }
        }
    }
    
    struct FantasyPayoutCalculator_Previews: PreviewProvider {
        static var previews: some View {
            FantasyPayoutCalculator()
                .environmentObject(AppSelection())
                .environmentObject(SleeperLeagueManager())
        }
    }
