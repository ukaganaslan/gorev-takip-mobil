import SwiftUI

// Kategori renkleri: sunucuda anahtar adı saklanır, iki temada da okunaklı tonlar burada seçilir.
struct CategoryColor: Identifiable {
    let id: String
    let name: String
    let color: Color
}

enum Palette {
    static let all: [CategoryColor] = [
        .init(id: "coral",  name: "Mercan",  color: Color(red: 0.91, green: 0.36, blue: 0.28)),
        .init(id: "orange", name: "Turuncu", color: Color(red: 0.95, green: 0.60, blue: 0.22)),
        .init(id: "yellow", name: "Hardal",  color: Color(red: 0.83, green: 0.66, blue: 0.14)),
        .init(id: "green",  name: "Yeşil",   color: Color(red: 0.33, green: 0.65, blue: 0.37)),
        .init(id: "teal",   name: "Çam",     color: Color(red: 0.20, green: 0.61, blue: 0.57)),
        .init(id: "blue",   name: "Mavi",    color: Color(red: 0.27, green: 0.54, blue: 0.85)),
        .init(id: "purple", name: "Mor",     color: Color(red: 0.55, green: 0.42, blue: 0.83)),
        .init(id: "pink",   name: "Gül",     color: Color(red: 0.87, green: 0.42, blue: 0.63)),
    ]

    static func color(_ key: String) -> Color {
        all.first { $0.id == key }?.color ?? all[0].color
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Otomatik"
        case .light: "Açık"
        case .dark: "Koyu"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
