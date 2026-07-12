import SwiftUI

// Ana ekran: üstte "Kişisel" + grup sekmeleri, altında seçili sekmenin kategori kartları.
struct RootView: View {
    @Environment(Session.self) private var session
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue

    enum Tab: Hashable {
        case personal
        case group(Int)
    }

    @State private var selection = Tab.personal
    @State private var navPath = NavigationPath()
    @State private var showCategoryForm = false
    @State private var editingCategory: Category?
    @State private var categoryToDelete: Category?
    @State private var showGroups = false
    @State private var showProfile = false
    @State private var showActivity = false
    @State private var errorMessage: String?

    private var currentGroupId: Int? {
        if case .group(let id) = selection { return id }
        return nil
    }

    private var selectedGroup: UserGroup? {
        guard let id = currentGroupId else { return nil }
        return session.groups.first { $0.id == id }
    }

    private var visibleCategories: [Category] {
        session.categories.filter { $0.groupId == currentGroupId }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    tabChips
                    if let group = selectedGroup {
                        groupInfoRow(group)
                    }
                    if visibleCategories.isEmpty {
                        emptyState
                    } else {
                        categoryGrid
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pano")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { mainMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCategoryForm = true
                    } label: {
                        Label("Kategori Ekle", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: Category.self) { category in
                CategoryDetailView(categoryId: category.id)
            }
            #if DEBUG
            // Test/otomasyon: "-panoOpenCategory <id>" launch argümanı ile doğrudan
            // kategori ekranı açılır (simülatörde dokunma otomasyonu olmadığı için).
            .task {
                guard let s = UserDefaults.standard.string(forKey: "panoOpenCategory"),
                      let id = Int(s) else { return }
                for _ in 0..<20 {
                    if let cat = session.categories.first(where: { $0.id == id }) {
                        navPath.append(cat)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            #endif
            .refreshable { await session.refresh() }
            .sheet(isPresented: $showCategoryForm) {
                CategoryFormView(groupId: currentGroupId, existing: nil)
            }
            .sheet(item: $editingCategory) { category in
                CategoryFormView(groupId: category.groupId, existing: category)
            }
            .sheet(isPresented: $showGroups) { GroupsView() }
            .sheet(isPresented: $showProfile) { ProfileView() }
            .sheet(isPresented: $showActivity) { ActivityView() }
            .onChange(of: session.groups) {
                // Seçili grup silindiyse ya da gruptan çıkıldıysa Kişisel'e dön.
                if currentGroupId != nil && selectedGroup == nil {
                    withAnimation(.snappy) { selection = .personal }
                }
            }
            .confirmationDialog(
                "\"\(categoryToDelete?.name ?? "")\" ve içindeki tüm görevler silinsin mi?",
                isPresented: Binding(get: { categoryToDelete != nil },
                                     set: { if !$0 { categoryToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Kategoriyi Sil", role: .destructive) {
                    if let category = categoryToDelete { delete(category) }
                }
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
    }

    // MARK: - Sekmeler

    private var tabChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Kişisel", icon: "person.fill", tab: .personal)
                ForEach(session.groups) { group in
                    chip(group.name, icon: "person.2.fill", tab: .group(group.id))
                }
                Button {
                    showGroups = true
                } label: {
                    Label("Grup", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().strokeBorder(.quaternary))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ label: String, icon: String, tab: Tab) -> some View {
        let isSelected = selection == tab
        return Button {
            withAnimation(.snappy) { selection = tab }
        } label: {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(isSelected
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(Color(.secondarySystemGroupedBackground))))
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func groupInfoRow(_ group: UserGroup) -> some View {
        NavigationLink {
            GroupDetailView(groupId: group.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(Color.accentColor)
                Text("\(group.members.count) üye")
                if group.founderId == session.user?.id {
                    Text("· kurucusun").foregroundStyle(.secondary)
                }
                Spacer()
                Text(group.inviteCode)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kategoriler

    private var categoryGrid: some View {
        // Uyarlanır sütunlar: iPhone'da 2, iPad'de genişliğe göre 4-6 kart.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 12)],
                  spacing: 12) {
            ForEach(visibleCategories) { category in
                NavigationLink(value: category) {
                    CategoryCard(category: category)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if canManage(category) {
                        Button {
                            editingCategory = category
                        } label: {
                            Label("Düzenle", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            categoryToDelete = category
                        } label: {
                            Label("Sil", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .animation(.snappy, value: visibleCategories)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Henüz kategori yok", systemImage: "tray")
        } description: {
            Text(currentGroupId == nil
                 ? "Sağ üstteki + ile ilk kategorini aç: Market, Ev İşleri, ne istersen."
                 : "Bu grupta henüz kategori yok. Sağ üstteki + ile ilkini sen aç; tüm üyeler görür.")
        }
        .padding(.top, 60)
    }

    // Kategoriyi oluşturan (veya grup kategorisiyse grubun kurucusu) yönetebilir.
    private func canManage(_ category: Category) -> Bool {
        guard let me = session.user?.id else { return false }
        if category.ownerId == me { return true }
        if let groupId = category.groupId,
           let group = session.groups.first(where: { $0.id == groupId }) {
            return group.founderId == me
        }
        return false
    }

    private func delete(_ category: Category) {
        Task {
            do {
                try await session.api.deleteCategory(id: category.id)
                await session.refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Menü

    private var mainMenu: some View {
        Menu {
            Button {
                showProfile = true
            } label: {
                Label("Profil", systemImage: "person.circle")
            }
            Button {
                showGroups = true
            } label: {
                Label("Gruplar", systemImage: "person.2")
            }
            Button {
                showActivity = true
            } label: {
                Label("Etkinlik", systemImage: "clock.arrow.circlepath")
            }
            Picker("Görünüm", selection: $appearanceRaw) {
                ForEach(Appearance.allCases) { appearance in
                    Label(appearance.label, systemImage: appearance.icon)
                        .tag(appearance.rawValue)
                }
            }
            Divider()
            Button(role: .destructive) {
                session.logout()
            } label: {
                Label("Çıkış Yap", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "line.3.horizontal")
        }
    }
}

// Kategori kartı: renk, ad ve "girmeden durumu gör" ilerleme çubuğu.
struct CategoryCard: View {
    let category: Category

    private var color: Color { Palette.color(category.color) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                Spacer()
                if category.taskCount > 0 {
                    Text("\(category.doneCount)/\(category.taskCount)")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text(category.name)
                .font(.headline)
                .fontDesign(.rounded)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if category.taskCount > 0 {
                ProgressView(value: Double(category.doneCount),
                             total: Double(max(category.taskCount, 1)))
                    .tint(color)
                Text("\(category.doneCount)/\(category.taskCount) tamamlandı")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Henüz görev yok")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(height: 120, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(color.opacity(0.13))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(color.opacity(0.2), lineWidth: 1)
        )
    }
}
