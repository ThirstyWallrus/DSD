//
//  DefStatExpandedView.swift
//  DynastyStatDrop
//

import SwiftUI

struct DefStatExpandedView: View {
    @EnvironmentObject var appSelection: AppSelection
    // NEW: access to global player caches to resolve players not present in TeamStanding.roster
    @EnvironmentObject var leagueManager: SleeperLeagueManager

    @State private var showConsistencyInfo = false
    @State private var showEfficiencyInfo = false
    // NEW: show detail sheet for defensive position balance
    @State private var showDefBalanceDetail = false

    // Defensive positions
    private let defPositions: [String] = ["DL", "LB", "DB"]

    // Position color mapping (kept consistent with OffStat)
    private var positionColors: [String: Color] {
        [
            "QB": .red,
            "RB": .green,
            "WR": .blue,
            "TE": .yellow,
            "K": Color.purple,
            "DL": .orange,
            "LB": .purple,
            "DB": .pink
        ]
    }

    // MARK: - Team/League/Season State

    private var team: TeamStanding? { appSelection.selectedTeam }
    private var league: LeagueData? { appSelection.selectedLeague }
    private var isAllTime: Bool { appSelection.isAllTimeMode }
    private var aggregate: AggregatedOwnerStats? {
        guard isAllTime, let league, let team else { return nil }
        return league.allTimeOwnerStats?[team.ownerId]
    }

    // MARK: - Grade computation (defense-only)
    // Build TeamGradeComponents for teams in current league/season (or use all-time owner aggregates when available).
    // Use gradeTeamsDefense and populate TeamGradeComponents with defensive-specific fields.
    private var computedGrade: (grade: String, composite: Double)? {
        guard let lg = league else { return nil }
        let teamsToProcess: [TeamStanding] = {
            if !isAllTime, let season = lg.seasons.first(where: { $0.id == appSelection.selectedSeason }) {
                return season.teams
            }
            return lg.seasons.sorted { $0.id < $1.id }.last?.teams ?? lg.teams
        }()
        var comps: [TeamGradeComponents] = []
        for t in teamsToProcess {
            // Prefer aggregated owner stats in all-time mode
            let aggOwner: AggregatedOwnerStats? = {
                if isAllTime { return lg.allTimeOwnerStats?[t.ownerId] }
                return nil
            }()

            // Defensive-specific values to populate TeamGradeComponents correctly for defense-only grading
            let defPF: Double = {
                if isAllTime {
                    return aggOwner?.totalDefensivePointsFor ?? (t.defensivePointsFor ?? 0)
                }
                return t.defensivePointsFor ?? 0
            }()

            let defPPW: Double = {
                if isAllTime {
                    return aggOwner?.defensivePPW ?? (t.averageDefensivePPW ?? 0)
                }
                return t.averageDefensivePPW ?? t.teamPointsPerWeek
            }()

            // Overall mgmt — keep existing behavior (season/all-time fallback)
            let pf: Double = {
                if isAllTime { return aggOwner?.totalPointsFor ?? t.pointsFor }
                return t.pointsFor
            }()
            let mpf: Double = {
                if isAllTime { return aggOwner?.totalMaxPointsFor ?? t.maxPointsFor }
                return t.maxPointsFor
            }()
            let mgmt = (mpf > 0) ? (pf / mpf * 100) : (t.managementPercent)

            // Off/Def mgmt (keep previous logic)
            let offMgmt: Double = {
                if isAllTime {
                    if let agg = aggOwner, agg.totalMaxOffensivePointsFor > 0 {
                        return (agg.totalOffensivePointsFor / agg.totalMaxOffensivePointsFor) * 100
                    }
                    return t.offensiveManagementPercent ?? 0
                } else {
                    return t.offensiveManagementPercent ?? 0
                }
            }()

            let defMgmt: Double = {
                if isAllTime {
                    if let agg = aggOwner, agg.totalMaxDefensivePointsFor > 0 {
                        return (agg.totalDefensivePointsFor / agg.totalMaxDefensivePointsFor) * 100
                    }
                    return t.defensiveManagementPercent ?? 0
                } else {
                    return t.defensiveManagementPercent ?? 0
                }
            }()

            // Position averages (fallback to 0)
            let qb = (t.positionAverages?[PositionNormalizer.normalize("QB")] ?? 0)
            let rb = (t.positionAverages?[PositionNormalizer.normalize("RB")] ?? 0)
            let wr = (t.positionAverages?[PositionNormalizer.normalize("WR")] ?? 0)
            let te = (t.positionAverages?[PositionNormalizer.normalize("TE")] ?? 0)
            let k  = (t.positionAverages?[PositionNormalizer.normalize("K")]  ?? 0)
            let dl = (t.positionAverages?[PositionNormalizer.normalize("DL")] ?? 0)
            let lb = (t.positionAverages?[PositionNormalizer.normalize("LB")] ?? 0)
            let db = (t.positionAverages?[PositionNormalizer.normalize("DB")] ?? 0)

            let (w,l,ties) = TeamGradeComponents.parseRecord(t.winLossRecord)
            let recordPct = (w + l + ties) > 0 ? Double(w) / Double(max(1, w + l + ties)) : 0.0

            // IMPORTANT: For defense grading, set pointsFor = defensive points for and ppw = defensivePPW
            let comp = TeamGradeComponents(
                pointsFor: defPF,
                ppw: defPPW,
                mgmt: mgmt,
                offMgmt: offMgmt,
                defMgmt: defMgmt,
                recordPct: recordPct,
                qbPPW: qb,
                rbPPW: rb,
                wrPPW: wr,
                tePPW: te,
                kPPW: k,
                dlPPW: dl,
                lbPPW: lb,
                dbPPW: db,
                teamName: t.name,
                teamId: t.id
            )
            comps.append(comp)
        }

        // Use defense-specific grading helper
        let graded = gradeTeamsDefense(comps)
        if let team = team, let found = graded.first(where: { $0.0 == team.name }) {
            return (found.1, found.2)
        }
        return nil
    }

