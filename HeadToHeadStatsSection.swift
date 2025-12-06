//
// HeadToHeadStatsService.swift
// DynastyStatDrop
//
// New service to manage per-league per-team matchup history.
// - Builds and stores matchup histories inside LeagueData.matchupHistories
// - Provides helpers to retrieve sorted match lists and compute aggregates
//
// Notes:
// - Idempotent backfill from season.matchupsByWeek
// - Stores perspective-specific H2HMatchDetail under teamId -> opponentId
// - Uses ManagementCalculator helpers where available to provide mgmt% values
//

import Foundation
import SwiftUI

@MainActor
final class HeadToHeadStatsService {

    private init() {}

    // MARK: - Public API

    /// Rebuilds/Backfills the league.matchupHistories mapping from existing season matchups.
    /// - Parameters:
    ///   - league: inout LeagueData to update with computed matchupHistories
    ///   - leagueManager: to help compute mgmt% via ManagementCalculator and access player cache if needed
    /// - Behavior: idempotent and best-effort. Existing entries will be replaced with the rebuilt mapping.
    static func rebuildMatchupHistories(for league: inout LeagueData, leagueManager: SleeperLeagueManager) {
        var map: [String: [String: [H2HMatchDetail]]] = league.matchupHistories ?? [:]

        // Helper to append a detail in perspective of teamId against opponentId
        func appendDetail(teamId: String, opponentId: String, detail: H2HMatchDetail) {
            var inner = map[teamId] ?? [:]
            var arr = inner[opponentId] ?? []
            arr.append(detail)
            // Keep descending chronological order - we'll sort later globally
            inner[opponentId] = arr
            map[teamId] = inner
        }

        // Iterate seasons/weeks
        for season in league.seasons {
            guard let byWeek = season.matchupsByWeek else { continue }
            for (week, entries) in byWeek {
                // Group entries by matchup id (older data may lack matchup_id, so group by pairing heuristics)
                let groups = Dictionary(grouping: entries) { $0.matchup_id ?? -1 }
                for (_, groupEntries) in groups {
                    // Only process pairs (or multi-team matchups) with at least two entries
                    if groupEntries.count < 2 { continue }

                    // Create pairwise details among entries within the same matchup group
                    for i in 0..<groupEntries.count {
                        for j in (i+1)..<groupEntries.count {
                            let a = groupEntries[i]
                            let b = groupEntries[j]

                            // Build TeamStanding lookup (season-level first, fallback to league.teams)
                            let aTeam = season.teams.first(where: { $0.id == String(a.roster_id) }) ?? league.teams.first(where: { $0.id == String(a.roster_id) })
                            let bTeam = season.teams.first(where: { $0.id == String(b.roster_id) }) ?? league.teams.first(where: { $0.id == String(b.roster_id) })

                            // Points: prefer entry.points, else sum players_points, else 0
                            let aPoints = a.points ?? (a.players_points?.values.reduce(0.0, +) ?? 0.0)
                            let bPoints = b.points ?? (b.players_points?.values.reduce(0.0, +) ?? 0.0)

                            // Compute optimal/max totals & mgmt% using ManagementCalculator where possible
                            // We attempt to compute mgmt% via computeManagementPercentForEntry which is canonical.
                            let aMgmtPct = ManagementCalculator.computeManagementPercentForEntry(entry: a, seasonTeam: aTeam, week: week, league: league, leagueManager: leagueManager) ?? 0.0
                            let bMgmtPct = ManagementCalculator.computeManagementPercentForEntry(entry: b, seasonTeam: bTeam, week: week, league: league, leagueManager: leagueManager) ?? 0.0

                            // Compute max totals via computeManagementForWeek (fallback)
                            let aTotals = aTeam.map { ManagementCalculator.computeManagementForWeek(team: $0, week: week, league: league, leagueManager: leagueManager) }
                            let bTotals = bTeam.map { ManagementCalculator.computeManagementForWeek(team: $0, week: week, league: league, leagueManager: leagueManager) }

                            let aMax = aTotals?.1 ?? 0.0
                            let bMax = bTotals?.1 ?? 0.0

                            // If computeManagementPercentForEntry returned 0.0 (meaning it couldn't compute),
                            // but we have max > 0, recalc aMgmtPct from actual / max.
                            let aMgmtPctFinal: Double = (aMgmtPct <= 0.0 && aMax > 0.0) ? ((aPoints / aMax) * 100.0) : aMgmtPct
                            let bMgmtPctFinal: Double = (bMgmtPct <= 0.0 && bMax > 0.0) ? ((bPoints / bMax) * 100.0) : bMgmtPct

                            // Determine results from perspective of each team
                            let resA: String = (aPoints > bPoints) ? "W" : (aPoints < bPoints) ? "L" : "T"
                            let resB: String = (bPoints > aPoints) ? "W" : (bPoints < aPoints) ? "L" : "T"

                            let matchupId = a.matchup_id ?? b.matchup_id ?? -1

                            // Build H2HMatchDetail perspective for A vs B
                            let detailA = H2HMatchDetail(
                                seasonId: season.id,
                                week: week,
                                matchupId: matchupId,
                                userRosterId: a.roster_id,
                                oppRosterId: b.roster_id,
                                userPoints: aPoints,
                                oppPoints: bPoints,
                                userMax: aMax,
                                oppMax: bMax,
                                userMgmtPct: aMgmtPctFinal,
                                oppMgmtPct: bMgmtPctFinal,
                                result: resA
                            )

                            // Build perspective for B vs A (swap sides)
                            let detailB = H2HMatchDetail(
                                seasonId: season.id,
                                week: week,
                                matchupId: matchupId,
                                userRosterId: b.roster_id,
                                oppRosterId: a.roster_id,
                                userPoints: bPoints,
                                oppPoints: aPoints,
                                userMax: bMax,
                                oppMax: aMax,
                                userMgmtPct: bMgmtPctFinal,
                                oppMgmtPct: aMgmtPctFinal,
                                result: resB
                            )

                            // Append to map under each team's id keyed by opponent id (string)
                            appendDetail(teamId: String(a.roster_id), opponentId: String(b.roster_id), detail: detailA)
                            appendDetail(teamId: String(b.roster_id), opponentId: String(a.roster_id), detail: detailB)
                        }
                    }
                }
            }
        }

        // Sort each list descending by (seasonId, week, matchupId) so newest first
        for (teamId, opponents) in map {
            var outOpps: [String: [H2HMatchDetail]] = [:]
            for (oppId, arr) in opponents {
                let sorted = arr.sorted { lhs, rhs in
                    if lhs.seasonId != rhs.seasonId { return lhs.seasonId > rhs.seasonId }
                    if lhs.week != rhs.week { return lhs.week > rhs.week }
                    return lhs.matchupId > rhs.matchupId
                }
                outOpps[oppId] = sorted
            }
            map[teamId] = outOpps
        }

        league.matchupHistories = map
    }

