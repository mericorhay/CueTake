# CueTake Workflow Platformu — Çalışma ve Mimari Planı

> Durum: onaylandı, uygulamada · Tarih: 16 Eylül 2026 · Kod tabanı: build 75

Amaç: Workflow'u "konuşan kafa videosunu toparlayan hat" olmaktan çıkarıp **tekrar eden içerik üretimini baştan sona otomatikleştiren** modüler bir platforma çevirmek. Bir kişi bir kez kurar, sonra her ay, her gün ya da tek seferde 60 video için çalıştırır.

---

## 1. Bugün elimizde ne var

| Parça | Durum |
|---|---|
| `WorkflowDefinition` (şema v2) | `sections` + `style` + doğrusal `steps`. JSON, AI yazabiliyor, bozuk elemanı atlıyor. |
| Adım türleri (13) | generateScript, segmentScript, record, assembleSections, analyzeSpeech, trimSilences, cutWords, setSpeed, cleanAudio, musicBed, generateCaptions, applyCaptionStyle, export |
| `WorkflowRunner` | Tek proje, sıralı, `record` gelince durur. Handler protokolü var ama adımların çoğu `AppModel+Workflows.perform` içinde `switch` ile. |
| Studio ekranı | Pipeline düzenleme, stil kartı, AI ile workflow yazma, çalıştırma sonucu. |
| Girdi | Kamera çekimi veya seçilen **videolar**. Fotoğraf klip olamaz, sadece üst katman. |
| Çıktı | Fotoğraflar / Dosyalar. Paylaşım, zamanlama, platforma yükleme yok. |
| Toplu iş | Yok. Bir çalıştırma = bir proje. Arka planda devam etmiyor. |
| Üretim (AI video/ses) | Yok. |
| Editör AI'ı | Güçlü (`EditPlan` + `AIDirector`: kesme, altyazı, filtre, ses, zoom, takip). Workflow'dan çağrılamıyor. |

**Ana açık:** Workflow tek bir kişinin tek bir çekimi için tasarlanmış. Fotoğraf yığınından içerik, üretilmiş medya, toplu çalıştırma, inceleme kuyruğu ve yayın yok.

---

## 2. Kullanıcılar (kimin için yapıyoruz)

