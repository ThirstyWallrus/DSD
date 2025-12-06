//
//  HeadToHeadStatsSection.swift
//  DynastyStatDrop
//
//  Updated to accept precomputed H2H snapshots passed from MatchupView (Option A).
//  HeadToHeadStatsSection will prefer the passed snapshots for Match History and
//  summary aggregates, avoiding independent per-match recomputation and ensuring
//  parity with the values shown in MatchupView.
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
    // When a historical H2H detail matches these, we will prefer snapshot values if they are supplied.
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

    // Backwards-compatible legacy fallback: uses cached aggregated all-time H2H if snapshots are not present
    private var h2hSummaryFallback: (record: String, avgMgmtFor: Double, avgPF: Double, avgMgmtAgainst: Double, avgPA: Double) {
        if let uid = user?.ownerId, let oid = opp?.ownerId {
            return Self.getHeadToHeadAllTime(userOwnerId: uid, oppOwnerId: oid, league: league)
        }
        if let uo = userSnapshot?.ownerId, let oo = oppSnapshot?.ownerId {
            return Self.getHeadToHeadAllTime(userOwnerId: uo, oppOwnerId: oo, league: league)
        }
        return ("0-0", 0.0, 0.0, 0.0, 0.0)
    }

    // Prefer snapshot aggregates when available
    private var h2hSummary: (record: String, avgMgmtFor: Double, avgPF: Double, avgMgmtAgainst: Double, avgPA: Double) {
        if let _ = matchSnapshots { return aggregatesFromSnapshots }
        return h2hSummaryFallback
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
                // Fallback: legacy behavior — use aggregated H2HDetails if available and snapshots not provided
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

    // MARK: - Legacy verification & helpers (left in place as a fallback)

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
            if match.userRosterId == oRid && match.oppRosterId == uRid {
                return MatchVerification(userMgmt: osnap.managementPercent, oppMgmt: usnap.managementPercent, missingPlayerIds: [], matchupMissing: false)
            }
        }

        // Locate user & opp matchup entries
        let myEntry = findUserMatchupEntry(for: match)
        let oppEntry = findOppMatchupEntry(for: match)

        guard let myE = myEntry else {
            return MatchVerification(userMgmt: nil, oppMgmt: nil, missingPlayerIds: [], matchupMissing: true)
        }
        guard let oppE = oppEntry else {
            let unresolved = unresolvedPlayersIn(entry: myE, matchWeek: match.week)
            return MatchVerification(userMgmt: nil, oppMgmt: nil, missingPlayerIds: unresolved, matchupMissing: false)
        }

        let storedTrustworthy: Bool = {
            let bothHavePP = (myE.players_points?.isEmpty == false) && (oppE.players_points?.isEmpty == false)
            let storedNonZero = match.userMgmtPct > 0 || match.oppMgmtPct > 0
            return bothHavePP && storedNonZero
        }()

        let unresolved = unresolvedPlayersIn(entry: myE, matchWeek: match.week)

        if storedTrustworthy {
            return MatchVerification(userMgmt: match.userMgmtPct, oppMgmt: match.oppMgmtPct, missingPlayerIds: unresolved, matchupMissing: false)
        }

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

    // MARK: - Legacy aggregated helpers (unchanged)
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
}
