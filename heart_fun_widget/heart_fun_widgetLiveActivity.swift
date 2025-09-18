//
//  heart_fun_widgetLiveActivity.swift
//  heart_fun_widget
//
//  Created by Egor on 19.09.2025.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct heart_fun_widgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct heart_fun_widgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: heart_fun_widgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension heart_fun_widgetAttributes {
    fileprivate static var preview: heart_fun_widgetAttributes {
        heart_fun_widgetAttributes(name: "World")
    }
}

extension heart_fun_widgetAttributes.ContentState {
    fileprivate static var smiley: heart_fun_widgetAttributes.ContentState {
        heart_fun_widgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: heart_fun_widgetAttributes.ContentState {
         heart_fun_widgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: heart_fun_widgetAttributes.preview) {
   heart_fun_widgetLiveActivity()
} contentStates: {
    heart_fun_widgetAttributes.ContentState.smiley
    heart_fun_widgetAttributes.ContentState.starEyes
}
