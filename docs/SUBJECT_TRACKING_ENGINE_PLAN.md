# CueTake Subject Tracking Engine

> Ürün, UX ve teknik mimari planı — 15 Eylül 2026
> Bu belge kodlama talimatı değildir. Buradaki “kesme”, timeline'da klip kesmek değil; görüntü içinden bir özneyi seçip hareketini izlemek ve kadrajı ona bağlamaktır.

## 1. Ürün vaadi

Kullanıcı videoyu durdurur, takip etmek istediği insanı, oyuncağı, motoru veya başka bir nesneyi oynatıcının üzerinde çember içine alır ya da boyar. CueTake seçimi anında görünür hâle getirir, klibin iki yönünde takip eder ve bu tek takip verisini şu işlerde tekrar kullanır:

- kadrajı özneye bağlama ve videoyu varsayılan olarak `%10–20` yakınlaştırma,
- özneye yazı, başka video, görsel, blur, vurgu veya efekt bağlama,
- dans adımı, nesne çarpması ya da müzik vuruşu gibi olaylardan doğal kamera darbeleri üretme,
- Zoom Engine'e güvenilir merkez, ölçek, yön ve olay sinyali sağlama,
- kullanıcı düzeltmesini bütün bağlı sonuçlara tek seferde yansıtma.

Temel deneyim “seç → izle → his ver” olmalı. Kullanıcı tracker kutuları, yüz noktaları, teknik anahtar kare listeleri veya ileri/geri oklarıyla uğraşmamalı.

## 2. Bugünkü CueTake altyapısı ve neden yetmiyor

Mevcut `SubjectTracker` yalnızca `VNDetectFaceRectanglesRequest` ile yüz arıyor, yaklaşık 0,5 saniyede bir örnek alıyor ve ana yüzü konum/yüzölçümü/güvenle seçiyor. Sonuç, `VideoFocusKeyframe` veya ana videonun reframe verisine dönüştürülüyor. Bu yapı yüz kadrajında işe yarayan bir başlangıçtır; oyuncak, araç, el, ayak ve serbest seçilmiş nesne için genel takip çekirdeği değildir.

İyi tarafları korunmalı:

- takip koordinatları kaynak videonun normalize uzayında tutuluyor,
- `VideoLayerComposer` focus ve placement verisini ayrı yorumluyor,
- yerleşim keyframe'leri ile otomatik takip birbirini ezmek zorunda değil,
- split, trim, hız değişimi ve klip sıralaması kaynak zamanına çevrilebilir.

Yeni motor mevcut yüz takibini silmemeli. Onu hızlı otomatik başlangıç sağlayan bir `FaceSeedProvider` adaptörüne dönüştürmeli.

## 3. Tasarım ilkeleri

1. **Doğrudan görüntü üzerinde seçim.** İş oynatıcıda başlar; ayrı bir teknik panelde başlamaz.
2. **İlk sonuç anlık hissedilir.** İlk kare maskesi hedef olarak 150 ms altında görünür; uzun analiz arka planda devam eder.
3. **Tek seçim, çok kullanım.** Takip verisi kadraja, zoom'a, maskeye ve efekte bağlanabilen bağımsız bir varlıktır.
4. **Güven görünür, hata sakin.** Motor emin değilse sessizce başka özneye atlamaz; sorunlu aralığı işaretler ve son güvenilir kadrajı korur.
5. **Kullanıcı düzeltmesi en güçlü sinyaldir.** Bir karede yeniden boyama, o noktada bir düzeltme çapası oluşturur ve yalnız gerekli aralığı yeniden hesaplar.
6. **Otomasyon geri alınabilir.** Analiz sonucu ham klibi ya da elle verilmiş yerleşimi değiştirmez.
7. **Hareket fiziksel hissedilir.** Rastgele titreşim yerine hız, ivme, darbe, sönüm ve kadraj payı olan bir hareket modeli kullanılır.
8. **Erişilebilir hareket.** Reduce Motion açıkken parıltı, salınım ve uçuşan geçişler sade opacity/crossfade karşılığına iner.

