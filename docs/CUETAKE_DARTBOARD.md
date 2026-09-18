# CueTake Dart Tahtası: Rakipler, Açıklar, Teknik Altyapı ve Plan

> Tek rapor, tek otorite. Önceki bütün planlar (master plan, gap report, AI tool roadmap, timeline audit, tracking, zoom, workflow platform) bu dosyada birleştirildi ve kaldırıldı; eski hâlleri git geçmişinde duruyor.
> Güncelleme: 18 Eylül 2026 · Kod: build 104 · sürüm 0.5.0 · durum: [§0](#0-durum-panosu)

## İçindekiler

0. [Durum panosu](#0-durum-panosu)
1. [Kısa cevap: aramızda ne kaldı](#1-kısa-cevap-aramızda-ne-kaldı)
2. [Dart tahtası](#2-dart-tahtası)
3. [Rakip profilleri](#3-rakip-profilleri)
4. [CueTake bugün ne yapıyor](#4-cuetake-bugün-ne-yapıyor)
5. [Hedefler: rakibin bizi geçtiği her konu ve bizim cevabımız](#5-hedefler-rakibin-bizi-geçtiği-her-konu-ve-bizim-cevabımız)
6. [Ortak teknik altyapı](#6-ortak-teknik-altyapı)
7. [İleri özellikler: kimsenin yapmadığı şeyler](#7-ileri-özellikler-kimsenin-yapmadığı-şeyler)
8. [Plan](#8-plan)
9. [Eski planlardan devreden açık işler](#9-eski-planlardan-devreden-açık-işler)
10. [Ölçüm, risk ve kurallar](#10-ölçüm-risk-ve-kurallar)
11. [Kaynaklar](#11-kaynaklar)

---

## 0. Durum panosu

Son güncelleme: 18 Eylül 2026, build 104. ✅ bitti · 🟢 kodu bitti, cihazda denenmedi · 🟡 kısmen · ⬜ başlanmadı.

| Hedef | Durum | Ne var / ne eksik |
|---|---|---|
| H1 Animasyonlu altyazı + stil paketleri | 🟢 | Kelime bazlı animasyon motoru (önizleme = export), 20 görünüm, 6 stil paketi, anahtar kelime/emoji, okunabilirlik uyarısı, yüzden kaçan konum. Cihazda denenmedi |
| H2 Long-to-short + reframe | 🟢 | Cümle bazlı an bulucu + puan, AI seçimi (`/highlights`), tek dokunuşla dikey kısa proje (dosyalar hard link), geniş videoda yüz takibi. Cihazda denenmedi |
| H3 Script hizalı temizlik | 🟢 | Script hizalaması (NW + bulanık eşleşme), dolgu/tekrar/yeniden başlama/script dışı, duraklama eşiği, tüm kliplere tek geri alma, geri açılabilir kesim, kesimde ses tıkı giderme, çekim puanı + en iyi çekim. Cümle bazında yeniden çekim (transcript'ten) ve yeniden çekimi konuşmaya göre kırpma da var. Eksik: çekim puanında ses kalitesi/göz teması, timeline'da hayalet aralık |
| H4 Göz teması | ⬜ | — |
| H5 Render/export güvenilirliği | 🟡 | Dayanıklı export (H.264 / altyazısız yeniden deneme), gerçek hata metni, dosya önbelleği. Metal çekirdek, arka plan export, kalite kapısı yok |
| H6 Şablon/efekt/geçiş/görünüm | 🟢 | **15 geçiş**, önceden çizilen geçiş filmleri (her biri CI'da gerçek videoyla test ediliyor); bitmiş videodan **şablon** çıkarma ve başka videoya uygulama; satın alınan **.cube renk tabloları** (hazır görünümle üst üste, medya temizlikçisi silmiyor). Eksik: Metal efekt |
| H7 Pro timeline | 🟡 | Güvenli silme (ripple + geri al), çoklu ses satırları ve mikser, kayıt bazında tutarlı kadraj, eklenen video gerçek bir satır, **proje sürümleri** (adlı + otomatik, temizlikçi sürüm videolarını korur), **ses eğrisi** (fade ve ducking'in üstüne çarpılan noktalar). Eksik: ana klip keyframe, hız eğrisi |
| H8 Maske / yeşil perde | 🟢 | Arka plan değişirken önde kalan: **kişi**, **nesne** (Apple ön plan maskesi, kareler arası yumuşatılmış) ya da **renk** (yeşil/mavi/seçilen; aralık, kenar, taşma). Eklenen videoda **yeşil perde** (canlı, sürüklerken yeniden kurulmuyor). **Yazı/fotoğraf kişinin arkasında** (compositor her karede kişi maskesiyle; seçiliyken önde). Nesne modunda **dokunarak tek nesne** seçilir, render onu kare kare izler. **AI asistan** hepsini kullanır (addText behind, setBackground keep/screen, updateVideo screen) |
| H9 Müzik/SFX/beat/loudness | ⬜ | SFX ve ducking temeli var; beat motoru, LUFS, kütüphane yok |
| H10 Çeviri/dublaj | ⬜ | — |
| H11 AI ikiz / Restyle | 🟡 | BYOK video üretimi editörde ve workflow'da var; avatar, lipsync, restyle yok |
| H12 Yayın | 🟡 | Workflow'a özel API teslimi (multipart/raw/JSON, Keychain'de anahtar). YouTube/IG/TikTok, zamanlama, arka plan yükleme yok |
| H13 Senkron / iPad / Mac | 🟡 | Ekip senkronu yazıldı ve kilitli (yukarıdaki not): CloudKit paylaşılan alanlar, üç yollu birleştirme, tokuşturmayla davet. iPad/Mac yok |
| H14 Marka kiti / fikir motoru | 🟢 | Marka sesi (ad, ne yaptığı, kitle, mutlaka/asla) AI script'e ve konuşma tanımaya giriyor; kaydedilen hazır metinler; **renk + yazı tipi + logo kiti**, köşe/boyut seçilen filigran, tek dokunuşla videoya uygulama. Eksik: fikir motoru, trend takibi |
| H15 Multicam | ⬜ | — |

| Altyapı | Durum | Not |
|---|---|---|
| T1 Tool Registry | ⬜ | AI hâlâ `EditPlan` → `AIDirector` (geçişler dahil) |
| T2 MediaIndex | ⬜ | — |
| T3 Render Core | 🟡 | Tek birleştirici + filtre compositor; geçişler önceden render. Metal yok |
| T4 JobQueue | 🟡 | Editör içi arka plan işleri (arka plan değiştirme, geçiş filmleri). Kalıcı kuyruk, `BGContinuedProcessingTask`, Live Activity yok |
| T5 Provider | 🟡 | Worker + BYOK video. Ses/TTS sağlayıcıları yok |
| T6 Sync & Catalog | ⬜ | — |

**Ekipler (build 102, kilitli):** Kod tamam ve derleniyor (`TeamSync`, `TeamFeature`, `BumpKit`, `ProjectMerge`), ama arayüzden kapalı: `CUETAKE_TEAMS` kapalıyken motor başlamaz, CloudKit'e dokunulmaz, Ayarlar'da Ekip satırı görünmez. Işık önizlemesi Ayarlar → sürüm satırına 2 sn basılı tutunca açılır. Kilidi açmadan önce:
1. **CloudKit şeması Üretim'e dağıtılmalı** — kayıt türleri Üretim'de kendiliğinden oluşmaz. CloudKit Console → `iCloud.com.orhay.cuetake` → Development'ta şu türleri oluştur, sonra *Deploy Schema Changes*: `Project` (document: Bytes, **şifreli**; title: String, **şifreli**; updatedAt: Date/Time; schema: Int64), `Media` (file: String, **şifreli**; asset: Asset; project: Reference), `Team` (name: String, **şifreli**).
2. `CUETAKE_TEAMS` bayrağı `Config/CueTake.xcconfig`'te açılır.
3. İki telefonla (iki farklı Apple ID) dene: tokuşturmayla katılma, bağlantıyla davet, projeyi ekibe koyma, iki yönlü düzenleme, aynı anda düzenleme.
4. Açık risk: `shareParticipants(for:)` ile kullanıcı kaydı kimliğinden katılımcı bulma gerçek cihazda doğrulanmadı; tutmazsa tokuşturma yerine bağlantıyla davet çalışır.

**Sahne (build 95–96):** ana video artık tam ekran olmak zorunda değil — `Project.mainVideoPlacement` kanvastan taşınıp boyutlanıyor, `StagePiece` ile eklenen videolarla aynı muameleyi görüyor. Bölünmüş ekran ön ayarları iki resmi birlikte yerleştiriyor, takas var. Yarım ekrana düşen resim mektup kutusu yerine kırpılıyor.

**Bu turda öğrenilen (tekrarlanmasın):**
- İkinci video izine animasyon rampası vermek cihazda oynatıcıyı durduruyordu.
- Oynatma sırasında çizim de bu sorunu çözmedi.
- Geçişler artık kısa film olarak önceden çiziliyor ve "eklenen video" yolundan konuyor.
- Başı ve sonu aynı olan rampa hiçbir yerde kullanılmıyor.

**H3 notları:**
- Kesim, mevcut "klibi parçalara böl" yolunu kullanır. Parçalar `Segment.cleanup` ile gruplanır; "Geri aç" klibi çekildiği hâline döndürür.
- Kesimden sonra üstteki yazı ve efektler kayar (ripple). Geçiş, klibin sonunda kalır.
- Apple'ın cihaz içi tanıyıcısı "ııı/um" seslerini çoğu zaman yazmaz. Bulut dinleyici (Whisper) daha çok yakalar; dolgu tespiti bu yüzden transcript kalitesine bağlı.

**Teleprompter turu (build 91):**
- Metin artık okunan satırı sabit bir "okuma yerinde" tutarak kayıyor; uzun script'te yer kaybolmuyor.
- Ayarlar (boyut, mod, konum, hız, ayna) uygulama kapansa da kalıyor.
- Canlı konuşma hızı (kelime/dk) ve hız koçu, kalan süre, ilerleme çizgisi.
- `*kelime*` vurgusu, konuşmacı notları ve editördeki klip hızı artık prompter'da.
- Tekrar çekim ekranı stüdyo ile aynı prompter'ı ve ayarları kullanıyor.
- Editörde metinden seçilen cümle tek başına yeniden çekilebiliyor; prompter script'teki doğru cümleyi gösteriyor. Tutulan yeniden çekim, konuşmaya göre kendiliğinden kırpılıyor.
- Eksik: prova modu (kayıtsız dinleme), uzaktan kumanda / ikinci ekran.

**Ses algılama turu (build 92):**
- Ölçüm: `Tests/SpeechBenchmarks/*.json` her CI'da kelime hata oranı, kelime başı sapması ve dolgu yakalama oranıyla puanlanıyor. Uygulamada transcript panelinden "Konuşma örneğini dışa aktar" ile gerçek kayıt örneği alınıyor; referans elle düzeltilip klasöre konuyor. Şu an yalnızca uydurma bir örnek var.
- İpuçları: script'teki isimler, markalar, sayılar ve marka sesindeki ifadeler hem telefondaki tanıyıcıya (canlı ve dosya) hem Whisper'a veriliyor.
- Dolgu: Whisper'a dolgu içeren bir ipucu metni gidiyor. Ayrıca iki dinleyicinin de yazmadığı ama sesin olduğu kısa yerler temizlik listesine "…" olarak geliyor.
- Kelime sınırları sesin başladığı ve bittiği yere oturtuluyor; kesimler sessizliğe düşüyor.
- Canlı takip: söylenen sayılar rakamla eşleşiyor ("iki bin yirmi altı" → 2026), aksan farkı eşleşmeyi bozmuyor, metin tanıyıcı sonuçları arasında ölçülen hızla en fazla 2 kelime önden kayıyor.
- Cihazda doğrulanmadı; özellikle SpeechAnalyzer bağlam (contextual strings) desteği denenmeli.

**Kararlılık turu (build 93):**
- Workflow "birleştir" adımı: bölüme klip atanmamışsa artık boş yer tutucu koymuyor; atanmamış klipleri sırayla dağıtıyor, kalan bölümü düşürüyor, hiç video yoksa adımı atlıyor. Eskiden videoların yerine boş "point, point, cta" geliyordu.
- Kısa klipler paneli sheet oldu; yazarken klavyenin altında kalmıyor.
- Editörde klavye açılınca panel/enspektör alanı klavyenin üstüne kalkıyor (altyazı metni, konuşmacı notu, özel model alanı).
- Araç animasyonu oynayınca kayboluyor; zaman çizelgesinde takılı yeşil ışık bırakmıyor.
- Stil paketi, kullanıcının seçtiği geçişleri ezmiyor; yalnızca boş kesimleri dolduruyor.
- Teleprompter ayarları kaydırma bitince tek seferde yazılıyor.
- Temizlik planı her karede değil, klip ya da eşik değişince hesaplanıyor.
- AI script yazma artık görünür: script ekranında her zaman bir düğme, stüdyoda metin yoksa bir kart.

**Sıradaki:** Cihaz kontrolü (H1, H2, H3, teleprompter, ses). Gerçek kayıtlarla ölçüm seti. Sonra H3'ün kalanı (cümle bazında yeniden çekim) veya Faz 2 (H4 göz teması, H5 export).

## 1. Kısa cevap: aramızda ne kaldı

CueTake'in çekirdeği güçlü: script → teleprompter'lı çekim → segment timeline → AI kurgu → workflow → export. Rakiplerin hiçbirinde **script'i bilen bir kamera ile adım adım görünen, tek tek geri alınabilen bir AI yönetmen** birlikte yok. Ama rakipler şu altı cephede bizden açıkça önde:

| # | Cephe | Kim önde | Neden önemli |
|---|---|---|---|
| 1 | **Animasyonlu altyazı ve tek dokunuş "AI Edit stilleri"** | Captions, Submagic, CapCut | Kısa videonun görünen kalitesi büyük ölçüde altyazı ve stilden geliyor; kullanıcı ilk 10 saniyede buna bakıyor |
| 2 | **Uzun videodan kısa klip (long-to-short)** | Opus Clip, Captions (Clips Chat), BIGVU (Auto-Shorts) | En çok para ödenen iş akışı |
| 3 | **Yüz/ses yapay zekâsı: göz teması, AI ikiz, dudak senkronlu dublaj, çeviri** | Captions, BIGVU, CapCut | Teleprompter kullanıcısının tam hedef kitlesi |
| 4 | **Efekt, şablon, müzik, SFX kütüphanesi ve trend** | CapCut, Edits, Premiere | Kullanıcı "boş sayfa" ile başlamak istemiyor |
| 5 | **Pro timeline: ana klip keyframe, hız eğrisi, multicam, LUT, arka plan silme** | Premiere iPhone, LumaFusion, VN, Edits | "Ciddi" üreticinin geçiş maliyeti |
| 6 | **Dağıtım ve süreklilik: platforma yayın, bulut senkron, Mac/masaüstü, ekip** | Captions, Premiere, Edits, BIGVU | Uygulamada kalma ve ekip satışı |

Bu raporun iddiası şu: bu altı cephenin her birinde **aynı özelliği kopyalamak yetmez**. CueTake'in elinde rakiplerde olmayan üç veri var ve her hedefi bunlarla daha iyi yapacağız:

1. **Script:** Çekimden önce ne söyleneceğini biliyoruz. Transcript'i tahmin etmiyoruz, script'le hizalıyoruz.
2. **Çekim anı:** Kamerayı biz açıyoruz. Göz teması, ışık ve kadraj sorununu sonradan onarmak yerine çekerken önleyebiliyoruz.
3. **Görünen AI yönetmen:** Her AI kararı zaman çizelgesinde bir adım, bir aralık ve bir geri alma. Rakiplerde AI bir kara kutu.

---

## 2. Dart tahtası

Halkalar, hedefin ne kadar kritik olduğunu gösterir. Merkez: vurmazsak kullanıcı kaybederiz. Dış halka: vurursak fark yaratırız.

```text
                          ┌────────────────────────────────────────────┐
                        ┌─┘  DIŞ HALKA (P2) — fark yaratan              └─┐
                      ┌─┘  AI ikiz · dudak senkronu · Restyle · masaüstü  └─┐
                    ┌─┘  ekip çalışma alanı · performans geri bildirimi     └─┐
                  ┌─┘ ┌────────────────────────────────────────────────┐    └─┐
                  │   │  ORTA HALKA (P1) — geçiş maliyeti               │      │
                  │   │  ana klip keyframe · hız eğrisi · LUT · multicam│      │
                  │   │  arka plan silme · müzik/SFX · YouTube/IG yayın │      │
                  │   │  bulut senkron · çeviri/dublaj · marka kiti     │      │
                  │   │   ┌────────────────────────────────────────┐    │      │
                  │   │   │  MERKEZ (P0) — kaybettiren açıklar      │    │      │
                  │   │   │  animasyonlu altyazı + stil paketleri   │    │      │
                  │   │   │  long-to-short + otomatik reframe       │    │      │
                  │   │   │  dolgu/tekrar/sessizlik temizliği       │    │      │
                  │   │   │  göz teması (çekimde önle, sonra onar)  │    │      │
                  │   │   │  hızlı ve güvenilir render/export       │    │      │
                  │   │   └────────────────────────────────────────┘    │      │
                  │   └────────────────────────────────────────────────┘      │
                  └───────────────────────────────────────────────────────────┘
```

| Rakip | Ana tehdit | Merkezde vurduğu yer | Bizim kozumuz |
|---|---|---|---|
| **Captions / Mirage** | Bizim hedef kullanıcıyla birebir aynı: telefonda konuşan kafa | AI Edit stilleri, altyazı, göz teması, AI ikiz, long-to-short, çok cihaz | Script farkındalığı, görünen AI adımları, BYOK, cihaz içi gizlilik |
| **CapCut** | Ücretsiz, devasa efekt/şablon kütüphanesi, üretken modeller | Altyazı, şablon, sessizlik silme, avatar | Konuşan kafa için odak, workflow + API, geri alınabilir AI |
| **Instagram Edits** | Ücretsiz, 4K, teleprompter dahil, IG'ye bağlı | Teleprompter + kurgu aynı yerde, efekt, Restyle | Script'ten kurguya kesintisiz hat; platformdan bağımsız |
| **Adobe Premiere (iPhone)** | Pro timeline ücretsiz, Firefly entegrasyonu | Sınırsız çoklu iz, keyframe, LUT, arka plan silme, Shorts yayını | AI yönetmen, konuşan kafa otomasyonu, workflow |
| **BIGVU** | Teleprompter kökenli, "pro" satış (emlak, koç) | Teleprompter + göz teması + avatar + yayın + marka | Daha iyi kurgu ve AI; workflow API ile kurumsal entegrasyon |
| **Opus Clip / Submagic** | Long-to-short ve altyazıda kategori lideri (çoğunlukla web) | Viralite skoru, ReframeAnything, animasyonlu altyazı | Telefonda uçtan uca; çekim + kurgu aynı uygulamada |
| **Descript** | Transcript'le kurgu standardı (masaüstü) | Dolgu kelime/tekrar silme, Studio Sound, Underlord | Mobilde ve script'e hizalı transcript kurgu |
| **VN / LumaFusion / InShot** | Ücretsiz ya da tek seferlik pro araçlar | Keyframe, multicam, 4K | Aynı kontrolü AI ile daha az dokunuşta vermek |

---

## 3. Rakip profilleri

Bilgiler resmi sayfalar, sürüm notları ve 2026 incelemelerinden derlendi; bağımsız ölçüm değildir. Ürün beyanı olarak okunmalı.

### Captions (Mirage)

- **Konum:** Telefonda konuşan kafa videosunun AI editörü. 2026'da 75 milyon dolar yatırım aldı ve kendi video modellerini geliştiriyor.
- **2026 sürüm notlarından öne çıkanlar:**
  - AI Edit V3 (Ocak), üstüne adlı stil paketleri: Prism, Linen, Evo, Focus, Stack, Lift, Chalk, Bloom, Bitmap, Atrium, Aperture, Pop, Orbit.
  - Çok klipli AI Edit ve klip birleştirme.
  - iOS'ta long-to-short (Haziran), "Clips Chat" ile sohbetle farklı klip isteme (Ağustos).
  - Tam proje senkronu, gerçek zamanlı çok cihaz, macOS uygulaması (Temmuz), varsayılan Teams çalışma alanı.
  - AI Twin (videodan oluşturma), avatar görünümleri, ses klonlama.
  - 30 dakikaya kadar transkripsiyon, bulutta saklanan özel altyazı şablonları, kelime grubu düzenleme, ters/negatif altyazı stili, konturlu altyazı arka planı.
  - Daha hızlı render motoru.
- **Ayrıca:** AI Eye Contact, çeviri ve dudak senkronlu dublaj (Lipdub kökeni), çok dilli altyazı, sohbetle kurgu (co-editor).
- **Zayıf yanı:** AI kararları kara kutu; stil bir preset, neyin neden değiştiği adım adım görünmüyor. Kredi ekonomisi pahalı. Çekim tarafı zayıf.

### CapCut

- **Konum:** Ücretsiz, en geniş efekt/şablon/müzik kütüphanesi; TikTok ile doğal akış.
- **AI:**
  - Otomatik kurgu, 130+ dilde anlık altyazı, sessizlik silme, akıllı arka plan müziği, geçişler.
  - AI avatar, 269 sesli TTS.
  - Üretken modeller: Seedance 2.0 (video), Seedream 5.0 (görsel), Nano Banana Pro.
  - Sonsuz tuvalli AI Design Studio.
- **Editör:** Keyframe, hız eğrisi, chroma, maske, beat işaretleri, otomatik reframe, motion tracking, ses efektleri.
- **Zayıf yanı:** Konuşan kafa için özel bir hat yok; kalabalık arayüz; gizlilik ve bölgesel erişim kaygısı; AI değişiklikleri geri alınabilir adımlar olarak listelenmiyor.

### Instagram Edits (Meta)

- **Konum:** Tamamen ücretsiz; 4K ve AI efektleri paywall'suz. Instagram'a bağlı. Masaüstü sürümü geliştiriliyor.
- **Özellikler:**
  - Teleprompter, storyboard (çoklu çekim karşılaştırma), kare hassasiyetinde timeline.
  - Nesne düzeyinde efekt için AI segmentasyon, Restyle (metinle görünüm değiştirme), AI video üretimi.
  - Yeşil perde/cutout, beat işaretleri, 150–200+ SFX, kendi sesini içe aktarma.
  - "Loudness Match", 15 dilde çift dilli altyazı, proje sürümleri.
  - Haftalık fikirler, trend ilhamı, IG bağlantıları, 15 dakikalık export (iOS), beta sekmesi.
- **Zayıf yanı:** AI kurgu yönetmeni yok; script üretimi ve script'e göre kurgu yok; yalnızca Meta ekosistemine yönelik.

### Adobe Premiere (iPhone)

- **Konum:** Eylül 2025'te çıktı; aboneliksiz kullanılabiliyor, Firefly kredileri ücretli.
- **Özellikler:**
  - Sınırsız çoklu iz (video/ses/metin).
  - Transform aracı (ölçek/dönüş/X-Y), `.cube` LUT içe aktarma ve Looks paneli.
  - Ses keyframe'leri.
  - Geliştirilmiş arka plan silme (kenar, hareket, ince detay).
  - Firefly ile SFX ve varlık üretimi.
  - Şablon kütüphanesi, yeni geçiş/efekt ve YouTube metin şablonları.
  - Doğrudan YouTube Shorts yayını.
- **Zayıf yanı:** AI yönetmen yok; teleprompter/script yok; Adobe hesabı ve kredi sürtünmesi.

### BIGVU

- **Konum:** Teleprompter'dan doğmuş "hepsi bir arada" profesyonel video platformu. 12 milyon kullanıcı beyanı; emlakçı, koç ve pazarlamacı hedefi.
- **Özellikler:**
  - AI script üretici, canlı kayan teleprompter.
  - AI Eye Contact Fix, otomatik altyazı, AI B-roll, Auto Zoom, AI müzik, arka plan değiştirme, Audio Boost, düzen ve logolar.
  - Marka kiti, AI avatar / konuşan fotoğraf, Auto-Shorts Agent.
  - Video e-posta (Gmail/Outlook), AI landing page, izlenme takibi.
  - IG/YouTube/TikTok/LinkedIn'e doğrudan yayın.
- **Zayıf yanı:** Kurgu derinliği sınırlı; AI araçları ayrı ayrı düğmeler, birleşik bir yönetmen değil.

### Opus Clip ve Submagic

- **Opus Clip:** ClipAnything (an tespiti) ve ReframeAnything (özneyi seçip takip eden reframe). Viralite skoru, dinamik altyazı, marka şablonu, API.
- **Submagic:**
  - 48+ dilde kelime düzeyinde animasyonlu altyazı; emoji tetikleyiciler, anahtar kelimeye SFX.
  - Sessizlik/dolgu silme, bağlamsal stok B-roll, otomatik zoom, hook başlığı.
  - Mobil uygulama eksikliği kullanıcı yorumlarında şikâyet konusu.
- **Ortak teknik hat:** ASR ile kelime zamanı → LLM ile an seçimi → yüz takibiyle 9:16 kırpma → karaoke altyazı → render.

### Descript

- **Konum:** Transcript'le kurgunun standardı.
- **Özellikler:** Underlord co-editor, Edit for Clarity, Studio Sound, dolgu kelime ve tekrar çekim silme, Overdub ses klonu.
- **Mobil:** 2026 itibarıyla tam mobil editör yok. Bu boşluk bizim.

### VN, LumaFusion, InShot

- **VN:** Ücretsiz; çoklu iz, keyframe, 4K.
- **LumaFusion:** Tek seferlik ödeme; 6 video/ses izi, tam keyframe, multicam, harici depolama, renk.
- **InShot:** Hızlı sosyal kurgu.
- **Ders:** "Pro kontrol" artık ücretsiz ya da tek seferlik bir beklenti.

---

## 4. CueTake bugün ne yapıyor

Kodla doğrulanmış envanter, build 80:

| Alan | Var olan | Modül |
|---|---|---|
| Script | Foundation Models ile cihazda script yazma ve yeniden yazma, blueprint, segmentler | `ScriptFeature`, `AIServices` |
| Çekim | AVCaptureSession, teleprompter (konuşmayı takip eden), retake, çerçeveleme ızgarası | `CaptureEngine`, `StudioFeature`, `Teleprompter` |
| Konuşma | SpeechAnalyzer/SpeechTranscriber, SFSpeechRecognizer yedeği, konuşma aktivitesi | `SpeechEngine`, `MediaEngine/VoiceActivity` |
| Timeline | Segmentler, trim/split, ripple silme + geri al toast'u, video katmanları, overlay, efekt, ses şeritleri, kamera hareketi şeridi, takip şeridi | `EditorFeature` |
| Ses | Çoklu ses, satır (lane), mikser, ses temizleme, ters ses, dalga formu, SFX | `AudioMixer`, `VoiceCleaner`, `SoundEffectRenderer` |
| Görüntü | Filtre compositor, arka plan kaldırma (kişi), overlay renderer, 15 geçiş | `FilterCompositor`, `BackgroundRemover`, `TransitionComposer` |
| Kadraj | Vision yüz + genel nesne takibi, güven değeri, yerel düzeltme, zoom kanalı, kamera tarifleri (hold/push/pull/punch) | `SubjectTracker`, `CameraMotion*` |
| Altyazı | Otomatik altyazı, hızlı düzenleme, render | `CaptionRenderer`, `CaptionsScreen` |
| AI kurgu | Worker üzerinden `EditPlan` → `AIDirector` adım adım uygular; her adım geri alınabilir; AI değişiklikleri listesi | `AIDirector`, `backend/assistant` |
| Üretim | BYOK: fal, Veo, Sora, Replicate; editörde "Üret", B-roll yerleştirme | `GenerationEngine` |
| Workflow | Adım tabanlı stüdyo, AI workflow yazarı, zorunlu son Export, workflow'a özel API teslimi | `WorkflowEngine`, `WorkflowsFeature` |
| Export | Dayanıklı yazıcı (H.264'e düşme, altyazısız yeniden deneme), Fotoğraflar/Dosyalar | `VideoComposer`, `ExportScreen` |
| Güvenlik | Anahtarlar cihaz Keychain'inde (`ThisDeviceOnly`); sağlayıcı anahtarı uygulamada yok | `Persistence` |

**Yok olanlar:**
- **Kurgu ve altyazı:** Animasyonlu altyazı stil motoru, long-to-short, dolgu/tekrar silme, ana klip keyframe, hız eğrisi, LUT, multicam.
- **Yüz, ses ve kütüphane:** Göz teması, dublaj/çeviri, müzik kütüphanesi, beat motoru.
- **Dağıtım ve süreklilik:** Platform yayını, bulut senkron, arka plan render/yükleme, Mac, ekip.
- **Sistem:** Metal render çekirdeği, App Intents.

---

## 5. Hedefler: rakibin bizi geçtiği her konu ve bizim cevabımız

Her hedef aynı kalıpla yazıldı: **kim önde ve nasıl** → **bizim "çok daha iyi" tasarımımız** → **teknik altyapı** → **kabul ölçütü**.

### H1 — Animasyonlu altyazı motoru ve stil paketleri (P0, merkez)

**Kim önde:**
- Submagic: kelime düzeyinde animasyon, emoji ve anahtar kelime SFX'i.
- Captions: 15+ adlı AI Edit stili, bulutta şablon, kontur ve negatif stil.
- CapCut: dev şablon havuzu.

**Bizim tasarımımız:**
- **Stil = bildirimsel paket.** Bir stil; altyazı, zoom ritmi, geçiş, müzik karakteri, renk görünümü ve B-roll yoğunluğunu birlikte tanımlayan bir JSON'dur. AI yönetmen bu paketi *adım adım* uygular, her adım geri alınabilir. Rakipte stil bir kara kutu, bizde düzenlenebilir bir tarif.
- **Konuşmaya duyarlı yerleşim.**
  - Altyazı yüzün ve ağzın üstüne binmez; `SubjectTracker` yüz kutusunu zaten biliyor.
  - Platform güvenli alanları dikkate alınır (TikTok/Reels/Shorts arayüz bölgeleri).
- **Okuma hızı garantisi.** Kelime/saniye ve satır uzunluğu sınırları otomatik uygulanır; ihlal bir "bulgu" olarak gösterilir.
- **Vurgu = script'ten.** Script yazılırken işaretlenen anahtar kelimeler altyazıda otomatik vurgulanır. Rakip bunu transcript'ten tahmin ediyor.
- **Emoji ve SFX tetikleyicileri** kelime anlamından (AI) ve kullanıcının kendi sözlüğünden gelir.

**Teknik altyapı:**
```text
Domain/Captions/CaptionStyle.swift      stil DSL: layout, font, renk, kontur, arka plan,
                                        giriş/çıkış animasyonu, kelime vurgu modu (karaoke,
                                        pop, highlight box, color sweep), emoji kuralı
Domain/Captions/StylePack.swift         altyazı + kamera ritmi + geçiş + görünüm + müzik etiketi
MediaEngine/CaptionAnimator             kelime zamanlarından kare bazlı durum (saf fonksiyon)
MediaEngine/CaptionRenderer             Core Animation katmanları → AVVideoCompositionCoreAnimationTool
                                        (bugünkü yol); Faz M'de Metal metin atlası
EditorFeature/CaptionStyleGallery       canlı önizlemeli galeri, favori, marka kiti bağlantısı
backend/assistant                       stil paketi kataloğu + AI'ın paket seçmesi
```
- **Kelime zamanı:** `SpeechTranscriber` ile `audioTimeRange` kelime başına alınır; script hizalaması (H3) ile düzeltilir.
- **Font:** Uygulama paketinde lisanslı fontlar; kullanıcı fontu `UIFontPickerViewController` ile eklenir.
- **Önizleme ve export aynı `CaptionAnimator` fonksiyonundan beslenir.** Sapma testi: aynı kare için iki yol piksel karşılaştırması.

**Kabul:**
- 20 stil paketi hazır.
- Her paket tek dokunuşla uygulanıyor ve adım adım geri alınıyor.
- 60 saniyelik videoda yüzle çakışan altyazı karesi %1'in altında.
- Önizleme ve export eşleşiyor.

### H2 — Long-to-short ve otomatik reframe (P0, merkez)

**Kim önde:**
- Opus Clip: ClipAnything, viralite skoru, ReframeAnything.
- Captions: iOS long-to-short, Clips Chat.
- BIGVU: Auto-Shorts Agent.

**Bizim tasarımımız:**
- **Telefonda uçtan uca.** Uzun video içe alınır; transcript, sahne, yüz ve ses analizi arka planda cihazda çalışır. LLM yalnızca metin ve metrik görür, video buluta gitmez.
- **Skor açıklanabilir.** Her aday klip için hook gücü, tamamlanmış düşünce, duygu zirvesi, tempo ve görsel çeşitlilik ayrı çubuklar hâlinde görünür. Tek bir "viralite 87" sayısı yerine *neden* gösterilir.
- **Sohbetle yeniden seçim.** Örnek istek: "daha komik olanlar", "30 saniyeden kısa", "fiyatla ilgili kısım". Mevcut `AIComposer` bunun için yeterli.
- **Reframe bizim takip motorumuzla.**
  - Konuşan kişiyi seçmek için ses yönü ve dudak hareketi kullanılır (çok kişili podcast).
  - Kamera hareketi, mevcut Camera Lane tarifleriyle doğal yapılır.
  - Kullanıcı yanlış özneyi tek dokunuşla düzeltir (`SubjectTrackingEditor`).
- **Klip = yeni proje.** Kaynağa bağlı kalır; kaynak altyazı düzeltmesi tüm kliplere yayılabilir.

**Teknik altyapı:**
```text
MediaEngine/MediaIndex (yeni)     kayıt başına kalıcı analiz: kelimeler, cümleler, konuşmacı
                                  değişimi, sahne kesmeleri, yüz izleri, ses yüksekliği, beat
                                  → proje klasöründe `index/<recordingID>.json`, kaynak hash'li
MediaEngine/SceneDetector         VNGenerateImageFeaturePrintRequest mesafesi + histogram farkı
MediaEngine/SpeakerTurns          SoundAnalysis + enerji; çok yüzde ağız açıklığı
                                  (VNDetectFaceLandmarksRequest) ile konuşanı eşle
WorkflowEngine/HighlightStep      transcript → worker `/highlights` → aday aralıklar + gerekçe
Domain/Project/ClipDerivation     kaynak proje + aralık + reframe tarifi
BGContinuedProcessingTask         iOS 26: kullanıcının başlattığı uzun analiz/render ön plan
                                  dışında sürer, sistem ilerleme arayüzü gösterir
```
- **Uzun kaynak:** 60 dakikaya kadar. Transkripsiyon parça parça, `SpeechAnalyzer` ile akış hâlinde yapılır. Kesilirse kaldığı yerden devam eder (indeks yazıldıkça kalıcı).
- **Worker maliyeti:** Transcript cümle kimlikleriyle sıkıştırılır; model yalnızca kimlik döndürür. Token sayısı ~%40 azalır, halüsinasyonla uydurulan zaman damgası olmaz.

**Kabul:**
- 30 dakikalık podcast iPhone 16'da 6 dakikadan kısa sürede 10 aday klibe dönüşüyor (analiz + skor).
- Her adayın gerekçesi görünüyor.
- İki kişili kayıtta konuşmacı kadrajı %90 doğru (elle etiketli set).

### H3 — Script'e hizalı temizlik: dolgu, tekrar, sessizlik, en iyi çekim (P0, merkez)

**Kim önde:**
- Descript: dolgu, tekrar çekim ve "edit for clarity".
- CapCut ve Submagic: sessizlik silme.

**Bizim tasarımımız (kimsede olmayan):**
- **Script hizalaması.**
  - Kaydın transcript'i, çekilen segmentin script'iyle kelime düzeyinde hizalanır (Needleman–Wunsch / DTW, fonetik benzerlik).
  - Script'te olmayan her kelime aday: dolgu ("ııı", "yani", "şey"), tekrar başlangıç, yanlış okuma.
  - Descript bunu tahmin ediyor; biz *ne söylenmesi gerektiğini* biliyoruz.
- **En iyi çekim seçici.**
  - Aynı cümle için birden çok çekim varsa her biri puanlanır: script doğruluğu, akıcılık, göz teması (H4), ses kalitesi, enerji.
  - En iyisi otomatik seçilir; diğerleri tek dokunuşla değiştirilebilir.
  - Edits'in storyboard'da yalnızca çekimleri yan yana koymasının ötesine geçer.
- **Cümle bazında yeniden çekim.** Kötü cümle işaretlenir; Studio yalnız o cümleyi teleprompter'a koyar ve yeni çekimi aynı yere yerleştirir. Bugünkü retake segment bazında; bunu cümleye indiriyoruz.
- **Doğal kesim.** Kesim noktası kelime sınırına ve sıfır geçişine hizalanır, 20–40 ms ses crossfade yapılır. İstenirse kesimde mikro "punch" zoom ile atlama gizlenir; bu, zoom motoruyla ortak.

**Teknik altyapı:**
```text
Domain/Script/ScriptAlignment      hizalama algoritması (saf, test edilebilir), TR/EN
                                   normalizasyon, sayı/tarih sözlüğü
Domain/Speech/Disfluency           dolgu sözlüğü (dil bazlı) + hizalamadan gelen fazlalık
MediaEngine/TakeScorer             ses: RMS/clipping/SNR; görüntü: göz, yüz, bulanıklık
EditorFeature/CleanupPanel         "Temizle": sessizlik eşik slider'ı, dolgu listesi (tek tek
                                   aç/kapa), tekrarlar, tahmini kazanılan süre
Timeline                           silinen aralıklar "hayalet" olarak görünür, geri açılabilir
                                   (source-time aralığı saklanır, ripple ile uyumlu)
```

**Kabul:**
- Türkçe ve İngilizce 20 kayıtlık sette dolgu tespitinde kesinlik %90'ın, geri çağırma %80'in üstünde.
- Sessizlik silme sonrası kesimde duyulabilir tık yok.
- En iyi çekim seçimi kullanıcı tercihinde %70'in üstünde eşleşiyor.

### H4 — Göz teması: çekimde önle, sonra onar (P0, merkez)

**Kim önde:** Captions AI Eye Contact, BIGVU Eye Contact Fix (post-process bakış düzeltme).

**Bizim tasarımımız:**
- **Önce önle.**
  - Teleprompter metni kameranın hemen altında dar bir sütunda akar; satır uzunluğu cihazın lens konumuna göre ayarlanır.
  - Göz sapması canlı ölçülür; sapma artınca metin daralır veya hızlanır.
  - İsteğe bağlı "göz koçu" ince bir halka ile uyarır.
  - Rakipler sorunu yaratıp sonra onarıyor; biz sorunu azaltıyoruz.
- **Sonra onar.**
  - Kalan sapma için bakış yönlendirme uygulanır. Yoğunluk slider'ı var; göz kırpma ve doğal sakkadlar korunur.
  - Doğal olmayan "sabit bakış" hissini önlemek için %100 değil, hedefe doğru kısmi düzeltme varsayılan.
- **Şeffaflık.** Düzeltilen aralıklar timeline'da işaretlenir ve kapatılabilir.

**Teknik altyapı:**
- **Ölçüm (cihazda):**
  - `VNDetectFaceLandmarksRequest` göz bebeği noktaları ve yüz yönü (yaw/pitch) verir.
  - ARKit yüz takibi (TrueDepth) çekim sırasında `lookAtPoint` sağlar; ön kamerada daha doğru.
  - Çekim anında sapma bir zaman serisi olarak kayda yazılır (`Recording.gaze`).
- **Düzeltme, iki yol:**
  1. **Cihazda Core ML bakış yönlendirme modeli.** Göz bölgesi kırpılır, küçük bir encoder-decoder uygulanır, sonuç harmanlanır. Açık kaynak gaze-redirection çalışmaları üzerinde eğitim ya da lisans gerekir; model boyutu hedefi 10 MB'ın altında. Önce ölçülür, sonra gömülür.
  2. **BYOK/worker ile bulut model.** Sağlayıcıda uygun bir model varsa kullanılır; video yalnız kullanıcı izin verirse gider.
- **Harmanlama:** Göz bölgesi maskesi Core Image ile uygulanır; kareler arası tutarlılık için optik akış (`VNGenerateOpticalFlowRequest`) ile titreme süzülür.

**Kabul:**
- Teleprompter ile çekilen videoda ortalama bakış sapması ilk sürüme göre %40 azalıyor.
- Düzeltme açıkken kör testte "kameraya bakıyor" oranı %80'in üstünde, "tuhaf görünüyor" oranı %10'un altında.

**Risk:** Model kalitesi ve lisansı en büyük belirsizlik; önce ölçüm ve prototip (bkz. Faz 2 kapısı).

### H5 — Render/export hızı ve güvenilirliği (P0, merkez)

**Kim önde:**
- Captions: "daha hızlı render motoru".
- Premiere ve CapCut: donanım hızlandırmalı pipeline.

**Bizim tasarımımız:**
- **Önizleme ve export tek değerlendiriciden geçer** (bugün kısmen var): aynı geometri, aynı filtre, aynı altyazı durumu.
- **Arka planda export.** Kullanıcı uygulamadan çıksa da render devam eder (`BGContinuedProcessingTask`); ilerleme Live Activity'de görünür.
- **Kalite kapısı.** Export sonrası otomatik kontrol yapılır: süre, siyah kare, sessiz bölüm, altyazı taşması, ses seviyesi (LUFS). Bulgu varsa rapor çıkar.

**Teknik altyapı:**
```text
MediaEngine/MetalCompositor (yeni)   AVVideoCompositing, CVMetalTextureCache ile sıfır kopya;
                                     filtre + geçiş + altyazı + overlay tek pass; Core Image
                                     yalnız gerekli yerde (CIRenderDestination, Metal context)
MediaEngine/ExportPipeline           AVAssetReader/AVAssetWriter; HEVC donanım encoder'ı
                                     (VTCompressionSession özellikleri), 10-bit HDR yolu
MediaEngine/ExportQA                 AVAssetReader ile örnekleyip bulgu üretir
Persistence/RenderCache              segment başına önceden render (smart render): değişmeyen
                                     segmentler yeniden kodlanmaz
```

**Kabul:**
- 60 saniye 1080p30, filtre + altyazı + 3 geçiş: iPhone 15'te 20 saniyenin altında.
- Uygulama arka plana alındığında export tamamlanıyor.
- 100 ardışık export'ta sıfır başarısızlık (CI'da simülatör + cihaz testleri).

### H6 — Şablon, efekt, geçiş ve görünüm kütüphanesi (P1)

**Kim önde:**
- CapCut: dev kütüphane.
- Edits: 25 yeni efekt, 15 giriş/çıkış animasyonu, opaklık karışımı.
- Premiere: şablon kütüphanesi, `.cube` LUT, Looks.

**Bizim tasarımımız:**
- **Şablon = yer tutuculu proje parçası.**
  - Yuvaları olan bir yapıdır: "burada hook cümlesi", "burada ürün B-roll'ü", "burada CTA".
  - AI yuvaları kullanıcının script'i ve çekimleriyle doldurur. CapCut şablonu medya bekler; bizimki içerik anlar.
- **Görünüm (Look).** Renk düzeltme + LUT + grain + vignette tek pakette. `.cube` içe aktarılır. Önce/sonra için basılı tutma karşılaştırması var.
- **Efekt çekirdekleri** Metal ile yazılır (glitch, RGB split, fisheye, bounce, shake, blur ailesi). Parametreleri keyframe'lenebilir.
- **Geçişler** bugünkü 15'in üzerine Metal shader ailesi olarak genişler: glitch, ışık sızıntısı, film yanığı, whip pan, morph. Mevcut taşıyıcı iz mimarisi korunur.

**Teknik altyapı:**
```text
Domain/Templates/Template            yuvalar, kurallar, stil paketi referansı, sürüm
Domain/Effects/Look                  CIColorCube (LUT), ton eğrisi, sıcaklık/renk tonu
MediaEngine/Shaders/*.metal          CIKernel (Metal) efekt ve geçiş çekirdekleri
backend/catalog (yeni)               şablon/efekt/LUT kataloğu; uygulama sürümünden bağımsız
                                     yayın (R2 + imzalı manifest), cihazda önbellek
```

**Kabul:**
- 30 şablon, 40 efekt, 30 geçiş, 25 görünüm.
- Katalog uygulama güncellemesi olmadan genişliyor.
- Her efekt önizlemede 30 fps'yi koruyor (iPhone 13 ve üstü).

### H7 — Pro timeline: ana klip keyframe, hız eğrisi, ses keyframe'i, proje sürümleri (P1)

**Kim önde:**
- Premiere: transform aracı, ses keyframe'leri, sınırsız iz.
- VN ve LumaFusion: tam keyframe.
- Edits ve CapCut: hız eğrisi ve proje sürümleri.

**Bizim tasarımımız:**
- **Tek Motion Graph.**
  - Ana klip transform'u (konum, ölçek, dönüş, opaklık, kırpma) Camera Lane ile aynı kanal sisteminde tutulur.
  - Takip, zoom tarifi, sarsıntı ve elle keyframe ayrı *katkılar* olarak karışır; birbirini ezmez.
  - Rakiplerde elle keyframe otomatik takibi siler.
- **Hız eğrisi.**
  - Bezier preset'leri var (montaj, kahraman, zıplama).
  - Ses perdesi korunur (`AVAudioTimePitchAlgorithm.spectral`).
  - Altyazı ve efekt zamanları source-time dönüşümüyle otomatik kayar (`ClipPlayback`).
- **Ses keyframe'i.** Seviye zarfı noktaları dalga formu üstünde düzenlenir. AI ducking aynı zarfı üretir.
- **Proje sürümleri.** "Bu sürümü sakla" ile anlık görüntü alınır; sürümler arasında A/B oynatma yapılabilir. AI kurgu her zaman yeni sürümde başlar.

**Teknik altyapı:**
```text
Domain/Motion/MotionChannel       anahtar kareler + eğri (Bezier/spring), katkı modu
Domain/Motion/MotionGraph         kanalların birleşimi (saf; preview/export ortak)
Domain/Timeline/SpeedCurve        zaman eşleme integrali; ters eşleme (sayısal)
AVMutableComposition              hız eğrisi: parçalı scaleTimeRange, 1/30 sn çözünürlük
AudioEnvelope                     mevcut; keyframe noktaları + AVMutableAudioMixInputParameters
Persistence/ProjectVersions       proje klasöründe `versions/<id>.json`, medya paylaşımlı
```

**Kabul:**
- Keyframe'li ana klip önizleme ve export'ta piksel eşleşiyor.
- Hız eğrisinde altyazılar konuşmayla ±1 karede kalıyor.
- Sürüm geçişi 300 ms'den kısa.

### H8 — Arka plan silme, yeşil perde, nesne segmentasyonu (P1)

**Kim önde:**
- Premiere: gelişmiş arka plan silme.
- Edits: nesne düzeyinde AI segmentasyon.
- CapCut: chroma ve maske.

**Bizim tasarımımız:**
- **Özne seçimi takip motoruyla ortak.** Bir kez seçilen özne; kadraj, maske, bulanıklık, yazı arkası ("metin öznenin arkasında") için kullanılır.
- **Zamansal kararlılık.** Maske kenar titremesi kareler arası süzülür; saç ve kenar için ince ayar yapılır.
- **Chroma key.** Renk seçici, tolerans, kenar yumuşaklığı ve taşma (spill) bastırma.

**Teknik altyapı:**
- **Maske kaynakları:**
  - `VNGeneratePersonSegmentationRequest` (kişi, akış modu).
  - `VNGenerateForegroundInstanceMaskRequest` (genel nesne, örnek seçimi).
  - `VNGeneratePersonInstanceMaskRequest` (çok kişi).
- **İşleme:**
  - Maske hazırlığı önceden hesaplanıp `MediaIndex`'e düşük çözünürlükte yazılır. Export'ta yüksek çözünürlüğe guided filter ile büyütülür (Metal).
  - Chroma: Metal çekirdeği (YUV uzayında mesafe + spill suppression).
- **"Metin arkada":** Overlay katmanı ile maske arasında sıralama; `OverlayRenderer`'a derinlik sırası eklenir.

**Kabul:**
- 1080p kişi maskesinde kenar titremesi görsel testte kabul ediliyor.
- Metin-arkada efekti 30 fps önizleniyor.

### H9 — Müzik, SFX, beat senkronu, ses seviyesi eşitleme (P1)

**Kim önde:**
- Edits: 200+ SFX, Loudness Match, kendi sesini içe aktarma.
- Premiere: Firefly ile SFX üretimi.
- CapCut: dev müzik kütüphanesi.
- Captions ve BIGVU: AI müzik.

**Bizim tasarımımız:**
- **Beat motoru her şeyi besler.** Kesim noktaları, zoom vuruşları, geçiş zamanlaması ve altyazı girişleri müziğin vuruşuna "yapışabilir". Bir anahtar ile açılıp kapanır.
- **Konuşmaya duyarlı ducking.** Konuşma sırasında müzik alçalır; nefes aralarında yavaşça yükselir. Zarf ses keyframe'i (H7) olarak düzenlenebilir.
- **Loudness.** Platform hedeflerine göre otomatik normalize (−14 LUFS entegre, −1 dBTP tepe); ölçüm export QA'da raporlanır.
- **Kütüphane.**
  - Lisanslı katalog (sağlayıcı anlaşması gerekir).
  - BYOK ile üretilmiş müzik/SFX (ör. fal üzerindeki ses modelleri, ElevenLabs sound effects).
  - Kullanıcının kendi dosyaları.
  - Şarkılar "ruh hâli / tempo / enerji" ile aranır.

**Teknik altyapı:**
```text
MediaEngine/BeatDetector       vDSP spektral akı onset + otokorelasyon tempo; downbeat tahmini
MediaEngine/Loudness           ITU-R BS.1770 K-ağırlıklı ölçüm (vDSP biquad), true-peak 4x
MediaEngine/Ducking            VoiceActivity + zarf üretimi (atak/bırakma)
SoundAnalysis                  SNClassifySoundRequest: müzik/konuşma/gürültü sınıfı
GenerationEngine               audio sağlayıcıları (BYOK) — mevcut video yapısıyla aynı protokol
```

**Kabul:**
- Beat tespiti etiketli 50 parçada ±50 ms içinde %85'in üstünde.
- Export'ların %100'ü hedef LUFS'a ±1 LU içinde.

### H10 — Çeviri, çok dilli altyazı, dublaj ve dudak senkronu (P1 çeviri, P2 dublaj)

**Kim önde:**
- Captions: 100+ dile çeviri, dudak senkronlu dublaj.
- Edits: 15 dilde çift dilli altyazı.
- CapCut: 130+ dilde altyazı.

**Bizim tasarımımız:**
- **Çeviri cihazda.** Apple Translation framework (`TranslationSession`) ile altyazı çevirisi yapılır; ücretsiz ve gizli. Çift dilli altyazı bir stil seçeneğidir.
- **Script'ten çeviri.** Çekimden önce script çevrilir, kullanıcı ikinci dilde de teleprompter'la çekebilir. Rakipler yalnızca sonradan dublaj yapıyor.
- **Dublaj (BYOK).**
  - Ses klonu ve TTS sağlayıcısıyla hedef dilde ses üretilir.
  - Cümle süresine sığdırmak için AI yeniden yazma yapılır ve zaman germe ±%12 ile sınırlanır.
  - Dudak senkronu, sağlayıcının lipsync modeliyle yalnız yüz bölgesine uygulanır.
- **Açık rıza.** Ses klonu yalnız kullanıcının kendi sesi için; rıza kaydı tutulur, üretilen video meta verisine AI etiketi yazılır.

**Teknik altyapı:**
```text
Translation framework            TranslationSession (iOS 18+), dil paketi indirme durumu
Domain/Captions/BilingualLayout  iki satır düzeni, ikinci dilin stili
GenerationEngine/Voice (yeni)    TTS / voice clone / lipsync sağlayıcı protokolleri (BYOK)
Domain/Generation/Provenance     C2PA benzeri meta veri; export'ta AVMetadataItem
```

**Kabul:**
- TR↔EN altyazı çevirisi cihazda 60 saniyelik video için 3 saniyenin altında.
- Dublajda cümle kayması ±150 ms.

### H11 — AI ikiz, avatar ve Restyle (P2, dış halka)

**Kim önde:**
- Captions: AI Twin (videodan), avatar görünümleri, Mirage modelleri.
- BIGVU: avatar ve konuşan fotoğraf.
- Edits: Restyle.
- CapCut: Seedance.

**Bizim tasarımımız:** Kendi model eğitmiyoruz. BYOK ile en iyi sağlayıcıyı bağlıyoruz ve **kurguya entegre** ediyoruz:
- Avatar klibi normal bir segment gibi timeline'a girer; altyazı, zoom ve stil paketi aynı şekilde uygulanır.
- "Bu cümleyi yeniden çekmek yerine ikizime söylet" seçeneği var (H3 cümle bazında yeniden çekimle aynı yuva).
- Restyle, video-to-video sağlayıcısıyla seçili aralığa uygulanır; orijinal saklanır, A/B karşılaştırılır.

**Teknik altyapı:** `GenerationEngine`'e `avatarVideo`, `videoToVideo` ve `lipsync` yetenekleri eklenir. Mevcut kuyruk ve yer tutucu şeridi yeniden kullanılır.

**Kabul:**
- Avatar segmenti kurgu araçlarının tamamıyla çalışıyor.
- Üretim başarısız olunca proje bozulmuyor (bugünkü yer tutucu modeli).

### H12 — Platform yayını, zamanlama, performans geri bildirimi (P1 yayın, P2 geri bildirim)

**Kim önde:**
- Premiere: doğrudan YouTube Shorts.
- BIGVU: 4 platforma yayın, izlenme takibi.
- Edits: IG entegrasyonu ve içgörüler.

**Bizim tasarımımız:**
- **Workflow'un son Export'u yayına bağlanır.** Bugünkü API teslimi yanına "YouTube", "Instagram", "TikTok" hedefleri eklenir; zamanlama yapılabilir.
- **Başlık, açıklama, etiket ve kapak AI ile üretilir.** Kapak, en iyi kareden + başlıktan oluşur; A/B için iki hook sunulur.
- **Geri bildirim döngüsü.**
  - Yayınlanan videoların izlenme ve tutma verisi çekilir (API izin verdiği ölçüde).
  - AI sonraki script'i ve stil paketini buna göre önerir: "hook'ları 2 saniye kısa olanlar %30 daha iyi tuttu".

**Teknik altyapı:**
```text
Persistence/AccountStore        OAuth token'ları Keychain'de (ThisDeviceOnly)
Publishing/YouTubeConnector     Data API v3 resumable upload, ASWebAuthenticationSession
Publishing/InstagramConnector   Graph API content publishing (Reels, carousel)
Publishing/TikTokConnector      Content Posting API (direct post / inbox)
URLSession background config    uygulama kapalıyken yükleme (workflow teslimi de buraya taşınır)
Analytics/InsightsFetcher       YouTube Analytics API, IG Insights
```

**Dış bağımlılık:** Google OAuth doğrulaması, Meta uygulama incelemesi, TikTok denetimi. Kota: YouTube yükleme başına 1600 birim, varsayılan günlük 10.000.

**Kabul:**
- Uygulama kapalıyken zamanlanmış yükleme tamamlanıyor.
- Yayın hatası kullanıcıya düzeltilebilir bir mesaj olarak dönüyor.

### H13 — Bulut senkron, iPad/Mac, ekip (P1 senkron, P2 ekip)

**Kim önde:**
- Captions: tam proje senkronu, macOS, Teams.
- Edits: masaüstü geliyor.
- Premiere: Creative Cloud.

**Bizim tasarımımız:**
- **Yerel öncelikli senkron.** Proje JSON'u küçük parçalara ayrılır (segment, katman, altyazı); çakışma parça düzeyinde çözülür, medya ayrı ve ihtiyaç hâlinde iner.
- **iPad ve Mac aynı kod.** iPad'de geniş timeline; Mac'te "Designed for iPad" ile hızlı başlangıç, ardından Mac Catalyst ile klavye kısayolları.
- **Ekip.** Workflow ve stil paketleri paylaşılır; API anahtarları paylaşılmaz (bugünkü kural). Yorum ve onay akışı eklenir.

**Teknik altyapı:**
```text
CloudKit (private DB + CKSyncEngine)   proje parçaları kayıt olarak, medya CKAsset
Domain/Project/ProjectPatch            parça düzeyinde birleştirme (son yazan kazanır + alan
                                       bazında istisna), şema sürümü
Persistence/MediaVault                 iCloud'da medya, cihazda LRU önbellek, proxy dosyalar
Ekip (P2)                              CloudKit shared zones veya kendi backend'imiz (Cloudflare
                                       D1 + R2) — Faz 5 kararı
```

**Kabul:**
- iPhone'da yapılan düzenleme iPad'de 10 saniye içinde görünüyor.
- Çevrimdışı düzenleme veri kaybı olmadan birleşiyor.

### H14 — Marka kiti ve fikir motoru (P1)

**Kim önde:**
- BIGVU ve Opus: marka kiti.
- Edits: haftalık fikirler, trend ilhamı.

**Bizim tasarımımız:**
- **Marka kiti tek nesne.** Logo, renkler, fontlar, altyazı stili, intro/outro, CTA kartı ve watermark konumu. Workflow stiline ve stil paketlerine bağlanır.
- **Fikir motoru.** Kullanıcının nişi ve geçmiş videoları, haftalık 10 script fikri olarak sunulur; tek dokunuşla script ve teleprompter açılır. Edits fikir veriyor, biz çekime hazır script veriyoruz.

**Teknik altyapı:** `Domain/Brand/BrandKit`. Fikirler worker'da üretilir; geçmiş videoların yalnız başlık ve transcript özeti gönderilir. Bildirim `UNCalendarNotificationTrigger` ile tetiklenir.

### H15 — Multicam ve çift kamera çekimi (P1)

**Kim önde:** LumaFusion Multicam Studio.

**Bizim tasarımımız:**
- **Çekimde multicam.** `AVCaptureMultiCamSession` ile ön ve arka kamera, ya da geniş ve tele lens aynı anda kaydedilir. AI yönetmen cümle vurgusuna göre açı değiştirir. Rakipte sonradan senkron gerekir; bizde kayıt zaten senkron.
- **İçe aktarılan multicam** ses dalga formu çapraz korelasyonuyla hizalanır.

**Teknik altyapı:**
- **Senkron:** vDSP çapraz korelasyon (düşük örnekleme zarfında kaba arama, sonra ince arama).
- **Model:** `Domain/Timeline/CameraGroup`; açı değişimi yeni klip kopyalamaz, gruptaki açıyı seçer.
- **Donanım sınırı:** `AVCaptureMultiCamSession.hardwareCost` ve sistem baskısı izlenir; sınırı aşarsa çözünürlük düşer.

### H16 — Canlı Suflör: başka uygulamada yayındayken yanında (P1, fark yaratan)

**Fikir (kullanıcıdan, 2026-09-18):** Kişi TikTok/Instagram'da canlı yayın yapıyor ya da onların kamerasıyla çekiyor. Kamerasını değiştiremeyiz, ama yanında durabiliriz: yayından önce reklam brifi hazırlanır, yayında CueTake küçük bir PiP penceresinde ve Dynamic Island'da suflörlük yapar, bir butonla "şimdi ne konuşayım" önerisi verir.

**Rakipte:** PiP'te yüzen teleprompter birkaç uygulamada var. Reklam brifi, zamanlama, köprü cümlesi, söylenmesi gerekenler listesi ve markaya rapor olan yok.

**Kesin sınır — mikrofon paylaşılamaz:** iOS mikrofonu aynı anda tek uygulamaya verir. TikTok/IG yayını mikrofonu aldığı an bizim arka plan kaydımız kesilir (`audioDeviceInUseByAnotherClient`); arka planda yeniden başlatmak da mümkün değil. Bu yüzden **aynı telefonda yayın sırasında dinleme yok.** Test gerekmez, tasarım buna göre:
- **Tek telefon (ana mod):** dinleme yayından *önce* (brif, prova, hız ölçümü). Yayında suflör provada ölçülen hızla ilerler; PiP düğmeleri elle kontrol (oynat/durdur = duraklat, ileri = sıradaki kart / "ne konuşayım", geri = önceki). "Ne konuşayım" dökümü değil brifi, geçen süreyi ve hangi kartta olunduğunu kullanır.
- **İkinci telefon (tam mod):** yayını telefon A yapar, CueTake telefon B'de karşıda durur ve dinler. Söylenenler otomatik işaretlenir, takılma tespit edilir, köprü cümlesi son 2 dakikanın dökümünden gelir.
- Yayın sonrası: TikTok/IG kaydı CueTake'e alınırsa döküm çıkar, söylenen/unutulan maddeler raporlanır.

**Akış:**
1. Ana sayfada "Canlı Suflör" kartı.
2. Hazırlık: canlı mı çekim mi → reklam brifi (marka, ürün, kod/link, 2–3 zorunlu madde, zaman: "15. dk" ya da "ben basınca", ton; yaz ya da Worker hazırlasın: açılış, 3 madde, çağrı, 2 kurtarma cümlesi) → 20 sn prova (hız + mikrofon).
3. "Sahneye çık": kart PiP'e dönüşür, "TikTok'u aç / Instagram'ı aç" düğmeleri, Island'da sayaç.
4. Yayında PiP: reklama 30 sn kala amber halka, reklam anında marka rengi, karaoke metin; zorunlu maddeler listesi (tek telefonda elle, iki telefonda otomatik).
5. Island: kompakt "Reklam 2:14" / "✓ 2/3"; genişte sıradaki cümle, "Sıradaki" ve "Takıldım".
6. Rapor: reklam süresi, söylenen/unutulan, markaya gönderilebilir özet, "videoyu CueTake'e al".

**Animasyonlar (Reduce Motion'a uyar):** kart→PiP matchedGeometry yayı; nefes alan 3 çubuk dalga; dolan amber halka, son 5 sn nabız; tik çizgisi çizilir; öneri bulanıktan netleşip aşağıdan gelir; kurtarma cümlesi 0.6 sn'de belirir; raporda sayılar sayarak yükselir.

**Teknik:**
- PiP: `AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer:)`, suflör görünümü `CMSampleBuffer`'a çizilir; `UIBackgroundModes` += `audio`.
- Worker: `/live-plan` (brif → kartlar), `/live-next` (bağlam → 3 öneri, ilki köprü cümlesi). Metin gider, ses gitmez.
- Canlı Etkinlik: yeni widget eklentisi + App Intents düğmeleri; **yeni App ID ve provisioning profili gerekir (kullanıcı oluşturur).**
- İkinci telefon: mevcut `SpeechEngine` (Türkçe `DictationTranscriber`), eşleşme QR ile, iletişim Multipeer.

**Fazlar:** 1 brif + Worker · 2 PiP suflör + düğmeler · 3 Canlı Etkinlik/Island · 4 ikinci telefon modu · 5 rapor + animasyon cilası.

**Durum (2026-09-18, build 113–115):**
- **Karar:** dinleme yok (mikrofon paylaşılamıyor), ikinci telefon modu yok (UX'i kötü bulundu). Suflör sabit hızda akar; hız, punto, sürükleyerek aşağı/yukarı ve kart atlama elle.
- **Yapıldı:** `SuflorFeature` modülü (brif 3 adım, AI kartları `/suflor` Worker'da + şablon, canlı önizleme, sahne: 3-2-1, reklam bekleme halkası, reklam anı süpürmesi, tik çizimi; PiP `AVSampleBufferDisplayLayer` ile, sistem düğmeleri durdur/kart atla; rapor: istatistikler, kanıt satırları, Fotoğraflar'dan kayıt ekleyip cihazda dinleyerek doğrulama + kare, PDF ve PNG paylaşımı). Domain: `SuflorBrief/Cue/Plan/Clock/Proof/Session` + `SuflorTests`. `UIBackgroundModes` += `audio`.
- **Açık:** cihazda PiP testi (mixWithOthers ile açılıyor mu, TikTok canlıyken pencere yaşıyor mu); Canlı Etkinlik/Dynamic Island (widget eklentisi + yeni App ID/profil gerekir); App Review notu (audio modu yalnız PiP için); konumlandırma "reklam teslim aracı", dağıtım PDF altbilgisi + ajanslar.
- **Rakip:** Beast Floating Teleprompter, Teleprompter™, VoicePrompter, Teleprompter: Floating Notes zaten PiP'te yüzüyor; VoicePrompter yüzerken ses takibi iddia ediyor — doğrulanmadı.

---

## 6. Ortak teknik altyapı

Hedeflerin çoğu aynı altı temele dayanıyor. Bunlar bir kez ve sağlam kurulur.

```text
┌───────────────────────────────────────────────────────────────────────┐
│ Özellik katmanı: Studio · Editor · Workflows · Publishing · Assistant │
├───────────────────────────────────────────────────────────────────────┤
│ T1 Tool Registry (ToolDescriptor)  — UI ve AI aynı eylemleri çağırır   │
├──────────────────────┬──────────────────────┬─────────────────────────┤
│ T2 MediaIndex         │ T3 Render Core        │ T4 JobQueue             │
│ analiz, kalıcı, hash  │ Metal, tek evaluator  │ arka plan, devam eden   │
├──────────────────────┴──────────────────────┴─────────────────────────┤
│ T5 Provider katmanı: cihaz (Apple) · worker · BYOK sağlayıcıları        │
├───────────────────────────────────────────────────────────────────────┤
│ T6 Sync & Catalog: CloudKit proje senkronu · uzaktan içerik kataloğu    │
└───────────────────────────────────────────────────────────────────────┘
```

### T1 — Tool Registry

Bugün AI, `EditPlan.Operation` → `AIDirector` yoluyla çalışıyor ve iyi çalışıyor. Ölçeklemek için her işlem bir tanımlayıcıya dönüşür:

```text
ToolDescriptor {
  id, intent (insan dili), arguments (Codable şema),
  preconditions, sideEffects (AITarget listesi),
  risk: none | reversible | destructive,
  undoScope, progress, verifier
}
yaşam döngüsü: proposed → validated → applied → verified  (↘ failed → rollback)
```

- Worker prompt'u ve workflow yazarı araç listesini buradan okur; elle senkron tutulan listeler biter.
- App Intents aynı tanımlayıcılardan üretilir. Kısayollar, Siri ve Spotlight'tan "son videoma altyazı ekle" çalışır.
- **Kural:** UI'nin yapabildiği her güvenli işlemi AI da yapabilir, AI'ın yaptığı her işlem UI'de görünür.

### T2 — MediaIndex

Her kayıt için bir kez hesaplanan ve kaynak hash'iyle önbelleğe alınan analiz. Bunu H1, H2, H3, H4, H8, H9, H15 kullanır.

| Kanal | Kaynak | Çözünürlük |
|---|---|---|
| Kelimeler + güven | SpeechTranscriber | kelime |
| Script hizalaması | ScriptAlignment | kelime |
| Cümle / konuşmacı değişimi | enerji + ağız + SoundAnalysis | cümle |
| Sahne kesmeleri | feature print + histogram | kare |
| Yüzler, bakış, göz kırpma | Vision landmarks, çekimde ARKit | 10 Hz |
| Özne izleri + güven | SubjectTracker | 10–30 Hz |
| Maske (düşük çözünürlük) | Vision segmentation | 10 Hz |
| Ses: RMS, LUFS, sınıf, beat | vDSP, SoundAnalysis | 10 Hz / olay |
| Bulanıklık, pozlama | Core Image istatistikleri | 2 Hz |

- **Depolama:** `index/<recordingID>.json` (+ ikili maske dosyası). Sürümlüdür; algoritma değişince yalnız ilgili kanal yeniden hesaplanır.
- **Çalışma:** T4 kuyruğunda düşük öncelikle; termal duruma göre yavaşlar (`ProcessInfo.thermalState`).

### T3 — Render Core

- **Tek değerlendirici.**
  - `MotionGraph`, `CaptionAnimator`, `Look`, geçiş ve overlay durumu saf fonksiyonlarla kare zamanına göre hesaplanır.
  - Önizleme (`AVPlayer` + custom compositor) ile export (`AVAssetWriter`) aynı compositor sınıfını kullanır.
- **Metal compositor.**
  - `AVVideoCompositing` uygulaması: `CVMetalTextureCache` ile sıfır kopya.
  - Katman sırası sabit: kaynak → görünüm → efekt → geçiş → maske/metin-arkada → overlay → altyazı.
  - Core Image, Metal context üzerinde yalnız hazır filtreler için kullanılır.
- **Akıllı render:** Değişmeyen segmentler önbellekten kopyalanır; yalnız değişenler kodlanır.
- **Mevcut yollarla geçiş:** `FilterCompositor` ve `TransitionComposer` davranışı korunarak yeni compositor'a taşınır; eski yol bir sürüm boyunca yedek kalır. `writeResilient` bu yedeği kullanır.

### T4 — JobQueue

- **İş türleri:** Analiz, render, üretim ve yükleme. Hepsi kalıcı bir kuyruktadır: `jobs.json` + her iş için checkpoint.
- **Sistem entegrasyonu:**
  - `BGContinuedProcessingTask` (iOS 26): kullanıcının başlattığı uzun işler.
  - `BGProcessingTask`: şarjda indeks.
  - `URLSession` background: yükleme.
  - Live Activity: ilerleme göstergesi, ör. "Shorts Fabrikası 23/60".
- Workflow toplu çalıştırmaları (eski plandaki Faz 2) bu kuyruğun üstüne kurulur.

### T5 — Provider katmanı

| Yetenek | Cihazda (varsayılan) | Worker | BYOK |
|---|---|---|---|
| Script, yeniden yazma | Foundation Models | ✓ (uzun/karmaşık) | — |
| AI kurgu planı, highlight, fikir | — | ✓ | — |
| Transkripsiyon | SpeechAnalyzer | — | (ops.) |
| Çeviri | Translation | — | — |
| Video üretimi, Restyle, avatar | — | — | fal / Veo / Sora / Replicate |
| TTS, ses klonu, lipsync, müzik/SFX | AVSpeechSynthesizer (yalnız önizleme) | — | ElevenLabs / fal ses modelleri |
| Bakış düzeltme | Core ML (hedef) | — | (yedek) |

**Kurallar (değişmez):**
- Sağlayıcı anahtarı uygulamaya gömülmez.
- BYOK anahtarları yalnız Keychain'de (`ThisDeviceOnly`).
- Kullanıcının videosu yalnız açık izinle buluta gider.

### T6 — Sync ve Catalog

- **Senkron:** Projeler için `CKSyncEngine` (H13).
- **Katalog:** Şablon, efekt, LUT ve stil paketleri için R2 + imzalı manifest. Uygulama sürümünden bağımsız yayınlanır; her öğede en düşük uygulama sürümü alanı bulunur.

### Gözlemlenebilirlik

- **Hata ve performans:** MetricKit (`MXMetricManager`) ile çökme, takılma ve disk yazma. Export süresi, AI adım başarısı ve iptal oranı yerel olarak toplanır; kullanıcı izniyle anonim gönderilir.
- **Performans ölçümü:** `os_signpost` aralıkları; CI'da performans testleri (XCTest metrics) ile regresyon kapısı.

---

## 7. İleri özellikler: kimsenin yapmadığı şeyler

Bunlar dart tahtasının dışında; rakibi yakaladıktan sonra kategori tanımlayan özellikler.

1. **Script-farkındalıklı yönetmen.**
   - Çekim sırasında teleprompter, cümle bitince "bu cümle temiz / tekrar al" işaretini canlı verir: hizalama, dolgu ve bakış ölçümü birlikte kullanılır.
   - Çekim bitince kurgu zaten %80 hazırdır.
2. **Canlı çekim koçu.** Işık (pozlama histogramı), kadraj (baş boşluğu), ses (clipping, arka plan gürültüsü) ve bakış için tek satırlık, dikkat dağıtmayan uyarılar.
3. **Tek çekim, çok dil.** Script çevrilir, her dilde teleprompter açılır, aynı kurgu şablonu uygulanır ve her dil ayrı video olarak export edilir.
4. **Kendi arşivinden B-roll.**
   - Fotoğraflar kütüphanesinde cihazda anlamsal arama yapılır (Vision feature print; iOS 26'da uygun ise cihazda gömme modeli).
   - Script'teki "kahve" kelimesi için kullanıcının kendi kahve videoları önerilir.
   - Stok veya üretim ikinci seçenektir.
5. **Hook laboratuvarı.** Aynı videonun 3 farklı açılışı (metin, zoom, ilk cümle) otomatik üretilir; yayın sonrası performansla (H12) kazanan öğrenilir.
6. **Kurgu açıklaması.** "Bu videoda ne yaptın?" sorusu, AI adımlarının insan diliyle özetiyle cevaplanır. Rakiplerde yok; bizde `AIDirector` adımları zaten var.
7. **Kısayollar ve otomasyon.** App Intents ile "Her pazartesi 9'da haftalık fikirleri hazırla", "Yeni kaydı Shorts workflow'undan geçir ve YouTube'a zamanla". Workflow + API teslimi bunu kurumsal entegrasyona açar (Zapier/Make/n8n).
8. **Dikte ile kurgu.** Basılı tut ve konuş: "şu kısmı kes, burada yakınlaş". `SpeechAnalyzer` + mevcut `AIComposer` kullanılır; eller serbest kalır.
9. **Kalite garantili export.** Her export'un yanında bir rapor çıkar: LUFS, altyazı okuma hızı, güvenli alan, siyah kare, AI etiketi. Ajanslar için PDF/JSON olarak teslim edilir.
10. **Çift kamera "röportaj modu".** Ön ve arka kamera aynı anda çalışır; konuşana otomatik geçiş yapılır (H15).

---

## 8. Plan

Tahminler tek geliştirici + AI yardımı ve CI'nın derleyici olduğu mevcut düzen içindir. Her faz sonunda TestFlight yayınlanır ve gerçek cihazda kabul listesi kontrol edilir.

### Faz 0 — Temel (2 hafta)

**Hedef:** Sonraki her şeyin dayanağı.

- **T2 MediaIndex iskeleti:** Kelimeler, sahne, ses RMS/LUFS. Kalıcı ve hash'li.
- **T4 JobQueue iskeleti:** Kalıcı kuyruk, `BGContinuedProcessingTask`, Live Activity.
- **Workflow API teslimi `URLSession` background'a taşınır.** Bu, eski plandaki açık adımdı.
- **T1 Tool Registry:** Mevcut `EditPlan` işlemleri tanımlayıcıya sarılır; worker prompt'u listeyi buradan alır.
- **MetricKit + signpost.**

**Kapı:** Uygulama kapatılıp açıldığında yarım kalan analiz ve yükleme devam ediyor.

### Faz 1 — Merkez halka, birinci atış (4 hafta)

**Hedef:** Kullanıcıya görünen en büyük açığı kapatmak.

- **H1:** Altyazı stil DSL'i, `CaptionAnimator`, 20 stil paketi, galeri, yüzden kaçan yerleşim, okuma hızı bulgusu.
- **H3:** Script hizalaması, temizlik paneli (sessizlik, dolgu, tekrar), hayalet aralıklar, doğal kesim.
- **H3:** Cümle bazında yeniden çekim.
- **H9 (parça):** Loudness normalize + export QA.

**Kapı:**
- 60 saniyelik konuşan kafa videosu 3 dokunuşta "yayınlanabilir" hâle geliyor: çek → temizle → stil.
- Kör testte Captions'ın varsayılan çıktısıyla eşit ya da daha iyi puan alıyor (10 kişilik panel).

### Faz 2 — Merkez halka, ikinci atış (4 hafta)

**Hedef:** Long-to-short ve göz teması.

- **H2:** Uzun içe aktarma, sahne ve konuşmacı analizi, worker `/highlights`, açıklanabilir skor, Clips sohbeti, reframe.
- **H3:** En iyi çekim seçici.
- **H4 (önleme):** Lens altı dar teleprompter, canlı bakış ölçümü, göz koçu.
- **H4 (düzeltme prototipi):** Model değerlendirmesi; kalite yetmezse bulut/BYOK yolu.

**Kapı:** H2 kabul ölçütleri sağlanıyor. H4 düzeltmesi yalnızca kör test eşiğini geçerse yayına giriyor; geçmezse "beta" etiketiyle ya da hiç yayınlanmıyor.

### Faz 3 — Render çekirdeği (3 hafta)

**Hedef:** Hız ve kalite tavanını kaldırmak.

- **T3:** Metal compositor, tek değerlendirici, akıllı render, arka plan export.
- **H5:** Kabul benchmark'ları CI'a eklenir.
- **Geçiş:** Mevcut filtre ve geçişler taşınır; eski yol yedek kalır.

**Kapı:** H5 süre hedefi sağlanıyor; önizleme/export piksel farkı eşik altında.

### Faz 4 — Orta halka (6 hafta)

**Hedef:** Pro kullanıcının geçiş maliyetini sıfırlamak.

- **H7:** Motion Graph ile ana klip keyframe, hız eğrisi, ses keyframe'i, proje sürümleri.
- **H6:** Şablon (yuvalı), Look/LUT, Metal efekt ve geçiş aileleri, uzaktan katalog.
- **H8:** Nesne maskesi, metin-arkada, chroma key.
- **H9:** Beat motoru, ducking, müzik/SFX kütüphanesi (lisans kararı gerekir).
- **H14:** Marka kiti.

**Kapı:** Her alt başlığın kabul ölçütü sağlanıyor.

### Faz 5 — Dağıtım ve süreklilik (5 hafta)

- **H12:** YouTube, sonra Instagram, sonra TikTok yayını; zamanlama; takvim; AI başlık/kapak.
- **H13:** CloudKit senkronu, iPad düzeni, Mac ("Designed for iPad" → Catalyst).
- **H10:** Cihazda çeviri, çift dilli altyazı, çok dilli çekim.
- **App Intents** (T1'den üretilir).

**Kapı:** Uygulama kapalıyken zamanlanmış yayın tamamlanıyor; iki cihaz arasında senkron veri kaybı olmadan çalışıyor.

### Faz 6 — Dış halka (sürekli)

- **H10:** Dublaj ve lipsync (BYOK).
- **H11:** Avatar/AI ikiz, Restyle.
- **H12:** Performans geri bildirimi, hook laboratuvarı.
- **H13:** Ekip çalışma alanı.
- **H15:** Çift kamera röportaj modu.
- **§7:** İleri özellik listesi.

### Zaman çizelgesi özeti

```text
Hafta   1-2   3-6        7-10        11-13    14-19          20-24        25+
        F0    F1         F2          F3       F4             F5           F6
        temel altyazı+   long2short  Metal    keyframe/efekt yayın/sync   ikiz/dublaj
              temizlik   göz teması  render   maske/müzik    çeviri       ekip
```

### Açık kararlar (kullanıcıdan cevap bekleyen)

1. **Müzik kütüphanesi.** Lisanslı katalog mu (maliyet + sözleşme), yoksa yalnız BYOK üretim + kullanıcı dosyası mı?
2. **Bakış düzeltme modeli.** Açık kaynak modeli eğitip cihaza gömmek mi, sağlayıcıya (BYOK) mı bırakmak?
3. **Fiyatlandırma.** Edits ve Premiere temel özellikleri ücretsiz veriyor. Önerim: çekim + temel kurgu ücretsiz; stil paketleri, long-to-short, bulut senkron ve yayın otomasyonu abonelikte. BYOK maliyeti kullanıcıda kalır.
4. **Ekip altyapısı.** CloudKit paylaşım mı, kendi backend'imiz (D1 + R2) mi?
5. **Workflow toplu üretimi ve worker üzerinden kredi** (eski plandaki açık karar). Şimdilik BYOK ile devam; kredi modeli Faz 5 sonrası.

---

## 9. Eski planlardan devreden açık işler

Silinen belgelerden, hâlâ yapılmamış ve bu plana bağlanan maddeler:

| Madde | Kaynak plan | Bu raporda |
|---|---|---|
| Vision tracker gerçek cihaz benchmark'ı (düşük ışık, örtülme, benzer nesne, kadrajdan çıkıp dönme) | Tracking | Faz 2 (H2 reframe kapısı) |
| Otomatik occlusion/re-entry ve yanlış özneye atlamama | Tracking | Faz 2 |
| Zoom tarif aralığını Camera Lane'de taşıma/uzatma, özneye bağlama | Zoom | Faz 4 (H7 Motion Graph) |
| Vuruş / ayak basma / beat olay motoru ve doğal sarsıntı | Tracking, Zoom | Faz 4 (H9 beat) |
| AI tool registry'si (ToolDescriptor) | AI tool roadmap | Faz 0 (T1) |
| Tracking/zoom araçlarını AI'a bağlama | AI tool roadmap | Faz 0 (T1) |
| Multicam, proxy, renk/HDR, chroma, ses stem'leri, toplu render | Gap report | H15, T3, H6, H8, H9, T4 |
| Timeline track kilidi / solo / mute | Timeline audit | Faz 4 |
| Workflow şema v3, StepRegistry, GraphExecutor, RunJournal | Workflow platform | Faz 0 (T4 üzerine) |
| Toplu Pano, inceleme kuyruğu, qualityGate adımı | Workflow platform | Faz 2–3 |
| Üretim uçları: TTS, müzik, matchAudioToVideo | Workflow platform | H9, H10 (BYOK) |
| YouTube/Instagram yayını, takvim, kota sayacı | Workflow platform | Faz 5 (H12) |
| Workflow teslimi arka planda (background URLSession) | Workflow platform (17 Eyl.) | Faz 0 |
| Aylık dump şablonu: yan özellik, düşük öncelik | Workflow platform (16 Eyl.) | Faz 6 |
| Build 80 cihaz doğrulaması: export, geçişler, API teslimi, timeline düzeni | 17 Eylül turu | Faz 0'dan önce |
| Zoom sorunu: belirti bilgisi bekleniyor | 17 Eylül turu | Kullanıcıdan bilgi bekleniyor |

**Korunan kararlar:**
- BYOK (16 Eylül).
- Editörde üretim (16 Eylül).
- Her workflow tek ve kilitli Export ile biter (17 Eylül).
- Workflow'a özel API teslimi, anahtar Keychain'de (17 Eylül).
- AI yeni bir preset değil, görünen ve geri alınabilir adımlarla çalışır.

---

## 10. Ölçüm, risk ve kurallar

### Başarı ölçütleri

| Ölçüt | Bugün | Faz 2 sonu hedefi | Faz 5 sonu hedefi |
|---|---|---|---|
| Çekimden yayınlanabilir videoya süre (60 sn) | ölçülmedi | < 3 dk | < 90 sn |
| Export başarı oranı | ölçülmedi | > %99 | > %99,5 |
| AI adımı geri alınma oranı | ölçülmedi | < %20 | < %12 |
| 7. gün tutma | ölçülmedi | ölç | +%30 |
| Kör test, Captions varsayılanına karşı | — | eşit | daha iyi |

### Riskler

| Risk | Etki | Önlem |
|---|---|---|
| Bakış düzeltme kalitesi "tuhaf" görünür | Güven kaybı | Kör test kapısı, varsayılan kısmi yoğunluk, kapatılabilir |
| Metal compositor geçişinde regresyon | Export bozulur | Eski yol yedek, piksel karşılaştırma testleri, kademeli açma |
| Platform API incelemeleri gecikir | Yayın fazı kayar | Önce paylaşım sayfası + workflow API teslimi; incelemeleri Faz 3'te başlat |
| Müzik lisansı | Telif ihlali | Lisans netleşmeden yalnız kullanıcı dosyası + üretim |
| Ses klonu / avatar kötüye kullanımı | Hukuki | Yalnız kendi sesi/yüzü, rıza kaydı, AI meta etiketi |
| Termal/pil (analiz + Metal) | Kötü deneyim | `thermalState` ile kısma, şarjda indeks, iptal edilebilir işler |
| Tek geliştirici hızı | Plan kayar | Merkez halka önce; dış halka BYOK ile ince entegrasyon |
| Cihazda test yok (Windows + CI) | Gerçek hata geç görülür | Her faz sonunda TestFlight kabul listesi; performans testleri CI'da |

### Değişmez kurallar

- **Mimari:** Feature modülleri birbirini import etmez. Domain saftır ve test edilir. Önizleme ile export aynı değerlendiriciyi kullanır.
- **Swift 6 eşzamanlılığı:** Framework'ün kendi kuyruğunda çağırdığı closure'lar `nonisolated` fonksiyonda ve `@Sendable` yazılır (PhotoKit export çökmesi dersi).
- **AI davranışı:** Sessizce değişiklik yapmaz; her adım görünür, aralığı bellidir ve geri alınabilir.
- **Anahtarlar:** Anahtar ve token yalnız cihaz Keychain'inde tutulur. Sağlayıcı anahtarı uygulamada ve workflow dosyasında yer almaz.
- **Erişilebilirlik:** 44 pt dokunma hedefi, VoiceOver, Dynamic Type, Reduce Motion.
- **Metin:** Her metin EN + TR String Catalog'unda.

---

## 11. Kaynaklar

Rakip bilgileri üçüncü taraf beyanıdır; bağımsız ölçüm değildir.

**Captions / Mirage**
- [Captions iPhone sürüm notları](https://captions.ai/help/updates/ios)
- [TechCrunch: Mirage 75M$ (Mart 2026)](https://techcrunch.com/2026/03/24/mirage-raises-75m-to-continue-building-models-for-its-ai-video-editing-app-captions/)
- [Captions genel bakış](https://captions.ai/overview)
- [Captions çeviri](https://captions.ai/features/translate-videos-with-ai)
- [Lipdub (TechCrunch)](https://techcrunch.com/2023/10/11/video-editing-startup-captions-launches-a-dubbing-app-with-support-for-28-languages)

**CapCut**
- [CapCut yeni sürümler](https://www.capcut.com/resource/new-release)

**Instagram Edits**
- [Edits tanıtımı](https://creators.instagram.com/blog/edits-video-creation-app)
- [Social Media Today: Edits güncellemesi](https://www.socialmediatoday.com/news/edits-gets-ig-links-weekly-ideas-and-new-video-effects-features/809644/)
- [Music Ally: Edits Ocak 2026](https://musically.com/2026/01/16/instagram-adds-new-edits-app-updates/)
- [Avocado Social: Reels/Edits 2026](https://avocadosocial.com/instagram-reels-editing-updates-2026-new-features-you-need-to-know/)
- [Edits App Store](https://apps.apple.com/us/app/edits-video-editor/id6738967378)

**Adobe Premiere (iPhone)**
- [Premiere iPhone yenilikler](https://helpx.adobe.com/premiere/mobile/whats-new/whats-new.html)
- [Premiere iPhone sürüm notları](https://helpx.adobe.com/premiere/mobile/whats-new/release-notes.html)
- [MacRumors: Premiere iPhone](https://www.macrumors.com/2025/09/30/adobe-launches-premiere-for-iphone/)

**BIGVU**
- [BIGVU 2026](https://bigvu.tv/blog/bigvu-2026-all-in-one-video-platform)
- [BIGVU App Store](https://apps.apple.com/us/app/bigvu-teleprompter-captions-ai/id1124958568)

**Opus Clip, Submagic ve teknik hat**
- [Opus Clip vs Submagic (Submagic)](https://www.submagic.co/blog/opus-clip-vs-submagic)
- [Opus Clip vs Submagic (ngram)](https://www.ngram.com/blog/opus-clip-vs-submagic)
- [AI kurgu araçlarının teknik hattı (Fora Soft)](https://www.forasoft.com/learn/ai-for-video-engineering/articles-ai/opus-clip-descript-submagic-captions-ai-video-editor-tools-2026)

**Descript**
- [Descript Underlord yardım](https://help.descript.com/hc/en-us/articles/36803785502221-Underlord-beta-Your-AI-co-editor-in-Descript)
- [Descript Season 6](https://www.descript.com/blog/article/descript-season-6-meet-underlord)

**VN, LumaFusion, InShot**
- [Unstar: CapCut vs InShot vs VN vs LumaFusion](https://unstar.app/blog/capcut-inshot-vn-splice-lumafusion-video-editing-apps-ranked-2026)
- [LumaFusion Multicam Studio](https://alternativeto.net/news/2023/4/lumafusion-introduces-multicam-studio-a-multicam-video-editing-feature)

**Eski workflow planından taşınan kaynaklar**
- [YouTube API kota (Phyllo)](https://www.getphyllo.com/post/youtube-api-limits-how-to-calculate-api-usage-cost-and-fix-exceeded-api-quota)
- [Meta içerik yayınlama](https://developers.facebook.com/docs/instagram-platform/content-publishing/)
- [Seedance 2.5 (Replicate)](https://replicate.com/bytedance/seedance-2.5)
