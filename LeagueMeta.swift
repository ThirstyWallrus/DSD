//
//  LeagueMeta.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 9/1/25.
//


import Foundation

// Lightweight metadata to populate lists without loading full heavy payloads if ever needed.
struct LeagueMeta: Codable {
    let id: String
    let name: String
    let season: String
    let lastUpdated: Date
}

@MainActor
final class LeagueDiskStore {

    static let shared = LeagueDiskStore()

    private init() {
        try? ensureDirs()
        loadIndex()
    }

    // MARK: Public State
    private(set) var metas: [LeagueMeta] = []

    // MARK: Paths / Keys
    private let dirName = "Leagues"
    private let indexFile = "index.json"

    private func baseDir() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent(dirName, isDirectory: true)
    }

    private func fileURL(_ leagueId: String) -> URL {
        baseDir().appendingPathComponent("\(leagueId).json")
    }

    private func indexURL() -> URL {
        baseDir().appendingPathComponent(indexFile)
    }

    private func ensureDirs() throws {
        var dir = baseDir()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var rv = URLResourceValues()
            rv.isExcludedFromBackup = true
            try dir.setResourceValues(rv)
        }
    }

    // MARK: Index Handling
    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL()),
              let arr = try? JSONDecoder().decode([LeagueMeta].self, from: data) else {
            metas = []
            return
        }
        metas = arr
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(metas) else { return }
        do {
            try data.write(to: indexURL(), options: .atomic)
        } catch {
            print("[LeagueDiskStore] Failed to write index: \(error)")
        }
    }

    // MARK: CRUD
    func saveLeague(_ league: LeagueData) {
        do {
            try ensureDirs()
            let data = try JSONEncoder().encode(league)
            try data.write(to: fileURL(league.id), options: .atomic)
            upsertMeta(for: league)
        } catch {
            print("[LeagueDiskStore] saveLeague error: \(error)")
        }
    }

    func loadLeague(id: String) -> LeagueData? {
        do {
            let data = try Data(contentsOf: fileURL(id))
            return try JSONDecoder().decode(LeagueData.self, from: data)
        } catch {
            return nil
        }
    }

    func deleteLeague(id: String) {
        try? FileManager.default.removeItem(at: fileURL(id))
        metas.removeAll { $0.id == id }
        persistIndex()
    }

    func loadAllLeagues() -> [LeagueData] {
        metas.compactMap { loadLeague(id: $0.id) }
    }

    func clearAll() {
        for m in metas {
            try? FileManager.default.removeItem(at: fileURL(m.id))
        }
        metas.removeAll()
        persistIndex()
    }

    // MARK: Helpers
    private func upsertMeta(for league: LeagueData) {
        let meta = LeagueMeta(id: league.id,
                              name: league.name,
                              season: league.season,
                              lastUpdated: Date())
        if let idx = metas.firstIndex(where: { $0.id == league.id }) {
            metas[idx] = meta
        } else {
            metas.append(meta)
        }
        persistIndex()
    }
}
