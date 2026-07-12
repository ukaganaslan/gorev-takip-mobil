import Foundation

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

private struct ServerMessage: Codable { let error: String? }

struct APIClient {
    var baseURL: URL
    var token: String?

    static let decoder: JSONDecoder = {
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        let dayOnly = DateFormatter()
        dayOnly.dateFormat = "yyyy-MM-dd"
        dayOnly.locale = Locale(identifier: "en_US_POSIX")

        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = iso.date(from: s) ?? isoFrac.date(from: s) ?? dayOnly.date(from: s) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Tarih çözülemedi: \(s)"
            ))
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    func send<T: Decodable>(_ method: String, _ path: String, bodyData: Data? = nil) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError(status: 0, message: "Sunucu adresi geçersiz. Giriş ekranındaki 'Sunucu ayarı'nı kontrol et.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = bodyData
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError(status: 0, message: "Sunucuya ulaşılamadı. Bağlantını ve sunucu adresini kontrol et.")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = (try? Self.decoder.decode(ServerMessage.self, from: data))?.error
            throw APIError(status: status, message: msg ?? "Sunucu hatası (\(status)).")
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    func request<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B) async throws -> T {
        try await send(method, path, bodyData: try Self.encoder.encode(body))
    }
}

// MARK: - Uç noktalar

extension APIClient {
    private struct Credentials: Encodable {
        let username: String
        let password: String
        var firstName: String?
    }
    private struct ProfileBody: Encodable {
        let firstName: String?
        let lastName: String?
        let email: String?
    }
    private struct PasswordBody: Encodable {
        let currentPassword: String
        let newPassword: String
    }
    private struct NameBody: Encodable { let name: String }
    private struct CodeBody: Encodable { let code: String }
    private struct CategoryBody: Encodable {
        let name: String
        let color: String
        var groupId: Int?
    }
    // nil alanlar anahtar atlanarak değil, açıkça null olarak gönderilir —
    // sunucu "alan gönderilmedi" ile "alan temizlendi"yi ayırt ediyor.
    private struct TaskBody: Encodable {
        let title: String
        let description: String?
        let dueDate: Date?
        let assignedTo: Int?
        let recurrence: String?

        enum CodingKeys: String, CodingKey { case title, description, dueDate, assignedTo, recurrence }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(title, forKey: .title)
            try c.encode(description, forKey: .description)
            try c.encode(dueDate, forKey: .dueDate)
            try c.encode(assignedTo, forKey: .assignedTo)
            try c.encode(recurrence, forKey: .recurrence)
        }
    }

    // hesap
    func register(username: String, password: String, firstName: String?) async throws -> AuthResponse {
        try await request("POST", "/api/register", body: Credentials(username: username, password: password, firstName: firstName))
    }
    func login(username: String, password: String) async throws -> AuthResponse {
        try await request("POST", "/api/login", body: Credentials(username: username, password: password))
    }
    func state() async throws -> StateResponse {
        try await send("GET", "/api/state")
    }
    func updateProfile(firstName: String?, lastName: String?, email: String?) async throws -> User {
        try await request("PUT", "/api/me", body: ProfileBody(firstName: firstName, lastName: lastName, email: email))
    }
    func changePassword(current: String, new: String) async throws {
        let _: OKResponse = try await request("PUT", "/api/me/password", body: PasswordBody(currentPassword: current, newPassword: new))
    }
    func deleteAccount() async throws {
        let _: OKResponse = try await send("DELETE", "/api/me")
    }

    // etkinlik akışı
    func activity() async throws -> [ActivityItem] {
        try await send("GET", "/api/activity")
    }

    // hatırlatıcı/widget için açık ve son tarihli görevler
    func reminderTasks() async throws -> [ReminderTask] {
        try await send("GET", "/api/tasks/upcoming")
    }

    // gruplar
    func createGroup(name: String) async throws -> UserGroup {
        try await request("POST", "/api/groups", body: NameBody(name: name))
    }
    func joinGroup(code: String) async throws -> UserGroup {
        try await request("POST", "/api/groups/join", body: CodeBody(code: code))
    }
    func renameGroup(id: Int, name: String) async throws -> UserGroup {
        try await request("PUT", "/api/groups/\(id)", body: NameBody(name: name))
    }
    func deleteGroup(id: Int) async throws {
        let _: OKResponse = try await send("DELETE", "/api/groups/\(id)")
    }
    func leaveGroup(id: Int) async throws {
        let _: OKResponse = try await send("POST", "/api/groups/\(id)/leave")
    }

    // kategoriler
    func createCategory(name: String, color: String, groupId: Int?) async throws -> Category {
        try await request("POST", "/api/categories", body: CategoryBody(name: name, color: color, groupId: groupId))
    }
    func updateCategory(id: Int, name: String, color: String) async throws -> Category {
        try await request("PUT", "/api/categories/\(id)", body: CategoryBody(name: name, color: color))
    }
    func deleteCategory(id: Int) async throws {
        let _: OKResponse = try await send("DELETE", "/api/categories/\(id)")
    }

    // görevler
    func tasks(categoryId: Int) async throws -> [TaskItem] {
        try await send("GET", "/api/categories/\(categoryId)/tasks")
    }
    func createTask(categoryId: Int, title: String, description: String?, dueDate: Date?, assignedTo: Int?, recurrence: String?) async throws -> TaskItem {
        try await request("POST", "/api/categories/\(categoryId)/tasks", body: TaskBody(title: title, description: description, dueDate: dueDate, assignedTo: assignedTo, recurrence: recurrence))
    }
    func updateTask(id: Int, title: String, description: String?, dueDate: Date?, assignedTo: Int?, recurrence: String?) async throws -> TaskItem {
        try await request("PUT", "/api/tasks/\(id)", body: TaskBody(title: title, description: description, dueDate: dueDate, assignedTo: assignedTo, recurrence: recurrence))
    }
    func complete(taskId: Int) async throws -> TaskItem {
        try await send("POST", "/api/tasks/\(taskId)/complete")
    }
    func uncomplete(taskId: Int) async throws -> TaskItem {
        try await send("POST", "/api/tasks/\(taskId)/uncomplete")
    }
    func deleteTask(id: Int) async throws {
        let _: OKResponse = try await send("DELETE", "/api/tasks/\(id)")
    }
}
