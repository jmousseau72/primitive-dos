import SwiftUI
import UniformTypeIdentifiers

/// Scrub through the finished render's shape history. Position is view-only:
/// Continue always resumes from the real model, not the scrub point.
struct TimelineBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { Double(state.timelinePosition) },
                    set: { state.scrubTimeline(to: Int($0.rounded())) }
                ),
                in: 0...Double(max(1, state.timelineCount))
            )
            .controlSize(.small)

            Text("\(state.timelinePosition.formatted()) / \(state.timelineCount.formatted())")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 110, alignment: .trailing)

            Menu("Export Frame…") {
                Button("PNG…") { state.exportTimelineFrame(.png) }
                Button("JPEG…") { state.exportTimelineFrame(.jpg) }
                Button("SVG…") { state.exportTimelineFrame(.svg) }
                Divider()
                Button("Composite over Source…") { state.exportTimelineFrame(.composite) }
            }
            .fixedSize()
            .disabled(state.timelinePosition == 0)
            .help("Save this moment at full resolution — the composite bakes the sketch over the source photo")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 8))
        .padding(.horizontal)
    }
}
