//
//  TheDeck.swift

import SwiftUI
import Foundation

// MARK: - StatGradeBreakdown Definition (PATCH)
struct StatGradeBreakdown {
    let grade: String
    let composite: Double
    let percentiles: [String: Double]
    let summary: String
}

struct TheDeck: View {
    @EnvironmentObject var appSelection: AppSelection
    @Binding var selectedTab: Tab
    @State private var order: [Int] = []
    @State private var flip: [Bool] = []

    private let CARD_ASPECT: CGFloat = 480.0 / 320.0
    private let CARD_WIDTH_MAX: CGFloat = 360
    private let CARD_WIDTH_MIN: CGFloat = 300
    private let STACK_OFFSET_X: CGFloat = 6
    private let STACK_OFFSET_Y: CGFloat = 8
    private let STACK_VISIBLE_DEPTH: Int = 8
    private let STACK_TILT_Y_DEG: Double = 3.0
    private let STACK_TILT_X_DEG: Double = 2.5

    // Centralized selection: always use appSelection
    private var league: LeagueData? { appSelection.selectedLeague }
    private var leagues: [LeagueData] { appSelection.leagues }

    private var models: [DeckFranchiseModel] {
        guard let lg = league,
              let cache = lg.allTimeOwnerStats else { return [] }
        let latestTeams: [TeamStanding]
        if appSelection.selectedSeason == "All Time" || appSelection.selectedSeason.isEmpty {
            latestTeams = lg.seasons.sorted { $0.id < $1.id }.last?.teams ?? lg.teams
        } else {
            latestTeams = lg.seasons.first(where: { $0.id == appSelection.selectedSeason })?.teams ?? lg.teams
        }
        return latestTeams.compactMap { team in
            guard let agg = cache[team.ownerId] else { return nil }
            return DeckFranchiseModel(
                ownerId: team.ownerId,
                displayName: agg.latestDisplayName,
                wins: agg.totalWins,
                losses: agg.totalLosses,
                ties: agg.totalTies,
                championships: agg.championships,
                stats: agg,
                weeklyActualLineupTotals: actualWeeklyTotals(ownerId: team.ownerId, league: lg, seasonId: appSelection.selectedSeason),
                playoffStats: agg.playoffStats
            )
        }
    }

    private var leagueMetricAverages: DeckLeagueAverages {
        DeckLeagueAverages(models: models)
    }

    var body: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width - 40
            let cardWidth = min(CARD_WIDTH_MAX, max(CARD_WIDTH_MIN, availableWidth))
            let cardHeight = cardWidth * CARD_ASPECT
            let visibleDepth = CGFloat(min(order.count, STACK_VISIBLE_DEPTH))
            let stackHeight = cardHeight + (visibleDepth - 1) * STACK_OFFSET_Y

