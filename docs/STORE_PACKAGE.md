# Store package

> Draft listing copy, reviewer notes, exact in-app wording, and the console
> checklists. English is the canonical source; the Turkish text is a translation
> of it, not a separate claim.
>
> **Nothing here guarantees approval.** Character limits were current in July
> 2026 and should be re-checked in the consoles before submission.
>
> **This copy describes the app as built and needs a pass before submission.**
> Two things changed after it was written. The product is a **reading library**
> in which an Entry belongs to the library whether or not its content has been
> downloaded ([PRODUCT.md](./PRODUCT.md)) — copy that equates "saved" with
> "downloaded" now understates it. And an **optional** account with cross-device
> sync is planned ([DECISIONS.md](./DECISIONS.md) V2-D3, V2-D8), so the
> unqualified claims *"No account."* and *"Scrollary has no server and receives
> nothing from you"* in §2, §3 and §7 must be re-scoped to anonymous use rather
> than deleted. §8.1 App Privacy, §8.2 Data safety and §7's reviewer notes all
> need redoing, and a demo account will be required. Tasks 7.5–7.8 in
> [V2_ROADMAP.md](./V2_ROADMAP.md); the full obligation list is
> [V2_SYNC.md](./V2_SYNC.md) §14. **Do not edit the copy below to describe
> unbuilt behaviour** — it is rewritten when the behaviour exists.

---

## 1. Brand

The name is **Scrollary**. It replaced the development working name "Web Reader",
which was descriptive, almost certainly already in use, and not a mark worth
defending.

### 1.1 Where each form of the name is used

| Surface | Value | Where it is set |
|---|---|---|
| Launcher / installed app, iOS | `Scrollary` | `CFBundleDisplayName` in `ios/Runner/Info.plist` |
| Launcher / installed app, Android | `Scrollary` | `android:label` in `android/app/src/main/AndroidManifest.xml` |
| Store listing, both stores | `Scrollary: Offline Web Reader` | entered in the consoles — 29 characters, inside both 30-character limits |
| In-app wordmark | `Scrollary` | `lib/features/splash_screen.dart` |
| Task-switcher / window title | `Scrollary` | `MaterialApp.title` in `lib/app.dart` |

The long store name is a listing title only. It is deliberately **not** the
launcher label: the home screen truncates, and "Offline Web Reader" is a
description of the product rather than part of the mark.

### 1.2 Checks still outstanding (not done in this repository)

- [ ] App Store Connect name availability, all target territories
- [ ] Google Play listing-title availability
- [ ] Trademark search: USPTO, EUIPO, and Türkiye (TÜRKPATENT), classes 9 and 42
- [ ] Domain availability for the support and privacy URLs
- [ ] Plain web search for an existing app or service with the name
- [ ] No confusing similarity to an Apple product or interface (Apple 5.2.5)

### 1.3 Bundle identifier

`com.mcagricaliskan.scrollary` on both platforms — the iOS
`PRODUCT_BUNDLE_IDENTIFIER` and the Android `applicationId` and `namespace`. The
iOS unit-test target is `com.mcagricaliskan.scrollary.RunnerTests`.

It was changed from `com.mcagricaliskan.webreader` before any signing,
provisioning or upload existed. Changing it again after the first upload is not
possible on either store: the identifier is the app's identity, and a new one is
a new listing. Both platforms treat a build with a new identifier as a different
installed application, so a device carrying a pre-rename development build keeps
that build's library in its own container; the two do not merge and neither is
migrated.

---

## 2. Apple App Store

**App name** (≤ 30 chars): `Scrollary: Offline Web Reader` *(29 characters.)*

**Subtitle** (≤ 30 chars):

```
Save web pages. Read offline.
```
*(29 characters.)*

**Promotional text** (≤ 170 chars):

```
Save an article now, read it later without a connection. Your library lives on
your device — no account, and nothing is sent to us.
```

**Keywords** (≤ 100 chars, comma-separated, no spaces):

```
read later,offline reading,save article,reading list,web pages,library,reader,bookmarks
```

**Description:**

