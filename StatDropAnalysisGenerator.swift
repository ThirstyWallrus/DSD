//
//  StatDropAnalysisGenerator.swift
//  DynastyStatDrop
//
//  AI-powered, personality-driven stat drop generator.
//  Supports multiple personalities and context-specific analysis (team, offense, defense, full).
//
//  ENHANCEMENTS (v2):
//  - Deeper analysis: Incorporate more stats (position PPW, individual PPW, league comparisons, management breakdowns, records, highs/lows, rivalries).
//  - Personable & comical: Tailor language per personality with puns, exaggerations, motivational quips, sarcasm.
//  - Robustness: Dynamic templates with conditional logic for highs/lows, comparisons; use all available TeamStanding & AggregatedOwnerStats fields.
//  - Creative originality: Vary sentence structures, add unique flair (e.g., analogies, pop culture refs for hype/snarky).
//  - Structure: Break into helpers for stat extraction, phrase building, and assembly.
//  - Fallbacks: Graceful handling for missing data.
//  - Length: FullTeam ~300-500 words; Cards ~100-200 words for brevity.
//  - ADDED: View-specific contexts (.myTeam, .myLeague, .matchup) and matchup/opponent persistence keys.
//  - ADDED: "Look Ahead" / predictions highlighted and personality-flavored.
//  - NOTE: This file is self-contained and integrates with existing StatDropAnalysisBox usage in views.
//          Some views pass `opponent` and `explicitWeek` — StatDropPersistence.getOrGenerateStatDrop now accepts those optional params.

import Foundation
import SwiftUI

private let offensivePositions: Set<String> = ["QB", "RB", "WR", "TE", "K"]
private let defensivePositions: Set<String> = ["DL", "LB", "DB"]
private let offensiveFlexSlots: Set<String> = ["FLEX", "WRRB", "WRRBTE", "WRRB_TE", "RBWR", "RBWRTE", "SUPER_FLEX", "QBRBWRTE", "QBRBWR", "QBSF", "SFLX"]

// MARK: - Stat Drop Personality (Unchanged)

enum StatDropPersonality: String, CaseIterable, Identifiable, Codable {
    case classicESPN
    case hypeMan
    case snarkyAnalyst
    case oldSchoolRadio
    case statGeek
    case motivationalCoach
    case britishCommentator
    case localNews
    case dramatic
    case robotAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classicESPN: return "Classic ESPN Anchor"
        case .hypeMan: return "Hype Man"
        case .snarkyAnalyst: return "Snarky Analyst"
        case .oldSchoolRadio: return "Old School Radio"
        case .statGeek: return "Stat Geek"
        case .motivationalCoach: return "Motivational Coach"
        case .britishCommentator: return "British Commentator"
        case .localNews: return "Local News"
        case .dramatic: return "Overly Dramatic"
        case .robotAI: return "Robot AI"
        }
    }

    var description: String {
        switch self {
        case .classicESPN: return "Professional, witty, classic sports banter."
        case .hypeMan: return "High energy, hype, and a touch of swagger."
        case .snarkyAnalyst: return "Sarcastic, dry humor, loves a good roast."
        case .oldSchoolRadio: return "Earnest, vintage, 1950s radio vibes."
        case .statGeek: return "Obscure stats and fun trivia galore."
        case .motivationalCoach: return "Pep talks, tough love, and inspiration."
        case .britishCommentator: return "Polite, understated, dry wordplay."
        case .localNews: return "Folksy, small-town charm and puns."
        case .dramatic: return "Everything is epic, even your kicker."
        case .robotAI: return "Deadpan, literal, and occasionally glitchy."
        }
    }
}

// MARK: - Stat Drop Context (EXTENDED)

enum StatDropContext: String, Codable {
    case fullTeam    // Full, long-form analysis (MyTeamView, "newspaper")
    case team        // Team-focused, brief (Team Card)
    case offense     // Offense-focused, brief (Offense Card)
    case defense     // Defense-focused, brief (Defense Card)
    // NEW view-specific contexts
    case myTeam      // MyTeamView — owner-focused
    case myLeague    // MyLeagueView — league-focused
    case matchup     // MatchupView — head-to-head per week
}

// MARK: - Focus Enum

enum Focus {
    case offense
    case defense
}

// MARK: - Candidate Struct

struct Candidate {
    let basePos: String
    let fantasy: [String]
    let points: Double
}

// MARK: - TeamStats Struct

struct TeamStats {
    let pointsFor: Double
    let maxPointsFor: Double
    let managementPercent: Double
    let ppw: Double
    let leagueAvgPpw: Double
    let record: String
    let offensivePointsFor: Double
    let maxOffensivePointsFor: Double
    let offensiveManagementPercent: Double
    let offensivePPW: Double
    let defensivePointsFor: Double
    let maxDefensivePointsFor: Double
    let defensiveManagementPercent: Double
    let defensivePPW: Double
    let positionAverages: [String: Double]
    let offensiveStrengths: [String]?
    let offensiveWeaknesses: [String]?
    let defensiveStrengths: [String]?
    let defensiveWeaknesses: [String]?
    let strengths: [String]?
    let weaknesses: [String]?
    let leagueStanding: Int
}

// MARK: - PreviousWeekStats Struct

struct PreviousWeekStats {
    let week: Int
    let actual: Double
    let max: Double
    let mgmt: Double
    let offActual: Double
    let offMax: Double
    let offMgmt: Double
    let defActual: Double
    let defMax: Double
    let defMgmt: Double
    let posSums: [String: Double]
    let leagueRank: Int
    let numTeams: Int

    var topPos: (String, Double)? { posSums.max { $0.value < $1.value } }
    var weakPos: (String, Double)? { posSums.min { $0.value < $1.value } }
    var topOffPos: (String, Double)? { posSums.filter { offensivePositions.contains($0.key) }.max { $0.value < $1.value } }
    var weakOffPos: (String, Double)? { posSums.filter { offensivePositions.contains($0.key) }.min { $0.value < $1.value } }
    var topDefPos: (String, Double)? { posSums.filter { defensivePositions.contains($0.key) }.max { $0.value < $1.value } }
    var weakDefPos: (String, Double)? { posSums.filter { defensivePositions.contains($0.key) }.min { $0.value < $1.value } }
}

// MARK: - String Extensions

extension String {
    var capitalizeFirst: String {
        prefix(1).capitalized + dropFirst()
    }

    func rangesOfNumbers() -> [NSRange] {
        var ranges: [NSRange] = []
        let regex = try? NSRegularExpression(pattern: "\\d+\\.?\\d*")
        let matches = regex?.matches(in: self, range: NSRange(location: 0, length: utf16.count))
        for match in matches ?? [] {
            ranges.append(match.range)
        }
        return ranges
    }