            ZStack {
                Image("Background1")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.55))

                VStack(spacing: 14) {
                    Text("The Deck")
                        .font(.custom("Phatt", size: 40))
                        .foregroundColor(.orange)
                        .shadow(color: .orange.opacity(0.55), radius: 14, y: 4)
                        .padding(.top, 16)
                    LeagueSeasonTeamPicker(showLeague: true, showSeason: true, showTeam: false)
                        .environmentObject(appSelection)
                }
                .frame(maxWidth: .infinity)

                if !models.isEmpty {
                    cardStack(width: cardWidth, height: cardHeight)
                        .frame(width: cardWidth, height: stackHeight)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                } else {
                    Text("No current franchises")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.custom("Phatt", size: 18))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
        }
        .onAppear {
            reloadStacks()
        }
        .onChange(of: appSelection.selectedLeagueId) {
            reloadStacks()
        }
        .onChange(of: appSelection.leagues) {
            reloadStacks()
        }
        .onChange(of: appSelection.selectedSeason) {
            reloadStacks()
        }
    }

    private func cardStack(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ForEach(order, id: \.self) { idx in
                if let pos = order.firstIndex(of: idx), pos < STACK_VISIBLE_DEPTH, idx < models.count {
                    let model = models[idx]
                    let xOffset = CGFloat(pos) * STACK_OFFSET_X
                    let yOffset = CGFloat(pos) * STACK_OFFSET_Y
                    let yaw = -STACK_TILT_Y_DEG * Double(pos)
                    let pitch = STACK_TILT_X_DEG * Double(pos)
                    
                    DeckCard(
                        model: model,
                        allModels: models,
                        leagueAverages: leagueMetricAverages,
                        cardSize: CGSize(width: width, height: height),
                        onCycleUp: { cycleUp() },
                        onCycleDown: { cycleDown() },
                        leagueName: league?.name ?? ""
                    )
                    .offset(x: xOffset - CGFloat(pos) * (STACK_OFFSET_X/2),
                            y: yOffset)
                    .rotation3DEffect(.degrees(yaw), axis: (0,1,0), perspective: 0.9/1200)
                    .rotation3DEffect(.degrees(pitch), axis: (1,0,0), perspective: 0.9/1200)
                    .zIndex(Double(models.count - pos))
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onEnded { val in
                    let vertical = val.translation.height
                    if vertical < -65 {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { cycleDown() }
                    } else if vertical > 65 {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { cycleUp() }
                    }
                }
        )
    }

    private func reloadStacks() {
        order = Array(0..<models.count)
        flip = Array(repeating: false, count: models.count)
    }

    private func cycleDown() {
        guard let first = order.first else { return }
        order.removeFirst()
        order.append(first)
    }

    private func cycleUp() {
        guard let last = order.last else { return }
        order.removeLast()
        order.insert(last, at: 0)
    }

    private func actualWeeklyTotals(ownerId: String, league: LeagueData, seasonId: String) -> [Double] {
        var timeline: [(String, Int, Double)] = []
        let targetSeasons: [SeasonData]
        if seasonId == "All Time" || seasonId.isEmpty {
            targetSeasons = league.seasons.sorted(by: { $0.id < $1.id })
        } else {
            targetSeasons = league.seasons.filter { $0.id == seasonId }
        }
        for season in targetSeasons {
            guard let team = season.teams.first(where: { $0.ownerId == ownerId }) else { continue }
            let playoffStart = season.playoffStartWeek ?? defaultPlayoffStart(for: season)
            let regularWeeks = Set(1..<playoffStart)
            if let dict = team.weeklyActualLineupPoints, !dict.isEmpty {
                for (week, pts) in dict where regularWeeks.contains(week) {
                    timeline.append((season.id, week, pts))
                }
            }
        }
        return timeline
            .sorted { a, b in a.0 == b.0 ? a.1 < b.1 : a.0 < b.0 }
            .map { $0.2 }
    }

    private func defaultPlayoffStart(for season: SeasonData) -> Int {
        let allWeeks = season.teams.flatMap { $0.weeklyActualLineupPoints?.keys.map { $0 } ?? [] }.max() ?? 13
        let playoffTeams = season.playoffTeamsCount ?? 4
        let rounds = Int(ceil(log2(Double(playoffTeams))))
        return allWeeks - rounds + 1
    }
}

// MARK: - Model & League Averages

struct DeckFranchiseModel {
    let ownerId: String
    let displayName: String
    let wins: Int
    let losses: Int
    let ties: Int
    let championships: Int
    let stats: AggregatedOwnerStats
    let weeklyActualLineupTotals: [Double]
    let playoffStats: PlayoffStats
}

struct DeckLeagueAverages {
    let avgPF: Double
    let avgPPW: Double
    let avgOPF: Double
    let avgOPPW: Double
    let avgDPF: Double
    let avgDPPW: Double
    let avgMgmt: Double

