# Android emülatör kontrolü — 2026-11-10

Berber_Test, Android 16 x86_64. Testler güncel Flutter kaynaklarından üretilen ayrı `com.barberbook.codexqa.ux` paketi ve sentetik kayıtlarla yürütüldü. Normal görünüm ve 320 dp × 640 dp, 1,8× sistem yazısı denendi.

| Ekran | Emülatörde gözlenen sorun | Düzeltme ve tekrar kontrolü |
|---|---|---|
| Ana ekran | Müşteriler düğmesi sağa taştı. | Alt eylemler dar alanda ikon ve etiketi alt alta gösteriyor. İki etiket tam göründü. |
| Takvim | Açık takvim alt sınırı aştı, günler ve başlıklar kırpıldı. | Takvim ve randevular aynı dikey kaydırmaya katılıyor. Gün boşlukları ve kısa hafta başlıkları ayarlandı. Son haftaya kaydırma ve 20–30 günlerinin okunması görüldü. |
| Randevu formu | Büyük yazıda kayıt düğmesinin ikinci satırı kesildi. | Düğme en az 56 dp ve metin kadar büyüyor. Saat seçimi, formdan çıkış onayı ve sentetik randevu oluşturma denendi. |
| Yedekleme | Tarih harf harf kırıldı. İç dosya yolunu gösteren bildirim ekranı kapladı. | Bilgi tam genişlikte, Paylaş ve Geri yükle ayrı satırda. Kısa başarı bildirimi. Sentetik yedek ve düğmeler denendi. |
| Randevu işlemleri | Düzenle ve durum kaydırma arkasındaydı. | Görünür üç nokta menüsü ve kaydırılabilir durum seçenekleri. Menüden Gelmedi seçildi ve kartta görüldü. |

Kod denetimi ayrıca eşzamanlı bir alarm ekranının randevu kaydı sonrası yanlışlıkla kapanmasını, iptal edilen alarmın eski native listeden yeniden gelmesini ve eski formun tamamlanmış randevu durumunu geri yazmasını ele aldı. Kayıt işlemi kendi ekranını kapatır. İptal edilen çalma eski listeden geri eklenmez. Randevu durumu değiştiyse düzenleme yazısı reddedilir. Bu senaryolar otomatik regresyonlarla doğrulandı. Alarm eylemleri kısa ekranda kaydırılabilir ve ortak işlem kilidi kullanır. Arşivlenmiş hizmet tekrarda yeniden seçilmez.

Çalışma saati ekranında yükleme tamamlanana kadar Kaydet kapalı. Hata halinde yeniden deneme gösteriliyor. Boş haftalık programın işletme tarafından bilerek kapalı olarak işaretlenmesinin ayrı veri durumu ve uygun saat önerileri sonraki çalışmadır.

Fiziksel telefon, üretim imzalı güncelleme ve gerçek alarmın arka plan/cihaz yeniden başlatma senaryoları ayrı kabul kapsamındadır. Bu emülatör turu canlı müşteri iletişimi veya cihaz dışına yedek paylaşımı içermedi.