```
Scrollary is a personal reading tool. Save web pages you are allowed to keep,
organise them in your own library, and read them offline — on a plane, on the
underground, or anywhere the signal runs out.

BUILT FOR READING, NOT FOR HOARDING

The ordinary action saves the page in front of you. Nothing else. When a page
turns out to be part of something longer — a multi-page document, a dated series
of posts, a set of related pages — Scrollary tells you what it found and saves
more only if you ask. Saving more means typing how many, so a run always stops
where you said it would. There is no "save everything" button.

YOUR LIBRARY

• Collections group related pages; single pages stay single pages
• Continue reading picks up exactly where you stopped, to the paragraph
• Reading progress survives restarts, re-saves and freeing up space
• Search your library by title or source
• Archive what you have finished without losing a thing
• Storage screen shows what is using space, per collection, with one tap to
  reclaim it

AN OFFLINE READER THAT RESPECTS THE PAGE

Text is stored as text. Images are stored exactly as the site served them — no
re-encoding, no quality profiles. Page dimensions are read from the stored files,
so a saved page opens at the right proportions and at the position you left.

HONEST ABOUT WHAT IT DOES

• Every save is something you started. There is no background saving.
• Multi-page saves are bounded, visible in a queue, and cancellable.
• If a site asks for a sign-in, shows a paywall, or presents a verification
  check, saving stops and says so. Scrollary does not work around paywalls,
  logins, access controls, DRM or verification checks.
• You choose what each save keeps: the page images, the readable text, or the
  text with the pictures that sit inside it. Scrollary suggests one and shows
  you the alternatives.
• Audio and video are not saved. A saved page links back to the original.
• Saving is not offered on major commercial content services — streaming video,
  music, audiobooks, ebook and comics stores, and subscription reading services.
  You can browse them in Scrollary as you would in any browser; the Save action
  simply is not there.
• Every saved page keeps its source address, and "Open original page" is one tap
  from the reader.

PRIVACY

No account. No analytics. No advertising. Your library, your reading position and
your browsing history stay in the app's private storage on your device, and you
can delete any of them at any time. Scrollary has no server and receives nothing
from you. The browser does contact the sites you choose to visit, as any browser
does.

YOU ARE RESPONSIBLE FOR WHAT YOU SAVE

Scrollary is a tool, not a licence. Save only content you created, own, have
permission to use, or are otherwise allowed to keep. Copyright rules, website
terms and applicable law are yours to follow.
```

---

## 3. Google Play

**Title** (≤ 30 chars): `Scrollary: Offline Web Reader` *(29 characters.)*

**Short description** (≤ 80 chars):

```
Save articles and web pages to your personal library and read them offline.
```
*(74 characters.)*

**Full description** (≤ 4000 chars): as §2, with the Apple-specific framing
removed.

---

## 4. Türkçe (Google Play / App Store)

**Uygulama adı:** `Scrollary: Offline Web Reader`

**Alt başlık / Kısa açıklama** (≤ 80 karakter):

```
Web sayfalarını kişisel kitaplığınıza kaydedin ve çevrimdışı okuyun.
```

**Tam açıklama:**

