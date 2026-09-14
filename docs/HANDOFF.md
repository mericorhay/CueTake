# CueTake: devir notu

14 Eylül 2026'da Claude (Anthropic, Claude Code masaüstü uygulaması) tarafından, işi devralacak yapay zekâ asistanı için yazıldı. Bu belgeyi baştan sona oku; sonra `README.md` ve `docs/ROADMAP.md` dosyalarına bak.

> **Merhaba, ben Claude.** Bu projede Meriç'le (GitHub: `mericorhay`, e-posta `mericorhayy@gmail.com`) günlerce birlikte çalıştım:
> - Kodu yazdım.
> - CI'ı tetikledim, TestFlight build'lerini gönderdim.
> - Cloudflare Worker'ı deploy ettim.
>
> Meriç Türkçe konuşur, kısa ve hızlı yazar ("kanka", yazım hataları olur, niyeti anlamaya çalış). Ürün sahibi odur; kod yazmaz. Uygulamayı iPhone'da TestFlight'tan dener, sorunları ekran görüntüsü, ekran kaydı ya da crash raporuyla bildirir.

---

## 1. Ürün: ne yapıyoruz?

**CueTake**, kameraya konuşarak kısa video (Reels, TikTok, Shorts) çeken tek kişilik içerik üreticiler için bir iOS uygulamasıdır. Akış şöyle:

1. **Başla:** Fikirden, hazır metinden, workflow'dan ya da doğrudan kayıtla başlanır. AI senaryo yazar ve senaryoyu segmentlere böler (hook, intro, point, example, CTA).
2. **Çek:** Stüdyoda teleprompter, konuşmayı cihaz üzerinde dinleyerek kişiyi takip eder. Kayıt tek dosyadır; segmentler bu dosyanın içindeki zaman aralıklarıdır.
3. **Düzenle:** Editörde gerçek bir zaman çizelgesi vardır.
   - Kırpma, bölme, hız, ters oynatma, dondurma.
   - Metin ve görsel katmanları, müzik ve ses katmanları, ses temizleme.
   - Metin üzerinden kesme (kelimeyi silince görüntü de gider).
   - Arka plan değiştirme.
   - Altyazılar, "AI kurgu" ve workflow'lar.
4. **Retake:** Sadece kötü çıkan segment yeniden çekilir.
5. **Dışa aktar:** Altyazılar ve katmanlar videoya gömülür, Fotoğraflar'a kaydedilir.

Uygulamanın en güçlü farkı **AI stüdyo kontrolüdür**. Kullanıcı "dolgu kelimeleri kes, başlık ekle, altyazıları büyüt" yazar. Model tüm editörü kompakt bir JSON belgesi olarak okur ve bir düzenleme planı döndürür. Uygulama planı editörde adım adım, animasyonlu uygular. Her değişiklik "AI değişiklikleri" bölümünden tek tek geri alınabilir.

- **Bundle id:** `com.orhay.cuetake`
- **Apple Team:** `XYB3NLV654` (MicFox ve Galapagos ile aynı takım)
- **Sürüm:** `0.4.0`, TestFlight build 40
- **Platform:** yalnızca iPhone, **iOS 26+**
- **Dil ve görünüm:** İngilizce ve Türkçe; her zaman koyu tema.

---

## 2. Makine ve ortam (önemli)

