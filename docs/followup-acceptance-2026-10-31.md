# Ek denetim sonrası doğrulama

- Alınmış 500 TL ödeme, veresiye veya başka tutarla değiştirilemiyor. Yeniden tamamlamada aynı ödeme kimliği/tarih/tutar korunuyor.
- SQLite hata enjeksiyonunda randevu/istatistikler ve müşteri/telefon değişimi birlikte geri alınıyor. Profil/fotoğraf geçmişi hatası da kısmi profil bırakmıyor.
- Eksik fotoğrafta yeni yedek başarı diye dönmüyor. Açık dışlama seçeneği aktif DB'yi değiştirmeyen, geri yüklenebilir bir snapshot oluşturuyor. Mevcut fotoğrafları içeren 999 fotoğraflı ZIP doğrulanıyor.
- İçe aktarılmış, milisaniyesiz gece yarısı tahsilatı hem ana kasa hem rapora dahil ediliyor.
- Native alarm false/exception sonucu görünür başarısızlık; geçmiş/iptal randevu için alarm istenmiyor. Aynı dakikada iki alarmın aynı saniyeyi kullanması önleniyor; native mutasyon kuyruğu hata sonrası devam ediyor.
- Gecikmiş arama/tarih sonucu, temizlenmiş arama ve kapanmış ekranı değiştiremiyor.
- Önce beş temel regresyonun eski kaynakta başarısız olduğu görüldü; ardından düzeltmeler ve ek regresyonlarla tam paket 127 teste ulaştı. Yerel analyzer temiz.

Otomatik testler fiziksel telefon/işletme kabulünün yerine geçmez. Bu turdaki yeni native sonuçlar ve debug build/CI doğrulaması tamamlandığında bu kayda eklenir. Tarihsel emülatör turu: [önceki kabul](acceptance-2026-10-31.md).