```
Scrollary kişisel bir okuma aracıdır. Saklamaya hakkınız olan web sayfalarını
kaydedin, kendi kitaplığınızda düzenleyin ve çevrimdışı okuyun — uçakta, metroda
ya da bağlantının kesildiği her yerde.

OKUMAK İÇİN TASARLANDI

Olağan işlem, önünüzdeki sayfayı kaydeder. Başka bir şey yapmaz. Bir sayfanın
daha uzun bir bütünün parçası olduğu anlaşıldığında — çok sayfalı bir belge,
tarihli bir gönderi dizisi, birbiriyle ilişkili sayfalar — Scrollary ne bulduğunu
söyler ve yalnızca siz isterseniz devam eder. Devam etmek, kaç öğe kaydedileceğini
yazmanız demektir; böylece işlem her zaman sizin belirlediğiniz yerde durur.
"Hepsini kaydet" diye bir düğme yoktur.

KİTAPLIĞINIZ

• Koleksiyonlar ilişkili sayfaları gruplar; tek sayfalar tek sayfa kalır
• Kaldığınız yerden, paragrafına kadar devam edin
• Okuma durumu yeniden başlatmalardan, yeniden kaydetmelerden ve yer açmaktan
  etkilenmez
• Kitaplığınızda başlığa veya kaynağa göre arama yapın
• Bitirdiklerinizi hiçbir şey kaybetmeden arşivleyin
• Depolama ekranı neyin yer kapladığını koleksiyon bazında gösterir

SAYFAYA SAYGILI BİR ÇEVRİMDIŞI OKUYUCU

Metin metin olarak saklanır. Görseller sitenin sunduğu biçimde, yeniden
kodlanmadan saklanır. Sayfa boyutları kaydedilen dosyalardan okunur; böylece
kaydedilmiş bir sayfa doğru oranlarla ve bıraktığınız konumda açılır.

NE YAPTIĞI KONUSUNDA DÜRÜST

• Her kayıt sizin başlattığınız bir işlemdir. Arka planda kayıt yapılmaz.
• Çok sayfalı kayıtlar sınırlıdır, kuyrukta görünür ve iptal edilebilir.
• Bir site oturum açma isterse, ödeme duvarı ya da doğrulama kontrolü gösterirse
  kayıt durur ve nedenini söyler. Scrollary ödeme duvarlarını, oturum açmayı,
  erişim denetimlerini, DRM'i veya doğrulama kontrollerini aşmaya çalışmaz.
• Her kaydın neyi tutacağına siz karar verirsiniz: sayfanın görselleri, okunabilir
  metin ya da metin ile içindeki görseller. Scrollary birini önerir, diğerlerini
  de gösterir.
• Ses ve video kaydedilmez. Kaydedilen sayfa özgün sayfaya bağlantı verir.
• Büyük ticari içerik hizmetlerinde kaydetme sunulmaz — video ve müzik yayını,
  sesli kitap, e-kitap ve çizgi roman mağazaları, abonelikli okuma servisleri.
  Bu siteleri Scrollary içinde her tarayıcıdaki gibi gezebilirsiniz; yalnızca
  Kaydet eylemi görünmez.
• Her kaydedilen sayfa kaynak adresini korur; "Özgün sayfayı aç" okuyucudan tek
  dokunuş uzaktadır.

GİZLİLİK

Hesap yok. Analitik yok. Reklam yok. Kitaplığınız, okuma konumunuz ve tarama
geçmişiniz cihazınızdaki uygulamaya özel depolamada kalır ve dilediğiniz an
silebilirsiniz. Scrollary'nin sunucusu yoktur ve sizden hiçbir veri almaz. Tarayıcı,
her tarayıcı gibi, yalnızca sizin ziyaret etmeyi seçtiğiniz sitelere bağlanır.

KAYDETTİKLERİNİZDEN SİZ SORUMLUSUNUZ

Scrollary bir araçtır, bir izin değil. Yalnızca kendi oluşturduğunuz, size ait
olan, kullanma izniniz bulunan veya saklamanıza başka bir şekilde izin verilen
içerikleri kaydedin. Telif hakkı kurallarına, web sitesi koşullarına ve geçerli
yasalara uymak sizin sorumluluğunuzdadır.
```

---

## 5. Screenshot captions

Each caption describes a screen the reviewer can reach. No third-party content
appears in any of them — every screenshot uses the demo content in
`docs/DEMO_CONTENT.md`.

| # | Screen | EN caption | TR caption |
|---|---|---|---|
| 1 | Library | Your reading library, on your device | Okuma kitaplığınız, cihazınızda |
| 2 | Save scope sheet | The default saves one page. More is your choice. | Varsayılan tek sayfa kaydeder. Fazlası sizin kararınız. |
| 3 | Reader | Read offline, exactly where you left off | Çevrimdışı okuyun, tam bıraktığınız yerden |
| 4 | Collection detail | Related pages, in order, with progress | İlişkili sayfalar, sırayla, ilerlemeyle |
| 5 | Queue / Activity | Every save is visible and cancellable | Her kayıt görünür ve iptal edilebilir |
| 6 | Storage | Know what is using space. Reclaim it in a tap. | Neyin yer kapladığını bilin. Tek dokunuşla geri kazanın. |

**Two captions were removed rather than kept, because their screens do not
exist.** A screenshot set is a claim about the app, and one that shows a screen
a reviewer cannot reach is worse than one screenshot fewer:

| Removed | Screen | Why |
|---|---|---|
| *See what was found before anything is saved* | Review related items | The save-scope review step is **deferred** — ARCHITECTURE.md §5, §10. Restore this caption when §6.4 is built |
| *Save only what you are allowed to keep* | Content rights | The content-rights disclosure is **deferred** — STORE_POLICY_MAP.md §8. Restore this caption when §6.1 is built |

