import SwiftUI

// School-themed palette: chalkboard greens, lined-paper cream, pencil yellow,
// cafeteria-apple red, and denim blue. Designed to feel warm and classroom-y.
enum SchoolTheme {
    static let chalkboard = Color(red: 0.16, green: 0.30, blue: 0.24)
    static let chalkboardDeep = Color(red: 0.10, green: 0.20, blue: 0.16)
    static let paper = Color(red: 0.985, green: 0.976, blue: 0.955)
    static let paperLine = Color(red: 0.64, green: 0.76, blue: 0.91)
    static let pencilYellow = Color(red: 1.00, green: 0.83, blue: 0.27)
    static let apple = Color(red: 0.86, green: 0.18, blue: 0.20)
    static let denim = Color(red: 0.21, green: 0.40, blue: 0.66)
    static let denimLight = Color(red: 0.36, green: 0.56, blue: 0.80)
    static let eraser = Color(red: 0.97, green: 0.69, blue: 0.76)
    static let crayonOrange = Color(red: 0.97, green: 0.55, blue: 0.16)
    static let crayonPurple = Color(red: 0.49, green: 0.36, blue: 0.78)
    static let crayonTeal = Color(red: 0.20, green: 0.66, blue: 0.66)
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.13)

    static let cardBackground = Color.white.opacity(0.96)
    static let subtleBorder = Color(red: 0.18, green: 0.25, blue: 0.31).opacity(0.10)
    static let mutedText = Color(red: 0.34, green: 0.37, blue: 0.40)

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

// A calm, classroom-inspired surface. The sparse ruling keeps the school
// personality without fighting with text, cards, or accessibility contrast.
struct LinedPaperBackground: View {
    var lineSpacing: CGFloat = 64

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [SchoolTheme.paper, Color(red: 0.94, green: 0.97, blue: 0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(SchoolTheme.pencilYellow.opacity(0.11))
                .frame(width: 290, height: 290)
                .blur(radius: 2)
                .offset(x: 150, y: -310)

            Circle()
                .fill(SchoolTheme.denimLight.opacity(0.10))
                .frame(width: 340, height: 340)
                .blur(radius: 6)
                .offset(x: -180, y: 330)

            Canvas { ctx, size in
                var y: CGFloat = 104
                while y < size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: 24, y: y))
                    path.addLine(to: CGPoint(x: size.width - 24, y: y))
                    ctx.stroke(
                        path,
                        with: .color(SchoolTheme.paperLine.opacity(0.14)),
                        lineWidth: 0.8
                    )
                    y += lineSpacing
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// Chalkboard background (used on hero areas).
struct ChalkboardBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.16, blue: 0.15),
                    SchoolTheme.chalkboard,
                    Color(red: 0.10, green: 0.25, blue: 0.27)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(SchoolTheme.denimLight.opacity(0.16))
                .frame(width: 360, height: 360)
                .blur(radius: 28)
                .offset(x: 170, y: -330)

            Circle()
                .fill(SchoolTheme.pencilYellow.opacity(0.10))
                .frame(width: 320, height: 320)
                .blur(radius: 34)
                .offset(x: -180, y: 360)

            // Deterministic chalk texture avoids visible jumps on state updates.
            Canvas { ctx, size in
                for index in 0..<96 {
                    let x = CGFloat((index * 79) % 997) / 997 * size.width
                    let y = CGFloat((index * 131 + 37) % 991) / 991 * size.height
                    let r = CGFloat(1 + (index % 3)) * 0.55
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                             with: .color(.white.opacity(0.06 + Double(index % 4) * 0.015)))
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