    /// Returns ranges between start and end tokens (inclusive of content)
    func rangesBetween(startToken: String, endToken: String) -> [NSRange] {
        var ranges: [NSRange] = []
        var searchStart = startIndex
        while let startRange = self.range(of: startToken, range: searchStart..<endIndex),
              let endRange = self.range(of: endToken, range: startRange.upperBound..<endIndex) {
            let nsStart = NSRange(startRange.upperBound..., in: self).location
            let nsLen = NSRange(startRange.upperBound..<endRange.lowerBound, in: self).length
            let nsRange = NSRange(location: nsStart, length: nsLen)
            ranges.append(nsRange)
            searchStart = endRange.upperBound
        }
        return ranges
    }
}

// MARK: - Enhanced StatDropAnalysisGenerator

@MainActor final class StatDropAnalysisGenerator {
    static let shared = StatDropAnalysisGenerator()

    private init() {}

    /// Main API
    /// - Parameters:
    ///   - opponent: optional TeamStanding for .matchup contexts (nil for non-matchup)
    ///   - explicitWeek: optional override week (useful for previewing upcoming week)
    func generate(for team: TeamStanding,
                  league: LeagueData,
                  week: Int,
                  context: StatDropContext,
                  personality: StatDropPersonality,
                  opponent: TeamStanding? = nil,
                  explicitWeek: Int? = nil) -> AttributedString {
        // If context is .matchup and opponent provided, route to matchup generator
        switch context {
        case .fullTeam:
            return generateFullTeam(team: team, league: league, week: week, personality: personality)
        case .team:
            return generateTeamCard(team: team, league: league, week: week, personality: personality)
        case .offense:
            return generateOffenseCard(team: team, league: league, week: week, personality: personality)
        case .defense:
            return generateDefenseCard(team: team, league: league, week: week, personality: personality)
        case .myTeam:
            return generateMyTeam(team: team, league: league, week: explicitWeek ?? week, personality: personality)
        case .myLeague:
            return generateMyLeague(team: team, league: league, week: explicitWeek ?? week, personality: personality)
        case .matchup:
            return generateMatchup(team: team, opponent: opponent, league: league, week: explicitWeek ?? week, personality: personality)
        }
    }

    // MARK: - Context-specific Generators (Enhanced)

    private func generateFullTeam(team: TeamStanding, league: LeagueData, week: Int, personality: StatDropPersonality) -> AttributedString {
        var analysis = ""

        let stats = extractTeamStats(team: team, league: league)
        let allTime = extractAllTimeStats(ownerId: team.ownerId, league: league)
        let previousWeek = week - 1
        let weekStats = computeWeekStats(team: team, league: league, week: previousWeek)

        // Look-ahead hook
        analysis += lookAheadHook(team: team, league: league, week: week, personality: personality)

        analysis += personalityIntro(team: team, week: week, personality: personality, stats: stats)

        analysis += previousWeekBreakdown(weekStats: weekStats, personality: personality)

        analysis += seasonBreakdown(team: team, stats: stats, allTime: allTime, personality: personality)

        analysis += suggestionsAndEncouragement(team: team, personality: personality)

        return formatAttributedString(analysis)
    }

    private func generateTeamCard(team: TeamStanding, league: LeagueData, week: Int, personality: StatDropPersonality) -> AttributedString {
        var analysis = ""

        let stats = extractTeamStats(team: team, league: league)
        let previousWeek = week - 1
        let weekStats = computeWeekStats(team: team, league: league, week: previousWeek)

        analysis += lookAheadHook(team: team, league: league, week: week, personality: personality, isBrief: true)

        analysis += personalityIntro(team: team, week: week, personality: personality, stats: stats, isBrief: true)

        analysis += previousWeekBreakdown(weekStats: weekStats, personality: personality, isBrief: true)

        analysis += seasonBreakdown(team: team, stats: stats, allTime: nil, personality: personality, isBrief: true)

        analysis += suggestionsAndEncouragement(team: team, personality: personality, isBrief: true)

        return formatAttributedString(analysis)
    }

    private func generateOffenseCard(team: TeamStanding, league: LeagueData, week: Int, personality: StatDropPersonality) -> AttributedString {
        var analysis = ""

        let stats = extractTeamStats(team: team, league: league)
        let previousWeek = week - 1
        let weekStats = computeWeekStats(team: team, league: league, week: previousWeek)

        analysis += lookAheadHook(team: team, league: league, week: week, personality: personality, isBrief: true)

        analysis += offenseIntro(team: team, personality: personality, stats: stats)

        analysis += offenseWeekBreakdown(weekStats: weekStats, personality: personality)

        analysis += offenseSeasonBreakdown(stats: stats, personality: personality)

        analysis += offenseSuggestions(team: team, personality: personality)

        return formatAttributedString(analysis)
    }

    private func generateDefenseCard(team: TeamStanding, league: LeagueData, week: Int, personality: StatDropPersonality) -> AttributedString {
        var analysis = ""

        let stats = extractTeamStats(team: team, league: league)
        let previousWeek = week - 1
        let weekStats = computeWeekStats(team: team, league: league, week: previousWeek)

        analysis += lookAheadHook(team: team, league: league, week: week, personality: personality, isBrief: true)

        analysis += defenseIntro(team: team, personality: personality, stats: stats)

        analysis += defenseWeekBreakdown(weekStats: weekStats, personality: personality)

        analysis += defenseSeasonBreakdown(stats: stats, personality: personality)

        analysis += defenseSuggestions(team: team, personality: personality)

        return formatAttributedString(analysis)
    }

    // MARK: - New View-Specific Generators

    /// MyTeam: introspective, owner-focused, MVP and bench watch, tie to aggregated all-time if present
    private func generateMyTeam(team: TeamStanding, league: LeagueData, week: Int, personality: StatDropPersonality) -> AttributedString {
        var analysis = ""
        let stats = extractTeamStats(team: team, league: league)
        let agg = extractAllTimeStats(ownerId: team.ownerId, league: league)
        let prevWeek = computeWeekStats(team: team, league: league, week: week - 1)

        analysis += lookAheadHook(team: team, league: league, week: week, personality: personality)
        analysis += personalityIntro(team: team, week: week, personality: personality, stats: stats)

        // MVP This Week
        if let mvp = topPerformerForWeek(team: team, week: week - 1) {
            analysis += "\n\nMVP (Last Week): \(mvp.name) with \(String(format: "%.1f", mvp.points)) pts — keep feeding the hot hand!"
        } else {
            analysis += "\n\nMVP (Last Week): no clear standout."
        }

        // Bench warmers to watch (players on roster not starting but with strong week)
        let bench = benchWatchlist(team: team, week: week - 1, limit: 3)
        if !bench.isEmpty {
            let names = bench.map { "\($0.name) (\(String(format: "%.1f", $0.points)) pts)" }.joined(separator: ", ")
            analysis += "\n\nBench Warmers to Watch: \(names)."
        }

        // Brief recap & position-level notes
        if let pw = prevWeek {
            analysis += "\n\nLast week you scored \(String(format: "%.1f", pw.actual)) / \(String(format: "%.1f", pw.max)) (Mgmt \(String(format: "%.0f%%", pw.mgmt)))."
            if let topOff = pw.topOffPos { analysis += " Top offense: \(topOff.0) \(String(format: "%.1f", topOff.1))." }
            if let weakOff = pw.weakOffPos { analysis += " Weak spot: \(weakOff.0) \(String(format: "%.1f", weakOff.1))." }
        }

        // Tie to all-time
        if let a = agg {
            analysis += "\n\nAll-time: \(a.seasonsIncluded.count) seasons, \(a.championships) championships, record \(a.recordString)."
        }

        analysis += "\n\n" + suggestionsAndEncouragement(team: team, personality: personality, isBrief: true)

        return formatAttributedString(analysis)
    }

