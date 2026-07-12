import SwiftUI

struct ProfileView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmDeleteAccount = false
    @State private var infoMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Kullanıcı adı", value: session.user?.username ?? "")
                    TextField("Ad", text: $firstName)
                    TextField("Soyad", text: $lastName)
                    TextField("E-posta (isteğe bağlı)", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Kaydet") { saveProfile() }
                } header: {
                    Text("Hesap")
                } footer: {
                    Text("Kullanıcı adı değiştirilemez — bu senin kimliğin. Adın, görev tamamladığında diğer üyelere görünen isimdir.")
                }

                Section("Şifre") {
                    SecureField("Mevcut şifre", text: $currentPassword)
                    SecureField("Yeni şifre (en az 6 karakter)", text: $newPassword)
                    Button("Şifreyi Değiştir") { changePassword() }
                        .disabled(currentPassword.isEmpty || newPassword.count < 6)
                }

                Section {
                    Button("Çıkış Yap") {
                        dismiss()
                        session.logout()
                    }
                    Button("Hesabımı Sil", role: .destructive) {
                        confirmDeleteAccount = true
                    }
                } footer: {
                    Text("Kurucusu olduğun bir grup varsa hesabın silinemez — o gruplar sahipsiz kalır. Önce grupları silmen gerekir.")
                }
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .onAppear {
                firstName = session.user?.firstName ?? ""
                lastName = session.user?.lastName ?? ""
                email = session.user?.email ?? ""
            }
            .confirmationDialog(
                "Hesabın ve kişisel kategorilerin kalıcı olarak silinsin mi?",
                isPresented: $confirmDeleteAccount, titleVisibility: .visible
            ) {
                Button("Hesabımı Sil", role: .destructive) { deleteAccount() }
            }
            .alert("Tamamdır", isPresented: Binding(
                get: { infoMessage != nil },
                set: { if !$0 { infoMessage = nil } }
            )) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(infoMessage ?? "")
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

    private func saveProfile() {
        Task {
            do {
                let first = firstName.trimmingCharacters(in: .whitespaces)
                let last = lastName.trimmingCharacters(in: .whitespaces)
                let mail = email.trimmingCharacters(in: .whitespaces)
                _ = try await session.api.updateProfile(
                    firstName: first.isEmpty ? nil : first,
                    lastName: last.isEmpty ? nil : last,
                    email: mail.isEmpty ? nil : mail)
                await session.refresh()
                infoMessage = "Profilin güncellendi."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func changePassword() {
        Task {
            do {
                try await session.api.changePassword(current: currentPassword, new: newPassword)
                currentPassword = ""
                newPassword = ""
                infoMessage = "Şifren değiştirildi."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteAccount() {
        Task {
            do {
                try await session.api.deleteAccount()
                dismiss()
                session.logout()
            } catch {
                // Örn. kurucusu olduğu grup varsa sunucu engeller ve nedenini söyler.
                errorMessage = error.localizedDescription
            }
        }
    }
}
