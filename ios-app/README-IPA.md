# Changan Remote — iPhone 17 (`.ipa`) Hazırlanması

Mövcud `mobile-app` (Android), `vehicle-agent` və `protocol` kodlarına **heç bir dəyişiklik edilmədən**, ayrıca `ios-app/` qovluğunda iOS 17+ / iPhone 17 üçün native **SwiftUI** versiyası və avtomatik imzasız `.ipa` yığma sistemi hazırlanıb.

---

## Mac kompüter olmadan `.ipa` faylını necə əldə etmək olar?

1. **Layihəni GitHub-a (Private repo kimi) yükləyin:**
   - GitHub hesabınızda yeni **Private** repository yaradın.
   - Bütün layihəni (`.github/workflows/build-ios-ipa.yml` və `ios-app/` qovluğu daxil olmaqla) həmin repoya push edin.

2. **GitHub Actions-da avtomatik kompilyasiya:**
   - GitHub reponuzda **Actions → Build Unsigned iOS IPA** bölməsinə keçin (push edəndə avtomatik işə düşür, ya da *Run workflow* düyməsinə basın).
   - GitHub-ın macOS serveri Xcode ilə layihəni yığıb **`ChanganRemote-unsigned-ipa`** adlı fayl hazırlayır (~2–3 dəqiqə).

3. **`.ipa` faylını imzalayıb iPhone 17-yə quraşdırın:**
   - Artifacts bölməsindən **`ChanganRemote-unsigned.ipa`** faylını kompüterə endirin.
   - Öz `.ipa` imzalama proqramınızla (*Sideloadly, ESign, Feather, AltStore, Signulous* və s.) imzalayıb birbaşa **iPhone 17**-yə quraşdırın.

---

## İPhone versiyasının xüsusiyyətləri
- **Protokol və Təhlükəsizlik:** `vehicle-agent` ilə 100% eyni `HMAC-SHA256 (v2)` imzası, kanonik JSON və `Replay Cache` qoruması (`CryptoKit`).
- **Bağlantı:** Pure-Swift MQTT v3.1.1 TLS (`ssl://broker.hivemq.com:8883`) Apple `Network.framework` üzərindən.
- **Kamera və Audio:** Apple `VideoToolbox` (`AVSampleBufferDisplayLayer`) ilə canlı H.264 video axını, `PHPhotoLibrary` ilə yüksək keyfiyyətli kadr saxlanması, `AVAudioEngine` ilə canlı salon səsi dinləmə və meqafon (`AVAS_TALK`).
- **Qoşulma:** iPhone kamerası ilə avtomobil monitorundakı QR kodu skan edib (`PAIR_CONFIRM`) avtomatik bağlanma.