## 4. Ana kullanıcı akışı

### 4.1 Giriş

Oynatıcının araç şeridinde `TAKİP` görünür. Dokunulduğunda oynatıcı matched-geometry geçişiyle tam sahneye genişler; normal timeline, altında tek satırlık `Track Spine` film şeridine dönüşür. Alt panel ekranın en fazla `%28` yüksekliğini kullanır. Görüntünün üstünü kapatan büyük bir sheet açılmaz.

İlk cümle kısa ve eylem odaklıdır: **“Takip edeceğin şeyi işaretle.”**

### 4.2 Seçim araçları

Varsayılan araç `Çember`dir; kapalı ve kusursuz bir geometrik şekil çizme zorunluluğu yoktur. Diğer seçenekler:

- `Dokun`: belirgin özneyi tek dokunuşla seçer,
- `Çember`: nesneyi çevreleyen serbest lasso,
- `Boya +`: seçime alan ekler,
- `Sil −`: yanlış alanı çıkarır,
- `Kutu`: düşük dokulu veya hızlı nesne için sıkı başlangıç kutusu.

Çizgi CueTake coral renginde akar. Parmak kalktığında seçili alan lime tonunda yarı saydam bir “subject wash” ile dolar; arka görüntü `%22` kararır. Maskenin kenarında bir kez dolaşan ince ışık, seçimin tamamlandığını anlatır. Seçimin türünü güvenle tanıyamıyorsak yapay bir isim uydurmayız; `Özne 1` deriz. Kullanıcı isterse `Motor`, `Oyuncak` gibi yeniden adlandırır.

### 4.3 İlk sonuç ve analiz

`Takibi başlat` düğmesinden sonra:

- seçili özne çevresindeki halo 260 ms içinde sahneye oturur,
- mini timeline boyunca ilerleyen ince coral/lime çizgi analiz edilen bölümü gösterir,
- kullanıcı analiz tamamlanmadan işlenmiş kısmı oynatabilir,
- analiz iptal edilebilir ve kaldığı yer cache'den devam eder,
- ileri ve geri yön aynı seçim karesinden otomatik işlenir.

Tam ekran bloklayan yüzde sayacı kullanılmaz. Büyük projede kalan süre `~12 sn` gibi küçük bir durum metniyle verilir.

### 4.4 Sonuç ekranı

Varsayılan sonuç `Takipli Kadraj`dır. Motor, seçili öznenin etrafında çözünürlüğü koruyan `%10–20` yakınlaşma uygular. Alt panelde yalnız üç ana karar vardır:

| Kontrol | Varsayılan | Anlamı |
|---|---:|---|
| `Yakınlık` | `%15` | `%10 Güvenli`, `%15 Doğal`, `%20 Yakın` |
| `Hareket` | `Doğal` | `Sakin`, `Doğal`, `Canlı` takip tepkisi |
| `Kadro Payı` | `Otomatik` | bakış/hareket yönünde bırakılan boşluk |

`Bağla` çekmecesi takip verisini `Kadraj`, `Zoom`, `Yazı/Görsel`, `Efekt` veya `Sarsıntı` kanalına bağlar. Kullanıcı aynı track'i tekrar üretmez.

### 4.5 Hata düzeltme

Güven düşüşleri timeline üzerinde sarı küçük çentikler olarak görünür. Kullanıcı çentiğe dokunduğunda o kare büyür ve **“Burada kimi takip edelim?”** mesajı çıkar. Boyayarak düzelttiğinde:

1. düzeltme `TrackCorrectionAnchor` olarak kaydedilir,
2. önceki ve sonraki güvenilir çapalar arasındaki kısa bölüm yeniden analiz edilir,
3. geçiş iki tarafta yumuşatılır,
4. bağlı zoom ve efektler otomatik güncellenir.

Güven tamamen kaybolursa motor özneyi değiştirmez. Son güvenilir hareketi kısa süre tahmin eder, sonra kadrajı yavaşça güvenli merkeze bırakır. Ekrandan çıkan özne geri geldiğinde görünüm zıplamadan yeniden bağlanır.

