//
//  HeadToHeadStatsSection.swift
//  DynastyStatDrop
//
//  Updated to accept precomputed H2H snapshots passed from MatchupView
//  and to remove legacy fallback / recomputation logic per request.
//
//  Design:
//   - HeadToHeadStatsSection exclusively uses `matchSnapshots` (if provided)
//     as the authoritative source for per-match scores and mgmt% values.
//   - Aggregated stats (Record, Avg Mgmt%, Avg PPG) are computed only from
//     these snapshots.
//   - No fallback recomputation of mgmt% or scores is performed here.
//   - The only season-scanning helper retained is `findMatchupWeeksBetweenTeams`
//     which enumerates the weeks/seasons where the two teams met (used by callers).
//

import SwiftUI

/// Lightweight per-team snapshot constructed by MatchupView (or other callers)
/// containing the exact numbers MatchupView displays for a given week.
struct H2HTeamSnapshot {
    let rosterId: String         // TeamStanding.id (roster id as string)
    let ownerId: String?         // optional owner id
    let name: String
    let totalPoints: Double
    let maxPoints: Double
    let managementPercent: Double

    /// Numeric roster id convenience
    var rosterIdInt: Int? { Int(rosterId) }
}

/// Lightweight per-match snapshot built by MatchupView that contains the
/// authoritative per-match values (scores, mgmt% etc) — MatchupView is
/// responsible for constructing these so HeadToHeadStatsSection does not
/// need to recompute anything.
struct H2HMatchSnapshot: Identifiable, Codable, Equatable {
    let id: String // unique id, e.g. "\(seasonId)-\(week)-\(matchupId)"
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
    let missingPlayerIds: [String]?

    init(seasonId: String, week: Int, matchupId: Int?, userRosterId: Int, oppRosterId: Int, userPoints: Double, oppPoints: Double, userMgmtPct: Double?, oppMgmtPct: Double?, missingPlayerIds: [String]? = nil) {
        self.seasonId = seasonId
        self.week = week
        self.matchupId = matchupId
        self.userRosterId = userRosterId
        self.oppRosterId = oppRosterId
        self.userPoints = userPoints
        self.oppPoints = oppPoints
        self.userMgmtPct = userMgmtPct
        self.oppMgmtPct = oppMgmtPct
        if userPoints > oppPoints { self.result = "W" }
        else if userPoints < oppPoints { self.result = "L" }
        else { self.result = "T" }
        self.missingPlayerIds = missingPlayerIds ?? []
        self.id = "\(seasonId)-\(week)-\(matchupId ?? -9999)-u:\(userRosterId)-o:\(oppRosterId)"
    }
}

struct HeadToHeadStatsSection: View {
    // Backwards-compatible: we still accept TeamStanding objects for callers that prefer them.
    let user: TeamStanding?
    let opp: TeamStanding?
    let league: LeagueData

    // Optional precomputed snapshots (constructed by MatchupView from its TeamDisplay)
    let userSnapshot: H2HTeamSnapshot?
    let oppSnapshot: H2HTeamSnapshot?

    // Optional full array of precomputed per-match snapshots (Option A)
    // When provided, HeadToHeadStatsSection will use these exclusively to render Match History
    // and to compute summary aggregates (Record, Avg Mgmt%, Avg PPG).
    let matchSnapshots: [H2HMatchSnapshot]?

    // Optional context identifying the current season & week displayed by MatchupView.
    // This may be used by callers; HeadToHeadStatsSection does not use it for recomputation.
    let currentSeasonId: String?
    let currentWeekNumber: Int?

    @EnvironmentObject private var leagueManager: SleeperLeagueManager

