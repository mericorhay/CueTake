// The privacy policy, served at /privacy for the App Store listing and the subscription screens.
// Written from what the app actually does: what stays on the phone, what is sent and to whom.
const TR = `
<h1>CueTake Gizlilik Politikası</h1>
<p class="date">Son güncelleme: 24 Eylül 2026</p>

<h2>Kısaca</h2>
<p>Videoların, kayıtların ve projelerin telefonunda kalır. Sunucumuza yalnızca senin açtığın yapay zekâ özellikleri için gereken metin ve ses gider; uygulamayı geliştirmek için anonim kullanım istatistikleri toplarız (kapatılabilir). Reklam için takip yapmayız, verini satmayız.</p>

<h2>Telefonunda kalanlar</h2>
<ul>
<li>Çektiğin ve içe aktardığın videolar, projeler, senaryolar ve suflör raporları.</li>
<li>Prompter'ın sesini takip etmesi ve otomatik altyazı: iPhone'un kendi konuşma tanıma motoruyla, cihazda yapılır.</li>
<li>Kullanım sayaçların (aylık yapay zekâ hakların) cihazının anahtar zincirinde tutulur.</li>
</ul>

<h2>Sunucuya gidenler (yalnızca ilgili özelliği kullandığında)</h2>
<ul>
<li><b>AI kurgu, AI asistan, senaryo yazma, altyazı çevirisi, paylaşım kiti:</b> videonun konuşma metni, altyazılar, düzenleme bilgisi ve kareler üzerinden telefonda çıkarılmış kısa görüntü notları (ör. "mutfak, 1 yüz"). AI kurguda ayrıca, başlıkları ve efektleri doğru yere koyabilmesi için kurgulanmış videodan birkaç küçük, düşük çözünürlüklü kare gönderilir. Video dosyası ve sesi gönderilmez. AI'a hatırlamasını söylediğin tercihler (AI hafızası) telefonda saklanır ve AI kurgu isteğiyle birlikte gönderilir; Ayarlar'dan silinebilir.</li>
<li><b>Bulut altyazı (isteğe bağlı):</b> konuşmanın ses kaydı, daha doğru altyazı için yazıya dökülür.</li>
<li><b>Stok B-roll:</b> konuşma metninden seçilen cümleler ve kısa İngilizce arama kelimeleri.</li>
</ul>
<p>Bu istekler sunucumuz (Cloudflare) üzerinden yapay zekâ ve stok görüntü sağlayıcılarına iletilir: OpenAI, Groq ve/veya Anthropic (metin, resim ve konuşma tanıma), Pexels (stok video araması). İstekler yanıt üretmek için kullanılır; biz içeriklerini saklamayız. Sağlayıcıların kendi politikaları geçerlidir.</p>

<h2>Kullanım istatistikleri</h2>
<p>Uygulamayı geliştirmek için PostHog (ABD sunucuları) üzerinden anonim kullanım olayları toplarız: hangi özelliğin kullanıldığı, aylık limitlere nerede takılındığı, dışa aktarmanın çözünürlüğü ve kare hızı, kaydın süresi, CueTake+ satın alma sonucu, uygulama sürümü, dili ve cihaz modeli. Bunlar telefonda üretilen rastgele bir kimlikle gönderilir; hesabına, Apple kimliğine ya da adına bağlanmaz. Videoların, kayıtların, senaryoların, altyazıların, proje adların ve ekran görüntüleri asla gönderilmez; ekran kaydı (session replay) kullanmayız. Reklam ya da takip için kullanılmaz, kimseyle paylaşılmaz. Ayarlar'daki "Anonim kullanım verisi paylaş" anahtarıyla istediğin an kapatabilirsin.</p>

<h2>iCloud yedekleme (CueTake+)</h2>
<p>Yedeklemeyi açarsan projelerin ve videoların kendi iCloud hesabındaki özel CloudKit alanına gönderilir. Bu veriyi yalnızca sen görebilirsin; bizim sunucumuzdan geçmez ve biz erişemeyiz.</p>

<h2>Uzak ayarlar</h2>
<p>Uygulama açılışta sunucumuzdan aylık limitleri ve özellik anahtarlarını okur. Bu istekte senin hakkında bir bilgi gönderilmez.</p>

<h2>Hesap</h2>
<p>Apple ile Giriş yaparsan Apple'ın verdiği kimlikten türetilen bir kimlik ve istersen adın saklanır. E-posta adresini almayız. Hesabını Ayarlar'dan istediğin an silebilirsin; silince hesabın ve oturumların sunucudan kalıcı olarak silinir.</p>

<h2>Abonelik</h2>
<p>CueTake+ aboneliği Apple üzerinden alınır ve yönetilir. Ödeme bilgilerini biz görmeyiz.</p>

<h2>Çocuklar</h2>
<p>CueTake 13 yaşından küçükler için tasarlanmamıştır.</p>

<h2>İletişim</h2>
<p>Sorular ve silme talepleri için App Store sayfasındaki destek bağlantısını kullanabilirsin.</p>
`;

