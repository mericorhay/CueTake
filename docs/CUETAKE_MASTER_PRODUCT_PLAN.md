# CueTake Master Product Plan

> AI, Studio, timeline, media engine, Apple platformu ve UX için tek ürün otoritesi
> Güncelleme: 15 Eylül 2026 · Kod tabanı: build 68 · marketing version: 0.5.0

Bu dosya CueTake’in build 63 sonrasındaki gerçek kod durumunu, yapılacak normal editör özelliklerini, AI araçlarını, Apple teknolojilerini, rakip karşılaştırmasını ve kullanıcı akışını tek bir yürütme planında birleştirir. Yeni bir özellik bu dosyada karşılığı olmadan “tamamlandı” sayılmaz. Eski ayrıntılı planlar tarihçe ve teknik ek olarak kalır:

- [AI tool list roadmap](AI_TOOL_LIST_ROADMAP.md)
- [Feature gap report](FEATURE_GAP_REPORT.md)
- [Timeline UX audit](TIMELINE_UX_AUDIT.md)
- [Subject tracking engine plan](SUBJECT_TRACKING_ENGINE_PLAN.md)
- [Zoom engine plan](ZOOM_ENGINE_PLAN.md)

## Ürün kararı

CueTake, mobilde masaüstü editörlerin bütün panellerini kopyalamaz. Rakiplerin hızını ve otomasyonunu, masaüstü seviyesinde kontrol edilebilir ve açıklanabilir bir edit kararıyla birleştirir:

1. Kullanıcı bir klibi, kelimeyi veya kadrajı seçer.
2. CueTake analiz eder ve açık bir öneri üretir.
3. Öneri etkilenecek aralık, güven, kalite etkisi ve geri alma kapsamıyla gösterilir.
4. Kullanıcı tek dokunuşla kabul eder, düzenler veya reddeder.
5. Aynı deterministik evaluator preview ve export’ta çalışır.

Bu ürünün savunulabilir farkı “daha fazla hazır efekt” değil; bir kez seçilen öznenin kadraj, zoom, yazı, blur, overlay ve ses kararlarının aynı zaman çizgisinde birlikte ve geri alınabilir çalışmasıdır.

## Gerçek başlangıç durumu

### Şu anda kodda kullanılan Apple katmanları

| Katman | Mevcut kullanım | Sınır |
|---|---|---|
| AVFoundation | `AVCaptureSession`, kamera preview, `AVPlayer`, `AVMutableComposition`, video/audio composition, `AVAssetWriter`, `AVAssetExportSession` | Doğrudan Metal render ve tam donanım codec kontrolü henüz yok |
| Vision | yüz tespiti, `VNTrackObjectRequest`, `VNSequenceRequestHandler`, confidence, kişi segmentation | Optical flow, foreground instance mask, body/hand pose ve re-detection henüz yok |
| Core Image | filtre, blend, mask, background removal, export görüntü işlemesi | Özel Metal shader katmanı henüz yok |
| Speech | `SpeechAnalyzer`/`SpeechTranscriber` ve eski `SFSpeechRecognizer` fallback’i | Transcript sonuçları henüz ortak AI tool registry’sine bağlanmadı |
| Foundation Models | `LanguageModelSession` ile script yazma, rewrite ve workflow yazarı | Mevcut `EditPlan`/`AIDirector` akışı var; genel typed tool registry ve otomatik araç seçimi eksik |
| Photos/PhotosUI | çoklu footage seçimi, video layer seçimi, Photos’a export | Share Extension ve sistem Shortcuts entegrasyonu yok |
| Swift Concurrency | analiz/export task’leri, progress, cancellation, actor sınırları | Uzun işlerin uygulama arka plana geçince devamı yok |
| SwiftUI | Studio, timeline, inspector, haptic `sensoryFeedback`, animasyonlu durumlar | Perf state ve gerçek cihaz ölçüm katmanı yok |

### Build 68’de tamamlanmış güvenlik tabanı

