import SwiftUI

// Bir kategorinin görev listesi. Kategori sayaçları Session'dan canlı okunur,
// görevler bu ekrana özel çekilir ve her senkron sinyalinde tazelenir.
struct CategoryDetailView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let categoryId: Int

    @State private var tasks: [TaskItem] = []
    @State private var hasLoaded = false
    @State private var showNewTask = false
    @State private var editingTask: TaskItem?
    @State private var errorMessage: String?

    private var category: Category? {
        session.categories.first { $0.id == categoryId }
    }

    private var color: Color { Palette.color(category?.color ?? "coral") }

    var body: some View {
        List {
            if let category, category.taskCount > 0 {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(category.doneCount)/\(category.taskCount) tamamlandı")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        ProgressView(value: Double(category.doneCount),
                                     total: Double(max(category.taskCount, 1)))
                            .tint(color)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 10, trailing: 8))
                }
            }

            if hasLoaded && tasks.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Henüz görev yok", systemImage: "checklist")
                    } description: {
                        Text("Sağ üstteki + ile ilk görevi ekle.")
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(tasks) { task in
                        TaskRow(task: task, color: color) {
                            toggle(task)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // Silme ve düzenleme yalnızca görevi oluşturana görünür.
                            if task.createdBy == session.user?.id {
                                Button(role: .destructive) {
                                    delete(task)
                                } label: {
                                    Label("Sil", systemImage: "trash")
                                }
                                Button {
                                    editingTask = task
                                } label: {
                                    Label("Düzenle", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
        }
        .animation(.snappy, value: tasks)
        .navigationTitle(category?.name ?? "")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewTask = true
                } label: {
                    Label("Görev Ekle", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewTask) {
            TaskFormView(categoryId: categoryId, existing: nil) { await reload() }
        }
        .sheet(item: $editingTask) { task in
            TaskFormView(categoryId: categoryId, existing: task) { await reload() }
        }
        .task {
            await reload()
            hasLoaded = true
        }
        .onChange(of: session.syncVersion) {
            Task { await reload() }
        }
        .onChange(of: session.categories) {
            // Kategori başka bir cihazdan/üyeden silindiyse ekranda kalma.
            if hasLoaded && category == nil { dismiss() }
        }
        .refreshable {
            await session.refresh()
            await reload()
        }
        .alert("Bu işlem yapılamadı", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reload() async {
        do {
            tasks = try await session.api.tasks(categoryId: categoryId)
            DiskCache.save(tasks, as: "tasks-\(categoryId)")
        } catch {
            // Çevrimdışı: elimizde hiç veri yoksa son bilinen listeyi göster.
            if tasks.isEmpty, let cached = DiskCache.load([TaskItem].self, from: "tasks-\(categoryId)") {
                tasks = cached
            }
        }
    }

    private func toggle(_ task: TaskItem) {
        Task {
            do {
                let updated = task.isDone
                    ? try await session.api.uncomplete(taskId: task.id)
                    : try await session.api.complete(taskId: task.id)
                if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[i] = updated
                }
                await session.refresh()
            } catch {
                // Örn. başkasının tamamladığı görevi geri almaya çalışmak — sunucu nedenini söyler.
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ task: TaskItem) {
        Task {
            do {
                try await session.api.deleteTask(id: task.id)
                tasks.removeAll { $0.id == task.id }
                await session.refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct TaskRow: View {
    @Environment(Session.self) private var session
    let task: TaskItem
    let color: Color
    let onToggle: () -> Void

    private var lockedByOther: Bool {
        task.isDone && task.completedBy != session.user?.id
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isDone ? color : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body.weight(.medium))
                    .strikethrough(task.isDone, color: .secondary)
                    .foregroundStyle(task.isDone ? .secondary : .primary)

                if let detail = task.description, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let due = task.dueDate {
                        Label(due.formatted(date: .abbreviated, time: .omitted),
                              systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(task.isOverdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    }
                    if task.recurrence != nil {
                        Image(systemName: "repeat")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if !task.isDone, let assignee = task.assignedToName {
                        Label(assignee, systemImage: "person.fill")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                            .foregroundStyle(.secondary)
                    }
                    if task.isDone, let name = task.completedByName {
                        HStack(spacing: 4) {
                            Image(systemName: lockedByOther ? "lock.fill" : "checkmark")
                                .font(.system(size: 9, weight: .bold))
                            Text(completedLabel(name))
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(color.opacity(0.15)))
                        .foregroundStyle(color)
                    } else {
                        Text(task.createdByName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }

    private func completedLabel(_ name: String) -> String {
        guard let at = task.completedAt else { return name }
        return "\(name) · \(at.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct TaskFormView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let categoryId: Int
    let existing: TaskItem?
    let onSaved: () async -> Void

    @State private var title = ""
    @State private var detail = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var recurrence: Recurrence?
    @State private var assignedTo: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?

    // Grup kategorisiyse üyeler atanabilir; kişisel kategoride atama gösterilmez.
    private var members: [Member] {
        guard let groupId = session.categories.first(where: { $0.id == categoryId })?.groupId,
              let group = session.groups.first(where: { $0.id == groupId }) else { return [] }
        return group.members
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ne yapılacak?", text: $title)
                    TextField("Açıklama (isteğe bağlı)", text: $detail, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Toggle("Son tarih", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Tarih", selection: $dueDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                        Picker("Tekrar", selection: $recurrence) {
                            Text("Yok").tag(Recurrence?.none)
                            ForEach(Recurrence.allCases) { r in
                                Text(r.label).tag(Recurrence?.some(r))
                            }
                        }
                    }
                } footer: {
                    if hasDueDate && recurrence != nil {
                        Text("Görev tamamlanınca bir sonraki tarih için yenisi otomatik oluşur.")
                    }
                }
                if !members.isEmpty {
                    Section {
                        Picker("Atanan kişi", selection: $assignedTo) {
                            Text("Kimse").tag(Int?.none)
                            ForEach(members) { member in
                                Text(member.displayName).tag(Int?.some(member.id))
                            }
                        }
                    } footer: {
                        Text("Atanan kişi görev satırında görünür; yine de herkes tamamlayabilir.")
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Yeni Görev" : "Görevi Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let existing {
                    title = existing.title
                    detail = existing.description ?? ""
                    if let due = existing.dueDate {
                        hasDueDate = true
                        dueDate = due
                    }
                    recurrence = existing.recurrence.flatMap(Recurrence.init)
                    assignedTo = existing.assignedTo
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
                let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                let description = trimmedDetail.isEmpty ? nil : trimmedDetail
                let due = hasDueDate ? dueDate : nil
                let repeats = hasDueDate ? recurrence?.rawValue : nil
                if let existing {
                    _ = try await session.api.updateTask(
                        id: existing.id, title: trimmedTitle, description: description, dueDate: due,
                        assignedTo: assignedTo, recurrence: repeats)
                } else {
                    _ = try await session.api.createTask(
                        categoryId: categoryId, title: trimmedTitle, description: description, dueDate: due,
                        assignedTo: assignedTo, recurrence: repeats)
                }
                await session.refresh()
                await onSaved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