    // MARK: - Weeks to Include (Exclude Current Week if Incomplete)

    private var validWeeks: [Int] {
        guard let league, let team else { return [] }
        // For season mode, use the selected season
        if !isAllTime, let season = league.seasons.first(where: { $0.id == appSelection.selectedSeason }) {
            let allWeeks = season.matchupsByWeek?.keys.sorted() ?? []
            if let currentWeek = allWeeks.max(), allWeeks.count > 1 {
                return allWeeks.filter { $0 != currentWeek }
            }
            return allWeeks
        }
        // For all time mode, use the latest season's weeks (for continuity)
        if isAllTime {
            let latest = league.seasons.sorted { $0.id < $1.id }.last
            let allWeeks = latest?.matchupsByWeek?.keys.sorted() ?? []
            if let currentWeek = allWeeks.max(), allWeeks.count > 1 {
                return allWeeks.filter { $0 != currentWeek }
            }
            return allWeeks
        }
        return []
    }

    // MARK: - Authoritative week points helper
    // Returns mapping playerId -> points for the given team & week using:
    // 1) matchup.players_points if available for that week & roster entry (PREFERRED)
    //    - if matchup.starters exist: returns players_points filtered to starters only
    //    - else returns the full players_points mapping
    // 2) fallback to deduplicated roster.weeklyScores (prefer matchup_id match or highest points)
    private func authoritativePointsForWeek(team: TeamStanding, week: Int) -> [String: Double] {
        // Try matchup.players_points (authoritative)
        if let lg = league {
            // pick season (selected or latest for All Time)
            let season = (!isAllTime)
                ? lg.seasons.first(where: { $0.id == appSelection.selectedSeason })
                : lg.seasons.sorted { $0.id < $1.id }.last
            if let season {
                if let entries = season.matchupsByWeek?[week],
                   let rosterIdInt = Int(team.id),
                   let myEntry = entries.first(where: { $0.roster_id == rosterIdInt }),
                   let playersPoints = myEntry.players_points,
                   !playersPoints.isEmpty {
                    // If starters present, return players_points filtered to starters only
                    if let starters = myEntry.starters, !starters.isEmpty {
                        var map: [String: Double] = [:]
                        for pid in starters {
                            if let p = playersPoints[pid] {
                                map[pid] = p
                            } else {
                                // starter not present in players_points -> treat as 0.0
                                map[pid] = 0.0
                            }
                        }
                        return map
                    } else {
                        return playersPoints.mapValues { $0 }
                    }
                }
                // else fall through to roster fallback
            }
        }
        // Fallback: build mapping from roster.weeklyScores but deduplicate per player/week
        var result: [String: Double] = [:]
        // If we can find the matchup_id for this team/week, prefer that matchup_id when picking entries
        var preferredMatchupId: Int? = nil
        if let lg = league {
            let season = (!isAllTime)
                ? lg.seasons.first(where: { $0.id == appSelection.selectedSeason })
                : lg.seasons.sorted { $0.id < $1.id }.last
            if let season, let entries = season.matchupsByWeek?[week], let rosterIdInt = Int(team.id) {
                if let myEntry = entries.first(where: { $0.roster_id == rosterIdInt }) {
                    preferredMatchupId = myEntry.matchup_id
                }
            }
        }
        // For each player on roster, collect weeklyScores for this week and pick one entry
        for player in team.roster {
            let scores = player.weeklyScores.filter { $0.week == week }
            if scores.isEmpty { continue }
            // If a preferredMatchupId exists, prefer an entry with that matchup_id
            if let mid = preferredMatchupId, let matched = scores.first(where: { $0.matchup_id == mid }) {
                result[player.id] = matched.points_half_ppr ?? matched.points
            } else {
                // otherwise pick the entry with max points to avoid double-counting duplicates
                if let best = scores.max(by: { ($0.points_half_ppr ?? $0.points) < ($1.points_half_ppr ?? $1.points) }) {
                    result[player.id] = best.points_half_ppr ?? best.points
                }
            }
        }
        return result
    }