## 5. “Vuruş” ve doğal sarsıntı deneyimi

`SARSINTI` bir filtre listesi değil, track'e bağlı hareket tarifidir.

### Otomatik tetik kaynakları

- `Ayak vuruşu`: insan vücudu pozu, ayak bileği/topuk hızının düşüşü ve alt zemin zarfı,
- `Darbe`: seçili özne çevresindeki ani optical-flow enerji değişimi,
- `Beat`: ses onset/beat işaretleri,
- `Manuel`: kullanıcı timeline üzerinde vuruş ekler.

İnsan olmayan nesnelerde motor “ayak vuruşu” iddiasında bulunmaz; `Darbe` veya `Beat` kullanır. Ses bulunmazsa görsel vuruş çalışmaya devam eder. Ses yalnız beat senkronu için ek kanıttır.

### Doğallık modeli

Her olay rastgele jitter değil, sönümlü bir kamera impulsu üretir:

- 30–60 ms kısa hazırlık,
- 70–110 ms ana darbe,
- 180–420 ms sönümlü dönüş,
- yoğunluğa bağlı çok küçük scale ve rotation eşliği,
- yüz ve yazı güvenli alanı koruması,
- siyah kenar oluşmasını engelleyen overscan bütçesi,
- art arda vuruşlarda toplam enerjiyi sınırlayan kompresör.

Makro kontroller `Hafif / Doğal / Sert`, `Sönüm` ve `Yön`dür. Gelişmiş görünümde genlik, decay, frekans, rotation ve scale contribution açılır. Kullanıcı her vuruşu dinleyip/izleyip silebilir; otomatik vuruşlar timeline üzerinde küçük lime noktalar hâlindedir.

## 6. Görsel sistem ve animasyon dili

Mevcut CueTake tokenları korunur:

- ekran `#0B0B0D`, sahne `#101014`, yüzey `#131317`,
- coral `#FF5A4F` aktif eylem ve çizim,
- lime `#E8FF4F` doğrulanmış seçim, başarılı takip ve vuruş işareti,
- ana metin `#F5F5F7`.

### Hareketler

| An | Animasyon | Süre / eğri |
|---|---|---|
| Oynatıcıdan takip sahnesine geçiş | matched geometry + kontrollü scale | `DS.Motion.settle` |
| Çizilen lasso | gerçek zamanlı stroke, parmağa 1:1 | animasyonsuz giriş |
| Maskenin kabulü | wash + tek edge sweep | 320 ms, `(0.22, 1, 0.36, 1)` |
| Track halo | konuma spring, boyuta yumuşak ramp | `snap` + 120 ms size filter |
| Crop penceresi | hafif overshoot olmadan yerleşme | `settle` |
| Güven kaybı | lime → amber renk geçişi | 180 ms |
| Vuruş önizlemesi | gerçek üretim impulsu | render ile aynı model |

Halo sürekli “nefes alıp” dikkat çalmamalı. Yalnız seçim beklerken çok düşük genlikli bir pulse çalışır. Analiz sırasında hareket comet çizgisinde kalır. Başarı haptic'i tek, hafif ve gecikmesizdir; her frame veya her vuruşta haptic verilmez.

## 7. Teknik mimari

### 7.1 Ortak veri modeli

```swift
struct TrackingSelection {
    let sourceAssetID: UUID
    let sourceTime: CMTime
    let positiveStrokes: [NormalizedStroke]
    let negativeStrokes: [NormalizedStroke]
    let fallbackBounds: CGRect
}

struct SubjectTrackSample {
    let sourceTime: CMTime
    let bounds: CGRect
    let centroid: CGPoint
    let rotation: Double?
    let maskReference: MaskReference?
    let confidence: Double
    let state: VisibilityState
}

struct MotionEvent {
    let sourceTime: CMTime
    let kind: EventKind       // footPlant, impact, beat, manual
    let strength: Double
    let direction: CGVector?
    let confidence: Double
}
```

