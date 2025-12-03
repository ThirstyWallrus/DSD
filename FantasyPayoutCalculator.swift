//
//  FantasyPayoutCalculator.swift
//  DynastyStatDrop
//
//  Styled to match RegisterView theme and assets (Background1, DynastyStatDropLogo, Button, TextBar).
//
//  Created by Dynasty Stat Drop on 12/3/25 (styled).
//

import SwiftUI

// MARK: - League Settings Model (unchanged behavior, styled views below)
@MainActor
final class LeagueSettings: ObservableObject {
    // League basics
    @Published var dues: Double = 100.0
    @Published var isWinnerTakeAll: Bool = false
    @Published var hasPlacesPayout: Bool = true
    @Published var regularSeasonWeeks: Int = 13
    // NOTE: Removed hasMultiplePayouts (sub-options are surfaced directly)

    // Multiple payouts sub-options (now surfaced inline)
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
        if dues >= 100 && hasPlacesPayout &&
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

        // NOTE: We no longer require a separate "enable multiple payouts" flag.
        // Each sub-option contributes if it's enabled.
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

// MARK: - Styled Views (theming aligned to RegisterView)

// Small styled numeric/text field that mimics RegisterView's visual (TextBar texture) without changing other files.
struct StyledTextField: View {
    let placeholder: String
    @Binding var value: String
    let keyboardType: UIKeyboardType
    var body: some View {
        ZStack(alignment: .leading) {
            Image("TextBar")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .allowsHitTesting(false)
            HStack {
                if keyboardType == .numberPad || keyboardType == .decimalPad {
                    TextField("", text: $value)
                        .keyboardType(keyboardType)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.orange)
                } else {
                    TextField("", text: $value)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 18)
            if value.isEmpty {
                Text(placeholder)
                    .foregroundColor(.orange.opacity(0.8))
                    .padding(.leading, 18)
            }
        }
        .frame(height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Initial Setup View (styled)
struct InitialSetupView: View {
    @ObservedObject var settings: LeagueSettings
    @Binding var path: [String]
    @State private var duesText: String = ""

    var body: some View {
        ZStack {
            Image("Background1")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    headerSection

                    // Form area with visual grouping
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("League Dues ($)")
                                .font(.headline)
                                .foregroundColor(.orange)
                            StyledTextField(placeholder: "Enter dues (e.g. 100)", value: $duesText, keyboardType: .decimalPad)
                                .onAppear { duesText = String(format: "%.2f", settings.dues) }
                                .onChange(of: duesText) { new in
                                    if let val = Double(new) { settings.dues = val }
                                }
                        }

                        ToggleRow(title: "Winner Take All?", binding: $settings.isWinnerTakeAll)
                        ToggleRow(title: "1st, 2nd, 3rd Place Payouts?", binding: $settings.hasPlacesPayout)

                        // NEW: Surface multiple-payout sub-options inline (removed separate "Enable Multiple Payouts?" control)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Additional Payout Options")
                                .foregroundColor(.orange)
                                .bold()
                                .padding(.bottom, 4)

                            ToggleRow(title: "Season High Score", binding: $settings.hasSeasonHighScore)
                            ToggleRow(title: "Season Best Record", binding: $settings.hasSeasonBestRecord)

                            VStack(alignment: .leading, spacing: 8) {
                                ToggleRow(title: "Weekly High Score", binding: $settings.hasWeeklyHighScore)
                                if settings.hasWeeklyHighScore {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ToggleRow(title: "Weekly — Full Team", binding: $settings.weeklyFullTeam)
                                        ToggleRow(title: "Weekly — Offensive", binding: $settings.weeklyOffensive)
                                        ToggleRow(title: "Weekly — Defensive", binding: $settings.weeklyDefensive)
                                    }
                                    .padding(.leading, 12)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.08)))

                        HStack {
                            Text("Regular Season Weeks:")
                                .foregroundColor(.orange)
                                .bold()
                            Spacer()
                            Text("\(settings.regularSeasonWeeks)")
                                .foregroundColor(.orange)
                        }
                        Stepper("", value: $settings.regularSeasonWeeks, in: 1...18)
                            .labelsHidden()
                    }
                    .padding()
                    .background(Color.black.opacity(0.35))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)

                    // "Next" action button (styled like RegisterView button)
                    Button(action: {
                        settings.setRecommendedPercentages()
                        path.append("percentages")
                    }) {
                        HStack {
                            Text("Accept Settings")
                                .font(.headline)
                                .foregroundColor(.orange)
                                .bold()
                                .padding(.vertical, 10)
                                .padding(.horizontal, 20)
                        }
                        .frame(maxWidth: 260)
                        .background(
                            Image("Button")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.bottom, 40)
                }
                .padding(.top, 20)
            }
        }
        .navigationTitle("")
        .navigationBarHidden(true)
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image("DynastyStatDropLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 140)
                .padding(.top, 28)

            Text("Payout Setup")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.orange)

            Text("Configure your league's payout structure")
                .foregroundColor(.orange.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
    }
}

struct ToggleRow: View {
    let title: String
    @Binding var binding: Bool

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.orange)
            Spacer()
            Toggle("", isOn: $binding)
                .labelsHidden()
        }
    }
}

