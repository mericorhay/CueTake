# CueTake Feature Gap Report

> Masaüstü–mobil karşılaştırması, önerilen ürün kapsamı ve mevcut kod durumu  
> Güncelleme: 15 Eylül 2026

Bu rapor, gönderilen masaüstü video düzenleyici araştırmasını ürün kararına çevirir. AI’ın çağıracağı araçların ayrıntılı sözleşmesi [AI_TOOL_LIST_ROADMAP.md](AI_TOOL_LIST_ROADMAP.md) içindedir. Görsel takip ve zoom’un UX/engine planları ise [SUBJECT_TRACKING_ENGINE_PLAN.md](SUBJECT_TRACKING_ENGINE_PLAN.md) ve [ZOOM_ENGINE_PLAN.md](ZOOM_ENGINE_PLAN.md) içindedir.

## Yönetici özeti

Premiere Pro, Final Cut Pro, DaVinci Resolve, PowerDirector, Pinnacle Studio ve Filmora gibi masaüstü editörler; çok katmanlı timeline, multicam, proxy, renk grading, VFX, gelişmiş ses, plugin/script, batch render, donanım hızlandırma ve proje işbirliği sunuyor. Mobil uygulamalar çoğunlukla hızlı sosyal içerik üretimine odaklandığından ana klip keyframe’i, HDR, gelişmiş chroma key, proxy ve kapsamlı ses/timeline kontrollerinde geride kalıyor.

CueTake’in hedefi masaüstünü küçük ekrana aynen taşımak değil. Mobilde kaybolmayı önleyen katmanlı bir timeline, source-time güvenliği, ortak Motion Graph, açıklanabilir AI önerileri ve gerektiğinde gelişmiş panellerle profesyonel sonucu taşımak.

Önerilen MVP sırası:

1. güvenilir çok parçalı timeline ve temel kamera/transform keyframe,
2. iki/üç kaynaklı multicam senkronu,
3. proxy ve adaptif preview,
4. temel renk düzeltme + HDR doğrulama,
5. chroma key ve foreground mask,
6. ses stem’leri, denoise, ducking ve beat sync,
7. stabilizasyon, temel VFX ve batch platform çıktıları.

## Metodoloji ve güven seviyesi

Karşılaştırma resmi ürün sayfaları, kullanım kılavuzları, sürüm notları ve kullanıcı geri bildirimlerinden çıkarılmış bir yönlendirme çalışmasıdır. Özellik tabloları aynı sürüm, cihaz ve lisans koşullarında bağımsız benchmark değildir. “Masaüstünde var” bilgisi mobilde aynı performansı veya aynı UX’i garanti etmez. AI önceliği, her özellik CueTake üzerinde ölçülüp doğrulandıktan sonra kesinleşmelidir.

## Özellik matrisi

| Alan | Masaüstü pazarı | Mobil pazardaki tipik durum | CueTake kararı |
|---|---|---|---|
| Çok katmanlı timeline | Birçok video/audio track, nested/compound timeline | Katman sayısı ve ana timeline kontrolü sınırlı | P0: track lane’leri, kilit, solo/mute, source-time ripple |
| Çoklu kamera | 2–6+ kamera senkronu ve angle switching | Nadiren var; Premiere Rush’ta multicam yok | P1: önce 2–3 kaynak, ses + clap/flash + manuel anchor |
| Proxy/optimizasyon | 4K/8K için proxy, cache, optimized media | Çoğunlukla yok veya görünmez | P1: adaptif preview, cache ve export source doğrulaması |
| Renk düzeltme | Curves, wheels, LUT, HDR, tracked secondary | Filtre ve az sayıda slider | P1: exposure/contrast/saturation/warmth + LUT metadata + HDR kapısı |
| VFX/kompozit | Node tabanlı Fusion/AE, tracking, mask, particles | Hazır efekt, basit chroma key | P1: chroma key, foreground mask, temel mask/blur; node graph sonraki aşama |
| Ses miksajı | Çok kanallı mixer, Fairlight, ADR, ducking | Stereo seviye ve birkaç temel efekt | P1: voice/music/ambience/SFX stem, denoise, ducking, beat marker |
| Eklenti/SDK | Plugin, OpenFX/VST, script API | Kapalı ekosistem | P2: önce güvenli ToolDescriptor/sandbox; plugin marketplace MVP değil |
| Batch/otomasyon | Render queue, Media Encoder, script ve toplu dönüşüm | Genelde tek export | P1: platform varyant kuyruğu + her çıktı için QA raporu |
| Donanım hızlandırma | CUDA/Metal/QuickSync ve GPU pipeline | Donanım encode var, ağır efektte ısı/performans sorunu | P0 altyapı: thermal-aware kalite ve ortak preview/export evaluator |
| Proje paylaşımı | Cloud project, collaboration, versioning | Sınırlı paylaşım/export | P2: önce deterministik proje dosyası ve conflict-safe history |
| Ana klip keyframe | Position, scale, rotation, opacity, crop eğrileri | Mobilde çoğu kez overlay ile sınırlı | P0/P1: Camera Lane, recipe + açık manuel keyframe |
| HDR/dinamik aralık | HDR çalışma alanı ve export kontrolü | Sürüm/codec bağımlı, sık SDR’ye düşüyor | P1: kaynak/output renk uzayı ve clipping uyarısı |
| Yeşil perde | Ultra Key, spill suppression, tracked mask | Basit tolerance/key | P1: keyColorRange, edge refine, quality finding |
| Stabilizasyon | Warp/gyro/optical-flow tabanlı seçenekler | Basit stabilize veya preset | P1: crop bütçeli, güvenli, ayrı correction kanalı |

