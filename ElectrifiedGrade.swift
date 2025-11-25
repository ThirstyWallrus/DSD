import SwiftUI

struct ElectrifiedGrade: View {
    let grade: String
    var fontSize: CGFloat = 36

    // Flicker config
    private let flickerInterval: Double = 30.0
    private let flickerDuration: Double = 0.35
    private let boltFlashDuration: Double = 0.35 // How long the lightning bolt flashes

    @State private var fadedIn: Bool = false
    @State private var showBolt: Bool = false
    @State private var flickerPhase: Int = 0
    @State private var isFlicker: Bool = false

    var color: Color {
        switch grade {
        case "A+", "A", "A-": return .green
        case "B+", "B", "B-": return .yellow
        case "C+", "C", "C-": return .orange
        default: return .gray
        }
    }
    var boltColor: Color {
        switch grade {
        case "A+", "A", "A-": return .cyan
        case "B+", "B", "B-": return .yellow
        case "C+", "C", "C-": return .orange
        default: return .gray
        }
    }

    var body: some View {
        ZStack {
            // Lightning bolt: flashes in, then disappears!
            if showBolt {
                CenterLightningFlash(
                    fontSize: fontSize,
                    color: boltColor,
                    flash: true
                )
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .center)))
            }

            // Grade (fades in, then flickers every so often)
            Text(grade)
                .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                .foregroundColor(color)
                .shadow(color: boltColor.opacity(0.19), radius: 2)
                .opacity(fadedIn
                         ? (isFlicker ? flickerOpacity : 1.0)
                         : 0)
                .animation(.easeOut(duration: 1.5), value: fadedIn)
                .animation(.linear(duration: 0.06), value: isFlicker)
        }
        .frame(width: fontSize * 2.2, height: fontSize * 2.2)
        .onAppear {
            // Lightning bolt flash when grade appears
            showBolt = true
            withAnimation(.easeOut(duration: 1.5)) {
                fadedIn = true
            }
            // Bolt disappears quickly after a flash
            DispatchQueue.main.asyncAfter(deadline: .now() + boltFlashDuration) {
                withAnimation(.easeIn(duration: 0.15)) {
                    showBolt = false
                }
            }
            flickerLoop()
        }
    }

    // Flicker randomly between 0.4 and 1.0 for a "spark" look
    private var flickerOpacity: Double {
        [0.35, 0.75, 0.12, 1.0][flickerPhase % 4]
    }

    private func flickerLoop() {
        Task {
            while true {
                try? await Task.sleep(nanoseconds: UInt64(flickerInterval * 1_000_000_000))
                for phase in 0..<6 {
                    DispatchQueue.main.async {
                        flickerPhase = phase
                        isFlicker = true
                    }
                    try? await Task.sleep(nanoseconds: UInt64((flickerDuration / 6) * 1_000_000_000))
                }
                DispatchQueue.main.async {
                    isFlicker = false
                }
            }
        }
    }
}

// MARK: - Center Lightning Bolt FLASH

private struct CenterLightningFlash: View {
    let fontSize: CGFloat
    let color: Color
    let flash: Bool

    var body: some View {
        ZStack {
            // Outer glow
            LightningPath(fontSize: fontSize)
                .stroke(
                    color.opacity(0.35),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 2)
            // Core white-hot bolt
            LightningPath(fontSize: fontSize)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
            // Core colored bolt
            LightningPath(fontSize: fontSize)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 2.7, lineCap: .round, lineJoin: .round)
                )
        }
        .frame(width: fontSize * 2.2, height: fontSize * 2.2)
        .scaleEffect(flash ? 1 : 0.9)
        .opacity(flash ? 1 : 0)
        .animation(.easeOut(duration: 0.14), value: flash)
    }
}

// MARK: - Lightning Path

private struct LightningPath: Shape {
    let fontSize: CGFloat

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let centerX = width / 2
        let centerY = height / 2
        let boltLength = fontSize * 1.5
        let points = 9

        var path = Path()
        let startY = centerY - boltLength / 2
        let segment = boltLength / CGFloat(points - 1)

        path.move(to: CGPoint(x: centerX, y: startY))
        for i in 1..<points {
            let y = startY + CGFloat(i) * segment
            // Stronger jagged effect, more energetic!
            let phase = Double(i) * 1.2
            let x = centerX + CGFloat(sin(phase) * Double(fontSize) * (i % 2 == 0 ? 0.23 : -0.14)) +
                CGFloat.random(in: -fontSize * 0.14...fontSize * 0.14)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}
