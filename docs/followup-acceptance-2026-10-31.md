# Ek denetim sonrası doğrulama

- Alınmış 500 TL ödeme, veresiye veya başka tutarla değiştirilemiyor. Yeniden tamamlamada aynı ödeme kimliği/tarih/tutar korunuyor.
- SQLite hata enjeksiyonunda randevu/istatistikler ve müşteri/telefon değişimi birlikte geri alınıyor. Profil/fotoğraf geçmişi hatası da kısmi profil bırakmıyor.
- Eksik fotoğrafta yeni yedek başarı diye dönmüyor. Açık dışlama seçeneği aktif DB'yi değiştirmeyen, geri yüklenebilir bir snapshot oluşturuyor. Mevcut fotoğrafları içeren 999 fotoğraflı ZIP doğrulanıyor.
- İçe aktarılmış, milisaniyesiz gece yarısı tahsilatı hem ana kasa hem rapora dahil ediliyor.
- Native alarm false/exception sonucu görünür başarısızlık; geçmiş/iptal randevu için alarm istenmiyor. Aynı dakikada iki alarmın aynı saniyeyi kullanması önleniyor; native mutasyon kuyruğu hata sonrası devam ediyor.
- Gecikmiş arama/tarih sonucu, temizlenmiş arama ve kapanmış ekranı değiştiremiyor.
- Önce beş temel regresyonun eski kaynakta başarısız olduğu görüldü; ardından düzeltmeler ve ek regresyonlarla tam paket 127 teste ulaştı. Yerel analyzer temiz.

## Yeni native emülatör kabulü

Ayrı `com.barberbook.codexqa` uygulama kimliği ve tamamen sentetik veriler kullanıldı; normal uygulama verisiyle karıştırılmadı.

- Aynı 10:00 dakikasındaki iki randevu native pakette ayrı kimlikler ve `10:00:00` / `10:00:01` olarak birlikte kaldı. Kurulumlar aynı anda istendi; seri kuyruk çakışmayı önledi.
- Gerçek Müşteriler ekranından test müşteri kartı silindi. Gelecekteki randevu `planned`, müşteri bağlantısı null ve native alarm hâlâ kayıtlıydı. Test kayıtları sonrasında temizlendi.
- Native geçersiz alarm kimliğiyle kontrollü hata üretildi; sonuç `failed` kaldı. Ürünün “randevu kaydedildi, ancak alarm kurulamadı” uyarısı ve Tekrar dene aksiyonu görüldü. Yeniden deneme başarılı alarm eşlemesini bildirdi. Bu, fiziksel cihazdaki izin reddinin ayrıca test edildiği anlamına gelmez.
- Önceden 450 TL tahsil edilmiş randevu gerçek durum menüsünden planlandı ve tekrar tamamlandı. Yeni ödeme formu açılmadı; kasadaki 450 TL korundu.
- 300 TL veresiye için gerçek formdan 100 TL tahsil edildi. Rapor 550 TL hizmet tahsilatı, ayrı 20 TL bahşiş ve kalan 200 TL veresiye gösterdi.
- [41 saniyelik demo](demo.mp4), bu gerçek ekran akışının 2× hızlandırılmış kaydıdır; müşteri ve telefonların tamamı kurgusaldır.

Private kaynakta ARM64/x86_64 debug APK'lar yerel olarak üretildi; public GitHub CI aynı iki ABI çıktısını artifact olarak üretmek üzere yapılandırıldı. CI sonucunun kendisi ilgili commit'in Actions çalıştırmasından doğrulanır.

Otomatik testler ve bu emülatör kabulü fiziksel telefon/işletme kabulünün yerine geçmez. Yeni üretim imzalı release dağıtımı yapılmadı. Tarihsel emülatör turu: [önceki kabul](acceptance-2026-10-31.md).
