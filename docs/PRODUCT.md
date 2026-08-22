# Product definition

> **What Scrollary is, for whom, and what it refuses to be.** The durable
> product statement, including parts not yet built.
> [ARCHITECTURE.md](./ARCHITECTURE.md) is the record of what exists today and is
> the one to trust about current behaviour.
>
> Terminology: [TERMINOLOGY.md](./TERMINOLOGY.md) · Domain:
> [V2_ARCHITECTURE.md](./V2_ARCHITECTURE.md) · Decisions:
> [DECISIONS.md](./DECISIONS.md).

## 1. What it is

**Scrollary is a cross-platform personal reading library for web-based reading
content.**

You read something on the web. Scrollary recognises what it is, keeps your
library current, and remembers where you got to — across the sites that publish
it and across your own devices. Where you are entitled to keep a copy, a device
can hold one for reading offline.

### 1.1 The centre is recognition, not curation

The primary write path is **not** manual download management. The normal
experience is:

1. You read — in Scrollary's browser on mobile, or through the extension on
   desktop.
2. Scrollary recognises which Collection, Entry, Source and Location that is.
3. If you follow the Collection, your library stays current on its own.
4. Reading state follows the **logical Entry**, whichever site you read it on.
5. Your library synchronises between your clients, automatically.
6. Downloading is an optional, per-device capability.

Explicit adding still exists. It is the fallback, not the main path.

### 1.2 The correction this document exists to make

A reader of V1's code alone would conclude Scrollary is a downloader whose
library consists of what it has downloaded. That was true of the first
implementation and it is not the product.

> **An Entry is in the library because you want to read or track it — not
> because its content has been downloaded, and not because of the URL it happens
> to live at.**

## 2. The model

**Library → Folder → Collection → Entry → Page or Section**, with Sources and
Locations underneath. `Collection` and `Entry` remain the only content nouns in
code; user-facing labels come from `lib/library/entry_labels.dart` and nowhere
else.

```
Library
└── Folder "Weekly"                user organisation
    ├── Collection                 a logical work
    │   ├── Source A   tr          the work, on one site
    │   ├── Source B   en          a translation is a Source
    │   └── Entry 101              a logical unit — carries reading state
    │       ├── Location on A      a URL
    │       ├── Location on B      a URL
    │       └── OfflineCopy        this device's bytes
    └── Entry (standalone)         a one-off, still a first-class item
```

### 2.1 Folder is not Collection

| | Means | Decided by |
|---|---|---|
| **Folder** | How *you* organise your library | You |
| **Collection** | Related content that belongs together | The content |

A Folder holds Collections and standalone Entries. A Collection holds Entries. An
Entry inside a Collection lives where its Collection lives — it has no separate
Folder membership. A standalone Entry lives in a Folder directly, and is never
wrapped in a Collection of one to make the model tidy.

Folder organisation synchronises. Deleting a Folder moves its children up; it
never destroys a Collection or an Entry.

### 2.2 A Collection can be published in several places

The same work often appears on several sites, sometimes in several languages, and
sites move, restructure and die. So a Collection has **Sources**, one per site,
each carrying its own language and lifecycle. A translation is a Source of the
same Collection, not a separate Collection — you read the work once.

Where sites number their content explicitly, Entries merge across Sources by
position. Where they do not, Sources still coexist and are readable, but Entries
are not merged — **Scrollary does not pretend every website can be normalised.**

### 2.3 Four independent facts about an Entry

| Fact | Meaning |
|---|---|
| **Known** | A Source lists it |
| **In the library** | You follow the Collection, or added it yourself |
| **Downloaded** | *This device* holds readable bytes |
| **Read** | You have read it, wherever you read it |

Conflating any two of these is a product bug. An Entry can be read but never
downloaded; downloaded on one device and not another; known without being yours.

### 2.4 The verbs

| Verb | Scope |
|---|---|
| **Follow a Collection** | Your library, everywhere |
| **Add to Library** | Your library, everywhere |
| **Organise into a Folder** | Your library, everywhere |
| **Read / Track** | Your library, everywhere |
| **Open at Source** | Records access, everywhere |
| **Download for Offline** | **This device** |
| **Remove Offline Copy** | **This device** |
| **Remove from Library** | Your library, everywhere |

*Remove Offline Copy* and *Remove from Library* are different operations with
different blast radii and are never offered as substitutes. **No action on one
device destroys bytes on another.**

## 3. Where reading happens

Both count, and both write to the same Entry.

- **In Scrollary's reader**, from a downloaded copy. Position is measured, so
  progress is precise and completion can be detected.
- **On the source website.** Scrollary cannot observe position there, so it
  records that the Entry was opened and when — and never invents a progress
  figure or infers that you finished. Marking read stays explicit and available
  everywhere.