| | |
|---|---|
| Bilgisayar | **Windows 11 Pro**, kullanıcı klasörü `C:\Users\bob` |
| Repo | `C:\Users\bob\code\CueTake` |
| GitHub | `github.com/mericorhay/CueTake`, dal `main`. Local remote hâlâ `Galapagos-GCS/CueTake` (GitHub yönlendiriyor). `gh` komutlarında `-R mericorhay/CueTake` kullan. |
| Diğer repo | `C:\Users\bob\code\micfox`: MicFox, ayrı bir uygulama (dal `master`). CueTake ile ilgisi yok, aynı Apple takımı. |
| Kabuklar | PowerShell 5.1 ve Git Bash |
| Kurulu araçlar | `git`, `gh` (giriş yapılmış), `node`/`npx` (PowerShell'de `npx.cmd`), `python` |
| Mac / Xcode | **Yok.** Swift bu makinede derlenemez ve test edilemez. |

**Derleyici CI'dır.** Her anlamlı değişiklikten sonra push et, CI'ı tetikle ve sonucuna bak. Derlenmeyen kod Meriç'e gitmemeli.

**Düzenleme ipuçları:**
- Git Bash heredoc içinde tırnaklı ya da çok satırlı Swift metni sık bozuluyor.
- Çok satırlı değişiklikleri küçük Python betikleriyle (dosya oku, `assert eski in metin`, değiştir, yaz) ya da doğrudan dosya düzenleme aracıyla yap.
- Dosyaları UTF-8 ve LF satır sonuyla yaz.

**Downloads klasörü:** `C:\Users\bob\Downloads` içinde `AuthKey_*.p8` (App Store Connect API anahtarı) var. **Asla açma, okuma, kopyalama.** Meriç crash raporlarını da bazen buraya zip olarak koyar; onları açabilirsin.

---

## 3. Güvenlik kuralları (pazarlık konusu değil)

- **Parola, API anahtarı, token ya da `.p12`/`.p8` içeriğini hiçbir yere yazma ve yapıştırma.** Meriç bir anahtarı sohbete yapıştırırsa kullanma. Anahtarı iptal edip yenisini kendisinin girmesini söyle.
  - Worker anahtarları: `npx wrangler secret put GROQ_API_KEY` ve `APP_TOKEN`
  - GitHub secret'ları: GitHub arayüzünden ya da `scripts/set-secrets.sh` ile.
- Uygulamaya asla bir sağlayıcı (Groq, Anthropic, OpenAI) anahtarı gömme. Bütün AI trafiği bizim Worker'dan geçer.
- Commit ve push'u Meriç istediğinde ya da iş akışı gerektirdiğinde yap. Bu projede her iş turunun sonunda push edip TestFlight göndermek alışkanlık oldu ve Meriç bundan memnun.

---

## 4. CI ve TestFlight

İki workflow var, ikisi de **yalnızca elle** tetiklenir (macOS runner pahalı):

```bash
# Derleme ve testler
gh workflow run ci.yml -R mericorhay/CueTake --ref main

# İmzalı build'i TestFlight'a gönder (build numarası = run numarası)
gh workflow run testflight.yml -R mericorhay/CueTake --ref main

# Son run'ı bul; headSha doğru commit mi, kontrol et
gh run list -R mericorhay/CueTake -w ci.yml -L 1 --json databaseId,headSha,status,conclusion

# Bitince sonucu gör
gh run view <id> -R mericorhay/CueTake --log | grep -E "error:|Test run with|✘"
```

- **`ci.yml`:** macOS-26 runner üzerinde iki adım var.
  - `xcodebuild build`: uygulama şeması; bütün modülleri ve app target'ı derler.
  - `xcodebuild test`: `Packages/CueTakeKit` paketinde Swift Testing ile çalışır.
  - Toplam ~10 dakika. Son durum: 80 test (Domain 50, EditorFeature 21, WorkflowEngine 7, MediaEngine 2), hepsi yeşil.
- **Push'tan hemen sonra tetikleme yarışı:** CI bazen önceki commit'i alır. Birkaç saniye bekle, `headSha` değerini kontrol et.
- **`testflight.yml`:** fastlane `beta` lane'i çalışır (`fastlane/Fastfile`).
  - İmzalama secret'ları: `APPLE_TEAM_ID`, `IOS_DISTRIBUTION_CERT_P12`, `IOS_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE`, `APP_STORE_CONNECT_API_KEY`, `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`.
  - Uygulamanın Worker adresi: `CUETAKE_ASSISTANT_URL` ve `CUETAKE_ASSISTANT_TOKEN`. CI bunları build sırasında `CueTake/Resources/AssistantEndpoint.json` dosyasına yazar; bu dosya gitignore'da.
  - App Store işlemesini beklediği için ~25–40 dakika sürer.
  - Apple'ın günlük yükleme limiti var (hata 90382); aşılırsa 24 saat bekle.
- **Sürüm:** `Config/CueTake.xcconfig` içindeki `MARKETING_VERSION`. Build numarasını CI verir.
- **Meriç'in tercihi:** "Push ettikten sonra izlemek zorunda değilsin." Tetikle ve haber ver. Ama derlenip derlenmediğini bilmen gerekiyorsa (Windows'ta başka yolu yok) CI sonucunu kontrol et.

---

## 5. Sunucu: Cloudflare Worker (AI proxy)