## Detaylı ürün kapsamı

### 1. Çok parçalı timeline — P0

Kullanıcı aynı anda ana video, ek video, caption, görsel, efekt, müzik ve SFX görebilmeli. Her lane’in kilit, görünürlük, solo/mute ve seçili hedef durumu olmalı. Timeline bir liste gibi uzamak yerine odaklanılan lane’i yükseltmeli; seçili klibin paneli timeline’ın üstüne binmemeli.

AI için gerekli işlemler: `addTrack`, `lockTrack`, `muteTrack`, `soloTrack`, `moveClip`, `rippleDelete`, `splitClip`, `verifyOverlap`. 50 klip ve çoklu katmanda hit area, scroll ve drag davranışı profillenmeli.

### 2. Multicam — P1

İlk sürümde iki/üç kaynağı ses waveform, clap/flash, ortak hareket veya manuel anchor ile hizala. Kullanıcı multicam grubunu tek bir “kamera grubu” chip’i olarak görmeli; angle değiştirmek yeni klip kopyalamamalı. AI yalnız güvenli geçiş önerir, tüm açıları sessizce değiştirmez.

Gerekli korumalar: drift tespiti, eksik ses fallback’i, farklı frame rate uyarısı, caption/audio zamanını koruma, tek undo grubu.

### 3. Proxy ve performans — P1

Proxy geçici, source hash’ine bağlı ve export’tan önce doğrulanabilir olmalı. AI işlem öncesi tahmini süre, bellek ve thermal maliyetini bilir. Preview düşük çözünürlükte çalışırken final render özgün kaynağa döner. Kullanıcı “neden bulanık?” sorusunu kalite chip’inden anlayabilmeli.

### 4. Renk ve HDR — P1

İlk panel exposure, contrast, highlights, shadows, saturation, warmth, tint, sharpness ve vignette içerir. Before/after hold preview zorunludur. HDR’de source color space, output space, clipping ve SDR fallback kontrol edilir. Node graph, sınırsız secondary correction ve plugin LUT marketi daha sonraya bırakılır.

### 5. VFX, chroma key ve mask — P1

Yeşil perde için renk seçimi, tolerance, spill suppression, edge softness ve feather gerekir. Foreground mask seçimi insanla sınırlı kalmamalı; Subject Tracking Engine’in nesne seçimiyle ortak çalışmalıdır. Kenar halo, delik, saç ve düşük confidence bir finding olarak gösterilir. Kullanıcı kötü maskeyi fark etmeden export’a gönderilmez.

### 6. Ses — P1

Voice, music, ambience ve SFX ayrı mantıksal stem’ler olarak timeline’da görünür. Denoise, echo/wind/hum azaltma ve voice enhancement before/after dinlenir. Ducking konuşma ve caption timing’iyle uyumlu envelope üretir. Beat marker’ları zoom, cut, transition ve shake motorlarına sinyal verir. Ses olmayan videoda görsel analiz çalışır.

### 7. Stabilizasyon ve temel VFX — P1

Stabilizasyon bağımsız bir correction channel olmalı; Subject Follow ve kullanıcı kamera hareketini yok etmemeli. Crop/overscan bütçesi aşılırsa yoğunluk azaltılmalı veya açık uyarı gösterilmeli. İlk VFX seti motion blur, zoom blur, blur/spotlight, basic mask ve tracked highlight’tır. Particles, 3D compositing ve tam node graph P2’dir.

