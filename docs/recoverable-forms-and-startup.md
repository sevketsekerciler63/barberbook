# Kayıt ve açılış hatalarından toparlanma

Geliştirme **1.1.3+5**, SQLite **v14** (şema değişmedi). 6 Kasım kullanım analizinin ilk üç önceliği.

## Randevu formu

- Başlangıç müşteri/hizmet bilgileri yüklenmeden form açılmaz. Yükleme hatası boş/verisiz form gibi gösterilmez; yeniden deneme sunulur. Eksik müşteri kimliği açık hata verir.
- Değişiklik yapılmış formdan çıkarken **Düzenlemeye devam et / Kaydetmeden çık** seçilir. Değişmemiş form normal kapanır. Taslak kalıcı diske yazılmaz; süreç öldürülürse girilmemiş veriyi kurtarma garantisi yoktur.
- Kaydetme sırasında form ve geri çıkış kilitlidir, ilerleme görünür. Kayıt başarısız olursa bilgiler korunur, hata kaydet düğmesinin yanında kalır. Hata mesajı düğmenin üstünü kapatan geçici snackbar değildir.
- DB kaydı tamamlandıktan sonra alarm kurulumu hatası yeni kayıt denemesi başlatmaz. Randevu başarılı sonuçla ana ekrana döner; alarm için mevcut uyarı/yeniden deneme kullanılır. DB commit sonrası alarm beklerken de çıkış kilidi sürer.
- Uzun müşteri adları, tarih/saat/model metinleri dar ekranda satıra sığar; metin sistem ölçeği küçültülmez.

## Hizmet yönetimi

Liste okuma hatası yeniden denenebilir. Hizmet formu ayrı state/controller ömrüne sahiptir; kaydetme sırasında çift kayıt, form değişikliği ve geri çıkış engellenir. Hata yerinde gösterilir ve girişler korunur.

Fiyat, ödeme ekranıyla aynı tamsayı kuruş ayrıştırıcısını kullanır. Boş fiyat belirtilmemiştir; virgül/nokta ile en fazla iki ondalık kabul edilir. NaN, Infinity, üçüncü ondalık ve aşırı büyük değerler sessiz yuvarlanmaz. Ad1–60karakter, süre1–480dakika ve fiyat0–999999999999kuruş sınırları servis katmanında da kontrol edilir.

Aktif hizmet adı çakışması yazma transaction'ında Türkçe normalizasyonla denetlenir. Eşzamanlı aynı adlı yeni aktif hizmetlerden biri reddedilir. Eski DB'deki aynı adlı aktif hizmetler silinmez/birleştirilmez; adı ve aktifliği değişmeyen düzenlemeleri yapılabilir. Yeniden aktifleştirme ve ad değiştirme çakışma kontrolünden geçer. Şema/backup biçimi değişmez.

## Açılış ve müşteri arama

Uygulama hata verebilen işler öncesinde yükleme ekranını açar. Sıra: platform/yerel tarih hazırlığı → mevcut kurtarma kurallarıyla DB açma → WhatsApp hatırlatma geçmişi geçişi → native alarm hazırlığı → erişim kontrolü. Herhangi bir aşama hatasında ana veri ekranları açılmaz; kayıtları silmeden yeniden deneme sunulur. Başarılı aşamalar tekrar çalıştırılmaz. Private erişim/lisans kontrolü yalnız özel main içindedir; public portföy kopyası lisans kodu içermez.

Müşteri araması yükleniyor/hata/yeniden deneme durumlarını gösterir. Yazarken eski müşteri seçimi hemen temizlenir; eski sonuç/hata yeni sorguya uygulanmaz. Focus geri geldiğinde arama yenilenir; kapanmış widget'a yanıt uygulanmaz.

## Doğrulama ve sınırlar

Yeni randevu11, hizmet widget6/gerçekSQLite3, müşteri arama7 kontrolü eklendi. Aritmetik placeholder test kaldırıldı, yerine8 gerçek başlangıç akışı/ekran testi geldi. Bunlar kontrollü gateway'lerle sıralama, hata/yeniden deneme, erişim reddi, çift çağrı, geç sonuç, dar ekran/büyük yazı davranışını sınar; native Android izinlerinin veya tüm Home akışının fiziksel kabulü değildir. 237 testlik yerel tabana alarm teslimi, aynı anda açılan ekranlar, eski randevu durumu ve dar alarm ekranı regresyonları eklendi. Güncel paket 243 test.

Bu tur ilk üç güvenilirlik önceliği tamamlandı. Randevu kartında görünür düzenleme ve durum menüsü eklendi. Uygun saat önerisi, finans kısayolları, ilk peşin ödeme yöntem düzeltmesi ve büyük veri arama iyileştirmesi ayrı sonraki işlerdir. Yeni imzalı üretim yayını veya manuel telefon kabulü yapılmadı.
