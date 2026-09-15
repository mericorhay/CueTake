# CueTake Zoom Engine

> **Ana ürün otoritesi:** [CUETAKE_MASTER_PRODUCT_PLAN.md](CUETAKE_MASTER_PRODUCT_PLAN.md). Bu dosya zoom/motion motorunun ayrıntılı teknik ekidir.

> Ürün, UX ve teknik mimari planı — 15 Eylül 2026
> Zoom Engine, Subject Tracking Engine ile ortak Motion Graph üzerinde çalışan fakat onsuz da manuel ve otomatik zoom üretebilen bağımsız bir araçtır.

## 1. Ürün vaadi

Zoom, yalnızca scale keyframe eklemek değildir. CueTake Zoom Engine anlatının vurgusunu, seçili öznenin hareketini, çıktı oranını, kaynak çözünürlüğünü, yazı/yüz güvenli alanını ve vuruşları birlikte değerlendirerek editör kalitesinde kamera hareketi üretir.

Kullanıcı şu üç düzeyden istediğinde durabilir:

1. bir hareket tarifine dokunup sonucu kabul eder,
2. `Miktar / Süre / His` ile tarifi düzenler,
3. gelişmiş görünümde anchor, eğri ve zaman işaretlerini değiştirir.

İlk iki düzeyde grafik editörü veya ham keyframe listesi gösterilmez.

## 2. Kapsam: tek motorda bulunacak zoom ailesi

### Temel hareketler

- **Sabit yakınlık:** seçili aralıkta anlık veya yumuşak `%5–200` ölçek; sosyal video varsayılanı `%10–20`.
- **Push In / Pull Out:** kontrollü yaklaşma ve uzaklaşma.
- **Punch In / Punch Out:** kısa, vurgu amaçlı giriş ve geri dönüş.
- **Crash Zoom:** yüksek hızlı, hafif motion blur destekli yaklaşma/uzaklaşma.
- **Hold + Release:** yaklaşıp konuşma/vurgu boyunca tutma, sonra çıkma.
- **Ken Burns:** durağan veya düşük hareketli görüntüde pan + zoom.
- **Optical/Lens hissi:** scale, hafif radial blur, exposure/vignette eşliği; gerçek optik zoom iddiası taşımaz.
- **Zoom transition:** iki klibin kesme noktasında yön ve hız eşleyen zoom-in/out geçişi.
- **Zoom blur:** yalnız hareket fazında artıp duruşta sıfırlanan blur.
- **Dolly/Vertigo simülasyonu:** subject scale korunurken arka plan perspektif hissini 2D transform/depth ile yaklaşık üretir; depth yoksa açıkça `Simülasyon` olarak adlandırılır.

### Akıllı hareketler

- **Follow Zoom:** Subject Track merkez/bounds verisine bağlı yaklaşma.
- **Auto Reframe:** 9:16, 1:1, 4:5, 16:9 ve özel oranlarda özneyi koruyan kadraj.
- **Group Framing:** iki veya daha fazla track'i güvenli kutuda tutar; ayrışınca genişler, yaklaşınca daralır.
- **Speaker Focus:** konuşan kişi track'ine sakin push/pull; kimlik değişiminde hard cut veya kontrollü handoff.
- **Emphasis Zoom:** transcript rolü, hook, CTA, soru, sayı veya vurgu olayına tarif bağlar.
- **Beat / Impact Zoom:** ses beat'i veya Tracking Engine `MotionEvent` sinyaliyle punch/impulse.
- **Motion Match:** nesnenin hareket yönü ve hızıyla zoom merkezini/tempo'yu eşler.
- **Shot-aware Zoom:** sahne kesiminde eğriyi resetler; bilinçli transition dışında iki shot üzerinden kesintisiz keyframe taşımaz.
- **Stabilized Follow:** kamera sallantısını azaltırken istenen subject hareketini korur.

### Profesyonel kontroller

