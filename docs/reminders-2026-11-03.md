# WhatsApp hatırlatma kimliği — 2026-11-03

## Sorun ve davranış

Önceki geçmiş anahtarı yalnız `randevuID_hatırlatmaTürü` idi. Açılmış/atlanmış bir randevu başka saate taşındığında yeni hatırlatma da gizleniyordu. Yedekten aynı ID ile farklı bir kayıt döndüğünde de aynı çakışma oluşabiliyordu. Açık bir pencere, randevu iptal edilmiş olsa bile eski mesaj bağlantısını açabiliyordu. Bu üç davranış düzeltmeden önce başarısız regresyonlarla doğrulandı.

Yeni geçmiş kimliği randevu ID'si, oluşturulma zamanı, yerel randevu saati, müşteri ID/oluşturulma zamanı, normalize alıcı numarası ve hatırlatma türünün SHA-256 özetidir. Tercih listesine açık telefon/isim yazılmaz; bu bir şifreleme özelliği değildir. Aynı kaydı aynı saatte geri yüklemek aynı atlama seçimini korur; başka kayıt/saat/numara yeni hatırlatmadır.

`wp_sent_reminders` eski seçimleri, iki uygulamanın `main` girişinde **arayüz açılmadan önce**, mevcut kayıtlarına bir kez bağlanır. Hatırlatma kapalı veya lisans ekranı açık olsa da geçiş yapılır. Bu sıralama önemlidir: yedek değişiminden sonra ilk kez geçiş yapmak eski seçimi yanlış kayda bağlayabilir. `wp_handled_reminders_v2` listesi tamamlanma işaretidir; eski liste ancak yeni liste kaydedildikten sonra kaldırılır. Artık bulunmayan eski kayıtlar yeni kayıtlara taşınmaz. Eski biçim geçmişteki randevu saatini içermediğinden, yükseltmeden **önce** yapılmış değişiklikler geriye dönük ayırt edilemez.

Geçmiş yazımları servis örnekleri arasında seri yapılır; eşzamanlı iki seçim birbirini ezmez. Dış bağlantı açılırken randevu değişirse yalnız açılan sürüm işlenmiş sayılır. Açmadan önce güncel randevu, planlı durum, gelecek saat, alıcı ve veri revizyonu denetlenir; eski pencere iptal/silme/saat/telefon/yedek değişiminden sonra bağlantı açmaz. Harici uygulama çağrısından sonraki teslimat doğrulanamaz; mesajı gönderen kullanıcıdır.

## Doğrulama

- `test/services/whatsapp_reminder_test.dart`: 16 test. Başarısız açma/exception, açık URL ve encoding, manuel atla, eski tercih geçişi, yeniden planlama, ID tekrar kullanımı, gerçek ZIP yedek geri yükleme, kapalı hatırlatmada startup geçişi, paralel seçim, iptal/silme/saat/alıcı değişimi, dış açma sırasında değişiklik kapsanır.
- Tam Flutter paketi: 152 test (önceki 141 + 11 yeni regresyon).
- Bu tur bağlı Android cihaz yoktu. Gerçek telefon/WhatsApp kurulumu veya mesaj gönderimi doğrulanmadı; harici URL açma testlerde sahte işlevle denetlenir. Üretim release/tag dağıtılmadı.

Fiziksel kabul: hatırlatmayı Atla → saati değiştir → yeni hatırlatma; sonra fotoğraflı ZIP geri yükleme ve kilit ekranı/reboot alarmı. WhatsApp'ta bağlantıyı açmak, gönderim/teslimat anlamına gelmez.
