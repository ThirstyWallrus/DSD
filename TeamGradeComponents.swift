//
//  TeamGradeComponents.swift
//  DynastyStatDrop
import Foundation

struct TeamGradeComponents {
    let pointsFor: Double
    let ppw: Double
    let mgmt: Double
    let offMgmt: Double
    let defMgmt: Double
    let recordPct: Double
    let qbPPW: Double
    let rbPPW: Double
    let wrPPW: Double
    let tePPW: Double
    let kPPW: Double
    let dlPPW: Double
    let lbPPW: Double
    let dbPPW: Double
    let teamName: String
    let teamId: String? // Optional, not part of grading logic; default nil

    // Returns a Double to sort teams by grade percentile (higher is better)
    // Lower value = better grade (A+), so sort ascendingly if you want A+ first
    static func gradeSortKey(for team: TeamGradeComponents, allStats: [TeamGradeComponents]) -> Double {
        // Use compositePercentileScore (already defined in your file)
        let (score, _) = compositePercentileScore(for: team, allTeams: allStats)
        // Negative so higher percentiles (A+) sort first
        return -score
    }

    // Convenience static helper for parsing W-L-T string
    static func parseRecord(_ record: String?) -> (Int, Int, Int) {
        guard let components = record?.split(separator: "-").map({ Int($0) ?? 0 }), !components.isEmpty else {
            return (0, 0, 0)
        }
        let w = components.count > 0 ? components[0] : 0
        let l = components.count > 1 ? components[1] : 0
        let t = components.count > 2 ? components[2] : 0
        return (w, l, t)
    }

    // Main initializer; teamId defaults to nil so you never have to supply it unless you want to
    init(
        pointsFor: Double,
        ppw: Double,
        mgmt: Double,
        offMgmt: Double,
        defMgmt: Double,
        recordPct: Double,
        qbPPW: Double,
        rbPPW: Double,
        wrPPW: Double,
        tePPW: Double,
        kPPW: Double,
        dlPPW: Double,
        lbPPW: Double,
        dbPPW: Double,
        teamName: String,
        teamId: String? = nil
    ) {
        self.pointsFor = pointsFor
        self.ppw = ppw
        self.mgmt = mgmt
        self.offMgmt = offMgmt
        self.defMgmt = defMgmt
        self.recordPct = recordPct
        self.qbPPW = qbPPW
        self.rbPPW = rbPPW
        self.wrPPW = wrPPW
        self.tePPW = tePPW
        self.kPPW = kPPW
        self.dlPPW = dlPPW
        self.lbPPW = lbPPW
        self.dbPPW = dbPPW
        self.teamName = teamName
        self.teamId = teamId
    }
}

// --- Grading logic ---

func percentile(for value: Double, in sortedDescending: [Double]) -> Double {
    guard sortedDescending.count > 1 else { return 1.0 }
    guard let idx = sortedDescending.firstIndex(where: { $0 <= value }) else { return 0 }
    return 1.0 - (Double(idx) / Double(sortedDescending.count - 1))
}

func compositePercentileScore(
    for team: TeamGradeComponents,
    allTeams: [TeamGradeComponents]
) -> (Double, [String: Double]) {
    func p(_ keyPath: KeyPath<TeamGradeComponents, Double>) -> Double {
        percentile(for: team[keyPath: keyPath], in: allTeams.map { $0[keyPath: keyPath] }.sorted(by: >))
    }
    let pfP      = p(\.pointsFor)
    let ppwP     = p(\.ppw)
    let mgmtP    = p(\.mgmt)
    let offMgmtP = p(\.offMgmt)
    let defMgmtP = p(\.defMgmt)
    let recordP  = p(\.recordPct)
    let qbP      = p(\.qbPPW)
    let rbP      = p(\.rbPPW)
    let wrP      = p(\.wrPPW)
    let teP      = p(\.tePPW)
    let kP       = p(\.kPPW)
    let dlP      = p(\.dlPPW)
    let lbP      = p(\.lbPPW)
    let dbP      = p(\.dbPPW)

    let composite =
        pfP      * 0.10 +
        ppwP     * 0.20 +
        mgmtP    * 0.10 +
        offMgmtP * 0.05 +
        defMgmtP * 0.05 +
        recordP  * 0.25 +
        qbP      * 0.02 +
        rbP      * 0.03 +
        wrP      * 0.03 +
        teP      * 0.02 +
        kP       * 0.01 +
        dlP      * 0.03 +
        lbP      * 0.03 +
        dbP      * 0.03

    let breakdown: [String: Double] = [
        "Points For": pfP,
        "Points Per Week": ppwP,
        "Mgmt%": mgmtP,
        "Off Mgmt%": offMgmtP,
        "Def Mgmt%": defMgmtP,
        "Record": recordP,
        "QB Position Avg": qbP,
        "RB Position Avg": rbP,
        "WR Position Avg": wrP,
        "TE Position Avg": teP,
        "K Position Avg": kP,
        "DL Position Avg": dlP,
        "LB Position Avg": lbP,
        "DB Position Avg": dbP
    ]
    return (composite, breakdown)
}

