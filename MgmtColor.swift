//
//  MgmtColor.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 9/21/25.
//  Centralized management-percent color mapping used across the app.
//

import SwiftUI

extension Color {
    static let mgmtSilverBlue = Color(red: 162/255, green: 209/255, blue: 241/255)
    static let mgmtGold = Color(red: 212/255, green: 175/255, blue: 55/255)
    static let mgmtLime = Color(red: 50/255, green: 205/255, blue: 50/255)
    static let mgmtAmber = Color(red: 255/255, green: 191/255, blue: 0/255)
    static let mgmtFieryRed = Color(red: 255/255, green: 69/255, blue: 0/255)

    static func mgmtPercentColor(_ percent: Double) -> Color {
        let p = percent
        switch p {
        case 95...100:
            return .mgmtGold
        case 90..<95:
            return .mgmtSilverBlue
        case 80..<90:
            return .mgmtLime
        case 75..<80:
            return .mgmtAmber
        case 0..<60:
            return .mgmtFieryRed
        default:
            return .gray
        }
    }

    /// Alias to match older helper naming used in some files.
    /// Prefer calling mgmtPercentColor(:) directly for clarity.
    static func mgmtColor(for percent: Double) -> Color {
        return mgmtPercentColor(percent)
    }
}

struct MgmtPercentView: View {
    let percent: Double
    @State private var shimmerPhase: CGFloat = 0.0 // For animation timing
    @Environment(\.accessibilityReduceMotion) var accessibilityReduceMotion
    
    var body: some View {
        let color = Color.mgmtPercentColor(percent)
        let isGold = percent >= 95
        
        ZStack {
            Text(String(format: "%.1f%%", percent))
                .foregroundColor(color)
                .font(.system(size: 16))
                .fontWeight(isGold ? .bold : .regular)
            
            if isGold && !accessibilityReduceMotion {
                // Shimmer layer: Gradient mask moves left-to-right (only if motion not reduced)
                Text(String(format: "%.1f%%", percent))
                    .foregroundColor(color)
                    .font(.system(size: 16, weight: .bold))
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: shimmerPhase - 0.3),
                                .init(color: .white, location: shimmerPhase),
                                .init(color: .clear, location: shimmerPhase + 0.3)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .onAppear {
                        // Repeat every 5 seconds (only if motion not reduced)
                        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                            withAnimation(.easeInOut(duration: 1.5)) {
                                shimmerPhase = shimmerPhase == 0 ? 1.5 : 0 // Toggle phase for movement
                            }
                        }.fire() // Start immediately
                    }
            }
        }
        .padding(8)
        .background(color.opacity(0.2))
    }
}