    /// Returns the stored list of matches (descending order) for teamId vs opponentId if present.
    /// If no explicit stored history exists, returns an empty array.
    static func getMatchesFor(teamId: String, opponentId: String, league: LeagueData) -> [H2HMatchDetail] {
        return league.matchupHistories?[teamId]?[opponentId] ?? []
    }

    /// Returns aggregated H2H summary (record, avgMgmtFor, avgPF, avgMgmtAgainst, avgPA) computed from the provided details.
    static func computeAggregates(from matches: [H2HMatchDetail]) -> (record: String, avgMgmtFor: Double, avgPF: Double, avgMgmtAgainst: Double, avgPA: Double) {
        guard !matches.isEmpty else { return ("0-0", 0.0, 0.0, 0.0, 0.0) }

        var wins = 0, losses = 0, ties = 0
        var sumMgmtFor = 0.0, countMgmtFor = 0
        var sumMgmtAgainst = 0.0, countMgmtAgainst = 0
        var sumPF = 0.0, sumPA = 0.0

        for m in matches {
            switch m.result {
            case "W": wins += 1
            case "L": losses += 1
            default: ties += 1
            }
            sumPF += m.userPoints
            sumPA += m.oppPoints

            if m.userMgmtPct > 0.0 {
                sumMgmtFor += m.userMgmtPct
                countMgmtFor += 1
            }
            if m.oppMgmtPct > 0.0 {
                sumMgmtAgainst += m.oppMgmtPct
                countMgmtAgainst += 1
            }
        }

        let games = matches.count
        let avgPF = games > 0 ? sumPF / Double(games) : 0.0
        let avgPA = games > 0 ? sumPA / Double(games) : 0.0
        let avgMgmtFor = countMgmtFor > 0 ? sumMgmtFor / Double(countMgmtFor) : 0.0
        let avgMgmtAgainst = countMgmtAgainst > 0 ? sumMgmtAgainst / Double(countMgmtAgainst) : 0.0
        let record = "\(wins)-\(losses)\(ties > 0 ? "-\(ties)" : "")"

        return (record, avgMgmtFor, avgPF, avgMgmtAgainst, avgPA)
    }