- **Kod:** `backend/assistant/worker.js`
- **Ayarlar:** `wrangler.toml`. Rate limit: adres başına dakikada 20 istek.
- **Adres:** `https://cuetake-assistant.mericorhayy.workers.dev`
- **Deploy:** `backend/assistant` klasöründe `npx.cmd wrangler deploy`. Wrangler bu makinede giriş yapılmış durumda.
- **Secret'lar:** `GROQ_API_KEY` ve `APP_TOKEN` Meriç tarafından ayarlandı. Değerlerini bilmiyorum, sen de bilmeyeceksin.
- **Sağlayıcı:** Groq, ücretsiz katman.
  - Model başına dakikada 8.000 token (prompt, belge ve cevap toplamı), günde 1.000 istek.
  - Sıra: `openai/gpt-oss-120b`, olmazsa `qwen/qwen3.8-27b`, o da olmazsa `openai/gpt-oss-20b`.
  - `max_completion_tokens` büyük olursa Groq reddeder ve uygulama 502 görür.
- **Kimlik doğrulama:** her POST isteğinde `x-cuetake-app: <APP_TOKEN>` başlığı olmalı.

Uç noktalar:

| Yol | Ne yapar |
|---|---|
| `GET /health` | Sağlayıcı anahtarı çalışıyor mu. `?models=1` modelleri listeler, `?limits=1` dakikalık limitleri gösterir. Token gerekmez. |
| `POST /` | Asistan sohbeti (workflow önerileri kart olarak döner) |
| `POST /edit` | **AI kurgu**: `{instruction, locale, document}` alır, `{plan}` döndürür (JSON plan metni). Prompt: `EDIT_PROMPT` |
| `POST /workflow` | Cümleden workflow üretir |
| `POST /script` ve `POST /rewrite` | Apple Intelligence olmayan telefonlar için senaryo yazma ve yeniden yazma |
| `POST /transcribe` | Ham m4a gövdesi alır (`?language=tr&prompt=...`). Groq Whisper'a (`whisper-large-v3-turbo`, olmazsa `whisper-large-v3`) gönderir. `{words:[[text,start,end]], segments:[[start,end,avg_logprob,no_speech_prob,compression_ratio]]}` döndürür |
| `POST /speech` | İki motorun anlaşamadığı pasajlar için hakem: `{choices}` (a = telefon, b = sunucu) |

**Kural:** Prompt'lar sunucuda yaşar. Prompt değişikliği için uygulama güncellemesi gerekmez, sadece `wrangler deploy` yeter.

---

## 6. Kod mimarisi ve dosya yapısı

```
C:\Users\bob\code\CueTake\
├── CueTake.xcodeproj                  App target (klasörler senkronize)
├── Config\CueTake.xcconfig            Bundle id, takım, sürüm, Swift ayarları
├── CueTake\                           App target: yönlendirme ve ekranlar arası orkestrasyon
│   ├── CueTakeApp.swift
│   ├── RootView.swift                 Screen enum'una göre hangi ekran; tab bar
│   ├── AppModel.swift                 Uygulama durumu, proje yükleme/kaydetme, stüdyo kaydını benimseme,
│   │                                  dinleme (transcribeNewTakes), editör kopyasını geri alma
│   ├── AppModel+Create.swift          Fikir / metin / kayıt ile başlama akışları
│   ├── AppModel+Listening.swift       İki motorlu dinleme orkestrasyonu (listen(to:))
│   ├── AppModel+Storage.swift         Çoklu proje silme, depolama temizliği
│   ├── AppModel+Workflows.swift       Workflow çalıştırma (tek geri alma adımı)
│   ├── AppModel+Assistant.swift       Asistan bağlantısı
│   ├── AppDependencies.swift          Somut implementasyonları bilen tek yer
│   └── Resources\                     Assets, InfoPlist.xcstrings, Localizable.xcstrings
├── Packages\CueTakeKit\               Tek local Swift paketi, çok modül
│   ├── Package.swift
│   ├── Sources\
│   │   ├── Domain\                    Saf modeller ve mantık (yalnızca Foundation)
│   │   ├── CaptureEngine\             Kamera, mikrofon (AVCaptureSession)
│   │   ├── SpeechEngine\              Apple konuşma tanıma (dosya + canlı)
│   │   ├── MediaEngine\               Composition, export, arka plan kaldırma, ses işlemleri
│   │   ├── AIServices\                AssistantClient (Worker istemcisi), cihaz üstü modeller
│   │   ├── Persistence\               Proje dosyaları, ayarlar, workflow deposu
│   │   ├── WorkflowEngine\            Adım adım workflow çalıştırıcı
│   │   ├── DesignSystem\              Token'lar, fontlar, animasyonlar, bileşenler
│   │   ├── Teleprompter\
│   │   ├── OnboardingFeature\  LibraryFeature\  ScriptFeature\  StudioFeature\
│   │   ├── EditorFeature\             En büyük modül (aşağıda)
│   │   ├── WorkflowsFeature\  SettingsFeature\  AssistantFeature\
│   └── Tests\  DomainTests\  EditorFeatureTests\  MediaEngineTests\  WorkflowEngineTests\
├── backend\assistant\                 Cloudflare Worker
├── fastlane\  Fastfile, Appfile
├── scripts\   set-secrets.sh (Meriç'in secret yükleme betiği), add_strings.py (çeviri ekleme yardımcısı)
├── docs\      ROADMAP.md (kısmen eski), PRIVACY.md (taslak), HANDOFF.md (bu belge)
└── .github\workflows\  ci.yml, testflight.yml
```