    // MARK: - Stacked Bar Chart Data (defense)
    private var stackedBarWeekData: [StackedBarWeeklyChart.WeekBarData] {
        guard let team else { return [] }
        let sortedWeeks = validWeeks
        return sortedWeeks.map { week in
            let playerPoints = authoritativePointsForWeek(team: team, week: week)
            var posSums: [String: Double] = [:]
            var unresolvedIds: [String] = []
            for (pid, pts) in playerPoints {
                // Prefer position from team roster if present
                if let player = team.roster.first(where: { $0.id == pid }) {
                    let norm = PositionNormalizer.normalize(player.position)
                    if ["DL","LB","DB"].contains(norm) {
                        posSums[norm, default: 0.0] += pts
                    } else {
                        // ignore offensive positions for defense chart
                    }
                } else if let raw = leagueManager.playerCache?[pid] ?? leagueManager.allPlayers[pid] {
                    let norm = PositionNormalizer.normalize(raw.position ?? "UNK")
                    if ["DL","LB","DB"].contains(norm) {
                        posSums[norm, default: 0.0] += pts
                    } else {
                        // player's resolved position is offensive -> ignore for defense segments
                    }
                } else {
                    // Fallback attribution to a defensive bucket to avoid dropping totals
                    posSums["DL", default: 0.0] += pts
                    unresolvedIds.append(pid)
                }
            }
            // Ensure positions exist in dict (0 default)
            let segments = defPositions.map { pos -> StackedBarWeeklyChart.WeekBarData.Segment in
                let norm = PositionNormalizer.normalize(pos)
                return StackedBarWeeklyChart.WeekBarData.Segment(
                    id: pos,
                    position: norm,
                    value: posSums[norm] ?? 0
                )
            }
#if DEBUG
            // Helpful debug print for developers when running locally
            if !unresolvedIds.isEmpty {
                let sample = unresolvedIds.prefix(6).joined(separator: ", ")
                print("[DEBUG][DefStatExpandedView] week \(week) unresolved ids (sample): \(sample)")
            }
#endif
            return StackedBarWeeklyChart.WeekBarData(id: week, segments: segments)
        }
    }

    // Helper: check if a PlayerWeeklyScore's player matches the target normalized position
    private func matchesNormalizedPosition(_ score: PlayerWeeklyScore, pos: String) -> Bool {
        guard let team = team else { return false }
        if let player = team.roster.first(where: { $0.id == score.player_id }) {
            return PositionNormalizer.normalize(player.position) == PositionNormalizer.normalize(pos)
        }
        // Try global caches (covers started players later dropped from roster)
        if let raw = leagueManager.playerCache?[score.player_id] ?? leagueManager.allPlayers[score.player_id] {
            return PositionNormalizer.normalize(raw.position ?? "") == PositionNormalizer.normalize(pos)
        }
        return false
    }

    // Derived weekly totals (actual roster total per week)
    private var sideWeeklyPoints: [Double] {
        stackedBarWeekData.map { $0.total }
    }

    // Use non-zero completed weeks for averages to avoid dividing by future zero weeks.
    private var sideWeeklyPointsNonZero: [Double] {
        let nonZero = sideWeeklyPoints.filter { $0 > 0.0 }
        // Fallback: if nothing found in stacked data, use team's recorded weeklyActualLineupPoints if available
        if nonZero.isEmpty, let team = team, let weekly = team.weeklyActualLineupPoints {
            let vals = weekly.keys.sorted().map { weekly[$0] ?? 0.0 }.filter { $0 > 0.0 }
            if !vals.isEmpty { return vals }
        }
        return nonZero
    }

    private var weeksPlayed: Int { sideWeeklyPointsNonZero.count }

    private var last3Avg: Double {
        guard weeksPlayed > 0 else { return 0 }
        let recent = sideWeeklyPointsNonZero.suffix(3)
        return recent.reduce(0,+) / Double(min(3, recent.count))
    }

    // seasonAvg (DPPW) computed from non-zero completed weeks, fallback to aggregates/team stored values
    private var seasonAvg: Double {
        // Prefer canonical value from DSDStatsService which applies the same "exclude current week" rules.
        if let t = team {
            if let stored = DSDStatsService.shared.stat(for: t, type: .averageDefensivePPW, league: league, selectedSeason: appSelection.selectedSeason) as? Double {
                if stored > 0 { return stored }
            }
        }
        if let agg = aggregate { return agg.defensivePPW }
        // Fallback: computed average from authoritative weekly totals (non-zero completed weeks)
        if weeksPlayed > 0 {
            return sideWeeklyPointsNonZero.reduce(0, +) / Double(weeksPlayed)
        }
        return 0
    }
    private var formDelta: Double { last3Avg - seasonAvg }
    private var formDeltaColor: Color {
        if formDelta > 2 { return .green }
        if formDelta < -2 { return .red }
        return .yellow
    }

    // MARK: - Defensive Points and Management %