    /// MyLeague: league-level highlights, top/bottom teams, trivia
    private func generateMyLeague(team: TeamStanding, league: LeagueData, week: Int, personality: StatDropPersonality) -> AttributedString {
        var analysis = ""
        analysis += lookAheadHook(team: team, league: league, week: week, personality: personality, isBrief: true)

        // League aggregates
        let teams = league.teams
        let count = teams.count
        let avgPPW = teams.reduce(0.0) { $0 + $1.teamPointsPerWeek } / Double(max(1, count))
        // Top offense / defense
        let topOff = teams.max { $0.offensivePointsFor ?? 0 < $1.offensivePointsFor ?? 0 }
        let topDef = teams.max { $0.defensivePointsFor ?? 0 < $1.defensivePointsFor ?? 0 }
        let worstOff = teams.min { $0.offensivePointsFor ?? 0 < $1.offensivePointsFor ?? 0 }

        analysis += "\n\nLeague Snapshot: \(count) teams, avg PPW \(String(format: "%.1f", avgPPW))."
        if let to = topOff { analysis += " Top offense: \(to.name) (\(String(format: "%.1f", to.offensivePointsFor ?? 0)) pts)." }
        if let td = topDef { analysis += " Top defense: \(td.name) (\(String(format: "%.1f", td.defensivePointsFor ?? 0)) pts)." }
        if let wo = worstOff { analysis += " Lowest scoring offense: \(wo.name) (\(String(format: "%.1f", wo.offensivePointsFor ?? 0)))." }

        // Fun trivia: league-high starters by position this week (approximate)
        let posSums = teams.reduce(into: [String: Double]()) { acc, t in
            if let pa = t.positionAverages {
                for (k, v) in pa { acc[k, default: 0] += v }
            }
        }
        if !posSums.isEmpty {
            let top = posSums.max { $0.value < $1.value }
            if let top = top {
                analysis += "\n\nLeague trivia: Across teams, \(top.key)s average \(String(format: "%.1f", top.value / Double(max(1, count)))) PPW — watch those matchups."
            }
        }

        // Where your team sits
        if let ix = teams.firstIndex(where: { $0.id == team.id }) {
            analysis += "\n\nYour team (\(team.name)) currently ranks \(ix + 1) of \(count) in the latest standings snapshot."
        }

        analysis += "\n\n" + suggestionsAndEncouragement(team: team, personality: personality, isBrief: true)
        return formatAttributedString(analysis)
    }

    /// Matchup: head-to-head and projections; requires opponent
    private func generateMatchup(team: TeamStanding, opponent: TeamStanding?, league: LeagueData, week: Int, personality: StatDropPersonality) -> AttributedString {
        var analysis = ""
        analysis += lookAheadHook(team: team, league: league, week: week, personality: personality)

        guard let opp = opponent else {
            // Fallback to regular team card
            analysis += "\n\nNo opponent data; falling back to team summary.\n\n"
            analysis += generateTeamCard(team: team, league: league, week: week, personality: personality).description
            return formatAttributedString(analysis)
        }

        // Intros
        analysis += personalityIntro(team: team, week: week, personality: personality, stats: extractTeamStats(team: team, league: league))
        analysis += "\n\nMatchup vs \(opp.name):"

        // Head-to-head quick numbers
        let teamOff = team.offensivePointsFor ?? 0
        let teamDef = team.defensivePointsFor ?? 0
        let oppOff = opp.offensivePointsFor ?? 0
        let oppDef = opp.defensivePointsFor ?? 0

        analysis += "\n • Your Off PPW: \(String(format: "%.1f", teamOff)) vs Their Def PPW: \(String(format: "%.1f", oppDef))"
        analysis += "\n • Their Off PPW: \(String(format: "%.1f", oppOff)) vs Your Def PPW: \(String(format: "%.1f", teamDef))"

        // Position-level edges
        let posNotes = matchupPositionEdges(team: team, opponent: opp)
        if !posNotes.isEmpty {
            analysis += "\n\nPosition Matchups: \(posNotes)"
        }

        // Simple projection
        let proj = matchupProjection(team: team, opponent: opp)
        analysis += "\n\nProjected: You \(String(format: "%.0f%%", proj.winChance * 100)) chance to win. Expect around \(String(format: "%.0f", proj.expectedTeam)) - \(String(format: "%.0f", proj.expectedOpponent))."

        // Personality quip
        switch personality {
        case .hypeMan:
            analysis += "\n\nVS \(opp.name.uppercased()): TIME TO CRUSH — RIDE THE HYPE!"
        case .snarkyAnalyst:
            analysis += "\n\nVS \(opp.name): This smells like an upset — or a nap. Bring actual starters."
        default:
            break
        }

        analysis += "\n\n" + suggestionsAndEncouragement(team: team, personality: personality, isBrief: true)
        return formatAttributedString(analysis)
    }

    // MARK: - Computation Helpers

    private func computeWeekStats(team: TeamStanding, league: LeagueData, week: Int) -> PreviousWeekStats? {
        if week < 1 { return nil }

        let actual = computeActualPointsForWeek(team: team, week: week)

        let max = computeMaxPointsForWeek(team: team, league: league, week: week)

        let mgmt = max.total > 0 ? (actual.total / max.total * 100) : 0

        let offMgmt = max.off > 0 ? (actual.off / max.off * 100) : 0

        let defMgmt = max.def > 0 ? (actual.def / max.def * 100) : 0

        let posSums = computePositionSumsForWeek(team: team, week: week)

        let leaguePoints = computeLeagueWeekPoints(league: league, week: week)

        let sorted = leaguePoints.sorted { $0.value > $1.value }

        if let idx = sorted.firstIndex(where: { $0.key == team.id }) {
            let rank = idx + 1
            return PreviousWeekStats(week: week, actual: actual.total, max: max.total, mgmt: mgmt, offActual: actual.off, offMax: max.off, offMgmt: offMgmt, defActual: actual.def, defMax: max.def, defMgmt: defMgmt, posSums: posSums, leagueRank: rank, numTeams: league.teams.count)
        }

        return nil
    }

