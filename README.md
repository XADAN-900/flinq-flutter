# FlinQ — Flutter

FlinQ'nun baştan yazılmış, yerel (native) Flutter sürümü. Eski WebView uygulamasıyla **aynı Firebase
projesini** (`flinq-8e74c`) kullanır: hesaplar (Firebase Auth), gönderiler, yorumlar, takipler ve bildirimler
iki sürüm arasında ortaktır.

## Özellikler

**Akış**
- "Sana özel" ve "Takip ettiklerin" akışları, aşağı çekip yenileme, sonsuz kaydırma
- Fotoğraf, video ve renkli metin gönderileri
- Çift dokunuşla beğeni (kalp animasyonu), yorum, paylaş, **kaydet**
- Akıştaki videolar ekrana gelince otomatik ve sessiz oynar, aynı anda tek video çalar

**Hikayeler** (yeni)
- 24 saatlik fotoğraf hikayeleri, ilerleme çubukları, dokunarak ileri/geri, basılı tutarak durdurma
- İzlenmemiş hikayeler için renkli halka, görüntülenme sayısı

**Reels** (yeni)
- Tam ekran, dikey kaydırmalı video akışı; beğeni, yorum, paylaş, kaydet, takip

**Keşfet**
- Etkileşime ve tazeliğe göre sıralanan gönderi ızgarası
- Kişi ve **#etiket** arama, etiket sayfaları

**Yorumlar**
- Yanıtlar (açılır/kapanır), **yorum beğenme**, @etiket önerileri, yorum silme

**Profil**
- Gönderiler / videolar / kaydedilenler sekmeleri, takipçi ve takip listeleri (aramalı)
- "Seni takip ediyor" bilgisi, mavi tik (1000 takipçide otomatik), 100 takipçi kutlaması
- Profil fotoğrafı, biyografi, kullanıcı adı değiştirme (15 gün kuralı)

**Bildirimler**
- Beğeni, yorum, yanıt, takip, etiket ve kutlama bildirimleri; filtreler, gruplama (Bugün / Bu hafta…)
- "Geri takip et" düğmesi, kaydırarak silme, tümünü okundu yap
- Uygulama arka plandayken telefon bildirimi, FlinQ bildirim sesi, kilit ekranı gizliliği
- FCM ile uygulama tamamen kapalıyken de bildirim (aşağıdaki kurulum)

**Hesap**
- E-posta **veya kullanıcı adıyla** giriş, kayıt, şifre sıfırlama e-postası
- Açık / koyu / sistem teması

## Derleme

GitHub Actions her `main` push'unda APK'yı derler ve **Releases**'a yükler:

`https://github.com/<kullanıcı>/flinq-flutter/releases/latest/download/FlinQ.apk`

Yerelde:

```bash
flutter create --platforms=android --org com.xadan --project-name flinq .
python3 ci/patch_android.py
flutter pub get
flutter build apk --release
```

## İsteğe bağlı ayarlar (GitHub → Settings → Secrets → Actions)

| Secret | Ne işe yarar |
|---|---|
| `FIREBASE_ANDROID_APP_ID` | Firebase konsolunda `com.xadan.flinq` Android uygulamasının kimliği (`1:40261522799:android:...`). Verilirse FCM push açılır. Sunucu tarafı eski repodaki `functions/` ile aynıdır. |
| `FQ_KEYSTORE_B64`, `FQ_KEYSTORE_PASSWORD` (`FQ_KEY_ALIAS`, `FQ_KEY_PASSWORD`) | Eski FlinQ repo'sundaki imza anahtarının aynısı. Eklenirse yeni sürüm eskisinin **üzerine** kurulur. Eklenmezse eski uygulamayı kaldırıp yenisini kurman gerekir (paket adı aynı: `com.xadan.flinq`). |

## Veritabanı kuralları

Yeni özellikler şu yollara yazar; kuralların bunlara izin verdiğinden emin ol:

```json
"stories":  { ".read": "auth != null", "$uid": { ".write": "auth != null" } },
"users":    { "$uid": { "saved": { ".write": "auth != null && auth.uid === $uid" } } },
"fcmTokens": { "$uid": { ".write": "auth != null && auth.uid === $uid" } }
```

Yorum beğenileri `posts/{id}/comments/{cid}/likedBy` altına yazılır (gönderi beğenisiyle aynı izin).
