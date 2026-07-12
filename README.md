# Pano

Aile ve küçük gruplar için görev takip uygulaması — buzdolabına yapıştırılan ortak
yapılacaklar listesinin dijitali. Birden fazla kişi aynı listeye bakar; kim ne yaptı
anında herkesin ekranına düşer.

Native **SwiftUI** iOS/iPadOS uygulaması + sıfır bağımlılıklı **Node.js** backend.

## Özellikler

- **Gruplar:** Davet kodu veya QR ile katılım; kategoriler ve görevler tüm üyelerde canlı senkronize (SSE).
- **Görevler:** Açıklama, son tarih, üyeye atama, günlük/haftalık/aylık tekrar.
- **Etkinlik akışı:** Kim hangi görevi ne zaman ekledi/tamamladı/sildi.
- **Hatırlatıcılar:** Son tarihli görevler için yerel bildirim.
- **Widget:** Ana ekranda yaklaşan görevler (küçük/orta boy).
- **Çevrimdışı:** Ağ yokken son bilinen durum gösterilir.
- **Kurallar sunucuda:** "Tamamlamayı sadece tamamlayan geri alabilir", "görevi sadece
  oluşturan silebilir", "kurucu gruptan ayrılamaz" gibi kurallar backend'de zorlanır.
- **Güvenlik:** Şifreler scrypt ile özetlenir; oturum JWT ile yürür, cihazda Keychain'de saklanır.

## Gereksinimler

| Bileşen | Sürüm |
|---|---|
| Node.js | 24+ (`node:sqlite` yerleşik modülü için; `npm install` gerekmez) |
| Xcode | 16+ |
| iOS / iPadOS | 17+ |

## Kurulum

### 1. Sunucu

```bash
cd server
node server.js        # http://localhost:4000 — PORT ortam değişkeniyle değiştirilebilir
```

Veritabanı ve imza anahtarı ilk çalıştırmada `server/data/` altında kendiliğinden
oluşur. Her şeyi sıfırlamak için sunucuyu durdurup bu klasörü silmek yeterlidir.

### 2. iOS uygulaması

```bash
open ios/Pano.xcodeproj
```

Xcode'da bir simülatör seçip **Run**'a bas.

- **Simülatörde:** varsayılan sunucu adresi (`http://127.0.0.1:4000`) doğrudan çalışır.
- **Gerçek cihazda:** telefon ile sunucunun çalıştığı makine aynı ağda olmalı. Giriş
  ekranındaki **Sunucu ayarı** alanına makinenin yerel IP'sini yaz
  (örn. `http://192.168.1.10:4000`; IP için `ipconfig getifaddr en0`).
- İnternet üzerinden kullanım için sunucu **HTTPS** arkasında yayınlanmalıdır
  (ATS, yerel ağ dışında düz HTTP'ye izin vermez).

İlk açılışta **Hesap Aç** ile kullanıcı oluştur, bir grup kur ve davet kodunu paylaş.

## Proje yapısı

```
├── server/                 Backend — tek dosya, sıfır npm bağımlılığı
│   ├── server.js           HTTP API + SQLite şeması + SSE canlı senkron
│   └── data/               Çalışma zamanında oluşur: pano.db + secret.key (git'e girmez)
└── ios/
    ├── Pano.xcodeproj      İki hedef: Pano (uygulama) + PanoWidget (widget)
    ├── Pano/
    │   ├── PanoApp.swift   Giriş noktası
    │   ├── Session.swift   Oturum, durum ve SSE senkron kanalı (tek gerçeklik kaynağı)
    │   ├── APIClient.swift Tüm API çağrıları
    │   ├── Models.swift    Codable modeller
    │   ├── DiskCache.swift Çevrimdışı önbellek
    │   ├── Notifications.swift  Son tarih hatırlatıcıları
    │   ├── WidgetBridge.swift   Widget'a App Group üzerinden veri aktarımı
    │   └── Views/          SwiftUI ekranları
    └── PanoWidget/         WidgetKit extension (yaklaşan görevler)
```

### Mimari notları

- **API:** Tüm uç noktalar `server/server.js` içinde `route(...)` çağrıları olarak
  listelenir; JSON konuşur, hata mesajları Türkçedir ve arayüzde doğrudan gösterilir.
- **Canlı senkron:** Sunucu her değişiklikte etkilenen kullanıcılara SSE ile sinyal
  yollar (`/api/events`, Bearer token ile); uygulama anında tazelenir, kopan bağlantı
  kendini yeniler.
- **Veritabanı:** SQLite (`node:sqlite`). Şema migration'ları açılışta otomatik uygulanır.
- **Widget verisi:** Uygulama her senkronda yaklaşan görevleri App Group konteynerine
  yazar; widget bu dosyayı okur.