    /// Returns aggregates computed for the last N matches (new "Past N Matchups", e.g. last 3)
    static func computeLastNAggregates(from matches: [H2HMatchDetail], lastN: Int) -> (record: String, avgMgmtFor: Double, avgPF: Double, avgMgmtAgainst: Double, avgPA: Double) {
        guard !matches.isEmpty else { return ("0-0", 0.0, 0.0, 0.0, 0.0) }
        let slice = Array(matches.prefix(lastN))
        return computeAggregates(from: slice)
    }

    // Convenience: returns both full aggregates and lastN aggregates
    static func summaryAndLastN(from matches: [H2HMatchDetail], lastN: Int = 3) -> (full: (record: String, avgMgmtFor: Double, avgPF: Double, avgMgmtAgainst: Double, avgPA: Double), lastN: (record: String, avgMgmtFor: Double, avgPF: Double, avgMgmtAgainst: Double, avgPA: Double)) {
        let full = computeAggregates(from: matches)
        let last = computeLastNAggregates(from: matches, lastN: lastN)
        return (full, last)
    }

    // MARK: - Utilities

    /// Helper: returns the most recent matchup snapshots between two roster ids (descending order).
    /// Useful for building the Match History list in the UI.
    static func recentMatchesBetween(teamId: String, opponentId: String, league: LeagueData, limit: Int? = nil) -> [H2HMatchDetail] {
        let all = getMatchesFor(teamId: teamId, opponentId: opponentId, league: league)
        if let lim = limit { return Array(all.prefix(lim)) }
        return all
    }

    /// For incremental flows: merge a new H2HMatchDetail into the league.matchupHistories mapping.
    /// Idempotent if the exact same detail (equal values) already exists.
    static func mergeMatchDetail(_ detail: H2HMatchDetail, league: inout LeagueData) {
        var map = league.matchupHistories ?? [:]
        let teamId = String(detail.userRosterId)
        let oppId = String(detail.oppRosterId)
        var inner = map[teamId] ?? [:]
        var arr = inner[oppId] ?? []

        // Avoid duplicates (exact match)
        if !arr.contains(where: { $0 == detail }) {
            arr.append(detail)
            // Keep sorted newest-first
            arr.sort { lhs, rhs in
                if lhs.seasonId != rhs.seasonId { return lhs.seasonId > rhs.seasonId }
                if lhs.week != rhs.week { return lhs.week > rhs.week }
                return lhs.matchupId > rhs.matchupId
            }
            inner[oppId] = arr
            map[teamId] = inner
            league.matchupHistories = map
        }
    }
}

// -------------------------------------------------------
// Lightweight SwiftUI view shim to satisfy MatchupView usage
// Minimal, non-invasive: shows basic aggregates from HeadToHeadStatsService.
// The view accepts MatchupView.TeamDisplay for user/opp to match the existing invocation in MatchupView.
// -------------------------------------------------------

struct HeadToHeadStatsSection: View {
    let user: MatchupView.TeamDisplay
    let opp: MatchupView.TeamDisplay
    let league: LeagueData
    let currentSeasonId: String
    let currentWeekNumber: Int

    var body: some View {
        // Query stored matches (descending newest-first)
        let matches = HeadToHeadStatsService.recentMatchesBetween(teamId: user.id, opponentId: opp.id, league: league)
        let aggregates = HeadToHeadStatsService.computeAggregates(from: matches)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Record:")
                    .foregroundColor(.orange)
                    .font(.headline)
                Text(aggregates.record)
                    .foregroundColor(.white)
                    .font(.subheadline)
                Spacer()
                Text("Matches: \(matches.count)")
                    .foregroundColor(.white.opacity(0.9))
                    .font(.caption)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Avg PF")
                        .foregroundColor(.orange)
                        .font(.caption.bold())
                    Text(String(format: "%.1f", aggregates.avgPF))
                        .foregroundColor(.white)
                        .font(.subheadline)
                }
                VStack(alignment: .leading) {
                    Text("Avg PA")
                        .foregroundColor(.orange)
                        .font(.caption.bold())
                    Text(String(format: "%.1f", aggregates.avgPA))
                        .foregroundColor(.white)
                        .font(.subheadline)
                }
                VStack(alignment: .leading) {
                    Text("Avg Mgmt For")
                        .foregroundColor(.orange)
                        .font(.caption.bold())
                    Text(String(format: "%.1f%%", aggregates.avgMgmtFor))
                        .foregroundColor(.white)
                        .font(.subheadline)
                }
                Spacer()
            }
            if matches.isEmpty {
                Text("No head-to-head history stored for these teams.")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.caption)
                    .padding(.top, 6)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.02))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }
}