    init(models: [DeckFranchiseModel]) {
        func avg(_ selector: (DeckFranchiseModel) -> Double) -> Double {
            guard !models.isEmpty else { return 0 }
            return models.map(selector).reduce(0, +) / Double(models.count)
        }
        avgPF = avg { $0.stats.totalPointsFor }
        avgPPW = avg { $0.stats.teamPPW }
        avgOPF = avg { $0.stats.totalOffensivePointsFor }
        avgOPPW = avg { $0.stats.offensivePPW }
        avgDPF = avg { $0.stats.totalDefensivePointsFor }
        avgDPPW = avg { $0.stats.defensivePPW }
        avgMgmt = avg { $0.stats.managementPercent }
    }

    func average(for label: String) -> Double {
        switch label {
        case "PF": return avgPF
        case "PPW": return avgPPW
        case "OPF": return avgOPF
        case "OPPW": return avgOPPW
        case "DPF": return avgDPF
        case "DPPW": return avgDPPW
        case "Mgmt%": return avgMgmt
        default: return 0
        }
    }
}

// MARK: - DeckCard

struct DeckCard: View {
    enum CardFace: CaseIterable { case front, back, bonus }
    let model: DeckFranchiseModel
    let allModels: [DeckFranchiseModel]
    let leagueAverages: DeckLeagueAverages
    let cardSize: CGSize
    let onCycleUp: () -> Void
    let onCycleDown: () -> Void
    let leagueName: String

    @State private var showPicker = false
    @State private var showGradeInfo = false
    @State private var cardFace: CardFace = .front

    @State private var isLoaded: Bool = false
    @State private var imageScale: CGFloat = 1.0
    @State private var statsOpacity: Double = 1.0
    @State private var currentImage: Image = Image("DefaultAvatar")

    private let catPairs: [(String, (AggregatedOwnerStats) -> Double)] = [
        ("PF", { $0.totalPointsFor }),
        ("PPW", { $0.teamPPW }),
        ("OPF", { $0.totalOffensivePointsFor }),
        ("OPPW", { $0.offensivePPW }),
        ("DPF", { $0.totalDefensivePointsFor }),
        ("DPPW", { $0.defensivePPW }),
        ("Mgmt%", { $0.managementPercent }),
        ("OMgmt%", { $0.offensiveManagementPercent }),
        ("DMgmt%", { $0.defensiveManagementPercent })
    ]

    private let offensePositions = ["QB", "RB", "WR", "TE", "K"]
    private let idpPositions = ["DL", "LB", "DB"]

    private var leagueAvgPos: [String: Double] { average(map: \.stats.positionAvgPPW, keys: offensePositions + idpPositions) }
    private var leagueAvgInd: [String: Double] { average(map: \.stats.individualPositionPPW, keys: offensePositions + idpPositions) }

    private func average(map: KeyPath<DeckFranchiseModel, [String: Double]>, keys: [String]) -> [String: Double] {
        var out: [String: Double] = [:]
        for k in keys {
            let vals = allModels.compactMap { $0[keyPath: map][k] }
            if !vals.isEmpty {
                out[k] = vals.reduce(0, +) / Double(vals.count)
            }
        }
        return out
    }

    private let threshold: Double = 0.05

    var body: some View {
        let gradeCol = gradeColor(for: statGradeForModel(model: model, allModels: allModels).grade)
        ZStack {
            switch cardFace {
            case .front: frontContent
            case .back: backContent
            case .bonus: bonusContent
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(gradeCol.opacity(0.85), lineWidth: 1.2)
        )
        .shadow(color: .blue.opacity(0.55), radius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 26))
        .gesture(
            DragGesture()
                .onEnded { val in
                    let dx = val.translation.width
                    let dy = val.translation.height
                    if abs(dy) > abs(dx) {
                        if dy < -30 {
                            withAnimation { cardFace = .back }
                        } else if dy > 30 {
                            withAnimation { cardFace = .bonus }
                        }
                    } else {
                        if dx > 30 {
                            withAnimation { onCycleUp() }
                        } else if dx < -30 {
                            withAnimation { onCycleDown() }
                        }
                    }
                }
        )
        .sheet(isPresented: $showPicker) {
            ImagePickerView { image in
                if let img = image { OwnerAssetStore.shared.setImage(for: model.ownerId, image: img) }
                showPicker = false
            }
        }
        .sheet(isPresented: $showGradeInfo) {
            GradeInfoSheet(gradeBreakdown: statGradeForModel(model: model, allModels: allModels))
                .presentationDetents([.medium])
        }
        .onAppear {
            updateCurrentImage()
        }
        .onChange(of: OwnerAssetStore.shared.images[model.ownerId]) {
            updateCurrentImage()
        }
    }

