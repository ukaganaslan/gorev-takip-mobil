import SwiftUI
import Observation

// Uygulamanın tek gerçeklik kaynağı: oturum, sunucudan gelen durum ve canlı senkron kanalı.
@MainActor
@Observable
final class Session {
    var user: User?
    var groups: [UserGroup] = []
    var categories: [Category] = []
    var isBootstrapping = true

    // SSE'den her "değişti" sinyali geldiğinde artar; açık ekranlar bunu izleyip kendini tazeler.
    var syncVersion = 0

    var serverAddress: String {
        didSet { UserDefaults.standard.set(serverAddress, forKey: "serverAddress") }
    }

    private(set) var token: String?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?

    init() {
        serverAddress = UserDefaults.standard.string(forKey: "serverAddress") ?? "http://127.0.0.1:4000"
        token = Keychain.load("token")
        #if DEBUG
        // Geliştirme kolaylığı: "-panoToken <jwt>" launch argümanı ile oturum enjekte edilebilir.
        if let injected = UserDefaults.standard.string(forKey: "panoToken") {
            token = injected
        }
        #endif
    }

    var isLoggedIn: Bool { token != nil }

    var api: APIClient {
        let url = URL(string: serverAddress.trimmingCharacters(in: .whitespaces))
            ?? URL(string: "http://127.0.0.1:4000")!
        return APIClient(baseURL: url, token: token)
    }

    func bootstrap() async {
        if token != nil {
            // Önce son bilinen durum: ağ yavaşsa/yoksa ekran boş kalmasın.
            if let cached = DiskCache.load(StateResponse.self, from: "state") {
                user = cached.user
                groups = cached.groups
                categories = cached.categories
            }
            await refresh()
            startEvents()
        }
        isBootstrapping = false
    }

    func signedIn(_ auth: AuthResponse) async {
        token = auth.token
        Keychain.save(auth.token, key: "token")
        user = auth.user
        await refresh()
        startEvents()
    }

    func logout() {
        eventsTask?.cancel()
        eventsTask = nil
        Reminders.cancelAll()
        DiskCache.clear()
        WidgetBridge.clear()
        Keychain.delete("token")
        token = nil
        user = nil
        groups = []
        categories = []
    }

    // Sunucudaki güncel durumu tek istekte çeker. Ağ hatasında eldeki veri korunur;
    // oturum düşmüşse (401) çıkışa döner.
    func refresh() async {
        guard token != nil else { return }
        do {
            let state = try await api.state()
            user = state.user
            groups = state.groups
            categories = state.categories
            DiskCache.save(state, as: "state")
            // Yaklaşan görevleri bir kez çek: hem hatırlatıcılar hem widget beslenir.
            let api = api, userId = user?.id
            Task.detached {
                let tasks = (try? await api.reminderTasks()) ?? []
                WidgetBridge.publish(tasks)
                await Reminders.schedule(tasks: tasks, userId: userId)
            }
        } catch let e as APIError where e.status == 401 {
            logout()
        } catch {
            // çevrimdışı: mevcut görünümü boz(ma)
        }
    }

    // Canlı senkronizasyon: sunucunun SSE kanalını dinler, kopunca kendini yeniler.
    func startEvents() {
        eventsTask?.cancel()
        guard let token else { return }
        guard let url = URL(string: "/api/events", relativeTo: api.baseURL) else { return }

        eventsTask = Task {
            while !Task.isCancelled {
                do {
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 3600
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    for try await line in bytes.lines where line.hasPrefix("data:") {
                        await refresh()
                        syncVersion += 1
                    }
                } catch {
                    // bağlantı koptu; birazdan yeniden dene
                }
                if Task.isCancelled { break }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}
