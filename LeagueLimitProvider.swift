//
//  LeagueLimitProvider.swift
//  DynastyStatDrop
//
//  Canonical single source for league import limits.
//  (Ensures no duplicate declarations elsewhere.)
//

import Foundation

protocol LeagueLimitProvider {
    func currentLimit(for username: String?) -> Int
}

struct DefaultLeagueLimitProvider: LeagueLimitProvider {
    // Adjust freely or drive from remote config / entitlement flags.
    private let freeLimit = 3
    private let proLimit = 12

    func currentLimit(for username: String?) -> Int {
        guard let u = username, !u.isEmpty else { return freeLimit }
        if UserDefaults.standard.bool(forKey: "dsd.entitlement.pro.\(u)") {
            return proLimit
        }
        return freeLimit
    }
}