### 8. Batch render, otomasyon ve paylaşım — P1/P2

Önce 9:16, 1:1, 4:5 ve 16:9 varyantlarını aynı recipe/brand kit ile kuyruğa al. Her varyant için crop, caption safe area, audio, HDR ve kaynak doğrulaması raporlanır. Proje collaboration, cloud conflict çözümü ve plugin SDK ancak yerel history ve ToolDescriptor güvenliği oturduktan sonra ele alınır.

## UX kuralları

- AI veya otomatik feature hiçbir şeyi sessizce uygulamaz; amaç, aralık, confidence ve geri alma görünür.
- Varsayılan panelde üç makro karar; gelişmiş teknik parametreler isteğe bağlı.
- Timeline, preview ve inspector aynı anda birbirinin üstüne binmez.
- Otomatik sonuç gerçek bir öneri olarak oynatılır; kabul edilince tek undo grubuna yazılır.
- Source-time veri split, trim, speed, reverse ve reorder sonrasında korunur.
- Preview ile export aynı geometry/evaluator yolunu kullanır.
- Reduce Motion, VoiceOver, Dynamic Type ve 44 pt hit target zorunludur.

## Mevcut kodda tam olarak nerede kaldık

### Tamamlanan son kod turu — build 65

Son kod commit’i `a754552 feat(editor): add direct subject tracking and zoom`.

- `SubjectTrackingEditor.swift`: oynatıcıdan açılan tam ekran seçim yüzeyi; çember/boya gesture’ı, kaynak kare, `%10/%15/%20` yakınlık ve analiz durumu.
- `SubjectTracker.objectFocus`: seçilen bounds’tan Vision `VNTrackObjectRequest` ile ileri/geri genel nesne takibi; yüzle sınırlı değil.
- `EditorModel.trackSelectedSubject`: takip sonucunu recording’in source-time `reframe` verisine ekliyor; mevcut aralık dışındaki track noktalarını koruyor.
- `VideoPlacement.zoom`: eski projeler için optional, geriye dönük uyumlu zoom kanalı.
- `VideoFrameGeometry`: placement zoom’unu crop/focus hesabına katıyor; preview/export aynı geometriden geçiyor.
- `ToolDock`: `Takip` ve `Zoom` girişleri; zoom panelinde 1×, +%10, +%15, +%20 ve slider.
- `Localizable.xcstrings`: takip/zoom UX metinleri Türkçe ve İngilizce.
- `VideoFrameGeometryTests`: zoom’un crop alanını küçülttüğünü doğrulayan test.

Build numarası `Config/CueTake.xcconfig` içinde **65**, marketing version **0.5.0**. Bu turdaki son dokümantasyon commit’i `f3673e9`.

### Henüz tamamlanmayanlar

- macOS üzerinde Xcode build/test çalıştırılmadı; Windows ortamında `swift`/`xcodebuild` yok. CI sonucu alınmadan bu dikey dilim tamamlanmış kabul edilmemeli.
- Vision tracker gerçek cihaz benchmark’ı yapılmadı; low texture, occlusion, benzer nesne, kadrajdan çıkma ve düşük ışık seti gerekiyor.
- Vuruş/ayak basma/beat event motoru henüz kodlanmadı.
- Zoom şu an ilk dikey dilimde statik ana placement kanalıdır; tarif galerisi, Camera Lane, recipe eğrileri ve event mix henüz yok.
- AI registry’ye tracking/zoom tool’ları henüz bağlanmadı.
- Multicam, proxy, renk/HDR, chroma key, ses stem ve batch render bu raporun sonraki feature fazlarıdır.
- TestFlight otomasyonu daha önce iptal edildi; bu doküman güncellemesi TestFlight çalıştırmaz.

## Önerilen uygulama sırası

1. macOS CI derlemesini çalıştır, Swift/Vision API hatalarını temizle.
2. `SubjectTrack` ve `CameraTransform` verisini ayrı domain primitive’lerine çıkar; mevcut yüz `reframe` verisi için migration yaz.
3. Track correction, confidence ribbon, occlusion/re-entry ve doğal event/shake motorunu tamamla.
4. Zoom recipe + Camera Lane + preview/export parity’sini tamamla.
5. AI registry ve validator’ları bu iki motorla bağla.
6. Timeline multicam/proxy, sonra renk/HDR/chroma/audio/batch fazlarına geç.

Bu sıra, önce kullanıcıya görünen büyüyü ve güvenli geri dönüşü kurar; ağır masaüstü parity’si, temel timeline ve kaynak-zamanı güvenliği kanıtlandıktan sonra eklenir.

