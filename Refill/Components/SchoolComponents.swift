import SwiftUI

// Small icon badge used in cards, tab bars, onboarding.
struct SymbolBadge: View {
    var system: String
    var color: Color
    var size: CGFloat = 44
    var symbolSize: CGFloat? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(color.opacity(0.18))
            RoundedRectangle(cornerRadius: size * 0.28)
                .stroke(color.opacity(0.45), lineWidth: 1.5)
            Image(systemName: system)
                .font(.system(size: symbolSize ?? size * 0.5, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

// Pill-style tag (e.g. "URGENT", "STEM").
struct SchoolTag: View {
    var text: String
    var color: Color
    var system: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let s = system { Image(systemName: s).font(.system(size: 11, weight: .bold)) }
            Text(text.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
    }
}

// A "sticky note" style card.
struct StickyNote<Content: View>: View {
    var color: Color = SchoolTheme.pencilYellow
    var rotation: Double = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 2, y: 4)
                }
            )
            .rotationEffect(.degrees(rotation))
    }
}

// A lined-paper card for content blocks.
struct PaperCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(SchoolTheme.cardBackground)
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(SchoolTheme.subtleBorder, lineWidth: 1)
                }
            )
            .shadow(color: SchoolTheme.chalkboardDeep.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}

// A "polaroid" frame for hero images.
struct Polaroid<Content: View>: View {
    var rotation: Double = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .padding(.bottom, 28)
            .background(Color.white)
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.18), radius: 10, x: 3, y: 6)
            .rotationEffect(.degrees(rotation))
    }
}

// Confetti burst when something is "funded".
struct ConfettiView: View {
    @State private var pieces: [ConfettiPiece] = []
    @State private var trigger = false
    var particleCount: Int = 80

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { p in
                    ConfettiShape(piece: p)
                        .position(x: p.x, y: trigger ? geo.size.height + 40 : p.startY)
                        .rotationEffect(.degrees(p.rotation))
                        .opacity(trigger ? 0 : 1)
                }
            }
            .onAppear {
                if pieces.isEmpty {
                    pieces = (0..<particleCount).map { _ in ConfettiPiece.random(in: geo.size.width) }
                }
                withAnimation(.easeOut(duration: 1.6)) { trigger = true }
            }
        }
        .allowsHitTesting(false)
    }
}

struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x: CGFloat
    let startY: CGFloat
    let color: Color
    let size: CGFloat
    let rotation: Double
    let symbol: String

    static func random(in width: CGFloat) -> ConfettiPiece {
        let palette: [Color] = [SchoolTheme.pencilYellow, SchoolTheme.apple, SchoolTheme.denim, SchoolTheme.crayonTeal, SchoolTheme.crayonPurple, SchoolTheme.crayonOrange, SchoolTheme.eraser]
        let symbols = ["star.fill", "heart.fill", "circle.fill", "triangle.fill", "sparkle", "graduationcap.fill"]
        return ConfettiPiece(
            x: CGFloat.random(in: 20...max(40, width - 20)),
            startY: CGFloat.random(in: -40...(-10)),
            color: palette.randomElement()!,
            size: CGFloat.random(in: 6...14),
            rotation: Double.random(in: 0...360),
            symbol: symbols.randomElement()!
        )
    }
}

struct ConfettiShape: View {
    let piece: ConfettiPiece
    var body: some View {
        Image(systemName: piece.symbol)
            .font(.system(size: piece.size, weight: .heavy))
            .foregroundStyle(piece.color)
    }
}

// Bouncing pencil used in the AI parsing animation.
struct BouncingPencil: View {
    @State private var bounce = false
    var color: Color = SchoolTheme.pencilYellow
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 14, height: 64)
            // Tip
            Triangle()
                .fill(SchoolTheme.ink)
                .frame(width: 14, height: 18)
                .offset(y: 41)
            // Eraser
            RoundedRectangle(cornerRadius: 4)
                .fill(SchoolTheme.eraser)
                .frame(width: 14, height: 18)
                .offset(y: -41)
        }
        .rotationEffect(.degrees(bounce ? -10 : 10))
        .offset(y: bounce ? -6 : 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                bounce.toggle()
            }
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// Animated three-dot loader ("AI is thinking").
struct ThinkingDots: View {
    @State private var phase: Int = 0
    var color: Color = .white
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .opacity(phase == i ? 1 : 0.25)
                    .scaleEffect(phase == i ? 1.15 : 0.8)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.3)) {
                    phase = (phase + 1) % 3
                }
            }
        }
    }
}

// Progress bar with a striped chalkboard pattern.
struct ChalkProgress: View {
    var progress: Double
    var height: CGFloat = 14
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(SchoolTheme.paper.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: height / 2)
                            .stroke(SchoolTheme.subtleBorder, lineWidth: 1)
                    )
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        LinearGradient(colors: [SchoolTheme.denimLight, SchoolTheme.denim],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
                    .overlay(
                        HStack(spacing: 6) {
                            ForEach(0..<8, id: \.self) { _ in
                                Rectangle()
                                    .fill(Color.white.opacity(0.25))
                                    .frame(width: 2, height: height * 0.6)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: height / 2))
                        .frame(width: max(0, min(1, progress)) * geo.size.width, alignment: .leading)
                    )
            }
        }
        .frame(height: height)
    }
}

// Animated empty-state bell.
struct NotificationBellAnimation: View {
    @State private var wiggle = false
    var color: Color = SchoolTheme.denim
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 140, height: 140)
                .scaleEffect(wiggle ? 1.1 : 0.95)
            Image(systemName: "bell.fill")
                .font(.system(size: 64, weight: .heavy))
                .foregroundStyle(color)
                .rotationEffect(.degrees(wiggle ? 14 : -14))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                wiggle.toggle()
            }
        }
    }
}

// Reusable inline "checkmark" step indicator.
struct StepDot: View {
    var index: Int
    var current: Int
    var total: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? SchoolTheme.denim : SchoolTheme.subtleBorder)
                    .frame(width: i == current ? 28 : 14, height: 8)
            }
        }
    }
}