**Feature graphic copy (Play, 1024×500):** `Save web pages. Read offline.` over
the app mark on the palette's quiet surface. No screenshots-in-graphic, no
third-party logos, no device frames implying an endorsement.

---

## 6. Exact in-app wording

The single source for these strings. The app must not paraphrase them.

**Not every section here is on screen yet.** Each one below says which it is.
A section marked *specified, not built* is wording held for a surface that does
not exist; it is not a description of the app, and nothing in the listing, the
reviewer notes or a screenshot may rely on it. The built/deferred split is
ARCHITECTURE.md §10.

| § | Surface | State |
|---|---|---|
| 6.1 | First-use content-rights disclosure | **Specified, not built** |
| 6.2 | Contextual multi-entry notice | **Specified, not built** |
| 6.3 | What to save (capture modes) | **Built** — verbatim, except where noted |
| 6.4 | Save-scope review | **Specified, not built** |
| 6.5 | Restricted-access stopping | **Built** — verbatim |
| 6.5.1 | Sites Scrollary does not save from | **Built** — verbatim |
| 6.6 | Video pages | **Built** — verbatim |
| 6.7 | Empty and error states | **Partly built** — see the note there |

### 6.1 First-use content-rights disclosure

**Specified, not built.** Shown once, immediately before the first save of an
external page.

> **Before you save**
>
> Scrollary is a personal reading tool. Save only content you created, own, have
> permission to use, or are otherwise legally allowed to keep. You are
> responsible for following copyright rules, website terms, and applicable law.
>
> The app does not bypass paywalls, logins, access controls, DRM, or site
> restrictions. It cannot check whether you have permission — that judgement is
> yours.

Actions: **Review terms** · **I understand**

Notes: no pre-ticked box, no countdown, no "Agree" styled as the only route out.
Dismissing without acknowledging cancels the save. Re-readable at
**Settings → Content rights**. Acknowledgement is stored locally with a version
(`disclosure.contentRights.version`); a material change asks once more.

### 6.2 Contextual multi-entry notice

**Specified, not built.** Intended to be shown once per domain, before the first
save of more than one page from it.

> **Saving several pages from example.com**
>
> Only save content you have permission to keep. This site's terms may limit
> automated requests or offline copies.
>
> This will save up to **12 items**, and will stop there.

Actions: **Cancel** · **Save**

Two things in the original draft were removed rather than carried forward,
because they described a product that no longer exists: *"following next-page
links, and will stop when there is no next page"* (there is no open-ended
scope — a run stops at the number the user typed, ARCHITECTURE.md §5) and a
**Review items** action (§6.4 is not built). If this notice is ever built, its
stop sentence must state the user's own number.

### 6.3 What to save

**Built.** Shown in the save sheet, above the save control. The heading is
**What to save**, with one line of what was detected beneath it. Verbatim from
`captureDetectionSummary` in `lib/features/capture_mode_section.dart`, and
pinned sentence-by-sentence by `test/capture_mode_section_test.dart`:

| Detection | Line |
|---|---|
| Confident | `This looks like an article.` — the noun varies: *a page of full-size images · an article · a dated post · part of a longer text · a long document · one page of a document · a video page* |
| Low confidence | `This might be an article — the page did not say clearly.` |
| Analysed, but the kind is unclear | `This page did not say clearly what it is. Pick what fits.` |
| Not analysed | `This page could not be analysed, so every option is offered. Pick what fits.` |
| Nothing possible | `Nothing on this page can be saved offline.` |

The low-confidence and unclear cases are deliberately two lines rather than one:
forcing "not something we could classify" through the *"this looks like…"*
template produced a sentence that read as a guess about a guess.

Modes, all three always visible, and **every one of them is one line** — its
glyph and its label, nothing else. A sentence under a label the icon already
distinguishes made the answer harder to find on a sheet that asks three other
questions above this block. An **unavailable** mode is disabled rather than
removed, because a missing option reads as a bug while a greyed one reads as an
answer; its reason is no longer printed under it, and is carried instead by the
row's tooltip and by the name a screen reader speaks:

| Mode | Reason when unavailable (spoken, and on a long press) |
|---|---|
| **Images only** | This page does not have enough full-size images to save as an image sequence. |
| **Text only** | No readable text was found on this page. |
| **Text and images** | No images were found inside the readable text. |

Where the *description* of a mode is still printed: the Collection's own
capture-mode menu (`lib/library_ui/collection_actions.dart`), which is a
standing choice about a work rather than a control on the way past.

Once a Collection has a standing answer the whole block collapses to one line —
`Capture · Images only ⌄` — and the heading **What to save** is the control that
closes it again. It is a dropdown: whatever opens it closes it.

Optional, when the page belongs to a collection:
**Use "<mode>" for this collection from now on** — **not built.** The V2
schema carries no per-Collection capture-mode preference, so there is
nothing for this toggle to write. The rest of §6.3 is built and verbatim;
this line alone is held for a column that does not exist yet.

### 6.4 Save-scope review

**Specified, not built.** This is the deferred review step (ARCHITECTURE.md §5,
§10). The domain layer already computes everything it needs — `detectSequence`
returns the kind, direction, known total and confidence, and `SaveLimits` the
ceiling — but there is no screen. **Nothing may cite this section as current
behaviour**, and the reviewer notes in §7 deliberately do not.

**What the save sheet shows today instead**, under the heading *How many
entries*, and this is what a screenshot or a reviewer note may describe:

| Line | Wording |
|---|---|
| Scope, preselected | **Current entry** — `Only the entry open in the browser` |
| Scope | **Number of entries** — `Type how many to save from here — up to 500` |
| After a number is typed | `New saves only — already saved entries that get skipped do not use up this number. The save stops here, or sooner if the collection ends.` and `Save 3 entries starting from "…".` |
| Estimated size | `Estimated size: <size> — <qualifier>.`, or `kSizeUnknownMessage` when nothing can be estimated |
| Free space | `Available: <n> GB. Space is re-checked before every entry.`, or `Free space could not be checked — it will be checked again before each entry.` |
| Where it goes | `Start Save opens and uses the current Browser now.` / `Add to Queue saves it for later.` |

It does **not** state a shape, a direction, a stop condition or a known total,
and it has no per-item list. Those are the four things §6.4 would add.

Header: **Review what will be saved**

| Line | Example |
|---|---|
| What was detected | `A next-page link was found.` / `This appears to be a dated list of posts.` / `This page has 12 numbered pages.` / `We found 8 related items.` / `No related pages found.` |
| Source | `example.com` |
| Count | `12 items` · or `Number of items is not known in advance` |
| Shape | `Numbered, 12 pages` · `Open-ended — no known end` · `Dated, newest first` · `One continuous page` |
| Direction | `Following "next", which moves to older posts` |
| Stop condition | `Stops when there is no next page, or after 12 items` |
| Estimated size | `Estimated size: 30 MB — based on entries already saved here` · `Estimated size: 15–100 MB — a rough range — nothing saved here yet` · or `Size cannot be estimated yet` |
| Cancel | `You can stop this at any time from Activity.` |

Scope options, in this order, with the first preselected:

1. **Save current page only**
2. **Review related items** → the reviewable list, then **Save selected items**
3. **Save a number of items** → typed positive integer, up to the per-run
   ceiling. There is no open-ended option: every run stops at a number the
   user chose.

### 6.5 Restricted-access stopping

**Built.** Verbatim from `StopReason.message` in `lib/save/stop_conditions.dart`,
and re-checked against it. That enum carries more reasons than this table lists
— `noNextPage`, `selectionComplete`, `unsupportedContent`, `insufficientStorage`,
`storageLimitReached`, `repeatedUrl`, `cancelledByUser`, `interrupted` — which
are ordinary outcomes rather than access restrictions, and are out of this
section's scope rather than missing from it:

| Condition | Message |
|---|---|
| Sign-in | Stopped: the site asked for a sign-in. Sign in yourself in the Browser if you have an account, then start again from that page. |
| Paywall | Stopped: this page is behind a paywall. The app does not work around paywalls. |
| Verification | Stopped: the site showed a human-verification check. Complete it yourself in the Browser if you want to continue. |
| Access denied | Stopped: the site refused access to the next page. |
| Rate limited | Stopped: the site asked for fewer requests. Try again later. |
| Different site | Stopped: the next page is on a different website. |
| Loop | Stopped: the pages started repeating themselves. |
| Layout changed | Stopped: the page layout changed, so continuing might have saved the wrong thing. |
| Unclear next | Stopped: it was not clear which link continues the sequence. |
| Limit | Reached the limit you set. |
| Saving unavailable here | Saving isn't available on this site. |