    private func computeActualPointsForWeek(team: TeamStanding, week: Int) -> (total: Double, off: Double, def: Double) {
        var total = 0.0
        var off = 0.0
        var def = 0.0

        if let starters = team.actualStartersByWeek?[week] {
            for id in starters {
                if let player = team.roster.first(where: { $0.id == id }), let score = player.weeklyScores.first(where: { $0.week == week }) {
                    let pts = score.points
                    total += pts
                    if offensivePositions.contains(player.position) {
                        off += pts
                    } else if defensivePositions.contains(player.position) {
                        def += pts
                    }
                }
            }
        } else if let pts = team.weeklyActualLineupPoints?[week] {
            total = pts
            // off and def not computable without starters, remain 0
        }

        return (total, off, def)
    }

    private func computeMaxPointsForWeek(team: TeamStanding, league: LeagueData, week: Int) -> (total: Double, off: Double, def: Double) {
        let slots = league.startingLineup
        var candidates: [Candidate] = team.roster.compactMap({ player in
            if let score = player.weeklyScores.first(where: { $0.week == week }) {
                return Candidate(basePos: player.position, fantasy: player.altPositions ?? [], points: score.points)
            }
            return nil
        })

        var used = Set<Int>()
        var totalMax = 0.0
        var offMax = 0.0
        var defMax = 0.0

        for slot in slots {
            var pickIdx: Int? = nil
            var maxP = -1.0
            for (i, c) in candidates.enumerated() {
                if !used.contains(i) && isEligible(c: c, allowed: allowedPositions(for: slot)) && c.points > maxP {
                    maxP = c.points
                    pickIdx = i
                }
            }

            if let idx = pickIdx {
                used.insert(idx)
                let c = candidates[idx]
                totalMax += c.points
                let counted = SlotPositionAssigner.countedPosition(for: slot, candidatePositions: c.fantasy, base: c.basePos)
                if offensivePositions.contains(counted) {
                    offMax += c.points
                } else if defensivePositions.contains(counted) {
                    defMax += c.points
                }
            }
        }

        return (totalMax, offMax, defMax)
    }

    private func computePositionSumsForWeek(team: TeamStanding, week: Int) -> [String: Double] {
        var dict: [String: Double] = [:]
        if let starters = team.actualStartersByWeek?[week] {
            for id in starters {
                if let player = team.roster.first(where: { $0.id == id }), let score = player.weeklyScores.first(where: { $0.week == week }) {
                    dict[player.position, default: 0] += score.points
                }
            }
        }
        return dict
    }

    private func computeLeagueWeekPoints(league: LeagueData, week: Int) -> [String: Double] {
        var dict: [String: Double] = [:]
        for t in league.teams {
            let actual = computeActualPointsForWeek(team: t, week: week)
            dict[t.id] = actual.total
        }
        return dict
    }

    private func isEligible(c: Candidate, allowed: Set<String>) -> Bool {
        if allowed.contains(c.basePos) { return true }
        return !allowed.intersection(Set(c.fantasy)).isEmpty
    }

    private func allowedPositions(for slot: String) -> Set<String> {
        let u = slot.uppercased()
        switch u {
        case "QB", "RB", "WR", "TE", "K", "DL", "LB", "DB": return [u]
        case "FLEX", "WRRB", "WRRBTE", "WRRB_TE", "RBWR", "RBWRTE": return ["RB", "WR", "TE"]
        case "SUPER_FLEX", "QBRBWRTE", "QBRBWR", "QBSF", "SFLX": return ["QB", "RB", "WR", "TE"]
        case "IDP": return ["DL", "LB", "DB"]
        default:
            if u.contains("IDP") { return ["DL", "LB", "DB"] }
            return [u]
        }
    }

    private func isIDPFlex(_ slot: String) -> Bool {
        let u = slot.uppercased()
        return u.contains("IDP") && u != "DL" && u != "LB" && u != "DB"
    }

    // Slightly smarter counted-position helper for internal use
    private func countedPosition(for slot: String, candidatePositions: [String], base: String) -> String {
        let u = slot.uppercased()
        if ["DL", "LB", "DB"].contains(u) { return u }
        if isIDPFlex(u) || offensiveFlexSlots.contains(u) { return candidatePositions.first ?? base }
        return base
    }

    // MARK: - Helper extraction methods

    private func extractTeamStats(team: TeamStanding, league: LeagueData) -> TeamStats {
        let totalPpw = league.teams.reduce(0.0) { $0 + $1.teamPointsPerWeek }
        let avgPpw = league.teams.isEmpty ? 0 : totalPpw / Double(league.teams.count)

        return TeamStats(
            pointsFor: team.pointsFor,
            maxPointsFor: team.maxPointsFor,
            managementPercent: team.managementPercent,
            ppw: team.teamPointsPerWeek,
            leagueAvgPpw: avgPpw,
            record: team.winLossRecord ?? "0-0",
            offensivePointsFor: team.offensivePointsFor ?? 0,
            maxOffensivePointsFor: team.maxOffensivePointsFor ?? 0,
            offensiveManagementPercent: team.offensiveManagementPercent ?? 0,
            offensivePPW: team.averageOffensivePPW ?? 0,
            defensivePointsFor: team.defensivePointsFor ?? 0,
            maxDefensivePointsFor: team.maxDefensivePointsFor ?? 0,
            defensiveManagementPercent: team.defensiveManagementPercent ?? 0,
            defensivePPW: team.averageDefensivePPW ?? 0,
            positionAverages: team.positionAverages ?? [:],
            offensiveStrengths: team.offensiveStrengths,
            offensiveWeaknesses: team.offensiveWeaknesses,
            defensiveStrengths: team.defensiveStrengths,
            defensiveWeaknesses: team.defensiveWeaknesses,
            strengths: team.strengths,
            weaknesses: team.weaknesses,
            leagueStanding: team.leagueStanding
        )
    }

    private func extractAllTimeStats(ownerId: String, league: LeagueData) -> AggregatedOwnerStats? {
        league.allTimeOwnerStats?[ownerId]
    }

    // MARK: - Phrase Builders (Enhanced & View-aware)