    // MARK: - Aggregates computed from snapshots (when provided)
    private var aggregatesFromSnapshots: (record: String, avgMgmtFor: Double, avgPF: Double, avgMgmtAgainst: Double, avgPA: Double) {
        guard let snaps = matchSnapshots, !snaps.isEmpty else {
            return ("0-0", 0.0, 0.0, 0.0, 0.0)
        }

        var wins = 0, losses = 0, ties = 0
        var sumMgmtFor = 0.0, countMgmtFor = 0
        var sumMgmtAgainst = 0.0, countMgmtAgainst = 0
        var sumPF = 0.0, sumPA = 0.0

        for s in snaps {
            switch s.result {
            case "W": wins += 1
            case "L": losses += 1
            default: ties += 1
            }
            sumPF += s.userPoints
            sumPA += s.oppPoints

            if let mg = s.userMgmtPct {
                sumMgmtFor += mg
                countMgmtFor += 1
            }
            if let mg = s.oppMgmtPct {
                sumMgmtAgainst += mg
                countMgmtAgainst += 1
            }
        }

        let games = snaps.count
        let avgPF = games > 0 ? sumPF / Double(games) : 0.0
        let avgPA = games > 0 ? sumPA / Double(games) : 0.0
        let avgMgmtFor = countMgmtFor > 0 ? sumMgmtFor / Double(countMgmtFor) : 0.0
        let avgMgmtAgainst = countMgmtAgainst > 0 ? sumMgmtAgainst / Double(countMgmtAgainst) : 0.0
        let record = "\(wins)-\(losses)\(ties > 0 ? "-\(ties)" : "")"
        return (record, avgMgmtFor, avgPF, avgMgmtAgainst, avgPA)
    }

    // Prefer snapshot aggregates when available; otherwise return zeroed default.
    private var h2hSummary: (record: String, avgMgmtFor: Double, avgPF: Double, avgMgmtAgainst: Double, avgPA: Double) {
        if let _ = matchSnapshots { return aggregatesFromSnapshots }
        return ("0-0", 0.0, 0.0, 0.0, 0.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleBarView
            statsColumnsView
            matchHistoryView
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var titleBarView: some View { EmptyView() }

    private var statsColumnsView: some View {
        let summary = h2hSummary

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(user?.name ?? userSnapshot?.name ?? "You").foregroundColor(.cyan).bold()
                statRow("Record vs Opp", summary.record)
                HStack {
                    Text("Mgmt % vs Opp").foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(String(format: "%.2f%%", summary.avgMgmtFor))
                        .foregroundColor(Color.mgmtPercentColor(summary.avgMgmtFor)).bold()
                }.font(.caption)
                statRow("Avg PPG vs Opp", String(format: "%.2f", summary.avgPF))
            }.frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(opp?.name ?? oppSnapshot?.name ?? "Opponent").foregroundColor(.yellow).bold()
                statRow("Record vs You", HeadToHeadStatsSection.reverseRecordString(summary.record))
                HStack {
                    Text("Mgmt % vs You").foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(String(format: "%.2f%%", summary.avgMgmtAgainst))
                        .foregroundColor(Color.mgmtPercentColor(summary.avgMgmtAgainst)).bold()
                }.font(.caption)
                statRow("Avg PPG vs You", String(format: "%.2f", summary.avgPA))
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var matchHistoryView: some View {
        Group {
            if let snaps = matchSnapshots, !snaps.isEmpty {
                Divider().background(Color.white.opacity(0.06))
                Text("Match History")
                    .font(.subheadline.bold())
                    .foregroundColor(.white.opacity(0.9))

                // Sort snapshots descending by season, week, matchupId for display
                let sorted = snaps.sorted { lhs, rhs in
                    if lhs.seasonId != rhs.seasonId { return lhs.seasonId > rhs.seasonId }
                    if lhs.week != rhs.week { return lhs.week > rhs.week }
                    return (lhs.matchupId ?? 0) > (rhs.matchupId ?? 0)
                }

                VStack(spacing: 8) {
                    ForEach(sorted) { match in
                        matchRowView(match)
                    }
                }
            } else {
                Text("No head-to-head matches on record.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Extracted subview to help compiler type-checking
    private func matchRowView(_ match: H2HMatchSnapshot) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text("Season \(match.seasonId) • Week \(match.week)")
                    .font(.caption.bold())
                    .foregroundColor(match.result == "W" ? .green : (match.result == "L" ? .red : .yellow))
                Text("Score: \(String(format: "%.2f", match.userPoints)) — \(String(format: "%.2f", match.oppPoints))")
                    .font(.caption2).foregroundColor(.white)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(match.result)
                    .font(.caption.bold())
                    .foregroundColor(match.result == "W" ? .green : (match.result == "L" ? .red : .yellow))

                if let userMgmt = match.userMgmtPct, let oppMgmt = match.oppMgmtPct {
                    HStack(spacing: 6) {
                        Text(String(format: "Mgmt: %.2f%%", userMgmt))
                            .font(.caption2)
                            .foregroundColor(Color.mgmtPercentColor(userMgmt))
                        Text("·").font(.caption2).foregroundColor(.white.opacity(0.5))
                        Text(String(format: "%.2f%%", oppMgmt))
                            .font(.caption2)
                            .foregroundColor(Color.mgmtPercentColor(oppMgmt))
                    }
                } else {
                    Text("Mgmt: —")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }

                if let missing = match.missingPlayerIds, !missing.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption2)
                        Text("\(missing.count) missing players")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.02)))
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Text(value)
                .foregroundColor(.orange)
                .bold()
        }
        .font(.caption)
    }