The last row is the app's **own** policy, not something the site did — see
§6.8. Every other row in this table is a condition the app detected and stopped
at.

### 6.5.1 Sites Scrollary does not save from

**Built.** Verbatim (`kCaptureRestrictedMessage`), and the only sentence used
anywhere for this:

> Saving isn't available on this site.

Where it appears: when a queued save is refused, when a batch names how many of
its entries could not be queued, and on a task in Activity that was refused.

Where it does **not** appear: while the user is simply browsing one of these
sites. There is no banner, no warning and no interstitial — the Save control is
absent, and everything else about the Browser is unchanged.

The wording is deliberately about the app, not the user. It never mentions
copyright, never says the content is protected, and never suggests the user was
attempting anything.

### 6.6 Video pages

**Built.** Shown in the save sheet when the page is primarily a video.

When the page also carries readable content:

> **Video is not saved.** The readable text on this page can be, and the entry
> will link back to the original for anything that plays.

When it does not:

> **Video is not saved**, and this page has no readable text to save instead.
> Open it in the Browser when you want to watch it.

In the second case no capture mode is offered and the save is refused. The app
does not fall back to saving a video page's thumbnails, advertisements or
navigation images.

In the reader, an inline image a document did not store reads:

> This image was not saved.

or, when the file is gone rather than never fetched:

> This image is no longer on the device.

### 6.7 Empty and error states

**Partly built, and this table is the *intended* wording rather than a
transcript.** It was written before these screens were, and most of them ended
up saying something else. That is not automatically a defect — a screen may
have found a better sentence — but the difference has to be visible here, or
this section quietly becomes a false claim about the app. The third column is
what the app says today; where it differs, one of the two needs to change and
neither has been chosen yet.

| State | Wording specified here | In the app today |
|---|---|---|
| Empty library | **Nothing saved yet.** Open the Browser, find something worth keeping, and tap Save. | `Nothing saved yet` — matches (`library_screen.dart`) |
| Empty collection | Nothing in this collection is available offline yet. | **Different.** The collection screen's resume control reads `Nothing to read yet`; there is no separate empty-collection sentence |
| No saved sites | Sites you save appear here. Nothing is added for you. | **Different.** `No saved sites yet` / `Save the sites you read on so they're one tap away.` (`browser_home.dart`) |
| No history | Pages you visit appear here. Saving a page does not. | **Different.** `No history yet` / `Pages you open in the Browser show up here. Nothing is sent anywhere.` (`browser_history_screen.dart`) |
| Entry not offline | Not available offline — save again. | **Close, not verbatim.** `Not available offline yet.` and `Not available offline — you removed its files. …` (`entry_actions.dart`), `Not available offline` (`reader_screen.dart`) |
| Offline, save attempted | You are offline. Saving needs a connection; everything already saved is still readable. | **Not present.** The nearest is the Browser's own offline page state: `The device has no connection, so this page can't load. Entries …` |
| Save failed | Could not save this page. Nothing already saved was affected. | **Different.** The save panel shows the label `Save failed`; the sentence is not used |
| Out of space | Not enough space. Free some up on Settings → Storage, then try again. | **Different.** Title `Not enough space`, body `<n> GB available — saving needs at least 500 MB free. Existing downloads are …` (`save_scope_sheet.dart`) |
| Partial save | Saved, but some images are missing. You can try again for the missing ones. | **Different.** `This entry is saved, but incomplete — some images are missing.` (`save_preflight.dart`) |

None of these rows is quoted in the listing copy (§2–§4) or the reviewer notes
(§7), so nothing outward-facing depends on the mismatch.

---

## 7. Reviewer notes (App Store Connect / Play Console)

```
WHAT THIS APP IS

Scrollary is a personal read-later and offline reading app: an embedded browser,
a native library, and an offline reader. There is no account, no server, and no
back end — nothing needs to be enabled for review, and no demo credentials are
required.

THERE IS NO PRECONFIGURED CONTENT