`SubjectTrack` proje timeline zamanında değil, kaynak varlığın zamanında saklanır. Split, trim, reorder ve speed değişiklikleri görüntüleme sırasında dönüştürülür. Böylece bir klip bölündüğünde track kaybolmaz veya yeniden analiz edilmez.

### 7.2 Protokol sınırları

```text
SelectionInterpreter
  └─ SubjectSegmenting
       └─ ObjectTracking
            ├─ TrackRecovery
            ├─ MotionEventDetecting
            ├─ TrackSmoothing
            └─ TrackReducer

SubjectTrackStore → MotionGraph → Renderer / Zoom / Effects / Attachments
```

Motorlar somut Vision veya ML tiplerini Domain katmanına sızdırmamalı:

- `SubjectSegmenting`: stroke/kutu/noktadan ilk maske veya sıkı bounds,
- `ObjectTracking`: ardışık karelerde bounds/mask yayılımı,
- `TrackRecovery`: occlusion ve confidence düşüşünde yeniden bulma,
- `MotionEventDetecting`: pose, optical flow ve ses olaylarını birleştirme,
- `TrackSmoothing`: gürültüyü azaltırken bilinçli hızlı hareketi koruma,
- `TrackReducer`: renderer için az fakat anlamlı örnek üretme,
- `SubjectTrackStore`: sürümlü, iptal edilebilir, kaynak hash'ine bağlı cache.

### 7.3 Apple-first çalışma yolu

**iOS 26 tabanı:** Kullanıcının lasso/kutu alanı sıkı bir başlangıç kutusuna çevrilir ve `VNTrackObjectRequest`, `VNSequenceRequestHandler` ile ardışık karelerde yürütülür. Apple'ın örneği başlangıç kutusunun kalitesinin sonucu ciddi etkilediğini, işi arka planda yapmayı, düşük confidence'ta durmayı ve tracker'ı periyodik yeniden başlatmayı öneriyor. Bu nedenle her yaklaşık 10 karede bir güvenli yeniden seed ve her shot değişiminde kesin reset planlanır. [Apple: Tracking Multiple Objects or Rectangles in Video](https://developer.apple.com/documentation/Vision/tracking-multiple-objects-or-rectangles-in-video), [VNTrackObjectRequest](https://developer.apple.com/documentation/vision/vntrackobjectrequest)

`VNGenerateForegroundInstanceMaskRequest` belirgin foreground instance'larını ayırmak ve kullanıcı lasso'sunu sıkılaştırmak için denenir; sonuç alınmazsa kutu takibi engellenmez. [Apple: VNGenerateForegroundInstanceMaskRequest](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest)

