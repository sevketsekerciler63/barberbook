# İade, borç düzeltme ve geri alma

Yönetim → **Ödeme geçmişi / iade**; tahsilat raporu ve veresiye listesinin geçmiş simgesinden de açılır. Müşteri veya tam randevu numarasıyla aranır. Kaydın ayrıntısında ilk ödeme ve sonraki hareketler tarih, yöntem ve gerekçeyle görülür.

## İşlem kuralları

- **Para iadesi:** hizmet ve bahşiş ayrı girilir. İkisi kendi kalan tahsilatlarını aşamaz; yalnız bahşiş de iade edilebilir. Gerçekte iade edilen yöntem seçilir. Bu uygulama para transferi yapmaz, yapılan işlemi yerel deftere kaydeder. İade hizmet bedelini de azaltır; müşteriye gizlice yeniden veresiye açmaz.
- **Borçtan düş:** yalnız henüz tahsil edilmemiş veresiye azaltılır. Bu işlem kasaya giriş/çıkış veya bahşiş yaratmaz. Örnek: 300 ₺ veresiye − 100 ₺ tahsilat − 50 ₺ borçtan düşme = 150 ₺ kalan.
- **Geri alma:** yanlış iade/borç düşme satırındaki geri alma simgesi kullanılır. Özgün hareket silinmez; ona bağlı ters hareket eklenir. İadeyi geri alma, para geri alınmışsa kaydedilir ve net tahsilatı artırır. Borç düşmeyi geri alma, açık borcu artırır. Yalnız özgün hareketin tamamı aynı yöntem ve tutarla, bir kez geri alınabilir. Geri almanın kendisi tekrar geri alınmaz; gerekirse yeni özgün işlem kaydedilir.
- Her işlem için gerekçe ve onay gerekir. İlk ödeme formu mevcut finansal kaydı yeniden yazmaz. Finansal kaydı olan randevu silinemez; durum değişimi/iade/düzeltme kullanılmalıdır.
- Kayıt hata verirse **Aynı işlemi yeniden dene**, aynı işlem kimliğini kullanır. Commit olmuş ama yanıtı alınamamış işlem ikinci kez eklenmez. **Geçmişi yenile** ile güncel hareketler tekrar okunabilir.

Örnek: 450 ₺ hizmet + 20 ₺ bahşiş alınmışsa, 50 ₺ hizmet + 10 ₺ bahşiş iadesinden sonra net hizmet 400 ₺, net bahşiş 10 ₺ olur. İade önceki günün tahsilatını silmez; yapıldığı günün raporuna düşer. Yalnız iade yapılan bir günde net tutar negatif olabilir. Geri alma da kaydedildiği günde ters etki yaratır.

## Rapor ve saklama

Ana ekran, kasa raporu ve CSV aynı CashReport hesabını kullanır. Brüt hizmet tahsilatı, net hizmet/bahşiş iadeleri, net hizmet/bahşiş, toplam net para hareketi ve nakitsiz borç düzeltmesi ayrıdır. Yöntemler tablosu **net hizmet** tutarını gösterir; bahşiş ayrı kalır. Tarih aralığında geri alma varsa iade/borç düzeltmesi toplamı negatif olabilir. Güncel veresiye rapor aralığından bağımsızdır. Rapor verileri tek SQLite okuma transaction'ında tutarlı okunur.

Kaynak geliştirme sürümü **1.1.1+3**, SQLite şeması **v14**. Eski ödeme/tahsilat satırları korunarak `tipCents`, `operationId`, `reversesTransactionId` eklenir. İşlem kimliği ve özgün hareketin geri alınması için ayrı UNIQUE indeksler vardır; geri alma özgün satıra foreign key ile bağlıdır. Tutar sınırı ve tekrar kontrolü, yazmayla aynı SQLite transaction'ındadır. İlk ödeme satırı değiştirilmez; bütün düzeltmeler eklemelidir.

v1–v13 yedekleri hâlâ doğrulanıp yükseltilir. Yeni v14 ZIP'ler hareket alanlarını, işlem kimliklerini ve geri alma bağlarını korur. Eski v13 ve önceki uygulamalar yeni v14 yedeği açamaz; güncel sürüm gerekir. Üretim imzalı teslim bu geliştirme sırasında yenilenmedi.

## Doğrulama ve sınır

İade/borç düzeltme için 15 gerçek SQLite/dosya + 7 widget testi eklenmişti; tahsilat geri alma ve yeniden deneme genişletmesiyle tam paket **192 test** oldu. Hizmet/bahşiş sınırları, fazla tahsilat, gereksiz borç oluşmaması, idempotency ve DB yeniden açma, eşzamanlı iadeler/geri almalar, v12→v13 veri koruma, v13 yedek/restore ve bozuk şema, CSV'nin gün/net hesabı, zorunlu gerekçe, kayıt hatası/retry, disposal ve 320dp büyük yazı formu kapsanır.

Bu yerel kayıt akışı ilk ödeme yöntemini yeniden sınıflandırmaz veya keyfî yeni borç oluşturmaz. Çoklu cihaz eşitleme, banka/ödeme sağlayıcısından otomatik iade ve muhasebe/vergisel fiş üretimi eklenmedi. Bu tur fiziksel telefon denemesi yapılmadı; kullanıcı kodlama/analiz istedi.


v14, v13 alanlarını korur; tahsilat geri alma semantiğini eski okuyuculardan ayırır. [Veresiye tahsilatını geri alma, yöntem düzeltme ve güvenilir yeniden deneme](collection-corrections.md).