    // Recompute DPF from the exact same weekly totals used to compute DPPW.
    private var sidePointsComputed: Double {
        // Prefer canonical DPF from DSDStatsService if available (ensures same logic everywhere).
        if let t = team {
            if let val = DSDStatsService.shared.stat(for: t, type: .defensivePointsFor, league: league, selectedSeason: appSelection.selectedSeason) as? Double {
                if val > 0 { return val }
            }
        }
        // Fallback to stacked weekly totals computed here (authoritative week mapping)
        let sum = stackedBarWeekData.map { $0.total }.reduce(0, +)
        if sum > 0 { return sum }
        if let agg = aggregate { return agg.totalDefensivePointsFor }
        return team?.defensivePointsFor ?? 0
    }

    // Expose sidePoints (prefer aggregate in All Time, then canonical team stat via DSDStatsService)
    private var sidePoints: Double {
        if let agg = aggregate { return agg.totalDefensivePointsFor }
        if let t = team {
            if let val = DSDStatsService.shared.stat(for: t, type: .defensivePointsFor, league: league, selectedSeason: appSelection.selectedSeason) as? Double {
                return val
            }
        }
        return sidePointsComputed
    }
    private var sideMaxPoints: Double {
        if let agg = aggregate { return agg.totalMaxDefensivePointsFor }
        if let t = team {
            if let val = DSDStatsService.shared.stat(for: t, type: .maxDefensivePointsFor, league: league, selectedSeason: appSelection.selectedSeason) as? Double {
                return val
            }
        }
        return team?.maxDefensivePointsFor ?? 0
    }
    private var managementPercent: Double {
        guard sideMaxPoints > 0 else { return 0 }
        return (sidePoints / sideMaxPoints) * 100
    }

    // MARK: - Consistency (StdDev)

    private var stdDev: Double {
        guard weeksPlayed > 1 else { return 0 }
        let mean = seasonAvg
        let variance = sideWeeklyPointsNonZero.reduce(0) { $0 + pow($1 - mean, 2) } / Double(weeksPlayed)
        return sqrt(variance)
    }
    private var consistencyDescriptor: String {
        switch stdDev {
        case 0..<15: return "Steady"
        case 15..<35: return "Average"
        case 35..<55: return "Swingy"
        default: return "Boom-Bust"
        }
    }

    // MARK: - Strengths/Weaknesses

    private var strengths: [String] {
        if let agg = aggregate {
            var arr: [String] = []
            if agg.defensiveManagementPercent >= 75 { arr.append("Efficient Usage") }
            if stdDev < 15 && weeksPlayed >= 4 { arr.append("Reliable Output") }
            if arr.isEmpty { arr.append("Developing Unit") }
            return arr
        }
        var arr: [String] = []
        if managementPercent >= 75 { arr.append("Efficient Usage") }
        if stdDev < 15 && weeksPlayed >= 4 { arr.append("Reliable Output") }
        if arr.isEmpty { arr.append("Developing Unit") }
        return arr
    }
    private var weaknesses: [String] {
        if let agg = aggregate {
            var arr: [String] = []
            if agg.defensiveManagementPercent < 55 { arr.append("Usage Inefficiency") }
            if stdDev > 40 { arr.append("Volatility") }
            if weeksPlayed >= 3 && last3Avg < seasonAvg - 5 { arr.append("Recent Dip") }
            if arr.isEmpty { arr.append("No Major Weakness") }
            return arr
        }
        var arr: [String] = []
        if managementPercent < 55 { arr.append("Usage Inefficiency") }
        if stdDev > 40 { arr.append("Volatility") }
        if weeksPlayed >= 3 && last3Avg < seasonAvg - 5 { arr.append("Recent Dip") }
        if arr.isEmpty { arr.append("No Major Weakness") }
        return arr
    }

