import OSLog

enum Log {
    private static let subsystem = "com.honeyyadav.dicta"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let speech = Logger(subsystem: subsystem, category: "speech")
    static let insert = Logger(subsystem: subsystem, category: "insert")
    static let updates = Logger(subsystem: subsystem, category: "updates")
}
