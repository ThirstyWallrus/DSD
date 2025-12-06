//
//  HeadToHeadStatsSection.swift
//  DynastyStatDrop
//
//  Updated to prefer stored H2H values when trustworthy; otherwise uses ManagementCalculator
//  to compute mgmt% so numbers match MatchupView exactly (Option C).
//
//  CHANGE: Accept optional precomputed per-team snapshot (H2HTeamSnapshot) and current season/week.
//  If a historical H2H match detail corresponds to the currently-displayed matchup, prefer the
//  precomputed values from MatchupView (avoids redundant recomputation).
//

import SwiftUI

/// Lightweight snapshot type used to pass precomputed matchup values (from MatchupView)
/// into HeadToHeadStatsSection to avoid redundant recomputation.
///
/// This struct is intentionally small and decoupled from MatchupView internal types so it can
/// be constructed by MatchupView and consumed here without depending on nested types.
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

struct HeadToHeadStatsSection: View {
    // Backwards-compatible: we still accept TeamStanding objects for callers that prefer them.
    // Prefer using the optional precomputed snapshots (userSnapshot / oppSnapshot) for the currently-displayed matchup.
    let user: TeamStanding?
    let opp: TeamStanding?
    let league: LeagueData

    // Optional precomputed snapshots (constructed by MatchupView from its TeamDisplay)
    let userSnapshot: H2HTeamSnapshot?
    let oppSnapshot: H2HTeamSnapshot?

    // Optional context identifying the current season & week displayed by MatchupView.
    // When a historical H2H detail matches these, we will use the snapshots instead of recomputing.
    let currentSeasonId: String?
    let currentWeekNumber: Int?

    @EnvironmentObject private var leagueManager: SleeperLeagueManager

    // Legacy accessors
    private var h2hSummary: (record: String, avgMgmtFor: Double, avgPF: Double, avgMgmtAgainst: Double, avgPA: Double) {
        // If we have owner IDs use them; otherwise fall back to stored aggregation retrieval using league
        if let uid = user?.ownerId, let oid = opp?.ownerId {
            return Self.getHeadToHeadAllTime(userOwnerId: uid, oppOwnerId: oid, league: league)
        }
        // Fallback: attempt to find owner IDs via snapshots
        if let uo = userSnapshot?.ownerId, let oo = oppSnapshot?.ownerId {
            return Self.getHeadToHeadAllTime(userOwnerId: uo, oppOwnerId: oo, league: league)
        }
        // As a last resort return zeros
        return ("0-0", 0.0, 0.0, 0.0, 0.0)
    }

    private var h2hDetails: [H2HMatchDetail]? {
        if let uid = user?.ownerId, let oid = opp?.ownerId {
            return Self.getHeadToHeadDetails(userOwnerId: uid, oppOwnerId: oid, league: league)
        }
        if let uo = userSnapshot?.ownerId, let oo = oppSnapshot?.ownerId {
            return Self.getHeadToHeadDetails(userOwnerId: uo, oppOwnerId: oo, league: league)
        }
        return nil
    }

