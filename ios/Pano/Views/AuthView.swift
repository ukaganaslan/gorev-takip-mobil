import SwiftUI

struct AuthView: View {
    @Environment(Session.self) private var session

    enum Mode { case login, register }

    @State private var mode = Mode.login
    @State private var username = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var session = session
        ScrollView {
            VStack(spacing: 28) {
                header

                Picker("Giriş türü", selection: $mode) {
                    Text("Giriş Yap").tag(Mode.login)
                    Text("Hesap Aç").tag(Mode.register)
                }
                .pickerStyle(.segmented)

                VStack(spacing: 12) {
                    if mode == .register {
                        field("Adın (isteğe bağlı)", text: $firstName)
                    }
                    field("Kullanıcı adı", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Şifre (en az 6 karakter)", text: $password)
                        .padding(14)
                        .background(fieldBackground)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button(action: submit) {
                    ZStack {
                        if isWorking {
                            ProgressView().tint(.white)
                        } else {
                            Text(mode == .login ? "Giriş Yap" : "Hesap Aç")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(username.count < 3 || password.count < 6 || isWorking)

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("http://192.168.1.10:4000", text: $session.serverAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(.footnote.monospaced())
                            .padding(10)
                            .background(fieldBackground)
                        Text("Simülatörde: http://127.0.0.1:4000 · Gerçek iPhone'da Mac'inin yerel IP adresini yaz (aynı Wi-Fi'da olmalı).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Sunucu ayarı", systemImage: "server.rack")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 88, height: 88)
                Image(systemName: "checklist")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text("Pano")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text("Evin ortak yapılacaklar listesi.\nHerkes görür; kim yaptıysa görünür.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 48)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .padding(14)
            .background(fieldBackground)
    }

    private func submit() {
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let auth: AuthResponse
                if mode == .login {
                    auth = try await session.api.login(username: username, password: password)
                } else {
                    let name = firstName.trimmingCharacters(in: .whitespaces)
                    auth = try await session.api.register(
                        username: username, password: password,
                        firstName: name.isEmpty ? nil : name)
                }
                await session.signedIn(auth)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
