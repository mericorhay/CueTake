# CueTake

AI Creator Camera for iOS. AI ile script oluştur → segmentlere böl → konuşurken seni takip eden teleprompter ile çek → timeline'da segmentleri düzenle → otomatik altyazı → sadece kötü segmenti tekrar çek → Reels / Shorts / TikTok olarak dışa aktar.

> **Durum:** Tasarımın 17 ekranının tamamı SwiftUI olarak uygulandı. Kamera, konuşma tanıma, AI, video düzenleme ve export motorları hâlâ yer tutucu; ekranlar bunların yerine tasarımın kendi zamanlamalarıyla çalışıyor.

## Teknoloji

| Alan | Seçim |
|---|---|
| Platform | Sadece iOS (iPhone), minimum **iOS 26** |
| Dil | Swift 6.2, **Swift 6 language mode**, strict concurrency |
| UI | SwiftUI + Observation (`@Observable`), Liquid Glass |
| Kamera | AVFoundation (AVCaptureSession + AVAssetWriter) |
| Konuşma | Speech: SpeechAnalyzer + SpeechTranscriber, gerekirse SFSpeechRecognizer'a düşüş |
| AI | Foundation Models (cihaz üzerinde) + CueTake backend (uzak) |
| Düzenleme / export | AVComposition, AVVideoComposition, PhotoKit |
| Kalıcılık | Proje klasörü (versiyonlu JSON + medya) + SwiftData yalnızca index için |
| Lokalizasyon | String Catalogs (`.xcstrings`), İngilizce + Türkçe |
| Test | Swift Testing |
| 3. parti bağımlılık | **Yok** |

## Yapı

```
CueTake/
├── CueTake/                      App target (ince): giriş noktası, composition root, routing
│   ├── CueTakeApp.swift
│   ├── AppDependencies.swift     Somut implementasyonları bilen tek yer
│   └── Resources/InfoPlist.xcstrings   İzin metinleri (TR + EN)
├── Packages/CueTakeKit/          Tek local Swift Package, çok modül
│   ├── Package.swift
│   ├── Sources/
│   │   ├── Domain/               Saf modeller + saf mantık (sadece Foundation)
│   │   ├── CaptureEngine/        Kamera, mikrofon, izinler, dosyaya yazma
│   │   ├── SpeechEngine/         Transcription + canlı script takibi
│   │   ├── MediaEngine/          Timeline → composition, altyazı layout, export
│   │   ├── AIServices/           Capability protokolleri, provider'lar, router
│   │   ├── Persistence/          ProjectStore, proje klasör düzeni, SwiftData index
│   │   ├── WorkflowEngine/       Step-based workflow çalıştırıcı
│   │   ├── DesignSystem/         Token, tipografi, animasyon, temel bileşenler
│   │   ├── Teleprompter/         Teleprompter state + görünüm
│   │   ├── LibraryFeature/       Home + projeler
│   │   ├── ScriptFeature/        AI script + segment düzenleme
│   │   ├── StudioFeature/        Kamera + Teleprompter + Kayıt + Retake
│   │   ├── EditorFeature/        Timeline + Altyazılar + Export
│   │   ├── WorkflowsFeature/     Workflow listesi / düzenleme / çalıştırma
│   │   └── SettingsFeature/      Varsayılanlar, ileride abonelik
│   └── Tests/
│       ├── DomainTests/
│       └── WorkflowEngineTests/
└── .github/workflows/ci.yml
```

## Modül sorumlulukları