// --- New: Offense-only composite scoring ---
// Notes:
// - This function computes a composite percentile score tailored to offense-only grading.
// - IMPORTANT: When calling this function (or gradeTeamsOffense), ensure the TeamGradeComponents
//   instance has pointsFor set to the team's OFFENSIVE Points For and ppw set to offensive PPW
//   (or otherwise ensure callers construct components with offensive values in those fields).
func compositePercentileScoreOffense(
    for team: TeamGradeComponents,
    allTeams: [TeamGradeComponents]
) -> (Double, [String: Double]) {
    func p(_ keyPath: KeyPath<TeamGradeComponents, Double>) -> Double {
        percentile(for: team[keyPath: keyPath], in: allTeams.map { $0[keyPath: keyPath] }.sorted(by: >))
    }

    let opfP   = p(\.pointsFor)   // Offensive Points For (caller should have populated this)
    let oppwP  = p(\.ppw)         // Offensive Points Per Week (caller should have populated this)
    let offMgmtP = p(\.offMgmt)
    let qbP    = p(\.qbPPW)
    let rbP    = p(\.rbPPW)
    let wrP    = p(\.wrPPW)
    let teP    = p(\.tePPW)
    let kP     = p(\.kPPW)

    // Formula provided:
    // OPF  * 0.25 +
    // OPPW * 0.25 +
    // offMgmtP * 0.25 +
    // qbP * 0.07 +
    // rbP * 0.06 +
    // wrP * 0.06 +
    // teP * 0.04 +
    // kP * 0.02
    let composite =
        opfP     * 0.25 +
        oppwP    * 0.25 +
        offMgmtP * 0.25 +
        qbP      * 0.07 +
        rbP      * 0.06 +
        wrP      * 0.06 +
        teP      * 0.04 +
        kP       * 0.02

    let breakdown: [String: Double] = [
        "Off Points For (OPF)": opfP,
        "Off Points Per Week (OPPW)": oppwP,
        "Off Mgmt%": offMgmtP,
        "QB Position Avg": qbP,
        "RB Position Avg": rbP,
        "WR Position Avg": wrP,
        "TE Position Avg": teP,
        "K Position Avg": kP
    ]

    return (composite, breakdown)
}

// --- New: Defense-only composite scoring ---
// Notes:
// - This function computes a composite percentile score tailored to defense-only grading.
// - IMPORTANT: When calling this function (or gradeTeamsDefense), ensure the TeamGradeComponents
//   instance has pointsFor set to the team's DEFENSIVE Points For and ppw set to defensive PPW
//   (or otherwise ensure callers construct components with defensive values in those fields).
func compositePercentileScoreDefense(
    for team: TeamGradeComponents,
    allTeams: [TeamGradeComponents]
) -> (Double, [String: Double]) {
    func p(_ keyPath: KeyPath<TeamGradeComponents, Double>) -> Double {
        percentile(for: team[keyPath: keyPath], in: allTeams.map { $0[keyPath: keyPath] }.sorted(by: >))
    }

    let dpfP   = p(\.pointsFor)   // Defensive Points For (caller should have populated this)
    let dppwP  = p(\.ppw)         // Defensive Points Per Week (caller should have populated this)
    let defMgmtP = p(\.defMgmt)
    let dlP    = p(\.dlPPW)
    let lbP    = p(\.lbPPW)
    let dbP    = p(\.dbPPW)

    // Formula provided:
    // DPF * 0.25 +
    // DPPW * 0.30 +
    // defMgmtP * 0.30 +
    // dlP * 0.05 +
    // lbP * 0.05 +
    // dbP * 0.05
    let composite =
        dpfP     * 0.25 +
        dppwP    * 0.30 +
        defMgmtP * 0.30 +
        dlP      * 0.05 +
        lbP      * 0.05 +
        dbP      * 0.05

    let breakdown: [String: Double] = [
        "Def Points For (DPF)": dpfP,
        "Def Points Per Week (DPPW)": dppwP,
        "Def Mgmt%": defMgmtP,
        "DL Position Avg": dlP,
        "LB Position Avg": lbP,
        "DB Position Avg": dbP
    ]

    return (composite, breakdown)
}

func gradeForComposite(_ composite: Double) -> String {
    switch composite {
    case 0.90...1: return "A+"
    case 0.80..<0.90: return "A"
    case 0.70..<0.80: return "A-"
    case 0.60..<0.70: return "B+"
    case 0.50..<0.60: return "B"
    case 0.40..<0.50: return "B-"
    case 0.30..<0.40: return "C+"
    case 0.20..<0.30: return "C"
    case 0.10..<0.20: return "C-"
    case 0.0..<0.10: return "F"
    default: return "C+"
    }
}

// --- Convenience grading functions ---

/// Grade teams using the original composite (overall) formula (backwards-compatible).
func gradeTeams(_ teams: [TeamGradeComponents]) -> [(String, String, Double, [String: Double])] {
    teams.map { team in
        let (score, breakdown) = compositePercentileScore(for: team, allTeams: teams)
        let grade = gradeForComposite(score)
        return (team.teamName, grade, score, breakdown)
    }
}

/// Grade teams using the offense-only composite formula.
/// IMPORTANT: Each TeamGradeComponents in `teams` should have pointsFor and ppw set to offense-specific values
/// (i.e., offensivePointsFor and offensivePPW) for correct percentiles.
func gradeTeamsOffense(_ teams: [TeamGradeComponents]) -> [(String, String, Double, [String: Double])] {
    teams.map { team in
        let (score, breakdown) = compositePercentileScoreOffense(for: team, allTeams: teams)
        let grade = gradeForComposite(score)
        return (team.teamName, grade, score, breakdown)
    }
}

/// Grade teams using the defense-only composite formula.
/// IMPORTANT: Each TeamGradeComponents in `teams` should have pointsFor and ppw set to defense-specific values
/// (i.e., defensivePointsFor and defensivePPW) for correct percentiles.
func gradeTeamsDefense(_ teams: [TeamGradeComponents]) -> [(String, String, Double, [String: Double])] {
    teams.map { team in
        let (score, breakdown) = compositePercentileScoreDefense(for: team, allTeams: teams)
        let grade = gradeForComposite(score)
        return (team.teamName, grade, score, breakdown)
    }
}
