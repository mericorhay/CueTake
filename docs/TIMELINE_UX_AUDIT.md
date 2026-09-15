# CueTake Timeline UX Audit

> **Ana ürün otoritesi:** [CUETAKE_MASTER_PRODUCT_PLAN.md](CUETAKE_MASTER_PRODUCT_PLAN.md). Bu dosya timeline denetim ayrıntılarını korur.

_15 Eylül 2026 — mobil kurgu akışı, resmi ürün sayfaları ve yardım belgeleri üzerinden karşılaştırıldı._

## Hedef

Timeline üzerinde her temasın tek bir anlamı olmalı: dokunmak zamanı ve klibi seçer, yatay sürüklemek videoyu scrub eder, uzun basıp sürüklemek klibi taşır, kenar tutamaçları yalnızca trim yapar. Kullanıcı yaptığı işlemin görüntüdeki sonucunu aynı anda görmeli ve her işlem geri alınabilmelidir.

## Rakiplerde yerleşmiş davranışlar

| Alan | CapCut | VN | Premiere on iPhone | Captions | CueTake durumu |
|---|---|---|---|---|---|
| Temel timeline | Klip seçme, trim, split ve uzun basıp sıralama | Çok katmanlı timeline, 0,05 sn hassasiyet ve 30× zoom | Akıcı ve hassas çok katmanlı timeline | Klip üzerinde zamanı ayarla, split/delete/merge/reorder | Ortadaki sabit playhead, pinch zoom ve çoklu lane var; klip gövdesinde dokunulan zamana gitme Build 64'te düzeltildi |
| Trim geri bildirimi | Kenardan doğrudan trim | Kare hassasiyetli trim | Seçili klipte belirgin tutamaçlar | Manuel clip/overlay/music trim | Canlı süre balonu, kaynak başlangıcını geri açma ve haptic snap var |
| Snap ve ritim | Timeline/kesim akışı; gelişmiş speed curve | Beat marker ve beat sync | Beat detection marker'ları; klip beat'e oturunca haptic | Shot change marker'ları | Kesim, overlay, efekt, ses ve video katmanı kenarlarına snap var; beat/shot marker yok |
| Katman kontrolü | Video, ses, yazı ve efekt katmanları | Video/audio/overlay çoklu katman | Çok katmanlı düzen | Media overlays ve ses | Video katmanı, ses, caption, overlay ve efekt lane'leri var; lane lock/hide/collapse yok |
| Efekt doğrulama | Timeline'da efekt ve ayar sonucu | Filtre, LUT, motion FX ve transition | Efekt, transition ve Lightroom look | AI efektler ve geçişler | Efekt lane'i ve süre ayarı var; anlık before/after ve işlem durumu eksik |
| Hassas düzenleme | Split, keyframe, mask, curve speed | 0,05 sn, 30× zoom, keyframe curves | Position/scale/opacity keyframe | Keyframe ve shot transition | 4–240 pt/sn pinch zoom ve video-layer keyframe var; ±1 frame adımı ve görünür zoom kontrolü yok |

## Build 64'te kapatılan hatalar

1. Numaralı import rolleri artık ekran açılışına bırakılmıyor. Konuşma sıradan olsa veya ses bulunmasa da import kaydedilmeden önce Hook/Point tabanı atanıyor; transcript semantik kanıt bulursa Intro/Example/CTA ile geliştiriyor ve arka plandaki transkripsiyon eski 1/2 kopyasını geri yazamıyor.
2. Klip gövdesine dokunmak, dokunulan yatay noktayı kesin timeline zamanına çeviriyor. Aynı temas klibi seçiyor; açık inspector sekmesini gereksiz yere sıfırlamıyor.
3. Yeni efekt eklendiğinde playhead efektin kapsadığı kareye alınıyor. Böylece başka bir zamanda durup çalışan efekti görünmez sanma durumu ortadan kalkıyor.
4. Özel video compositor hedef buffer biçimi düzeltildi. AVFoundation'a bir hedef pixel format yerine format dizisi verilmesi `newPixelBuffer()` üretimini engelleyerek görsel efektleri sessizce düşürüyordu.

## Sonraki timeline öncelikleri

### P0 — güven ve hassasiyet

- **Ayrı düzenleme modu:** Normal modda her gövde teması scrub/seçim; “Klipleri düzenle” modunda gövde drag'i sıralama. Uzun basmanın iki farklı anlama gelmesini tamamen kaldırır.
- **±1 kare adımı:** Playhead'in iki yanında önceki/sonraki kare; uzun basınca sürekli ilerleme. Kesim doğruluğu dokunmatik hedef boyutundan bağımsız olur.
- **Görünür zoom kontrolü:** Pinch korunur; `−`, “seçime sığdır”, `+` düğmeleri keşfedilebilirlik sağlar.
- **Efekt bypass:** Efekt inspector'ında basılı tutarak önce/sonra karşılaştırması ve “önizleme hazırlanıyor” durumu.
- **Boşluk/ripple kuralı:** Silme ve taşımanın diğer katmanları kaydırıp kaydırmadığını işlemden önce gösteren tek bir magnetic/pro seçimi.

### P1 — uzun projeler

- **Timeline overview/minimap:** 30–50 klipte mevcut konumu ve seçimi gösterir; bir bölgeye dokunarak hızlı gezinilir.
- **Lane başlıkları:** Video, overlay, caption, efekt ve ses için collapse, hide, mute ve lock.
- **Çoklu seçim:** Birden fazla klibi birlikte taşıma, silme, hız veya filtre uygulama.
- **Marker sistemi:** Kullanıcı marker'ı, otomatik shot boundary ve müzik beat marker'ı aynı ruler üzerinde farklı işaretlerle görünür.
- **Bağlantılı taşıma:** Kliple birlikte caption/overlay/effect'in hareket edip etmeyeceği açıkça seçilir.

### P2 — yaratıcı güç

- Kesim noktasına doğrudan transition yerleştirme ve timeline üzerinde süre tutamacı.
- Ana video için position/scale/opacity keyframe ve curve editor.
- Speed ramp eğrisi, LUT import ve mask/blend mode.
- Proxy/preview kalite seçimi ve ağır efektlerde render-cache göstergesi.

## Kaynaklar

- CapCut: [mobil klipleri uzun basıp sıralama ve transition](https://www.capcut.com/resource/merge-two-videos), [split/trim/keyframe araçları](https://www.capcut.com/resource/how-to-use-capcut)
- VN: [resmi özellikler — multi-track, keyframe, speed curve ve frame-precision trim](https://vlognow.me/), [App Store — 0,05 sn hassasiyet ve 30× zoom](https://apps.apple.com/us/app/vn-video-editor/id1343581380)
- Adobe Premiere on iPhone: [hassas çok katmanlı timeline](https://www.adobe.com/products/premiere-rush.html), [beat detection ve haptic snap](https://helpx.adobe.com/ca/premiere/mobile/audio-editing/use-beat-detection-for-music-synced-edits.html), [keyframe ve efekt güncellemeleri](https://helpx.adobe.com/ca/premiere/mobile/whats-new/release-notes.html)
- Captions: [iOS timeline özellik tablosu](https://help.captions.ai/docs/feature-availability), [shot detection ve transitions](https://help.captions.ai/docs/timeline/transitions), [timeline üzerinde klip ekleme/silme](https://help.captions.ai/docs/timeline/add-delete)