    /// Look-ahead hook: adds a short prediction/tease block at the top of the drop.
    private func lookAheadHook(team: TeamStanding,
                               league: LeagueData,
                               week: Int,
                               personality: StatDropPersonality,
                               isBrief: Bool = false) -> String {
        // Use StatDropPersistence to determine canonical current week if needed
        let currentWeek = StatDropPersistence.shared.currentWeek(leagueSeason: league.season)
        let targetWeek = max(1, week)
        // Build a short prediction string using simple trend heuristic.
        // Example predictions are personality-flavored.
        let expected = String(format: "%.0f", team.teamPointsPerWeek * 1.02) // naive small bump
        switch personality {
        case .hypeMan:
            return "\n✨LOOKAHEAD✨\nWEEK \(targetWeek): LET'S GO! Expect an explosive \(expected)+ pt outing if you start the studs.\n"
        case .snarkyAnalyst:
            return "\n✨LOOKAHEAD✨\nWeek \(targetWeek) forecast: probably \(expected) pts. Unless you bench your best players again.\n"
        case .classicESPN:
            return "\n✨LOOKAHEAD✨\nUp next (Week \(targetWeek)): projection around \(expected) — trending up if usage continues.\n"
        case .dramatic:
            return "\n✨LOOKAHEAD✨\nWEEK \(targetWeek): A STORM BREWS — anticipate ~\(expected) points of sheer chaos!\n"
        default:
            return isBrief ? "" : "\n✨LOOKAHEAD✨\nWeek \(targetWeek) projection: ~\(expected) pts based on current trends.\n"
        }
    }

    private func personalityIntro(team: TeamStanding, week: Int, personality: StatDropPersonality, stats: TeamStats, isBrief: Bool = false) -> String {
        let intro = "Week \(week) Stat Drop for \(team.name):"
        switch personality {
        case .classicESPN:
            return "\(intro) Let's dive into the numbers."
        case .hypeMan:
            return "\(intro.uppercased()) LET'S GET HYPED!"
        case .snarkyAnalyst:
            return "\(intro) Buckle up for disappointment."
        case .oldSchoolRadio:
            return "\(intro) Gather 'round the radio, folks."
        case .statGeek:
            return "\(intro) Time for some deep stats."
        case .motivationalCoach:
            return "\(intro) You've got the power!"
        case .britishCommentator:
            return "\(intro) Quite the show."
        case .localNews:
            return "\(intro) Community update."
        case .dramatic:
            return "\(intro) THE DRAMA UNFOLDS!"
        case .robotAI:
            return "\(intro) Initializing analysis."
        }
    }

    private func previousWeekBreakdown(weekStats: PreviousWeekStats?, personality: StatDropPersonality, isBrief: Bool = false) -> String {
        guard let stats = weekStats else { return "\n\nNo data for previous week." }

        let week = stats.week
        let actualStr = String(format: "%.1f", stats.actual)
        let maxStr = String(format: "%.1f", stats.max)
        let mgmtStr = String(format: "%.0f%%", stats.mgmt)
        let rankStr = "\(stats.leagueRank) out of \(stats.numTeams)"

        // Position-level breakdown (QB / RB / WR / TE / DL/LB/DB)
        var posLines: [String] = []
        if let qb = stats.posSums["QB"] { posLines.append("QBs \(String(format: "%.1f", qb))") }
        if let rb = stats.posSums["RB"] { posLines.append("RBs \(String(format: "%.1f", rb))") }
        if let wr = stats.posSums["WR"] { posLines.append("WRs \(String(format: "%.1f", wr))") }
        if let te = stats.posSums["TE"] { posLines.append("TEs \(String(format: "%.1f", te))") }

        let posSummary = posLines.isEmpty ? "No position-specific highlights." : posLines.joined(separator: " • ")

        let offMgmtStr = String(format: "%.0f%%", stats.offMgmt)
        let defMgmtStr = String(format: "%.0f%%", stats.defMgmt)

        let fullText = "Scored \(actualStr) points out of a possible \(maxStr), for a management efficiency of \(mgmtStr). Offense management \(offMgmtStr), defense \(defMgmtStr). That performance ranked you \(rankStr). Positions: \(posSummary)."
        let briefText = "Week \(week): \(actualStr) pts (\(mgmtStr) mgmt), rank \(rankStr). Top position: \(stats.topPos?.0 ?? "—")"

        let text = isBrief ? briefText : fullText

        switch personality {
        case .classicESPN:
            return "\n\nPrevious Week (Week \(week)): \(text)"
        case .hypeMan:
            return "\n\nWEEK \(week) RECAP: \(actualStr) OUTTA \(maxStr)! MGMT \(mgmtStr), OFF \(offMgmtStr), DEF \(defMgmtStr)! \(posSummary.uppercased())"
        case .snarkyAnalyst:
            return "\n\nLast week (Week \(week)): Only \(actualStr) when \(maxStr) was possible. \(mgmtStr) management. \(posSummary) — do better."
        case .oldSchoolRadio:
            return "\n\nIn Week \(week), you tallied \(actualStr) points, potential \(maxStr). Management \(mgmtStr). \(posSummary)"
        case .statGeek:
            return "\n\nWeek \(week) stats: \(actualStr)/\(maxStr) pts, \(mgmtStr) efficiency. \(posSummary). Rank: \(rankStr)."
        case .motivationalCoach:
            return "\n\nWeek \(week): Great effort with \(actualStr) pts (\(mgmtStr)). Build on positions: \(posSummary)."
        case .britishCommentator:
            return "\n\nWeek \(week): \(actualStr) points from \(maxStr), \(mgmtStr) management. \(posSummary)."
        case .localNews:
            return "\n\nLocal recap for Week \(week): \(actualStr) pts, \(mgmtStr) mgmt. \(posSummary)."
        case .dramatic:
            return "\n\nTHE TRAGEDY OF WEEK \(week): \(actualStr) AGAINST \(maxStr)! MGMT \(mgmtStr)! \(posSummary.uppercased())"
        case .robotAI:
            return "\n\nWeek \(week) data: \(actualStr)/\(maxStr), management \(mgmtStr). \(posSummary)."
        }
    }