The app ships with no list of websites, no site-specific rules, no selectors and
no content catalogue. The saved-sites list and the library both start empty. A
build-time test (test/repository_cleanliness_test.dart) fails if a third-party
hostname or a site rule is added.

The single exception is a RESTRICTED-SITE list, and it works the other way: it
names commercial content services the app REFUSES to save from — subscription
video, hosted commercial video, music, audiobooks, ebook stores and readers,
licensed serialised reading, and official publisher reading services. Nothing on
that list makes any site work. On those hosts the Save control is simply not
shown, while browsing them stays completely normal.

Amazon's retail domains are restricted in full, deliberately: their reading,
video, music and audiobook services share those domains, and no static rule can
separate a product page from a reader without inspecting the page. Apple and
Google are restricted only through selected content-service hosts (tv.apple.com,
music.apple.com, books.apple.com, podcasts.apple.com, itunes.apple.com,
play.google.com, books.google.com); their parent domains and unrelated
subdomains are untouched.

The rule is enforced below the interface, not by hiding a button: the direct
start, the queue, resume, retry, multi-page continuation, top-level redirects
mid-save and update checking each check it independently
(lib/save/capture_policy.dart; test/capture_restriction_test.dart).

The rule applies to the PAGE being saved, not to the individual images inside
it. Ordinary websites deliver their pictures through CDNs run by large
commercial platforms, so an image's delivery host is never tested against the
list — otherwise perfectly ordinary articles would save incompletely for a
reason unrelated to them. The audio/video restriction is separate and stricter:
the fetcher accepts image bytes only, verified by magic number rather than by
the server's declared content type, so audio and video are refused from every
host (test/asset_host_policy_test.dart). The list is
static and manually maintained — there is no remote configuration, no DRM
detection, no Terms-of-Service fetching, no user override and no developer
bypass. It reduces risk; it is not offered as a claim of legal compliance.
Nothing already downloaded is ever removed by it.

HOW SAVING WORKS

1. The user browses to a page themselves, in the app's browser.
2. They tap Save. The save sheet says what the page was detected to be and
   offers three capture modes (images only, text only, text and images), with
   any mode the page cannot support shown disabled and the reason beside it.
3. Below that, "How many entries". The DEFAULT and preselected option is
   "Current entry" — one page. The only other option is "Number of entries",
   where the user types a number, up to a per-run ceiling of 500.
4. THERE IS NO UNLIMITED OR OPEN-ENDED SAVE. The app has no "keep going until
   the site runs out" option; a multi-page run stops at the number the person
   typed, or sooner if the sequence ends. The sheet also shows an estimated
   size and the device's free space before anything starts.
5. Multi-page saves appear in Activity with live progress and can be cancelled at
   any point; cancellation takes effect at the next safe point and the wording
   says so.
6. Nothing saves in the background. Queued saves wait for an explicit Start.

WHAT IT DOES NOT DO

- It does not bypass authentication, subscriptions, paywalls, DRM, CAPTCHAs,
  robots restrictions, rate limits or anti-bot measures. When any of those is
  detected, saving STOPS and names the reason. There is no retry with different
  headers, no alternate-URL attempt, and no rate-limit wait-out anywhere in the
  code (see lib/save/stop_conditions.dart).
- It does not download, convert or export audio or video. The asset fetcher
  accepts image bytes only, verified by magic number. A page with media shows a
  placeholder and a link to the original page.
- It has no bulk export to Photos, Gallery, Downloads or shared storage. Saved
  files stay in app-private storage.

WEBVIEW AND JAVASCRIPT (for the Play device-and-network-abuse review)

The app injects a measurement script into its WebView. It is read-only: it
reports layout metrics, image metadata, links and structural signals, and can
scroll. It exposes no filesystem, database, network or native API to page
content, and it never evaluates page-supplied code. No code is downloaded or
executed from any source.

WHERE THINGS ARE

- Capture mode and how many entries to save: Browser → Save
- Queue, cancel, retry and the last run's summary: Library → Activity (top of the Library screen). Live progress appears wherever the run is visible
- Delete saved files, keeping the library entry: Collection detail → select →
  Remove offline files; or Settings → Storage
- Delete a whole collection permanently, files and records together:
  Collection detail → ⋯ → Delete permanently