- focus anchor ve follow offset,
- başlangıç/bitiş/hold süresi,
- amount, speed, direction,
- easing: linear, ease, smooth, cinematic, elastic kontrollü,
- anticipation ve overshoot,
- scale/position/rotation ayrı contribution,
- look-ahead, dead zone, follow lag,
- crop/overscan budget ve çözünürlük sınırı,
- face, caption ve overlay safe-area protection,
- motion blur shutter hissi,
- loop, reverse, mirror recipe,
- manuel keyframe ve segment bazlı curve edit,
- tarif kaydetme ve proje içinde tekrar kullanma.

## 3. Ana UX

### 3.1 Giriş ve sahne

Oynatıcı araç şeridindeki `ZOOM` düğmesi, görüntüyü aynı yerde tutup alt timeline'ı `Camera Lane`e dönüştürür. Kullanıcı hangi klipte ve hangi zamanda olduğunu kaybetmez. Büyük modal veya oynatıcının üstünü kapatan ayar kutusu kullanılmaz.

Görüntünün üzerinde küçük bir `Focus Orb` belirir. Kullanıcı orb'a dokunarak zoom merkezini değiştirir; bir Subject Track varsa orb öznenin adıyla bağlanır: `Takip: Motor`. Orb'un izi yalnız düzenleme sırasında görünür, export edilmez.

### 3.2 Tarif galerisi

İlk şerit yedi canlı thumbnail içerir:

1. `Sakin Yaklaş`
2. `Vurgu`
3. `Geri Açıl`
4. `Takip Et`
5. `Vuruş`
6. `Ken Burns`
7. `Geçiş`

Thumbnail'lar kendi gerçek hareket eğrisini 1,2 saniyelik sessiz loop ile gösterir. Aynı anda yalnız ekrandaki iki veya üç thumbnail animasyon çalıştırır. Reduce Motion'da başlangıç/son kare arasında crossfade kullanılır.

Bir tarife dokunmak anında non-destructive preview başlatır. Uygulanmış gibi görünür fakat `Bitti` denmeden proje history'sine tek undo grubu olarak yazılmaz.

### 3.3 Üç makro kontrol

Tarif seçilince alt panelde:

| Kontrol | Görev |
|---|---|
| `Miktar` | scale değişimi; varsayılan `%15` |
| `Süre` | seçili aralık veya 0,25–8 sn |
| `His` | `Sakin / Doğal / Canlı / Sert` motion profile |

`His`, rastgele preset değildir; hız, acceleration, jerk, anticipation, overshoot ve damping için kontrollü bir profil seçer.

### 3.4 Camera Lane

Normal timeline'ın hemen üstünde 28–36 pt yüksekliğinde ince bir kamera şeridi açılır:

- zoom miktarı dolu bir eğri/ribbon olarak görünür,
- hold bölgeleri düz plato,
- punch olayları damla biçimli marker,
- takip bağı küçük subject chip'i,
- güven sorunu amber kesik çizgi,
- klip kesimleri dik sınırdır.

Hareketin başı veya sonu sürüklendiğinde süre değişir. Tüm blok sürüklendiğinde zaman değişir. Tutamaçlar en az 44 pt hit area'ya sahiptir fakat görsel olarak ince kalır. Timeline scroll ile zoom bloğu sürükleme arasında 6–8 pt yön kilidi ve kısa hysteresis bulunur; bir dokunuş öğeyi havaya kaldırıp timeline'ı kilitlemez.

### 3.5 Manuel mod

`Elle` seçildiğinde pinch hareketi mevcut zamanda açık bir keyframe oluşturur. Kullanıcıya ilk pinch'te küçük bir toast gösterilir: `Başlangıç karesi eklendi`. Playhead başka zamana taşınıp tekrar pinch yapılınca ikinci keyframe oluşur ve aradaki ribbon görünür.

Gizli veya her dokunuşta otomatik keyframe üretilmez. `Gelişmiş` açılınca mini curve editor gelir; varsayılan görünümde curve handle yoktur.