    // MARK: - UI: Top Title + 4 stat bubbles (Grade, DPF, DMPF, DPPW)
    /// A generic stat bubble builder (copied from OffStatExpandedView for parity).
    @ViewBuilder
    private func statBubble<Content: View, Caption: View>(width: CGFloat, height: CGFloat, @ViewBuilder content: @escaping () -> Content, @ViewBuilder caption: @escaping () -> Caption) -> some View {
        VStack(spacing: 6) {
            ZStack {
                // Slight glass/bubble effect background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.03))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors: [Color.white.opacity(0.02), Color.white.opacity(0.01)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.45), radius: 6, x: 0, y: 2)
                    .frame(width: width, height: height)
                    .overlay(
                        // subtle specular shine
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.0)]), startPoint: .top, endPoint: .center))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    )
                content()
            }
            caption()
        }
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Title + bubble row (grade, DPF, DMPF, DPPW)
            VStack(spacing: 8) {
                // Title uses selected team name like TeamStatExpandedView / OffStatExpandedView
                let viewerName: String = {
                    if let team = team {
                        return team.name
                    }
                    if let uname = appSelection.currentUsername, !uname.isEmpty { return uname }
                    return appSelection.userTeam.isEmpty ? "Team" : appSelection.userTeam
                }()
                Text("\(viewerName)'s Defense Drop")
                    .font(.custom("Phatt", size: 20))
                    .bold()
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                GeometryReader { geo in
                    let horizontalPadding: CGFloat = 8
                    let spacing: CGFloat = 10
                    let itemCount: CGFloat = 4 // Grade, DPF, DMPF, DPPW
                    let available = max(0, geo.size.width - horizontalPadding * 2 - (spacing * (itemCount - 1)))
                    let bubbleSize = min(72, floor(available / itemCount))
                    HStack(spacing: spacing) {
                        // 1) Grade
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            if let g = computedGrade?.grade {
                                ElectrifiedGrade(grade: g, fontSize: min(28, bubbleSize * 0.6))
                                    .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78)
                            } else {
                                Text("--")
                                    .font(.system(size: bubbleSize * 0.32, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78)
                            }
                        } caption: {
                            Text("Grade")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        // 2) DPF (Defensive Points For)
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            Text(String(format: "%.2f", sidePoints))
                                .font(.system(size: bubbleSize * 0.30, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78)
                        } caption: {
                            Text("DPF")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        // 3) DMPF (Defensive Max Points For)
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            Text(String(format: "%.2f", sideMaxPoints))
                                .font(.system(size: bubbleSize * 0.30, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78)
                        } caption: {
                            Text("DMPF")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        // 4) DPPW (Defensive PPW)
                        // Uses seasonAvg computed from non-zero completed weeks derived from the same weekly totals.
                        statBubble(width: bubbleSize, height: bubbleSize) {
                            Text(String(format: "%.2f", seasonAvg))
                                .font(.system(size: bubbleSize * 0.36, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                                .frame(width: bubbleSize * 0.78, height: bubbleSize * 0.78, alignment: .center)
                        } caption: {
                            Text("DPPW")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .frame(width: geo.size.width, height: bubbleSize + 26, alignment: .center)
                }
                .frame(height: 96)
            }

            sectionHeader("Defensive Weekly Trend")
            // Chart: Excludes current week if incomplete, uses normalized positions
            StackedBarWeeklyChart(
                weekBars: stackedBarWeekData,
                positionColors: positionColors,
                showPositions: Set(defPositions),
                gridIncrement: 25,
                barSpacing: 4,
                tooltipFont: .caption2.bold(),
                showWeekLabels: true,
                aggregateToOffDef: false,
                showAggregateLegend: false,
                showOffensePositionsLegend: false,
                showDefensePositionsLegend: true   // show DL/LB/DB
            )
            .frame(height: 140)

            sectionHeader("Lineup Efficiency")
            lineupEfficiency

            // NEW: Defensive Efficiency Spotlight (position-level Mgmt% gauges)
            sectionHeader("Defensive Efficiency Spotlight")
            defensiveEfficiencySpotlight

            sectionHeader("Recent Form")
            recentForm

            sectionHeader("Consistency Score")
            consistencyRow

            // Strengths / Weaknesses sections removed per request.
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .sheet(isPresented: $showConsistencyInfo) {
            ConsistencyInfoSheet(stdDev: stdDev, descriptor: consistencyDescriptor)
                .presentationDetents([.fraction(0.40)])
        }
        // Present the DefensiveBalanceInfoSheet when user taps the center Balance element
        .sheet(isPresented: $showDefBalanceDetail) {
            DefensiveBalanceInfoSheet(
                positionPercents: positionMgmtPercents,
                balancePercent: positionBalancePercent,
                tagline: generatePositionBalanceTagline()
            )
            .presentationDetents([PresentationDetent.fraction(0.40)])
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.yellow)
            .padding(.top, 4)
    }

    // REPLACED: The old statBlock + EfficiencyBar combo is now replaced by a ManagementPill identical to OffStatExpandedView,
    // but showing the defense-only Mgmt% (managementPercent), with delta computed by priorManagementPercent.
    private var lineupEfficiency: some View {
        VStack(alignment: .leading, spacing: 10) {
            ManagementPill(
                ratio: max(0.0, min(1.0, managementPercent / 100.0)),
                mgmtPercent: managementPercent,
                delta: managementDelta,
                mgmtColor: mgmtColor(for: managementPercent)
            )
            .padding(.vertical, 2)

            // Removed info button per request (no popup for Mgmt%).
        }
    }

    // MARK: - Defensive Efficiency Spotlight helpers

    // Returns per-position mgmt% using DSDStatsService (season vs all-time)
    private var positionMgmtPercents: [String: Double] {
        guard let team = team else { return [:] }
        var dict: [String: Double] = [:]
        for pos in defPositions {
            let mgmt: Double
            if isAllTime {
                if let agg = aggregate {
                    mgmt = DSDStatsService.shared.managementPercentForPosition(allTimeAgg: agg, position: pos)
                } else {
                    // Fallback to TeamStanding field if present
                    mgmt = team.positionAverages?[PositionNormalizer.normalize(pos)] ?? 0
                }
            } else {
                mgmt = DSDStatsService.shared.managementPercentForPosition(
                    team: team,
                    position: pos,
                    league: league,
                    selectedSeason: appSelection.selectedSeason,
                    leagueManager: leagueManager
                )
            }
            dict[pos] = mgmt
        }
        return dict
    }

    // Compute coefficient-of-variation based balance percent for the three defense positions.
    // balancePercent = (stdDev(mgmtPercents) / mean(mgmtPercents)) * 100
    // Lower = more balanced. We clamp and handle zero mean gracefully.
    private var positionBalancePercent: Double {
        let vals = defPositions.compactMap { positionMgmtPercents[$0] }
        guard !vals.isEmpty else { return 0 }
        let mean = vals.reduce(0, +) / Double(vals.count)
        guard mean > 0 else { return 0 }
        let variance = vals.reduce(0) { $0 + pow($1 - mean, 2) } / Double(vals.count)
        let sd = sqrt(variance)
        return (sd / mean) * 100
    }

    // Tagline generator for the position balance
    private func generatePositionBalanceTagline() -> String {
        let balance = positionBalancePercent
        if balance < 8 { return "Well-balanced front — usage distributed among DL/LB/DB." }
        if balance < 16 { return "Some positional skew — one group picks up more of the load." }
        // Determine heavy positions (significantly above mean)
        let mgmts = positionMgmtPercents
        let mean = mgmts.values.reduce(0, +) / Double(max(1, mgmts.count))
        let heavy = mgmts.filter { $0.value > mean + 10 }.map { $0.key }
        if !heavy.isEmpty {
            return "Skewed towards: \(heavy.joined(separator: ", ")). Consider balancing matchups."
        }
        return "Unbalanced — defense relies heavily on specific position groups."
    }

    // View: Defensive Efficiency Spotlight
    // Layout:
    // - 3 columns (DL, LB, DB) with gauges; center (LB) includes balance center tappable to show detail sheet.
    private var defensiveEfficiencySpotlight: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let spacing: CGFloat = 12
            let columnWidth = max(80, (totalWidth - spacing * 2) / 3)

            HStack(alignment: .top, spacing: spacing) {
                // LEFT: DL
                VStack(spacing: 12) {
                    positionGauge(position: "DL", percent: positionMgmtPercents["DL"] ?? 0)
                    Spacer()
                }
                .frame(width: columnWidth, alignment: .center)

                // CENTER: LB + Balance
                VStack(spacing: 12) {
                    positionGauge(position: "LB", percent: positionMgmtPercents["LB"] ?? 0)
                    Spacer()
                    VStack(spacing: 6) {
                        Text("⚖️ \(String(format: "%.2f%%", positionBalancePercent))")
                            .font(.subheadline).bold()
                            .foregroundColor(positionBalancePercent < 8 ? .green : (positionBalancePercent < 16 ? .yellow : .red))
                            .accessibilityLabel("Defensive balance")
                            .accessibilityValue(String(format: "%.2f percent balance score", positionBalancePercent))
                        Text(generatePositionBalanceTagline())
                            .font(.caption2)
                            .foregroundColor(.yellow)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: columnWidth * 0.95)
                    }
                    .onTapGesture {
                        showDefBalanceDetail = true
                    }
                }
                .frame(width: columnWidth, alignment: .center)

                // RIGHT: DB
                VStack(spacing: 12) {
                    positionGauge(position: "DB", percent: positionMgmtPercents["DB"] ?? 0)
                    Spacer()
                }
                .frame(width: columnWidth, alignment: .center)
            }
            .frame(width: totalWidth, height: geo.size.height)
        }
        .frame(height: 170)
        .padding(.vertical, 4)
    }

    // Single position gauge builder (matches OffStat's gauge style)
    @ViewBuilder
    private func positionGauge(position: String, percent: Double) -> some View {
        VStack(spacing: 6) {
            Gauge(value: max(0.0, min(1.0, percent/100.0))) {
                EmptyView()
            } currentValueLabel: {
                Text(String(format: "%.2f%%", percent))
                    .font(.caption2).bold()
                    .foregroundColor(.white)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [Color(red: 0.7, green: 0.0, blue: 0.0), Color(red: 0.0, green: 1.0, blue: 0.0)]))
            .frame(width: 56, height: 56)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(position) Usage Efficiency")
            .accessibilityValue(String(format: "%.2f percent", percent))

            // Caption shows position + small color dot
            HStack(spacing: 6) {
                Circle().fill(positionColors[position] ?? .white).frame(width: 8, height: 8)
                Text(position)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: 90)
    }

    // MARK: - Remaining UI (recentForm, consistencyRow, small helpers)

    private var recentForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            let arrow = formDelta > 0.5 ? "↑" : (formDelta < -0.5 ? "↓" : "→")
            HStack(alignment: .top, spacing: 12) {
                formStatBlock("Last 3", last3Avg)
                formStatBlock("Season", seasonAvg)
                formDeltaBlock(arrow: arrow, delta: formDelta)
            }
            Text("Compares recent 3 weeks to season average for this unit.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))
        }
    }

    private var consistencyRow: some View {
        HStack {
            HStack(spacing: 8) {
                Text(consistencyDescriptor)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Button { showConsistencyInfo = true } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            Spacer()
            ConsistencyMeter(stdDev: stdDev)
                .frame(width: 110, height: 12)
        }
    }

    private func statBlock(title: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.2f", value))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func statBlockPercent(title: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.1f%%", value))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func formStatBlock(_ name: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.2f", value))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Text(name)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func formDeltaBlock(arrow: String, delta: Double) -> some View {
        VStack(spacing: 2) {
            Text("\(arrow) \(String(format: "%+.2f", delta))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(formDeltaColor)
            Text("Delta")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    // Small components (copied/consistent with TeamStat)
    private struct ConsistencyMeter: View {
        let stdDev: Double
        private var norm: Double { max(0, min(1, stdDev / 60.0)) }
        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .yellow, .orange, .red],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * norm)
                }
            }
            .clipShape(Capsule())
        }
    }

    private struct Pill: View {
        let text: String
        let bg: Color
        let stroke: Color
        var body: some View {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(bg))
                .overlay(Capsule().stroke(stroke.opacity(0.7), lineWidth: 1))
                .foregroundColor(.white)
        }
    }

    // MANAGEMENT PILL: closely matches TeamStatExpandedView's pill but applied to defense-only mgmt%
    private struct ManagementPill: View {
        let ratio: Double       // 0.0 - 1.0
        let mgmtPercent: Double // 0-100
        let delta: Double       // mgmt change since prior week (percentage points)
        let mgmtColor: Color

        private let pillHeight: CGFloat = 24
        private let dotSize: CGFloat = 10
        private let horizontalPadding: CGFloat = 8

        var body: some View {
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: pillHeight/2)
                            .fill(LinearGradient(
                                colors: [Color(red: 0.6, green: 0.0, blue: 0.0), Color(red: 0.9, green: 0.95, blue: 0.0), Color.green],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(height: pillHeight)

                        // subtle overlay to keep pill "filled" look consistent
                        RoundedRectangle(cornerRadius: pillHeight/2)
                            .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
                            .frame(height: pillHeight)

                        // Dot marker
                        let x = clampedX(for: geo.size.width)
                        Circle()
                            .fill(Color.white)
                            .frame(width: dotSize, height: dotSize)
                            .shadow(color: Color.black.opacity(0.6), radius: 2, x: 0, y: 1)
                            .position(x: x, y: pillHeight/2)
                    }
                }
                .frame(height: pillHeight)

                // Percentage and delta aligned under dot marker
                GeometryReader { geo in
                    let x = clampedX(for: geo.size.width)
                    ZStack {
                        // full-width clear background so ZStack fills parent and we can use .position
                        Color.clear
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%.2f%%", mgmtPercent))
                                .font(.subheadline).bold()
                                .foregroundColor(mgmtColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            // Delta to right in smaller font
                            Text(deltaText)
                                .font(.caption2)
                                .foregroundColor(delta >= 0 ? Color.green : Color.red)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .padding(.top, 2)
                        }
                        .fixedSize()                 // keep intrinsic width, do not compress
                        .position(x: x, y: 11)      // center the HStack at the dot's x and mid of the 22pt row
                    }
                }
                .frame(height: 22)
            }
        }

        private func clampedX(for totalWidth: CGFloat) -> CGFloat {
            // leave horizontalPadding from edges
            let leftBound = horizontalPadding + dotSize/2
            let rightBound = max(leftBound, totalWidth - horizontalPadding - dotSize/2)
            let raw = totalWidth * CGFloat(ratio)
            return min(max(raw, leftBound), rightBound)
        }

        // Option C: show signed absolute percentage-point difference with "pp" suffix (e.g. "+0.71 pp", "-0.61 pp")
        private var deltaText: String {
            if delta == 0 { return "0.00 pp" }
            return String(format: "%+.2f pp", delta)
        }
    }

    // New helpers to compute prior management percent and delta (mirror OffStat implementation)
    private var latestValidWeekTotal: Double? {
        guard let team else { return nil }
        let pairs = zip(validWeeks, stackedBarWeekData)
        if let last = pairs.reversed().first(where: { $0.1.total > 0 }) {
            return last.1.total
        }
        if let weekly = team.weeklyActualLineupPoints {
            let last = weekly.keys.sorted().reversed().first(where: { (weekly[$0] ?? 0) > 0 })
            if let wk = last { return weekly[wk] }
        }
        return nil
    }

    private func findLatestValidWeek() -> Int? {
        guard let team else { return nil }
        let pairs = zip(validWeeks, stackedBarWeekData)
        if let last = pairs.reversed().first(where: { $0.1.total > 0 }) {
            return last.0
        }
        if let weekly = team.weeklyActualLineupPoints {
            let lastKey = weekly.keys.sorted().reversed().first(where: { (weekly[$0] ?? 0) > 0 })
            if let wk = lastKey { return wk }
        }
        return nil
    }

    /// Compute the optimal (max) points for a given week by greedily selecting the highest-scoring eligible player for each lineup slot.
    /// Returns nil if computation cannot be performed (e.g., no weekly scores available).
    private func computeWeekMax(for week: Int) -> Double? {
        guard let team = team else { return nil }
        let roster = team.roster
        // Determine lineup slots
        let lineupConfig = team.lineupConfig ?? inferredLineupConfig(from: roster)
        let slots = expandSlots(lineupConfig: lineupConfig)
        if slots.isEmpty { return nil }
        // Build candidates from roster (player id -> candidate)
        struct Candidate {
            let playerId: String
            let basePos: String
            let fantasy: [String]
            let points: Double
        }
        var candidates: [Candidate] = []
        for p in roster {
            if let ws = p.weeklyScores.first(where: { $0.week == week }) {
                let pts = ws.points_half_ppr ?? ws.points
                candidates.append(Candidate(playerId: p.id, basePos: p.position, fantasy: p.altPositions ?? [], points: pts))
            }
        }
        if candidates.isEmpty { return nil } // cannot compute
        var used = Set<String>()
        var weekMax: Double = 0.0
        // Greedy: for each slot pick highest points candidate eligible and not used
        for slot in slots {
            let allowed = allowedPositions(for: slot)
            let pick = candidates
                .filter { !used.contains($0.playerId) && isEligible(basePos: $0.basePos, fantasy: $0.fantasy, allowed: allowed) }
                .max(by: { $0.points < $1.points })
            if let p = pick {
                used.insert(p.playerId)
                weekMax += p.points
            }
        }
        // If we managed to fill at least one slot, return weekMax (0 could be legitimate).
        return weekMax
    }

    // Prior management percent approximated by removing the latest completed week's contribution.
    // Exclude the most recent week from BOTH numerator (points) and denominator (season max) when possible.
    private var priorManagementPercent: Double {
        guard let last = latestValidWeekTotal else { return 0 }
        guard sideMaxPoints > 0 else { return 0 }
        let priorPoints = max(0, sidePoints - last)
        guard let lastWeek = findLatestValidWeek() else {
            // can't find week index — fallback to original behavior
            return (priorPoints / sideMaxPoints) * 100
        }
        if let lastWeekMax = computeWeekMax(for: lastWeek), lastWeekMax > 0 {
            let priorMax = sideMaxPoints - lastWeekMax
            if priorMax > 0 {
                return (priorPoints / priorMax) * 100
            } else {
                return (priorPoints / sideMaxPoints) * 100
            }
        } else {
            return (priorPoints / sideMaxPoints) * 100
        }
    }

    private var managementDelta: Double {
        managementPercent - priorManagementPercent
    }

    // Helper to determine mgmt color (attempt to match existing MgmtColor semantics)
    private func mgmtColor(for pct: Double) -> Color {
        // Reasonable mapping: >75 green, 60-75 yellow, <60 red
        switch pct {
        case let x where x >= 75: return .green
        case let x where x >= 60: return .yellow
        default: return .red
        }
    }

    // Helper utilities reused
    private func inferredLineupConfig(from roster: [Player]) -> [String: Int] {
        var counts: [String:Int] = [:]
        for p in roster {
            // Normalize position for starter slot assignment
            let normalized = PositionNormalizer.normalize(p.position)
            counts[normalized, default: 0] += 1
        }
        return counts.mapValues { min($0, 3) }
    }
    private func expandSlots(lineupConfig: [String:Int]) -> [String] {
        lineupConfig.flatMap { Array(repeating: $0.key, count: $0.value) }
    }
    private func allowedPositions(for slot: String) -> Set<String> {
        switch slot.uppercased() {
        case "QB","RB","WR","TE","K","DL","LB","DB": return [slot.uppercased()]
        case "FLEX","WRRB","WRRBTE","WRRB_TE","RBWR","RBWRTE": return ["RB","WR","TE"]
        case "SUPER_FLEX","QBRBWRTE","QBRBWR","QBSF","SFLX": return ["QB","RB","WR","TE"]
        case "IDP": return ["DL","LB","DB"]
        default:
            if slot.uppercased().contains("IDP") { return ["DL","LB","DB"] }
            return [slot.uppercased()]
        }
    }
    private func isEligible(basePos: String, fantasy: [String], allowed: Set<String>) -> Bool {
        let normalizedAllowed = Set(allowed.map { PositionNormalizer.normalize($0) })
        let candidates = ([basePos] + fantasy).map { PositionNormalizer.normalize($0) }
        return candidates.contains(where: { normalizedAllowed.contains($0) })
    }

    // Small components (copied/consistent with TeamStat)
    private struct EfficiencyBar: View {
        let ratio: Double
        let height: CGFloat
        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height/2)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: height/2)
                        .fill(LinearGradient(colors: [.red, .orange, .yellow, .green],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, min(geo.size.width, geo.size.width * ratio)))
                        .animation(.easeInOut(duration: 0.5), value: ratio)
                }
            }
        }
    }

    // MARK: - Defensive Balance Detail Sheet (use shared DefensiveBalanceInfoSheet in project)
    // NOTE: The concrete sheet implementation lives in DefensiveBalanceInfoSheet.swift (shared).
    // We intentionally present that shared view above in the .sheet presentation to avoid duplicate definitions.

    // Reuse existing EfficiencyBar (kept for consistency but not used in lineupEfficiency anymore)
    // (Already declared above)

    // Helper: check if a PlayerWeeklyScore's player matches the target normalized position
    // (Already implemented above)
}