A progress reading is scoped to the rendering it was taken against. Sixty percent
of one Source's rendering is not a claim about another's.

## 4. Cross-platform

Your library follows you across your own clients: what is in it, how it is
organised, where it came from, what you have read, and roughly how far you got.

**Library metadata and reading state cross the network. Downloaded content never
does.** Offline availability is a property of a device.

Signing in is **optional on mobile, permanently**. Without an account, Scrollary
is the complete product on one device. The browser extension requires an account
by nature — it exists to put things into a library shared with your phone.

## 5. Product principles

### 5.1 Local-first

Every action succeeds against the device in front of you and is visible
immediately. Synchronisation happens afterwards, on its own. A network failure
never rolls back a library or reading action. The app is fully usable with no
connectivity and, on mobile, with no account.

### 5.2 The user owns their state

Their library, organisation, reading position, downloaded files and corrections
are theirs. Nothing is deleted to simplify an implementation, no automatic
process removes something they attached to, and no remote action destroys local
files.

### 5.3 Honest over universal

A low-confidence answer is printed as one. Where two Sources contradict each
other, the contradiction is kept and shown rather than repaired by guessing.
"Finished" and "the site stopped us" are different outcomes. Scrollary would
rather be reliably narrow than broadly wrong.

### 5.4 The app stops; it never works around

When a source declines, the app stops and names the condition. No retry with
different headers, no alternate-URL attempt, no cookie manipulation, no waiting
out a rate limit, no getting past any access control.

### 5.5 Nothing site-specific ships

No hostname, selector, site list or provider catalogue. Detection uses standard
HTML semantics and measurement. The one exception is the restricted-capture
policy, which only ever *refuses*.

### 5.6 Simple

The smallest coherent solution. No speculative abstraction, no mechanism without
a demonstrated problem, no second copy of a rule that already lives somewhere.

## 6. Two rules about the network

These are different things and V2 treats them differently.

### 6.1 Content-affecting source automation — explicit

Capture, source traversal, update checking, and anything that drives the browser
remain **user-started, visible, bounded and cancellable**. Nothing saves in the
background. Every ceiling is a number the user chose and can see.

### 6.2 Metadata synchronisation — automatic

Synchronising library organisation and reading state is **automatic,
opportunistic and mostly invisible**. It fetches no page, drives no browser and
stores no content. It runs when the app has a reasonable execution opportunity,
resumes after connectivity returns, and is safe to interrupt at any point.

Scrollary does **not** promise permanent background execution — no mobile
platform offers it. It promises durable local state and reliable continuation.

*This split replaces the earlier blanket rule. See
[DECISIONS.md](./DECISIONS.md) V2-D20.*

Reaching the network for this is a **Pro capability**: the library keeps
working identically without it — everything commits locally and nothing is
gated on recording, reading or organising — but a Free device's own mutations
stay on that device until it is entitled ([DECISIONS.md](./DECISIONS.md)
V2-D37).

## 7. What Scrollary is not

Not a bulk fetcher, an automated harvester, a site archiver, a client for
particular websites, or a tool for getting past any access control.

- **Not a generic bookmark manager.** The library is organised around Collections
  and Entries — related reading content with structure, order and reading state.
  Folders are how you arrange those, not a replacement for them.
- **Not a hosted content platform.** The backend holds library metadata and
  reading state. It never holds page content, never fetches a page, and
  downloaded bytes are never uploaded.
- **Not a content redistribution service.** Nothing is shared with anyone,
  including the developer. No sharing, no public library, nothing cross-user.

Audio and video are never saved. No analytics, crash-reporting or advertising
SDK.

## 8. Where the rest is written down

| Question | Document |
|---|---|
| What exists today, exactly | [ARCHITECTURE.md](./ARCHITECTURE.md) |
| The nouns and labels | [TERMINOLOGY.md](./TERMINOLOGY.md) |
| Domain model, invariants, state ownership | [V2_ARCHITECTURE.md](./V2_ARCHITECTURE.md) |
| Sync, backend boundary, client contract | [V2_SYNC.md](./V2_SYNC.md) |
| What gets built, in what order, by how many agents | [V2_ROADMAP.md](./V2_ROADMAP.md) |
| Auth, monetization, production, deferred questions | [V2_PRODUCTIZATION.md](./V2_PRODUCTIZATION.md) |
| Why a decision was made | [DECISIONS.md](./DECISIONS.md) |
| Store positioning and exact copy | [STORE_PACKAGE.md](./STORE_PACKAGE.md) |
| Policy reasoning behind the safety rules | [STORE_POLICY_MAP.md](./STORE_POLICY_MAP.md) |
| Per-flow data audit | [PRIVACY.md](./PRIVACY.md) |