    private func seasonBreakdown(team: TeamStanding, stats: TeamStats, allTime: AggregatedOwnerStats?, personality: StatDropPersonality, isBrief: Bool = false) -> String {
        let standing = stats.leagueStanding
        let record = stats.record
        let mgmt = String(format: "%.0f%%", stats.managementPercent)
        let ppw = String(format: "%.1f", stats.ppw)
        let vsLg = stats.ppw > stats.leagueAvgPpw ? "above league average" : "below league average"
        let offMgmt = String(format: "%.0f%%", stats.offensiveManagementPercent)
        let offPPW = String(format: "%.1f", stats.offensivePPW)
        let defMgmt = String(format: "%.0f%%", stats.defensiveManagementPercent)
        let defPPW = String(format: "%.1f", stats.defensivePPW)
        let strengths = stats.strengths?.joined(separator: ", ") ?? "none apparent"
        let weaknesses = stats.weaknesses?.joined(separator: ", ") ?? "none glaring"
        let rival = team.biggestRival ?? "yourself"
        let allTimeStr = allTime.map { "Historically, \($0.championships) championships and a \($0.recordString) record." } ?? ""

        // Position averages breakdown
        var posLines: [String] = []
        for pos in ["QB", "RB", "WR", "TE"] {
            if let val = stats.positionAverages[pos] {
                posLines.append("\(pos)s \(String(format: "%.1f", val))")
            }
        }
        let posSummary = posLines.isEmpty ? "" : " Positions: " + posLines.joined(separator: " • ") + "."

        let fullText = "Currently \(standing)th in the league with a \(record) record. Management at \(mgmt), averaging \(ppw) PPW (\(vsLg)). Offense: \(offPPW) PPW (\(offMgmt)). Defense: \(defPPW) PPW (\(defMgmt)). Strengths: \(strengths). Weaknesses: \(weaknesses). Biggest rival: \(rival). \(allTimeStr)\(posSummary)"
        let briefText = "\(standing)th, \(record), Mgmt \(mgmt), PPW \(ppw). Off \(offPPW)/\(offMgmt), Def \(defPPW)/\(defMgmt)."

        let text = isBrief ? briefText : fullText

        switch personality {
        case .classicESPN:
            return "\n\nFull Season Breakdown: \(text)"
        case .hypeMan:
            return "\n\nSEASON SO FAR: \(text.uppercased())"
        case .snarkyAnalyst:
            return "\n\nSeason summary: \(text)"
        case .oldSchoolRadio:
            return "\n\nSeason to date: \(text)"
        case .statGeek:
            return "\n\nSeason stats: \(text)"
        case .motivationalCoach:
            return "\n\nSeason progress: \(text)"
        case .britishCommentator:
            return "\n\nSeason to date: \(text)"
        case .localNews:
            return "\n\nCommunity season update: \(text)"
        case .dramatic:
            return "\n\nTHE GRAND SEASON EPIC: \(text.uppercased())"
        case .robotAI:
            return "\n\nSeason data: \(text)"
        }
    }

    private func suggestionsAndEncouragement(team: TeamStanding, personality: StatDropPersonality, isBrief: Bool = false) -> String {
        let standing = team.leagueStanding
        let weaknesses = team.weaknesses?.joined(separator: ", ") ?? ""
        let suggestion = !weaknesses.isEmpty ? "Consider the waivers/trades for \(weaknesses) to bolster your roster." : "Your team looks balanced—maintain the course."
        let encouragement = standing <= (team.league?.teams.count ?? 12) / 2 ? "You're in contention—push for the playoffs!" : "Plenty of games left—stage a comeback!"
        let fullText = "\(suggestion) \(encouragement)"
        let briefText = "\(suggestion)"

        let text = isBrief ? briefText : fullText

        switch personality {
        case .classicESPN:
            return "\n\nLooking ahead: \(text)"
        case .hypeMan:
            return "\n\nNEXT MOVES: \(text.uppercased())"
        case .snarkyAnalyst:
            return "\n\nSuggestions: \(text)"
        case .oldSchoolRadio:
            return "\n\nForward thinking: \(text)"
        case .statGeek:
            return "\n\nOptimal moves: \(text)"
        case .motivationalCoach:
            return "\n\nGame plan: \(text)"
        case .britishCommentator:
            return "\n\nRecommendations: \(text)"
        case .localNews:
            return "\n\nCommunity tips: \(text)"
        case .dramatic:
            return "\n\nTHE CLIMAX APPROACHES: \(text.uppercased())"
        case .robotAI:
            return "\n\nComputed advice: \(text)"
        }
    }

    private func offenseWeekBreakdown(weekStats: PreviousWeekStats?, personality: StatDropPersonality) -> String {
        guard let stats = weekStats else { return "" }

        let week = stats.week
        let actualStr = String(format: "%.1f", stats.offActual)
        let mgmtStr = String(format: "%.0f%%", stats.offMgmt)
        let topStr = stats.topOffPos.map { "\($0) with \(String(format: "%.1f", $1)) pts" } ?? "no standout"
        let weakStr = stats.weakOffPos.map { "\($0) with \(String(format: "%.1f", $1)) pts" } ?? "no weak"

        let text = "Offense scored \(actualStr) points, management \(mgmtStr). Top \(topStr), weak \(weakStr)."

        switch personality {
        case .classicESPN:
            return "\nPrevious Week Offense (Week \(week)): \(text)"
        case .hypeMan:
            return "\nOFF WEEK \(week): \(actualStr) PTS, \(mgmtStr) MGMT! TOP \(topStr.uppercased())"
        case .snarkyAnalyst:
            return "\nOffense last week: \(actualStr) pts, \(mgmtStr). \(topStr) okay, \(weakStr) pathetic."
        default:
            return "\nOffense Week \(week): \(text)"
        }
    }

    private func defenseWeekBreakdown(weekStats: PreviousWeekStats?, personality: StatDropPersonality) -> String {
        guard let stats = weekStats else { return "" }

        let week = stats.week
        let actualStr = String(format: "%.1f", stats.defActual)
        let mgmtStr = String(format: "%.0f%%", stats.defMgmt)
        let topStr = stats.topDefPos.map { "\($0) with \(String(format: "%.1f", $1)) pts" } ?? "no standout"
        let weakStr = stats.weakDefPos.map { "\($0) with \(String(format: "%.1f", $1)) pts" } ?? "no weak"

        let text = "Defense scored \(actualStr) points, management \(mgmtStr). Top \(topStr), weak \(weakStr)."

        switch personality {
        case .classicESPN:
            return "\nPrevious Week Defense (Week \(week)): \(text)"
        case .hypeMan:
            return "\nDEF WEEK \(week): \(actualStr) PTS, \(mgmtStr) MGMT! TOP \(topStr.uppercased())"
        case .snarkyAnalyst:
            return "\nDefense last week: \(actualStr) pts, \(mgmtStr). \(topStr) passable, \(weakStr) disastrous."
        default:
            return "\nDefense Week \(week): \(text)"
        }
    }

    private func offenseSeasonBreakdown(stats: TeamStats, personality: StatDropPersonality) -> String {
        let mgmt = String(format: "%.0f%%", stats.offensiveManagementPercent)
        let ppw = String(format: "%.1f", stats.offensivePPW)
        let strengths = stats.offensiveStrengths?.joined(separator: ", ") ?? "--"
        let weaknesses = stats.offensiveWeaknesses?.joined(separator: ", ") ?? "--"

        let text = "Offense management \(mgmt), PPW \(ppw). Strengths \(strengths), weaknesses \(weaknesses)."

        switch personality {
        case .classicESPN:
            return "\nSeason Offense: \(text)"
        default:
            return "\nOffense season: \(text)"
        }
    }

    private func defenseSeasonBreakdown(stats: TeamStats, personality: StatDropPersonality) -> String {
        let mgmt = String(format: "%.0f%%", stats.defensiveManagementPercent)
        let ppw = String(format: "%.1f", stats.defensivePPW)
        let strengths = stats.defensiveStrengths?.joined(separator: ", ") ?? "--"
        let weaknesses = stats.defensiveWeaknesses?.joined(separator: ", ") ?? "--"

        let text = "Defense management \(mgmt), PPW \(ppw). Strengths \(strengths), weaknesses \(weaknesses)."

        switch personality {
        case .classicESPN:
            return "\nSeason Defense: \(text)"
        default:
            return "\nDefense season: \(text)"
        }
    }

