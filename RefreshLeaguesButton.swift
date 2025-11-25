//
//  RefreshLeaguesButton.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 8/27/25.
//


//
//  RefreshLeaguesButton.swift
//  DynastyStatDrop
//
//  Optional manual force-refresh control.
//  Safe: only triggers latest-season refresh; preserves M% logic.
//

import SwiftUI

struct RefreshLeaguesButton: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var leagueManager: SleeperLeagueManager
    @EnvironmentObject var appSelection: AppSelection

    var body: some View {
        Button {
            Task {
                let user = authViewModel.currentUsername
                await leagueManager.forceRefreshAllLeagues(username: user)
                await MainActor.run {
                    appSelection.updateLeagues(leagueManager.leagues, username: user)
                }
            }
        } label: {
            if leagueManager.isRefreshing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
            } else {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
            }
        }
        .disabled(leagueManager.isRefreshing)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.4))
        )
        .foregroundColor(.orange)
        .accessibilityLabel("Refresh Leagues")
    }
}