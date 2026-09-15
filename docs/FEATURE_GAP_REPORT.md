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

### Tamamlanan son kod turu — build 68

Build 67’de takip güveni ve lokal düzeltme, build 68’de build 63 sonrasındaki Studio akışının geniş güvenlik taraması tamamlandı. Son düzeltmeler `c8241fb`, `aefab8b` ve `a6209e3` commit’lerindedir.

- `SubjectTrackingEditor.swift`: oynatıcıdan açılan tam ekran seçim yüzeyi; çember/boya gesture’ı, kaynak kare, `%10/%15/%20` yakınlık ve analiz durumu.
- `SubjectTracker.objectFocus`: seçilen bounds’tan Vision `VNTrackObjectRequest` ile ileri/geri genel nesne takibi; yüzle sınırlı değil.
- `EditorModel.trackSelectedSubject`: takip sonucunu recording’in source-time `reframe` verisine ekliyor; mevcut aralık dışındaki track noktalarını koruyor.
- Takip güveni `VideoFocusKeyframe.confidence` içinde kalıcı; tam ekran editörde confidence spine, zayıf nokta seçimi ve gerçek başarı aralığını değiştiren lokal ±2 saniye düzeltme var.
- `VideoPlacement.zoom`: eski projeler için optional, geriye dönük uyumlu zoom kanalı.
- `VideoFrameGeometry`: placement zoom’unu crop/focus hesabına katıyor; preview/export aynı geometriden geçiyor.
- `ToolDock`: `Takip` ve `Zoom` girişleri; zoom panelinde 1×, +%10, +%15, +%20 ve slider.
- `Localizable.xcstrings`: takip/zoom UX metinleri Türkçe ve İngilizce.
- `VideoFrameGeometryTests`: zoom’un crop alanını küçülttüğünü doğrulayan test.
- `CameraMotionRecipe`: sabit kadraj, `Yaklaş`, `Vurgu` ve `Geri açıl` hareketlerini recording source-time aralığında saklıyor.
- `CameraMotionEvaluator`: calm/natural/energetic eğrilerini preview, export ve timeline için tek noktada hesaplıyor.
- `VideoComposer`: focus track ile zoom recipe’yi aynı geometry pipeline’ında birleştiriyor; hareket mesafesini takibin güvenli crop değerine ekliyor, sabit kadrajı minimum crop olarak uyguluyor.
- `CameraMotionLane`: timeline’da uygulanan kamera hareketini ince lime–coral ribbon olarak gösteriyor.
- Zoom paneli: hareket tarifini uygula/kaldır ve ayrı sabit kadraj kontrolleri.
- Reverse ve freeze kliplerde source-time dönüşümü ortak `ClipPlayback` yardımcılarıyla yapılıyor; donmuş kare takip/zoom animasyonunu ilerletmiyor.
- Aynı recording’den farklı trim’ler birbirinin takip ve kamera verisini kullanmıyor; boş veya alakasız Camera Lane oluşmuyor.
- Push/pull yönü ters oynatılan kliplerde timeline yönüne göre adlandırılıyor ve render’da aynı anlamı koruyor.
- Takip ekranı kapanınca Vision görevleri iptal ediliyor; eski sonuç artık projeyi arka planda değiştiremiyor.
- Track/Zoom yalnız eylem uygulanabilecek klipte etkin; Track seçilen klibe gider ve yükleme sırasında kamera metadata dokunuşları kaybolmaz.
- Eski `zoom == nil` takip kareleri authored zoom’u 1×’e çekmiyor; ara karelerde zoom kanalı korunuyor.
- Domain, MediaEngine ve EditorFeature regresyon testleri source-time, reverse/freeze, confidence, birleşik zoom ve yükleme sırasındaki kamera düzenlemesini kapsıyor.

Build numarası `Config/CueTake.xcconfig` içinde **68**, marketing version **0.5.0**. Build 67 ve build 68 ara kapıları macOS CI’da geçti. Build 68’in son commit’i için uygulama derlemesi ve bütün package testlerini çalıştıran CI run’ı `35006624862` başarıyla tamamlandı.

### Henüz tamamlanmayanlar

- Vision tracker gerçek cihaz benchmark’ı yapılmadı; low texture, occlusion, benzer nesne, kadrajdan çıkma ve düşük ışık seti gerekiyor. Confidence ve lokal düzeltme hazır, ancak otomatik occlusion/re-entry politikası henüz yok.
- Vuruş/ayak basma/beat event motoru henüz kodlanmadı.
- Zoom recipe ve Camera Lane’in ilk sürümü var; recipe aralığını timeline’da elle uzatma/taşıma, gelişmiş feel kontrolü, subject binding, transition ve event mix henüz yok.
- AI registry’ye tracking/zoom tool’ları henüz bağlanmadı.
- Multicam, proxy, renk/HDR, chroma key, ses stem ve batch render bu raporun sonraki feature fazlarıdır.
- TestFlight otomasyonu daha önce iptal edildi; bu doküman güncellemesi TestFlight çalıştırmaz.

## Önerilen uygulama sırası

1. Occlusion/re-entry ve yanlış özneye atlamama politikasını gerçek cihaz benchmark’ıyla tamamla.
2. Zoom recipe aralığı düzenleme, subject binding ve Camera Lane seçim UX’ini tamamla.
3. Görsel impact, ayak basma ve beat event’lerini ortak doğal shake/zoom impulse kanalına bağla.
4. AI registry ve validator’ları bu iki motorla bağla.
5. Timeline multicam/proxy, sonra renk/HDR/chroma/audio/batch fazlarına geç.

Bu sıra, önce kullanıcıya görünen büyüyü ve güvenli geri dönüşü kurar; ağır masaüstü parity’si, temel timeline ve kaynak-zamanı güvenliği kanıtlandıktan sonra eklenir.