const EN = `
<h1>CueTake Privacy Policy</h1>
<p class="date">Last updated: 24 September 2026</p>

<h2>In short</h2>
<p>Your videos, recordings and projects stay on your phone. Only the text and sound needed for the AI features you choose to use reach our server. We collect anonymous usage statistics to improve the app (you can turn this off). We do not track you for advertising and we do not sell your data.</p>

<h2>What stays on your phone</h2>
<ul>
<li>The videos you record and import, projects, scripts and suflör reports.</li>
<li>The prompter following your voice and automatic captions run on the iPhone's own speech recognition, on the device.</li>
<li>Your usage counts (monthly AI allowance) are kept in the device keychain.</li>
</ul>

<h2>What is sent (only when you use that feature)</h2>
<ul>
<li><b>AI edit, AI assistant, script writing, caption translation, post kit:</b> the video's transcript, captions, editing details and short scene notes read from frames on the phone (e.g. "kitchen, 1 face"). For AI edit, a few small, low-resolution pictures of the edited video are also sent, so the AI can put titles and effects in the right place. The video file and its sound are not sent. Preferences you ask the AI to remember (AI memory) are kept on the phone and sent with AI edit requests; they can be deleted in Settings.</li>
<li><b>Cloud captions (optional):</b> the speech audio, transcribed for more accurate captions.</li>
<li><b>Stock B-roll:</b> sentences chosen from the transcript and short English search terms.</li>
</ul>
<p>These requests pass through our server (Cloudflare) to AI and stock footage providers: OpenAI, Groq and/or Anthropic (text, picture and speech recognition), Pexels (stock video search). They are used to produce the answer; we do not store their content. The providers' own policies apply.</p>

<h2>Usage statistics</h2>
<p>To improve the app we collect anonymous usage events through PostHog (US servers): which features are used, where monthly limits are reached, an export's resolution and frame rate, a recording's length, the outcome of a CueTake+ purchase, the app version, language and device model. They are sent with a random identifier made on the phone and are never linked to your account, your Apple ID or your name. Your videos, recordings, scripts, captions, project names and screen contents are never sent, and we do not use session replay. The data is not used for advertising or tracking and is not shared with anyone. You can turn it off at any time with "Share anonymous usage" in Settings.</p>

<h2>iCloud backup (CueTake+)</h2>
<p>If you turn backup on, your projects and videos go to a private CloudKit area in your own iCloud account. Only you can see this data; it does not pass through our server and we cannot access it.</p>

<h2>Remote settings</h2>
<p>At launch the app reads monthly limits and feature switches from our server. Nothing about you is sent with that request.</p>

<h2>Account</h2>
<p>If you sign in with Apple, an identifier derived from Apple's and, if you choose, your name are stored. We do not receive your email address. You can delete your account at any time in Settings; your account and sessions are then permanently removed from the server.</p>

<h2>Subscription</h2>
<p>CueTake+ is bought and managed through Apple. We never see your payment details.</p>

<h2>Children</h2>
<p>CueTake is not directed to children under 13.</p>

<h2>Contact</h2>
<p>For questions and deletion requests, use the support link on the App Store page.</p>
`;

export function privacyPage(url) {
  const lang = (url.searchParams.get("lang") || "").toLowerCase();
  const body = lang === "en" ? EN : lang === "tr" ? TR : `${TR}<hr>${EN}`;
  const html = `<!doctype html><html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>CueTake Gizlilik · Privacy</title>
<style>
:root{--bg:#0B0B0D;--ink:#F5F5F7;--dim:rgba(245,245,247,.62);--lime:#E8FF4F;--line:rgba(245,245,247,.1)}
@media (prefers-color-scheme: light){:root{--bg:#FAFAF7;--ink:#141416;--dim:rgba(20,20,22,.6);--lime:#5a6b00;--line:rgba(20,20,22,.12)}}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.6 -apple-system,system-ui,sans-serif}
main{max-width:680px;margin:0 auto;padding:40px 20px 80px}
h1{font-size:28px;line-height:1.2;margin:0 0 4px}
h2{font-size:17px;margin:28px 0 6px;color:var(--lime)}
.date{color:var(--dim);font-size:13px;margin:0 0 20px}
ul{padding-left:20px}li{margin:6px 0}
hr{border:0;border-top:1px solid var(--line);margin:48px 0}
</style></head><body><main>${body}</main></body></html>`;
  return new Response(html, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=3600" } });
}
