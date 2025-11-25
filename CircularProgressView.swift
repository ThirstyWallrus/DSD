//
//  CircularProgressView.swift
//  DynastyStatDrop
//
//  Shared UI components used by balance/info sheets.
//  Contains: CircularProgressView, PositionGauge, BalanceGauge.
//  NOTE: Flame/Glow/Ice decorative effects have been removed for simplicity/consistency.
//

import SwiftUI

// MARK: - Circular / Decorative Visuals

public struct CircularProgressView: View {
    public var progress: Double
    public var tintColor: Color
    public var lineWidth: CGFloat = 5

    private var arcColor: Color {
        // Use tintColor as primary color and subtly shift hue based on progress for contrast.
        // Keep calculation simple and deterministic.
        let hueShift = CGFloat(max(0.0, min(1.0, progress)) * 0.08)
        return tintColor.adjusted(hueShift: hueShift)
    }

    private var backgroundCircle: some View {
        Circle()
            .stroke(Color.white.opacity(0.18), lineWidth: lineWidth)
    }

    private var progressArc: some View {
        Circle()
            .trim(from: 0, to: max(0, min(1, progress)))
            .stroke(arcColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }

    private var progressDot: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 8, height: 8)
            .offset(y: -30)
            .rotationEffect(.degrees(360 * progress - 90))
    }

    private var progressText: some View {
        Text(String(format: "%.0f%%", progress * 100))
            .font(.caption)
            .bold()
            .foregroundColor(.white)
    }

    public init(progress: Double, tintColor: Color, lineWidth: CGFloat = 5) {
        self.progress = progress
        self.tintColor = tintColor
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            backgroundCircle
            progressArc
            progressDot
            progressText
        }
        .frame(width: 60, height: 60)
    }
}

// Simple Color extension to allow a subtle hue adjustment without importing extra libs.
// This keeps visuals consistent while removing heavy decorative effects.
fileprivate extension Color {
    func adjusted(hueShift: CGFloat) -> Color {
        #if os(iOS) || os(watchOS) || os(tvOS)
        // Try to convert to UIColor and shift hue — fallback to original color on failure.
        if let ui = UIColor(self).hsbAdjusted(hueShift: hueShift) {
            return Color(ui)
        }
        return self
        #else
        return self
        #endif
    }
}

#if os(iOS) || os(watchOS) || os(tvOS)
import UIKit
fileprivate extension UIColor {
    // Returns a new UIColor with hue shifted by hueShift in [-1,1], preserving saturation/brightness/alpha.
    func hsbAdjusted(hueShift: CGFloat) -> UIColor? {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard self.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return nil }
        let newHue = CGFloat(fmod(Double(h + hueShift + 1.0), 1.0))
        return UIColor(hue: newHue, saturation: s, brightness: b, alpha: a)
    }
}
#endif

// MARK: - Position / Balance Gauges (shared)

public struct PositionGauge: View {
    public let pos: String
    public let pct: Double
    public let color: Color

    public init(pos: String, pct: Double, color: Color) {
        self.pos = pos
        self.pct = pct
        self.color = color
    }

    public var body: some View {
        VStack(spacing: 4) {
            CircularProgressView(progress: pct / 100.0, tintColor: color)
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(pos)
                    .font(.caption2)
                    .bold()
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(width: 80)
    }
}

public struct BalanceGauge: View {
    public let balance: Double

    public init(balance: Double) {
        self.balance = balance
    }

    private var color: Color {
        balance < 8 ? .green : (balance < 16 ? .yellow : .red)
    }

    public var body: some View {
        VStack(spacing: 4) {
            CircularProgressView(progress: balance / 100.0, tintColor: color)
            // Invisible placeholder to match height and alignment
            Text(" ")
                .font(.caption2)
                .bold()
                .foregroundColor(.clear)
        }
        .frame(width: 80)
    }
}
