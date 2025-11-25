//
//  MainTabView.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 7/12/25.
//  Diagnostics feature removed.
//  FIX: Use the root-injected SleeperLeagueManager via @EnvironmentObject instead of
//       creating & re‑injecting a second local instance (which caused the compile error).
//

import SwiftUI

struct MainTabView: View {
    // Use the instance injected by DynastyStatDropApp
    @EnvironmentObject var leagueManager: SleeperLeagueManager
    @State private var selectedTab: Tab

    //
    init(selectedTab: Tab = .dashboard) {
        _selectedTab = State(initialValue: selectedTab)
    }
    
    var body: some View {
        // No extra .environmentObject(...) here; the app root already injected it.
        content
            .edgesIgnoringSafeArea(.all)
    }
    
    @ViewBuilder
    var content: some View {
        switch selectedTab {
        case .dashboard:
            NavigationStack {
                VStack(spacing: 0) {
                    DSDDashboard(selectedTab: $selectedTab)
                    CustomNavigationBar(selectedTab: $selectedTab)
                }
            }
        case .deck:
            NavigationStack {
                VStack(spacing: 0) {
                    TheDeck(selectedTab: $selectedTab)
                    CustomNavigationBar(selectedTab: $selectedTab)
                }
            }
        case .myTeam:
            NavigationStack {
                VStack(spacing: 0) {
                    // MyTeamView now acquires leagueManager via @EnvironmentObject
                    MyTeamView(selectedTab: $selectedTab)
                    CustomNavigationBar(selectedTab: $selectedTab)
                }
            }
        case .myLeague:
            NavigationStack {
                VStack(spacing: 0) {
                    MyLeagueView(selectedTab: $selectedTab)
                    CustomNavigationBar(selectedTab: $selectedTab)
                }
            }
        case .matchup:
            NavigationStack {
                VStack(spacing: 0) {
                    MatchupView(selectedTab: $selectedTab)
                    CustomNavigationBar(selectedTab: $selectedTab)
                }
            }
        }
    }
}

struct CustomNavigationBar: View {
    @Binding var selectedTab: Tab
    
    // Define the custom order: TheDeck (deck), MyTeam (myTeam), DSDDash (dashboard), MyLeague (myLeague), Matchup (matchup)
    private let orderedTabs: [Tab] = [.deck, .myTeam, .dashboard, .myLeague, .matchup]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(orderedTabs, id: \.self) { tab in
                navBarButton(tab: tab)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color.black.opacity(0.5).ignoresSafeArea(edges: .all))
    }

    private func navBarButton(tab: Tab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 15) {
                Image(tab.customImage)
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    // Make the center DSDDash icon slightly bigger
                    .frame(width: tab == .dashboard ? 60 : 50, height: tab == .dashboard ? 60 : 50)
                Text(tab.label)
                    .font(.caption2)
                    .foregroundColor(selectedTab == tab ? .orange : .white)
            }
        }
    }
}
