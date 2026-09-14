# AI Tool List Roadmap

Bu dosya, sonraki AI güçlendirme turlarında ana referanstır.

## Hedef

CueTake AI’sının editörü yalnızca metinle tarif etmek yerine, kullanılabilir araçları otomatik keşfedip doğru sırayla seçmesi, güvenli parametrelerle çalıştırması ve sonucu doğrulaması.

## Yapılacak çekirdek sistem

- Tek bir `ToolDescriptor` / registry: araç adı, açıklama, giriş parametreleri, ön koşullar, risk seviyesi ve geri alma kapsamı.
- AI isteğine göre otomatik tool seçimi ve sıralaması.
- Parametreleri çalıştırmadan önce tip, aralık, zaman aralığı ve mevcut medya kontrolü.
- Her tool için `proposed → approved → applied → verified` yaşam döngüsü.
- Başarısız tool için açık hata, retry ve güvenli rollback.
- Tool çıktılarının sonraki tool’lara aktarılması; finding ve confidence nesnelerinin ortak primitive olması.
- Kullanıcıya AI’nın hangi araçları neden seçtiğini gösteren sade bir plan özeti.

## İlk tool grupları

1. **Analyze:** transcribe, detect filler, detect dead air, detect repetition, check script coverage, detect framing issues.
2. **Edit:** cut words, trim pauses, trim/split clip, select take, reorder clips, set speed.
3. **Captions:** generate captions, retime captions, apply caption style, shift caption window.
4. **Visual:** smart reframe, update video layer, keyframe video, layout videos, background/effect/filter.
5. **Audio:** clean voice, set voice effects, set music level, add/retime sound.
6. **Workflow:** assemble sections, ask user approval, retry step, render QA, export.

## Rakip taramasından çıkan eksik tool yüzeyi

Bu liste, CapCut’ın scene split/trim/transcript editing/multi-track/beat sync araçları, Descript’in transcript tabanlı edit ve AI Tools yüzeyi, Captions’ın AI Trim, keyframe, shots transition, split media tracks, AI zoom, censor, denoise, music/SFX ve clips akışı incelenerek çıkarıldı. Rakip sayfaları üretici beyanıdır; araçların CueTake’e alınması kalite veya platform parity garantisi vermez.

### P0 — Temel timeline ve güvenilir execution

- `trimClip`: klibin başından/sonundan veya seçilen aralıktan kes.
- `splitClip`: playhead, kelime sınırı, sessizlik veya sahne değişiminde böl.
- `deleteRange`: seçilen aralığı ripple delete ile kaldır; sonraki klipleri güvenli kaydır.
- `restoreOriginalRange`: daha önce trimlenmiş klibi kaynak uzunluğuna geri aç.
- `replaceClipSource`: aynı zaman aralığını başka take/video ile değiştir.
- `reorderClips`: klipleri sürükle-bırak sırasına getir; captions/effects/audio zamanlarını taşı.
- `setSpeed` ve `reverse`: aralık bazlı hız/ters oynatma; ses ve caption zamanlarını doğrula.
- `toolPreview`: uygulanmadan önce etkilenecek aralık ve tahmini süre kazancını göster.
- `toolUndo` ve `toolRetry`: her AI tool’u tek undo grubunda ve tekrar çalıştırılabilir yap.

### P0 — Konuşma ve transcript araçları

- `detectFillerWords`: dil sözlüğü + transcript confidence ile filler bul.
- `detectSpeechGaps`: dead-air, kısa kelime arası ve doğal pause’u ayrı sınıflandır.
- `removeFillers`: yalnız filler kelimesini veya çevresindeki sessizliği kes.
- `removeRepetition`: tekrar edilen cümle/take aralıklarını bul; son temiz take’i öner.
- `editByTranscript`: transcript metnini silince karşılık gelen videoyu güvenli kaldır.
- `alignToScript`: cümleleri script beat’lerine bağla; eksik/yarım/off-script finding üret.
- `scriptCoverage`: segment ve proje seviyesinde coverage score üret.
- `captionTiming`: phrase/word görünümüyle başlangıç-bitiş, satır bölme ve okuma süresini düzelt.

### P0 — Layer, transform ve çoklu video

- `updateVideoLayer`: sourceStart, duration, x/y, width/height, opacity, volume, mute, mirror.
- `splitVideoLayer`: ek videoyu timeline’da iki parçaya ayır.
- `cropVideo`, `fitVideo`, `fillVideo`, `rotateVideo`, `mirrorVideo`.
- `keyframeTransform`: position, scale, rotation, opacity için keyframe; interpolasyon ve sınır kontrolü.
- `layoutVideos`: side-by-side, stacked, picture-in-picture, grid; otomatik güvenli boşluk.
- `detectActiveSpeaker`: çoklu konuşmacıda aktif kişiyi seçip framing öner.
- `smartReframe`: focus trail, önce/sonra preview ve “değişiklik yok” açıklamasıyla çalışsın.
- `autoZoom`: hook, punchline veya vurgu kelimesinde kontrollü zoom öner.
- `sceneDetect`: shot boundary ve hareket değişimlerini finding olarak üret.

### P1 — Görsel ve ses polish araçları

