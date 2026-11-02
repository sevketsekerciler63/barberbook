# Hatalı veresiye tahsilatını geri alma

Geliştirme sürümü **1.1.1+3**, SQLite **v14**. Bu akış, yanlış girilmiş veresiye tahsilatını geçmişi silmeden düzeltir. Müşteriye normal para iadesi farklı bir işlemdir.

## Kullanım

1. **Yönetim → Ödeme geçmişi / iade** içinde ilgili randevuyu açın.
2. Özgün tahsilat satırındaki **Tahsilatı geri al** simgesini seçin. Tutar/yöntem özgün kayıttan gelir; gerekçe zorunludur. Geri alma, aynı tutarı yeniden açık borç yapar ve o günün net tahsilatını azaltır.
3. Yanlış yöntem seçilmişse, **Açık veresiyeler** ekranından doğru yöntemle tahsilatı yeniden girin. Örnek: 300 ₺ borçtan yanlış Nakit 100 ₺ tahsil edilmişse, geri alma borcu 300 ₺ yapar. Ardından Kart 100 ₺ tahsilat girilirse kalan borç 200 ₺; yöntemler toplamı net Nakit 0 ₺, Kart 100 ₺ olur.

Özgün tahsilat ve geri alma satırları korunur. Geri alma tutarı/yöntemi değiştirilemez; aynı tahsilat yalnız bir kez geri alınır. Geri almanın kendisi yeniden terslenmez. Geri alınacak tutar, randevunun iadelerden sonra kalan toplam hizmet tahsilatını aşamaz. Bakiye yetmiyorsa işlem engellenir; ilgili iadeleri ve geçmişi kontrol edin.

## İade ile fark

- Normal **para iadesi**, net nakdi ve hizmet bedelini azaltır; borcu gizlice yeniden açmaz.
- **Tahsilat geri alma**, hatalı tahsilat kaydını tersler; hizmet bedeli aynı kalır ve borç yeniden açılır.
- **Borçtan düşme**, yalnız henüz tahsil edilmemiş borcu azaltır; nakit hareketi yaratmaz.

Uygulama banka işlemi yapmaz; yerel hareket kaydı tutar. İlk peşin ödeme yöntemini yeniden sınıflandırma bu akışa eklenmedi; burada düzeltilebilen yöntem veresiye tahsilatının yöntemidir.

## Güvenilir yeniden deneme ve rapor

Yeni tahsilat formu, işlem kimliğini bir kez üretir; kayıt tarihi kullanıcı Tahsilatı kaydet'e bastığında alınır. Veritabanı, aynı kimlikle aynı tutar/yöntem/not/randevu için gelen tekrarı ilk kayıt kimliğiyle cevaplar. Başka içerikle aynı kimlik reddedilir. Eski servis çağrılarında kimlik boş olabilir; yeni kullanıcı akışı her zaman kimlik gönderir.

Kayıt hatasında istek ekranda saklanır. **Aynı tahsilatı yeniden dene**, aynı işlem kimliği ve tarihini kullanır; commit olup yanıtı kaybolmuş tahsilatı iki kez eklemez. **Listeyi yenile**, önce mevcut bakiyeyi yeniden okur. Sonuç belirsizken yeni tahsilat formu başlatılamaz. Kaydetme sürerken ilerleme göstergesi vardır; geç yanıt ekran kapandıktan sonra state'i güncellemez. İptal edilen form kilidi bırakır.

Rapor/CSV brüt tahsilat, tahsilat geri alma ve normal iadeyi ayrı gösterir. **Net hizmet = tahsilat − hizmet iadesi − tahsilat geri alma**. Geri alma eski günün kaydını silmez; yapıldığı günün net tutarını azaltır. Yalnız geri alma olan gün negatif net olabilir. Ana ekran aynı hesabı kullanır.

## Veri uyumu ve testler

v14, v13'ün tablo yerleşimini/alanlarını korur. Sürüm kapısı gereklidir: v13 okuyucusu, ters tahsilatı yeni gelir olarak sayardı. Yeni v14 yedeği eski v13 uygulamada açılmaz; eski v1–v13 yedekleri yeni kodda yükseltilir. Yeni üretim imzalı yayın bu geliştirmede oluşturulmadı.

Önceki 182 teste 6 gerçek SQLite/dosya ve 4 widget kontrolü eklendi: toplam **192 otomatik test**. Idempotent tam/kısmi tahsilat, DB reopen, yöntem değiştirme için geri alma+yeniden tahsilat, günlük negatif net/CSV, iade edilmiş paraya ikinci düşüm koruması, eşzamanlı ters/tahsilat sınırları, v13→v14/backup restore, kayıp commit yanıtı/retry, çift işlem/disposal, iptal/yenileme ve320dp/büyük yazı kapsanır. Büyük yazı testinde bulunan liste bakiyesi ve ödeme yöntemi taşmaları giderildi.