    // PATCH: Ensure all computed views return a concrete view, not just a modifier.
    private var frontContent: some View {
        let cardName = model.displayName
        let cardTeam = model.stats.latestDisplayName
        let cardType = model.championships > 0 ? "Champion" : "Franchise"
        let cardImage: Image = currentImage

        let stats: [(String, String)] = [
            ("Wins", "\(model.wins)"),
            ("Losses", "\(model.losses)"),
            ("PF", String(format: "%.0f", model.stats.totalPointsFor)),
            ("PPW", String(format: "%.2f", model.stats.teamPPW)),
            ("Mgmt%", String(format: "%.1f%%", model.stats.managementPercent)),
            ("Championships", "\(model.championships)")
        ]

        return VStack(spacing: 0) {
            // Card image (art/photo region)
            ZStack {
                cardImage
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(imageScale)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: imageScale)
                    .frame(height: cardSize.height * 0.45)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color.cyan.opacity(0.18), radius: 10, x: 0, y: 5)
            }
            .frame(height: cardSize.height * 0.45)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color("DeckCardTopBG", bundle: nil).opacity(0.23),
                        Color("DeckCardBottomBG", bundle: nil).opacity(0.21)
                    ]),
                    startPoint: .top, endPoint: .bottom)
            )
            .onTapGesture {
                showPicker = true
            }
            
            // League name (above user name, under image, with small font)
            if !leagueName.isEmpty {
                // CHANGE: Remove Group, attach .padding directly to Text
                Text(leagueName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 2)
                    .padding(.horizontal, 8)
            }
            // Name + Type/Grade
            HStack {
                Text(cardName)
                    .font(.custom("Phatt", size: 22))
                    .fontWeight(.bold)
                    .foregroundColor(Color.orange)
                    .shadow(color: .orange.opacity(0.14), radius: 1, y: 1)
                Spacer()
                Text(cardType)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.82))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            
            // Team info
            Text("Team: \(cardTeam)")
                .font(.subheadline)
                .foregroundColor(Color("DeckCardTeam", bundle: nil).opacity(0.95))
                .padding(.horizontal, 8)
            
            // Grade badge
            HStack(spacing: 7) {
                Text("Grade:")
                    .font(.callout.bold())
                    .foregroundColor(Color(.blue))
                ElectrifiedGrade(grade: statGradeForModel(model: model, allModels: allModels).grade, fontSize: 26)
                    .frame(width: 36, height: 36)
                Spacer()
            }
            .padding(.horizontal, 8)
            
            Divider()
                .padding(.horizontal, 8)
            
            // Stats grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(stats, id: \.0) { label, value in
                    HStack {
                        Text(label + ":")
                            .font(.headline)
                            .foregroundColor(Color(.blue))
                        Spacer()
                        Text(value)
                            .font(.custom("Phatt", size: 18).weight(.bold))
                            .foregroundColor(Color(.orange))
                    }
                }
            }
            .opacity(statsOpacity)
            .animation(.easeInOut(duration: 0.5).delay(0.3), value: statsOpacity)
            .padding(.horizontal, 8)
            
            // Accolades
            if model.championships > 0 || !myAccolades.isEmpty {
                HStack(spacing: 8) {
                    ForEach(myAccolades, id: \.self) { stat in
                        Image("Trophy")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22)
                    }
                    if model.championships > 0 {
                        Text("\(model.championships)× Champ")
                            .font(.caption2.bold())
                            .foregroundColor(.yellow)
                    }
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
                .background(
                    RoundedRectangle(cornerRadius: 13)
                        .fill(
                            LinearGradient(colors: [
                                Color("DeckCardStatsBG", bundle: nil).opacity(0.93),
                                Color("DeckCardStatsBG2", bundle: nil).opacity(0.89)
                            ], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: Color.cyan.opacity(0.16), radius: 5, x: 0, y: 2)
                )
            }
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color("DeckCardBackTop", bundle: nil).opacity(0.22),
                    Color("DeckCardBackBottom", bundle: nil).opacity(0.18)
                ]),
                startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .shadow(color: Color.black.opacity(0.17), radius: 14, x: 0, y: 5)
        .padding(.vertical, 8)
        .frame(width: cardSize.width, height: cardSize.height)
        .scaleEffect(isLoaded ? 1.0 : 0.95)
        .opacity(isLoaded ? 1.0 : 0.0)
        .animation(.easeOut(duration: 0.55), value: isLoaded)
        .onAppear {
            withAnimation {
                isLoaded = true
                statsOpacity = 1.0
                imageScale = 1.0
                updateCurrentImage()
            }
        }
    }

    private func updateCurrentImage() {
        let img = OwnerAssetStore.shared.image(for: model.ownerId)
        currentImage = img ?? Image("DefaultAvatar")
    }

    private var backContent: some View {
        VStack(spacing: 10) {
            header
            sectionHeader("Offensive Positions")
            positionTable(for: offensePositions)
            sectionHeader("Defensive Positions")
            positionTable(for: idpPositions)
            legend
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var bonusContent: some View {
        VStack(spacing: 10) {
            header
            sectionHeader("Playoff Stats")
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    metricBox(label: "Playoff PF", value: model.playoffStats.pointsFor)
                    metricBox(label: "Playoff PPW", value: model.playoffStats.ppw)
                }
                HStack(spacing: 10) {
                    metricBox(label: "Playoff Mgmt%", value: model.playoffStats.managementPercent ?? 0)
                    metricBox(label: "Record", value: Double(model.playoffStats.wins), isRecord: true)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(colors: [.black.opacity(0.70), .black.opacity(0.45)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(LinearGradient(colors: [.blue.opacity(0.8), .cyan.opacity(0.35), .blue.opacity(0.8)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 0.8)
                    )
            )
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var header: some View {
        VStack(spacing: 6) {
            profileImage
            if !leagueName.isEmpty {
                // CHANGE: Remove Group, attach .padding directly to Text
                Text(leagueName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 2)
            }
            Text(model.displayName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(recordString)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.65))
            if model.championships > 0 {
                Text("\(model.championships) Championship\(model.championships == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
            Button(action: { showGradeInfo = true }) {
                Text("Grade Info")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.blue.opacity(0.3)))
                    .overlay(Capsule().stroke(Color.blue.opacity(0.5), lineWidth: 0.7))
            }
        }
    }

    private var accoladeStats: [String] {
        ["PF", "PPW", "OPF", "OPPW", "DPF", "DPPW", "Mgmt%", "OMgmt%", "DMgmt%"]
    }

    private var accoladeHolders: [String: String] {
        var result: [String: String] = [:]
        for stat in accoladeStats {
            let max = allModels.max { $0.stats.statValue(for: stat) < $1.stats.statValue(for: stat) }
            if let leader = max { result[stat] = leader.ownerId }
        }
        return result
    }

    private var myAccolades: [String] {
        accoladeStats.filter { accoladeHolders[$0] == model.ownerId }
    }

    private var leftAccolades: [String] { Array(myAccolades.prefix(myAccolades.count/2)) }
    private var rightAccolades: [String] { Array(myAccolades.suffix(myAccolades.count/2)) }

    private var profileImage: some View {
        let img = OwnerAssetStore.shared.image(for: model.ownerId) ?? Image("DefaultAvatar")
        return ZStack {
            img
                .resizable()
                .scaledToFill()
                .frame(width: 110, height: 110)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(gradeColor(for: statGradeForModel(model: model, allModels: allModels).grade).opacity(0.65), lineWidth: 2)
                )
                .onTapGesture { showPicker = true }

            if model.championships > 0 {
                HStack {
                    VStack {
                        ForEach(leftAccolades, id: \.self) { stat in
                            Image("Trophy")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20)
                        }
                        Spacer()
                    }
                    Spacer()
                    VStack {
                        ForEach(rightAccolades, id: \.self) { stat in
                            Image("Trophy")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20)
                        }
                        Spacer()
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 5)
            }

            ElectrifiedGrade(grade: statGradeForModel(model: model, allModels: allModels).grade, fontSize: 28)
                .frame(width: 44, height: 44)
        }
    }

    private var recordString: String {
        "\(model.wins)-\(model.losses)\(model.ties > 0 ? "-\(model.ties)" : "")"
    }

    private var metricsGrid: some View {
        let rows = catPairs.chunked(into: 2)
        return VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.0) { pair in
                        metricBox(label: pair.0, value: pair.1(model.stats))
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(colors: [.black.opacity(0.70), .black.opacity(0.45)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(LinearGradient(colors: [.blue.opacity(0.8), .cyan.opacity(0.35), .blue.opacity(0.8)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 0.8)
                )
        )
    }

    private func metricBox(label: String, value: Double, isRecord: Bool = false) -> some View {
        let avg = leagueAverages.average(for: label)
        let glow = isRecord ? .yellow : glowColor(value: value, avg: avg, label: label)
        return VStack(spacing: 4) {
            Text(label)
                .font(.caption2.bold())
                .foregroundColor(.white.opacity(0.85))
            Text(isRecord ? recordString : label.contains("Mgmt") ? String(format: "%.1f%%", value) : formatMetric(label, value))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .glowShadow(color: glow)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.36)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(glow.opacity(0.55), lineWidth: 0.6)
                )
        )
    }

    private func formatMetric(_ label: String, _ v: Double) -> String {
        if ["PF", "OPF", "DPF", "Max PF"].contains(label) { return String(format: "%.0f", v) }
        return String(format: "%.2f", v)
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.18))
                        .overlay(Capsule().stroke(Color.blue.opacity(0.5), lineWidth: 0.7))
                )
            Spacer()
        }
    }

    private func positionTable(for positions: [String]) -> some View {
        VStack(spacing: 6) {
            ForEach(positions, id: \.self) { pos in
                let teamPos = model.stats.positionAvgPPW[pos] ?? 0
                let teamInd = model.stats.individualPositionPPW[pos] ?? 0
                let lgPos = leagueAvgPos[pos] ?? 0
                let lgInd = leagueAvgInd[pos] ?? 0
                PositionLine(position: pos,
                             ppw: teamPos,
                             ppwAvg: lgPos,
                             ind: teamInd,
                             indAvg: lgInd,
                             pctBand: threshold,
                             glowFunc: glowColor)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.06), lineWidth: 0.6))
    }

    private var legend: some View {
        HStack {
            Text("●").foregroundColor(.green) + Text(" Above").foregroundColor(.white.opacity(0.7))
            Text("●").foregroundColor(.yellow) + Text(" Near").foregroundColor(.white.opacity(0.7))
            Text("●").foregroundColor(.red) + Text(" Below").foregroundColor(.white.opacity(0.7))
            Spacer()
        }
        .font(.caption2)
    }

    private func gradeColor(for grade: String) -> Color {
        switch grade {
        case "A+": return .yellow
        case "A": return Color.orange
        case "A-": return Color.orange.opacity(0.8)
        case "B+": return Color.green
        case "B": return Color.green.opacity(0.7)
        case "B-": return Color.gray
        case "C+": return Color.purple
        case "C": return Color.pink
        default: return Color.gray.opacity(0.6)
        }
    }

    private var cardBackground: some View {
        ZStack {
            Image("CardBackground")
                .resizable()
                .scaledToFill()
                .clipped()
            LinearGradient(colors: [
                Color.black.opacity(0.90),
                Color.black.opacity(0.70),
                Color.black.opacity(0.90)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.blue.opacity(0.25), .clear],
                           center: .topLeading,
                           startRadius: 8,
                           endRadius: 350)
                .blendMode(.overlay)
        }
    }

    private func glowColor(value: Double, avg: Double, label: String) -> Color {
        if avg == 0 {
            if value > 0 { return .green }
            return .yellow
        }
        if value >= avg * (1 + threshold) { return .green }
        if value <= avg * (1 - threshold) { return .red }
        return .yellow
    }

    private struct PositionLine: View {
        let position: String
        let ppw: Double
        let ppwAvg: Double
        let ind: Double
        let indAvg: Double
        let pctBand: Double
        let glowFunc: (Double, Double, String) -> Color

        private func color(_ v: Double, _ avg: Double, _ label: String) -> Color {
            glowFunc(v, avg, label)
        }

        var body: some View {
            HStack(spacing: 8) {
                Text(position)
                    .font(.caption.bold())
                    .foregroundColor(colorFor(position))
                    .frame(width: 32, alignment: .leading)
                statBlock(label: "PPW", value: ppw, avg: ppwAvg)
                statBlock(label: "IND", value: ind, avg: indAvg)
                Spacer()
            }
            .font(.caption2)
        }

        private func statBlock(label: String, value: Double, avg: Double) -> some View {
            let glow = color(value, avg, label)
            return VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Text(label)
                        .foregroundColor(.white.opacity(0.55))
                    Text(String(format: "%.2f", value))
                        .foregroundColor(.white)
                        .glowShadow(color: glow)
                    Text(deltaString(value - avg))
                        .foregroundColor(glow)
                }
                Text("Lg \(String(format: "%.2f", avg))")
                    .foregroundColor(.white.opacity(0.35))
            }
            .font(.caption2.bold())
        }

        private func deltaString(_ d: Double) -> String {
            if abs(d) < 0.01 { return "±0" }
            return String(format: "%+.2f", d)
        }

        private func colorFor(_ pos: String) -> Color {
            switch pos {
            case "QB": return .red
            case "RB": return .green
            case "WR": return .blue
            case "TE": return .yellow
            case "K": return Color(red: 0.90, green: 0.88, blue: 0.98)
            case "DL": return .orange
            case "LB": return .purple
            case "DB": return .pink
            default: return .white
            }
        }
    }

    private struct GradeInfoSheet: View {
        let gradeBreakdown: StatGradeBreakdown
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Performance Grade")
                    .font(.title3.bold())
                Text("Your grade reflects how this franchise compares to the league in Points For, Weekly Average, Management %, and Record. Higher = better all-around performance.")
                    .font(.callout)
                VStack(alignment: .leading, spacing: 8) {
                    row("A+", "Top 5%")
                    row("A", "Top 15%")
                    row("A-", "Top 25%")
                    row("B+", "Top 40%")
                    row("B", "Top 55%")
                    row("B-", "Top 70%")
                    row("C+", "Top 85%")
                    row("C", "Top 95%")
                    row("C-", "Bottom 5%")
                }
                Divider()
                Text("Your Grade: \(gradeBreakdown.grade) (Composite: \(String(format: "%.2f", gradeBreakdown.composite)))")
                    .font(.callout.bold())
                ForEach(gradeBreakdown.percentiles.sorted(by: { $0.key < $1.key }), id: \.key) { stat, perc in
                    Text("\(stat): Top \(Int((1.0 - perc)*100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .presentationBackground(.regularMaterial)
        }

        private func row(_ label: String, _ desc: String) -> some View {
            HStack {
                Text(label).bold().frame(width: 38, alignment: .leading)
                Text(desc).foregroundColor(.secondary)
                Spacer()
            }
            .font(.caption)
        }
    }
}

