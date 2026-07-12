import Foundation
import WidgetKit

// Widget veri köprüsü: yaklaşan görevler her senkronda App Group konteynerine
// yazılır; widget bu dosyayı okur. Grup kimliği widget tarafıyla aynı olmalı
// (PanoWidget/PanoWidget.swift içindeki SharedStore).
enum WidgetBridge {
    private static let groupId = "group.com.pano.app"
    private static let fileName = "widget-tasks.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupId)?
            .appendingPathComponent(fileName)
    }

    static func publish(_ tasks: [ReminderTask]) {
        guard let url = fileURL else { return }
        if let data = try? APIClient.encoder.encode(tasks) {
            try? data.write(to: url, options: .atomic)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
