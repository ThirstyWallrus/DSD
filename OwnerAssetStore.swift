//
//  OwnerAssetStore.swift
//  DynastyStatDrop
//
//  MIGRATED to disk‑backed storage.
//  - Old (v1) behavior: All images base64‑encoded into a single UserDefaults blob (udKey: dsd.owner.images.v1).
//    This inflated memory & launch time for many / large images.
//  - New (v2) behavior: Persist each image as an individual PNG under Application Support / OwnerImages,
//    and store a lightweight index [ownerId: fileName] in UserDefaults (index key: dsd.owner.images.index.v2).
//  - Automatic one‑time migration runs on first init if old blob exists and new index absent.
//
//  Public API kept source‑compatible:
//     image(for:), setImage(for:image:), remove(ownerId:)
//  Added conveniences:
//     preloadAll()      – eagerly load all disk images into memory (optional)
//     clearDisk()       – remove all stored images (index + files)
//     memoryFootprint() – approximate in‑memory bytes of cached UIImages
//
//  Notes:
//  - Images are loaded lazily; requesting image(for:) for an uncached owner triggers a disk read.
//  - An in‑memory NSCache reduces repeated decoding cost; @Published images retains only those
//    explicitly loaded or set this run (so SwiftUI views can observe changes).
//

import SwiftUI

@MainActor
final class OwnerAssetStore: ObservableObject {
    static let shared = OwnerAssetStore()

    // Published dictionary (only populated for images loaded / set during this session)
    @Published private(set) var images: [String: UIImage] = [:]

    // MARK: Keys / Paths
    private let legacyUDKey = "dsd.owner.images.v1"          // old monolithic base64 dictionary
    private let indexUDKey  = "dsd.owner.images.index.v2"    // new mapping ownerId -> fileName
    private let directoryName = "OwnerImages"

    // Lightweight index (ownerId -> fileName.png)
    private var index: [String: String] = [:]

    // Memory cache (allows eviction under pressure automatically)
    private let cache = NSCache<NSString, UIImage>()

    // MARK: Init
    private init() {
        migrateIfNeeded()
        loadIndex()
    }

    // MARK: Public API

    /// SwiftUI Image wrapper (returns nil if not found).
    func image(for ownerId: String) -> Image? {
        guard let ui = uiImage(for: ownerId) else { return nil }
        return Image(uiImage: ui)
    }

    /// Underlying UIImage (lazy loads from disk if needed).
    func uiImage(for ownerId: String) -> UIImage? {
        if let mem = images[ownerId] { return mem }
        if let cached = cache.object(forKey: ownerId as NSString) {
            images[ownerId] = cached
            return cached
        }
        guard let fileName = index[ownerId],
              let data = try? Data(contentsOf: imageDirectory().appendingPathComponent(fileName)),
              let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: ownerId as NSString)
        images[ownerId] = img
        return img
    }

    /// Store / overwrite an image for an owner.
    func setImage(for ownerId: String, image: UIImage) {
        do {
            try ensureDirectory()
            // Remove prior file if exists
            if let old = index[ownerId] {
                try? FileManager.default.removeItem(at: imageDirectory().appendingPathComponent(old))
            }
            // Encode (PNG). If PNG fails (rare), fallback to JPEG(0.9).
            let fileName = "\(UUID().uuidString).png"
            let url = imageDirectory().appendingPathComponent(fileName)
            if let data = image.pngData() {
                try data.write(to: url, options: .atomic)
            } else if let jpeg = image.jpegData(compressionQuality: 0.9) {
                let jpegURL = url.deletingPathExtension().appendingPathExtension("jpg")
                try jpeg.write(to: jpegURL, options: .atomic)
                index[ownerId] = jpegURL.lastPathComponent
                persistIndex()
                cache.setObject(image, forKey: ownerId as NSString)
                images[ownerId] = image
                return
            } else {
                print("[OwnerAssetStore] Failed to encode image for ownerId \(ownerId)")
                return
            }
            index[ownerId] = fileName
            persistIndex()
            cache.setObject(image, forKey: ownerId as NSString)
            images[ownerId] = image
        } catch {
            print("[OwnerAssetStore] setImage error: \(error)")
        }
    }

    /// Remove image for owner (memory + disk + index).
    func remove(ownerId: String) {
        if let fileName = index[ownerId] {
            let url = imageDirectory().appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: url)
        }
        index.removeValue(forKey: ownerId)
        persistIndex()
        cache.removeObject(forKey: ownerId as NSString)
        images.removeValue(forKey: ownerId)
    }

    /// Eagerly read all disk images (optional; can increase memory).
    func preloadAll() {
        for ownerId in index.keys {
            _ = uiImage(for: ownerId)
        }
    }

    /// Remove all images & index (use with caution).
    func clearDisk() {
        let dir = imageDirectory()
        if FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
        index.removeAll()
        persistIndex()
        images.removeAll()
        cache.removeAllObjects()
    }

    /// Approximate in‑memory footprint in bytes (decoded UIImages currently retained).
    func memoryFootprint() -> Int {
        images.values.reduce(0) { total, img in
            guard let cg = img.cgImage else { return total }
            // rough = bytesPerRow * height
            return total + (cg.bytesPerRow * cg.height)
        }
    }

    // MARK: - Migration

    /// If we find the legacy base64 blob and no v2 index, migrate.
    private func migrateIfNeeded() {
        let ud = UserDefaults.standard
        guard ud.data(forKey: indexUDKey) == nil, // no new index yet
              let legacyData = ud.data(forKey: legacyUDKey),
              let legacyDict = try? JSONDecoder().decode([String:String].self, from: legacyData),
              !legacyDict.isEmpty
        else { return }

        print("[OwnerAssetStore] Migrating \(legacyDict.count) legacy images to disk…")
        do {
            try ensureDirectory()
            var newIndex: [String: String] = [:]
            for (ownerId, b64) in legacyDict {
                guard let data = Data(base64Encoded: b64),
                      let img = UIImage(data: data) else { continue }
                let fileName = "\(UUID().uuidString).png"
                let url = imageDirectory().appendingPathComponent(fileName)
                if let png = img.pngData() {
                    try png.write(to: url, options: .atomic)
                    newIndex[ownerId] = fileName
                }
                // Keep in‑memory for immediate availability this launch
                images[ownerId] = img
                cache.setObject(img, forKey: ownerId as NSString)
            }
            index = newIndex
            persistIndex()
            ud.removeObject(forKey: legacyUDKey)
            print("[OwnerAssetStore] Migration complete. Stored \(newIndex.count) images.")
        } catch {
            print("[OwnerAssetStore] Migration failed: \(error)")
        }
    }

    // MARK: - Index Persistence

    private func loadIndex() {
        let ud = UserDefaults.standard
        guard let data = ud.data(forKey: indexUDKey) else { return }
        if let dict = try? JSONDecoder().decode([String:String].self, from: data) {
            index = dict
        }
    }

    private func persistIndex() {
        let ud = UserDefaults.standard
        if let data = try? JSONEncoder().encode(index) {
            ud.set(data, forKey: indexUDKey)
        }
    }

    // MARK: - Directory Helpers

    private func imageDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    private func ensureDirectory() throws {
        var dir = imageDirectory()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Exclude from iCloud backup (optional)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try dir.setResourceValues(resourceValues)
        }
    }
}
