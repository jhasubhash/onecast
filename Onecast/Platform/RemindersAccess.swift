import Foundation

/// What the Mac will let Onecast write to the user's Apple Reminders.
enum RemindersAccess: Sendable {
    case notDetermined
    case granted
    /// Denied or restricted: only System Settings can undo it, so both read the same to us.
    case denied
}
