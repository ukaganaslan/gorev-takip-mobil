import WidgetKit
import SwiftUI

// Ana ekran widget'ı: son tarihi yaklaşan görevler. Veri, uygulamanın her
// senkronda App Group konteynerine yazdığı JSON'dan okunur (Shared.swift'e bakın).

struct WidgetTask: Codable, Identifiable {
    let id: Int
    let title: String
    let dueDate: Date
    let assignedTo: Int?
    let categoryId: Int
    let categoryName: String

    var isOverdue: Bool { dueDate < Calendar.current.startOfDay(for: .now) }
    var isToday: Bool { Calendar.current.isDateInToday(dueDate) }
}

struct TaskEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTask]
}

struct Provider: TimelineProvider {
    static let sample = [
        WidgetTask(id: 1, title: "Süt al", dueDate: .now, assignedTo: nil, categoryId: 1, categoryName: "Market"),
        WidgetTask(id: 2, title: "Çöpü çıkar", dueDate: .now, assignedTo: nil, categoryId: 2, categoryName: "Ev İşleri"),
        WidgetTask(id: 3, title: "Ödevi teslim et", dueDate: .now.addingTimeInterval(86400), assignedTo: nil, categoryId: 3, categoryName: "Okul"),
    ]

    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(date: .now, tasks: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        completion(TaskEntry(date: .now, tasks: context.isPreview ? Self.sample : load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        let entry = TaskEntry(date: .now, tasks: load())
        // Uygulama her senkronda zaten yeniler; bu sadece emniyet payı.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }

    private func load() -> [WidgetTask] {
        guard let dir = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.groupId),
              let data = try? Data(contentsOf: dir.appendingPathComponent(SharedStore.fileName))
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([WidgetTask].self, from: data)) ?? []
    }
}

enum SharedStore {
    static let groupId = "group.com.pano.app"
    static let fileName = "widget-tasks.json"
}

struct PanoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TaskEntry

    private var visible: [WidgetTask] {
        Array(entry.tasks.prefix(family == .systemSmall ? 2 : 4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checklist")
                    .font(.caption.weight(.bold))
                Text("Yaklaşan")
                    .font(.caption.weight(.semibold))
                Spacer()
                if !entry.tasks.isEmpty {
                    Text("\(entry.tasks.count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.tint)

            if entry.tasks.isEmpty {
                Spacer()
                Text("Son tarihli açık görev yok 🎉")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(visible) { task in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(task.isOverdue ? Color.red : (task.isToday ? Color.orange : Color.secondary.opacity(0.5)))
                            .frame(width: 6, height: 6)
                        Text(task.title)
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if family != .systemSmall {
                            Text(task.dueDate.formatted(.dateTime.day().month(.abbreviated)))
                                .font(.caption2)
                                .foregroundStyle(task.isOverdue ? .red : .secondary)
                        }
                    }
                }
                if entry.tasks.count > visible.count {
                    Text("+\(entry.tasks.count - visible.count) görev daha")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct PanoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PanoWidget", provider: Provider()) { entry in
            PanoWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Yaklaşan Görevler")
        .description("Son tarihi yaklaşan açık görevlerini gösterir.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PanoWidgetBundle: WidgetBundle {
    var body: some Widget {
        PanoWidget()
    }
}