| Modül | Sorumluluk | Bağımlılıklar |
|---|---|---|
| **Domain** | Project, Segment, Take, Recording, Transcript, Caption, Timeline, Workflow modelleri. `TimelineBuilder`, retake operasyonu, Türkçe-duyarlı metin yardımcıları. UI ve medya framework'ü bilmez. | — |
| **CaptureEngine** | Gerçek zamanlı çekim: oturum, cihaz, izinler, dosya yazımı, canlı ses buffer'larının speech'e aktarımı. Dosya oluştuktan sonrası MediaEngine'in işi. | Domain |
| **SpeechEngine** | `SpeechTranscribing` (canlı + dosya) ve `ScriptTracking` (konuşmacının script'teki yerini gerçek zamanlı bulur, teleprompter'ı sürer). | Domain |
| **MediaEngine** | `MediaComposing` (Timeline → AVComposition, oynatma ve export aynı composition'ı kullanır), `VideoExporting`, `CaptionRendering` (önizleme ve burn-in için tek layout). | Domain |
| **AIServices** | Capability bazlı AI protokolleri, `FoundationModelsProvider`, `RemoteAIProvider`, `AICapabilityRouter`. | Domain |
| **Persistence** | `ProjectStore`, `ProjectLayout`, `ProjectDocumentCoder` (schema version kontrolü), `InMemoryProjectStore`, SwiftData `ProjectIndexEntry`. | Domain |
| **WorkflowEngine** | `WorkflowRunner`, `WorkflowStepHandler`, devam ettirilebilir `WorkflowRunState`. Hiçbir capability modülünü import etmez; handler'ları app bağlar. | Domain |
| **DesignSystem** | Tasarımdan birebir alınan token'lar (`DS.Palette`, `DS.Radius`, `DS.Easing`), gömülü fontlar ve tipografi (`DS.archivo/sans/mono`, `DSHeadline`), sekiz keyframe animasyonu, cam yüzeyler ve temel kontroller (`DSPrimaryButton`, `DSPill`, `DSSlider`, `DSTabBar`, `FlowLayout`). | — |
| **Teleprompter** | `TeleprompterModel` (yüzde tabanlı yerleşim, dört hazır düzen, sürükle-boyutlandır, Word / Line / Karaoke vurgulama) ve panel + ayar sayfası görünümleri. Ses bilmez, sadece `ScriptPosition` alır. | Domain, DesignSystem |
| **LibraryFeature** | Proje listesi, oluştur / aç / sil. | Domain, DesignSystem, Persistence |
| **ScriptFeature** | AI ile script, segment düzenleme (sırala, böl, birleştir, yeniden yaz). | Domain, DesignSystem, AIServices |
| **StudioFeature** | Kamera önizleme + teleprompter overlay + kayıt + retake. Tek ekran, iki mod: tüm script veya tek segment. | Domain, DesignSystem, Teleprompter, CaptureEngine, SpeechEngine |
| **EditorFeature** | Video önizleme, segment timeline, altyazı düzenleme, export sheet. | Domain, DesignSystem, MediaEngine |
| **WorkflowsFeature** | Workflow'ları listeleme, oluşturma, çalıştırma. Doğrusal liste editörü, node editor yok. | Domain, DesignSystem, WorkflowEngine |
| **SettingsFeature** | Kamera, teleprompter ve altyazı varsayılanları; ileride StoreKit 2. | Domain, DesignSystem |

### Bağımlılık kuralları

- **Domain** hiçbir şeye bağımlı değil ve SwiftUI / AVFoundation import etmez.
- **Engine'ler** Domain dışında hiçbir modülü import etmez, birbirlerini de bilmez.
- **Feature'lar** birbirini import etmez. Ekranlar arası geçişi app target yönetir.
- **Feature'lar** ihtiyaç duydukları protokolleri initializer üzerinden alır. Global DI container yok; somut tipleri sadece `AppDependencies` bilir.
- **Eşzamanlılık:** UI modülleri (DesignSystem, Teleprompter, Feature'lar) varsayılan olarak `MainActor` üzerinde. Domain ve engine'ler nonisolated, engine implementasyonları actor olacak.

## Veri modeli: Segment merkezde

```
Project
 ├─ format, localeIdentifier, captionStyle
 ├─ recordings: [Recording]         fiziksel dosyalar (bir çekim = bir dosya)
 └─ segments: [Segment]             sıra = dizideki konum
      Segment
       ├─ role, title, script, estimatedDuration, teleprompter hints, metadata
       ├─ takes: [Take]             retake geçmişi
       │    Take ── recordingID ──► Recording
       │         └─ sourceRange (dosya içindeki aralık), status, transcript (kelime + zaman)
       ├─ selectedTakeID
       └─ captions: [CaptionCue]    segment-göreli zamanlar

Timeline = TimelineBuilder.build(project)    türetilir, asla kaydedilmez
   clips (mutlak zamanlı), captions (mutlak zamanlı), duration, missingSegmentIDs
```

**Neden mutlak zaman saklanmıyor?** 3. segment 2 saniye daha uzun tekrar çekildiğinde 4. ve 5. segmentleri ve onların altyazılarını kaydırmak gerekmesin diye. Retake sadece o segmente bir `Take` ekler (`Project.addTake`); Timeline yeniden hesaplanınca sonraki her şey kendiliğinden kayar.

**Neden Recording ile Take ayrı?** Tüm script'i tek seferde çekince tek bir `Recording` oluşur. Hizalama sonucu her segment bu dosyanın farklı bir aralığını gösteren bir `Take` alır. Retake yeni bir `Recording` ile tek bir `Take` üretir.

**Türetilen değerler:** `recordingState`, `actualDuration` ve timeline pozisyonları saklanmaz, seçili take'ten hesaplanır. Böylece aynı bilgi iki yerde tutulup birbirinden sapamaz.

**Altyazılar seçili take'e aittir.** Seçili take değişince o segmentin altyazıları temizlenir ve yeni transcript'ten tekrar üretilir. Diğer segmentlerinkine dokunulmaz.

### Sistemler nasıl bağlanıyor?

```
Canlı:    CaptureEngine ─ses─► SpeechTranscribing ─TranscriptUpdate─► ScriptTracking ─ScriptPosition─► TeleprompterModel
Kayıt:    CaptureResult ─► Recording + Take(lar) ─► transcribeFile ─► Take.transcript
Sonra:    SpeechAligning (AI) ─► segment sınırları    CaptionGenerating ─► Segment.captions
Düzenle:  Project ─TimelineBuilder─► Timeline ─MediaComposing─► AVComposition ─► oynatma / VideoExporting
```

## AI mimarisi

AI tek bir "servis" değil, birbirinden bağımsız capability'lerden oluşuyor:

| Capability | Protokol | Ne yapar |
|---|---|---|
| `scriptWriting` | `ScriptWriting` | Brief'ten script. Kısmi `ScriptDraft`'ları akış olarak döner. |
| `scriptSegmentation` | `ScriptSegmenting` | Hazır bir metni rollere sahip segmentlere böler. |
| `speechAlignment` | `SpeechAligning` | Kayıt sonrası söyleneni script'e hizalar, sürekli çekimi segmentlere böler. |
| `captionGeneration` | `CaptionGenerating` | Transcript'ten altyazı cue'ları üretir. |
| `videoAnalysis` | `VideoAnalyzing` | Dolgu kelime, uzun duraklama, script dışına çıkma gibi retake gerektiren yerleri bulur. |
| `workflowAI` | `WorkflowAssisting` | Doğal dilden `WorkflowDefinition` üretir. |

- Bir provider bu protokollerin herhangi bir alt kümesini uygular.
- `AICapabilityRouter`, tercih sırasına göre ilk *uygun* provider'ı seçer. Uygunluğu cihaz, dil ve yapılandırma belirler.
- Girdi ve çıktılar Domain tipleridir; feature'lar provider'a özel formatları görmez.
- Uzak modellerin API anahtarları backend'de durur, uygulamaya asla gömülmez.
- SpeechEngine'deki `ScriptTracking` deterministik ve gerçek zamanlıdır (teleprompter için). AI tarafındaki `SpeechAligning` ise kayıttan sonra çalışan, daha akıllı ikinci geçiştir.

## Workflow modeli

- `WorkflowDefinition`, sıralı `WorkflowStep`'lerden oluşan Codable bir veridir ve `schemaVersion` taşır. Node graph değildir.
- Adımlar `{"type": "...", "parameters": {...}}` olarak kodlanır: `generateScript`, `segmentScript`, `record`, `analyzeSpeech`, `generateCaptions`, `applyCaptionStyle`, `export`.
- Tanınmayan tipler `.unsupported` olarak okunur ve runner onları atlar. Yeni sürüm veya API'den gelen workflow'lar eski istemcileri bozmaz.
- `record` gibi kullanıcı gerektiren adımlarda runner `.needsUser` olayıyla durur. Kullanıcı adımı bitirince `state.advanced()` ile kaldığı yerden devam eder. `WorkflowRunState` Codable'dır, uygulama kapansa da kaldığı yer kaybolmaz.
- Tanım Domain'de, çalıştırma WorkflowEngine'de, UI WorkflowsFeature'da. App Intents ve uzak otomasyon ileride aynı runner'ı çağırabilir.

Örnek:

```json
{
  "schemaVersion": 1,
  "name": "Instagram Ürün Videosu",
  "steps": [
    { "kind": { "type": "generateScript", "parameters": { "platform": "instagramReels", "targetDuration": { "value": 18000, "timescale": 600 } } } },
    { "kind": { "type": "segmentScript" } },
    { "kind": { "type": "record", "parameters": { "mode": "continuous", "camera": "front", "countdownSeconds": 3 } } },
    { "kind": { "type": "analyzeSpeech" } },
    { "kind": { "type": "generateCaptions" } },
    { "kind": { "type": "applyCaptionStyle", "parameters": { "presetID": "bold-pop" } } },
    { "kind": { "type": "export", "parameters": { "format": { "aspectRatio": "portrait9x16", "resolution": "hd1080", "frameRate": 30 }, "burnsInCaptions": true, "destination": "photoLibrary" } } }
  ]
}
```

## Kalıcılık

```
Application Support/Projects/<project-id>/
    project.json    versiyonlu Project dokümanı (tek doğru kaynak)
    media/          kayıt dosyaları (Recording.relativePath)
```

SwiftData **ana domain modeli değildir**, sadece listeleme index'i olarak kullanılır (`ProjectIndexEntry`). İndex her an dokümanlardan yeniden kurulabildiği için migration gerekmez. Nedenleri:

- `@Model` sınıfları Sendable değildir, engine actor'leri arasında taşınamaz.
- SwiftData dizi sırasını korumaz, segment sırası ise hayati.

## Lokalizasyon (TR + EN)

- Her UI modülünün kendi `Resources/Localizable.xcstrings` dosyası var. Metinler `Text("key", bundle: .module)` / `String(localized:bundle:)` ile kullanılır; kullanıcıya görünen hiçbir metin hard-code edilmez.
- Anahtarlar semantiktir (`studio.retake.title`), İngilizce kaynak dildir.
- İzin metinleri app target'taki `InfoPlist.xcstrings` dosyasında. Bu dosya app bundle'ına `tr.lproj` da eklediği için iOS, package bundle'larındaki Türkçe metinleri de seçebiliyor.
- **Türkçe dikkat:** büyük/küçük harf dönüşümleri ve metin karşılaştırmaları her zaman locale ile yapılır. `CaptionTextCase.apply`, "istanbul"u "İSTANBUL" yapar (ISTANBUL değil). `ScriptText.matchKey`, konuşma takibinde ı/i karışmasını önler.

## Kurulum (Mac)

Bu iskelet Windows'ta oluşturuldu. Package CI'da derleniyor, ama `.xcodeproj` Mac'te bir kez oluşturulmalı:

1. Xcode 26 veya üstünde **File ▸ New ▸ Project ▸ iOS App** seç: ad `CueTake`, arayüz SwiftUI, testler Swift Testing. Geçici bir klasöre kaydet.
2. `CueTake.xcodeproj` dosyasını bu reponun köküne taşı. Xcode'un oluşturduğu kaynak klasörünü sil.
3. Projede eski grubu kaldır. Repodaki `CueTake/` klasörünü **folder (buildable)** olarak app target'a ekle.
4. **File ▸ Add Package Dependencies ▸ Add Local…** ile `Packages/CueTakeKit` paketini ekle ve `CueTakeKit` ürününü app target'a bağla.
5. Build Settings:
   - iOS Deployment Target `26.0`
   - Swift Language Version `6`
   - Default Actor Isolation `MainActor`
   - Approachable Concurrency `Yes`
   - Targeted Device Family `iPhone`
6. Project ▸ Info ▸ Localizations bölümüne **Turkish** ekle.
7. Info: `GENERATE_INFOPLIST_FILE` açık kalsın. Kamera, mikrofon, konuşma ve fotoğraf izin anahtarlarını ekle; çevirileri `InfoPlist.xcstrings`'ten gelir.

## CI

`.github/workflows/ci.yml`, her push'ta paketi macOS runner'da derleyip iOS Simulator'de testleri koşar. Private repoda macOS dakikaları ücretsiz kotadan 10 kat hızlı düşer.

## Tasarımın uygulanması

Kaynak: Claude Design dosyası `CueFlow.dc.html`, 17 ekranlık interaktif prototip (dosya adı tasarımdaki hâliyle bırakıldı). Renkler, boşluklar, köşe yarıçapları, tipografi ölçeği, gölgeler, animasyon eğrileri ve gecikmeler dosyadan birebir alındı.

| Tasarım ekranı | Modül |
|---|---|
| onboarding | `OnboardingFeature` |
| home, projects | `LibraryFeature` |
| create, prompt, blueprint, script | `ScriptFeature` |
| studio, recording, complete, retake | `StudioFeature` |
| editor, captions, export | `EditorFeature` |
| workflows, workflowDetail | `WorkflowsFeature` |
| settings | `SettingsFeature` |
| teleprompter paneli + ayar sayfası | `Teleprompter` |

### Fontlar

Tasarım Archivo, Instrument Sans ve JetBrains Mono kullanıyor; üçü de iOS'ta yok. Gerekli ağırlıklar `DesignSystem/Resources/Fonts` altına gömüldü ve çalışma anında kaydediliyor (`FontRegistry`), böylece Info.plist'e dokunmadan modül kendi kendine yeterli kalıyor. Üçü de SIL Open Font License; lisans dosyaları yanlarında duruyor.

### Bilinçli olarak uygulanmayanlar

Prototipin bir kısmı uygulamanın değil, önizlemenin parçası. Bunlar kopyalanmadı:

- **Cihaz çerçevesi, sahte durum çubuğu, Dynamic Island ve home indicator.** Gerçek uygulamada bunları iOS çiziyor; kopyalamak gerçek olanın üstüne ikinci bir kopya çizmek olurdu.
- **Portrait/Landscape anahtarı ve alttaki ekran haritası çipleri.** Prototipte gezinmek için var; uygulamada yönü cihaz, ekranı kullanıcının akışı belirliyor.

### Doğruluk sınırları

- **Cam yüzeyler.** CSS'teki `backdrop-filter: blur()` + `rgba()` ikilisinin SwiftUI'de birebir karşılığı yok. Blur için `Material`, renk için tasarımın kendi rgba değeri üst üste konuyor; Material kendi tonunu da kattığı için sonuç birkaç adım daha koyu olabilir.
- **Sıkı satır yüksekliği.** Tasarımın başlıkları `line-height:.95`–`1`, kart başlıkları ve altyazılar `1.15`–`1.2` kullanıyor; hepsi fontun doğal satır aralığından sıkı ve SwiftUI'nin `Text`'i satır aralığını daraltamıyor. Bu yüzden `TightText`, `UILabel` + `NSParagraphStyle` üzerinden mutlak satır kutusu dayatıyor; `DSHeadline` de her satırı bununla diziyor, yani kendiliğinden alt satıra taşan metinler (Türkçe çeviriler İngilizceden uzun olduğunda) de aynı sıkı aralığı koruyor. Gevşek değerler (`1.4`–`1.5`) SwiftUI'nin kendi `lineSpacing`'iyle veriliyor.
- **Zamanlayıcılar.** Kayıt (135 ms/kelime), retake (130 ms), AI üretimi (850 ms/adım), export (1150 ms/aşama) ve workflow (900 ms/adım) şu an tasarımdaki sürelerle taklit ediliyor. Gerçek motorlar geldiğinde bu zamanlayıcılar `ScriptPosition`, export ilerlemesi ve `WorkflowRunner` olaylarıyla değişecek; ekranlar zaten bu değerleri okuyor.

### Dil

Tasarımın arayüz metinleri İngilizce, içerik metinleri Türkçe. String catalog'larda kaynak dil İngilizce ve değerler tasarımdaki metinlerin birebir aynısı; Türkçe çeviriler yanlarında. Yani uygulama İngilizce çalıştırıldığında ekranlar tasarımla kelimesi kelimesine aynı.
