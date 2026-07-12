import Foundation
import UserNotifications

// Son tarih hatırlatıcıları: her senkronda açık görevlerin son tarihlerine göre
// yerel bildirimler baştan planlanır (görev değişince eskisi otomatik düşer).
enum Reminders {
    private static let idPrefix = "pano-task-"

    // Bildirim, son tarih gününün sabahı gösterilir.
    private static let fireHour = 9

    static func schedule(tasks: [ReminderTask], userId: Int?) async {
        let center = UNUserNotificationCenter.current()

        // İzin ilk planlama ihtiyacında istenir; reddedildiyse sessizce vazgeç.
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional else { return }

        let pending = await center.pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let calendar = Calendar.current
        for task in tasks {
            // Başkasına atanmış görev başkasının derdi; bana atanan veya sahipsiz olan hatırlatılır.
            if let assignee = task.assignedTo, assignee != userId { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: task.dueDate)
            comps.hour = fireHour
            guard let fireDate = calendar.date(from: comps), fireDate > .now else { continue }

            let content = UNMutableNotificationContent()
            content.title = task.categoryName
            content.body = "Bugün son gün: \(task.title)"
            content.sound = .default
            try? await center.add(UNNotificationRequest(
                identifier: idPrefix + String(task.id),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            ))
        }
    }

    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests()
                .map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)
        }
    }
}