### Katman kuralları

- **Domain** hiçbir modüle bağımlı değildir. SwiftUI veya AVFoundation import etmez.
- **Engine modülleri** (Capture, Speech, Media, AIServices, Persistence, WorkflowEngine) yalnızca Domain'e bağlıdır.
- **Feature modülleri** birbirini import etmez; aralarındaki geçişi app target yapar. Feature'lar dışarıya closure'lar açar (`onExport`, `onAIEdit` gibi), app target bunları bağlar.

### Swift ayarları (derleme hatalarının çoğu buradan çıkar)

- **Sürüm ve izolasyon:** Paket Swift 6.2 araç sürümüyle, Swift 6 dil modunda.
  - UI modülleri ve app target varsayılan olarak `MainActor` üzerinde çalışır.
  - Engine ve Domain modülleri `nonisolated` kalır.
- **`NonisolatedNonsendingByDefault` açık:** `nonisolated async` fonksiyonlar çağıranın actor'ünde çalışır. Ağır işi ana thread'den almak için fonksiyonu **`@concurrent`** yap (örnekler: `BackgroundRemover.render`, `VoiceActivity.measure`, `SpeechAudio.compact`).
- **`MemberImportVisibility` açık:** Bir dosyada başka bir modülün türünü ya da uzantısını kullanıyorsan o modülü o dosyada import et.
- **Framework kuyruklarında çağrılan closure'lar:** PhotoKit, KVO, AVFoundation callback'leri gibi closure'lar `@Sendable` ya da `nonisolated` olmalı. Aksi halde çalışma anında çöker; export'taki eski crash buydu.
- **AVPlayer seek:** `async` fonksiyon içinde completion handler'lı sürümü kullan: `player.seek(to:…) { _ in }`.
- **Projede üçüncü parti bağımlılık yoktur.** Böyle kalsın.

### Kod stili

- **Yorumlar:** Neden öyle olduğunu ve eskiden neyin bozuk olduğunu anlatan, düzyazı `///` belge yorumları. Mevcut dosyaları taklit et; yorum yoğunluğu yüksek.
- **İsimler:** Uzun ve açıklayıcı. İngilizce kod, kısaltma yok.
- **Metinler:** Kullanıcıya görünen her metin String Catalog'a gider (`Resources/Localizable.xcstrings`, modül başına bir tane). Hem İngilizce hem Türkçe girilir.
  - SwiftUI: `Text("editor.key", bundle: .module)`
  - Kod: `String(localized: "editor.key \(value)", bundle: .module)`. Anahtarda `%@` ve `%lld`, değerde `%1$@` kullanılır.
  - Eklemek için `scripts/add_strings.py` içindeki `write(path, {key: (en, tr)})` fonksiyonunu kullan.
- **Değişiklik noktası:** Editörde her değişiklik `EditorModel` üzerindeki `record(...)` fonksiyonundan geçer. Geri alma tek bir noktadan snapshot'la çalışır.
- **Commit mesajları:** Conventional commit başlığı (`feat(editor): …`, `fix(ai): …`), altında ne değişti ve neden. Sonuna attribution satırı.

---

## 7. Veri modeli (Domain)