- `addTransition` / `updateTransition`: cut, fade, crossfade, wipe ve stil uyumlu süre.
- `applyFilter` ve `colorCorrect`: brightness, contrast, saturation, warmth, vignette, sharpness.
- `stabilizeVideo`: hareketli/elde çekilmiş görüntüde crop sınırlarını kontrol ederek stabilize et.
- `backgroundCutout` / `replaceBackground`: kişi maskesi, feather, edge quality ve geri alma.
- `denoiseVoice`: gürültü, echo, wind ve hum azalt; before/after ses preview.
- `splitAudioTracks`: voice, music, background parçalarını ayrı timeline layer’larına ayır.
- `censorProfanity`: kelimeyi mute/bleep/replace et; captions’ı da senkron güncelle.
- `syncMusicToBeats`: beat marker üret, cut/transition öner; kullanıcı ritim yoğunluğu seçsin.
- `generateMusic` ve `generateSoundEffect`: prompt’tan medya üret; kaynak/izin ve süre metadata’sı taşı.
- `addVoiceover` / `textToSpeech`: script’ten ses üret veya kullanıcı kaydını yerleştir.

### P1 — Caption ve stil araçları

- `applyCaptionStyle`: font, size, color, highlight, plate, animation, max words.
- `captionWordHighlight`: karaoke/phrase highlight; confidence düşük kelimeyi review’a gönder.
- `translateCaptions`: hedef dil, satır bölme ve süre taşması kontrolü.
- `exportSRT`: burn-in yanında harici SRT/VTT üret.
- `stylePreset`: caption + color + transition + music + B-roll kararlarını tek preset olarak uygula.
- `brandKit`: kayıtlı renk, font, logo, safe-area ve intro/outro kuralları.

### P1 — Repurposing ve içerik seçimi

- `findHighlights`: hook, payoff, conflict, reaction ve CTA adaylarını bul.
- `rankShorts`: adayları bağlam, completeness, pacing ve confidence ile sırala; “viral” iddiasını kesin gerçek gibi sunma.
- `makeShorts`: uzun kayıttan seçilen süre aralıklarında 2–3 alternatif short üret.
- `platformFormat`: 9:16, 1:1, 16:9; her biri için smart reframe ve caption safe-area.
- `generateTitleDescriptionHashtags`: seçilen short’un diline ve platformuna göre metadata.
- `batchRender`: aynı projeden platform/format varyantlarını kuyrukla; her çıktı için ayrı QA raporu.

### P2 — Üretken ve ileri seviye AI

- `generateBRoll`: konuşulan cümleye göre medya öner/ekle; her öneri kullanıcı onaylı olsun.
- `generateImage` / `generateVideo`: prompt veya script beat’inden medya üret.
- `dubVideo`: çeviri, voice clone ve lip-sync; açık izin, maliyet ve veri akışı göster.
- `createAvatar`: avatar/twin üretimi; çekirdek CueTake farkı olmadığı için sonraya bırak.
- `autoPublish`: platforma gönderim; en son aşama, açık onay ve OAuth kapsamı gerektirir.

## Öncelik kuralı

- **P0**: Kullanıcı şu an timeline’da temel işi yapamıyorsa önce bunlar; AI bunları güvenli ve geri alınabilir çağırabilmeli.
- **P1**: Rakip parity ve profesyonel polish; P0 validator’ları olmadan otomatik çalıştırılmamalı.
- **P2**: Maliyet, gizlilik, izin ve içerik güvenliği yüksek; agent’in varsayılan davranışı öneri + onay olmalı.

## Rakip kanıtları

- CapCut, scene detection ile otomatik bölme, transcript düzenleme, filler/speech gap kaldırma, multi-track katmanlama, beat sync, crop/resize, stabilization ve çoklu AI araçlarını listeliyor: [Auto Video Editor](https://www.capcut.com/tools/auto-video-editor), [Transcript Editing](https://www.capcut.com/tools/video-transcript-editing), [Split Scene](https://www.capcut.com/tools/split-scene), [Online Video Editor](https://www.capcut.com/tools/online-video-editor).
- Descript, transcript üzerinden düzenleme, filler/retake/gap temizleme, Studio Sound, eye contact, center active speaker, multicam ve clip üretimini AI Tools/Underlord altında topluyor: [Underlord](https://www.descript.com/underlord), [Video Editor](https://www.descript.com/tools/video-editor), [Release Version 91](https://feedback.descript.com/changelog/descript-season-6-release-version-91).
- Captions’ın özellik tablosu AI Trim, AI Zoom, AI Censor, AI Denoise, AI Sound Effects, AI Music, AI Cutout, AI Eye Contact, keyframes, split/merge/reorder, transitions, split audio tracks, SRT export ve media overlays’i açıkça listeliyor: [Feature Availability](https://help.captions.ai/docs/feature-availability). AI Edit ve Co-editor; trim, captions, B-roll, music, transitions ve motion graphics’i tek akışta çalıştırıyor: [AI Edit](https://help.captions.ai/docs/project/ai-edit), [No-timeline Edit](https://captions.ai/help/guides/edit-faster/no-timeline-edit).

## Sıralama

- Önce registry ve ortak EditAction sözleşmesi.
- Sonra finding → condition → action bağlantısı.
- Ardından otomatik tool seçimi ve güvenli execution state.
- En son branching, loops, tool önerileri ve workflow marketplace.

## Tasarım kuralı

AI hiçbir aracı sessizce çalıştırmamalı. Kullanıcı, seçilen aracın amacını, etkileyeceği zaman aralığını, güvenini ve geri alınabilir olduğunu görmelidir.
