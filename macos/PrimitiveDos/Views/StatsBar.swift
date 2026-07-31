import SwiftUI

struct StatsBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 18) {
            if state.totalShapes > 0 {
                ProgressView(value: Double(state.shapesDone), total: Double(max(1, state.totalShapes)))
                    .frame(maxWidth: 220)
                Text("\(state.shapesDone.formatted()) / \(state.totalShapes.formatted())")
                    .fontWeight(.semibold)
            } else {
                if state.phase == .running {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("\(state.shapesDone.formatted()) shapes")
                    .fontWeight(.semibold)
            }

            if state.score > 0 {
                Text("\(state.similarity, format: .number.precision(.fractionLength(2)))% similar")
                    .help("RMSE score \(state.score, format: .number.precision(.fractionLength(5)))")
            }

            if state.shapesPerSec > 0 {
                Text("\(state.shapesPerSec, format: .number.precision(.fractionLength(state.shapesPerSec >= 10 ? 0 : 1))) shapes/s")
            }

            Text(elapsedText)

            Spacer()

            if let info = state.inputInfo {
                Text("\(info.width) × \(info.height)")
                    .help("Source image size")
            }
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    private var elapsedText: String {
        let total = state.elapsedMs / 1000
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
