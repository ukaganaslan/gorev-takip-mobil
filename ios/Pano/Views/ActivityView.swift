import SwiftUI

// Etkinlik akışı: "kim, hangi görevi, ne yaptı" — buzdolabı panosunun kenar notları.
struct ActivityView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var items: [ActivityItem] = []
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            List {
                if hasLoaded && items.isEmpty {
                    ContentUnavailableView {
                        Label("Henüz etkinlik yok", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Görev eklendikçe ve tamamlandıkça burada görünür.")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(items) { item in
                        ActivityRow(item: item)
                    }
                }
            }
            .navigationTitle("Etkinlik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .task {
                await reload()
                hasLoaded = true
            }
            .onChange(of: session.syncVersion) {
                Task { await reload() }
            }
            .refreshable { await reload() }
        }
    }

    private func reload() async {
        do {
            items = try await session.api.activity()
        } catch {
            // liste eski kalır; aşağı çekerek yenilenebilir
        }
    }
}

private struct ActivityRow: View {
    let item: ActivityItem

    private var verb: String {
        switch item.action {
        case "created": "ekledi"
        case "completed": "tamamladı"
        case "uncompleted": "geri aldı"
        case "deleted": "sildi"
        default: item.action
        }
    }

    private var icon: (name: String, color: Color) {
        switch item.action {
        case "created": ("plus.circle.fill", .blue)
        case "completed": ("checkmark.circle.fill", .green)
        case "uncompleted": ("arrow.uturn.backward.circle.fill", .orange)
        case "deleted": ("trash.circle.fill", .red)
        default: ("circle.fill", .secondary)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon.name)
                .font(.title3)
                .foregroundStyle(icon.color)

            VStack(alignment: .leading, spacing: 3) {
                Text("**\(item.actorName)**, \"\(item.taskTitle)\" görevini \(verb).")
                    .font(.subheadline)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Palette.color(item.categoryColor))
                        .frame(width: 7, height: 7)
                    Text(item.groupName.map { "\(item.categoryName) · \($0)" } ?? item.categoryName)
                    Text("·")
                    Text(item.createdAt.formatted(.relative(presentation: .named)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
