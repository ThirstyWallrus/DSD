//
//  FontLoader.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 12/4/25.
//


//
//  FontLoader.swift
//  DynastyStatDrop
//
//  Purpose:
//   - Programmatically register bundled .ttf/.otf fonts at app startup using CoreText.
//   - Provide diagnostics (family names, font names, PostScript names) to help find the
//     exact name to use with Font.custom(...) and UIFont(name:...).
//   - Provide helper to find a PostScript name matching a friendly name like "Phatt".
//
//  Usage:
//   FontLoader.registerAllBundleFonts()
//   let postScript = FontLoader.postScriptName(matching: "Phatt") // optional
//

import Foundation
import UIKit
import CoreText

enum FontLoader {
    /// Register all .ttf/.otf files that are in the main bundle (non-recursive).
    /// Prints diagnostics to the console indicating success/failure and available names.
    static func registerAllBundleFonts() {
        let bundle = Bundle.main
        let candidateExtensions = ["ttf", "otf"]
        var registeredFiles: [String] = []
        var failedFiles: [(String, String)] = []

        for ext in candidateExtensions {
            if let urls = bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                for url in urls {
                    let filename = url.lastPathComponent
                    var error: Unmanaged<CFError>?
                    let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
                    if success {
                        print("[FontLoader] Registered font file: \(filename)")
                        registeredFiles.append(filename)
                    } else {
                        let msg = error?.takeRetainedValue().localizedDescription ?? "unknown error"
                        print("[FontLoader] FAILED to register \(filename): \(msg)")
                        failedFiles.append((filename, msg))
                    }
                }
            }
        }

        // Diagnostics: list families and font names
        logAvailableFonts(prefix: "[FontLoader]")

        if registeredFiles.isEmpty && failedFiles.isEmpty {
            print("[FontLoader] No bundled .ttf/.otf fonts found in Bundle.main.")
        } else {
            if !registeredFiles.isEmpty {
                print("[FontLoader] Registered files: \(registeredFiles.joined(separator: ", "))")
            }
            if !failedFiles.isEmpty {
                print("[FontLoader] Registration failures: \(failedFiles.map { "\($0.0): \($0.1)" }.joined(separator: "; "))")
            }
        }
    }

    /// Attempt to register a single filename (useful if fonts are inside a subfolder inside the bundle)
    static func registerFont(filename: String) {
        guard let url = Bundle.main.url(forResource: filename, withExtension: nil) else {
            print("[FontLoader] Could not find \(filename) in Bundle.main")
            return
        }
        var error: Unmanaged<CFError>?
        let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if success {
            print("[FontLoader] Registered font file: \(filename)")
        } else {
            let msg = error?.takeRetainedValue().localizedDescription ?? "unknown error"
            print("[FontLoader] FAILED to register \(filename): \(msg)")
        }
        logAvailableFonts(prefix: "[FontLoader]")
    }

    /// Logs available UIFont families and their font names (POSTSCRIPT names) to console.
    static func logAvailableFonts(prefix: String = "") {
        let families = UIFont.familyNames.sorted()
        print("\(prefix) Available font families (\(families.count)):")
        for fam in families {
            let names = UIFont.fontNames(forFamilyName: fam)
            print("  \(fam): \(names)")
        }
    }

    /// Return a PostScript name (UIFont name) that appears to match the given friendly name.
    /// Strategy:
    /// 1) Try to find any font family whose family name contains the match string (case-insensitive),
    ///    and return the first font name from that family.
    /// 2) If not found, search across all font names for a font name containing the match string.
    /// 3) As a last resort, try to read bundled font files and extract CGFont postScript names.
    static func postScriptName(matching friendlyName: String) -> String? {
        let lower = friendlyName.lowercased()
        // 1) family contains friendlyName
        for fam in UIFont.familyNames {
            if fam.lowercased().contains(lower) {
                let names = UIFont.fontNames(forFamilyName: fam)
                if let first = names.first {
                    print("[FontLoader] Found PostScript name '\(first)' for family '\(fam)' (matched by family).")
                    return first
                }
            }
        }
        // 2) direct font name contains friendlyName
        for fam in UIFont.familyNames {
            let names = UIFont.fontNames(forFamilyName: fam)
            for n in names {
                if n.lowercased().contains(lower) {
                    print("[FontLoader] Found PostScript name '\(n)' (matched by font name).")
                    return n
                }
            }
        }
        // 3) Inspect bundled font files (ttf/otf) and extract postScript name from CGFont
        let candidateExtensions = ["ttf", "otf"]
        for ext in candidateExtensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                for url in urls {
                    if let ps = postScriptNameFromFontFile(url: url) {
                        if ps.lowercased().contains(lower) || url.lastPathComponent.lowercased().contains(lower) {
                            print("[FontLoader] Found PostScript name '\(ps)' from file \(url.lastPathComponent).")
                            return ps
                        }
                    }
                }
            }
        }
        // nothing found
        print("[FontLoader] No PostScript name matched '\(friendlyName)'.")
        return nil
    }

    /// Extract PostScript name directly from a font file URL using CGFont.
    private static func postScriptNameFromFontFile(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        guard let cgFont = CGFont(provider) else { return nil }
        if let psName = cgFont.postScriptName as String? {
            return psName
        }
        return nil
    }
}