import SwiftUI

struct KadrioToolIcon: View {
    let tool: KadrioTool
    var body: some View {
        KadrioToolIconShape(tool: tool)
            .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .accessibilityHidden(true)
    }
}

private struct KadrioToolIconShape: Shape {
    let tool: KadrioTool
    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch tool {
        case .collage:
            for x in [3.0, 13.5] {
                for y in [3.0, 13.5] {
                    path.addRoundedRect(in: CGRect(x: x, y: y, width: 7.5, height: 7.5), cornerSize: CGSize(width: 1.6, height: 1.6))
                }
            }
        case .crop:
            path.move(to: CGPoint(x: 6, y: 1.5))
            path.addLine(to: CGPoint(x: 6, y: 18))
            path.addLine(to: CGPoint(x: 22.5, y: 18))
            path.move(to: CGPoint(x: 1.5, y: 6))
            path.addLine(to: CGPoint(x: 18, y: 6))
            path.addLine(to: CGPoint(x: 18, y: 22.5))
        case .filters:
            for center in [CGPoint(x: 9, y: 8.9), CGPoint(x: 15, y: 8.9), CGPoint(x: 12, y: 14.1)] {
                path.addEllipse(in: CGRect(x: center.x - 5.8, y: center.y - 5.8, width: 11.6, height: 11.6))
            }
        case .frames:
            path.addRoundedRect(in: CGRect(x: 3, y: 2.5, width: 18, height: 19), cornerSize: CGSize(width: 2.8, height: 2.8))
            path.addRoundedRect(in: CGRect(x: 7.2, y: 6.8, width: 9.6, height: 10.4), cornerSize: CGSize(width: 1.1, height: 1.1))
        }
        let side = min(rect.width, rect.height)
        let transform = CGAffineTransform(scaleX: side / 24, y: side / 24).concatenating(CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2))
        return path.applying(transform)
    }
}

struct KadrioCropActionIcon: View {
    let action: String
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            context.scaleBy(x: scale, y: scale)
            var path = Path()
            if action == "flip" {
                path.move(to: CGPoint(x: 12, y: 2))
                path.addLine(to: CGPoint(x: 12, y: 22))
                path.move(to: CGPoint(x: 16, y: 5))
                path.addLine(to: CGPoint(x: 22, y: 18))
                path.addLine(to: CGPoint(x: 16, y: 18))
                path.closeSubpath()
                var filled = Path()
                filled.move(to: CGPoint(x: 8, y: 5))
                filled.addLine(to: CGPoint(x: 2, y: 18))
                filled.addLine(to: CGPoint(x: 8, y: 18))
                filled.closeSubpath()
                context.fill(filled, with: .foreground)
            } else {
                path.move(to: CGPoint(x: 20, y: 8))
                path.addCurve(to: CGPoint(x: 5, y: 6), control1: CGPoint(x: 17, y: 2), control2: CGPoint(x: 9, y: 2))
                path.addCurve(to: CGPoint(x: 11, y: 21), control1: CGPoint(x: 0, y: 12), control2: CGPoint(x: 4, y: 21))
                path.addCurve(to: CGPoint(x: 21, y: 14), control1: CGPoint(x: 16, y: 21), control2: CGPoint(x: 20, y: 18))
                path.move(to: CGPoint(x: 20, y: 2))
                path.addLine(to: CGPoint(x: 20, y: 8))
                path.addLine(to: CGPoint(x: 14, y: 8))
                if action == "reset" {
                    path = path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 24, ty: 0))
                }
            }
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }.accessibilityHidden(true)
    }
}
