import SwiftUI

// MARK: - Progress Ring

struct ProgressRing: View {
    var progress: Double
    var size: CGFloat = 18
    var lineWidth: CGFloat = 2.5
    var color: Color = .orange

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

func progressColor(_ s: AgentSession) -> Color {
    if s.progress >= 0.99 { return claudeGreen }
    return s.agentType.accentColor
}
