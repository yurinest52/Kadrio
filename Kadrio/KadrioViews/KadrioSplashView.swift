import SwiftUI

struct KadrioSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()
    @State private var settled = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || settled)) { context in
            let elapsed = reduceMotion || settled ? 2.4 : max(0, context.date.timeIntervalSince(startedAt))
            let assembly = progress(elapsed, from: 0.12, duration: 0.92)
            let lettering = progress(elapsed, from: 0.76, duration: 0.64)
            let subtitle = progress(elapsed, from: 1.12, duration: 0.56)
            VStack(spacing: 0) {
                ZStack {
                    focusCorners(elapsed: elapsed)
                    ForEach(0..<3) { index in
                        photoCard(index: index, assembly: assembly, elapsed: elapsed)
                    }
                    logo(elapsed: elapsed)
                }
                .frame(width: 200, height: 162)
                .accessibilityHidden(true)
                Text(kadrioText("appTitle"))
                    .font(.system(size: 25, weight: .bold))
                    .tracking(-0.55 + (1 - lettering) * 3)
                    .opacity(lettering)
                    .blur(radius: (1 - lettering) * 5)
                    .offset(y: (1 - lettering) * 11)
                    .padding(.top, 8)
                Text(kadrioText("splash.subtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.kadrioSecondary)
                    .opacity(subtitle)
                    .offset(y: (1 - subtitle) * 7)
                    .padding(.top, 9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.kadrioBackground.ignoresSafeArea())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kadrioText("appTitle") + ". " + kadrioText("splash.subtitle"))
        .accessibilityIdentifier("KadrioAnimatedSplash")
        .task {
            startedAt = Date()
            do {
                try await Task.sleep(for: .milliseconds(2300))
                settled = true
            } catch {}
        }
    }

    private func logo(elapsed: Double) -> some View {
        let entrance = progress(elapsed, from: 0.18, duration: 0.75)
        let spring = 1 - exp(-7 * max(0, elapsed - 0.18)) * cos(10 * max(0, elapsed - 0.18))
        let light = progress(elapsed, from: 0.88, duration: 0.83)
        return Image("KadrioSplashLogo")
            .resizable()
            .frame(width: 96, height: 96)
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white.opacity(0.04), location: 0.3), .init(color: .white.opacity(0.28), location: 0.5), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 58, height: 170)
                    .rotationEffect(.degrees(24))
                    .offset(x: -125 + light * 250)
                    .opacity(elapsed > 0.88 && elapsed < 1.71 ? 1 : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.13 * entrance), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.13 * entrance), radius: 11, x: 0, y: 7)
            .scaleEffect(0.74 + 0.26 * spring)
            .rotationEffect(.degrees(-12 * (1 - entrance)))
            .opacity(entrance)
    }

    private func photoCard(index: Int, assembly: Double, elapsed: Double) -> some View {
        let direction = index.isMultiple(of: 2) ? -1.0 : 1.0
        let distance = Double(3 - index)
        let reveal = progress(elapsed, from: Double(index) * 0.06, duration: 0.34)
        let tuck = progress(elapsed, from: 1.38, duration: 0.62)
        return RoundedRectangle(cornerRadius: 25, style: .continuous)
            .fill(Color(white: 0.98 - Double(index) * 0.025))
            .overlay {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .strokeBorder(.black.opacity(0.055), lineWidth: 0.75)
            }
            .frame(width: 96, height: 96)
            .shadow(color: .black.opacity(0.035), radius: 5, y: 3)
            .rotationEffect(.degrees(direction * ((1 - assembly) * (17 + distance * 6) + (1 - tuck) * distance * 2)))
            .offset(x: direction * ((1 - assembly) * 27 + (1 - tuck) * distance * 2.8), y: (1 - assembly) * (distance * 8 - 10) + (1 - tuck) * distance * 3)
            .scaleEffect(0.82 + assembly * 0.18)
            .opacity(reveal * (1 - tuck * 0.9))
    }

    private func focusCorners(elapsed: Double) -> some View {
        let arrival = progress(elapsed, from: 0.05, duration: 0.76)
        let release = progress(elapsed, from: 1.16, duration: 0.72)
        let inset = 19 + arrival * 16 - release * 7
        return Canvas { context, size in
            let rect = CGRect(x: inset, y: inset - 19, width: size.width - inset * 2, height: size.height - (inset - 19) * 2)
            let length = 15.0
            var path = Path()
            for (x, y, dx, dy) in [(rect.minX, rect.minY, 1.0, 1.0), (rect.maxX, rect.minY, -1.0, 1.0), (rect.minX, rect.maxY, 1.0, -1.0), (rect.maxX, rect.maxY, -1.0, -1.0)] {
                path.move(to: CGPoint(x: x, y: y + dy * length))
                path.addLine(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + dx * length, y: y))
            }
            context.stroke(path, with: .color(.black.opacity(0.17 * arrival * (1 - release))), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 200, height: 162)
        .blur(radius: (1 - arrival) * 2)
    }

    private func progress(_ elapsed: Double, from start: Double, duration: Double) -> Double {
        let value = min(1, max(0, (elapsed - start) / duration))
        return value * value * (3 - 2 * value)
    }
}