`VNTrackOpticalFlowRequest` yalnız recovery, darbe algılama ve zor aralıklarda yardımcı sinyal olur. Apple bunu yüksek kaynak tüketimli olarak tanımlıyor ve eşzamanlı tek istek öneriyor; ana tracker olarak her karede zorunlu tutulmaz. [Apple: TrackOpticalFlowRequest](https://developer.apple.com/documentation/vision/trackopticalflowrequest)

**Yeni Vision için opsiyonel yol:** `GenerateIterativeSegmentationRequest` nokta, kutu ve scribble ile ekle/çıkar düzeltmelerini destekliyor; fakat güncel belgede beta ve indirilebilir asset gerektiriyor. Availability-gated bir `AppleIterativeSegmenter` olarak eklenmeli, minimum OS veya ilk sürümün zorunlu bağımlılığı yapılmamalı. [Apple: GenerateIterativeSegmentationRequest](https://developer.apple.com/documentation/vision/generateiterativesegmentationrequest), [WWDC26 image understanding](https://developer.apple.com/videos/play/wwdc2026/237/)

İnsan vuruşlarında Vision body pose'un bilek, diz, ayak bileği gibi normalize eklem noktaları ve confidence değerleri kullanılır. Apple, öznenin görüntü yüksekliğinin yaklaşık üçte birinden büyük olmasının ve ana gövde bölgelerinin görünmesinin doğruluğu artırdığını belirtiyor; bu koşullar sağlanmıyorsa UI otomatik olarak genel `Darbe` moduna düşer. [Apple: Detecting Human Body Poses](https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images)

### 7.4 Açık kaynak desteği: al, ölç, sonra göm

| Bileşen | Kullanım | Lisans | Karar |
|---|---|---|---|
| OpenCV 4.5+ | Lucas–Kanade/Farneback optical flow, feature motion, stabilizasyon prototipi | Apache 2.0 | Cihaz üstünde yalnız ölçüm sonucu Apple yolundan anlamlı biçimde iyiyse ekle |
| SAM 2.1 | point/box prompt ile masklet yayılımı, çoklu nesne ve yeniden prompt | Apache 2.0 | Mac/server kalite referansı ve zor-klip opsiyonu; PyTorch/CUDA yapısı nedeniyle ilk iPhone çekirdeği değil |
| MobileSAM | hafif ilk-kare segmentasyonu, ONNX export | repo lisansı ayrıca hukuk incelemesi | Core ML benchmark spike; ismine rağmen doğrudan üretim iOS çözümü varsayma |
| Cutie | etkileşimli video object segmentation ve kalıcı bellek yaklaşımı | repo/model lisansı ayrı doğrulanmalı | R&D benchmark; PyTorch/Ubuntu üretim bağımlılığı değil |

OpenCV'nin 4.5+ sürümleri resmi olarak Apache 2.0'dır ve optical flow/tracking/stabilization altyapısı sunar. [OpenCV lisansı](https://opencv.org/license/), [OpenCV optical flow](https://docs.opencv.org/4.x/d4/dee/tutorial_optical_flow.html) SAM 2 ise point/box prompt'larını video boyunca masklet olarak yayabiliyor ve çoklu nesneyi destekliyor; resmi repo model checkpoint ve kodu Apache 2.0 altında yayımlıyor. [Meta SAM 2](https://github.com/facebookresearch/sam2)

Üçüncü taraf modeli uygulamaya eklemeden önce binary boyutu, ilk sonuç süresi, A15/A17/M sınıfı cihaz FPS'i, bellek zirvesi, enerji ve lisans/model koşulları ayrı kapı kriteridir.

### 7.5 Analiz pipeline'ı

1. AVAssetReader ile orientation uygulanmış düşük çözünürlüklü preview frame'leri üret.
2. Seçim karesinde maskeyi/bounds'u çıkar.
3. Seçim karesinden ileri ve geri iki görev başlat; aynı decoder'ı yarışmalı kullanma.
4. Periyodik re-seed, shot-boundary reset ve confidence state machine uygula.
5. Zor aralıkta optical-flow ve appearance benzerliğiyle recovery dene.
6. Ham yolu One Euro veya Kalman filtresiyle hız duyarlı yumuşat.
7. Ramer–Douglas–Peucker benzeri reducer ile görsel hatayı aşmadan sample sayısını azalt.
8. Kaynak hash'i + engine sürümü + selection hash'i ile cache'le.
9. Export sırasında tam çözünürlükte yeniden segmentasyon gerektiren efekt varsa maskeyi refine et; salt kadraj için bounds yolu yeterlidir.

Preview ve export iki kalite profilidir. Preview gecikmesi düşük, export deterministik olmalıdır; aynı track kimliği kullanıldığı için kadraj sonucu değişmemelidir.

## 8. Ortak Motion Graph

Tracking Engine doğrudan video yerleşimini yazmaz. Şu sinyalleri üretir:

```text
subject.center(t)
subject.bounds(t)
subject.rotation(t)
subject.confidence(t)
subject.visibility(t)
event.impulse(t)
```

Zoom Engine ve renderer bunları şu katmanlarla birleştirir:

```text
Manual Override
  ↑ Zoom Envelope
  ↑ Subject Follow
  ↑ Shake Impulse
  ↑ Stabilization Correction
  ↑ Base Framing
```

Elle yapılan düzeltme en yüksek önceliğe sahiptir. Katmanlar toplanırken scale, rotation, hız, jerk ve overscan sınırları tek yerde uygulanır. Bu ayrım AI kurgu workflow'unu da korur: AI bir track üretebilir veya bir tarifi track'e bağlayabilir; ham placement keyframe'lerini körlemesine değiştiremez.

## 9. Rakip incelemesi ve vuracağımız boşluklar

| Ürün | Güçlü taraf | Kullanıcı yükü / boşluk | CueTake karşılığı |
|---|---|---|---|
| CapCut | arbitrary object motion tracking, auto reframe, scale/distance/direction, dinamik zoom ve shake | tracking, auto reframe, effect ve zoom farklı yüzeylerde; manuel keyframe hâlâ ayrı iş | tek seçimden kadraj + zoom + shake + attachment; tek düzeltme bütününe yayılır |
| Final Cut Pro | object tracker, Magnetic Mask, add/subtract seçim, çoklu maskeler, track verisini efekt/başlık/görsele bağlama | ileri/geri analiz kontrolleri ve inspector yapısı mobil kullanıcı için ağır; maske düzeltmesi keyframe'i bozabilir | yönleri otomatik analiz, confidence ribbon, splice correction, telefon için üç ana kontrol |
| Premiere / After Effects | mask tracking, position/scale/rotation/perspective, frame-level correction, motion attach ve stabilizasyon | teknik panel, tracking region ve çok sayıda keyframe uzmanlık ister | kullanıcı görüntüyü boyar; karmaşık track içeride kalır, yalnız sorunlu anlar görünür |
| DaVinci Resolve | Magic Mask, Smart Reframe, point/object tracking, 3D tracking | güçlü fakat Studio/cihaz kısıtları ve çok sayıda sayfa/palet | cihaz üstü ilk sonuç, aynı oynatıcı içinde seçim ve canlı sonuç |
| Captions | tek dokunuş AI Edit ile otomatik zoom/geçiş/B-roll | otomatik kararın nedenini ve hareket yolunu ince ayarlama sınırlı; güncel yardım sayfası tek konuşmacı/dikey/kısa içerikte daha iyi çalıştığını söylüyor | otomatik tarif + tam görünür track + tek kare düzeltme + genel nesne desteği |

Rakip verileri üreticilerin kendi sayfalarına dayanır: [CapCut Motion Tracking](https://www.capcut.com/tools/motion-tracking), [CapCut AI Movement Tracking](https://www.capcut.com/tools/ai-movement-tracking), [Final Cut Pro Object Tracking](https://support.apple.com/en-sg/guide/final-cut-pro/ver02684fa6a/mac), [Final Cut Pro Magnetic Mask](https://support.apple.com/en-au/guide/final-cut-pro/ver1d67e3a53/mac), [Premiere Mask Tracking](https://helpx.adobe.com/premiere/desktop/add-video-effects/work-with-masks/track-masks.html), [DaVinci Resolve Studio](https://www.blackmagicdesign.com/products/davinciresolve/studio), [Captions AI Edit](https://captions.ai/tools/ai-video-editor).

Buradaki “boşluk” sütunu, belgelenmiş özelliklerin akışlarından yaptığımız ürün çıkarımıdır; bağımsız performans testi sonucu değildir.

## 10. Uygulama fazları

### Faz T0 — Track domain ve kaynak-zamanı güvenliği

- `SubjectTrack`, selection, correction, event ve cache şeması,
- mevcut yüz takibinin adapter'a taşınması,
- split/trim/speed/reorder dönüşüm testleri,
- placement/focus migration ve eski projeyi açma.

**Çıkış koşulu:** Bir track üretmek elle verilmiş video layer konumunu değiştirmez; eski projeler aynı görünür.

### Faz T1 — Oynatıcı üstünde seçim ve genel nesne takibi

- tam sahne selection UX,
- lasso/box/paint UI,
- Vision box tracker, foreground-mask seed, ileri/geri analiz,
- confidence ribbon, cancel/resume, cache,
- `%10/15/20` takipli kadraj önizlemesi.

**Çıkış koşulu:** yüz, oyuncak ve motor örneklerinde ilk görünür seçim <150 ms; kısa klipte ilk takip önizlemesi <1 s; kayıpta yanlış özneye sessiz geçiş yok.

### Faz T2 — Düzeltme, occlusion ve çoklu özne

- correction anchor ve lokal splice,
- re-entry recovery,
- birden fazla track, yeniden adlandırma ve track binding,
- iki özne için group framing.

### Faz T3 — Vuruş motoru ve doğal shake

- pose foot-plant, generic impact ve audio beat dedektörleri,
- impulse synthesizer, crop guard, energy limiter,
- kullanıcı marker düzeltmesi ve Zoom Engine bağlantısı.

### Faz T4 — Segmentasyon kalitesi

- availability-gated Apple iterative segmentation,
- OpenCV/Core ML/SAM ailesi benchmarkları,
- yalnız ölçüm kapısını geçen backend'in ürünleştirilmesi.

## 11. Kalite ve kabul ölçütleri

- **Track doğruluğu:** IoU/center error, identity switch, lost-frame oranı.
- **Görüntü hissi:** crop center jerk, ani scale farkı, safe-area ihlali, siyah kenar frame sayısı.
- **UX:** selection-to-mask, selection-to-first-preview, correction-to-updated-preview süreleri.
- **Dayanıklılık:** occlusion, ekran dışına çıkış, benzer iki nesne, motion blur, düşük ışık, düşük texture, shot cut.
- **Kaynak yönetimi:** A15/A17/M sınıfı cihazlarda peak RAM, thermal state, enerji ve analiz FPS'i.
- **Kurgu bütünlüğü:** split, trim, speed, reorder, undo/redo, app relaunch ve export sonrası track eşleşmesi.
- **Erişilebilirlik:** VoiceOver seçim açıklaması, Dynamic Type paneli, Reduce Motion karşılığı, 44 pt minimum hedef.

Önerilen benchmark seti en az 120 kısa klip içermeli: insan yüz/gövde, dans ve ayak vuruşu, araç, oyuncak, hayvan, küçük nesne, benzer nesneler, kapanma, hızlı kamera, düşük ışık ve kadraj dışına çıkış. Altın sonuçlar elle işaretlenmeli; yalnız “güzel göründü” değerlendirmesiyle backend seçilmemeli.

## 12. Başlıca riskler ve ürün kararı

| Risk | Etki | Karar |
|---|---|---|
| Nesne kapanıyor veya kadrajdan çıkıyor | yanlış özneye atlama | confidence gate, freeze/predict, re-entry ve kullanıcı çengeli |
| Çok küçük/dokusuz nesne | tracker drift | sıkı kutu önerisi, uyarı, daha geniş crop payı |
| Lasso maskesi sistem sürümünde yok | seçim hissi bozulur | lasso → bounds yolu her zaman çalışır; gelişmiş maskeyi availability ile aç |
| Ağır model cihazı ısıtıyor | kötü preview/export | Apple-first hafif yol, kalite profilleri, cache, thermal throttling |
| Shake mide bulandırıyor veya amatör görünüyor | ürün kalitesi düşer | deterministic damped impulse, düşük varsayılan, face/text protect, Reduce Motion |
| Track, mevcut keyframe'i eziyor | kurgu bozulur | Motion Graph katmanları ve açık öncelik; user override kazanır |
| Açık kaynak lisansı/model koşulu belirsiz | dağıtım riski | dependency kabulünden önce kod ve weight lisansını ayrı incele |

## 13. AI tool yüzeyi

Motor tamamlandığında agentic kurguya şu küçük ve doğrulanabilir araçlar açılır:

- `createSubjectTrack(asset, time, selection)`
- `correctSubjectTrack(track, time, selection)`
- `bindTrack(track, target, mode)`
- `detectMotionEvents(track, kinds)`
- `applyShakeRecipe(events, recipe, range)`
- `inspectTrackConfidence(track)`

AI bilinmeyen nesneyi isimlendirmek zorunda değildir. Düşük confidence veya yüksek hareket maliyetinde sonucu uygulamak yerine kullanıcıya tek sorunlu kareyi açar. Her işlem preview, apply, verify ve tek-grup undo yaşam döngüsünü izler.
