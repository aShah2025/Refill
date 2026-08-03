import SwiftUI

// School-themed palette: chalkboard greens, lined-paper cream, pencil yellow,
// cafeteria-apple red, and denim blue. Designed to feel warm and classroom-y.
enum SchoolTheme {
    static let chalkboard = Color(red: 0.16, green: 0.30, blue: 0.24)
    static let chalkboardDeep = Color(red: 0.10, green: 0.20, blue: 0.16)
    static let paper = Color(red: 0.99, green: 0.97, blue: 0.93)
    static let paperLine = Color(red: 0.78, green: 0.85, blue: 0.95)
    static let pencilYellow = Color(red: 1.00, green: 0.83, blue: 0.27)
    static let apple = Color(red: 0.86, green: 0.18, blue: 0.20)
    static let denim = Color(red: 0.21, green: 0.40, blue: 0.66)
    static let denimLight = Color(red: 0.36, green: 0.56, blue: 0.80)
    static let eraser = Color(red: 0.97, green: 0.69, blue: 0.76)
    static let crayonOrange = Color(red: 0.97, green: 0.55, blue: 0.16)
    static let crayonPurple = Color(red: 0.49, green: 0.36, blue: 0.78)
    static let crayonTeal = Color(red: 0.20, green: 0.66, blue: 0.66)
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.13)

    static let cardBackground = Color.white
    static let subtleBorder = Color.black.opacity(0.08)
    static let mutedText = Color(white: 0.45)

    // Fonts
    static func displayFont(size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }
    static func headlineFont(size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }
    static func bodyFont(size: CGFloat = 16) -> Font {
        .system(size: size, weight: .regular, design: .rounded)
    }
    static func monoFont(size: CGFloat = 14) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

// Rounded button with "sticker" shadow + bounce press feedback.
struct SchoolButtonStyle: ButtonStyle {
    var color: Color = SchoolTheme.denim
    var textColor: Color = .white
    var cornerRadius: CGFloat = 18
    var fillHeight: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SchoolTheme.headlineFont(size: 17))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, minHeight: fillHeight)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(color.opacity(0.35))
                        .offset(y: 5)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(color)
                }
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

// Subtle lined-paper background.
struct LinedPaperBackground: View {
    var lineSpacing: CGFloat = 28
    var body: some View {
        ZStack {
            SchoolTheme.paper
            Canvas { ctx, size in
                let lineColor = SchoolTheme.paperLine
                var y: CGFloat = lineSpacing
                while y < size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: 16, y: y))
                    path.addLine(to: CGPoint(x: size.width - 16, y: y))
                    ctx.stroke(path, with: .color(lineColor), lineWidth: 1)
                    y += lineSpacing
                }
                // Left margin line
                var margin = Path()
                margin.move(to: CGPoint(x: 44, y: 0))
                margin.addLine(to: CGPoint(x: 44, y: size.height))
                ctx.stroke(margin, with: .color(SchoolTheme.apple.opacity(0.35)), lineWidth: 1.4)
            }
        }
        .ignoresSafeArea()
    }
}

// Chalkboard background (used on hero areas).
struct ChalkboardBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [SchoolTheme.chalkboardDeep, SchoolTheme.chalkboard],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Subtle chalk dust speckles
            Canvas { ctx, size in
                for _ in 0..<160 {
                    let x = CGFloat.random(in: 0...size.width)
                    let y = CGFloat.random(in: 0...size.height)
                    let r = CGFloat.random(in: 0.5...2.2)
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                             with: .color(.white.opacity(Double.random(in: 0.04...0.18))))
                }
            }
        }
        .ignoresSafeArea()
    }
}