### 3.6 A/B ve geri dönüş

Preview üzerinde `Önce` düğmesine basılı tutulunca orijinal kadraj gösterilir; bırakınca zoom sonucu geri gelir. Bu davranış render ile aynı frame geometry yolunu kullanır. `Sıfırla` yalnız seçili zoom tarifini kaldırır, track'i veya diğer efektleri silmez.

## 4. Tracking Engine ile ortak deneyim

Zoom bağımsız çalışır; track bağlandığında güçlenir:

- Focus Orb, `SubjectTrack.center` ve `bounds` yolunu izler.
- `Yakınlık %15`, sabit scale değil, öznenin kadrajdaki hedef doluluk oranıdır.
- bakış/hareket yönünde lead room bırakılır.
- takip confidence'ı düşünce zoom agresifleşmez; mevcut merkezi korur ve gerekirse yumuşakça güvenli merkeze döner.
- kullanıcı orb'u track'ten uzağa sürüklerse bağ kopmaz; `follow offset` kaydedilir.
- `Bağı Ayır` track'i silmeden yalnız zoom bağlantısını kaldırır.
- Tracking Engine event'leri Vuruş zoom ve shake'i aynı zamanda tetikleyebilir.

İki motor tek ekranda birleştiğinde kontrol sırası `Özne → Kadraj → Hareket → Vuruş` olur. Kullanıcı araçlar arasında gidip yeniden seçim yapmaz.

## 5. Hareketin doğal görünme kuralları

### 5.1 Kinematik sınırlar

Her tarif normalize edilmiş bir kamera dönüşümü üretir:

```text
CameraTransform(t) = center(x,y) + scale + rotation + optional blur
```

Composer şunları sınırlar:

- scale velocity,
- pan velocity,
- acceleration,
- jerk,
- rotation velocity,
- edge overscan,
- minimum export resolution.

Varsayılan sosyal video zoom'u `%10–20` aralığındadır. Daha büyük yakınlaşma kullanıcı tarafından bilinçli seçilir ve çıktı çözünürlüğü zayıflıyorsa `Kalite düşebilir` işareti miktar slider'ında ilgili noktada görünür.

### 5.2 Follow filtresi

- Küçük subject hareketleri için dead zone,
- hızlı yön değişiminde hız-duyarlı One Euro/Kalman filtresi,
- 4–10 frame look-ahead ile gecikme hissini azaltma,
- scale değişiminde center'dan daha uzun smoothing,
- pan ve zoom için ayrı damping,
- kadraj sınırında sert clamp yerine soft boundary.

Bu sayede özne nefes aldığında görüntü titremez; sahnede koştuğunda kamera geride kalmaz.

### 5.3 Editoryal kurallar

- Hook/CTA zoom'u kelimenin başladığı frame'de patlamaz; 80–160 ms anticipation ile hazırlanır.
- Aynı cümlede sürekli punch yapılmaz; minimum cooldown ve enerji bütçesi vardır.
- Hard cut çevresindeki 2–4 frame'de eski track devam ettirilmez.
- Caption'a yaklaşan yüz veya odak noktası varsa framing safe-area solver devreye girer.
- Birden fazla otomatik öneri çakışırsa en yüksek editoryal önem kalır; scale katkıları üst üste çarpılarak aşırı zoom oluşturmaz.

## 6. Animasyon ve görsel dil

Mevcut CueTake paleti ve motion tokenları kullanılır: `#0B0B0D` ekran, `#101014` kamera, `#131317` surface, `#FF5A4F` aktif hareket, `#E8FF4F` bağlı/doğrulanmış sinyal ve `#F5F5F7` metin.