    private static func reverseRecordString(_ str: String) -> String {
        let parts = str.split(separator: "-")
        if parts.count == 2 { return "\(parts[1])-\(parts[0])" }
        if parts.count == 3 { return "\(parts[1])-\(parts[0])-\(parts[2])" }
        return str
    }

    // MARK: - Minimal helper kept to determine the weeks/season matchups where the two teams met.
    // This helper is intentionally read-only and DOES NOT perform mgmt% or score recomputation.
    // It returns an ordered list of match descriptors (seasonId, week, matchupId, roster ids).
    //
    // Usage: callers (e.g., MatchupView) can call this to determine which season/week pairs to ask
    // the authoritative per-week TeamDisplay / snapshot generator to build H2HMatchSnapshot objects.
    func findMatchupWeeksBetweenTeams() -> [(seasonId: String, week: Int, matchupId: Int?, userRosterId: Int, oppRosterId: Int)] {
        var out: [(seasonId: String, week: Int, matchupId: Int?, userRosterId: Int, oppRosterId: Int)] = []

        // Determine user and opp owner ids (prefer TeamStanding.ownerId when available)
        let userOwnerId = user?.ownerId ?? userSnapshot?.ownerId
        let oppOwnerId = opp?.ownerId ?? oppSnapshot?.ownerId

        // If we have neither owner id nor numeric roster ids, attempt to use roster ids directly
        let explicitUserRosterId = user?.id.flatMap { Int($0) } ?? userSnapshot?.rosterIdInt
        let explicitOppRosterId = opp?.id.flatMap { Int($0) } ?? oppSnapshot?.rosterIdInt

        // Iterate seasons/wks
        for season in league.seasons {
            guard let weeks = season.matchupsByWeek else { continue }
            // Build season-local roster id candidates for owners if owner ids present
            var seasonUserRosterId: Int? = nil
            var seasonOppRosterId: Int? = nil
            if let uOwner = userOwnerId {
                seasonUserRosterId = season.teams.first(where: { $0.ownerId == uOwner }).flatMap { Int($0.id) }
            }
            if seasonUserRosterId == nil { seasonUserRosterId = explicitUserRosterId }

            if let oOwner = oppOwnerId {
                seasonOppRosterId = season.teams.first(where: { $0.ownerId == oOwner }).flatMap { Int($0.id) }
            }
            if seasonOppRosterId == nil { seasonOppRosterId = explicitOppRosterId }

            guard let uRid = seasonUserRosterId, let oRid = seasonOppRosterId else { continue }

            for wk in weeks.keys.sorted() {
                let entries = weeks[wk] ?? []
                let hasUser = entries.contains(where: { $0.roster_id == uRid })
                let hasOpp = entries.contains(where: { $0.roster_id == oRid })
                if hasUser && hasOpp {
                    // attempt to prefer a matchup_id from either entry
                    let uEntry = entries.first(where: { $0.roster_id == uRid })
                    let oEntry = entries.first(where: { $0.roster_id == oRid })
                    let mid = uEntry?.matchup_id ?? oEntry?.matchup_id
                    out.append((seasonId: season.id, week: wk, matchupId: mid, userRosterId: uRid, oppRosterId: oRid))
                }
            }
        }

        // Sort by season desc, week desc for convenience (match display order)
        out.sort { a, b in
            if a.seasonId != b.seasonId { return a.seasonId > b.seasonId }
            if a.week != b.week { return a.week > b.week }
            return (a.matchupId ?? 0) > (b.matchupId ?? 0)
        }
        return out
    }
}
