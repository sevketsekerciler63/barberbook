# Otomatik kontrol ve demo APK

`.github/workflows/ci.yml`, push ve pull request üzerinde format, analyzer, tam Flutter testleri ve iki Android debug APK üretimini çalıştırır. Bir adım başarısızsa sonraki adıma geçilmez.

## 2026-11-03 bakım kararı

Önceki başarılı çalışmada Node 20 ve eski `setup-java` sürümü için uyarılar vardı. Üç action'ın resmî kararlı sürümü ve etiketinin işaret ettiği commit, GitHub API ve kaynak `action.yml` dosyalarından doğrulandı. Üçü de Node 24 kullanır. Workflow, hareketli ana sürüm etiketi yerine bu commit'lere bağlanır:

| Action | İncelenen sürüm | Workflow'daki commit |
| --- | --- | --- |
| [checkout](https://github.com/actions/checkout/releases/tag/v7.0.1) | v7.0.1 | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| [setup-java](https://github.com/actions/setup-java/releases/tag/v6.1.0) | v6.1.0 | `b843ebf9b913146b38da2eaa7aeddf76074ae1ad` |
| [upload-artifact](https://github.com/actions/upload-artifact/releases/tag/v7.0.2) | v7.0.2 | `cf430e030ddbb5b0abf93d22962f4752f3646cd9` |

Ubuntu ailesi `ubuntu-24.04` olarak seçilmiştir; `ubuntu-latest` geçişi bu işi farklı bir Ubuntu ana sürümüne kendiliğinden taşımaz. Bu bir imaj snapshot'ı değildir; [24.04 imajının](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md) yamaları zaman içinde güncellenir. Java 17 ve Flutter 3.38.5 kullanılır; Flutter checkout'unda `f6ff1529fd6d8af5f706051d9251ac9231c83407` kontrolü vardır. Dart bağımlılıkları `pubspec.lock` ile kaydedilmiştir. Byte düzeyinde aynı APK üretileceği iddia edilmez.

Token yetkisi `contents: read`; checkout kimlik bilgisini kalıcı bırakmaz. İş akışı üretim imzası, lisans anahtarı veya müşteri verisi almaz. Sürüm güncellerken resmî release notu, commit ve Node/runner uyumunu yeniden doğrulayın, ardından tam workflow'u geçirin.

## Çıktı

Başarılı çalışmanın **Artifacts → barberbook-demo-debug** ZIP'i 14 gün tutulur:

- `app-arm64-v8a-debug.apk`: ARM64 Android cihazı.
- `app-x86_64-debug.apk`: x86_64 Android emülatörü/cihazı.
- `SHA256SUMS.txt`: o çalışmada üretilen iki APK'nın SHA-256 değerleri.

Checksum adımı iki dosyayı adlarıyla zorunlu tutar; eksik dosya varsa job başarısız olur. Aynı değerler ve kaynak commit Actions Summary'de gösterilir. `archive: true` çok dosyalı ZIP davranışını açıkça seçer.

ZIP'i açtıktan sonra Linux'ta `sha256sum -c SHA256SUMS.txt`, PowerShell'de `Get-FileHash .\app-arm64-v8a-debug.apk -Algorithm SHA256` ile ilgili satırı karşılaştırın. Bu kontrol indirilen dosyanın çalışmadaki APK ile eşleşmesini denetler; APK debug imzalıdır ve üretim sürümü değildir.

Telefon kabulü ve sonuç formu: [device-acceptance.md](device-acceptance.md). CI sonucu telefon/işletme kabulünü otomatik tamamlamaz.
