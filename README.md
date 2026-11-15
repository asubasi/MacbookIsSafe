# HingeGuard

MacBook için kişisel anti-hırsızlık alarmı. Menü çubuğunda çalışır.
Alarm kurulduktan sonra menteşe açısı değişirse ya da güç kablosu çekilirse
5 saniyelik uyarı penceresinin ardından yüksek sesli siren çalar.
Devre dışı bırakmak için Touch ID / Mac parolası gerekir.

## Derleme ve çalıştırma

```bash
cd ~/Desktop/HingeGuard
swift build
swift run
```

Menü çubuğunda 🔓 simgesi çıkar. Menüden "Alarmı kur" seçeneğine bas, 10 sn içinde uzaklaş.

Sensör okumak bazı macOS sürümlerinde root yetkisi isteyebilir. Menteşe
sensörü okunamıyorsa menüde uyarı çıkar. O zaman şunu dene:

```bash
sudo .build/debug/HingeGuard
```

## DMG oluşturma

```bash
./scripts/make-dmg.sh
```

`dist/HingeGuard-<sürüm>.dmg` oluşur. DMG'yi açıp `HingeGuard.app`'i Uygulamalar klasörüne sürükle.
Uygulama ad-hoc imzalı (Apple Developer kimliği yok). Kendi Mac'inde sorunsuz açılır;
başka bir Mac'te ilk açılışta Gatekeeper uyarı verir: sağ tık → Aç, ya da
Sistem Ayarları → Gizlilik ve Güvenlik → "Yine de aç".

Sürüm numarası `scripts/make-dmg.sh` içindeki `VERSION` değişkeninde.

## Telefon bildirimi (opsiyonel)

[ntfy.sh](https://ntfy.sh) uygulamasını telefonuna kur, kendine özel bir konu adı seç ve:

```bash
HINGEGUARD_NTFY_TOPIC=gizli-konu-adin swift run
```

## Durum

İlk prototip. Derleniyor, henüz gerçek cihazda denenmedi.

- [x] Menteşe açısı (IOKit HID, resmi olmayan yol)
- [x] Güç kablosu çekilmesi
- [x] Uyku engeli, siren, ses zorla açma, Touch ID ile kapatma, ntfy bildirimi
- [x] Hareket/eğim algılama (SPU ivmeölçeri, resmi olmayan yol; M4 Pro'da root gerekmeden çalışıyor). Eşik 30 mg (art arda 2 × 200 ms) veya 8° eğim.
- [x] Canlı sensör paneli (menteşe açısı, ivme, eğim, grafikler)
- [ ] Kapak kapanınca uykuya geçme sorunu: kapak kapanırsa Mac uyur ve siren çalamaz. Uyanınca alarm hemen tetiklenir ama uyku sırasında susar.
- [x] Gerçek .app paketi ve DMG
- [ ] Açılışta otomatik başlatma
