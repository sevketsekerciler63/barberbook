# Gerçek Android telefonda kabul oturumu

Bu belge **uygulanacak plandır**. İşaretlenmemiş kontroller geçmişte başarıyla yapılmış sayılmaz. Son kodda otomatik test ve emülatör kanıtları vardır; güncel fiziksel telefon/berber oturumu ayrıca kaydedilmelidir.

## Kurulum ve kayıt

1. [Başarılı Actions çalışmasından](https://github.com/sevketsekerciler63/barberbook/actions/workflows/ci.yml) `barberbook-demo-debug` ZIP'ini indirin. Kaynak commit'i aşağıdaki forma yazın; [checksum kontrolünü](ci.md#çıktı) yapın. Çoğu güncel Android telefon ARM64 kullanır; seçimi cihazın ABI bilgisine göre yapın.
2. **BarberBook Demo** (`com.barberbook.portfolio`) kurun. Demo, ticari uygulamanın paketinden ve veri alanından ayrıdır. Android “güncelleme yüklenemedi/imza uyumsuz” derse uygulamayı silerek aşmayın; aynı debug imzası başka makinede değişebilir. Önce test verisini ZIP olarak dışarı alın veya başka bir test cihazı kullanın. Demo yedeği bile otomatik geri yüklenmiş kabul edilmez.
3. Kurgusal müşteri ve kendi test telefon numaranızla çalışın. Fotoğraf için size ait bir test görseli kullanın. Randevuları seçili günün çalışma saatleri içine koyun; gerekirse test çalışma saatlerini yönetimden ayarlayın.
4. Telefonun bildirim, tam zamanlı alarm ve uygulamanın yönlendirdiği kilit ekranı/pil izinlerini kaydedin. İzin eksikse önce izin durumunu düzeltip alarmı yeniden deneyin. Ses ve ekranın öne gelmesini ayrı gözlemler olarak yazın.

ADB kullanılıyorsa belirli cihazı açıkça seçin; `adb -s <cihaz> shell getprop ro.product.cpu.abilist` ABI bilgisini verir. Mevcut uygulama güncellemesinde `adb -s <cihaz> install -r <APK>` kullanın. Başarısız kurulumda otomatik uninstall/veri temizleme yapmayın. Komutlar bu belgenin parçasıdır; bu tur telefonda çalıştırılmış değildir.

## Senaryolar

| No | Uygulanan işlem | Beklenen sonuç | Sonuç / kanıt |
| --- | --- | --- | --- |
| 1 | Müşteriye fotoğraf ve not ekleyip bir randevu kaydedin. İkinci randevuda müşteriyi arama listesinden seçin, telefonunu değiştirin. | Aynı müşteri, fotoğraf, not ve önceki randevu korunur; telefon günceldir. | Bekliyor |
| 2 | Tamamlanan hizmete 450 TL bedel + 20 TL bahşiş, nakit girin. Ardından randevuyu iptal edin ve aynı gün raporuna bakın. | Kasa 450 TL hizmet + ayrı 20 TL bahşiş gösterir; iptal para iadesi oluşturmaz. | Bekliyor |
| 3 | Ayrı bir 300 TL veresiye oluşturun, Açık veresiyeler'den 100 TL tahsil edin. | Aynı gün toplam hizmet tahsilatı 550 TL, bahşiş 20 TL, güncel veresiye 200 TL. Tek 100 TL tahsilat hareketi vardır. Önceden kayıt yoksa bu tam değerler geçerlidir. | Bekliyor |
| 4 | Uygulama açıkken WhatsApp hatırlatmasını etkinleştirin; yaklaşık 30 dk sonraki randevuda “Atla” seçin. Saati 5 dk ileri taşıyın. | İlk sürüm tekrar çıkmaz; yeni saat hatırlatma aralığındayken yeni hatırlatma çıkar. Kontrol 60 sn aralıkla çalışır, anlık görünme beklenmez. | Bekliyor |
| 5 | WhatsApp'ta aç seçeneğini deneyin; sonra mesajı göndermeden uygulamaya dönün. | Hazır metin ve alıcı doğrudur. Açma başarılıysa hatırlatma kapanır; bu mesajın gönderildiği/teslim edildiği anlamına gelmez. Açılamazsa beklemede kalır. | Bekliyor |
| 6 | Fotoğraflı ZIP yedeği oluşturup cihaz dışına paylaşın. Ardından ayrı bir test müşteri ekleyip ZIP'i geri yükleyin. | Yedekteki fotoğraf, not, randevu ve kasa geri gelir; sonradan eklenen test müşteri yoktur. Ana ekran yenilenir. Gelecekteki planlı alarmlar yeniden kurulur veya açık hata/yeniden deneme sunulur. | Bekliyor |
| 7 | Aynı dakikaya iki planlı randevu koyun (kapasiteyi 2 yapın). Alarm anını ön planda gözleyin. | İki alarm kimliği korunur; native saniye ayrımı nedeniyle aynı dakika içinde farklı saniyelerde tetiklenebilir. Alarmı kapatma çalışır. | Bekliyor |
| 8 | Yeni yakın alarm kurup uygulamayı Home ile arka plana alın ve ekranı kilitleyin. | Ses, bildirim, ekran uyanması ve uygulamanın kendiliğinden öne gelişi ayrı ayrı kaydedilir. Bildirim + ses, tek başına tam ekran kabulü değildir. | Bekliyor |
| 9 | En az 7 dk sonrası için yeni randevu kurun. Telefonu normal yeniden başlatın, kilidini bir kez açın; uygulamayı elle açmadan alarm anını bekleyin. | Randevu/veri korunur; yeniden kurulan alarmın sesi/bildirimi ve ekran davranışı kaydedilir. Reboot, force-stop ile aynı işlem değildir. | Bekliyor |
| 10 | Test müşterisini silin; gelecekteki planlı randevuyu kontrol edin. | Müşteri kartı silinir; planlı randevu ve alarm korunur. | Bekliyor |

Her alarm denemesini ayrı bir gelecek saatte yapın. Uygulamayı ayarlardan “Zorla durdur” işlemi farklı bir Android durumudur; bu tablo onun için garanti vermez. Arka plan/yeniden başlatma adımları gerçek cihazda uygulanmadan tamamlanmış işaretlenmez.

## Sonuç formu

```text
Tarih / uygulayan:
GitHub Actions çalışma bağlantısı:
Kaynak commit:
APK adı / SHA-256:
Paket: com.barberbook.portfolio
Cihaz marka-model / Android sürümü / ABI:
Bildirim izni:
Tam zamanlı alarm izni:
Kilit ekranı / pil ayarları:
Senaryo 1–10: geçti / kaldı / denenmedi + gözlenen sonuç
Alarm sesi:
Bildirim:
Ekran uyanması:
Otomatik tam ekran:
Yedekten geri gelen fotoğraf/not/kasa:
Yerel kanıt dosyaları:
Tekrar üretilebilen hata adımları:
```

Sonuç formunu proje notuna veya özel bir yerel dosyaya kaydedin. Public ekran görüntüleri yalnız kurgusal test verisi içerir. Berberin gerçek günlük kullanım geri bildirimi ayrıca tarih, gözlenen aksaklık ve beklenen davranışla kaydedilir.