// MARK: - Stat Grading Helper

private func statGradeForModel(
    model: DeckFranchiseModel,
    allModels: [DeckFranchiseModel]
) -> StatGradeBreakdown {
    let pfArr = allModels.map { $0.stats.totalPointsFor }
    let ppwArr = allModels.map { $0.stats.teamPPW }
    let mgmtArr = allModels.map { $0.stats.managementPercent }
    let offMgmtArr = allModels.map { $0.stats.offensiveManagementPercent }
    let defMgmtArr = allModels.map { $0.stats.defensiveManagementPercent }
    let recArr = allModels.map {
        let g = Double($0.wins + $0.losses + $0.ties)
        return g > 0 ? Double($0.wins) / g : 0
    }

    let pfP = percentile(for: model.stats.totalPointsFor, in: pfArr.sorted(by: >))
    let ppwP = percentile(for: model.stats.teamPPW, in: ppwArr.sorted(by: >))
    let mgmtP = percentile(for: model.stats.managementPercent, in: mgmtArr.sorted(by: >))
    let offMgmtP = percentile(for: model.stats.offensiveManagementPercent, in: offMgmtArr.sorted(by: >))
    let defMgmtP = percentile(for: model.stats.defensiveManagementPercent, in: defMgmtArr.sorted(by: >))
    let recP = percentile(for: recArr[allModels.firstIndex(where: { $0.ownerId == model.ownerId }) ?? 0], in: recArr.sorted(by: >))

    let composite = pfP * 0.25 + ppwP * 0.20 + mgmtP * 0.20 + offMgmtP * 0.10 + defMgmtP * 0.10 + recP * 0.15
    let grade: String = {
        switch composite {
        case 0.95...1: return "A+"
        case 0.85..<0.95: return "A"
        case 0.75..<0.85: return "A-"
        case 0.60..<0.75: return "B+"
        case 0.45..<0.60: return "B"
        case 0.30..<0.45: return "B-"
        case 0.15..<0.30: return "C+"
        case 0.05..<0.15: return "C"
        default: return "C-"
        }
    }()
    let percentiles: [String: Double] = [
        "Points For": pfP,
        "PPW": ppwP,
        "Mgmt%": mgmtP,
        "Off Mgmt%": offMgmtP,
        "Def Mgmt%": defMgmtP,
        "Record": recP
    ]
    let summary = "\(grade) (Composite: \(String(format: "%.2f", composite))) ● Top \(Int((1.0 - pfP)*100))% Points, Top \(Int((1.0 - mgmtP)*100))% Mgmt"
    return StatGradeBreakdown(grade: grade, composite: composite, percentiles: percentiles, summary: summary)
}

// MARK: - Glow Shadow Modifier

struct GlowShadow: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.9), radius: 6, y: 0)
            .shadow(color: color.opacity(0.6), radius: 10, y: 0)
    }
}

extension View {
    func glowShadow(color: Color) -> some View {
        modifier(GlowShadow(color: color))
    }
}

// MARK: - Utilities

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        var out: [[Element]] = []
        var idx = 0
        while idx < count {
            let end = Swift.min(idx + size, count)
            out.append(Array(self[idx..<end]))
            idx = end
        }
        return out
    }
}

// MARK: - AggregatedOwnerStats stat value helper

extension AggregatedOwnerStats {
    func statValue(for key: String) -> Double {
        switch key {
        case "PF": return totalPointsFor
        case "PPW": return teamPPW
        case "OPF": return totalOffensivePointsFor
        case "OPPW": return offensivePPW
        case "DPF": return totalDefensivePointsFor
        case "DPPW": return defensivePPW
        case "Mgmt%": return managementPercent
        case "OMgmt%": return offensiveManagementPercent
        case "DMgmt%": return defensiveManagementPercent
        default: return 0
        }
    }
}
