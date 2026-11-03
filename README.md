# Self Control 

Aplikasi Android berbasis Flutter untuk pengendalian diri, fokus, dan pencegahan kecanduan gawai. Menggabungkan lapisan antarmuka Flutter yang modern dengan layanan aksesibilitas (*Android Accessibility Service*) native untuk memblokir aplikasi pengalih perhatian secara real-time dan anti-manipulasi (*tamper-resistant*).

---

## Fitur Utama

- **Pemblokiran Real-time & Responsif**:
  Mendeteksi aplikasi target di latar depan secara instan menggunakan `AppMonitorService` (*Android Accessibility Service*) dengan filter debounce optimal (400ms) tanpa jeda yang mengganggu.
- **Layar Kunci & Timer Anti-Tamper**:
  Menampilkan layar penguncian (*LockedScreen*) dengan hitung mundur waktu tunggu. Dilengkapi perlindungan terhadap manipulasi waktu (*clock tampering* mundur maupun lompatan maju).
- **Buka Akses Sementara Terlindungi Password**:
  Akses ke aplikasi terblokir hanya dapat dibuka sementara setelah waktu tunggu habis dan pengguna memasukkan kata sandi (dihash dengan SHA-256). Pengguna dapat memilih durasi (5, 10, 15 menit, atau durasi kustom).
- **Katalog & Manajemen Aplikasi Terpasang**:
  Daftar aplikasi terpasang di perangkat dapat dipindai secara otomatis untuk memudahkan pemilihan aplikasi yang ingin dibatasi.
- **Pemulihan Otomatis Saat Boot (*Boot Recovery*)**:
  Memulihkan status dan aturan pemblokiran secara otomatis saat perangkat dinyalakan ulang (*device reboot*) via `BootReceiver`.
- **Audit & Riwayat Aktivitas (*Activity Logging*)**:
  Mencatat riwayat percobaan pembukaan aplikasi, upaya manipulasi jam, serta status pembukaan akses sementara ke basis data lokal SQLite.
- **Desain Bersih & Elegan**:
  Antarmuka Material 3 dengan palet warna natural (*Cream Canvas*, *Dark Green*, dan *Peach Accent*) yang nyaman di mata dan bebas distraksi.

---

## Arsitektur Proyek

Proyek ini menerapkan prinsip arsitektur modular berlapis (*Clean Architecture*):

```text
self_control/
├── android/app/src/main/kotlin/com/example/self_control/
│   ├── accessibility/          # Android Accessibility Service & window launcher
│   ├── apps/                   # Provider informasi aplikasi terpasang native
│   ├── blocking/               # Engine evaluasi blokir & DebounceFilter
│   ├── persistence/            # SharedPreferences native store untuk performa cepat
│   ├── platform/               # MethodChannel handler untuk integrasi Flutter
│   ├── receiver/               # BroadcastReceiver (BOOT_COMPLETED)
│   └── recovery/               # Logika pemulihan proteksi pasca-reboot
├── lib/
│   ├── application/services/   # Logika bisnis (LockSession, RuntimeSync, TemporaryUnlock)
│   ├── core/                   # Konstanta warna, spacing, theme, dan platform channel
│   ├── data/                   # Database SQLite, model data, dan repositori
│   ├── presentation/           # Layar UI (Dashboard, Selection, LockScreen, Settings)
│   └── main.dart               # Entry point aplikasi Flutter
└── test/                       # 400+ unit, widget, dan adversarial resilience tests
```

---

## Prasyarat & Lingkungan Pengembangan

- **Flutter SDK**: `>=3.13.5`
- **Dart SDK**: `^3.13.5`
- **JDK**: Java 17 atau lebih baru
- **Android SDK**: Min SDK 24 (Android 7.0), Target SDK 34 (Android 14)
- **Perangkat Android Fisik atau Emulator** dengan dukungan Google Play Services

---

## Panduan Memulai

### 1. Kloning Repositori
```bash
git clone https://github.com/goks29/self_control.git
cd self_control
```

### 2. Pasang Dependensi
```bash
flutter pub get
```

### 3. Jalankan Aplikasi
Jalankan aplikasi pada perangkat Android atau emulator:
```bash
flutter run
```

### 4. Konfigurasi Izin di Perangkat
Agar aplikasi dapat memonitor dan memblokir aplikasi target:
1. Buka aplikasi **Self Control**.
2. Masuk ke panduan aktivasi atau menu pengaturan.
3. Berikan izin **Aksesibilitas (*Accessibility Service*)** untuk Self Control pada Pengaturan Android Anda.

---

## Pengujian (*Testing*)

Proyek ini dilengkapi dengan suite pengujian otomatis komprehensif, mencakup *unit test*, *widget test*, hingga *adversarial state tests*.

### Menjalankan Uji Flutter
```bash
flutter test
```

### Menjalankan Uji Unit Android (Kotlin)
```bash
cd android
./gradlew testDebugUnitTest
cd ..
```

---

## Keamanan & Privasi

- **Penyimpanan Lokal**: Seluruh data aturan pemblokiran, sesi, dan log aktivitas tersimpan secara offline di perangkat pengguna menggunakan SQLite.
- **Enkripsi Password**: Kata sandi penguncian disimpan dalam bentuk hash SHA-256 dengan salt unik, tidak pernah disimpan dalam bentuk teks polos (*plain text*).
- **Perlindungan Jam**: Timer hitung mundur memverifikasi waktu monotonik sistem dan mendeteksi anomali jika jam sistem dimanipulasi secara manual.

---

