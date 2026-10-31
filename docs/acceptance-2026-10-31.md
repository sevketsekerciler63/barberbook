# 2026-10-31 doğrulama kaydı

## Otomatik kontroller

- 108 Flutter testi geçti; model, gerçek SQLite, migration, yedek ve widget akışları dahil.
- `flutter analyze --no-pub` temiz.
- Android ARM64 ve x86_64 debug APK üretildi. Portföy kopyasında x86_64 debug APK ayrıca üretildi.
- Açık portföy deposunda GitHub Actions format, analyzer ve test adımları başarılı.

## Android emülatör kabulü

Bu tur `Berber_Test` emülatöründe yapıldı. Fotoğraf ve gerçek alarm denemeleri, mevcut kurulumun verisini korumak için ayrı `com.barberbook.codexqa` uygulama kimlikli geçici test kopyasında çalıştırıldı. Test paneli gerçek uygulama ekranlarını ve servislerini açtı; gerçek müşteri verisi kullanılmadı.

| Senaryo | Uygulanan işlem ve gözlenen sonuç |
| --- | --- |
| Fotoğraflı müşterinin telefonunu değiştirme | Yeni randevu formunda müşteri arandı ve listeden seçildi; `05000000001` yerine `05000000002` girildi, yeni randevu kaydedildi. Aynı müşteri kimliği, eski randevu, not ve fotoğraf galerisi korundu. Gerçek fotoğraf dosyası SHA-256 karşılaştırmasında birebir aynı; iki randevu aynı müşteriye bağlı. |
| SQLite bütünlüğü | Form işlemi sonrasında `integrity_check = ok`, foreign-key hatası yok. |
| Randevu iptalinden sonra kasa | Önceden alınmış 500 ₺ nakit ödemeli randevu ana ekrandaki Durum menüsünden iptal edildi. Ana ekranın bugünkü tahsilatı ve aynı günün tahsilat raporu 500 ₺ kaldı. Durum değişimi para iadesi sayılmıyor. |
| Gerçek alarm | Bildirim ve tam zamanlı alarm izinleriyle gelecek dakikaya randevu alarmı kuruldu. Native alarm tetiklendi, gerçek `Alarm.ringing` olayı ve ürünün alarm ekranı görüldü; Kapat düğmesiyle durduruldu. |
| Arka plan alarmı | Home tuşuyla uygulama arka plana alındı. İkinci native alarm tetiklendi ve bildirim oluştu. Launcher üzerinden uygulamaya dönülünce alarm ekranı görüldü ve Kapat çalıştı. Ekranın kendiliğinden öne gelmesi bu emülatörde doğrulanmadı. |
| Restore sonrası alarm eşleme | Ayrı native denemede eski alarm kaydı kaldırıldı; geri yüklenen gelecekteki planlı randevunun kimliğine karşılık gelen alarm oluştu. Otomatik testler ayrıca kısmi alarm hatasında verinin korunmasını denetliyor. |

## Tekrarlama ve sınırlar

1. Gerçek veriye dokunmayan bir test kurulumunda fotoğraflı müşteri ve eski randevu oluşturun.
2. Yeni randevuda müşteriyi listeden seçin; telefonu değiştirip kaydedin. Müşteri kartında fotoğrafı, yeni telefonu ve iki randevuyu kontrol edin.
3. Nakit ödeme alınmış bir randevuyu iptal edin; ana kasa ile aynı tarih raporunun eşit kaldığını kontrol edin.
4. İzinleri ayarlayıp yakın geleceğe alarm kurun; ön planda, arka planda, ekran kilidinde ve yeniden başlatma sonrasında kendi cihazınızda ayrı ayrı deneyin.

Bu tur yeni fiziksel telefon/işletme kabulü veya üretim imzalı release dağıtımı yapılmadı. Emülatör sonucu farklı üreticilerin güç yönetimi, kilit ekranı veya reboot davranışını garanti etmez. Debug APK üretim APK'sının yerine otomatik kurulmaz.

## Sadeleştirme

Toplu WhatsApp kampanya ekranı, çağrılmayan mesaj yardımcıları, boş titreşim metotları ve kullanılmayan `audioplayers` bağımlılığı kaldırıldı. Müşteri bazlı manuel WhatsApp bağlantısı, uygulama içi hatırlatma kontrolü ve `alarm` paketinin gerçek sesi/titreşimi korunuyor.
