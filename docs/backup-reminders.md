# Yerel yedek tarihi ve hatırlatma

Geliştirme sürümü **1.1.2+4**, SQLite şeması değişmeden **v14**.

## Kullanım

- Ana ekranda yerel yedek bulunmuyorsa **Henüz yerel yedek yok** kartı görünür.
- En yeni erişilebilir, boş olmayan yerel yedek dosyası 7 takvim gününü doldurduğunda hatırlatma görünür. Eşik yerel takvime göre hesaplanır; saat farkı/yaz saati nedeniyle 24 saat hesabıyla kaymaz.
- **Yedeklemeyi aç** var olan oluşturma, paylaşma ve geri yükleme ekranını açar. Yedekleme ekranında son yerel dosyanın tarihi vardır. Yeni yedek alıp ana ekrana dönünce hatırlatma yenilenir.
- Uygulamaya dönüşte ve görünür ekranda saatlik durum kontrol edilir. Hatırlatma randevu listesinin kaydırılan parçasıdır; arama sonuçlarına karışmaz.
- Dosya okuma hatası, yalnız erişilemeyen/boş dosyalar veya ilerideki dosya tarihi için ayrı mesaj vardır. Gelecek tarih hatırlatmayı sonsuza kadar gizlemez.

## Sınırlar

Tarih, uygulamanın yerel yedek klasöründeki ZIP/eski DB dosyalarının son değişiklik metadata'sıdır. Her hatırlatmada arşiv açılıp bütünlük doğrulanmaz; gerçek oluşturma ve geri yükleme akışlarının mevcut doğrulamaları korunur. Sıfır bayt dosyalar güncel yedek sayılmaz. Eski bir dosyanın metadata'sını dışarıdan değiştirmek tarih göstergesini değiştirebilir.

Uygulama kapalıyken işletim sistemi bildirimi gönderilmez. Otomatik yedek alınmaz, otomatik paylaşım yapılmaz. Paylaşım penceresini açmak cihaz dışına kopyalandığını kanıtlamaz; bu nedenle arayüz her zaman bir kopyayı cihaz dışına kaydetmeyi hatırlatır. Mevcut güvenlik yedekleri de yerel dosya listesinde yer alır; gösterge, güncel her değişikliğin yedeğe dahil olduğu garantisi değildir.

## Doğrulama

6 durum hesabı + 6 widget testi eklendi. İlk yedek, 7 gün eşiği, yıl geçişi, dosya sırasından bağımsız en yeni tarih, boş/okunamayan ve ileri tarihli dosyalar; çift gezinme, dönüşte yenileme, hata, eski asenkron yanıt, disposal, uygulamaya dönüş/saatlik kontrol ve 320dp/1.8× yazı kapsanır. Önceki 192 testle toplam 204 test. Gerçek Android cihaz denemesi bu tur yapılmadı.
