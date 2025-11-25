//
//  CustomizationSets.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 8/22/25.
//


import Foundation

// MARK: - Public Structures

struct CustomizationSets {
    var standings: Set<Category>
    var team: Set<Category>
    var offensive: Set<Category>
    var defensive: Set<Category>
}

private struct DashboardCustomizationPayload: Codable {
    let version: Int
    let selections: [String: [String]]
}

// MARK: - Store


@MainActor
final class DashboardCustomizationStore {
    static let shared = DashboardCustomizationStore()
    private init() {}

    private let defaults = UserDefaults.standard
    private let version = 1

    func load(for username: String, leagueId: String?) -> CustomizationSets? {
        let key = makeKey(username: username, leagueId: leagueId)
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let payload = try? JSONDecoder().decode(DashboardCustomizationPayload.self, from: data) else { return nil }

        func mapList(_ id: String) -> Set<Category> {
            let rawList = payload.selections[id] ?? []
            let mapped = rawList.compactMap { Category(rawValue: $0) }
            return Set(mapped.prefix(3))
        }

        return CustomizationSets(
            standings: mapList("standings"),
            team: mapList("teamStats"),
            offensive: mapList("offensive"),
            defensive: mapList("defensive")
        )
    }

    func save(sets: CustomizationSets, for username: String, leagueId: String?) {
        let key = makeKey(username: username, leagueId: leagueId)
        let payload = DashboardCustomizationPayload(
            version: version,
            selections: [
                "standings": sets.standings.map { $0.rawValue },
                "teamStats": sets.team.map { $0.rawValue },
                "offensive": sets.offensive.map { $0.rawValue },
                "defensive": sets.defensive.map { $0.rawValue }
            ]
        )
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: key)
        }
    }

    private func makeKey(username: String, leagueId: String?) -> String {
        let userComponent = username.isEmpty ? "anon" : username
        let leagueComponent = leagueId ?? "__global"
        return "dashboard.customization.\(userComponent).\(leagueComponent)"
    }
}
