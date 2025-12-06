//
//  HeadToHeadStatsSection.swift
//  DynastyStatDrop
//
//

import SwiftUI

struct HeadToHeadStatsSection: View {
    let user: TeamStanding
    let opp: TeamStanding
    let league: LeagueData

    // New: we need access to the canonical player cache for resolving historical starter ids
    @EnvironmentObject private var leagueManager: SleeperLeagueManager

    // MARK: - Extracted computed properties / helpers to reduce body complexity

    private var h2hSummary: (record: String, avgMgmtFor: Double, avgPF: Double, avgMgmtAgainst: Double, avgPA: Double) {
        Self.getHeadToHeadAllTime(
            userOwnerId: user.ownerId,
            oppOwnerId: opp.ownerId,
            league: league
        )
    }

    private var h2hDetails: [H2HMatchDetail]? {
        Self.getHeadToHeadDetails(
            userOwnerId: user.ownerId,
            oppOwnerId: opp.ownerId,
            league: league
        )
    }

    // Sort so that the most recent match appears first: season desc, week desc, matchupId desc
    private func sortedDetails(_ list: [H2HMatchDetail]) -> [H2HMatchDetail] {
        list.sorted { lhs, rhs in
            if lhs.seasonId != rhs.seasonId { return lhs.seasonId > rhs.seasonId }
            if lhs.week != rhs.week { return lhs.week > rhs.week }
            return lhs.matchupId > rhs.matchupId
        }
    }

    // MARK: - Body (broken into smaller subviews to aid the compiler)

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

    // MARK: - Subviews

    private var titleBarView: some View {
        // Title removed per request — intentionally empty
        EmptyView()
    }

