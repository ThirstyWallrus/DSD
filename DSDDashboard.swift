//
//  DSDDashboard.swift
//  DynastyStatDrop
//
//  Full updated file (includes Off MPF / Def MPF integration)
//  NOTE: StandingsExplorerView struct should be REMOVED and placed in its own file (StandingsExplorerView.swift).
//  This file should not contain StandingsExplorerView, but should import and use it.
//  No code is truncated or removed except for StandingsExplorerView struct.
//

import SwiftUI
import Foundation
import UIKit

struct DSDDashboard: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appSelection: AppSelection
    @EnvironmentObject var leagueManager: SleeperLeagueManager
    @Binding var selectedTab: Tab
    @AppStorage("statDropPersonality") var userStatDropPersonality: StatDropPersonality = .classicESPN
   
    // Layout constants
    private let horizontalEdgePadding: CGFloat = 16
    private let cardHeight: CGFloat = 160
    private let cardSpacing: CGFloat = 30
    private let cardMaxWidth: CGFloat = 780
    private let threeCardHeight: CGFloat = 3 * 160 + 2 * 30
   
    // Default card selections
    private let defaultStandings: Set<Category> = [.teamStanding, .pointsForStanding, .averagePointsPerWeekStanding]
    private let defaultTeam: Set<Category>       = [.pointsFor, .teamAveragePPW, .managementPercent]
    private let defaultOffensive: Set<Category>  = [
        .offensivePointsFor,
        .averageOffensivePPW,
        .offensiveManagementPercent
    ]
    private let defaultDefensive: Set<Category>  = [
        .defensivePointsFor,
        .averageDefensivePPW,
        .defensiveManagementPercent
    ]
   
    // UI / selection state
    @State private var showImportLeague = false
    @State private var showSettingsMenu = false
   
    // Customization (3 stats per card)
    @State private var selectedStandings: Set<Category> = []
    @State private var selectedTeamStats: Set<Category> = []
    @State private var selectedOffensiveStats: Set<Category> = []
    @State private var selectedDefensiveStats: Set<Category> = []
    @State private var customizationLoaded = false
   
    // Behavior flags
    @State private var suppressAutoUserTeam = false
   
    // Flip / expand model
    @StateObject private var flipModel = FlipExpandModel()
    @Namespace private var statCardNamespace
    @AccessibilityFocusState private var isAccessibilityFocused: Bool
   
    // Standings Explorer
    @State private var standingsSelectedCategory: Category = .pointsForStanding
    @State private var standingsSearchText: String = ""
    @State private var standingsShowGrid = false
   
    // Convenience
    var selectedLeague: LeagueData? { appSelection.selectedLeague }
    var seasons: [SeasonData] { selectedLeague?.seasons ?? [] }
    private var isAllTimeMode: Bool { appSelection.selectedSeason == "All Time" }
   
    var allSeasonNames: [String] {
        let ids = seasons.map { $0.id }
        return ids.isEmpty ? ["All Time"] : ["All Time"] + ids
    }
    var teams: [TeamStanding] {
        guard let league = selectedLeague else { return [] }
        if isAllTimeMode {
            return league.seasons.sorted { $0.id < $1.id }.last?.teams ?? []
        }
        return league.seasons.first(where: { $0.id == appSelection.selectedSeason })?.teams ?? []
    }
    var selectedTeam: TeamStanding? {
        appSelection.selectedTeam
    }
   
    private func aggregatedOwner(for team: TeamStanding?) -> AggregatedOwnerStats? {
        guard isAllTimeMode,
              let t = team,
              let league = selectedLeague,
              let cache = league.allTimeOwnerStats else { return nil }
        return cache[t.ownerId]
    }
   
    struct AggregatedTeamStats {
        let teamName: String
        let totalPointsFor: Double
        let totalMaxPointsFor: Double
        let aggregatedManagementPercent: Double
        let avgTeamPPW: Double
        let totalWins: Int
        let totalLosses: Int
        let totalTies: Int
        let offensivePointsFor: Double?
        let defensivePointsFor: Double?
        let avgOffPPW: Double?
        let avgDefPPW: Double?
        let championships: Int
        let totalMaxOffensivePointsFor: Double?
        let totalMaxDefensivePointsFor: Double?
        let playoffStats: PlayoffStats?
    }
   
    // Helper to build aggregated stats for any team
    private func aggregatedStats(for team: TeamStanding) -> AggregatedTeamStats? {
        guard isAllTimeMode,
              let league = selectedLeague,
              let cache = league.allTimeOwnerStats,
              let agg = cache[team.ownerId] else { return nil }
        return AggregatedTeamStats(
            teamName: agg.latestDisplayName,
            totalPointsFor: agg.totalPointsFor,
            totalMaxPointsFor: agg.totalMaxPointsFor,
            aggregatedManagementPercent: agg.managementPercent,
            avgTeamPPW: agg.teamPPW,
            totalWins: agg.totalWins,
            totalLosses: agg.totalLosses,
            totalTies: agg.totalTies,
            offensivePointsFor: agg.totalOffensivePointsFor,
            defensivePointsFor: agg.totalDefensivePointsFor,
            avgOffPPW: agg.offensivePPW,
            avgDefPPW: agg.defensivePPW,
            championships: agg.championships,
            totalMaxOffensivePointsFor: agg.totalMaxOffensivePointsFor,
            totalMaxDefensivePointsFor: agg.totalMaxDefensivePointsFor,
            playoffStats: agg.playoffStats        )
    }
   
    var aggregatedAllTime: AggregatedTeamStats? {
        guard let team = selectedTeam else { return nil }
        return aggregatedStats(for: team)
    }
   
    // Header helpers
    private var seasonDisplayText: String {
        guard let league = selectedLeague else { return "--" }
        if isAllTimeMode || appSelection.selectedSeason.isEmpty {
            let count = league.seasons.count
            return "\(count)\(ordinalSuffix(count)) season"
        }
        if let idx = league.seasons.firstIndex(where: { $0.id == appSelection.selectedSeason }) {
            let n = idx + 1
            return "\(n)\(ordinalSuffix(n)) season"
        }
        return appSelection.selectedSeason
    }
    private func displayRecord() -> String {
        if isAllTimeMode, let agg = aggregatedAllTime {
            return "\(agg.totalWins)-\(agg.totalLosses)\(agg.totalTies > 0 ? "-\(agg.totalTies)" : "")"
        }
        return selectedTeam?.winLossRecord ?? "--"
    }
   
    // Category lists
    let availableStandings: [Category] = [
        .teamStanding, .pointsForStanding, .averagePointsPerWeekStanding, .averagePointsScoredAgainstPerWeekStanding,
        .maxPointsForStanding, .managementPercentStanding, .offensiveStanding, .defensiveStanding,
        .pointsScoredAgainstStanding, .qbPPWStanding, .individualQBPPWStanding, .rbPPWStanding, .individualRBPPWStanding,
        .wrPPWStanding, .individualWRPPWStanding, .tePPWStanding, .individualTEPPWStanding, .kickerPPWStanding,
        .individualKickerPPWStanding, .dlPPWStanding, .individualDLPPWStanding, .lbPPWStanding, .individualLBPPWStanding,
        .dbPPWStanding, .individualDBPPWStanding
    ]
    let availableTeamStats: [Category] = [
        .pointsFor, .teamAveragePPW, .managementPercent, .maxPointsFor, .pointsScoredAgainst,
        .highestPointsInGameAllTime, .highestPointsInGameSeason, .recordAllTime, .recordSeason,
        .mostPointsAgainstAllTime, .mostPointsAgainstSeason, .playoffBerthsAllTime, .playoffRecordAllTime, .championships
    ]
    let availableOffensiveStats: [Category] = [
        .offensivePointsFor, .maxOffensivePointsFor, .averageOffensivePPW, .offensiveManagementPercent,
        .bestOffensivePositionPPW, .worstOffensivePositionPointsAgainstPPW,
        .qbPositionPPW, .rbPositionPPW, .wrPositionPPW, .tePositionPPW, .kickerPPW,
        .individualQBPPW, .individualRBPPW, .individualWRPPW, .individualTEPPW, .individualKickerPPW
    ]
    let availableDefensiveStats: [Category] = [
        .defensivePointsFor, .maxDefensivePointsFor, .averageDefensivePPW, .defensiveManagementPercent,
        .bestDefensivePositionPPW, .worstDefensivePositionPointsAgainstPPW,
        .dlPositionPPW, .lbPositionPPW, .dbPositionPPW,
        .individualDLPPW, .individualLBPPW, .individualDBPPW
    ]
    let standingsExplorerCategories: [Category] = [
        .teamStanding,
        .pointsForStanding, .maxPointsForStanding, .averagePointsPerWeekStanding,
        .managementPercentStanding,
        .offensiveManagementPercentStanding,
        .defensiveManagementPercentStanding,
        .offensiveStanding, .defensiveStanding,
        .qbPPWStanding, .rbPPWStanding, .wrPPWStanding, .tePPWStanding, .kickerPPWStanding,
        .dlPPWStanding, .lbPPWStanding, .dbPPWStanding,
        .individualQBPPWStanding, .individualRBPPWStanding, .individualWRPPWStanding,
        .individualTEPPWStanding, .individualKickerPPWStanding,
        .individualDLPPWStanding, .individualLBPPWStanding, .individualDBPPWStanding
    ]
    private let ascendingBetterStandings: Set<Category> = [
        .pointsScoredAgainstStanding, .averagePointsScoredAgainstPerWeekStanding
    ]
   
    // Position tokens (normalize keys for DL, LB, DB)
    let positionColors: [String: Color] = [
        PositionNormalizer.normalize("QB"): .red,
        PositionNormalizer.normalize("RB"): .green,
        PositionNormalizer.normalize("WR"): .blue,
        PositionNormalizer.normalize("TE"): .yellow,
        PositionNormalizer.normalize("K"): Color(red: 0.75, green: 0.6, blue: 1.0),
        PositionNormalizer.normalize("DL"): .orange,
        PositionNormalizer.normalize("LB"): .purple,
        PositionNormalizer.normalize("DB"): .pink
    ]
   
    var body: some View {
        ZStack {
            Image("Background1").resizable().ignoresSafeArea()
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 20) {
                        logoAndDashboardText(availableWidth: geo.size.width)
                        teamInfoLine
                        selectionMenus
                        cardGrid(availableWidth: geo.size.width)
                            .padding(.bottom, 30)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
            }
            overlayLayer
        }
        .onAppear {
            initializeDefaultSelections()
            syncInitialSelections(replaceTeam: false)
            loadCustomizationIfAvailable()
            standingsSelectedCategory = standingsExplorerCategories.first ?? .teamStanding
            if appSelection.leagues.isEmpty {
                loadSavedLeagues()
            }
            // KEEP appSelection.currentUsername in sync with the motherview's selected username
            appSelection.currentUsername = authViewModel.currentUsername
        }
        .onChange(of: appSelection.leagues) { _, _ in syncInitialSelections(replaceTeam: true) }
        .onChange(of: appSelection.selectedLeagueId) { _, _ in
            customizationLoaded = false
            syncInitialSelections(replaceTeam: false)
            loadCustomizationIfAvailable(force: true)
        }
        .onChange(of: authViewModel.userTeam) { _, _ in syncInitialSelections(replaceTeam: true) }
        // Keep appSelection.currentUsername updated whenever the authViewModel's currentUsername changes
        .onChange(of: authViewModel.currentUsername) { _, _ in
            appSelection.currentUsername = authViewModel.currentUsername
        }
        .onChange(of: appSelection.selectedSeason) { _, _ in handleSeasonChange() }
        .onChange(of: selectedStandings) { _, _ in enforceIntegrityAndPersist() }
        .onChange(of: selectedTeamStats) { _, _ in enforceIntegrityAndPersist() }
        .onChange(of: selectedOffensiveStats) { _, _ in enforceIntegrityAndPersist() }
        .onChange(of: selectedDefensiveStats) { _, _ in enforceIntegrityAndPersist() }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)) { _ in
            flipModel.reducedMotion = UIAccessibility.isReduceMotionEnabled
        }
    }
   
    // MARK: Header UI
    private func logoAndDashboardText(availableWidth: CGFloat) -> some View {
        let maxLogoWidth = min(availableWidth - 2 * horizontalEdgePadding, 300)
        return VStack(spacing: -60) {
            Image("DSDLogo")
                .resizable()
                .scaledToFit()
                .frame(width: maxLogoWidth)
                .accessibilityHidden(flipModel.isAnyOverlayActive)
            Image("DashboardText")
                .resizable()
                .scaledToFit()
                .frame(width: maxLogoWidth)
                .accessibilityHidden(flipModel.isAnyOverlayActive)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, -155)
        .animation(.easeInOut(duration: 0.25), value: maxLogoWidth)
    }
    private var teamInfoLine: some View {
        let displayName: String = {
            if let team = selectedTeam {
                return isAllTimeMode
                ? (aggregatedOwner(for: team)?.latestDisplayName ?? team.name)
                : team.name
            }
            return appSelection.userTeam
            ?? fallbackFirstTeamName()
            ?? "Team"
        }()
        return HStack(spacing: 8) {
            Text(displayName)
                .font(.custom("Phatt", size: 18)).bold()
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(seasonDisplayText)
                .font(.custom("Phatt", size: 18)).bold()
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(displayRecord())
                .font(.custom("Phatt", size: 18)).bold()
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.55))
        .cornerRadius(12)
        .shadow(color: .yellow.opacity(0.8), radius: 6, y: 2)
        .padding(.horizontal, horizontalEdgePadding)
        .accessibilityHidden(flipModel.isAnyOverlayActive)
    }
   
    // MARK: Menus
    private var selectionMenus: some View {
        VStack(spacing: 10) {
            // Top row: League menu stretched full width
            leagueMenu
                .frame(height: 50)
                .sheet(isPresented: $showImportLeague) {
                    SleeperLeaguesImportView(
                        onLeagueImported: { newLeagueId in
                            appSelection.selectedLeagueId = newLeagueId
                            customizationLoaded = false
                            appSelection.selectedSeason = ""
                            appSelection.selectedTeamId = nil
                            suppressAutoUserTeam = false
                            DispatchQueue.main.async {
                                syncInitialSelections(replaceTeam: true)
                                if let userTeam = authViewModel.userTeam,
                                   let league = appSelection.leagues.first(where: { $0.id == newLeagueId }),
                                   let latestSeason = league.seasons.sorted(by: { $0.id < $1.id }).last,
                                   let userTeamMatch = latestSeason.teams.first(where: { $0.name == userTeam }) {
                                    appSelection.selectedTeamId = userTeamMatch.id
                                }
                                loadCustomizationIfAvailable(force: true)
                                handleSeasonChange()
                                loadSavedLeagues()
                            }
                            print("Auto-selected new league: \(newLeagueId)")
                        }
                    )
                }
                .accessibilityHidden(flipModel.isAnyOverlayActive)

            // Bottom row: season (bubble-sized) | team (stretch) | settings (bubble-sized)
            GeometryReader { geo in
                let spacing: CGFloat = 12
                // Measure the season text and set a reasonable min/max to avoid extremes.
                let seasonLabel = appSelection.selectedSeason.isEmpty ? "Season" : appSelection.selectedSeason
                let measured = measuredTextWidth(seasonLabel, fontSize: 16, fontName: "Phatt")
                // Add padding so the bubble includes the label's horizontal padding in menuLabel.
                let bubbleWidth = min(max(60, measured + 40), 160) // clamps between 60 and 160
                let totalAvailable = geo.size.width
                // Account for spacing between three items: two gaps of 'spacing'
                let teamWidth = max(80, totalAvailable - bubbleWidth * 2 - spacing * 2)
                HStack(spacing: spacing) {
                    seasonMenu
                        .frame(width: bubbleWidth)
                    teamMenu
                        .frame(width: teamWidth)
                    settingsMenuButton
                        .frame(width: bubbleWidth)
                }
                .accessibilityHidden(flipModel.isAnyOverlayActive)
            }
            .frame(height: 50)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, horizontalEdgePadding)
    }
    private func menuLabel(_ text: String) -> some View {
        Text(text)
            .bold()
            .foregroundColor(.orange)
            .font(.custom("Phatt", size: 16))
            .frame(minHeight: 36)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 30)
                    .fill(Color.black)
                    .shadow(color: .blue.opacity(0.7), radius: 8, y: 2)
            )
    }
    private var seasonMenu: some View {
        Menu {
            ForEach(allSeasonNames, id: \.self) { name in
                Button(name) {
                    appSelection.selectedSeason = name
                    handleSeasonChange()
                }
            }
        } label: { menuLabel(appSelection.selectedSeason.isEmpty ? "Season" : appSelection.selectedSeason) }
    }
    private var leagueMenu: some View {
        Menu {
            ForEach(appSelection.leagues, id: \.id) { league in
                Button(league.name) {
                    appSelection.selectedLeagueId = league.id
                    let key = "dsd.lastSelectedLeague.\(currentUsernameForKey())"
                    UserDefaults.standard.set(league.id, forKey: key)
                    customizationLoaded = false
                    appSelection.selectedSeason = league.seasons.sorted { $0.id < $1.id }.last?.id ?? "All Time"
                    handleSeasonChange()
                    loadCustomizationIfAvailable(force: true)
                }
            }
            Divider()
            Button("Upload New League") { showImportLeague = true }
        } label: {
            menuLabel(appSelection.selectedLeague?.name ?? "Import League")
        }
    }
   
    private var settingsMenuButton: some View {
        Menu {
            Button("Sync Leagues") { syncLeagues() }
            Button("Reset Leagues", action: resetLeagues)
            Divider()
            Button("Settings") { showSettingsMenu = true }
            Button("Sign Out", action: signOut)
        } label: {
            Image(systemName: "gearshape.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .foregroundColor(.orange)
                .background(
                    RoundedRectangle(cornerRadius: 30)
                        .fill(Color.black)
                        .shadow(color: .blue.opacity(0.7), radius: 8, y: 2)
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
    }
   
    private func signOut() {
        authViewModel.logout()
        if let username = authViewModel.currentUsername {
            UserDefaults.standard.set(false, forKey: "rememberMe_\(username)")
            UserDefaults.standard.removeObject(forKey: "lastRememberedUsername")
        }
        appSelection.leagues = []
        appSelection.selectedLeagueId = nil
        appSelection.selectedTeamId = nil
        appSelection.selectedSeason = ""
        appSelection.userTeam = ""
        appSelection.currentUsername = nil
        leagueManager.clearInMemory()
    }

    private func resetLeagues() {
        leagueManager.clearInMemory()
        leagueManager.saveLeagues()
        let activeUsername = authViewModel.currentUsername ?? "global"
        let userDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SleeperLeagues", isDirectory: true)
            .appendingPathComponent(activeUsername, isDirectory: true)
        if FileManager.default.fileExists(atPath: userDir.path) {
            try? FileManager.default.removeItem(at: userDir)
        }
        appSelection.leagues = []
        appSelection.selectedLeagueId = nil
        appSelection.selectedTeamId = nil
        appSelection.selectedSeason = ""
        appSelection.userTeam = ""
        UserDefaults.standard.removeObject(forKey: "dsd.lastSelectedLeague.\(activeUsername)")
        UserDefaults.standard.set(false, forKey: "hasImportedLeague_\(activeUsername)")
        OwnerAssetStore.shared.clearDisk()
    }
   
    private func syncLeagues() {
        guard let selectedLeague = appSelection.selectedLeague else {
            print("No league selected for sync")
            return
        }
        print("Syncing league: \(selectedLeague.name)")
        leagueManager.refreshLeagueData(leagueId: selectedLeague.id) { result in
            DispatchQueue.main.async { [self] in
                switch result {
                case .success(let updatedLeague):
                    if let index = appSelection.leagues.firstIndex(where: { $0.id == selectedLeague.id }) {
                        appSelection.leagues[index] = updatedLeague
                    }
                    customizationLoaded = false
                    loadCustomizationIfAvailable(force: true)
                    print("League sync completed: \(updatedLeague.name)")
                case .failure(let error):
                    print("Sync failed: \(error.localizedDescription)")
                }
            }
        }
    }
   
    // ... (existing imports and struct definition) ...

    private var teamMenu: some View {
        Menu {
            let sortedTeams = teams.sorted { teamA, teamB in
                let nameA = isAllTimeMode
                    ? (aggregatedOwner(for: teamA)?.latestDisplayName ?? teamA.name)
                    : teamA.name
                let nameB = isAllTimeMode
                    ? (aggregatedOwner(for: teamB)?.latestDisplayName ?? teamB.name)
                    : teamB.name
                return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
            }
            ForEach(sortedTeams, id: \.id) { team in
                let displayName = isAllTimeMode
                    ? (aggregatedOwner(for: team)?.latestDisplayName ?? team.name)
                    : team.name
                let isSelected = appSelection.selectedTeamId == team.id
                Button(displayName) {
                    appSelection.setUserSelectedTeam(teamId: team.id, teamName: displayName)
                }
                .foregroundColor(isSelected ? .orange : .white)
                .background(isSelected ? Color.orange.opacity(0.2) : Color.clear)
                .cornerRadius(8)
            }
        } label: {
            let displayName: String = {
                if let team = selectedTeam {
                    return isAllTimeMode
                    ? (aggregatedOwner(for: team)?.latestDisplayName ?? team.name)
                    : team.name
                }
                return appSelection.userTeam ?? "Select Team"
            }()
            menuLabel(displayName)
        }
    }
   
    private func cardGrid(availableWidth: CGFloat) -> some View {
        let usableWidth = min(cardMaxWidth, availableWidth - 2 * horizontalEdgePadding)
        return VStack(spacing: cardSpacing) {
            statCard(index: 0, glow: .orange, categories: Array(selectedStandings), width: usableWidth)
            statCard(index: 1, glow: .green, categories: Array(selectedTeamStats), width: usableWidth)
            statCard(index: 2, glow: .red, categories: Array(selectedOffensiveStats), width: usableWidth)
            statCard(index: 3, glow: .blue, categories: Array(selectedDefensiveStats), width: usableWidth)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, horizontalEdgePadding)
        .animation(.easeInOut(duration: 0.25), value: flipModel.isAnyOverlayActive)
    }
    private func statCard(index: Int,
                          glow: Color,
                          categories: [Category],
                          width: CGFloat) -> some View {
        let isExpanded = flipModel.expandedSection == index
        let isCustomizing = flipModel.customizingSection == index
        let isOtherDimmed = flipModel.isAnyOverlayActive && !isExpanded && !isCustomizing
        let showFront = !isExpanded && !isCustomizing
        let identifier = "card-\(index)"
        let team = selectedTeam
        return ZStack {
            if showFront {
                collapsedCard(index: index, glow: glow, categories: categories, team: team)
                    .matchedGeometryEffect(id: identifier, in: statCardNamespace)
            } else {
                Color.clear.frame(height: cardHeight)
            }
        }
        .frame(width: width)
        .opacity(isOtherDimmed ? 0 : 1)
        .scaleEffect(isOtherDimmed ? 0.95 : 1)
        .animation(.easeInOut(duration: 0.25), value: isOtherDimmed)
        .onTapGesture {
            guard flipModel.customizingSection == nil else { return }
            flipModel.beginFlip(for: index)
        }
    }
    private func collapsedCard(index: Int,
                               glow: Color,
                               categories: [Category],
                               team: TeamStanding?) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.black)
            .overlay(
                VStack(spacing: 8) {
                    let displayName = isAllTimeMode
                    ? (aggregatedOwner(for: team)?.latestDisplayName ?? (team?.name ?? ""))
                    : (team?.name ?? "")
                    Text(
                        index == 0 ? "\(displayName) Standings" :
                        index == 1 ? "Team Stat Drop" :
                        index == 2 ? "Offensive Stat Drop" : "Defensive Stat Drop"
                    )
                    .foregroundColor(glow)
                    .bold()
                    .font(.custom("Phatt", size: 20))
                    .underline()
                    .padding(.top, 8)
                   
                    Spacer(minLength: 0)
                   
                    if let team = team, !categories.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(categories.prefix(3), id: \.self) { category in
                                VStack(spacing: 4) {
                                    coloredStatName(category)
                                        .padding(.vertical, 2)
                                        .padding(.horizontal, 6)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                    Text(statDisplayValue(category: category, team: team))
                                        .foregroundColor(.white)
                                        .bold()
                                        .font(.custom("Phatt", size: 14))
                                        .minimumScaleFactor(0.7)
                                        .lineLimit(1)
                                        .frame(maxWidth: 90)
                                }
                                .frame(minWidth: 70, maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 6)
                    } else {
                        Text("No data")
                            .font(.custom("Phatt", size: 16))
                            .foregroundColor(.gray)
                    }
                   
                    Spacer(minLength: 0)
                   
                    Button("Customize") {
                        flipModel.beginCustomize(for: index)
                    }
                    .underline()
                    .font(.custom("Phatt", size: 12))
                    .foregroundColor(.blue)
                    .bold()
                    .padding(.bottom, 10)
                    .disabled(flipModel.expandedSection != nil)
                }
                .padding(.horizontal, 8)
            )
            .shadow(color: glow.opacity(0.9), radius: 10, y: 4)
            .frame(height: cardHeight)
    }
   
    @ViewBuilder
    private var overlayLayer: some View {
        if flipModel.isAnyOverlayActive {
            GeometryReader { proxy in
                let width = min(proxy.size.width - 2 * horizontalEdgePadding, cardMaxWidth)
                let height = min(threeCardHeight, proxy.size.height - 120)
                let identifier = "card-\(flipModel.expandedSection ?? flipModel.customizingSection ?? -1)"
                ZStack {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture { flipModel.collapse() }
                    VStack {
                        Spacer(minLength: 0)
                        ZStack {
                            if let index = flipModel.expandedSection ?? flipModel.customizingSection {
                                let glow: Color = [0: .orange, 1: .green, 2: .red, 3: .blue][index] ?? .orange
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.black)
                                    .shadow(color: glow.opacity(0.9), radius: 34)
                                    .overlay(
                                        Group {
                                            if flipModel.expandedSection == index {
                                                flipFaceContainer(index: index, team: selectedTeam, glow: glow)
                                            } else {
                                                customizationContent(index: index, glow: glow)
                                            }
                                        }
                                    )
                                    .matchedGeometryEffect(id: identifier, in: statCardNamespace)
                                    .frame(width: width, height: height)
                                    .modifier(FlipTiltModifier(progress: flipModel.flipProgress,
                                                               enabled: flipModel.expandedSection == index,
                                                               glow: glow,
                                                               reducedMotion: flipModel.reducedMotion))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: flipModel.isAnyOverlayActive)
            }
            .accessibilityAddTraits(.isModal)
        }
    }
    @ViewBuilder
    private func flipFaceContainer(index: Int, team: TeamStanding?, glow: Color) -> some View {
        let angle = 180.0 * Double(flipModel.flipProgress)
        ZStack {
            if let team = team {
                frontSummaryFlip(index: index, team: team, glow: glow)
                    .opacity(angle < 90 ? 1 : 0)
                    .rotation3DEffect(.degrees(angle), axis: (0,1,0), perspective: 0.9/900)
            }
            backDetailFlip(index: index, glow: glow)
                .opacity(angle >= 90 ? 1 : 0)
                .rotation3DEffect(.degrees(angle - 180), axis: (0,1,0), perspective: 0.9/900)
                .rotation3DEffect(.degrees(180), axis: (0,1,0)) // <-- Fix
            closeButton
        }
        .clipped()
    }
    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { flipModel.collapse() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(6)
                }
                .accessibilityLabel("Close expanded panel")
            }
            Spacer()
        }
        .padding(.trailing, 8)
        .padding(.top, 8)
    }
    private func frontSummaryFlip(index: Int, team: TeamStanding, glow: Color) -> some View {
        VStack(spacing: 16) {
            Text(cardTitle(index: index, team: team))
                .foregroundColor(glow)
                .font(.custom("Phatt", size: 28))
                .underline()
                .padding(.top, 4)
            HStack(spacing: 14) {
                ForEach(displayCategories(for: index).prefix(3), id: \.self) { cat in
                    VStack(spacing: 6) {
                        coloredStatName(cat)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.7)))
                        Text(statDisplayValue(category: cat, team: team))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            Text("Flipping...")
                .font(.caption)
                .foregroundColor(.white.opacity(0.35))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }
    @ViewBuilder
        private func backDetailFlip(index: Int, glow: Color) -> some View {
            switch index {
            case 0:
                if let allTimeOwnerStats = selectedLeague?.allTimeOwnerStats {
                    Group {
                        StandingsExplorerView(
                            categories: standingsExplorerCategories,
                            ascendingBetter: ascendingBetterStandings,
                            selected: $standingsSelectedCategory,
                            searchText: $standingsSearchText,
                            showGrid: $standingsShowGrid,
                            statProvider: { cat, tm in self.valueForStandingCategory(cat, team: tm) },
                            rankProvider: { cat, tm in self.rankString(for: cat, team: tm) },
                            colorForCategory: { categoryColor(for: $0) },
                            onClose: { flipModel.collapse() },
                            isAllTimeMode: isAllTimeMode,
                            ownerAggProvider: { aggregatedOwner(for: $0) },
                            ascendingBetterStandings: ascendingBetterStandings,
                            allTimeOwnerStats: allTimeOwnerStats
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(8)
                    }
                } else {
                    Group {
                        emptyDetail
                    }
                }
            case 1:
                // Use the new TeamStatExpandedView (consistent layout with Off/Def)
                ScrollView {
                    TeamStatExpandedView(aggregatedAllTime: { team in
                        return self.aggregatedStats(for: team)
                    })
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(4)
            case 2:
                // Use OffStatExpandedView (new consistent offense panel)
                ScrollView {
                    OffStatExpandedView()
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(4)
            case 3:
                ScrollView {
                    DefStatExpandedView()
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(4)
            default:
                emptyDetail
            }
        }
    private var emptyDetail: some View {
            VStack {
                Spacer()
                Text("No Team Selected")
                    .foregroundColor(.gray)
                    .font(.headline)
                Spacer()
            }
        }
   
    // MARK: Helpers (color, stats, ranking)
    private func categoryColor(for category: Category) -> Color {
        let abbr = category.abbreviation
        let token = abbr.split(separator: " ").first.map(String.init) ?? abbr
        // Use normalized token for DL, LB, DB
        return positionColors[PositionNormalizer.normalize(token)] ?? .orange
    }
    private func valueForStandingCategory(_ category: Category, team: TeamStanding) -> String {
        if isAllTimeMode, let agg = aggregatedOwner(for: team) {
            switch category {
            case .teamStanding: return rankString(for: .teamStanding, team: team)
            case .pointsForStanding: return formatNumber(agg.totalPointsFor, decimals: 2)
            case .averagePointsPerWeekStanding: return String(format: "%.2f", agg.teamPPW)
            case .maxPointsForStanding: return formatNumber(agg.totalMaxPointsFor, decimals: 2)
            case .managementPercentStanding: return String(format: "%.1f%%", agg.managementPercent)
            case .offensiveManagementPercentStanding: return String(format: "%.1f%%", agg.offensiveManagementPercent)
            case .defensiveManagementPercentStanding: return String(format: "%.1f%%", agg.defensiveManagementPercent)
            case .offensiveStanding: return formatNumber(agg.totalOffensivePointsFor, decimals: 2)
            case .defensiveStanding: return formatNumber(agg.totalDefensivePointsFor, decimals: 2)
            case .qbPPWStanding: return ppwString(agg.positionAvgPPW[PositionNormalizer.normalize("QB")])
            case .rbPPWStanding: return ppwString(agg.positionAvgPPW[PositionNormalizer.normalize("RB")])
            case .wrPPWStanding: return ppwString(agg.positionAvgPPW[PositionNormalizer.normalize("WR")])
            case .tePPWStanding: return ppwString(agg.positionAvgPPW[PositionNormalizer.normalize("TE")])
            case .kickerPPWStanding: return ppwString(agg.positionAvgPPW[PositionNormalizer.normalize("K")])
            case .dlPPWStanding: return ppwString(agg.positionAvgPPW[PositionNormalizer.normalize("DL")])
            case .lbPPWStanding: return ppwString(agg.positionAvgPPW[PositionNormalizer.normalize("LB")])
            case .dbPPWStanding: return ppwString(agg.positionAvgPPW[PositionNormalizer.normalize("DB")])
            case .individualQBPPWStanding: return ppwString(agg.individualPositionPPW[PositionNormalizer.normalize("QB")])
            case .individualRBPPWStanding: return ppwString(agg.individualPositionPPW[PositionNormalizer.normalize("RB")])
            case .individualWRPPWStanding: return ppwString(agg.individualPositionPPW[PositionNormalizer.normalize("WR")])
            case .individualTEPPWStanding: return ppwString(agg.individualPositionPPW[PositionNormalizer.normalize("TE")])
            case .individualKickerPPWStanding: return ppwString(agg.individualPositionPPW[PositionNormalizer.normalize("K")])
            case .individualDLPPWStanding: return ppwString(agg.individualPositionPPW[PositionNormalizer.normalize("DL")])
            case .individualLBPPWStanding: return ppwString(agg.individualPositionPPW[PositionNormalizer.normalize("LB")])
            case .individualDBPPWStanding: return ppwString(agg.individualPositionPPW[PositionNormalizer.normalize("DB")])
            default: break
            }
        }
        switch category {
        case .teamStanding: return ordinal(team.leagueStanding)
        case .pointsForStanding: return formatNumber(team.pointsFor, decimals: 2)
        case .averagePointsPerWeekStanding: return String(format: "%.2f", team.teamPointsPerWeek)
        case .maxPointsForStanding: return formatNumber(team.maxPointsFor, decimals: 2)
        case .managementPercentStanding:
            let mgmt = team.maxPointsFor > 0 ? (team.pointsFor / team.maxPointsFor) * 100 : 0
            return String(format: "%.1f%%", mgmt)
        case .offensiveManagementPercentStanding:
            let val = team.offensiveManagementPercent ?? 0
            return String(format: "%.1f%%", val)
        case .defensiveManagementPercentStanding:
            let val = team.defensiveManagementPercent ?? 0
            return String(format: "%.1f%%", val)
        case .offensiveStanding: return formatNumber(team.offensivePointsFor ?? 0, decimals: 2)
        case .defensiveStanding: return formatNumber(team.defensivePointsFor ?? 0, decimals: 2)
        case .qbPPWStanding: return formatPosAvg(team, key: .qbPositionPPW, normalizedKey: PositionNormalizer.normalize("QB"))
        case .rbPPWStanding: return formatPosAvg(team, key: .rbPositionPPW, normalizedKey: PositionNormalizer.normalize("RB"))
        case .wrPPWStanding: return formatPosAvg(team, key: .wrPositionPPW, normalizedKey: PositionNormalizer.normalize("WR"))
        case .tePPWStanding: return formatPosAvg(team, key: .tePositionPPW, normalizedKey: PositionNormalizer.normalize("TE"))
        case .kickerPPWStanding: return formatPosAvg(team, key: .kickerPPW, normalizedKey: PositionNormalizer.normalize("K"))
        case .dlPPWStanding: return formatPosAvg(team, key: .dlPositionPPW, normalizedKey: PositionNormalizer.normalize("DL"))
        case .lbPPWStanding: return formatPosAvg(team, key: .lbPositionPPW, normalizedKey: PositionNormalizer.normalize("LB"))
        case .dbPPWStanding: return formatPosAvg(team, key: .dbPositionPPW, normalizedKey: PositionNormalizer.normalize("DB"))
        case .individualQBPPWStanding: return formatIndAvg(team, key: .individualQBPPW, normalizedKey: PositionNormalizer.normalize("QB"))
        case .individualRBPPWStanding: return formatIndAvg(team, key: .individualRBPPW, normalizedKey: PositionNormalizer.normalize("RB"))
        case .individualWRPPWStanding: return formatIndAvg(team, key: .individualWRPPW, normalizedKey: PositionNormalizer.normalize("WR"))
        case .individualTEPPWStanding: return formatIndAvg(team, key: .individualTEPPW, normalizedKey: PositionNormalizer.normalize("TE"))
        case .individualKickerPPWStanding: return formatIndAvg(team, key: .individualKickerPPW, normalizedKey: PositionNormalizer.normalize("K"))
        case .individualDLPPWStanding: return formatIndAvg(team, key: .individualDLPPW, normalizedKey: PositionNormalizer.normalize("DL"))
        case .individualLBPPWStanding: return formatIndAvg(team, key: .individualLBPPW, normalizedKey: PositionNormalizer.normalize("LB"))
        case .individualDBPPWStanding: return formatIndAvg(team, key: .individualDBPPW, normalizedKey: PositionNormalizer.normalize("DB"))
        default: return "—"
        }
    }
    private func rankString(for category: Category, team: TeamStanding) -> String {
        standingRank(category: category, team: team)
    }
    private func ppwString(_ v: Double?) -> String {
        guard let v = v else { return "—" }
        return String(format: "%.2f", v)
    }
    private func formatPosAvg(_ team: TeamStanding, key: DSDStatsService.StatType, normalizedKey: String? = nil) -> String {
        let posKey = normalizedKey ?? {
            switch key {
            case .qbPositionPPW: return PositionNormalizer.normalize("QB")
            case .rbPositionPPW: return PositionNormalizer.normalize("RB")
            case .wrPositionPPW: return PositionNormalizer.normalize("WR")
            case .tePositionPPW: return PositionNormalizer.normalize("TE")
            case .kickerPPW: return PositionNormalizer.normalize("K")
            case .dlPositionPPW: return PositionNormalizer.normalize("DL")
            case .lbPositionPPW: return PositionNormalizer.normalize("LB")
            case .dbPositionPPW: return PositionNormalizer.normalize("DB")
            default: return ""
            }
        }()
        if let dict = team.positionAverages, let raw = dict[posKey] {
            return String(format: "%.2f", raw)
        }
        if let raw = DSDStatsService.shared.stat(for: team, type: key) as? Double {
            return String(format: "%.2f", raw)
        }
        return "—"
    }

    private func formatIndAvg(_ team: TeamStanding, key: DSDStatsService.StatType, normalizedKey: String? = nil) -> String {
        let posKey = normalizedKey ?? {
            switch key {
            case .individualQBPPW: return PositionNormalizer.normalize("QB")
            case .individualRBPPW: return PositionNormalizer.normalize("RB")
            case .individualWRPPW: return PositionNormalizer.normalize("WR")
            case .individualTEPPW: return PositionNormalizer.normalize("TE")
            case .individualKickerPPW: return PositionNormalizer.normalize("K")
            case .individualDLPPW: return PositionNormalizer.normalize("DL")
            case .individualLBPPW: return PositionNormalizer.normalize("LB")
            case .individualDBPPW: return PositionNormalizer.normalize("DB")
            default: return ""
            }
        }()
        if let dict = team.individualPositionAverages, let raw = dict[posKey] {
            return String(format: "%.2f", raw)
        }
        if let raw = DSDStatsService.shared.stat(for: team, type: key) as? Double {
            return String(format: "%.2f", raw)
        }
        if let arr = DSDStatsService.shared.stat(for: team, type: key) as? [String] {
            return arr.first ?? "—"
        }
        return "—"
    }
    private func customizationConfig(for index: Int) -> (binding: Binding<Set<Category>>, all: [Category], title: String)? {
        switch index {
        case 0: return ($selectedStandings, availableStandings, "Standings Stats")
        case 1: return ($selectedTeamStats, availableTeamStats, "Team Stats")
        case 2: return ($selectedOffensiveStats, availableOffensiveStats, "Offensive Stats")
        case 3: return ($selectedDefensiveStats, availableDefensiveStats, "Defensive Stats")
        default: return nil
        }
    }
    @ViewBuilder
    private func customizationContent(index: Int, glow: Color) -> some View {
        if let cfg = customizationConfig(for: index) {
            StatCardCustomizationOverlay(
                title: cfg.title,
                allItems: cfg.all,
                selectedItems: cfg.binding,
                maxSelections: 3,
                valueProvider: { cat in
                    if let team = selectedTeam { return statDisplayValue(category: cat, team: team) }
                    return "—"
                },
                onClose: { flipModel.collapseCustomization() },
                glowColor: glow
            )
            .padding(16)
        }
    }
    private func displayCategories(for index: Int) -> [Category] {
        switch index {
        case 0: return Array(selectedStandings)
        case 1: return Array(selectedTeamStats)
        case 2: return Array(selectedOffensiveStats)
        case 3: return Array(selectedDefensiveStats)
        default: return []
        }
    }
    private func cardTitle(index: Int, team: TeamStanding) -> String {
        let baseName = isAllTimeMode ? (aggregatedOwner(for: team)?.latestDisplayName ?? team.name) : team.name
        switch index {
        case 0: return "\(baseName) Standings"
        case 1: return "Team Drop"
        case 2: return "Offense Drop"
        case 3: return "Defense Drop"
        default: return "Stats"
        }
    }
    private func coloredStatName(_ category: Category) -> AnyView {
        let abbr = category.abbreviation
        let token = abbr.split(separator: " ").first.map(String.init) ?? abbr
        let color = positionColors[PositionNormalizer.normalize(token)] ?? .white
        return AnyView(
            Text(abbr)
                .foregroundColor(color)
                .font(.custom("Phatt", size: 15))
                .bold()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        )
    }
    private func underlyingStatForStanding(_ category: Category) -> DSDStatsService.StatType? {
        switch category {
        case .pointsForStanding: return .pointsFor
        case .averagePointsPerWeekStanding: return .teamAveragePPW
        case .maxPointsForStanding: return .maxPointsFor
        case .managementPercentStanding: return .managementPercent
        case .offensiveStanding: return .offensivePointsFor
        case .defensiveStanding: return .defensivePointsFor
        case .qbPPWStanding: return .qbPositionPPW
        case .individualQBPPWStanding: return .individualQBPPW
        case .rbPPWStanding: return .rbPositionPPW
        case .individualRBPPWStanding: return .individualRBPPW
        case .wrPPWStanding: return .wrPositionPPW
        case .individualWRPPWStanding: return .individualWRPPW
        case .tePositionPPW, .tePPWStanding: return .tePositionPPW
        case .individualTEPPWStanding: return .individualTEPPW
        case .kickerPPWStanding: return .kickerPPW
        case .individualKickerPPWStanding: return .individualKickerPPW
        case .dlPPWStanding: return .dlPositionPPW
        case .individualDLPPWStanding: return .individualDLPPW
        case .lbPPWStanding: return .lbPositionPPW
        case .individualLBPPWStanding: return .individualLBPPW
        case .dbPPWStanding: return .dbPositionPPW
        case .individualDBPPWStanding: return .individualDBPPW
        default: return nil
        }
    }
    private func mapCategoryToStatType(_ category: Category) -> DSDStatsService.StatType? {
        switch category {
        case .pointsFor: return .pointsFor
        case .maxPointsFor: return .maxPointsFor
        case .managementPercent: return .managementPercent
        case .teamAveragePPW: return .teamAveragePPW
        case .offensivePointsFor: return .offensivePointsFor
        case .maxOffensivePointsFor: return .maxOffensivePointsFor
        case .averageOffensivePPW: return .averageOffensivePPW
        case .offensiveManagementPercent: return .offensiveManagementPercent
        case .defensivePointsFor: return .defensivePointsFor
        case .maxDefensivePointsFor: return .maxDefensivePointsFor
        case .averageDefensivePPW: return .averageDefensivePPW
        case .defensiveManagementPercent: return .defensiveManagementPercent
        case .qbPositionPPW: return .qbPositionPPW
        case .rbPositionPPW: return .rbPositionPPW
        case .wrPositionPPW: return .wrPositionPPW
        case .tePositionPPW: return .tePositionPPW
        case .kickerPPW: return .kickerPPW
        case .dlPositionPPW: return .dlPositionPPW
        case .lbPositionPPW: return .lbPositionPPW
        case .dbPositionPPW: return .dbPositionPPW
        case .individualQBPPW: return .individualQBPPW
        case .individualRBPPW: return .individualRBPPW
        case .individualWRPPW: return .individualWRPPW
        case .individualTEPPW: return .individualTEPPW
        case .individualKickerPPW: return .individualKickerPPW
        case .individualDLPPW: return .individualDLPPW
        case .individualLBPPW: return .individualLBPPW
        case .individualDBPPW: return .individualDBPPW
        case .highestPointsInGameAllTime: return .highestPointsInGameAllTime
        case .highestPointsInGameSeason: return .highestPointsInGameSeason
        case .mostPointsAgainstAllTime: return .mostPointsAgainstAllTime
        case .mostPointsAgainstSeason: return .mostPointsAgainstSeason
        case .playoffBerthsAllTime: return .playoffBerthsAllTime
        case .playoffRecordAllTime: return .playoffRecordAllTime
        case .strengths: return .strengths
        case .weaknesses: return .weaknesses
        case .offensiveStrengths: return .offensiveStrengths
        case .offensiveWeaknesses: return .offensiveWeaknesses
        case .defensiveStrengths: return .defensiveStrengths
        case .defensiveWeaknesses: return .defensiveWeaknesses
        case .bestOffensivePositionPPW: return .bestOffensivePositionPPW
        case .worstOffensivePositionPointsAgainstPPW: return .worstOffensivePositionPointsAgainstPPW
        case .bestDefensivePositionPPW: return .bestDefensivePositionPPW
        case .worstDefensivePositionPointsAgainstPPW: return .worstDefensivePositionPointsAgainstPPW
        case .bestGameDescription: return .bestGameDescription
        case .biggestRival: return .biggestRival
        case .recordSeason, .recordAllTime, .winLossRecord: return .winLossRecord
        case .championships: return .championships
        default: return nil
        }
    }
    private func isStandingCategory(_ cat: Category) -> Bool {
        switch cat {
        case .teamStanding, .pointsForStanding, .averagePointsPerWeekStanding,
            .averagePointsScoredAgainstPerWeekStanding, .maxPointsForStanding,
            .managementPercentStanding, .offensiveStanding, .defensiveStanding,
            .pointsScoredAgainstStanding, .qbPPWStanding, .individualQBPPWStanding,
            .rbPPWStanding, .individualRBPPWStanding, .wrPPWStanding, .individualWRPPWStanding,
            .tePPWStanding, .individualTEPPWStanding, .kickerPPWStanding, .individualKickerPPWStanding,
            .dlPPWStanding, .individualDLPPWStanding, .lbPPWStanding, .individualLBPPWStanding,
            .dbPPWStanding, .individualDBPPWStanding: return true
        default: return false
        }
    }
    private func statDisplayValue(category: Category, team: TeamStanding) -> String {
        if isStandingCategory(category) { return standingRank(category: category, team: team) }
        if [.recordAllTime, .recordSeason, .winLossRecord].contains(category) {
            if isAllTimeMode, let agg = aggregatedAllTime {
                return "\(agg.totalWins)-\(agg.totalLosses)\(agg.totalTies > 0 ? "-\(agg.totalTies)" : "")"
            }
            return team.winLossRecord ?? "--"
        }
        if isAllTimeMode,
           let agg = aggregatedAllTime,
           let aggVal = aggregatedValue(category: category, aggregate: agg) {
            return aggVal
        }
        if category == .pointsScoredAgainst {
            return formatNumber(team.pointsScoredAgainst, decimals: 2)
        }
        if category == .averagePointsScoredAgainstPerWeekStanding {
            let avg = averagePointsAgainstPerWeek(team)
            return avg.isFinite ? String(format: "%.2f", avg) : "—"
        }
        if category == .pointsScoredAgainstStanding {
            return formatNumber(team.pointsScoredAgainst, decimals: 2)
        }
        if let statType = mapCategoryToStatType(category),
           let raw = DSDStatsService.shared.stat(for: team, type: statType) {
            return formatRawStat(raw, category: category)
        }
        return "—"
    }
    private func standingRank(category: Category, team: TeamStanding) -> String {
        guard !teams.isEmpty else { return "--" }
        if isAllTimeMode,
           let league = selectedLeague,
           let cache = league.allTimeOwnerStats {
            func numericValueAllTime(_ category: Category, for team: TeamStanding) -> Double {
                guard let agg = cache[team.ownerId] else { return 0 }
                switch category {
                case .pointsForStanding: return agg.totalPointsFor
                case .averagePointsPerWeekStanding: return agg.teamPPW
                case .maxPointsForStanding: return agg.totalMaxPointsFor
                case .managementPercentStanding: return agg.managementPercent
                case .offensiveManagementPercentStanding: return agg.offensiveManagementPercent
                case .defensiveManagementPercentStanding: return agg.defensiveManagementPercent
                case .offensiveStanding: return agg.totalOffensivePointsFor
                case .defensiveStanding: return agg.totalDefensivePointsFor
                case .qbPPWStanding: return agg.positionAvgPPW[PositionNormalizer.normalize("QB")] ?? 0
                case .rbPPWStanding: return agg.positionAvgPPW[PositionNormalizer.normalize("RB")] ?? 0
                case .wrPPWStanding: return agg.positionAvgPPW[PositionNormalizer.normalize("WR")] ?? 0
                case .tePPWStanding: return agg.positionAvgPPW[PositionNormalizer.normalize("TE")] ?? 0
                case .kickerPPWStanding: return agg.positionAvgPPW[PositionNormalizer.normalize("K")] ?? 0
                case .dlPPWStanding: return agg.positionAvgPPW[PositionNormalizer.normalize("DL")] ?? 0
                case .lbPPWStanding: return agg.positionAvgPPW[PositionNormalizer.normalize("LB")] ?? 0
                case .dbPPWStanding: return agg.positionAvgPPW[PositionNormalizer.normalize("DB")] ?? 0
                case .individualQBPPWStanding: return agg.individualPositionPPW[PositionNormalizer.normalize("QB")] ?? 0
                case .individualRBPPWStanding: return agg.individualPositionPPW[PositionNormalizer.normalize("RB")] ?? 0
                case .individualWRPPWStanding: return agg.individualPositionPPW[PositionNormalizer.normalize("WR")] ?? 0
                case .individualTEPPWStanding: return agg.individualPositionPPW[PositionNormalizer.normalize("TE")] ?? 0
                case .individualKickerPPWStanding: return agg.individualPositionPPW[PositionNormalizer.normalize("K")] ?? 0
                case .individualDLPPWStanding: return agg.individualPositionPPW[PositionNormalizer.normalize("DL")] ?? 0
                case .individualLBPPWStanding: return agg.individualPositionPPW[PositionNormalizer.normalize("LB")] ?? 0
                case .individualDBPPWStanding: return agg.individualPositionPPW[PositionNormalizer.normalize("DB")] ?? 0
                default: return 0
                }
            }
            if category == .teamStanding {
                let ordered = teams.sorted { a, b in
                    let aggA = cache[a.ownerId]
                    let aggB = cache[b.ownerId]
                    if (aggA?.championships ?? 0) != (aggB?.championships ?? 0) {
                        return (aggA?.championships ?? 0) > (aggB?.championships ?? 0)
                    }
                    if (aggA?.totalWins ?? 0) != (aggB?.totalWins ?? 0) {
                        return (aggA?.totalWins ?? 0) > (aggB?.totalWins ?? 0)
                    }
                    if (aggA?.totalLosses ?? 0) != (aggB?.totalLosses ?? 0) {
                        return (aggA?.totalLosses ?? 0) < (aggB?.totalLosses ?? 0)
                    }
                    if (aggA?.totalPointsFor ?? 0) != (aggB?.totalPointsFor ?? 0) {
                        return (aggA?.totalPointsFor ?? 0) > (aggB?.totalPointsFor ?? 0)
                    }
                    if (aggA?.managementPercent ?? 0) != (aggB?.managementPercent ?? 0) {
                        return (aggA?.managementPercent ?? 0) > (aggB?.managementPercent ?? 0)
                    }
                    let nameA = aggA?.latestDisplayName ?? a.name
                    let nameB = aggB?.latestDisplayName ?? b.name
                    return nameA < nameB
                }
                if let idx = ordered.firstIndex(where: { $0.id == team.id }) {
                    return ordinal(idx + 1)
                }
                return "--"
            }
            let asc = ascendingBetterStandings.contains(category)
            let sorted = teams.sorted {
                let av = numericValueAllTime(category, for: $0)
                let bv = numericValueAllTime(category, for: $1)
                return asc ? av < bv : av > bv
            }
            if let idx = sorted.firstIndex(where: { $0.id == team.id }) {
                return ordinal(idx + 1)
            }
            return "--"
        }
        if category == .teamStanding {
            let ordered = teams.sorted { $0.leagueStanding < $1.leagueStanding }
            if let idx = ordered.firstIndex(where: { $0.id == team.id }) { return ordinal(idx + 1) }
            return "--"
        }
        if category == .pointsScoredAgainstStanding {
            let ranked = teams.sorted {
                ($0.pointsScoredAgainst ?? .greatestFiniteMagnitude) <
                ($1.pointsScoredAgainst ?? .greatestFiniteMagnitude)
            }
            if let idx = ranked.firstIndex(where: { $0.id == team.id }) { return ordinal(idx + 1) }
            return "--"
        }
        if category == .averagePointsScoredAgainstPerWeekStanding {
            let ranked = teams.sorted {
                averagePointsAgainstPerWeek($0) < averagePointsAgainstPerWeek($1)
            }
            if let idx = ranked.firstIndex(where: { $0.id == team.id }) { return ordinal(idx + 1) }
            return "--"
        }
        guard let statType = underlyingStatForStanding(category) else { return "--" }
        let scored: [(TeamStanding, Double)] = teams.map {
            let val = (DSDStatsService.shared.stat(for: $0, type: statType) as? Double) ?? 0
            return ($0, val)
        }
        let asc = ascendingBetterStandings.contains(category)
        let ranked = scored.sorted { asc ? $0.1 < $1.1 : $0.1 > $1.1 }
        if let index = ranked.firstIndex(where: { $0.0.id == team.id }) { return ordinal(index + 1) }
        return "--"
    }
    private func formatRawStat(_ raw: Any, category: Category) -> String {
        switch raw {
        case let v as Double:
            if category == .managementPercent ||
                category == .offensiveManagementPercent ||
                category == .defensiveManagementPercent {
                return String(format: "%.1f%%", v)
            }
            return String(format: "%.2f", v)
        case let v as Int:
            return String(format: "%.2f", Double(v))
        case let v as String: return v
        case let arr as [String]:
            if arr.isEmpty { return "—" }
            return arr.count == 1 ? arr[0] : "\(arr.count)x"
        case let tuple as (position: String, avg: Double):
            return "\(tuple.position) \(String(format: "%.2f", tuple.avg))"
        default: return "—"
        }
    }
    private func aggregatedValue(category: Category, aggregate: AggregatedTeamStats) -> String? {
        switch category {
        case .pointsFor: return String(format: "%.2f", aggregate.totalPointsFor)
        case .maxPointsFor: return String(format: "%.2f", aggregate.totalMaxPointsFor)
        case .managementPercent: return String(format: "%.1f%%", aggregate.aggregatedManagementPercent)
        case .teamAveragePPW: return String(format: "%.2f", aggregate.avgTeamPPW)
        case .offensivePointsFor: return aggregate.offensivePointsFor.map { String(format: "%.2f", $0) }
        case .defensivePointsFor: return aggregate.defensivePointsFor.map { String(format: "%.2f", $0) }
        case .maxOffensivePointsFor:
            return aggregate.totalMaxOffensivePointsFor.map { String(format: "%.2f", $0) }
        case .maxDefensivePointsFor:
            return aggregate.totalMaxDefensivePointsFor.map { String(format: "%.2f", $0) }
        case .averageOffensivePPW: return aggregate.avgOffPPW.map { String(format: "%.2f", $0) }
        case .averageDefensivePPW: return aggregate.avgDefPPW.map { String(format: "%.2f", $0) }
        case .championships: return String(format: "%.0f", Double(aggregate.championships))
        case .recordAllTime:
            return "\(aggregate.totalWins)-\(aggregate.totalLosses)\(aggregate.totalTies > 0 ? "-\(aggregate.totalTies)" : "")"
        default: return nil
        }
    }
    private func initializeDefaultSelections() {
        if selectedStandings.isEmpty { selectedStandings = defaultStandings }
        if selectedTeamStats.isEmpty { selectedTeamStats = defaultTeam }
        if selectedOffensiveStats.isEmpty { selectedOffensiveStats = defaultOffensive }
        if selectedDefensiveStats.isEmpty { selectedDefensiveStats = defaultDefensive }
    }
    private func currentUsernameForKey() -> String { authViewModel.currentUsername ?? "anon" }
    private func loadCustomizationIfAvailable(force: Bool = false) {
        guard selectedLeague != nil else { return }
        if customizationLoaded && !force { return }
        if let loaded = DashboardCustomizationStore.shared.load(
            for: currentUsernameForKey(),
            leagueId: selectedLeague?.id
        ) {
            if !loaded.standings.isEmpty { selectedStandings = loaded.standings }
            if !loaded.team.isEmpty { selectedTeamStats = loaded.team }
            if !loaded.offensive.isEmpty { selectedOffensiveStats = loaded.offensive }
            if !loaded.defensive.isEmpty { selectedDefensiveStats = loaded.defensive }
        }
        customizationLoaded = true
    }
    private func persistCustomization() {
        guard customizationLoaded else { return }
        let sets = CustomizationSets(
            standings: selectedStandings,
            team: selectedTeamStats,
            offensive: selectedOffensiveStats,
            defensive: selectedDefensiveStats
        )
        DashboardCustomizationStore.shared.save(
            sets: sets,
            for: currentUsernameForKey(),
            leagueId: selectedLeague?.id
        )
    }
    private func enforceIntegrityAndPersist() {
        if selectedStandings.isEmpty { selectedStandings = defaultStandings }
        if selectedTeamStats.isEmpty { selectedTeamStats = defaultTeam }
        if selectedOffensiveStats.isEmpty { selectedOffensiveStats = defaultOffensive }
        if selectedDefensiveStats.isEmpty { selectedDefensiveStats = defaultDefensive }
        persistCustomization()
    }
    private func syncInitialSelections(replaceTeam: Bool) {
        guard let league = selectedLeague else { return }
        if appSelection.selectedSeason.isEmpty { appSelection.selectedSeason = league.seasons.sorted { $0.id < $1.id }.last?.id ?? "All Time" }
        if let userTeam = authViewModel.userTeam,
           let latestSeason = league.seasons.sorted(by: { $0.id < $1.id }).last,
           let userTeamMatch = latestSeason.teams.first(where: { $0.name == userTeam }) {
            appSelection.selectedTeamId = userTeamMatch.id
        } else if replaceTeam, appSelection.selectedTeamId == nil {
            let firstTeam = teams.first
            appSelection.selectedTeamId = firstTeam?.id
        }
    }
    private func handleSeasonChange() {
        guard selectedLeague != nil else { return }
        if let tid = appSelection.selectedTeamId {
            if isAllTimeMode {
                if let match = teams.first(where: { $0.id == tid }) {
                    appSelection.selectedTeamId = match.id
                    return
                }
            } else if let match = teams.first(where: { $0.id == tid }) {
                appSelection.selectedTeamId = match.id
                return
            }
        }
        if !suppressAutoUserTeam, let ut = authViewModel.userTeam {
            appSelection.selectedTeamId = teams.first { $0.name == ut }?.id ?? teams.first?.id
        } else if appSelection.selectedTeamId == nil {
            appSelection.selectedTeamId = teams.first?.id
        }
    }
    private func fallbackFirstTeamName() -> String? {
        selectedLeague?.seasons.sorted { $0.id < $1.id }.last?.teams.first?.name
    }
    private func loadSavedLeagues() {
        guard let username = authViewModel.currentUsername else { return }
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let leaguesDir = appSupport.appendingPathComponent("SleeperLeagues/\(username)", isDirectory: true)
        let leaguesFile = leaguesDir.appendingPathComponent("leagues.json")
        do {
            if fm.fileExists(atPath: leaguesFile.path) {
                let data = try Data(contentsOf: leaguesFile)
                let loadedLeagues = try JSONDecoder().decode([LeagueData].self, from: data)
                appSelection.leagues = loadedLeagues.sorted { $0.name < $1.name }
            }
        } catch {
            print("Error loading leagues: \(error)")
        }
    }

    // Measures a string's width using UIKit UIFont. Returns ceil(width).
    // fontName is optional — if the custom font isn't available, falls back to system font.
    private func measuredTextWidth(_ text: String, fontSize: CGFloat = 16, fontName: String? = nil) -> CGFloat {
        let uiFont: UIFont
        if let name = fontName, let f = UIFont(name: name, size: fontSize) {
            uiFont = f
        } else {
            uiFont = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        }
        let attributes = [NSAttributedString.Key.font: uiFont]
        let size = (text as NSString).size(withAttributes: attributes)
        return ceil(size.width)
    }
}

private func formatNumber(_ value: Double?, decimals: Int = 2) -> String {
    guard let v = value else { return "—" }
    return String(format: "%.\(decimals)f", v)
}
private func ordinal(_ n: Int) -> String { "\(n)\(ordinalSuffix(n))" }
private func ordinalSuffix(_ n: Int) -> String {
    let mod10 = n % 10, mod100 = n % 100
    if (11...13).contains(mod100) { return "th" }
    switch mod10 {
    case 1: return "st"
    case 2: return "nd"
    case 3: return "rd"
    default: return "th"
    }
}
private func averagePointsAgainstPerWeek(_ team: TeamStanding) -> Double {
    guard let pa = team.pointsScoredAgainst, team.teamPointsPerWeek > 0 else {
        return .greatestFiniteMagnitude
    }
    let approxWeeks = team.pointsFor / max(0.01, team.teamPointsPerWeek)
    return pa / max(1, approxWeeks)
}
private func computedAverageSeasonStanding(ownerId: String, in league: LeagueData) -> Double {
    let standings = league.seasons.compactMap {
        $0.teams.first(where: { $0.ownerId == ownerId })?.leagueStanding
    }
    guard !standings.isEmpty else { return Double.greatestFiniteMagnitude }
    return Double(standings.reduce(0,+)) / Double(standings.count)
}
private func allTimeStandingSort(a: TeamStanding, b: TeamStanding, cache: [String: AggregatedOwnerStats]) -> Bool {
    let aggA = cache[a.ownerId]
    let aggB = cache[b.ownerId]
    if (aggA?.championships ?? 0) != (aggB?.championships ?? 0) {
        return (aggA?.championships ?? 0) > (aggB?.championships ?? 0)
    }
    if (aggA?.totalWins ?? 0) != (aggB?.totalWins ?? 0) {
        return (aggA?.totalWins ?? 0) > (aggB?.totalWins ?? 0)
    }
    if (aggA?.totalLosses ?? 0) != (aggB?.totalLosses ?? 0) {
        return (aggA?.totalLosses ?? 0) < (aggB?.totalLosses ?? 0)
    }
    if (aggA?.totalPointsFor ?? 0) != (aggB?.totalPointsFor ?? 0) {
        return (aggA?.totalPointsFor ?? 0) > (aggB?.totalPointsFor ?? 0)
    }
    if (aggA?.managementPercent ?? 0) != (aggB?.managementPercent ?? 0) {
        return (aggA?.managementPercent ?? 0) > (aggB?.managementPercent ?? 0)
    }
    let nameA = aggA?.latestDisplayName ?? a.name
    let nameB = aggB?.latestDisplayName ?? b.name
    return nameA < nameB
}

struct FlipTiltModifier: ViewModifier {
    let progress: Double   // 0.0 = front, 1.0 = back
    let enabled: Bool
    let glow: Color
    let reducedMotion: Bool

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(enabled ? (180 * progress) : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.9 / 900
            )
            .shadow(color: glow.opacity(enabled ? 0.21 : 0.0), radius: enabled ? 12 : 0, y: enabled ? 8 : 0)
            .animation(reducedMotion ? nil : .easeInOut(duration: 0.25), value: progress)
    }
}

struct DSDDashboard_Previews: PreviewProvider {
    static var previews: some View {
        DSDDashboard(selectedTab: .constant(.dashboard))
            .environmentObject(AuthViewModel())
            .environmentObject(AppSelection())
    }
}
