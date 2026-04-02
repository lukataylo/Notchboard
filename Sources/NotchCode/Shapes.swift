import SwiftUI

// MARK: - Claude Code Icon (from official SVG path data)

struct ClaudeCodeIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.minX + (rect.width - 24 * s) / 2
        let oy = rect.minY + (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }
        var path = Path()
        path.move(to: p(20.998, 10.949))
        path.addLine(to: p(24, 10.949)); path.addLine(to: p(24, 14.051))
        path.addLine(to: p(21, 14.051)); path.addLine(to: p(21, 17.079))
        path.addLine(to: p(19.513, 17.079)); path.addLine(to: p(19.513, 20))
        path.addLine(to: p(18, 20)); path.addLine(to: p(18, 17.079))
        path.addLine(to: p(16.513, 17.079)); path.addLine(to: p(16.513, 20))
        path.addLine(to: p(15, 20)); path.addLine(to: p(15, 17.079))
        path.addLine(to: p(9, 17.079)); path.addLine(to: p(9, 20))
        path.addLine(to: p(7.488, 20)); path.addLine(to: p(7.488, 17.079))
        path.addLine(to: p(6, 17.079)); path.addLine(to: p(6, 20))
        path.addLine(to: p(4.487, 20)); path.addLine(to: p(4.487, 17.079))
        path.addLine(to: p(3, 17.079)); path.addLine(to: p(3, 14.05))
        path.addLine(to: p(0, 14.05)); path.addLine(to: p(0, 10.95))
        path.addLine(to: p(3, 10.95)); path.addLine(to: p(3, 5))
        path.addLine(to: p(20.998, 5))
        path.closeSubpath()
        path.move(to: p(6, 10.949))
        path.addLine(to: p(7.488, 10.949)); path.addLine(to: p(7.488, 8.102))
        path.addLine(to: p(6, 8.102)); path.closeSubpath()
        path.move(to: p(16.51, 10.949))
        path.addLine(to: p(18, 10.949)); path.addLine(to: p(18, 8.102))
        path.addLine(to: p(16.51, 8.102)); path.closeSubpath()
        return path
    }
}

// MARK: - Cursor Icon

struct CursorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.minX + (rect.width - 24 * s) / 2
        let oy = rect.minY + (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }
        var path = Path()
        path.move(to: p(4, 2))
        path.addLine(to: p(4, 20)); path.addLine(to: p(9, 15.5))
        path.addLine(to: p(13.5, 22)); path.addLine(to: p(16.5, 20.5))
        path.addLine(to: p(12, 14)); path.addLine(to: p(18, 13))
        path.closeSubpath()
        return path
    }
}

// MARK: - NotchCode Icon (</>)

struct NotchCodeIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.minX + (rect.width - 24 * s) / 2
        let oy = rect.minY + (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }
        var path = Path()
        path.move(to: p(9, 5)); path.addLine(to: p(3, 12)); path.addLine(to: p(9, 19))
        path.addLine(to: p(10.5, 17.5)); path.addLine(to: p(6, 12)); path.addLine(to: p(10.5, 6.5))
        path.closeSubpath()
        path.move(to: p(15, 5)); path.addLine(to: p(21, 12)); path.addLine(to: p(15, 19))
        path.addLine(to: p(13.5, 17.5)); path.addLine(to: p(18, 12)); path.addLine(to: p(13.5, 6.5))
        path.closeSubpath()
        path.move(to: p(13.2, 4)); path.addLine(to: p(14.2, 4))
        path.addLine(to: p(10.8, 20)); path.addLine(to: p(9.8, 20))
        path.closeSubpath()
        return path
    }
}

// MARK: - Agent Icon Helper

@ViewBuilder
func agentIcon(for type: AgentType, size: CGFloat, filled: Bool = true) -> some View {
    switch type {
    case .claudeCode:
        ClaudeCodeIcon()
            .fill(filled ? claudeOrange : Color.white.opacity(0.5), style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
    case .cursor:
        CursorIcon()
            .fill(filled ? cursorPurple : Color.white.opacity(0.5))
            .frame(width: size, height: size)
    }
}

// MARK: - Notch Shape

struct NotchCollapsedShape: Shape {
    var bottomRadius: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let br = min(bottomRadius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                  radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + br, y: rect.maxY - br),
                  radius: br, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}
