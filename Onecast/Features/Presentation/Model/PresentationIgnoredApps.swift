import Foundation

/// Meeting apps Presentation Mode leaves alone by default: hiding one would take the call with it.
enum PresentationIgnoredApps {
    static let defaults = [
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "us.zoom.xos",
        "Cisco-Systems.Spark",
        "com.webex.meetingmanager",
        "com.apple.FaceTime",
    ]
}
