//
//  LeagueSeasonTeamPicker.swift
//  DynastyStatDrop
//
//  Refactored: Centralized Season/Team/League Selection
//  - All local selection state removed.
//  - Always use AppSelection's published properties for league, season, and team selection.
//  - All pickers and displays read/write to appSelection properties directly.
//  - Appearance/features preserved; only selection logic source changed.
//

import SwiftUI

struct LeagueSeasonTeamPicker: View {
    @EnvironmentObject var appSelection: AppSelection

    // Configuration
    var showLeague: Bool = true
    var showSeason: Bool = true
    var showTeam: Bool = true
    var seasonLabel: String = "Season"
    var teamLabel: String = "Team"
    var leagueLabel: String = "League"
    var maxMenuWidth: CGFloat = 180

    private var league: LeagueData? { appSelection.selectedLeague }

    private var seasonIds: [String] {
        guard let league else { return ["All Time"] }
        let ids = league.seasons.map { $0.id }.sorted(by: >)
        return ["All Time"] + ids
    }

    private var seasonTeams: [TeamStanding] {
        guard let league else { return [] }
        if appSelection.selectedSeason == "All Time" {
            return league.seasons.sorted { $0.id < $1.id }.last?.teams ?? league.teams
        }
        return league.seasons.first(where: { $0.id == appSelection.selectedSeason })?.teams
            ?? league.seasons.sorted { $0.id < $1.id }.last?.teams
            ?? league.teams
    }

    var body: some View {
        HStack(spacing: 12) {
            if showLeague {
                Menu {
                    ForEach(appSelection.leagues, id: \.id) { lg in
                        Button(lg.name) { appSelection.selectedLeagueId = lg.id }
                    }
                } label: {
                    pill(appSelection.selectedLeague?.name ?? leagueLabel)
                }
                .frame(maxWidth: maxMenuWidth)
            }
            if showSeason {
                Menu {
                    ForEach(seasonIds, id: \.self) { sid in
                        Button(sid) { appSelection.selectedSeason = sid }
                    }
                } label: {
                    pill(appSelection.selectedSeason.isEmpty ? seasonLabel : appSelection.selectedSeason)
                }
                .frame(maxWidth: maxMenuWidth)
            }
            if showTeam {
                Menu {
                    ForEach(seasonTeams, id: \.id) { tm in
                        Button(tm.name) { appSelection.selectedTeamId = tm.id }
                    }
                } label: {
                    pill(seasonTeams.first(where: { $0.id == appSelection.selectedTeamId })?.name
                         ?? teamLabel)
                }
                .frame(maxWidth: maxMenuWidth)
            }
        }
        .onChange(of: appSelection.selectedLeagueId) { _ in
            normalizeAfterLeagueChange()
        }
        .onChange(of: appSelection.selectedSeason) { _ in
            normalizeAfterSeasonChange()
        }
        .onAppear {
            normalizeAfterLeagueChange()
            normalizeAfterSeasonChange()
        }
    }

    // MARK: - Normalization

    private func normalizeAfterLeagueChange() {
        guard let lg = appSelection.selectedLeague else {
            appSelection.selectedSeason = "All Time"
            appSelection.selectedTeamId = nil
            return
        }
        // Ensure season valid
        if appSelection.selectedSeason != "All Time" &&
            !lg.seasons.contains(where: { $0.id == appSelection.selectedSeason }) {
            appSelection.selectedSeason = lg.seasons.sorted { $0.id < $1.id }.last?.id ?? "All Time"
        }
        normalizeAfterSeasonChange()
    }

    private func normalizeAfterSeasonChange() {
        guard let lg = appSelection.selectedLeague else { return }
        let teams = seasonTeams
        if teams.isEmpty {
            appSelection.selectedTeamId = nil
            return
        }
        if let current = appSelection.selectedTeamId,
           teams.contains(where: { $0.id == current }) {
            return
        }
        appSelection.selectedTeamId = teams.first?.id
    }

    // MARK: - UI Helpers

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.orange)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black)
                    .shadow(color: .blue.opacity(0.6), radius: 8, y: 2)
            )
            .accessibilityLabel(text)
    }
}
