import Foundation

struct User: Codable, Identifiable, Hashable {
    let id: Int
    let username: String
    var firstName: String?
    var lastName: String?
    var email: String?

    var displayName: String {
        let full = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return full.isEmpty ? username : full
    }
}

struct Member: Codable, Identifiable, Hashable {
    let id: Int
    let username: String
    let firstName: String?

    var displayName: String { firstName ?? username }
}

struct UserGroup: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    let founderId: Int
    let inviteCode: String
    var members: [Member]
}

struct Category: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var color: String
    let ownerId: Int
    let groupId: Int?
    var taskCount: Int
    var doneCount: Int
}

enum Recurrence: String, CaseIterable, Identifiable {
    case daily, weekly, monthly
    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: "Her gün"
        case .weekly: "Her hafta"
        case .monthly: "Her ay"
        }
    }
}

struct TaskItem: Codable, Identifiable, Hashable {
    let id: Int
    var title: String
    var description: String?
    var dueDate: Date?
    let createdBy: Int
    let createdByName: String
    var assignedTo: Int?
    var assignedToName: String?
    var recurrence: String?
    var completedBy: Int?
    var completedByName: String?
    var completedAt: Date?
    let createdAt: Date

    var isDone: Bool { completedBy != nil }

    var isOverdue: Bool {
        guard let dueDate, !isDone else { return false }
        return dueDate < Calendar.current.startOfDay(for: .now)
    }
}

struct ReminderTask: Codable, Identifiable {
    let id: Int
    let title: String
    let dueDate: Date
    let assignedTo: Int?
    let categoryId: Int
    let categoryName: String
}

struct ActivityItem: Codable, Identifiable, Hashable {
    let id: Int
    let actorId: Int
    let actorName: String
    let action: String
    let taskTitle: String
    let categoryName: String
    let categoryColor: String
    let groupName: String?
    let createdAt: Date
}

struct StateResponse: Codable {
    let user: User
    let groups: [UserGroup]
    let categories: [Category]
}

struct AuthResponse: Codable {
    let token: String
    let user: User
}

struct OKResponse: Codable {}