### A) "Aylık dump" yapan içerik üreticisi
Ayın 30'unda galeride 400 fotoğraf + 60 kısa video var. İstediği:
- En iyi 15–20 kareyi seçmek (bulanık, kapalı göz, neredeyse aynı kareler elensin; farklı günler, farklı insanlar temsil edilsin).
- Hikâye gibi sıralamak (kronolojik ya da renk/enerji akışı).
- **Carousel** (en çok 20 öğe, 4:5) ve aynı içerikten **müziğe oturmuş Reel** (beat'e göre kesilmiş, fotoğraflarda hafif Ken Burns).
- Kapak seçimi, gönderi açıklaması ve hashtag önerisi.
- Her ay aynı görünüm: tek dokunuş "Eylül dump'ını yap".

### B) "Shorts fabrikası" (yüzsüz kanal)
Bir konu listesinden (ya da AI'ın ürettiği 60 fikirden) her biri için:
- Senaryo → **Seedance 2.5** ile ses + video (tek seferde 30 sn'ye kadar, sesi eşzamanlı) ya da görüntü + ayrı TTS seslendirme.
- Ses ile görüntüyü eşleştirme, altyazı, hook yazısı, zoom/punch, müzik, loudness.
- 50–60 videoyu kuyrukta üretme, hızlıca gözden geçirme (kabul / yeniden üret / sil).
- Başlık, açıklama, etiket şablonu ile YouTube'a yükleme ya da zamanlama.

### C) Konuşan kafa (bugünkü kullanıcı)
Senaryo → çekim → temizlik → altyazı → zoom → dışa aktarma. Mevcut hat; yeni motora taşınır, hiçbir şey kaybolmaz.

### D) Tekrar kullanıcı (repurpose)
Uzun bir video (podcast, canlı yayın) → en iyi 10 an → 10 dikey klip. B'nin toplu altyapısını, C'nin konuşma araçlarını kullanır.

---

## 3. Gerçek dünya kısıtları (plana yön veren)

| Konu | Bilgi | Etkisi |
|---|---|---|
| Seedance 2.5 | 31 Temmuz 2026'da çıktı. Tek geçişte 30 sn'ye kadar, sesi eşzamanlı video; 720p'ye kadar; çoklu referans (30 görsel, 10 video, 10 ses); FAL üzerinden herkese açık API (7 Ağustos'tan beri). | Sağlayıcı olarak eklenebilir. Anahtar **sunucuda** (Worker) kalır. Maliyet ve kuyruk süresi kullanıcıya gösterilmeli. |
| YouTube yükleme | 1 Haziran 2026'dan beri `videos.insert` ayrı kotada: çağrı başı 1 birim, **günde 100 yükleme** (varsayılan). | 60 short/gün sığar. OAuth + Google uygulama doğrulaması gerekir. |
| Instagram yayın | Graph API ile **24 saatte 100 gönderi** (kayan pencere); carousel tek gönderi sayılır; profesyonel hesap şart. | Dump için yeterli. Meta uygulama incelemesi gerekir; ilk sürümde paylaşım sayfası (share sheet) yeterli. |
| Platform politikaları | Toplu, birbirine çok benzeyen AI içeriği YouTube'da gelir ortaklığı ve erişim açısından riskli; yapay içerik etiketi bekleniyor. | "Çeşitlilik koruması" ve otomatik AI etiketi motorun parçası olmalı. |
| iOS arka plan | Uygulama arka plana geçince uzun iş durur. iOS 26'da kullanıcı başlatmalı uzun işler için sürekli işleme görevi ve Live Activity ile ilerleme var. | Toplu render kuyruğu kalıcı olmalı, kaldığı yerden devam etmeli. |
| Cihazda render | 50 video × ~10–20 sn render = 10–20 dk; ısınma. | Paralellik 1–2; ısı durumuna göre yavaşlama; "dakikalar içinde" ancak üretim bulutta paralel, render/yayın sıralı olursa. |

---

## 4. Hedef mimari (modüler, taş gibi)

```
┌──────────────────────── UI ─────────────────────────┐
│ Workflow Galerisi · Studio (graph) · Toplu Pano ·    │
│ İnceleme Kuyruğu · Takvim · Sağlayıcı/Kredi ayarları │
└───────────────▲──────────────────────────────────────┘
                │ yalnızca durum okur, komut gönderir
┌───────────────┴──── WorkflowPlatform ────────────────┐
│ JobQueue (actor, kalıcı)  ·  Scheduler  ·  Budget     │
│ GraphExecutor (DAG, fan-out, retry, checkpoint)       │
└───────▲──────────────▲───────────────▲───────────────┘
        │ StepRegistry  │ Providers      │ Artifacts
┌───────┴─────┐ ┌───────┴────────┐ ┌─────┴──────────────┐
│ Step modülleri│ │ Generation     │ │ ArtifactStore       │
│ (her biri ayrı│ │ Publishing     │ │ MediaSet, Project,  │
│  paket hedefi)│ │ Storage        │ │ Render, Carousel,   │
└──────────────┘ └────────────────┘ │ PublishReceipt      │
                                     └────────────────────┘
```

### 4.1 Katmanlar ve paket hedefleri

| Hedef | Sorumluluk | Bağımlılık |
|---|---|---|
| `Domain/Workflow` (v3) | Graph, girdi yuvaları, adım örnekleri, değişkenler, çıktı tanımları, şema göçü | Yalnız Foundation |
| `WorkflowEngine` (genişler) | `StepDescriptor`, `StepExecutor`, `StepRegistry`, `GraphExecutor`, `RunJournal` | Domain |
| `WorkflowPlatform` (yeni) | `JobQueue` actor, kalıcılık, zamanlayıcı, bütçe, arka plan görevi, Live Activity köprüsü | Engine, Persistence |
| `WorkflowSteps/Media` (yeni) | Fotoğraf seçimi, eleme, sıralama, fotoğraf→klip, beat kesimi, carousel | MediaEngine, Vision |
| `WorkflowSteps/Edit` (yeni) | Mevcut 13 adımın taşınmış hali + "AI ile düzenle" adımı (AIDirector) | EditorFeature'ın model katmanı |
| `WorkflowSteps/Generate` (yeni) | Video / ses / müzik üretimi, ses-görüntü eşleştirme | Providers |
| `WorkflowSteps/Publish` (yeni) | Kaydet, paylaş, YouTube, Instagram, zamanlama | Providers |
| `Providers` (yeni) | `GenerationProvider`, `PublishingProvider` protokolleri; Worker istemcisi | AIServices |
| `backend/assistant` | `/generate/video`, `/generate/voice`, `/jobs/:id`, OAuth token değişimi, kredi defteri | — |
| `WorkflowsFeature` | Galeri, Studio, Toplu Pano, İnceleme, Takvim ekranları | Platform (yalnız durum) |

Kural: **UI hiçbir adımı kendisi çalıştırmaz.** `AppModel+Workflows.perform` içindeki `switch` kaldırılır; her adım kendi modülünde bir `StepExecutor` olur.

### 4.2 Veri modeli (şema v3)

```text
WorkflowDefinition v3
  inputs:   [InputSlot]      // "photos": mediaSet(filter), "topics": textList, "music": audio
  variables:[Variable]       // {{month}}, {{topic}}, {{index}}, kullanıcı alanları
  graph:    [StepNode]       // id, type, params, inputs: [port -> nodeID.port], forEach?
  outputs:  [Deliverable]    // reel 9:16, carousel 4:5, short 9:16 + yayın hedefleri
  style, sections            // v2'den aynen
  policy:   RunPolicy        // paralellik, bütçe, onay noktaları, çeşitlilik koruması
```

- v2 dosyaları otomatik göçer: doğrusal `steps` → zincir graph.
- Adım parametreleri tipli ama JSON'da gevşek okunur (bugünkü "bozuk eleman düşer" ilkesi korunur).
- `forEach` bir düğümü girdideki her öğe için çoğaltır (60 konu → 60 alt çalıştırma).

### 4.3 Adım sözleşmesi

```text
StepDescriptor {
  type: "selectBest"                // kalıcı kimlik
  title, summary                    // UI ve AI yazarı için
  inputs:  [Port(name, ArtifactType)]
  outputs: [Port(name, ArtifactType)]
  params:  JSON Schema              // AI workflow yazarı buradan okur
  cost:    none | credits(estimate) // üretim adımları
  runsOn:  device | cloud
  needsUser: none | review | record
  idempotencyKey(params, inputs)    // aynı girdi → önbellekten
}

protocol StepExecutor {
  func run(_ ctx: StepContext) async throws -> StepOutput   // ilerleme, iptal, günlük ctx'te
}
```

- **Artifact türleri:** `MediaSet`, `TextList`, `Script`, `AudioAsset`, `VideoAsset`, `Project`, `RenderedVideo`, `Carousel`, `PostDraft`, `PublishReceipt`.
- Her çıktı `ArtifactStore`'da içerik anahtarıyla saklanır. Yeniden çalıştırmada değişmeyen adım atlanır, çöken çalıştırma kaldığı yerden sürer.
- `RunJournal`: her adımın başlangıcı, süresi, maliyeti, hatası. İnceleme ve hata ayıklama buradan.

### 4.4 Toplu çalışma (JobQueue)

- Kalıcı kuyruk (actor). Uygulama kapansa da iş kaybolmaz.
- Kaynak havuzları ayrı sınırlanır:
  - üretim (bulut): 4 paralel,
  - render (cihaz): 1, ısı durumuna göre bekler,
  - yükleme: platform kotasına göre sıralı.
- Hata politikası: ağ/sağlayıcı hatasında geri çekilmeli tekrar deneme; içerik hatasında öğe "incelemeye" düşer, diğerleri devam eder.
- Arka plan: kullanıcı "Başlat" dediğinde iOS 26 sürekli işleme görevi + Live Activity ("23/60 hazır").
- Bütçe: çalıştırmadan önce tahmini kredi gösterilir; limit aşılırsa durur.

### 4.5 Sağlayıcılar

- `GenerationProvider`: `submit(request) -> JobID`, `status(JobID)`, `result(JobID) -> URL`. İlk uygulama **Seedance 2.5** (Worker → FAL). Sonra TTS ve müzik.
- `PublishingProvider`: `prepare(PostDraft)`, `publish`, `schedule`, `status`. Sıra:
  1. Fotoğraflar / Dosyalar / paylaşım sayfası (hemen),
  2. YouTube (OAuth, günlük 100 yükleme sayacı, AI içerik etiketi alanı),
  3. Instagram (profesyonel hesap, 24 saatte 100 gönderi sayacı, carousel).
- Anahtarlar ve OAuth sırları **yalnız sunucuda**. Uygulama sadece kısa ömürlü token tutar (Keychain).

### 4.6 Kalite ve güvenlik kapıları (her çıktıda)

- Süre, çözünürlük, en-boy, güvenli alan (altyazı platform butonlarının altında kalmasın).
- Ses yüksekliği (−14 LUFS hedef), sessiz/siyah kare taraması.
- Çeşitlilik koruması: toplu işte aynı hook/başlık/müzik tekrarını engeller.
- Yapay içerik etiketi: üretim adımı kullanıldıysa yayın taslağına otomatik işaret.
- İnceleme noktası: workflow sahibi "yayından önce bana göster" diyebilir.

---

## 5. Yeni adım kataloğu

**Girdi**
- `pickMedia`: tarih aralığı, albüm, kişi, tür (foto/video), en fazla N.
- `textList`: satır satır konu, CSV, ya da `generateIdeas`.
- `generateIdeas`: niş + ton + adet → konu listesi (AI).
- `importLongVideo`: uzun video → konuşma analizi.

**Seçme ve sıralama (dump)**
- `dedupe`: benzer kareleri gruplar, en iyisini tutar (Vision feature print).
- `scoreAesthetics`: estetik puanı, bulanıklık, göz kapalı, yüz var mı (Vision).
- `selectBest`: N öğe, gün / kişi / tür dağılımı kuralıyla.
- `orderStory`: kronolojik, renk akışı, enerji (sakin → yoğun → kapanış).
- `pickCover`: en yüksek puanlı + yüzlü + ortalanmış kare.

**Kurgu**
- `photoToClip`: süre, Ken Burns (mevcut zoom motoru), yüz odaklı.
- `beatSync`: müziğin vuruşlarını bulur (cihazda onset analizi), kesimleri vuruşa oturtur.
- `assembleSequence`: medya listesi → proje.
- `aiEdit`: talimat metni → `AIDirector` (kesme, altyazı, zoom, takip, filtre… editördeki her şey).
- `hookTitle`, `brandKit` (logo, renk, font), `highlightMoments` (uzun videodan en iyi anlar).
- Mevcut 13 adım aynen taşınır.

**Üretim**
- `generateScript` (mevcut, genişler), `generateVideo` (Seedance 2.5: metin/görsel/referans → sesli video), `generateVoice` (TTS), `generateMusic`, `matchAudioToVideo` (süre eşitleme, ducking, altyazı hizası).

**Çıktı**
- `render`: çoklu varyant (9:16, 4:5, 1:1).
- `carousel`: en çok 20 öğe, 4:5, sıralı dosyalar.
- `writePost`: açıklama, hashtag, YouTube başlık/açıklama/etiket (şablon + AI).
- `qualityGate`, `review`, `publish` (platform, hemen/zamanlı), `saveToPhotos`.

---

## 6. Hazır şablonlar (galeride)

1. **Aylık Dump** — pickMedia(bu ay) → dedupe → scoreAesthetics → selectBest(18) → orderStory → pickCover → [carousel] + [photoToClip → beatSync(müzik) → render 9:16] → writePost → review → publish/kaydet.
2. **Shorts Fabrikası** — textList / generateIdeas(60) → forEach: generateScript → generateVideo(Seedance 2.5, sesli) → matchAudioToVideo → aiEdit("hook yazısı, altyazı, punch zoom") → qualityGate → writePost → review(toplu) → publish(YouTube, zamanlı).
3. **Konuşan Kafa** — bugünkü hat + aiEdit + zoom/takip.
4. **Podcast → Klipler** — importLongVideo → highlightMoments(10) → forEach: reframe(takip) → captions → hookTitle → render.

---

## 7. UI planı

- **Galeri:** şablon kartları, kişi tipine göre ("Dump", "Faceless Shorts", "Konuşan kafa", "Repurpose").
- **Studio:** bugünkü dikey hat görünümü korunur. Graph dallanması "kol" olarak gösterilir (Carousel kolu / Reel kolu). Serbest düğüm tuvali yok, mobilde okunaklı kalsın.
- **Çalıştırma sayfası:** girdileri iste (hangi ay, hangi konular), tahmini süre ve kredi, "Başlat".
- **Toplu Pano:** her öğe bir kart (küçük önizleme, durum çipi: üretiliyor / render / incelemede / hazır / yüklendi / hata). Kaydırarak kabul, yeniden üret, sil. Tek dokunuşla editörde aç.
- **Takvim:** zamanlanmış yayınlar, günlük kota göstergesi.
- **Live Activity:** "Shorts Fabrikası 23/60".

---

## 8. Fazlar

| Faz | İçerik | Dış bağımlılık | Bitti sayılması için |
|---|---|---|---|
| **0 — Temel** | Şema v3 + v2 göçü, StepRegistry, GraphExecutor, ArtifactStore, RunJournal. Mevcut 13 adım executor'a taşınır. UI aynı kalır. | Yok | Eski workflow'lar aynen çalışır; testler: göç, fan-out, checkpoint, iptal. |
| **1 — Dump** | Fotoğraf klip olarak (Domain), pickMedia, dedupe, scoreAesthetics, selectBest, orderStory, pickCover, photoToClip, beatSync, carousel, writePost, paylaşım sayfası. Aylık Dump şablonu. | Yok (tamamen cihazda) | 400 öğeden 2 dk altında seçim; carousel + reel çıkar. |
| **2 — Toplu** | JobQueue, arka plan görevi, Live Activity, Toplu Pano, inceleme kuyruğu, qualityGate, aiEdit adımı. | Yok | 60 öğelik yapay iş kapanıp açılınca devam eder. |
| **3 — Üretim** | Worker üretim uçları, Seedance 2.5, TTS, müzik, matchAudioToVideo, kredi defteri, Shorts Fabrikası şablonu. | FAL hesabı + sunucu anahtarı, kredi modeli | 10 konu → 10 sesli, altyazılı short. |
| **4 — Yayın** | YouTube OAuth + yükleme + zamanlama + kota sayacı + AI etiketi; Instagram Graph (carousel/reel); Takvim. | Google doğrulaması, Meta incelemesi | Günlük 60 short planlanıp yüklenir. |
| **5 — Zekâ** | AI workflow yazarı descriptor'lardan okur; Kısayollar (App Intents); "her ayın 1'inde dump'ı hazırla" hatırlatıcısı; performans geri bildirimi. | — | "Bana yemek kanalı için günlük 3 short hattı kur" cümlesi çalışan bir workflow üretir. |

---

## 9. Kararlar

**16 Eylül 2026 — kullanıcı kendi anahtarını bağlar (BYOK).** Üretim sağlayıcıları (fal.ai / Seedance ve fal'daki her model, Google Veo, OpenAI Sora, Replicate'teki her model) kullanıcının kendi API anahtarıyla, telefondan doğrudan çağrılır. Anahtarlar Keychain'de, yalnız bu cihazda. Sunucu kredisi şimdilik yok. İlk teslim: `GenerationEngine`, Ayarlar → API anahtarları, workflow'da "Video üret" adımı.

**16 Eylül 2026 — aylık dump yan özellik.** Öne çıkarılmaz; şablon galerisinde "Diğer şablonlar" altında durur, onboarding ve ana ekranda anılmaz. Faz 1 önceliği düşer; ana odak üretilen videoların workflow **ve editörde** kullanılması.

**16 Eylül 2026 — editörde üretim.** Editörde "Üret" aracı: istem → kullanıcının modeli → videonun üstüne (B-roll, sessiz) ya da klip olarak, oynatma çizgisine. Arka planda çalışır, zaman çizelgesinde yer tutucu gösterir, kendini yerleştirir, geri alınabilir. AI kurgu da `generateVideo` ile B-roll üretebilir (en fazla 3, yalnız model bağlıysa).

**17 Eylül 2026 — her workflow videoyu yazarak biter.** Son adım her zaman tek bir Export'tur; silinemez, taşınamaz, kapatılamaz (`WorkflowDefinition.ensureFinalExport`, eski/AI/JSON belgelerde de uygulanır). Çözünürlük ve FPS stilden gelir ve Export kartında da düzenlenir; hedef (Fotoğraflar/Dosyalar) çalıştırmada gerçekten uygulanır.

**17 Eylül 2026 — workflow'a özel API gönderimi.** Export adımında `delivery`: adres (HTTPS), POST/PUT, gövde (multipart form + video / yalnız video / yalnız JSON bilgi), başlık/önek, ek alanlar. Anahtar workflow dosyasında değil, Keychain'de workflow kimliğiyle (`WorkflowSecretStore`); çoğaltılan workflow anahtarsız başlar. "Bağlantıyı dene" JSON test isteği atar; sonuç kartı gönderim durumunu ve "Tekrar gönder"i gösterir. Arka planda (uygulama kapalıyken) yükleme henüz yok — sonraki adım: `URLSession` background configuration.

## Açık kararlar (ilk sürümdeki öneriler)

1. **Üretim ve ödeme:** Seedance'ı kendi sunucumuz üzerinden, kredi (uygulama içi satın alma) ile mi sunalım, yoksa ilk aşamada yalnız kendi hesabımızla mı test edelim?
2. **Yayın sırası:** Önce paylaşım sayfası (hemen), sonra YouTube, sonra Instagram. Uygun mu?
3. **Toplu render yeri:** Cihazda (ücretsiz, daha yavaş) ile başlayıp bulut render'ı sonraya bırakmak. Uygun mu?
4. **Başlangıç:** Faz 0 + Faz 1 (dış bağımlılık yok) ile başlamak.

Kaynaklar: [Seedance 2.5 (Replicate)](https://replicate.com/bytedance/seedance-2.5), [Seedance 2.5 rehberi (Apiframe)](https://apiframe.ai/guides/seedance-2-5-guide), [YouTube API kota 2026 (Phyllo)](https://www.getphyllo.com/post/youtube-api-limits-how-to-calculate-api-usage-cost-and-fix-exceeded-api-quota), [bundle.social – YouTube kota](https://bundle.social/blog/youtube-api-quota-exceeded-limits-fixes), [Meta içerik yayınlama dokümanı](https://developers.facebook.com/docs/instagram-platform/content-publishing/), [Instagram API limitleri (bundle.social)](https://bundle.social/blog/instagram-api-rate-limits).
