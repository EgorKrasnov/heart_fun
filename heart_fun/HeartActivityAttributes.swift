import ActivityKit

struct HeartActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var heartRate: Int
    }
    var deviceName: String
}
