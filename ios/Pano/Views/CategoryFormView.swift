import SwiftUI

// Kategori oluşturma/düzenleme. Yeni kategori, hangi sekmede açıldıysa oraya
// (kişisel ya da o gruba) kaydedilir — ayrıca seçim istemez.
struct CategoryFormView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let groupId: Int?
    let existing: Category?

    @State private var name = ""
    @State private var colorKey = "coral"
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var groupName: String? {
        guard let groupId else { return nil }
        return session.groups.first { $0.id == groupId }?.name
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Kategori adı (örn. Market)", text: $name)
                }
                Section("Renk") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4),
                              spacing: 16) {
                        ForEach(Palette.all) { item in
                            Button {
                                colorKey = item.id
                            } label: {
                                VStack(spacing: 5) {
                                    ZStack {
                                        Circle()
                                            .fill(item.color)
                                            .frame(width: 40, height: 40)
                                        if colorKey == item.id {
                                            Image(systemName: "checkmark")
                                                .font(.subheadline.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    Text(item.name)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
                if existing == nil {
                    Section {
                        Label(groupName.map { "\"\($0)\" grubunda oluşturulacak — tüm üyeler görür" }
                              ?? "Kişisel panonda oluşturulacak — sadece sen görürsün",
                              systemImage: groupId == nil ? "person.fill" : "person.2.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Yeni Kategori" : "Kategoriyi Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    colorKey = existing.color
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
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if let existing {
                    _ = try await session.api.updateCategory(id: existing.id, name: trimmed, color: colorKey)
                } else {
                    _ = try await session.api.createCategory(name: trimmed, color: colorKey, groupId: groupId)
                }
                await session.refresh()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
