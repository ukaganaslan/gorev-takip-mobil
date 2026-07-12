import Foundation

// Çevrimdışı önbellek: sunucudan gelen son yanıtlar diske yazılır; ağ yokken
// boş ekran yerine son bilinen durum gösterilir. Kritik veri değildir —
// her başarılı senkron üzerine yazar, çıkışta tamamen silinir.
enum DiskCache {
    private static let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("pano-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func url(_ name: String) -> URL {
        dir.appendingPathComponent("\(name).json")
    }

    static func save<T: Encodable>(_ value: T, as name: String) {
        guard let data = try? APIClient.encoder.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? APIClient.decoder.decode(type, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: dir)
    }
}
