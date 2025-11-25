//
//  FlipExpandModel.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 8/22/25.
//


//
//  FlipExpandModel.swift
//  DynastyStatDrop
//
//  Encapsulates shared state & helpers for flip + expand and customization expand flows.
//

import SwiftUI
import Combine

@MainActor
final class FlipExpandModel: ObservableObject {
    // Which main section index (0..3) is in flip-detail expansion
    @Published var expandedSection: Int? = nil
    // Which section index is in customization (expand+fade) mode
    @Published var customizingSection: Int? = nil

    // Flip progress 0.0 → 1.0 (drives diagonal rotation)
    @Published var flipProgress: CGFloat = 0
    // Midpoint toggle to show detail content
    @Published var showDetailContent: Bool = false

    // Accessibility + motion
    @Published var reducedMotion: Bool = UIAccessibility.isReduceMotionEnabled

    // Haptic gating
    private var lastHapticDate: Date = .distantPast
    private let hapticCooldown: TimeInterval = 0.35

    var isAnyOverlayActive: Bool {
        expandedSection != nil || customizingSection != nil
    }

    // MARK: - Public Control

    func beginFlip(for index: Int) {
        guard customizingSection == nil else { return } // do not flip while customizing
        if expandedSection == index {
            // Already expanded -> collapse
            collapse()
            return
        }
        guard expandedSection == nil else {
            // Collapse current then open new
            collapse {
                self.internalStartFlip(for: index)
            }
            return
        }
        internalStartFlip(for: index)
    }

    func beginCustomize(for index: Int) {
        guard expandedSection == nil else { return } // cannot customize while detail open
        if customizingSection == index {
            collapse()
            return
        }
        guard customizingSection == nil else {
            collapseCustomization {
                self.startCustomize(index)
            }
            return
        }
        startCustomize(index)
    }

    func collapse(_ completion: (() -> Void)? = nil) {
        if let _ = expandedSection {
            withAnimation(.easeInOut(duration: reducedMotion ? 0.25 : 0.55)) {
                flipProgress = 0
                showDetailContent = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (reducedMotion ? 0.25 : 0.55)) {
                self.expandedSection = nil
                completion?()
            }
        } else if let _ = customizingSection {
            collapseCustomization(completion)
        } else {
            completion?()
        }
        impact()
    }

    func collapseCustomization(_ completion: (() -> Void)? = nil) {
        if customizingSection != nil {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                customizingSection = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                completion?()
            }
            impact()
        } else {
            completion?()
        }
    }

    // MARK: - Internal

    private func internalStartFlip(for index: Int) {
        expandedSection = index
        flipProgress = 0
        showDetailContent = false
        impact()
        if reducedMotion {
            withAnimation(.easeInOut(duration: 0.35)) {
                flipProgress = 1
                showDetailContent = true
            }
            return
        }
        // Phase animation
        withAnimation(.easeInOut(duration: 0.55)) {
            flipProgress = 1
        }
        // Midpoint content swap ~0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            if self.expandedSection == index {
                withAnimation(.easeInOut(duration: 0.22)) {
                    self.showDetailContent = true
                }
            }
        }
    }

    private func startCustomize(_ index: Int) {
        customizingSection = index
        impact()
    }

    // MARK: - Haptics
    private func impact() {
        #if os(iOS)
        guard !reducedMotion else { return }
        let now = Date()
        guard now.timeIntervalSince(lastHapticDate) > hapticCooldown else { return }
        lastHapticDate = now
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
