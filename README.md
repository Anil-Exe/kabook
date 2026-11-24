# KaBOOK

**Üniversite yaşamı için mobil sosyal ağ**

| Alan | Ayrıntı |
| --- | --- |
| Proje türü | Mobil uygulama / sosyal ağ |
| Teknolojiler | Flutter · Dart · Riverpod · Appwrite |
| Geliştirici | Anıl Polat |

---

Üniversite öğrencilerine yönelik Flutter tabanlı sosyal ağ projesi.

## Proje bağlamı

Üniversite eğitimi sırasında geliştirilen, mobil uygulama mimarisi ve bulut servis entegrasyonlarına odaklanan bir sosyal ağ projesidir. Bu depo, öğrenme sürecindeki tasarım ve uygulama çalışmalarını portföy kapsamında sunar.

### Servis entegrasyonları

Özgün API anahtarları ve kişisel bulut yapılandırmaları bu portföy sürümüne dahil değildir. Eski servis bağlantıları kullanım dışı bırakılmıştır. Entegrasyonları çalıştırmak için kendi Firebase/Appwrite projenizi ve ilgili API sağlayıcılarında kendi anahtarlarınızı oluşturup yerel yapılandırma üzerinden sağlamanız gerekir. Bu gereksinim, kişisel hesaplardan bağımsız ve yeniden kurulabilir bir örnek sunmak için bilinçli bir tercihtir.

## Kaynakta bulunan özellikler

- Kullanıcı kaydı, giriş ve profil ekranları
- Gönderi, medya, yorum ve beğeni akışları
- Birebir/grup mesajlaşması ve bildirim ekranları
- Etkinlik oluşturma ve katılım akışları
- Riverpod ile durum yönetimi, go_router ile yönlendirme
- Appwrite entegrasyonu ve Python/Node.js sunucu fonksiyonları

## Teknolojiler

Flutter, Dart, Riverpod, go_router, Appwrite, Firebase Messaging.
pubspec.yaml Dart ^3.9.2 gerektirir.

## Yerel kurulum

1. Uygun Flutter SDK'sını kurun ve `flutter pub get` çalıştırın.
2. Kendi Firebase projenizi oluşturun. Android için kendi `android/app/google-services.json` dosyanızı ve gerektiğinde diğer platform yapılandırmalarını yerel olarak ekleyin. Bu dosyalar Git kapsamı dışındadır.
3. Kendi Appwrite projenizi, veritabanınızı, koleksiyon izinlerinizi ve storage bucket'ınızı yapılandırın. Eski ortama erişim bilgileri bu kopyada bulunmaz.
4. Aşağıdaki değerleri kendi ortamınızdan sağlayın:

```sh
flutter run --dart-define=APPWRITE_ENDPOINT=https://cloud.appwrite.io/v1 --dart-define=APPWRITE_PROJECT_ID=YOUR_PROJECT --dart-define=APPWRITE_DATABASE_ID=YOUR_DATABASE --dart-define=APPWRITE_STORAGE_BUCKET_ID=YOUR_BUCKET
```

Sunucu fonksiyonlarının API anahtarları yalnızca sunucu ortam değişkenlerinde tutulmalıdır. Mobil uygulamaya yönetici anahtarı eklemeyin. `.gitignore` geçmişte commit edilmiş verileri temizlemez.

## Teknik durum

Bu sürümde servis yapılandırması dışarıdan sağlanır ve Appwrite sertifika doğrulaması açıktır.

<details>
<summary>Doğrulama kapsamı ve geliştirme notları</summary>

Flutter/Android/iOS derlemeleri ve canlı servis entegrasyonu bu ortamda çalıştırılmadı. Kaynaklardaki göreli import yolları kontrol edildi. Kendi sunucu ortamınızda koleksiyon/belge izinleri ve kullanıcılar arası erişim kontrolleri ayrıca doğrulanmalıdır.

</details>