    private var statsColumnsView: some View {
        // Pull precomputed values here with explicit type to avoid big expression in the main body
        let summary: (record: String, avgMgmtFor: Double, avgPF: Double, avgMgmtAgainst: Double, avgPA: Double) = h2hSummary

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(user.name)
                    .foregroundColor(.cyan)
                    .bold()
                statRow("Record vs Opp", summary.record)
                // Use centralized mgmt color for the mgmt percent value
                HStack {
                    Text("Mgmt % vs Opp")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(String(format: "%.2f%%", summary.avgMgmtFor))
                        .foregroundColor(Color.mgmtPercentColor(summary.avgMgmtFor))
                        .bold()
                }
                .font(.caption)
                statRow("Avg PPG vs Opp", String(format: "%.2f", summary.avgPF))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(opp.name)
                    .foregroundColor(.yellow)
                    .bold()
                // Use reverse format for opponent's record
                statRow("Record vs You", HeadToHeadStatsSection.reverseRecordString(summary.record))
                // Use centralized mgmt color for opponent mgmt percent display
                HStack {
                    Text("Mgmt % vs You")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(String(format: "%.2f%%", summary.avgMgmtAgainst))
                        .foregroundColor(Color.mgmtPercentColor(summary.avgMgmtAgainst))
                        .bold()
                }
                .font(.caption)
                statRow("Avg PPG vs You", String(format: "%.2f", summary.avgPA))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // REPLACED: Removed ScrollView -> List all matches inline, most recent first.
    // Each match row attempts to locate the original MatchupEntry and performs a validation check:
    // - recomputes mgmt% (if possible) and compares to stored values
    // - lists any unresolved player ids (not in that season's team roster AND not in canonical player cache)
    private var matchHistoryView: some View {
        Group {
            if let list = h2hDetails, !list.isEmpty {
                Divider().background(Color.white.opacity(0.06))
                Text("Match History")
                    .font(.subheadline.bold())
                    .foregroundColor(.white.opacity(0.9))

                // Sorted so newest first
                let sorted = sortedDetails(list)

                VStack(spacing: 8) {
                    ForEach(sorted.indices, id: \.self) { idx in
                        let match = sorted[idx]
                        // For each match compute verification info
                        let verification = verifyMatch(match)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading) {
                                Text("Season \(match.seasonId) • Week \(match.week)")
                                    .font(.caption.bold())
                                    .foregroundColor(match.result == "W" ? .green : (match.result == "L" ? .red : .yellow))
                                Text("Score: \(String(format: "%.2f", match.userPoints)) — \(String(format: "%.2f", match.oppPoints))")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(match.result)
                                    .font(.caption.bold())
                                    .foregroundColor(match.result == "W" ? .green : (match.result == "L" ? .red : .yellow))
                                // Management % display with recomputed check (if available)
                                if let oppMgmt = verification.oppMgmt {
                                    HStack(spacing: 6) {
                                        Text(String(format: "Mgmt: %.2f%%", match.userMgmtPct))
                                            .font(.caption2)
                                            .foregroundColor(Color.mgmtPercentColor(match.userMgmtPct))
                                        Text("·")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.5))
                                        Text(String(format: "%.2f%%", oppMgmt))
                                            .font(.caption2)
                                            .foregroundColor(Color.mgmtPercentColor(oppMgmt))
                                    }
                                } else if verification.matchupMissing {
                                    Text("Matchup data unavailable")
                                        .font(.caption2)
                                        .foregroundColor(.red.opacity(0.8))
                                } else {
                                    // Fallback: show reported mgmt only
                                    Text(String(format: "Mgmt: %.2f%%", match.userMgmtPct))
                                        .font(.caption2)
                                        .foregroundColor(Color.mgmtPercentColor(match.userMgmtPct))
                                }

                                // If any missing players were detected, show a compact inline warning
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

    // A compact result for match verification
    private struct MatchVerification {
        let oppMgmt: Double?
        let missingPlayerIds: [String]
        let matchupMissing: Bool
    }

    // Attempts to find the MatchupEntry for the user's roster in league seasons and recompute mgmt%
    // Also returns any player ids included in the matchup that could not be resolved from
    // that season's team roster or the global player cache.
    private func verifyMatch(_ match: H2HMatchDetail) -> MatchVerification {
        // Try to locate the matchup entry (best-effort across all seasons)
        guard let myEntry = findUserMatchupEntry(for: match) else {
            return MatchVerification(oppMgmt: nil, missingPlayerIds: [], matchupMissing: true)
        }

        // We have a MatchupEntry for the user for that week/season
        // Gather the players pool and player points
        let playersPool = myEntry.players ?? []
        let playersPoints = myEntry.players_points ?? [:]
        // Resolve the seasonTeam (historical team object for that entry) if available
        let seasonTeam = findSeasonTeam(forEntry: myEntry)

        // For missing players: players that are in playersPool (or in starters) but not in seasonTeam.roster
        var unresolved: [String] = []
        let playerCache = leagueManager.playerCache ?? [:]

        let candidatesToCheck = Set((myEntry.starters ?? []) + playersPool + Array(playersPoints.keys))

        for pid in candidatesToCheck {
            // skip padded/zero
            if pid == "0" { continue }
            var found = false
            if let team = seasonTeam {
                if team.roster.contains(where: { $0.id == pid }) { found = true }
            }
            if !found {
                if playerCache[pid] != nil { found = true }
            }
            if !found {
                unresolved.append(pid)
            }
        }

        guard let oppEntry = findOppMatchupEntry(for: match) else {
            // Log a concise debug message for QA (non-invasive)
            if !unresolved.isEmpty {
                print("[H2H][Verify] Season:\(match.seasonId) Wk:\(match.week) - Unresolved player IDs: \(unresolved)")
            }
            return MatchVerification(oppMgmt: nil, missingPlayerIds: unresolved, matchupMissing: false)
        }

        let oppSeasonTeam = findSeasonTeam(forEntry: oppEntry)

        // Pass the week into recompute so the function can build a players_points fallback if necessary
        let oppMgmt: Double? = recomputeManagementPercent(entry: oppEntry, seasonTeam: oppSeasonTeam, week: match.week)

        // Log a concise debug message for QA (non-invasive)
        if !unresolved.isEmpty {
            print("[H2H][Verify] Season:\(match.seasonId) Wk:\(match.week) - Unresolved player IDs: \(unresolved)")
        }

        return MatchVerification(oppMgmt: oppMgmt, missingPlayerIds: unresolved, matchupMissing: false)
    }

    // Attempt to locate the user's MatchupEntry in the league seasons by week & roster_id.
    // We search all seasons' matchupsByWeek for the given week and roster_id matching user.id.
    private func findUserMatchupEntry(for match: H2HMatchDetail) -> MatchupEntry? {
        // roster_id is stored as Int in the matchup entries; user.id is String (team id).
        let rosterId = Int(user.id) ?? -1
        for season in league.seasons {
            if let weeks = season.matchupsByWeek {
                if let entries = weeks[match.week] {
                    // Prefer exact matchup id match when available
                    if let candidate = entries.first(where: { $0.roster_id == rosterId && ($0.matchup_id ?? -1) == match.matchupId }) {
                        return candidate
                    }
                    // Otherwise, take the entry with matching roster_id
                    if let candidate = entries.first(where: { $0.roster_id == rosterId }) {
                        return candidate
                    }
                }
            }
        }
        return nil
    }

    private func findOppMatchupEntry(for match: H2HMatchDetail) -> MatchupEntry? {
        let rosterId = Int(opp.id) ?? -1
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

    // Finds the TeamStanding in the season that corresponds to a given MatchupEntry (if possible).
    // This helps us check the historical roster for that entry.
    private func findSeasonTeam(forEntry entry: MatchupEntry?) -> TeamStanding? {
        guard let entry = entry else { return nil }
        // roster_id is Int in entry; find the season containing that entry
        let rosterId = entry.roster_id
        for season in league.seasons {
            if let weeks = season.matchupsByWeek, weeks.contains(where: { $0.value.contains(where: { $0.roster_id == rosterId }) }) {
                // find the team in that season with id == roster_id (string)
                if let team = season.teams.first(where: { $0.id == String(rosterId) }) {
                    return team
                }
                // fallback: try league-wide teams (some seasons may not include roster snapshots)
                if let team = league.teams.first(where: { $0.id == String(rosterId) }) {
                    return team
                }
            }
        }
        return nil
    }

    // Recompute Management % for the given matchup entry (user side).
    // Returns nil if recomputation couldn't be performed (insufficient data).
    // NOTE: This routine is now tolerant of missing entry.players_points: if players_points is absent/empty,
    //       it will attempt to build a fallback playersPoints map from the seasonTeam.roster weeklyScores
    //       (using the provided week). This mirrors the tolerant behavior used elsewhere (AllTimeAggregator/computeMaxForEntry).
    private func recomputeManagementPercent(entry: MatchupEntry, seasonTeam: TeamStanding?, week: Int) -> Double? {
        // Attempt to obtain an authoritative players_points map. If not present, try to build a best-effort map
        // from the seasonTeam roster weeklyScores for the requested week.
        var playersPoints: [String: Double] = entry.players_points ?? [:]

        if playersPoints.isEmpty {
            // If we have the season team and week information, build fallback mapping from roster weeklyScores
            if let team = seasonTeam {
                for p in team.roster {
                    if let s = p.weeklyScores.first(where: { $0.week == week }) {
                        playersPoints[p.id] = s.points_half_ppr ?? s.points
                    }
                }
            }
        }

        // If still empty, we can't reliably recompute actual starters' totals -> return nil
        if playersPoints.isEmpty {
            return nil
        }

        // Determine starting slots for the league (strip BN/IR/TAXI)
        var startingSlots: [String] = league.startingLineup.filter { !["BN", "IR", "TAXI"].contains($0) }
        if startingSlots.isEmpty {
            // Fall back to seasonTeam lineupConfig if available
            if let cfg = seasonTeam?.lineupConfig, !cfg.isEmpty {
                startingSlots = expandSlots(cfg)
            }
        }
        if startingSlots.isEmpty {
            // Give up if we don't know the expected starter slots
            return nil
        }

        let playerCache = leagueManager.playerCache ?? [:]

        // Build candidate list with normalized base positions and alt positions (normalized)
        // Use a robust id set that includes starters, players, players_points keys, and roster ids
        var idSet = Set<String>()
        if let players = entry.players { idSet.formUnion(players) }
        if let starters = entry.starters { idSet.formUnion(starters) }
        idSet.formUnion(playersPoints.keys)
        if let team = seasonTeam {
            idSet.formUnion(team.roster.map { $0.id })
        }

        let candidates: [(id: String, basePos: String, altPos: [String], score: Double)] = idSet.compactMap { pid in
            // Attempt to find a historical player object in season team roster
            if let p = seasonTeam?.roster.first(where: { $0.id == pid }) {
                let base = PositionNormalizer.normalize(p.position)
                let alt = (p.altPositions ?? []).map { PositionNormalizer.normalize($0) }
                return (id: pid, basePos: base, altPos: alt, score: playersPoints[pid] ?? 0.0)
            }
            // Fallback to player cache
            if let raw = playerCache[pid] {
                let base = PositionNormalizer.normalize(raw.position ?? "UNK")
                let alt = (raw.fantasy_positions ?? []).map { PositionNormalizer.normalize($0) }
                return (id: pid, basePos: base, altPos: alt, score: playersPoints[pid] ?? 0.0)
            }
            // Last-resort include with UNK pos
            let score = playersPoints[pid] ?? 0.0
            return (id: pid, basePos: PositionNormalizer.normalize("UNK"), altPos: [], score: score)
        }

        // Determine starting slot strict vs flex split
        var strictSlots: [String] = []
        var flexSlots: [String] = []
        for slot in startingSlots {
            let allowed = allowedPositions(for: slot)
            if allowed.count == 1 &&
                !isIDPFlex(slot) &&
                !offensiveFlexSlots.contains(slot.uppercased()) {
                strictSlots.append(slot)
            } else {
                flexSlots.append(slot)
            }
        }
        let optimalOrder = strictSlots + flexSlots

        var used = Set<String>()
        var maxTotal = 0.0
        var actualTotal = 0.0

        // compute actual total from starters using playersPoints (we built a fallback above)
        if let starters = entry.starters {
            for pid in starters where pid != "0" {
                actualTotal += playersPoints[pid] ?? 0.0
            }
        }

        // compute greedy max using candidate pool
        for slot in optimalOrder {
            let allowed = allowedPositions(for: slot)
            let candidatePool = candidates.filter { candidate in
                return !used.contains(candidate.id) && (allowed.contains(candidate.basePos) || !allowed.intersection(Set(candidate.altPos)).isEmpty)
            }
            if let pick = candidatePool.max(by: { $0.score < $1.score }) {
                used.insert(pick.id)
                maxTotal += pick.score
            }
        }

        guard maxTotal > 0 else { return nil }
        let mgmtPercent = (actualTotal / maxTotal) * 100.0
        return mgmtPercent
    }

    // MARK: - Small utility helpers (duplicated/embedded for encapsulation)
    // These are intentionally provided here as local helpers to avoid introducing cross-file
    // coupling or unexpected side effects while still matching the position normalization
    // and slot rules used across the app.

    private func allowedPositions(for slot: String) -> Set<String> {
        switch slot.uppercased() {
        case "QB","RB","WR","TE","K","DL","LB","DB": return Set([PositionNormalizer.normalize(slot)])
        case "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE": return Set(["RB","WR","TE"].map(PositionNormalizer.normalize))
        case "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX": return Set(["QB","RB","WR","TE"].map(PositionNormalizer.normalize))
        case "IDP": return Set(["DL","LB","DB"])
        default:
            if slot.uppercased().contains("IDP") { return Set(["DL","LB","DB"]) }
            return Set([PositionNormalizer.normalize(slot)])
        }
    }

    private func isIDPFlex(_ slot: String) -> Bool {
        let s = slot.uppercased()
        return s.contains("IDP") && s != "DL" && s != "LB" && s != "DB"
    }

    private func isEligible(_ c: (id: String, pos: String, altPos: [String], score: Double), allowed: Set<String>) -> Bool {
        let normBase = PositionNormalizer.normalize(c.pos)
        let normAlt = c.altPos.map { PositionNormalizer.normalize($0) }
        if allowed.contains(normBase) { return true }
        return !allowed.intersection(Set(normAlt)).isEmpty
    }

    private let offensiveFlexSlots: Set<String> = [
        "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE",
        "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX"
    ]

    private func expandSlots(_ config: [String: Int]) -> [String] {
        let sanitized = SlotUtils.sanitizeStartingLineupConfig(config)
        return sanitized.flatMap { Array(repeating: $0.key, count: $0.value) }
    }

    // Replicate the small statRow helper previously in MatchupView
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

    // Local helper to reverse record string like "W-L" -> "L-W" and "W-L-T" -> "L-W-T"
    private static func reverseRecordString(_ str: String) -> String {
        let parts = str.split(separator: "-")
        if parts.count == 2 {
            return "\(parts[1])-\(parts[0])"
        } else if parts.count == 3 {
            return "\(parts[1])-\(parts[0])-\(parts[2])"
        }
        return str
    }

    // Same logic as prior: read all-time H2H from league.allTimeOwnerStats
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
