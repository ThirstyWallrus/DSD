//
//  HeadToHeadStatsSection.swift
//  DynastyStatDrop
//
//  Simplified rewrite: shows full historical head-to-head history between two teams
//  and a compact Stat History comparison (record, avg PPG, past-3 PPG, avg mgmt%, past-3 mgmt%).
//
//  Notes:
//  - Scans all seasons in the provided LeagueData and finds weeks where both roster entries
//    (for the owners involved) appear in the same week. Best-effort owner -> roster mapping
//    is used per season so franchise owner changes across seasons are supported.
//  - Uses ManagementCalculator.computeManagementPercentForEntry when possible to obtain mgmt%
//    for a matchup entry. This preserves canonical mgmt% behavior used elsewhere in the app.
//  - The view accepts the same signature as before to preserve caller compatibility.
//
import SwiftUI
import Foundation

private struct H2HMatchSimple: Identifiable {
    let id = UUID()
    let seasonId: String
    let week: Int
    let matchupId: Int?
    let userRosterId: Int
    let oppRosterId: Int
    let userPoints: Double
    let oppPoints: Double
    let userMgmtPct: Double?
    let oppMgmtPct: Double?
    let result: String // "W","L","T" from user's perspective
}

struct HeadToHeadStatsSection: View {
    // Backwards-compatible inputs used by MatchupView
    let user: TeamStanding?
    let opp: TeamStanding?
    let league: LeagueData

    // Keep optional snapshot params for compatibility but they are ignored by this simplified view
    let userSnapshot: Any? = nil
    let oppSnapshot: Any? = nil
    let matchSnapshots: [Any]? = nil
    let currentSeasonId: String? = nil
    let currentWeekNumber: Int? = nil

    @EnvironmentObject private var leagueManager: SleeperLeagueManager

    // MARK: - Computation

    private func seasonRosterIdForOwner(season: SeasonData, ownerId: String) -> Int? {
        // Return the roster ID for this owner in this season if present
        if let team = season.teams.first(where: { $0.ownerId == ownerId }) {
            return Int(team.id)
        }
        return nil
    }

    private func pointsForEntry(_ entry: MatchupEntry) -> Double {
        if let p = entry.points { return p }
        if let players = entry.players_points, !players.isEmpty {
            return players.values.reduce(0.0, +)
        }
        return 0.0
    }

    @MainActor
    private func collectAllMatches() -> [H2HMatchSimple] {
        guard let userOwner = user?.ownerId, let oppOwner = opp?.ownerId else { return [] }

        var matches: [H2HMatchSimple] = []

        // Walk every season in the league
        for season in league.seasons {
            guard let matchupsByWeek = season.matchupsByWeek else { continue }

            // Determine roster ids for this season (owner -> rosterId mapping)
            let userRidSeason = seasonRosterIdForOwner(season: season, ownerId: userOwner) ?? Int(user?.id ?? "") ?? nil
            let oppRidSeason = seasonRosterIdForOwner(season: season, ownerId: oppOwner) ?? Int(opp?.id ?? "") ?? nil

            // If we couldn't map either roster id for this season, skip it.
            guard let uRid = userRidSeason, let oRid = oppRidSeason else { continue }

            for (week, entries) in matchupsByWeek {
                // Find entries for both roster ids in this week
                guard let uEntry = entries.first(where: { $0.roster_id == uRid }),
                      let oEntry = entries.first(where: { $0.roster_id == oRid }) else {
                    continue
                }

                let uPts = pointsForEntry(uEntry)
                let oPts = pointsForEntry(oEntry)

                // Attempt to compute mgmt% for each entry (best-effort)
                let uMgmt = ManagementCalculator.computeManagementPercentForEntry(entry: uEntry, seasonTeam: season.teams.first(where: { Int($0.id) == uRid }), week: week, league: league, leagueManager: leagueManager)
                let oMgmt = ManagementCalculator.computeManagementPercentForEntry(entry: oEntry, seasonTeam: season.teams.first(where: { Int($0.id) == oRid }), week: week, league: league, leagueManager: leagueManager)

                let result: String = {
                    if uPts > oPts { return "W" }
                    if uPts < oPts { return "L" }
                    return "T"
                }()

                let m = H2HMatchSimple(
                    seasonId: season.id,
                    week: week,
                    matchupId: uEntry.matchup_id ?? oEntry.matchup_id,
                    userRosterId: uRid,
                    oppRosterId: oRid,
                    userPoints: uPts,
                    oppPoints: oPts,
                    userMgmtPct: uMgmt,
                    oppMgmtPct: oMgmt,
                    result: result
                )
                matches.append(m)
            }
        }

        // Sort most recent first: prefer season numeric value if possible, then week descending
        let sorted = matches.sorted { a, b in
            let aSeason = Int(a.seasonId) ?? Int.min
            let bSeason = Int(b.seasonId) ?? Int.min
            if aSeason != bSeason { return aSeason > bSeason }
            if a.week != b.week { return a.week > b.week }
            // tie-breaker: matchupId if present
            let ai = a.matchupId ?? Int.min
            let bi = b.matchupId ?? Int.min
            return ai > bi
        }
        return sorted
    }

