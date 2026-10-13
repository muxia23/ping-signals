import Foundation
import PingCore
import UserNotifications

/// macOS notifications for todo DDLs: at the due time, or 9:00 on a date-only due day.
/// Every change to the list re-syncs the whole set, so done, deleted or re-dated todos never fire.
/// Permission is asked the first time there is something to remind about.
@MainActor
final class TodoReminders: NSObject, UNUserNotificationCenterDelegate {
  private let center = UNUserNotificationCenter.current()
  /// Clicking a reminder: show the todo panel.
  var onOpen: (() -> Void)?
  /// Bumped per sync, so a sync still waiting for permission can't re-add reminders a later one removed.
  private var generation = 0

  override init() {
    super.init()
    center.delegate = self
  }

  func sync(_ items: [TodoItem]) {
    generation += 1
    let g = generation
    let now = Date()
    let wanted = items.compactMap { item in TodoDue.pendingReminder(for: item, now: now).map { (item, $0) } }
    center.removeAllPendingNotificationRequests()   // only ours: the app schedules nothing else
    guard !wanted.isEmpty else { return }
    let requests = wanted.map { item, date -> UNNotificationRequest in
      let content = UNMutableNotificationContent()
      content.title = String(localized: "Todo due")
      content.body = item.text
      content.sound = .default
      let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
      return UNNotificationRequest(identifier: item.id.uuidString, content: content,
                                   trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }
    Task {
      guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
      for r in requests {
        guard g == generation else { return }
        try? await center.add(r)
      }
    }
  }

  nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                          didReceive response: UNNotificationResponse) async {
    await MainActor.run { onOpen?() }
  }

  nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                          willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }
}