// MARK: - Percentages View (styled)
struct PercentagesView: View {
    @ObservedObject var settings: LeagueSettings
    @Binding var path: [String]

    var body: some View {
        ZStack {
            Image("Background1")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 12) {
                header
                ScrollView {
                    VStack(spacing: 18) {
                        SectionHeader(title: "Payout Percentages — Total: \(settings.totalPercentage, default: "%.2f")%")

                        if settings.hasPlacesPayout {
                            SliderRow(label: "1st Place", value: $settings.firstPlacePct)
                            SliderRow(label: "2nd Place", value: $settings.secondPlacePct)
                            SliderRow(label: "3rd Place", value: $settings.thirdPlacePct)
                        }

                        // Show sliders whenever the underlying option is enabled
                        if settings.hasSeasonHighScore {
                            SliderRow(label: "Season High Score", value: $settings.seasonHSPct)
                        }
                        if settings.hasSeasonBestRecord {
                            SliderRow(label: "Season Best Record", value: $settings.seasonBRPct)
                        }
                        if settings.hasWeeklyHighScore {
                            if settings.weeklyFullTeam { SliderRow(label: "Weekly Team HS (Total)", value: $settings.weeklyTeamHSPct) }
                            if settings.weeklyOffensive { SliderRow(label: "Weekly Offensive HS (Total)", value: $settings.weeklyOffHSPct) }
                            if settings.weeklyDefensive { SliderRow(label: "Weekly Defensive HS (Total)", value: $settings.weeklyDefHSPct) }
                        }

                        Spacer(minLength: 40)
                    }
                    .padding()
                    .background(Color.black.opacity(0.35))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                }

                HStack(spacing: 16) {
                    Button(action: {
                        path.removeLast()
                    }) {
                        Text("Back")
                            .bold()
                            .foregroundColor(.orange)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.5)))
                    }
                    Button(action: {
                        path.append("calculator")
                    }) {
                        HStack {
                            Text("Accept Settings")
                                .font(.headline)
                                .foregroundColor(.orange)
                                .bold()
                                .padding(.vertical, 10)
                                .padding(.horizontal, 20)
                        }
                        .background(Image("Button").resizable().aspectRatio(contentMode: .fill))
                    }
                }
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("")
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image("DynastyStatDropLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 110)
                .padding(.top, 18)
            Text("Set Percentages")
                .font(.title2)
                .bold()
                .foregroundColor(.orange)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.orange)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(label): \(value, specifier: "%.2f")%")
                    .foregroundColor(.orange)
                Spacer()
            }
            Slider(value: $value, in: 0...100, step: 0.5)
                .accentColor(.orange)
        }
    }
}

// MARK: - Calculator View (styled)
struct CalculatorView: View {
    @ObservedObject var settings: LeagueSettings

    @EnvironmentObject var appSelection: AppSelection
    @EnvironmentObject var leagueManager: SleeperLeagueManager

    var body: some View {
        ZStack {
            Image("Background1")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image("DynastyStatDropLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 110)
                    .padding(.top, 10)

                Text("Payout Calculator")
                    .font(.title)
                    .bold()
                    .foregroundColor(.orange)

                let teamsCount = numberOfTeams()
                let (breakdown, notes) = settings.calculatePayouts(numberOfTeams: teamsCount)
                let totalPot = settings.dues * Double(max(1, teamsCount))

                ScrollView {
                    VStack(spacing: 12) {
                        Group {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Teams in League").foregroundColor(.orange)
                                    Text("\(teamsCount)").foregroundColor(.white)
                                }
                                Spacer()
                                VStack(alignment: .leading) {
                                    Text("League Dues").foregroundColor(.orange)
                                    Text("$\(settings.dues, specifier: "%.2f")").foregroundColor(.white)
                                }
                                Spacer()
                                VStack(alignment: .leading) {
                                    Text("Total Pot").foregroundColor(.orange)
                                    Text("$\(totalPot, specifier: "%.2f")").foregroundColor(.white)
                                }
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.45)))
                        }
                        .padding(.horizontal, 20)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Breakdown").foregroundColor(.orange).bold()
                            ForEach(breakdown.keys.sorted(), id: \.self) { key in
                                HStack {
                                    Text(key).foregroundColor(.white)
                                    Spacer()
                                    Text("$\(breakdown[key] ?? 0.0, specifier: "%.2f")").foregroundColor(.white)
                                }
                                .padding(.vertical, 6)
                                Divider().background(Color.gray)
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35)))
                        .padding(.horizontal, 20)

                        if !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Notes").foregroundColor(.orange).bold()
                                ForEach(notes, id: \.self) { n in
                                    Text(n)
                                        .font(.footnote)
                                        .foregroundColor(.white.opacity(0.9))
                                }
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35)))
                            .padding(.horizontal, 20)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle("")
        .navigationBarHidden(true)
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

// MARK: - Container View (styled entry)
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

// MARK: - Previews
struct FantasyPayoutCalculator_Previews: PreviewProvider {
    static var previews: some View {
        FantasyPayoutCalculator()
            .environmentObject(AppSelection())
            .environmentObject(SleeperLeagueManager())
    }
}
