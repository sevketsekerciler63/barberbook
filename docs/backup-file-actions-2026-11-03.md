# Yedek ekranında dosya hataları — 2026-11-03

Dosya seçiciden geç dönen sonuç, ekran kapandıktan sonra geri yüklemeyi başlatabiliyordu. Dosya seçme ve paylaşma çağrılarının hataları yakalanmıyordu; aynı düğmeye hızlı basışta ikinci dosya seçme/paylaşma çağrısı da başlayabiliyordu. Liste satırı dosyanın tarih/boyutunu build sırasında senkron okuduğu için listelemeden sonra silinmiş dosya çizim hatası üretebiliyordu. Liste yükleme hatasında geçici mesaj kaybolunca “Henüz yedek oluşturulmadı” görünüyordu.

## Düzeltilen davranış

- Seçme/paylaşma işlemleri ekranın meşgul durumunu kullanır. Yinelenen çağrı, yalnız düğmenin yeniden çizilmesine bağlı kalmadan metot girişinde engellenir. İşlem bitince veya hata/iptal olduğunda kontroller açılır.
- Native hata, görünür mesajla karşılanır; ekran kapandıktan sonra gelen dosya geri yüklenmez. Geç tamamlanma artık disposed state'i güncellemez.
- Dosya tarih ve boyutu asenkron snapshot olarak okunur; build içinde dosya I/O'su yok. Erişilemeyen satır açıkça belirtilir; paylaş/geri yükle kapalıdır. Yenile düğmesi dosya durumunu tekrar okur. Snapshot'tan sonra dosya kaybolursa işlem hatası ayrıca yakalanır.
- Liste okunamadığında kalıcı hata ve Tekrar dene görünür. Başarısız okuma boş yedek listesi sayılmaz.
- Paylaşım penceresinden dönmek, yedeğin cihaz dışına başarıyla taşındığı anlamına gelmez; böyle bir başarı iddiası eklenmedi. Veritabanı, ZIP biçimi ve güvenlik yedeği/geri yükleme algoritması değiştirilmedi.

## Kanıt

`backup_screen_failure_test.dart` içinde 7 widget senaryosu: yükleme hatası/yeniden deneme, platform picker hatası, çift çağrı/iptal, disposal sonrası geç dosya, paylaşma hatası/yeniden deneme, paylaşma sırasında çift çağrı/disposal, metadata yokluğu/yenileme. Native picker/share sınırları kontrollü sahte gateway ile temsil edilir; gerçek Android paylaşımının kabul edildiği iddia edilmez.

`backup_file_gateway_test.dart` gerçek geçici dosyadan metadata alır, dosyayı siler, snapshot'ın kaldığını ve yeni okumada kullanılamazlığın döndüğünü denetler. Geçici klasör de dosya olarak kabul edilmez.

Önceki 152 teste 8 test eklendi; tam paket 160 testtir. Fiziksel telefon bu tur bağlı değil; kullanıcı şu an bağlayamayacağını bildirmişti. Yeni üretim release/tag yok.