    // MARK: - Stat aggregations (from collected matches)
    private func computeAggregates(from matches: [H2HMatchSimple]) -> (user: [String: String], opp: [String: String]) {
        // Defaults
        var userStats: [String: String] = [
            "record": "0-0",
            "avgPPG": "0.00",
            "past3PPG": "0.00",
            "avgMgmt": "—",
            "past3Mgmt": "—"
        ]
        var oppStats = userStats

        guard !matches.isEmpty else { return (userStats, oppStats) }

        // Record
        var wins = 0, losses = 0, ties = 0
        var sumUserPts = 0.0, sumOppPts = 0.0
        var sumUserMgmt = 0.0, cntUserMgmt = 0
        var sumOppMgmt = 0.0, cntOppMgmt = 0

        for m in matches {
            if m.result == "W" { wins += 1 }
            else if m.result == "L" { losses += 1 }
            else { ties += 1 }
            sumUserPts += m.userPoints
            sumOppPts += m.oppPoints
            if let mg = m.userMgmtPct { sumUserMgmt += mg; cntUserMgmt += 1 }
            if let mg = m.oppMgmtPct { sumOppMgmt += mg; cntOppMgmt += 1 }
        }

        userStats["record"] = "\(wins)-\(losses)\(ties > 0 ? "-\(ties)" : "")"
        oppStats["record"] = "\(losses)-\(wins)\(ties > 0 ? "-\(ties)" : "")"

        let games = Double(matches.count)
        userStats["avgPPG"] = String(format: "%.2f", sumUserPts / games)
        oppStats["avgPPG"] = String(format: "%.2f", sumOppPts / games)

        // Past 3 (most recent up to 3)
        let recent = Array(matches.prefix(3))
        let recentUserSum = recent.reduce(0.0) { $0 + $1.userPoints }
        let recentOppSum = recent.reduce(0.0) { $0 + $1.oppPoints }
        let recentCount = Double(recent.count)
        userStats["past3PPG"] = recentCount > 0 ? String(format: "%.2f", recentUserSum / recentCount) : "0.00"
        oppStats["past3PPG"] = recentCount > 0 ? String(format: "%.2f", recentOppSum / recentCount) : "0.00"

        // Avg mgmt% (only where mgmt% exists)
        if cntUserMgmt > 0 {
            userStats["avgMgmt"] = String(format: "%.2f%%", sumUserMgmt / Double(cntUserMgmt))
        } else { userStats["avgMgmt"] = "—" }

        if cntOppMgmt > 0 {
            oppStats["avgMgmt"] = String(format: "%.2f%%", sumOppMgmt / Double(cntOppMgmt))
        } else { oppStats["avgMgmt"] = "—" }

        // Past 3 mgmt% (use matches where mgmt% exists among the most recent matches)
        var recentUserMgmtVals: [Double] = []
        var recentOppMgmtVals: [Double] = []
        for m in matches {
            if let mg = m.userMgmtPct { recentUserMgmtVals.append(mg) }
            if let mg = m.oppMgmtPct { recentOppMgmtVals.append(mg) }
            if recentUserMgmtVals.count >= 3 && recentOppMgmtVals.count >= 3 { break }
        }
        if !recentUserMgmtVals.isEmpty {
            let avg = recentUserMgmtVals.reduce(0.0, +) / Double(recentUserMgmtVals.count)
            userStats["past3Mgmt"] = String(format: "%.2f%%", avg)
        } else {
            userStats["past3Mgmt"] = "—"
        }

        if !recentOppMgmtVals.isEmpty {
            let avg = recentOppMgmtVals.reduce(0.0, +) / Double(recentOppMgmtVals.count)
            oppStats["past3Mgmt"] = String(format: "%.2f%%", avg)
        } else {
            oppStats["past3Mgmt"] = "—"
        }

        return (userStats, oppStats)
    }