| UI olayı | Görsel davranış | Motion |
|---|---|---|
| Zoom aracını açma | timeline Camera Lane'e morph olur, player yerini korur | `DS.Motion.settle` |
| Tarif seçme | thumbnail büyümez; coral alt çizgi akar, canlı preview başlar | `snap` |
| Focus Orb bağlama | orb'dan subject halo'ya kısa lime tether | 260 ms settle |
| Süre sürükleme | ribbon gerçek zamanlı uzar, komşu sınırda haptic snap | parmağa 1:1 |
| Punch marker | tek kontrollü pulse | gerçek recipe süresi |
| Apply | ribbon lime'a dönüp sakinleşir | 220 ms ease |
| Hata/güven düşüşü | ilgili ribbon parçası amber ve kesik | 180 ms crossfade |

Ekranda aynı anda sürekli animasyon yapan halo, kart, timeline ve progress bulunmaz. Bir anda tek odak hareket eder. Render sonucunu taklit eden önizleme animasyonu UI spring'inden değil gerçek CameraTransform'dan beslenir.

## 7. Teknik mimari

### 7.1 Domain modelleri

```swift
struct ZoomRecipe {
    let id: UUID
    let sourceRange: CMTimeRange
    let kind: ZoomKind
    let amount: Double
    let timing: TimingProfile
    let feel: MotionProfile
    let anchor: AnchorBinding
    let protections: FramingProtections
}

enum AnchorBinding {
    case fixed(CGPoint)
    case subject(trackID: UUID, offset: CGPoint)
    case group(trackIDs: [UUID])
    case manual([CameraKeyframe])
}

struct CameraTransformSample {
    let sourceTime: CMTime
    let center: CGPoint
    let scale: Double
    let rotation: Double
    let motionBlur: Double
}
```

Recipe, render keyframe'inden farklıdır. Kullanıcı `Sakin Yaklaş` tarifini seçer; motor gerektiğinde deterministik sample üretir. Bu ayrım tarifin süresini, track bağını veya hissini daha sonra bozulmadan değiştirmeyi sağlar.

### 7.2 Motion Graph kanalları

```text
Base Framing
 + Stabilization Correction
 + Subject Follow
 + Zoom Envelope
 + Impact/Beat Impulse
 + Manual Offset
 = Constraint Solver
 → Camera Transform Track
 → Preview / Export Renderer
```

Birleştirme kuralı açık olmalı:

1. manuel kullanıcı override'ı hedef center ve scale için en yüksek öncelik,
2. track follow hedefi anchor üretir,
3. zoom envelope scale değişimini üretir,
4. impulse kısa süreli offset/scale/rotation ekler,
5. stabilization istenmeyen kamera hareketini azaltır,
6. constraint solver crop, safe area, velocity ve kalite sınırlarını uygular.

Bu graph hem ana videoda hem ek video layer'larında aynı evaluator'ı kullanmalıdır. Preview ile export farklı geometri kodlarına sahip olmamalıdır.

### 7.3 Servis sınırları

- `ZoomRecipeEvaluating`: recipe → continuous envelope,
- `AnchorResolving`: fixed/subject/group/manual anchor çözümü,
- `FramingConstraintSolving`: output aspect, safe-area, crop ve resolution,
- `MotionMixing`: follow/zoom/shake/stabilization katkıları,
- `CameraTrackReducing`: görsel hatayı koruyarak keyframe azaltma,
- `ZoomSuggestionGenerating`: transcript/shot/event'ten öneri,
- `CameraPreviewRendering`: edit ekranı preview,
- `CameraExportRendering`: AVFoundation/Core Image/Metal export yolu.

### 7.4 Mevcut yapıyla birleşme

- `VideoFocusKeyframe` okunmaya devam eder; yeni `AnchorBinding.subject` için migration/adaptor olur.
- `VideoPlacement` elle yerleşimi korur; Zoom Engine onu doğrudan overwrite etmez.
- `VideoLayerComposer` instruction boundary üretimini Camera Transform Track sample'larından besleyecek şekilde genişler.
- ana video reframe ve ek video focus aynı `CameraTransformEvaluator` üzerinden geçer.
- `EditorAction` bir recipe ekleme/değiştirme/silme işlemini tek undo grubu olarak taşır.
- AI workflow ham `editor.change.videoLayer` gibi kullanıcıya sızan teknik anahtarlar yerine yerelleştirilmiş eylem adı gösterir: `Motoru takip eden yakınlaşma`.