    private func sortedDetails(_ list: [H2HMatchDetail]) -> [H2HMatchDetail] {
        list.sorted { lhs, rhs in
            if lhs.seasonId != rhs.seasonId { return lhs.seasonId > rhs.seasonId }
            if lhs.week != rhs.week { return lhs.week > rhs.week }
            return lhs.matchupId > rhs.matchupId
        }
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
            if let list = h2hDetails, !list.isEmpty {
                Divider().background(Color.white.opacity(0.06))
                Text("Match History")
                    .font(.subheadline.bold())
                    .foregroundColor(.white.opacity(0.9))

                let sorted = sortedDetails(list)

                VStack(spacing: 8) {
                    ForEach(sorted.indices, id: \.self) { idx in
                        let match = sorted[idx]
                        let verification = verifyMatch(match)
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

                                // Prefer verification values; fallback to stored values
                                if let userMgmt = verification.userMgmt, let oppMgmt = verification.oppMgmt {
                                    HStack(spacing: 6) {
                                        Text(String(format: "Mgmt: %.2f%%", userMgmt))
                                            .font(.caption2)
                                            .foregroundColor(Color.mgmtPercentColor(userMgmt))
                                        Text("·").font(.caption2).foregroundColor(.white.opacity(0.5))
                                        Text(String(format: "%.2f%%", oppMgmt))
                                            .font(.caption2)
                                            .foregroundColor(Color.mgmtPercentColor(oppMgmt))
                                    }
                                } else if verification.matchupMissing {
                                    Text("Matchup data unavailable")
                                        .font(.caption2)
                                        .foregroundColor(.red.opacity(0.8))
                                } else {
                                    // Final fallback: show stored numbers
                                    HStack(spacing: 6) {
                                        Text(String(format: "Mgmt: %.2f%%", match.userMgmtPct))
                                            .font(.caption2)
                                            .foregroundColor(Color.mgmtPercentColor(match.userMgmtPct))
                                        Text("·").font(.caption2).foregroundColor(.white.opacity(0.5))
                                        Text(String(format: "%.2f%%", match.oppMgmtPct))
                                            .font(.caption2)
                                            .foregroundColor(Color.mgmtPercentColor(match.oppMgmtPct))
                                    }
                                }

                                if !verification.missingPlayerIds.isEmpty {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.red)
                                            .font(.caption2)
                                        Text("\(verification.missingPlayerIds.count) missing players")
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.02)))
                    }
                }
            } else {
                Text("No head-to-head matches on record.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Verification Helpers

    private struct MatchVerification {
        let userMgmt: Double?
        let oppMgmt: Double?
        let missingPlayerIds: [String]
        let matchupMissing: Bool
    }

    private func verifyMatch(_ match: H2HMatchDetail) -> MatchVerification {
        // If this match corresponds to the currently-displayed season/week and we were passed snapshots,
        // prefer snapshot values and avoid recomputing.
        if let curSeason = currentSeasonId, let curWeek = currentWeekNumber,
           match.seasonId == curSeason, match.week == curWeek,
           let usnap = userSnapshot, let osnap = oppSnapshot,
           let uRid = usnap.rosterIdInt, let oRid = osnap.rosterIdInt {
            if match.userRosterId == uRid && match.oppRosterId == oRid {
                return MatchVerification(userMgmt: usnap.managementPercent, oppMgmt: osnap.managementPercent, missingPlayerIds: [], matchupMissing: false)
            }
            // If the snapshot roster ids are reversed in the match detail, swap appropriately
            if match.userRosterId == oRid && match.oppRosterId == uRid {
                return MatchVerification(userMgmt: osnap.managementPercent, oppMgmt: usnap.managementPercent, missingPlayerIds: [], matchupMissing: false)
            }
        }

        // Locate user & opp matchup entries
        let myEntry = findUserMatchupEntry(for: match)
        let oppEntry = findOppMatchupEntry(for: match)

        // If either entry is missing, mark matchupMissing
        guard let myE = myEntry else {
            return MatchVerification(userMgmt: nil, oppMgmt: nil, missingPlayerIds: [], matchupMissing: true)
        }
        guard let oppE = oppEntry else {
            // still attempt to list unresolved players for debugging
            let unresolved = unresolvedPlayersIn(entry: myE, matchWeek: match.week)
            return MatchVerification(userMgmt: nil, oppMgmt: nil, missingPlayerIds: unresolved, matchupMissing: false)
        }

        // If stored details exist AND both entries contain players_points (non-empty), prefer stored values.
        // This avoids recomputation when AllTimeAggregator already computed mgmt% from authoritative matchup data.
        let storedTrustworthy: Bool = {
            let bothHavePP = (myE.players_points?.isEmpty == false) && (oppE.players_points?.isEmpty == false)
            let storedNonZero = match.userMgmtPct > 0 || match.oppMgmtPct > 0
            return bothHavePP && storedNonZero
        }()

        // collect unresolved players for display (best-effort)
        let unresolved = unresolvedPlayersIn(entry: myE, matchWeek: match.week)

        if storedTrustworthy {
            // Use stored H2H values directly
            return MatchVerification(userMgmt: match.userMgmtPct, oppMgmt: match.oppMgmtPct, missingPlayerIds: unresolved, matchupMissing: false)
        }

        // Otherwise, recompute both sides using the canonical ManagementCalculator
        let seasonTeamUser = findSeasonTeam(forEntry: myE)
        let seasonTeamOpp = findSeasonTeam(forEntry: oppE)

        let recomputedUser = ManagementCalculator.computeManagementPercentForEntry(entry: myE, seasonTeam: seasonTeamUser, week: match.week, league: league, leagueManager: leagueManager)
        let recomputedOpp = ManagementCalculator.computeManagementPercentForEntry(entry: oppE, seasonTeam: seasonTeamOpp, week: match.week, league: league, leagueManager: leagueManager)

        return MatchVerification(userMgmt: recomputedUser, oppMgmt: recomputedOpp, missingPlayerIds: unresolved, matchupMissing: false)
    }

    private func unresolvedPlayersIn(entry: MatchupEntry, matchWeek: Int) -> [String] {
        var unresolved: [String] = []
        let playerCache = leagueManager.playerCache ?? [:]
        let seasonTeam = findSeasonTeam(forEntry: entry)
        let candidatesToCheck = Set((entry.starters ?? []) + (entry.players ?? []) + Array(entry.players_points?.keys ?? []))
        for pid in candidatesToCheck {
            if pid == "0" { continue }
            var found = false
            if let team = seasonTeam {
                if team.roster.contains(where: { $0.id == pid }) { found = true }
            }
            if !found {
                if playerCache[pid] != nil { found = true }
            }
            if !found { unresolved.append(pid) }
        }
        return unresolved
    }

    private func findUserMatchupEntry(for match: H2HMatchDetail) -> MatchupEntry? {
        let rosterId = Int(user?.id ?? userSnapshot?.rosterId ?? "") ?? -1
        for season in league.seasons {
            if let weeks = season.matchupsByWeek {
                if let entries = weeks[match.week] {
                    if let candidate = entries.first(where: { $0.roster_id == rosterId && ($0.matchup_id ?? -1) == match.matchupId }) {
                        return candidate
                    }
                    if let candidate = entries.first(where: { $0.roster_id == rosterId }) {
                        return candidate
                    }
                }
            }
        }
        return nil
    }

    private func findOppMatchupEntry(for match: H2HMatchDetail) -> MatchupEntry? {
        let rosterId = Int(opp?.id ?? oppSnapshot?.rosterId ?? "") ?? -1
        for season in league.seasons {
            if let weeks = season.matchupsByWeek {
                if let entries = weeks[match.week] {
                    if let candidate = entries.first(where: { $0.roster_id == rosterId && ($0.matchup_id ?? -1) == match.matchupId }) {
                        return candidate
                    }
                    if let candidate = entries.first(where: { $0.roster_id == rosterId }) {
                        return candidate
                    }
                }
            }
        }
        return nil
    }

    private func findSeasonTeam(forEntry entry: MatchupEntry?) -> TeamStanding? {
        guard let entry = entry else { return nil }
        let rosterId = entry.roster_id
        for season in league.seasons {
            if let weeks = season.matchupsByWeek, weeks.contains(where: { $0.value.contains(where: { $0.roster_id == rosterId }) }) {
                if let team = season.teams.first(where: { $0.id == String(rosterId) }) { return team }
                if let team = league.teams.first(where: { $0.id == String(rosterId) }) { return team }
            }
        }
        return nil
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

    static func getHeadToHeadAllTime(userOwnerId: String, oppOwnerId: String, league: LeagueData) -> (record: String, avgMgmtFor: Double, avgPF: Double, avgMgmtAgainst: Double, avgPA: Double) {
        guard let userAgg = league.allTimeOwnerStats?[userOwnerId],
              let h2h = userAgg.headToHeadVs[oppOwnerId] else {
            return ("0-0", 0.0, 0.0, 0.0, 0.0)
        }
        return (h2h.record, h2h.avgMgmtFor, h2h.avgPointsFor, h2h.avgMgmtAgainst, h2h.avgPointsAgainst)
    }

    static func getHeadToHeadDetails(userOwnerId: String, oppOwnerId: String, league: LeagueData) -> [H2HMatchDetail]? {
        guard let userAgg = league.allTimeOwnerStats?[userOwnerId] else { return nil }
        return userAgg.headToHeadDetails?[oppOwnerId]
    }
}