    // MARK: - View
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Head-to-Head History")
                .font(.headline)
                .foregroundColor(.white)
            Divider().background(Color.white.opacity(0.06))

            // Compute matches & aggregates on-demand synchronously (main actor / lightweight)
            let matches = collectAllMatches()
            let aggregates = computeAggregates(from: matches)

            // Stat History: two-column comparison
            statHistoryView(userStats: aggregates.user, oppStats: aggregates.opp)

            Divider().background(Color.white.opacity(0.06))

            // Match list
            if matches.isEmpty {
                Text("No head-to-head matches found between these teams.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(matches) { m in
                        matchRowView(m)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    private func statHistoryView(userStats: [String: String], oppStats: [String: String]) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(user?.name ?? user?.ownerId ?? "You")
                    .foregroundColor(.cyan)
                    .bold()
                Spacer()
                Text(opp?.name ?? opp?.ownerId ?? "Opponent")
                    .foregroundColor(.yellow)
                    .bold()
            }

            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    statLine(label: "Record", value: userStats["record"] ?? "0-0")
                    statLine(label: "Avg PPG", value: userStats["avgPPG"] ?? "0.00")
                    statLine(label: "Past 3", value: userStats["past3PPG"] ?? "0.00")
                    statLine(label: "Avg Mgmt%", value: userStats["avgMgmt"] ?? "—")
                    statLine(label: "Past 3 Mgmt%", value: userStats["past3Mgmt"] ?? "—")
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    statLine(label: "Record", value: oppStats["record"] ?? "0-0")
                    statLine(label: "Avg PPG", value: oppStats["avgPPG"] ?? "0.00")
                    statLine(label: "Past 3", value: oppStats["past3PPG"] ?? "0.00")
                    statLine(label: "Avg Mgmt%", value: oppStats["avgMgmt"] ?? "—")
                    statLine(label: "Past 3 Mgmt%", value: oppStats["past3Mgmt"] ?? "—")
                }
            }
            .font(.caption)
        }
    }

    private func statLine(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.white.opacity(0.8))
            Spacer()
            Text(value).foregroundColor(.orange).bold()
        }
    }

    private func matchRowView(_ m: H2HMatchSimple) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Season \(m.seasonId) • Week \(m.week)")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.9))
                Text("Score: \(String(format: "%.2f", m.userPoints)) — \(String(format: "%.2f", m.oppPoints))")
                    .font(.caption2)
                    .foregroundColor(.white)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(m.result)
                    .font(.caption.bold())
                    .foregroundColor(m.result == "W" ? .green : (m.result == "L" ? .red : .yellow))
                HStack(spacing: 8) {
                    if let mg = m.userMgmtPct {
                        Text(String(format: "Mgmt: %.2f%%", mg))
                            .font(.caption2)
                            .foregroundColor(Color.mgmtPercentColor(mg))
                    } else {
                        Text("Mgmt: —")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Text("·").font(.caption2).foregroundColor(.white.opacity(0.5))
                    if let mg2 = m.oppMgmtPct {
                        Text(String(format: "%.2f%%", mg2))
                            .font(.caption2)
                            .foregroundColor(Color.mgmtPercentColor(mg2))
                    } else {
                        Text("—").font(.caption2).foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.01)))
    }
}