    private func offenseSuggestions(team: TeamStanding, personality: StatDropPersonality) -> String {
        let weaknesses = team.offensiveWeaknesses?.joined(separator: ", ") ?? ""
        let suggestion = !weaknesses.isEmpty ? "Scout waivers or trades for \(weaknesses) to amp up offense." : "Offense solid - keep rolling."

        switch personality {
        case .classicESPN:
            return "\nOffense Tips: \(suggestion)"
        default:
            return "\nOffense tips: \(suggestion)"
        }
    }

    private func defenseSuggestions(team: TeamStanding, personality: StatDropPersonality) -> String {
        let weaknesses = team.defensiveWeaknesses?.joined(separator: ", ") ?? ""
        let suggestion = !weaknesses.isEmpty ? "Target waivers or trades for \(weaknesses) to lock down defense." : "Defense strong - maintain."

        switch personality {
        case .classicESPN:
            return "\nDefense Tips: \(suggestion)"
        default:
            return "\nDefense tips: \(suggestion)"
        }
    }

    private func offenseIntro(team: TeamStanding, personality: StatDropPersonality, stats: TeamStats) -> String {
        switch personality {
        case .classicESPN:
            return "Offense Stat Drop for \(team.name): Let's break it down."
        case .hypeMan:
            return "OFFENSE HYPE FOR \(team.name.uppercased())!"
        default:
            return "Offense analysis for \(team.name)."
        }
    }

    private func defenseIntro(team: TeamStanding, personality: StatDropPersonality, stats: TeamStats) -> String {
        switch personality {
        case .classicESPN:
            return "Defense Stat Drop for \(team.name): Let's analyze."
        case .hypeMan:
            return "DEFENSE HYPE FOR \(team.name.uppercased())!"
        default:
            return "Defense analysis for \(team.name)."
        }
    }

    // MARK: - Small utilities (MVPs / bench watch / matchup helpers)

    private func topPerformerForWeek(team: TeamStanding, week: Int) -> (name: String, points: Double)? {
        guard week >= 1 else { return nil }
        var best: (String, Double)? = nil
        for player in team.roster {
            if let pts = player.weeklyScores.first(where: { $0.week == week })?.points {
                if best == nil || pts > best!.1 {
                    best = (player.id, pts)
                }
            }
        }
        if let b = best {
            // prefer readable name if available in roster Player struct - we only have id, but return id for now
            return (name: b.0, points: b.1)
        }
        return nil
    }

    private func benchWatchlist(team: TeamStanding, week: Int, limit: Int) -> [(name: String, points: Double)] {
        guard week >= 1 else { return [] }
        // bench = roster players not appearing in starters that week
        var startersSet = Set<String>()
        if let starters = team.actualStartersByWeek?[week] {
            startersSet = Set(starters)
        }
        var candidates: [(String, Double)] = []
        for player in team.roster where !startersSet.contains(player.id) {
            if let pts = player.weeklyScores.first(where: { $0.week == week })?.points {
                candidates.append((player.id, pts))
            }
        }
        return candidates.sorted { $0.1 > $1.1 }.prefix(limit).map { (name: $0.0, points: $0.1) }
    }

    private func matchupPositionEdges(team: TeamStanding, opponent: TeamStanding) -> String {
        // compare position averages between team and opponent: offense vs defense for key roles
        var notes: [String] = []
        if let qb = team.positionAverages?["QB"], let db = opponent.positionAverages?["DB"] {
            if qb > db { notes.append("QB vs DB looks like an edge for you (\(String(format: "%.1f", qb)) vs \(String(format: "%.1f", db)))") }
        }
        if let rb = team.positionAverages?["RB"], let lb = opponent.positionAverages?["LB"] {
            if rb < lb { notes.append("RBs may struggle vs their LB (\(String(format: "%.1f", rb)) vs \(String(format: "%.1f", lb)))") }
        }
        return notes.joined(separator: " • ")
    }

    private func matchupProjection(team: TeamStanding, opponent: TeamStanding) -> (expectedTeam: Double, expectedOpponent: Double, winChance: Double) {
        // naive projection: use team.teamPointsPerWeek and opponent.teamPointsPerWeek
        let t = max(0.1, team.teamPointsPerWeek)
        let o = max(0.1, opponent.teamPointsPerWeek)
        // scale by management (favor higher management)
        let tAdj = t * max(0.5, team.managementPercent / 100)
        let oAdj = o * max(0.5, opponent.managementPercent / 100)
        let total = tAdj + oAdj
        var win = 0.5
        if total > 0 { win = tAdj / total }
        // clamp 0.05..0.95
        let clamped = min(max(win, 0.05), 0.95)
        return (expectedTeam: tAdj, expectedOpponent: oAdj, winChance: clamped)
    }

    // MARK: - Format & Highlighting

    /// Format AttributedString:
    ///  - Bold numeric tokens and color them yellow (existing)
    ///  - Additionally highlight "LOOKAHEAD" sections in green (between special markers ✨LOOKAHEAD✨ ... newline)
    private func formatAttributedString(_ text: String) -> AttributedString {
        // First convert raw string to AttributedString
        var raw = text

        // For LookAhead: we used special prefix "✨LOOKAHEAD✨\n" in lookAheadHook; we will look for that substring and style the line following it.
        // Simpler: find occurrences of "✨LOOKAHEAD✨\n" and style the immediate following sentence (until double newline or end).
        var attr = AttributedString(raw)

        // Bold all numbers & color yellow (existing behavior)
        let ranges = raw.rangesOfNumbers()
        for nsRange in ranges {
            if let stringRange = Range(nsRange, in: raw) {
                if let start = AttributedString.Index(stringRange.lowerBound, within: attr),
                   let end = AttributedString.Index(stringRange.upperBound, within: attr) {
                    let attrRange = start..<end
                    attr[attrRange].font = .boldSystemFont(ofSize: 16)
                    attr[attrRange].foregroundColor = .yellow
                }
            }
        }

        // Style lookahead chunks (green & bold): look for "✨LOOKAHEAD✨\n" markers
        let lookToken = "✨LOOKAHEAD✨\n"
        var searchRangeStart = raw.startIndex
        while let tokenRange = raw.range(of: lookToken, range: searchRangeStart..<raw.endIndex) {
            // find end of chunk (double newline or end)
            let afterToken = tokenRange.upperBound
            let endRange = raw.range(of: "\n\n", range: afterToken..<raw.endIndex) ?? raw.range(of: "\n", range: afterToken..<raw.endIndex) ?? raw.range(of: "", range: afterToken..<raw.endIndex)
            let chunkEnd = endRange?.lowerBound ?? raw.endIndex
            let nsChunk = NSRange(afterToken..<chunkEnd, in: raw)
            if let stringRange = Range(nsChunk, in: raw),
               let start = AttributedString.Index(stringRange.lowerBound, within: attr),
               let end = AttributedString.Index(stringRange.upperBound, within: attr) {
                let attrRange = start..<end
                attr[attrRange].foregroundColor = .green
                attr[attrRange].font = .boldSystemFont(ofSize: 15)
            }
            // move search cursor
            searchRangeStart = chunkEnd < raw.endIndex ? chunkEnd : raw.endIndex
        }

        return attr
    }
}

