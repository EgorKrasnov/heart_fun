import ActivityKit
import WidgetKit
import SwiftUI

struct HeartActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HeartActivityAttributes.self) { context in
            VStack {
                Text("❤️ \(context.state.heartRate) bpm")
                    .font(.title)
                Text(context.attributes.deviceName)
                    .font(.footnote)
                    .foregroundColor(.gray)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text("❤️ \(context.state.heartRate) bpm")
                        .font(.title)
                }
            } compactLeading: {
                Text("❤️")
            } compactTrailing: {
                Text("\(context.state.heartRate)")
            } minimal: {
                Text("\(context.state.heartRate)")
            }
        }
    }
}
