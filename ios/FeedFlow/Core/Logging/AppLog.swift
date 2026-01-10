import Foundation
import os

enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "FeedFlow"
    static let network = Logger(subsystem: subsystem, category: "network")
    static let player = Logger(subsystem: subsystem, category: "player")
}