- **`Project`** (`Domain/Project/Project.swift`) sürümlü JSON olarak saklanır, medya dosyaları yanında durur. Alanları:
  - `segments`, `recordings`, `captionStyle`
  - `audio: [AudioClip]`, `overlays: [Overlay]`, `effects: [TimelineEffect]`
  - `voiceEffects`, `captionWindow`
  - Decoder elle yazılmıştır: yeni alan eklersen `decodeIfPresent` ile varsayılan ver, yoksa eski projeler açılmaz.
- **`Segment`**: Tek bir bölüm. İçinde:
  - `takes` ve `selectedTakeID`
  - `captions`: take'e göre saniye.
  - `playback: ClipPlayback`: hız, ters, dondurma.
  - `script`
  - Zaman çizelgesindeki konum saklanmaz, sıradan türetilir (`barWeight`, `start(at:)`).
- **`Take`**: Bir `Recording` dosyası içindeki `sourceRange`, artı `transcript` (take'e göre kelime zamanları). Kesme ve bölme dosyaya dokunmaz, sadece aralık değişir.
- **`Recording.speech: TranscriptVersions?`**: İki motorun duyduğu, pasaj pasaj (`Domain/Speech/TranscriptVersions.swift`).
- **`TimelineEffect`** (`Domain/Effects/TimelineEffect.swift`): Başlangıç, süre ve `.background(BackgroundSettings)`.
  - `BackgroundSettings` alanları: stil (blur, dim, studio, black, white, green, color), strength, feather, color, fineEdges.
  - `Project.stretches(ofSegmentAt:)` bir klibi efekt kenarlarından parçalara ayırır.
  - Eski `Segment.background` alanı açılışta efekte dönüştürülür.
- **AI tarafı** (`Domain/Assistant/`):
  - `EditDocument`: Modelin okuduğu kompakt belge (`c1`, `k1`, `o1`, `a1`, `e1` kısa id'leri, sayılar yüzde bire yuvarlanır).
  - `EditPlan`: İşlem sözlüğü; model gevşek JSON yazsa da hoşgörülü çözülür.
  - `AITarget`: Geri alma birimi; `Project.restoring(_:from:)` kullanır.

---

## 8. EditorFeature: önemli dosyalar

| Dosya | Ne |
|---|---|
| `EditorModel.swift` | Editör durumu. Oynatıcı tek bir `AVPlayer`; her yeniden kurulumda `replaceCurrentItem` ile item değişir (yeni player siyah ekran yapıyordu). `compositionSignature` değişince önizleme yeniden kurulur. Item `failed` olursa kendini toparlar. |
| `EditorScreen.swift` | Editör ekranı: önizleme (altyazılar video karesine sabit), transport, ToolDock, zaman çizelgesi, alttaki paneller. |
| `EditorTimeline.swift` | Ölçekli zaman çizelgesi. Oynatma çizgisi ortada sabit, yakınlaştırma var. Satırlar: `OverlayLane`, klipler, `EffectLane`, `CaptionLane`, `AudioLane`. |
| `EffectLane.swift` | Hangi araç nereye uygulandı: arka plan çubukları (sürükle, uçlarından uzat) ve hız/ters/dondurma çubukları. |
| `EffectInspector.swift`, `EditorEffects.swift` | Efekt paneli ve model API'si. Aralığa hız uygulama: klibi iki uçtan bölüp ortadaki parçaya uygular, tek geri alma adımıdır. |
| `ClipRangeBar.swift` | İki tutamaçlı aralık seçici. |
| `ToolDock.swift` | Önizlemenin altındaki araç sırası. Paneller çipten açılır: kırp, hız, arka plan, AI. |
| `EditorBackgrounds.swift` | Arka plan render işi: arka planda, ilerlemeli, düşük öncelikli. |
| `CaptionOverlay.swift`, `CaptionLane.swift`, `CaptionQuickEdit.swift`, `SpeechVersions.swift` | Önizlemedeki altyazı, zaman çizelgesindeki altyazı satırı, hızlı düzenleme paneli, iki motor seçimi. |
| `AIDirector.swift` | AI kurgu: planı güvenli sırayla adımlara çevirir, canlı uygular, her değişikliğin önce/sonra snapshot'ını alır. AI **asla klip silmez**. |
| `AIDirectorHUD.swift`, `AIGlow.swift`, `AIChangesSheet.swift`, `AIEditPanel.swift` | AI arayüzü: üst kart, değişen şeyin yanması, değişiklik listesi ve geri alma, istek alanı. |
| `EditorHistory.swift` | Geri al / yinele (snapshot). `beginBatch` ve `endBatch` ile tek adım. |
| `TranscriptEditing.swift` | Metinden kesme. |

**MediaEngine:**

| Dosya | Ne |
|---|---|
| `VideoComposer.swift` | Timeline'dan AVComposition üretir. Klibi efekt parçalarına böler; ters kopya ve arka planlı kopyayı kullanır; sesi orijinal dosyadan alır. |
| `BackgroundRemover.swift` | Vision person segmentation. Bütün take için bir kez render edilip önbelleğe alınır (`<take>-bg-<token>.mov`). |
| `VoiceActivity.swift` | Dosyanın ses enerjisini ölçer; sessiz yere düşen kelimeleri atar. |
| `SpeechAudio.swift` | Sunucuya gidecek küçük mono m4a (16 kHz, 32 kbps). |
| `PlaybackAudio.swift` | Ses oturumu `.playback` (sessiz modda da ses çalar). |
| `MediaJanitor.swift` | Kullanılmayan önbellekleri siler. |

**SpeechEngine:** `SystemSpeechTranscriber.swift` önce `SpeechTranscriber`'ı, dil desteklenmiyorsa `DictationTranscriber`'ı, o da olmazsa `SFSpeechRecognizer`'ı dener. Türkçe pratikte son yolu kullanır; bu yol artık uzun dosyada bütün final sonuçları topluyor.

---

## 9. UI dili (tasarım sistemi)

`Packages/CueTakeKit/Sources/DesignSystem/`, `Theme/Tokens.swift`, `Typography.swift`, `Motion.swift`, `Components/`.

- **Her zaman koyu.**
  - Zemin: `DS.Palette.screen` `#0B0B0D`, `page` `#08080A`.
  - Yüzeyler: `surface` `#131317` ve `surfaceRaised`.
  - Metin: `ink` `#F5F5F7`, opaklıkla `DS.Palette.ink(0.5)`.
  - Çizgiler: `hairline(0.08)`.
- **Vurgu renkleri:**
  - `accent` mercan `#FF5A4F` (kayıt, yıkıcı işlemler)
  - `accentWarm` `#FF7043`
  - `lime` `#E8FF4F` (seçili, aktif, onay)
  - Segment renkleri: hook = accent, intro = accentWarm, point = lime, CTA = ink.
- **AI rengi:** tatlı mavi (`AIPalette.blue` ≈ rgb 0.36/0.66/1.0, `sky`). Meriç moru istemedi; AI dışındaki hiçbir yerde mavi kullanma. Efekt satırındaki arka plan çubukları mint yeşili (`EffectLane.tint`); hız çubukları `accentWarm`.
- **Fontlar** (gömülü, OFL lisanslı):
  - Başlık ve etiket: `Archivo` (Bold, ExtraBold).
  - Gövde: `Instrument Sans`.
  - Sayı ve zaman kodu: `JetBrains Mono`.
  - Kullanım: `.dsFont(.archivo | .sans | .mono, .semibold, 14)`.
  - Etiketler için `DSKicker` (büyük harf, geniş aralık).
- **Hareket:**
  - Seçim için `DS.Motion.snap`, panel ve yerleşim için `DS.Motion.settle`, açılış için `DS.Motion.bloom`.
  - `accessibilityReduceMotion` her zaman dikkate alınır.
  - SF Symbols `symbolEffect` bol kullanılır.
  - Dokunma hissi `sensoryFeedback` ile verilir.
- **Yüzeyler:** Liquid Glass tarzı cam (`.dsGlass(tint:in:border:)`). Alttan açılan paneller üst köşeleri yuvarlatılmış, önizlemenin üstüne biner.
- **Basma stili:** `.buttonStyle(.dsPress(radius:))` ve `.dsPressIcon`.
- **UX ilkeleri (Meriç'in beklentisi):**
  - UX önce gelir.
  - Değişen şey anlık ve güzel bir animasyonla görünmeli.
  - Her şey geri alınabilir olmalı.
  - Hiçbir şey sessizce başarısız olmamalı; ekranda neden söylenmeli.
  - Özellik "var gibi görünüp çalışmamalı".
  - Kullanıcının gözüne sokmadan ama keşfedilebilir olmalı.

---

## 10. Bu turlarda yapılanlar (özet kronoloji)

- **0.3.0:**
  - AI stüdyoyu devraldı: plan, canlı uygulama, parlama, değişiklik listesi, tek tek geri alma, AI'ya özel araçlar.
  - 502 hataları giderildi (Groq token limiti).
  - Depolama temizliği ve çoklu proje silme eklendi.
  - Fikirle, metinle, kayıtla başlama akışları sağlamlaştırıldı.
  - Arka plan kaldırıcı eklendi.
  - Altyazılar önizlemede düzenlenebilir oldu.
  - Siyah önizleme düzeltildi (tek AVPlayer).
  - Altyazılar video karesine sabitlendi.
- **0.4.0 (build 40, son):**
  - Araçlar zaman aralığına uygulanıyor ve zaman çizelgesinde katman olarak görünüyor.
  - Arka plan için detaylı ayarlar geldi.
  - Önizlemede sesin çalmaması düzeltildi (audio session).
  - İki bağımsız konuşma tanıma motoru, AI hakemi ve kullanıcı seçimi eklendi.
  - Baştaki hayali 0.1 sn altyazı düzeltildi.

Ayrıntı için `git log`.

---

## 11. Doğrulanmamış ve açık işler

Hepsi CI'da derlendi ama **cihazda test edilmedi**. Meriç'ten geri bildirim bekleniyor:

1. **Önizleme sesi:** Düzeltme audio session; başka bir sebep varsa composition ses yolu (`VideoComposer` içindeki ses kısmı) incelenmeli.
2. **Arka plan kaldırma:**
   - Kalite, ısınma ve bellek.
   - Ön kamera ve aynalanmış kayıtlarda yön.
   - "İnce kenarlar" hızı.
3. **İki motorlu dinleme uçtan uca:**
   - `/transcribe` ve `/speech` gerçek token ile hiç denenmedi.
   - `SFSpeechRecognizer` delegate'in uzun dosyadaki davranışı: zaman damgaları mutlak mı, parça başına mı?
   - Gizlilik: artık ses sunucuya gidiyor. Ayarlara kapatma seçeneği ve `docs/PRIVACY.md` güncellemesi önerildi, yapılmadı.
4. **Aralıklı hız:** Bölmeden sonra efekt ve katmanların zamanları kaymıyor, klibe göre sabit kalıyor. Tasarım gereği böyle ama kullanıcı beklentisini kontrol et.
5. **Kalan eksikler:**
   - Ses temizleme hâlâ tüm videoya uygulanıyor, aralığa değil.
   - Ters oynatılan ve dondurulan klipler aralığa bölünemiyor.
6. **`docs/ROADMAP.md`** kısmen eski:
   - StoreKit 2 / paywall yok.
   - Gizlilik URL'si yok.
   - Workflow'lardaki senaryo ve kayıt adımları atlanıyor.

**Hata ayıklama ipucu:** Önizleme bozulursa (siyah ekran, üstü çizili oynat simgesi) `EditorModel.loadPlayback`, `compositionSignature` ve `EditorBackgrounds.prepareBackgrounds` üçlüsüne bak.

---

## 12. Nasıl çalışıyordum (önerilen iş akışı)

1. **Anla ve oku:** Meriç'in mesajını madde madde ayır. İlgili dosyaları oku; tahminle kod yazma, var olan API'yi bul.
2. **Planla:** Büyük işi bağımsız parçalara böl: önce Domain ve test, sonra motor, sonra UI, sonra AI ve Worker.
3. **Yaz:** Stili taklit et, metinleri iki dilde ekle. Mümkünse Domain'e saf mantık koy ve Swift Testing ile test yaz.
4. **Doğrula:** Commit, push, `gh workflow run ci.yml`, sonucu kontrol et. Hata varsa log'dan `error:` satırlarını bulup düzelt.
5. **Gönder:** İş turu bitince gerekiyorsa `MARKETING_VERSION` artır, `testflight.yml` tetikle.
6. **Worker:** Değiştiyse `node --check worker.js` ve `npx.cmd wrangler deploy`.
7. **Raporla:** Meriç'e Türkçe, kısa ve somut bir özet ver: ne değişti, neden bozuktu, nasıl denenir, neyi test edemedin. Sonuçlar hakkında dürüst ol.

Kolay gelsin. Büyük zevkti.