## 8. Otomatik zoom karar motoru

Otomatik zoom bir “her N saniyede zoom” kuralı olmamalı. Öneri üretici şu sinyalleri puanlar:

- transcript rolü: hook, claim, örnek, punchline, CTA,
- kelime ve cümle vurgusu,
- konuşma enerjisi ve duraklama,
- shot değişimi,
- subject track hareketi ve ölçeği,
- motion event/beat,
- mevcut caption/overlay yoğunluğu,
- son zoom'dan geçen süre,
- projenin seçilen stil profili.

Her aday `neden`, `range`, `confidence`, `energyCost` ve `conflicts` taşır. Scheduler, zaman aralığında toplam kamera enerjisini sınırlar. Hook ve CTA gibi roller otomatik stil atama motorundan gelirse kullanılır; rol yoksa zoom bozulmaz, görsel/ses sinyalleriyle devam eder.

Otomatik sonuç Camera Lane'de öneri olarak görünür. Kullanıcı `Tümünü uygula`, tek tek kabul, silme veya yoğunluğu azaltma yapabilir. Uygulanan her öneri recipe olarak kalır; sonradan düzenlenebilir.

## 9. Rakip özellik haritası

| Alan | CapCut | Adobe Premiere / AE | Final Cut Pro | DaVinci Resolve | Captions | CueTake hedefi |
|---|---|---|---|---|---|---|
| Manuel zoom | keyframe, strength/speed/duration | position/scale keyframes | iPad pan/zoom transform keyframes | inspector/Fusion keyframe | Zoom + keyframes | üç makro kontrol + açık manuel keyframe |
| Preset zoom | Optical Zoom, Zoom Lens, templates | preset/effect ekosistemi | effect/keyframe | Resolve FX/Fusion | AI Edit styles | gerçek eğri gösteren canlı tarifler |
| Auto reframe | oran, movement tracking, speed | aspect ratio, motion preset, path override | object tracking ile kurulabilir | Smart Reframe + reference point | otomatik sosyal edit | track bağlı, source-time, group framing |
| Object follow | motion tracking; scale/distance/direction | mask/motion tracking | object tracker ve motion track reuse | tracker/Magic Mask | otomatik fakat ayrıntısı sınırlı | bir kez boya; her hedefe tekrar bağla |
| Shake / impact | AI movement tracking, subtle shake/effects | keyframe/effect | effect/keyframe | Camera Shake/Fusion | otomatik SFX/motion | pose/impact/beat tabanlı fiziksel impulse |
| Düzeltme | manuel keyframe/yeniden takip | frame-level mask/path correction | track/mask controls | reference point/manual correction | prompt veya regenerate | confidence ribbon + tek kare boya + lokal splice |
| Otomatik anlatı | templates/AI edit | araçlar ayrı | büyük ölçüde manuel | büyük ölçüde manuel | tek-tap AI Edit | otomatik öneri + neden + tam düzenlenebilir recipe |

Kaynaklar:

- CapCut, Auto Reframe'de çeşitli oranlar, hareket takibi, stabilization ve camera movement speed; zoom akışında Optical Zoom/Zoom Lens ile strength, speed, duration ve mobil keyframe mesafesi sunuyor. [CapCut Auto Reframe](https://www.capcut.com/tools/auto-reframe), [CapCut Zoom](https://www.capcut.com/resource/how-to-zoom-in-on-video), [CapCut AI Movement Tracking](https://www.capcut.com/tools/ai-movement-tracking)
- Adobe Auto Reframe slow/default/fast motion presetleri üretip position keyframe'lerini override etmeye izin veriyor; Premiere mask tracker yön ve frame düzeltmesi, After Effects position/rotation/scale tracking ve stabilization sunuyor. [Adobe Auto Reframe](https://helpx.adobe.com/premiere/desktop/add-video-effects/commonly-used-effects/add-auto-reframe-effect-to-a-clip.html), [Adobe Mask Tracking Tools](https://helpx.adobe.com/premiere/desktop/add-video-effects/work-with-masks/mask-tracking-tools.html), [After Effects Tracking](https://helpx.adobe.com/after-effects/desktop/animate-in-after-effects/track-motion/tracking-stabilizing-motion-cs5.html)
- Final Cut Pro iPad position, scale, rotation ve crop keyframe'lerini interpolate ediyor; Mac object tracker verisini klip, başlık, görsel ve efekt maskesine bağlayabiliyor. [Final Cut Pro iPad Keyframes](https://support.apple.com/en-euro/guide/final-cut-pro-ipad/dev2823419d2/ipados), [Final Cut Pro Object Tracker](https://developer.apple.com/documentation/professional-video-applications/object-tracker?language=objc)
- DaVinci Neural Engine object detection, Smart Reframe ve Magic Mask sağlıyor; resmi özellik tablosu bazı AI özelliklerinin Studio ve cihaz sınıfına bağlı olduğunu gösteriyor. [DaVinci Resolve](https://www.blackmagicdesign.com/products/davinciresolve), [DaVinci Studio/iPad Feature Table](https://documents.blackmagicdesign.com/SupportNotes/DaVinci_Resolve_Studio_Features.pdf)
- Captions AI Edit otomatik zoom, geçiş, B-roll ve grafik ekliyor; Co-editor metinle düzeltme sağlıyor. Güncel yardım akışı tek konuşmacı, dikey ve kısa videoda en iyi sonucu belirtiyor. [Captions AI Video Editor](https://www.captions.ai/tools/ai-video-editor), [Captions No-Timeline Edit](https://captions.ai/help/guides/edit-faster/no-timeline-edit)

Üretici sayfaları özellik varlığını gösterir, kalite karşılaştırması değildir. CueTake “hepsinden iyi takip eder” iddiasını ancak ortak test seti sonuçlarıyla kullanmalıdır.

## 10. Rakip boşluklarına ürün cevabı

Araştırmadan çıkan fırsat, daha fazla preset eklemekten önce şu birleşimi kusursuz yapmaktır:

1. **Bir seçim, tekrar kullanılabilir track.** Rakiplerde maske, tracker, auto reframe ve zoom sıklıkla farklı başlangıçlar ister.
2. **Otomatik ama düzenlenebilir.** Captions benzeri tek dokunuş hızını, Premiere/Resolve seviyesinde düzeltilebilir veriyle birleştir.
3. **Telefon için confidence UX.** İleri/geri analiz ve binlerce keyframe yerine yalnız problemli anı göster.
4. **Hikâye ile fizik aynı graph'ta.** Hook/CTA zoom'u, subject follow ve ayak vuruşu shake'i birbirinden habersiz transformlar üretmesin.
5. **Kaynak-zamanı sağlamlığı.** Split/trim/reorder sonrası track ve recipe doğru aralığa taşınsın.
6. **Görsel kalite koruması.** Aşırı crop, caption çakışması, siyah kenar ve titreme otomatik sınırlandırılsın.
7. **Preview = export.** Kullanıcının gördüğü hareket export'ta farklılaşmasın.

## 11. Uygulama fazları

### Faz Z0 — Camera domain ve Motion Graph

- recipe, anchor, camera transform ve channel mixer modelleri,
- source-time dönüşümleri,
- tek preview/export evaluator,
- eski reframe/focus verisi adaptörü,
- undo/redo ve persistence.

**Çıkış koşulu:** Mevcut projeler pixel eşdeğer açılır; zoom eklemek placement veya caption konumunu değiştirmez.

### Faz Z1 — Temel zoom UX

- Zoom sahnesi, tarif galerisi, üç makro kontrol,
- Push/Pull/Punch/Hold/Ken Burns,
- Camera Lane, süre taşıma ve A/B,
- çözünürlük/crop guard ve Reduce Motion.

### Faz Z2 — Tracking bağlantısı

- fixed/subject/group anchors,
- follow offset, dead zone, look-ahead ve confidence davranışı,
- 9:16/1:1/4:5/16:9 reframe,
- caption/overlay safe-area solver.

### Faz Z3 — Vuruş, blur ve geçiş

- MotionEvent bağlama,
- punch + natural shake mix,
- zoom blur ve matched zoom transition,
- shot boundary kuralları ve energy limiter.

### Faz Z4 — Akıllı editör

- transcript role/emphasis sinyalleri,
- öneri scheduler'ı, neden/confidence,
- stil profilleri ve proje recipe library,
- agentic tool yüzeyi.

## 12. Kabul kriterleri

- İlk tarif önizlemesi sıcak cache'de 100 ms, soğuk durumda 250 ms hedefini aşmamalı.
- Preview ve export'ta center/scale farkı görünür frame düzeyinde olmamalı.
- Varsayılan Follow Zoom'da durağan özne için center jitter < frame genişliğinin `%0,15`i.
- Hard cut üzerinden istemsiz eğri taşmamalı.
- Siyah kenar, NaN transform veya negatif crop hiçbir export frame'inde oluşmamalı.
- `%20` üstündeki zoom için çıktı çözünürlük bütçesi hesaplanmalı; uyarı doğru eşikte görünmeli.
- Timeline scroll, zoom block drag ve trim gesture birbirini kilitlememeli.
- 50 klipli projede Camera Lane açılışı ve scroll akıcılığı profillenmeli.
- Split, trim, speed, reorder, duplicate, undo/redo ve relaunch sonrasında recipe aralığı doğru kalmalı.
- VoiceOver bütün tarifleri hareket ve miktarla okumalı; tüm hit target'lar en az 44 pt olmalı.

## 13. AI tool yüzeyi

- `suggestZoomRecipes(range, style, intensity)`
- `applyZoomRecipe(range, recipe, anchor)`
- `bindZoomToTrack(recipe, track)`
- `setZoomTiming(recipe, start, hold, end)`
- `addImpactZoom(event, amount, feel)`
- `addZoomTransition(cut, direction, feel)`
- `inspectFramingConflicts(range)`
- `removeZoomRecipe(recipe)`

Tool çıktısı kullanıcıya teknik anahtar olarak gösterilmez. Örnek history metni: `CTA’da doğal yakınlaşma`, `Motoru takip eden kadraj`, `3 ayak vuruşuna hafif darbe`. AI her uygulamadan sonra crop, safe-area, track confidence ve render sonucunu doğrular; çakışmada ikinci otomatik zoom'u üst üste bindirmez.

## 14. Riskler

| Risk | Sonuç | Önlem |
|---|---|---|
| Birden fazla kanal scale'i büyütüyor | amatör, aşırı zoom | enerji bütçesi ve constraint solver; multiplicative stacking yok |
| Track gecikiyor | kamera öznenin arkasında kalıyor | look-ahead + hız duyarlı filtre + confidence state |
| Büyük zoom çözünürlüğü bozuyor | yumuşak/piksel görüntü | output-aware crop budget ve slider üstünde kalite eşiği |
| UI keyframe aracına dönüşüyor | mobilde kaybolma | üç makro kontrol varsayılanı; gelişmiş görünüm isteğe bağlı |
| Auto zoom çok sık | yorucu kurgu | cooldown, story priority ve toplam motion energy |
| Preview/export farklı | güven kaybı | ortak evaluator ve golden-frame testleri |
| Efekt caption/yüzü kapatıyor | okunabilirlik düşer | safe-area solver ve per-frame conflict check |
