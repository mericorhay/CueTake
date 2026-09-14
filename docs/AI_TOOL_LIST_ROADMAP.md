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

## Sıralama

- Önce registry ve ortak EditAction sözleşmesi.
- Sonra finding → condition → action bağlantısı.
- Ardından otomatik tool seçimi ve güvenli execution state.
- En son branching, loops, tool önerileri ve workflow marketplace.

## Tasarım kuralı

AI hiçbir aracı sessizce çalıştırmamalı. Kullanıcı, seçilen aracın amacını, etkileyeceği zaman aralığını, güvenini ve geri alınabilir olduğunu görmelidir.