- Clear browsing history: Browser → Home → Full history → Clear
- Clear website data (cookies, cache): Settings → Browser data
- Saved rules (page elements the user taught), Activity history: Settings
- Source attribution and "Open original page": Reader → ⋯, and Entry details

HOW TO TEST EACH CONTENT SHAPE

Use the demo site at <DEMO_BASE_URL> (original content, developer-owned):

  /article            one standalone article, no continuation
  /doc/page-1         a 12-page numbered document (rel=next + pagination)
  /posts              a reverse-chronological list of dated posts
  /journal            a chronological (oldest-first) list of dated posts
  /gallery/1          an image-heavy sequence, original artwork
  /chain/1            an open-ended next-link chain with no declared end
  /gated              a page behind a demo sign-in form — shows the app STOPPING

Suggested pass: save /article, leaving the preselected "Current entry" alone →
save /doc/page-1, choose "Number of entries" and type 3 → open /chain/1 and see
that even an endless next-link chain still requires a typed number, because
there is no open-ended option → open /gated and start a save to see the sign-in
stop condition → read offline in Airplane Mode → check Activity, then
Settings → Storage.

AGE RATING

The app allows the user to enter any web address, so it is rated for
unrestricted web access and is not directed to children.
```

---

## 8. Console checklists

### 8.1 App Privacy (App Store Connect)

| Question | Answer |
|---|---|
| Does your app collect data? | **No** |
| Third-party SDKs collecting data | **None** |
| Tracking (ATT) | **No** — no `NSUserTrackingUsageDescription`, no IDFA access |
| Privacy policy URL | required — see §8.5 |
| Data used to track you | none |
| Data linked to you | none |
| Data not linked to you | none |

Confirm the app contains no analytics, crash-reporting or advertising SDK before
answering. Current dependencies: `flutter_inappwebview`, `drift`, `dio`,
`flutter_riverpod`, `go_router`, `path_provider`, `uuid`, `crypto`, `collection`,
`wakelock_plus`, `share_plus`, `url_launcher`. None transmits data to the
developer.

### 8.2 Data safety (Play Console)

| Field | Answer |
|---|---|
| Does your app collect or share user data? | **No** |
| Web browsing history | Stored on device only; not collected (Play: local-only processing need not be disclosed) |
| Files and docs | Stored on device only; not collected |
| Is data encrypted in transit? | N/A — no data is sent to the developer |
| Can users request deletion? | **Yes**, in-app and without an account: per-collection *Delete permanently*, Settings → Storage, Browser → Full history → Clear, and Settings → Browser data. The full local reset is **not** part of this answer — it is gated by `kInternalBuild` and is absent from a Store build (PRIVACY.md §1) |
| Committed to Play Families policy | **No** |
| Independent security review | No |

### 8.3 Content rating (IARC)

- Violence / sexual content / language / controlled substances / gambling: **No**
- Users can interact / share location / share personal info: **No**
- **Unrestricted internet access: Yes**
- In-app purchases: **No**

### 8.4 Target audience

- Age groups: **18 and over** only
- Appeals to children: **No**
- Ads: **None**

### 8.5 Support and legal URLs — required, not yet created

- [ ] Privacy policy URL (public, reachable, matches `docs/PRIVACY.md`)
- [ ] Terms of use URL
- [ ] Content-rights page URL (may live under Terms)
- [ ] Support URL with a working contact address
- [ ] Marketing URL (optional)

### 8.6 Manual console and build tasks that cannot be done from this repository

- [ ] **Build the submission binary with no `--dart-define=SCROLLARY_INTERNAL_BUILD`.**
      Passing it compiles in the destructive local-reset screen and the
      entitlement override (STORE_POLICY_MAP.md §4). This is the one release
      obligation the code cannot enforce for itself.

- [ ] Answer the App Privacy questionnaire (§8.1)
- [ ] Answer the Data safety form (§8.2)
- [ ] Complete the IARC questionnaire (§8.3)
- [ ] Set the target audience to 18+ (§8.4)
- [ ] Enter the reviewer notes from §7 verbatim
- [ ] Upload screenshots built from the demo content only
- [ ] Confirm the final app name and bundle identifier (§1)
- [ ] Enter the privacy, terms and support URLs (§8.5)
- [ ] Declare the WebView/JavaScript position for Play (§7)
