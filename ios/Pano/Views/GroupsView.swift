import SwiftUI

// Grup listesi + kurma ve davet koduyla katılma.
struct GroupsView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var showCreate = false
    @State private var newGroupName = ""
    @State private var showJoin = false
    @State private var joinCode = ""
    @State private var showScanner = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if session.groups.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("Henüz bir grubun yok", systemImage: "person.2")
                        } description: {
                            Text("Grup kur ve davet kodunu ailene ya da ev arkadaşlarına gönder — ya da sana gelen kodla bir gruba katıl.")
                        }
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section("Grupların") {
                        ForEach(session.groups) { group in
                            NavigationLink {
                                GroupDetailView(groupId: group.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(group.name)
                                            .font(.body.weight(.medium))
                                        if group.founderId == session.user?.id {
                                            Text("Kurucu")
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    Text("\(group.members.count) üye")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        newGroupName = ""
                        showCreate = true
                    } label: {
                        Label("Yeni Grup Kur", systemImage: "plus.circle.fill")
                    }
                    Button {
                        joinCode = ""
                        showJoin = true
                    } label: {
                        Label("Davet Koduyla Katıl", systemImage: "envelope.open.fill")
                    }
                    Button {
                        showScanner = true
                    } label: {
                        Label("QR Kodla Katıl", systemImage: "qrcode.viewfinder")
                    }
                } footer: {
                    Text("Grubu kuran kişi otomatik olarak kurucu olur; davet kodu grup ekranında görünür.")
                }
            }
            .navigationTitle("Gruplar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .alert("Yeni Grup", isPresented: $showCreate) {
                TextField("Grup adı (örn. Yılmaz Ailesi)", text: $newGroupName)
                Button("Kur") { createGroup() }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Grubu kurunca sana 8 karakterlik bir davet kodu verilir.")
            }
            .sheet(isPresented: $showScanner) {
                QRScannerSheet { code in
                    joinCode = code
                    joinGroup()
                }
            }
            .alert("Gruba Katıl", isPresented: $showJoin) {
                TextField("Davet kodu (örn. X7B2M9QK)", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Katıl") { joinGroup() }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Sana gönderilen 8 karakterlik kodu yapıştır.")
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

    private func createGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            do {
                _ = try await session.api.createGroup(name: name)
                await session.refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func joinGroup() {
        let code = joinCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard !code.isEmpty else { return }
        Task {
            do {
                _ = try await session.api.joinGroup(code: code)
                await session.refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// Grup detayı: davet kodu paylaşımı, üyeler ve kurucu/üye eylemleri.
struct GroupDetailView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let groupId: Int

    @State private var showRename = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var confirmLeave = false
    @State private var copied = false
    @State private var errorMessage: String?

    private var group: UserGroup? {
        session.groups.first { $0.id == groupId }
    }

    private var isFounder: Bool {
        group?.founderId == session.user?.id
    }

    var body: some View {
        List {
            if let group {
                Section("Davet Kodu") {
                    VStack(spacing: 12) {
                        InviteQR(code: group.inviteCode)
                            .padding(.top, 4)
                        Text(group.inviteCode)
                            .font(.system(.title, design: .monospaced).weight(.bold))
                            .kerning(4)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                        Text("Bu kodu paylaş; \"Davet Koduyla Katıl\" diyen herkes gruba girer.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            Button {
                                UIPasteboard.general.string = group.inviteCode
                                withAnimation { copied = true }
                            } label: {
                                Label(copied ? "Kopyalandı" : "Kopyala",
                                      systemImage: copied ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            ShareLink(item: "\"\(group.name)\" grubuna katıl! Pano davet kodu: \(group.inviteCode)") {
                                Label("Paylaş", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.bottom, 4)
                    }
                }

                Section("Üyeler (\(group.members.count))") {
                    ForEach(group.members) { member in
                        HStack(spacing: 8) {
                            Text(member.displayName)
                            if member.id == group.founderId {
                                Image(systemName: "crown.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            if member.id == session.user?.id {
                                Text("sen")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    if isFounder {
                        Button {
                            newName = group.name
                            showRename = true
                        } label: {
                            Label("Adı Değiştir", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Grubu Sil", systemImage: "trash")
                        }
                    } else {
                        Button(role: .destructive) {
                            confirmLeave = true
                        } label: {
                            Label("Gruptan Ayrıl", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                } footer: {
                    Text(isFounder
                         ? "Kurucu gruptan ayrılamaz — grup sahipsiz kalmasın diye. Grubu silersen içindeki tüm kategoriler ve görevler de silinir."
                         : "Ayrıldığında bu grubun kategorilerini artık görmezsin.")
                }
            }
        }
        .navigationTitle(group?.name ?? "Grup")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: session.groups) {
            if group == nil { dismiss() }
        }
        .alert("Grup Adı", isPresented: $showRename) {
            TextField("Grup adı", text: $newName)
            Button("Kaydet") { rename() }
            Button("Vazgeç", role: .cancel) {}
        }
        .confirmationDialog(
            "\"\(group?.name ?? "")\" ve içindeki tüm kategoriler ile görevler silinsin mi?",
            isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("Grubu Sil", role: .destructive) { deleteGroup() }
        }
        .confirmationDialog(
            "\"\(group?.name ?? "")\" grubundan ayrılmak istiyor musun?",
            isPresented: $confirmLeave, titleVisibility: .visible
        ) {
            Button("Gruptan Ayrıl", role: .destructive) { leaveGroup() }
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

    private func rename() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            do {
                _ = try await session.api.renameGroup(id: groupId, name: name)
                await session.refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteGroup() {
        Task {
            do {
                try await session.api.deleteGroup(id: groupId)
                await session.refresh()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func leaveGroup() {
        Task {
            do {
                try await session.api.leaveGroup(id: groupId)
                await session.refresh()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