// MARK: - SwiftUI View Wrapper (updated to accept opponent & explicitWeek)

import SwiftUI

struct StatDropAnalysisBox: View {
    let team: TeamStanding
    let league: LeagueData
    let context: StatDropContext
    let personality: StatDropPersonality

    // Optional extras supported by Matchup/MyLeague/MyTeam usage in views
    var opponent: TeamStanding? = nil
    var explicitWeek: Int? = nil

    var body: some View {
        let week = explicitWeek ?? StatDropPersistence.shared.currentWeek(leagueSeason: league.season)
        let attributed = StatDropPersistence.shared.getOrGenerateStatDrop(
            for: team,
            league: league,
            context: context,
            personality: personality,
            opponent: opponent,
            explicitWeek: explicitWeek ?? week
        )
        VStack(alignment: .leading, spacing: 8) {
            Text(context == .fullTeam ? "Weekly Stat Drop" : "Stat Drop Analysis")
                .font(.headline)
                .foregroundColor(.yellow)
            ScrollView(.vertical, showsIndicators: false) {
                Text(attributed)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.bottom, 6)
            }
            .frame(maxHeight: 380) // prevents runaway height in some views
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.13))
        )
        .padding(.vertical, 4)
    }
}


/// Helper for persisting and scheduling weekly Stat Drop analysis.
@MainActor final class StatDropPersistence {
    static let shared = StatDropPersistence()
    private let userDefaults = UserDefaults.standard

    /// The scheduled drop day for a new week (e.g. Tuesday).
    /// You can customize this or make it dynamic per-league if you wish.
    static var weeklyDropWeekday: Int { 3 } // 1 = Sunday, 2 = Monday, 3 = Tuesday...
    static var dropHour: Int { 9 } // 9am UTC

    private init() {}

    /// Returns the current NFL/fantasy week number (1-18) based on the date and league season.
    func currentWeek(for date: Date = Date(), leagueSeason: String) -> Int {
        guard let year = Int(leagueSeason) else { return 1 } // Fallback if season not numeric

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)! // UTC

        // Find first Thursday in September of the year
        var septFirst = DateComponents(year: year, month: 9, day: 1)
        let septFirstDate = calendar.date(from: septFirst)!

        var seasonStart = septFirstDate
        var weekday = calendar.component(.weekday, from: seasonStart)
        while weekday != 5 { // 5 = Thursday (Sunday=1)
            seasonStart = calendar.date(byAdding: .day, value: 1, to: seasonStart)!
            weekday = calendar.component(.weekday, from: seasonStart)
        }

        // Days since season start
        let daysSinceStart = calendar.dateComponents([.day], from: seasonStart, to: date).day ?? 0

        // Raw week = (days // 7) + 1, but cap at 18
        var rawWeek = (daysSinceStart / 7) + 1
        if rawWeek > 18 { rawWeek = 18 }
        if rawWeek < 1 { rawWeek = 1 }

        // Adjust for drop schedule: If before Tuesday 9am of the current NFL week, use previous week
        let adjustedDate = adjustedDateForDrop(date)
        let adjustedDays = calendar.dateComponents([.day], from: seasonStart, to: adjustedDate).day ?? 0
        let adjustedWeek = (adjustedDays / 7) + 1

        return min(max(adjustedWeek, 1), 18)
    }

    /// Adjusts a date to the latest scheduled drop (e.g. most recent Tuesday 9am).
    private func adjustedDateForDrop(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let weekStart = calendar.date(from: components)!
        // Find this week's Tuesday 9am
        let dropDate = calendar.date(byAdding: .day, value: StatDropPersistence.weeklyDropWeekday - 1, to: weekStart)!
        let dropDateWithHour = calendar.date(bySettingHour: StatDropPersistence.dropHour, minute: 0, second: 0, of: dropDate)!
        // If current date is before this drop, go back one week
        if date < dropDateWithHour {
            return calendar.date(byAdding: .weekOfYear, value: -1, to: dropDateWithHour)!
        }
        return dropDateWithHour
    }

    /// Key for storing/retrieving stat drops. Uniqueness: (league, team, [opponent], context, week, personality)
    private func storageKey(leagueId: String, teamId: String, context: StatDropContext, week: Int, personality: StatDropPersonality, opponentId: String? = nil) -> String {
        if context == .matchup {
            // include opponent if available (ensures distinct matchup drops)
            let oppPart = opponentId ?? "noOpp"
            return "statdrop.\(leagueId).\(teamId).\(oppPart).\(context.rawValue).\(week).\(personality.rawValue)"
        } else {
            return "statdrop.\(leagueId).\(teamId).\(context.rawValue).\(week).\(personality.rawValue)"
        }
    }

    /// Retrieves the persisted stat drop for this week, or generates and saves a new one if not present.
    /// - Parameters:
    ///   - opponent: optional TeamStanding, used for matchup contexts
    ///   - explicitWeek: optional week override (useful for previews of upcoming week)
    func getOrGenerateStatDrop(for team: TeamStanding,
                               league: LeagueData,
                               context: StatDropContext,
                               personality: StatDropPersonality,
                               opponent: TeamStanding? = nil,
                               explicitWeek: Int? = nil) -> AttributedString {
        let leagueId = league.id
        let teamId = team.id
        let week = explicitWeek ?? currentWeek(leagueSeason: league.season)
        let opponentId = opponent?.id

        let key = storageKey(leagueId: leagueId, teamId: teamId, context: context, week: week, personality: personality, opponentId: opponentId)

        if let savedData = userDefaults.data(forKey: key),
           let saved = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: savedData) {
            return AttributedString(saved)
        }

        let generated = StatDropAnalysisGenerator.shared.generate(
            for: team,
            league: league,
            week: week,
            context: context,
            personality: personality,
            opponent: opponent,
            explicitWeek: explicitWeek
        )
        // Persist it (as NSAttributedString)
        let nsAttr = NSAttributedString(generated)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: nsAttr, requiringSecureCoding: false) {
            userDefaults.set(data, forKey: key)
        }
        return generated
    }

    /// Clears all persisted stat drops (for debugging or force refresh).
    func clearAll() {
        for key in userDefaults.dictionaryRepresentation().keys where key.hasPrefix("statdrop.") {
            userDefaults.removeObject(forKey: key)
        }
    }

    /// Remove a single persisted key (convenience)
    func removeKey(_ key: String) {
        userDefaults.removeObject(forKey: key)
    }
}
