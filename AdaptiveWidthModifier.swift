//
//  AdaptiveWidth.swift
//  DynastyStatDrop
//
//  Simplified responsive width helpers (NO GeometryReader).
//  Fix: Previous version used GeometryReader at the root of ScrollView content,
//       preventing vertical scrolling (content height matched viewport).
//
//  Usage:
//     VStack { ... }.adaptiveWidth()          // clamps to 860, centers, adds horizontal padding
//     VStack { ... }.adaptiveWidth(max: 600)
//     Image(...).adaptiveLogo()               // responsive logo sizing
//

import SwiftUI

private struct AdaptiveWidthModifier: ViewModifier {
    let max: CGFloat
    let padding: CGFloat
    let fillVertical: Bool
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, padding)
            .frame(maxWidth: max, alignment: .center)
            // Expand horizontally so centering works in wider parents
            .frame(maxWidth: .infinity, alignment: .center)
            // Optionally ensure at least viewport height (off by default to preserve scroll)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .frame(minHeight: fillVertical ? geo.size.height : 0)
                }
            )
    }
}

public extension View {
    /// Clamp width for readability & responsiveness. No GeometryReader expansion, safe in ScrollViews.
    func adaptiveWidth(max: CGFloat = 860,
                       padding: CGFloat = 16,
                       fillVertical: Bool = false) -> some View {
        modifier(AdaptiveWidthModifier(max: max, padding: padding, fillVertical: fillVertical))
    }

    /// Adaptive logo sizing: shrinks on small devices, capped on large ones.
    func adaptiveLogo(max: CGFloat = 500, screenFraction: CGFloat = 0.9) -> some View {
        let deviceWidth = UIScreen.main.bounds.width
        return self
            .frame(maxWidth: min(max, deviceWidth * screenFraction))
    }
}