- Source-time dönüşümü split, trim, speed, reverse ve freeze için ortak `ClipPlayback` yardımcılarında.
- Takip confidence’ı `VideoFocusKeyframe` içinde saklanıyor; zayıf nokta ve lokal correction var.
- Takip ve authored zoom aynı geometry/evaluator hattında birleşiyor.
- Hold, push-in, pull-out ve punch kamera tarifleri source-time içinde saklanıyor.
- Reverse klipte kamera hareketinin timeline anlamı korunuyor.
- Freeze klipte kamera/track saati ilerlemiyor.
- Aynı recording’in farklı trim’leri birbirinin focus/camera verisini kullanmıyor.
- Takip ekranı kapanınca Vision task’leri iptal ediliyor.
- Track/Zoom yalnız eylem uygulanabilir klipte etkinleşiyor; medya hazırlanırken kamera metadata dokunuşu kaybolmuyor.
- Preview/export aynı framing geometry’sini kullanıyor.
- Build 68’in son commit’i [CI run 35006624862](https://github.com/mericorhay/CueTake/actions/runs/35006624862) ile uygulama derlemesi ve package testlerini geçti.

### Mevcut eksikler

- Genel `ToolDescriptor` registry yok; AI işlemleri ağırlıklı olarak `EditPlan.Operation` ve `AIDirector` üzerinden çalışıyor.
- Confidence düştüğünde otomatik yeniden bulma/re-identification yok.
- Track recipe aralığını Camera Lane’de taşıma/uzatma ve track’i başka hedefe bağlama eksik.
- Beat, ayak/impact ve doğal shake motoru kodlanmadı.
- Multicam, proxy, renk/HDR, chroma key, ses stem ve batch render tamamlanmadı.
- Sound Analysis, optical flow, Metal render pipeline, Background Tasks, MetricKit, App Intents ve CloudKit bağlı değil.
- Vision’ın gerçek iPhone düşük ışık, örtülme, motion blur ve kadrajdan çıkıp dönme benchmark’ı yapılmadı.

## Rakiplerden alınacak ders ve CueTake açığı

Rakiplerin resmi dokümanlarındaki özellikleri ürün beyanı olarak değerlendiriyoruz; bu sayfalar bağımsız kalite benchmark’ı değildir.

| Rakip | Pazardaki güçlü davranış | CueTake’in alacağı prensip | CueTake’in farklılaşacağı nokta |
|---|---|---|---|
| CapCut | Hızlı AI edit, auto reframe, motion tracking, beat ve sosyal format akışı | Tek dokunuş, hızlı öneri, platform çıktısı | Öneriyi gizli preset olarak değil, Camera Lane ve undo edilebilir recipe olarak gösterme |
| Captions | AI Edit/Co-editor, otomatik zoom, cut, caption, B-roll ve mobil akış | Kullanıcıdan az karar isteyen ilk taslak | Her otomatik kararın aralık, neden, confidence ve manuel düzeltme karşılığını verme |
| Descript | Transcript üzerinden kesme, filler/gap temizleme, AI edit ve konuşma odaklı akış | Metin ile video arasındaki bire bir bağ | Transcript akışını gerçek çok katmanlı timeline, kamera ve efekt graph’ına bağlama |
| Adobe Premiere | Mask/object tracking, çift yönlü ve kare bazlı düzeltme, auto reframe, position/scale/rotation/perspective | İleri/geri analiz, frame correction ve transform kanalları | Mobilde teknik panel kalabalığı olmadan aynı kontrolü üç makro kararla sunma |
| Final Cut Pro | ML + point-cloud tracking, orta örtülmeyi aşma, track verisini başlık/efekt/maska bağlama | Hibrit tracker ve yeniden kullanılabilir Motion Track | Aynı track’i kadraj, yazı, blur, overlay ve beat effect için tek seçimle kullanma |
| DaVinci Resolve | Magic Mask, IntelliTrack, Smart Reframe, Neural Engine, gelişmiş color/audio | Maske, güven, kalite doğrulaması ve ortak transform graph | Resolve karmaşıklığını mobilde confidence-first review ve basit makro kontrollerle çözme |

Resmî referanslar: [CapCut auto reframe](https://www.capcut.com/tools/auto-reframe), [Captions AI Edit](https://help.captions.ai/docs/project/ai-edit), [Descript Underlord](https://www.descript.com/underlord), [Premiere mask tracking](https://helpx.adobe.com/premiere/desktop/add-video-effects/work-with-masks/mask-tracking-tools.html), [Final Cut object tracking](https://support.apple.com/en-ca/guide/final-cut-pro/vere9b794f29/mac), [DaVinci Resolve](https://www.blackmagicdesign.com/products/davinciresolve).

### Rakip seviyesine yaklaşmak için en yüksek etkili birleşim

1. **Transcript-to-timeline:** kelimeyi veya cümleyi silince doğru source-time video, caption, ses ve effect aralığı birlikte değişir.
2. **One selection, reusable track:** kullanıcı bir kere boyar; aynı track kadraj, zoom, yazı, blur, sticker ve video layer’a bağlanabilir.
3. **Auto result with manual escape hatch:** otomatik sonuç tek dokunuşta gelir; sorun yalnız düşük güven aralığında açılır.
4. **Motion Graph:** takip, stabilization, zoom, beat/impact ve manuel offset ayrı katkılar olarak karışır; birbirini ezmez.
5. **Platform-ready output:** 9:16/1:1/4:5/16:9 aynı karardan güvenli alan ve kalite kontrolüyle çıkar.

## Birleşik öncelik planı

Öncelikler AI ve normal kullanıcı için ayrılmaz. Normal UI’nin yaptığı bütün güvenli işlemler AI tarafından aynı domain action’larıyla çağrılabilir.

### P0 — Güvenilir edit temeli

| İş | Normal kullanıcı deneyimi | AI işlemi | Teknik kabul koşulu |
|---|---|---|---|
| Timeline integrity | Kullanıcı bir klibi taşıdığında overlap, boşluk ve bağlı katmanlar görünür | `validateTimelineOperation`, `verifyTimelineIntegrity` | Caption/effect/audio zamanları kaybolmaz; başarısız işlem kısmi kalmaz |
| Split/trim/ripple | Playhead’e bas, split veya kenarı sürükle; klip uçları 44 pt hit area | `splitClip`, `trimClip`, `deleteRange`, `restoreOriginalRange` | Source-time doğru; tek undo grubunda geri alınır |
| Video layers | Layer liste değil, seçili klip inspector’ı; duration, source start, crop, opacity, volume | `updateVideoLayer`, `splitVideoLayer`, `moveClip`, `layoutVideos` | 50 klipte drag/scroll ayrılır; layer paneli preview/timeline’ın üstüne binmez |
| Caption timing | Kelime/phrase görünümünde metin konuşmadan önce çıkmaz; süre konuşma ve okuma hızına uyarlanır | `captionTiming`, `retimeCaptions`, `applyCaptionStyle` | Başlangıç erkenliği ve aşırı uzun kalma otomatik finding olarak raporlanır |
| Edit transaction | Her otomatik işlem öncesi özet, aralık ve geri alma görünür | `propose → approve → apply → verify` | Her action deterministik, idempotent ve tek undo transaction’a bağlı |

P0 tamamlanmadan yeni preset, efekt veya “agentic” davranış eklenmez.

### P0 — AI yürütme sistemi

`EditPlan` korunur; bunun üzerine aşağıdaki typed registry eklenir:

```text
ToolDescriptor {
  id: StableToolID
  intent: HumanReadableIntent
  arguments: CodableSchema
  preconditions: [Condition]
  sideEffects: [ProjectMutation]
  risk: none | reversible | destructive
  undoScope: action | plan
  progress: ProgressKind
  verifier: VerificationID
}
```

Her araç şu yaşam döngüsünü kullanır:

```text
proposed → validated → awaitingApproval → applied → verified
                                  ↘ failed → rollback / retry
```

AI output’unda teknik id gösterilmez. `editor.change.videoLayer` yerine `Motoru takip eden klip düzenlendi` görünür. Tool çıktısı sonraki tool için yapılandırılmış finding, confidence, changed range ve entity id taşır.

İlk registry grupları:

```text
Analyze:
  transcribe, detectSpeechGaps, detectFillers, detectRepetition,
  analyzeRoles, detectScenes, inspectFraming, inspectAudioMix

Timeline:
  splitClip, trimClip, deleteRange, restoreOriginalRange,
  moveClip, reorderClips, replaceClipSource, setSpeed, reverse

Captions:
  captionTiming, applyCaptionStyle, translateCaptions,
  captionWordHighlight, exportSubtitleSidecar

Camera:
  createSubjectTrack, correctSubjectTrack, bindTrackToTarget,
  suggestZoomRecipes, applyZoomRecipe, setCameraKeyframes,
  inspectTrackConfidence, detectMotionEvents

Visual:
  updateVideoLayer, layoutVideos, smartReframe, applyFilter,
  colorCorrect, backgroundCutout, replaceBackground,
  stabilizeVideo, addTransition

Audio:
  cleanVoice, splitAudioTracks, duckMusicUnderVoice,
  detectBeats, syncEditsToBeats, setMusicLevel, censorProfanity

Delivery:
  createOutputVariants, batchRender, verifyExportSource,
  renderQA, exportProject
```

AI, user dokunuşu ve workflow aynı action executor’ı kullanır. AI bir işlemi doğrudan `EditorModel` alanına yazmaz.

### P0 — Takip ve zoom’un sosyal video kalitesi

Mevcut Vision tracker korunur ve şu güvenli ekleme yapılır:

1. İnsan için yüz/kişi tespiti, genel nesne için foreground instance mask ile yeniden aday üret.
2. `VNTrackObjectRequest` confidence’ı düşerse `searching` durumuna geç; son güvenilir crop çevresinde aday ara.
3. Adayın konumu, boyutu, hareket vektörü ve görsel benzerliği yeterli olmadan yeniden bağlanma.
4. İki veya üç güvenilir frame görülmeden track’i “reacquired” sayma.
5. Emin olunmazsa en fazla iki aday göster; tüm videoyu yeniden seçtirme.
6. Optical flow yalnız belirsiz aralıkta fallback olarak çalışsın; sürekli analiz yapılmasın.
7. İnsanlarda body pose/hand pose, ayak vuruşu ve impact motoruna sinyal üretsin.

Takip çıktısı yalnız merkez değildir:

```text
TrackSample {
  sourceTime, bounds, center, scale, rotation?, perspective?,
  mask?, confidence, velocity, state
}
```

Zoom ve takip tek `Motion Graph` içinde birleşir:

```text
Base Framing
 + Stabilization Correction
 + Subject Follow
 + Zoom Envelope
 + Beat/Impact Impulse
 + Manual Offset
 → Constraint Solver
 → Camera Transform Track
 → Preview + Export
```

Manuel override en yüksek önceliktedir. Hold authored crop için minimum sınırdır; hareketli zoom takip crop’undan başlar. Çarpan çarpan zoom yapılmaz. Reverse klipte timeline anlamı korunur.

### P1 — Apple ile rakip parity

| İş | Kullanılacak Apple katmanı | Ürün sonucu |
|---|---|---|
| Multicam 2–3 kaynak | AVFoundation composition + Speech/audio waveform + Vision visual anchor | Clap/flash/waveform/manuel anchor ile sync, tek kamera grubu, güvenli angle switch |
| Proxy/adaptive preview | AVAssetReader/Writer + VideoToolbox + Background Tasks | 4K/8K preview akıcı; export özgün source hash’i doğrular |
| Renk/HDR | AVFoundation HDR + Core Image + Metal | Exposure, contrast, curves/LUT metadata, source/output color-space ve clipping kontrolü |
| Chroma/foreground | Vision masks + Core Image blend + Metal feather | Tolerance, spill, edge, hair/halo finding; kötü maskeyi sessizce export etmeme |
| Ses | SpeechAnalyzer + SoundAnalysis + Accelerate/vDSP + AVAudioEngine | Voice/music/ambience/SFX, denoise, ducking, beat/impact marker |
| Batch output | AVFoundation + Background Tasks + Live Activity | 9:16, 1:1, 4:5, 16:9 kuyruk; varyant başına QA |
| Gerçek cihaz kalite | MetricKit + OSLog/OSSignposter | Studio hitch, memory, hang, export crash, enerji ve cihaz sınıfı raporu |

İlk multicam sürümü iki veya üç kaynakla sınırlıdır. Altı kamera parity’si cihaz bellek ve UX ölçülmeden hedeflenmez.

### P1 — Normal kullanıcı araçları

- `keyframeTransform`: position, scale, rotation, opacity; otomatik veya manuel.
- `layoutVideos`: side-by-side, stacked, picture-in-picture, grid; safe-area solver.
- `stabilizeVideo`: crop/overscan bütçesiyle; subject follow’ı yok etmez.
- `colorCorrect`: exposure, contrast, highlights, shadows, saturation, warmth, tint, sharpness, vignette.
- `backgroundCutout`/`replaceBackground`: kişi/foreground mask, edge refine, before/after.
- `denoiseVoice`, `duckMusicUnderVoice`, `splitAudioTracks`.
- `addTransition`: cut/fade/crossfade/wipe; shot boundary ve caption sınırıyla uyumlu.
- `createOutputVariants`, `exportSRT/VTT`, `renderQA`.

Her biri aynı normal UI kontrolüyle ve AI tool’uyla erişilebilir. Bir özellik yalnız AI’dan çağrılabiliyor ama kullanıcı arayüzünde düzenlenemiyorsa P0 kabul edilmez.

## Apple entegrasyon planı

### A0 — Mevcut teknoloji için sağlamlaştırma

- AVFoundation composition/export için tek `RenderGeometry` ve tek source-time resolver.
- SpeechAnalyzer sonucu transcript, caption ve role analyzer’a tek normalize edilmiş zaman formatıyla girsin.
- Foundation Models prompt’ları `ToolDescriptor` listesini değil, bağlama uygun dar tool setini alsın.
- Vision task’leri priority, cancellation, progress ve cache key ile çalışsın.
- Core Image context ve pixel buffer yaşam döngüsü ana thread’i bloklamasın.

### A1 — En yüksek getirili eklemeler

1. `SoundAnalysis`: alkış, kahkaha, konuşma, müzik ve SFX event’leri.
2. `Accelerate/vDSP`: waveform enerji, onset ve beat marker’ları.
3. `VNGenerateOpticalFlowRequest`: yalnız confidence düşük kısa aralık için fallback.
4. Foreground/person instance mask: gerçek nesne sınırı ve mask tracking.
5. `BGContinuedProcessingTask`: kullanıcı başlattığı export/analysis uygulama arka plana geçince devam eder.
6. `MetricManager`/MetricKit: gerçek cihaz kalite ve enerji verisi.
7. `App Intents`: “Reels’e hazırla”, “son projeyi aç”, “altyazı ekle”, “export et” gibi eylemler.

Foundation Models tool calling için [Apple’ın resmi yaklaşımı](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling) kullanılmalı. SpeechAnalyzer asenkron modüller ve transcript akışları sağlar: [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer). Sound Analysis yüzlerce ses sınıfını ve özel Core ML sound classifier’ı destekler: [Sound Analysis](https://developer.apple.com/documentation/soundanalysis/). Uzun kullanıcı başlatmalı işlerin arka planda devamı için [BGContinuedProcessingTask](https://developer.apple.com/documentation/BackgroundTasks/performing-long-running-tasks-on-ios-and-ipados), gerçek cihaz diagnostikleri için [MetricKit](https://developer.apple.com/documentation/metrickit/monitoring-app-performance-with-metrickit) kullanılmalı.

### A2 — Kalite ve platform genişlemesi

- Metal compute/shader: blur, motion blur, tracked highlight, LUT ve mask performansı.
- VideoToolbox: codec seçimi, hardware decode/encode ve device capability gate.
- Core ML: hafif appearance embedding ile kayıp nesne identity kontrolü.
- CloudKit: önce project metadata, proxy, transcript ve history; ham video senkronu daha sonra.
- StoreKit 2: entitlement ve Pro özellikleri; tool sonuçları abonelik durumuna göre değil quality gate’e göre çalışmalı.
- Share Extension, Widgets ve Shortcuts: çekimden export’a sistem akışı.

SAM 2 gibi ağır açık kaynak model, iOS ana yoluna ilk aşamada eklenmez. Meta’nın video segmentation modeli güçlüdür, ancak mobil model boyutu, dönüştürme, enerji ve lisans/dağıtım benchmark’ı yapılmadan varsayılan tracker olamaz. [SAM 2 repository](https://github.com/facebookresearch/sam2)

## UX ve görsel sistem

### Tek ana ekran modeli

Studio ve Editor’da bilgi mimarisi sabit kalır:

```text
┌─────────────────────────────┐
│ Preview / camera transform   │  ← sonuç burada görülür
├─────────────────────────────┤
│ Context toolbar              │  ← yalnız seçili hedefin araçları
├─────────────────────────────┤
│ Timeline + active lanes      │  ← video/audio/caption/camera
├─────────────────────────────┤
│ Inspector bottom sheet       │  ← seçili action’ın üç makro kontrolü
└─────────────────────────────┘
```

Inspector preview’ın üstüne çıkmaz. Timeline açıldığında editor’ün altı boş kalmaz; panel seçili klibe bağlanır ve bottom sheet olarak yükselir. Kamera lane yalnız kamera verisi varsa veya kullanıcı açtıysa görünür.

### Kullanıcının her şeye erişme yolu

- Seçili klibin context toolbar’ı: `Düzenle`, `Takip`, `Zoom`, `Ses`, `Caption`, `Efekt`.
- Timeline lane’leri: Video, Caption, Audio, Camera; gereksiz lane’ler otomatik gizli.
- Global AI girişi: kullanıcı “şu klibi…” dediğinde playhead ve selection otomatik hedeflenir.
- Search/command sheet: tool adı değil insan diliyle arama (`kamerayı takip ettir`, `boşluğu kes`).
- Inspector `Temel` ve `Gelişmiş` olarak iki seviye; teknik değerler varsayılan ekranda yok.
- Her sonuç `Önce/Sonra`, `Uygula`, `Düzenle`, `Geri al` ile aynı yerde.

### Takip/zoom akışı

1. Kullanıcı preview’de `Takip` açar.
2. Yüz/kişi/nesne adayları hafif highlight olarak görünür.
3. Tap, kutu veya boya ile seçim yapılır; seçim sırasında oynatıcı kaybolmaz.
4. `Kadraj`, `Yazı/efekt`, `Blur`, `Overlay` hedefi seçilir.
5. `%10 / %15 / %20` ve `Sakin / Doğal / Canlı` varsayılan makrolardır.
6. Preview gerçek motion graph ile oynar; henüz project history’ye yazılmaz.
7. Apply tek undo transaction yazar.
8. Confidence düşükse yalnız problemli aralık amber olarak gösterilir; kullanıcı o frame’de yeniden boyar.

### Timeline etkileşimi

- Tap seçim içindir; tek tap öğeyi yukarı kaldırıp timeline’ı kilitlemez.
- Drag başlamadan önce 160–220 ms long-press ve 6–8 pt yön hysteresis vardır.
- Klip, parmağa 1:1 bağlı hareket eder; komşular fiziksel spring ile yer açar.
- Reorder sırasında “1 ↔ 3” gibi oklar kullanılmaz; gerçek klipler canlı olarak yer değiştirir.
- Trim tutamaçları en az 44 pt; görsel ince, hit area geniştir.
- Playhead dokunuşu ile inspector seçimi birbirini engellemez.
- Layer listesi ekranı dağıtmaz; yatay scroll veya üst üste binen floating panel yoktur.
- Haptic yalnız snap, apply, confidence correction ve başarılı export gibi anlamlı geçişlerde çalışır.

### Animasyon kuralları

- Aynı anda tek odak hareket eder; toolbar, ribbon, progress ve glow birlikte yarışmaz.
- Preview hareketleri UI spring’inden değil gerçek camera transform’dan beslenir.
- Apply: 180–260 ms settle; hata: amber crossfade; loading: determinate progress.
- Reduce Motion açıkken spring ve sürekli halo yerine opacity/crossfade kullanılır.
- VoiceOver her tool’u amaç, aralık, miktar ve sonuçla okur.
- Dynamic Type’da timeline item’ları metni kesmez; kritik ikonlara text label eşlik eder.

## AI davranış sözleşmesi

AI şu kuralları ihlal edemez:

1. Kullanıcının açık isteği olmadan destructive işlem yapamaz.
2. `proposed` sonucu preview edilmeden otomatik apply yapılamaz; düşük riskli toplu ayar için bile özet görünür.
3. Bir araç başarısız olursa kısmi timeline veya metadata bırakamaz.
4. Source range, selected take, locked lane ve media availability kontrol edilmeden çalışamaz.
5. Preview’da görünen sonuç export evaluator’ından farklı olamaz.
6. Confidence düşükse kesin cümle kuramaz; `emin değilim` ve düzeltme yolu göstermelidir.
7. Aynı kanal katkılarını çarpan şekilde üst üste bindiremez.
8. Kullanıcı manuel bir değeri değiştirdiyse AI bunu sessizce geri yazamaz.
9. Teknik symbol veya internal action key kullanıcıya gösterilemez.
10. Her AI planı tek bir undo transaction ve doğrulama raporuyla biter.

## Ölçülebilir kabul kriterleri

### Correctness

- Split, trim, reorder, speed, reverse, freeze, relaunch ve undo/redo sonrasında source-time verisi doğru kalır.
- Caption başlangıcı konuşmadan önce görünmez; doğal pause ile filler aynı sınıf sayılmaz.
- Preview/export center, scale, rotation, crop ve opacity açısından aynı evaluator sonucunu verir.
- Hiçbir export frame’inde NaN transform, negatif crop, siyah kenar veya kaynak dışı zaman oluşmaz.

### Performance

- Sıcak cache preview başlangıcı 100 ms, soğuk analiz progress’i görünür.
- 50 klipte timeline scroll ve drag ana thread’i kilitlemez.
- Track analizi uygulama kapanmadığı sürece cancellation’a yanıt verir.
- Gerçek cihazda CPU, memory, energy, hitch ve export süresi MetricKit ile ölçülür.

### Tracking quality

- Sosyal video test setinin en az %90’ında otomatik track manuel düzeltme istemez.
- Kalan kliplerde tüm videoyu yeniden seçmek yerine tek lokal correction yeterlidir.
- Düşük confidence noktası doğru source-time frame’inde gösterilir.
- Nesne kadrajdan çıkınca model sessizce başka nesneye bağlanmaz.

### UX

- Kullanıcı seçili action’ın nereye etki ettiğini tek bakışta görür.
- 44 pt hit target, VoiceOver, Dynamic Type ve Reduce Motion testleri geçer.
- Inspector hiçbir kritik timeline veya preview alanını kapatmaz.
- Otomatik öneri ilk bakışta anlaşılır: ne yaptı, neden yaptı, hangi aralık, nasıl geri alınır.

## Uygulama sırası

### Faz M0 — Tek action executor ve timeline güvenliği

`ToolDescriptor`, precondition, verifier, undo scope, rollback, finding/confidence ve source-time resolver ortaklaştırılır. Mevcut `EditPlan` bu executor’a adaptor ile bağlanır.

### Faz M1 — Caption + layer + Camera Lane UX

Adaptive caption timing, video layer duration/source start editing, split/trim drag, Camera Lane range editing ve inspector layout birlikte tamamlanır.

### Faz M2 — Takip kurtarma ve Motion Graph

Foreground/person mask, confidence state machine, re-detection, optical flow fallback, body pose, reusable track binding, zoom/impact/stabilization mixer.

### Faz M3 — Ses, multicam ve performans

SoundAnalysis/vDSP beat events, two/three-source multicam, proxy cache, Background Tasks, MetricKit ve export QA.

### Faz M4 — Apple sistem yüzeyi ve parity

Metal/VideoToolbox kalite hattı, HDR/color, chroma key, App Intents/Shortcuts, Share Extension, CloudKit metadata sync ve StoreKit 2.

Her fazın çıkış şartı: domain testleri, UI interaction testleri, gerçek cihaz benchmark’ı ve preview/export golden-frame doğrulaması. Sadece “buton görünüyor” bir özellik tamamlanmış sayılmaz.

## AI için kısa çalışma talimatı

Bu repo üzerinde yeni iş yaparken:

1. Önce bu rapordaki mevcut durum ve fazı oku.
2. P0 kuralını ihlal eden yeni bir P1/P2 feature ekleme.
3. Normal UI ve AI için aynı domain action’ı kullan.
4. Source-time ve preview/export parity’sini test et.
5. Kullanıcıya görünen teknik id üretme.
6. Her otomatik sonucu confidence, finding, changed range ve undo kapsamıyla doğrula.
7. Gerçek cihaz gerektiren sonucu simülatör başarısı gibi raporlama.
8. Build bump yalnız kod değişikliğinde yapılır; docs-only değişiklikte build aynı kalır.
