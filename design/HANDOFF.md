# Handoff: Mac Vinyl Player — Desktop Widget + WidgetKit Widgets

## Overview
A tiny turntable that sits on the Mac desktop and plays along with whatever the user is listening to. A small pixel pet lives on top of it: it walks over to lift or lower the tonearm when playback is paused or resumed, swaps records when the song changes, and dances to the beat while music plays. Songs can be shared as a "sealed record" link that the recipient opens.

Deliverables for the native build:
1. **Desktop Player** — a borderless, transparent, always-on-desktop window (the main experience, full animation).
2. **WidgetKit widgets** — small / medium / large widgets for the desktop and Notification Center (static snapshots plus interactive buttons).
3. **Host app** — menu-bar app: Spotify sign-in, settings, playback bridge, shared-record link handling.

## About the Design Files
Everything in `design/` is a **design reference built in HTML**: a working prototype that shows the intended look, motion and behaviour. It is not production code to ship. Recreate it natively in **Swift / SwiftUI (+ AppKit where noted)**, targeting **macOS 14 Sonoma or later** (needed for interactive widgets).

To view the prototypes, open `design/Vinyl Player Widget.dc.html` in a browser (keep all files in the folder together). All logic lives in the `<script data-dc-script>` block at the bottom of each file; `vinyl-shared.js` holds cover lookup, cover-colour extraction and the synthesized audio.

## Fidelity
**High-fidelity.** Colours, sizes, timings and easings below are final. Match the motion feel closely, because the physicality *is* the product.

---

## Architecture

```
VinylHost.app (menu-bar, LSUIElement)
├── PlaybackService      // protocol; SpotifyService, AppleMusicService, MockService
├── ArtworkService       // cover URL + dominant tint, disk cache
├── DesktopPlayerWindow  // NSPanel, borderless, desktop-level, SwiftUI content
├── SoundEngine          // AVAudioEngine: needle drop + crackle loop
├── ShareService         // builds share links, handles vinyl:// open-URL
└── App Group container  // shared state for widgets (JSON + cover PNG)
VinylWidgets.appex (WidgetKit)
└── Small / Medium / Large, AppIntents: PlayPause, Next, Previous
```

### Desktop Player window (full-animation "widget")
- `NSPanel`, `styleMask: [.borderless, .nonactivatingPanel]`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false` (the shadow is drawn in SwiftUI).
- `level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)` so it sits on the wallpaper behind normal windows. Offer a "Float above windows" option that switches to `.floating`.
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`.
- Draggable by background (`isMovableByWindowBackground = true`); persist the frame origin.
- Content: one SwiftUI view, rendered by a single `TimelineView(.animation)` (or a `CADisplayLink` on macOS 14+) clock. **All motion derives from one clock + one state model**; never restart animations.

### Playback
- **Spotify** (primary): OAuth Authorization Code + PKCE via `ASWebAuthenticationSession`. Scopes: `user-read-currently-playing user-read-playback-state user-modify-playback-state`. Poll `GET /v1/me/player` every 1 s while the window is visible (back off to 5 s when hidden). Controls: `PUT /me/player/play|pause`, `POST /me/player/next|previous`, `PUT /me/player/seek`. Control needs Spotify Premium; without it, show the controls disabled with the tooltip "Playback control needs Spotify Premium".
  - In development mode Spotify only allows an allow-list of users. A public release needs Spotify's quota extension.
- **Apple Music**: MusicKit `ApplicationMusicPlayer` / `SystemMusicPlayer` (later phase; the UI shows "Coming soon").
- **Mock**: `TRACKS` array in the prototype (6 real songs), used for previews and tests.
- `PlaybackState { track(title, artist, album, durationMs, artworkURL, bpm?), isPlaying, progressMs, source }`.
- BPM: Spotify audio-features is restricted for new apps, so use a stored BPM when known; otherwise default to 100.

### Artwork
- Prefer the artwork URL from the playback source. Fallback: iTunes Search API (`https://itunes.apple.com/search?media=music&entity=song&limit=25&term=…`). Scoring is in `vinyl-shared.js → lookup()`:
  - exact normalised title match (strip `(feat…)` and ` - Remastered` suffixes);
  - reject remix / live / karaoke / instrumental / acoustic / sped up / slowed / cover / tribute;
  - exact artist +6, partial +3;
  - non-single/EP album +4, greatest-hits −3.
- Request 600×600 (`/600x600bb.`). Cache on disk keyed by `title|artist`.
- **User override**: the user can pick their own cover image for any track (prototype: click the cover thumbnail). It always wins.
- **Tint**: dominant colour weighted by saturation² × (1 − |luminance − 0.5|) + 0.02, sampled on a 300×300 downscale. This tint drives the glow, progress fill and widget backgrounds.

---

## Screens / Views

### 1. Desktop Player (344 × 384 pt, plus 58 pt above it for the pet)
The window content is a 344 pt wide column: pet zone (58 pt) → widget card (384 pt) → optional panels (Share / Crate, 12 pt gap).

**Widget card**: 344×384, corner radius 30, background `rgba(30,30,34,0.58)` (dark) / `rgba(246,244,240,0.72)` (light) over `NSVisualEffectView` (`.hudWindow`, blur ~40, saturation 170%). Stroke 0.5 pt `rgba(255,255,255,0.14)` inset; top highlight 1 pt `rgba(255,255,255,0.08)`. Shadows: `0 30 70 rgba(0,0,0,0.55)`, `0 8 20 rgba(0,0,0,0.35)`. Tint glow layer: radial gradient at top-centre, tint at 22% alpha (dark) / 19% (light), fading by 70%.

**Turntable deck (3D)**: a plane 344×300 at y −8, perspective 1000, rotated **X 30°** (the user looks slightly down). Build it in SceneKit / RealityKit, or fake it with layered SwiftUI and `rotation3DEffect`. Plane coordinates:
- Plinth: (18, 8) 308×288, radius 24, z −10, gradient `oklch(0.83 0.05 75)` → `oklch(0.76 0.055 68)` (warm sand). The front face is 10 pt deep, `oklch(0.62 0.05 62)` → `oklch(0.5 0.045 58)`.
- Platter: (25, 19) Ø258, metal gradient `#2e2e33 → #8c8c94 → #3a3a40`, 4 layers z −9…−6; soft shadow under it.
- **Record**: (30, 24) Ø248, z 0, edge thickness 5 pt (layers z −5…−1, `edge→edge2` gradient top→bottom).
  - Top surface: grooves = repeating radial `base 0–1.1 px, ridge 1.5 px, base 2.3 px`, plus 8 alternating wedges (`rgba(255,255,255,0.05)` every 45°).
  - Groove-band rings at insets 4/14/34/52.
  - Dead-wax ring inset 64 `oklch(0.86 0.045 80)`. Label = album art, inset 73 (Ø102), raised z 0.8, bevel inner shadows.
  - Spindle hole Ø12, metal spindle Ø7 stacked to z 8.
  - **Static** specular overlay (conic highlights at 26° and 206°) and bevel rim. These do NOT rotate; the record turns under the light.
- Record colours (picker): Classic `#101012/#1c1c20`; Oxblood `oklch(0.3 0.1 22)`; Ocean `oklch(0.32 0.09 245)`; Mustard `oklch(0.66 0.12 82)`; Smoke `oklch(0.42 0.01 260)`.
- **Tonearm**:
  - Pivot base Ø34 at (289, 29); post Ø12 stacked z −9…4.5.
  - Arm group at pivot (306, 46), z 6. Counterweight 14×26 at −40; tube 4×186; gimbal Ø18; headshell 12×24 rotated 22°; stylus 3×5 `oklch(0.72 0.15 45)`.
  - **Swing (rotateZ)**: rest 3°; playing 18° + 14° × progress (follows the groove inward). Transition 850 ms `cubic-bezier(.34,1.22,.52,1)` (slight overshoot).
  - **Lift (rotateX around the pivot)**: up 3.5°, down −1.4° (stylus touches). Transition 480 ms `cubic-bezier(.45,0,.2,1)`.
  - Arm shadow on the record: offset (h×0.35, h×0.55), blur 1.2 + h×0.18, opacity 0.6 when down / 0.38 when up, where h = 1 (down) or 12 (up).
- Status LED Ø6 at (310, 76): off `rgba(255,255,255,0.14)`; on `oklch(0.78 0.16 45)` with an 8 pt glow.
- RPM switch at (256, 258): a pill of "33" / "45", 10 pt semibold, on `oklch(0.32 0.03 60)`.

**Bottom bar**:
- Progress row at y 302, h 18 (the whole row is the scrub hit area): elapsed / `-remaining` 10 pt tabular, colour ink3; track 3 pt `rgba(255,255,255,0.1)`; fill = tint.
- Info row at y 330, h 44:
  - Cover thumb 40×40, radius 7 (click → pick custom cover).
  - Title 13 pt semibold, −0.01 em tracking; artist line 12 pt ink2 "Artist · Side A|B".
  - Controls: Prev 32, **Play/Pause 42** (white `rgba(255,255,255,0.93)`, icon `#141416`; hover scale 1.07, press 0.92), Next 32, Share 30, Crate 30.
- Ink (dark): ink `rgba(255,255,255,0.94)`, ink2 `0.6`, ink3 `0.45`. Ink (light): `#1d1a17`, 62%, 50%.
- Font: SF Pro (system).

**Pet** (pixel art, 3 pt pixels, 16 columns × 16–18 rows):
- Sits on the card's top edge at x 44 (feet at the card top).
- Pets:
  - Mochi the cat `#f0a860`;
  - Bao the panda `#f4f1ea` with `#3a3a42` patches;
  - Pip the frog `#8fcf6a`;
  - Tofu the bunny `#ece6f5`.
- Shared palette: outline k, belly `l`, blush `p`, white `w`. Headphones accessory `#2b2b30` with `#e0565b` cups.
- The sprite grids and frame variants are in the `PETS` / `BODY` / `petFrame()` source:
  - arms down/up;
  - eyes open / look / blink / happy / sleep;
  - legs a/b (walk);
  - accessory h.
- Render with nearest-neighbour scaling (`.interpolation(.none)`), flipping horizontally when it walks left.

**Panels below the card** (344 wide, radius 24, same glass):
- **Crate** tabs: Up next / Records / Pets.
  - Up next: horizontal list of 84 pt records with the album art on the label. The current one has a 2 pt ring `oklch(0.78 0.16 45)`. Tags: "Now playing" / "On deck" / "Up next" / duration.
  - Records: 5 swatches, 54 pt.
  - Pets: 4 tiles, 66×62. "Unlocked: headphones · On/Off" appears once unlocked.
- **Share**: sleeve and record preview, title, artist, the copy "Your friend gets a sealed sleeve. When they open it, the record slides out with the song and links to play it.", and buttons [Copy link] [Preview].

### 2. Shared Record (opened by a link)
Implement as a small web page (so non-users can open it) plus a deep link `vinyl://record?song=…&by=…&from=…&pet=…` for app users.
- Use the URL fragment (`#song=&by=&from=&pet=`) for the parameters.
- Layout: a 560×320 stage with the sleeve (57% wide square, radius 8, art) over the record (54%).
- Sealed state: a rotated "Tap to open" sticker on `oklch(0.86 0.12 80)`.
- Tap: the record slides out `translateX(76%)` over 1100 ms `cubic-bezier(.22,1,.36,1)`, the needle-drop sound plays and the record spins up (τ 600 ms).
- Then the title (30 pt bold) and artist appear, with buttons **Open in Spotify** (`#1ed760` on black text) and **Apple Music**.
- Page background: radial tint at 45% mixed into `#121013`.

### 3. WidgetKit widgets (desktop + Notification Center)
Same visual language, simplified; reference `iPhone Widget.dc.html` → "sleeve widgets" (sizes differ on Mac).
- **Small**: record (top-left, ~70% of the width) with the tonearm, title and artist below; tapping the record toggles play.
- **Medium**: sleeve (cover) with the record half out of it to the right; status "Now spinning · Side A" in tint, title 14 pt semibold (2 lines), artist, and Prev / Play / Next.
- **Large**: big sleeve and record, tonearm, pet, title and controls, progress bar, and an "Up next" row of 3 mini records.
- Background: linear 160° from `color-mix(tint 30%, #1f1c1a)` to `#161412` (dark); light uses tint 22% into `#f7f4ef` → `#ebe6df`.
- **What a widget can't do**: continuous spinning or walking/dancing. Use timeline entries plus `.contentTransition` / `.transition` for state changes:
  - arm up↔down (rotation, 0.7 s spring);
  - cover change (record slides into the sleeve, then back out);
  - pet pose (happy when playing, idle when paused, sleeping after 20 min paused).
- Interactive buttons: `Button(intent: PlayPauseIntent())` etc., all calling the host via the App Group / XPC. After each action, call `WidgetCenter.shared.reloadTimelines(ofKind:)`.
- *Optional, risky*: some widgets spin continuously using an undocumented SwiftUI rotation effect. It isn't App Store-safe, so it's not recommended for v1.

---

## Interactions & Behaviour (Desktop Player)

All driven by `isPlaying` from `PlaybackService`; the pet *performs* the transition.

**Play** (user presses Play, clicks the record, or the remote state flips to playing):
1. The pet walks from home (x 44) along the card's top edge to x 238 at 0.17 pt/ms, legs alternating every 130 ms.
2. It hops down to (242, 120) in 460 ms (cosine ease, 16 pt arc), arms up.
3. "Grab" for 1150 ms. At its start: the arm swings over the record (`armOver`). At 620 ms it lowers (`armLow`) and the needle-drop sound plays. At 980 ms the motor starts. Send the play command at that moment.
4. It hops back up, walks home, then dances.

**Pause**: the same walk and hop. At grab: the motor stops (the record spins down naturally), the arm lifts at 420 ms and swings home at 820 ms. Ignore input while the pet is busy (`busy`). With **Reduce Motion** on, or the setting "Pet operates arm" off, skip the pet and run the sequence directly.

**Platter physics**: angular velocity eases to target 33⅓ (or 45) rpm with τ 420 ms when spinning up and 380 ms when spinning down. Belt-drive option: 1500 / 1100 ms. Angle accumulates and **never resets**; resuming continues from the same angle. Reduce Motion: 12% speed.

**Song change** (Next / Prev / pick in Up next / track ends):
1. If playing: motor off, arm lifts at 300 ms and swings back at 650 ms.
2. The pet walks to x 128 (above the record). At D = 950 ms (playing) or 150 ms (paused), the record lifts (z up to 36) and slides away 300 pt up behind the top edge over 700 ms (smoothstep).
3. The art swaps; after a 220 ms gap the new record drops back in over 760 ms (ease-out cubic).
4. If it was playing, the arm drops again and the motor restarts. The pet walks home.
5. **Side flip**: when moving between neighbouring tracks across the A/B boundary (tracks 1–3 = Side A, 4–6 = Side B), the record lifts z 46 and flips (rotateY 0→90°, then −90→0°) instead of sliding.

**Pet personality** (only while at home):
- **Dancing**: amplitude eases to 1 (τ 260 ms). The beat follows the track's BPM.
  - Bounce height (1.6 + 4×tempo) × |sin(beat·π)|^1.4 and side sway (3.2 − 1.8×tempo), where tempo = clamp((bpm − 84) / 34).
  - Arms go up on even beats; a landing squash of 5%.
  - A hop every 6–14 beats; a happy squint with 8% chance per beat.
- **Idle**: breathing (±1.5% scaleY, 3.2 s period).
  - Blinks every 2.2–5.4 s (150 ms) and looks toward the record now and then (1.2–2.1 s).
  - Eyes droop after 7 s; asleep with a "z" after 20 s. Click the pet to wake it (hop plus a happy squint).
- **Unlock**: after 45 s of cumulative listening, headphones unlock (can be toggled in Pets). Production: make this hours-based and add more unlockables.
- **Stuck needle (easter egg)**: while playing, about once every 2.5 min on average, the record jitters for 1.5 s. Progress loops back 0.38 s every 380 ms, the arm bounces, then the pet hops ("bonk") and play continues.

**Hover**: the record lifts z +2.5 pt (τ 120 ms). Buttons: hover background `rgba(255,255,255,0.09)`, press scale 0.9.
**Scrub**: pointer-down anywhere on the progress row seeks; the drag updates live; the tonearm angle follows progress.
**Sound** (toggle, default on):
- Needle drop = a 90→38 Hz sine thump (180 ms, peak 0.22) plus an 80 ms band-passed noise tick at 2.4 kHz.
- Crackle = a looped 3 s buffer of sparse clicks (p 0.00035) plus faint hiss, high-passed at 900 Hz, gain 0.14 with a 0.6 s fade in and 0.35 s fade out. It plays only while the motor is on and the arm is down.

---

## State Management
- `PlaybackState` (above) is the single source of truth. The view model keeps local state on top of it:
  - motion: `armOver`, `armLow`, `motor`, `angle`, `velocity`;
  - pet: `pet.mode` (home | walk | hopDown | grab | hopUp | back | swap) with position, facing and timers; `busy`;
  - selections: `rpm`, `vinyl`, `petId`, `drawer`, `share`;
  - flags: `theme`, `sound`, `listenedMs`, `unlocks`.
- Remote changes (e.g. paused from the phone) should run the same pet sequence, unless the window is hidden; then apply instantly.
- Widgets read a snapshot from the App Group: `{title, artist, coverPNG, tint, isPlaying, progress, upNext[3], petId, petPose}`. Write it on every state change, throttled to once per second.

## Design Tokens
- Glass: dark `rgba(30,30,34,0.58)`, light `rgba(246,244,240,0.72)`; card radius 30, panel radius 24, button radii fully round.
- Deck sand `oklch(0.83 0.05 75)` / `oklch(0.76 0.055 68)`; label ring `oklch(0.86 0.045 80)`.
- Accent / LED `oklch(0.78 0.16 45)`. Spotify button `#1ed760`.
- Track fallback tints:
  - Blinding Lights `#5a78c8`
  - Dreams `#d9784a`
  - Get Lucky `#3fa58a`
  - Redbone `#e0a24a`
  - Electric Feel `#7aa860`
  - Heat Waves `#c86aa8`
- Type: SF Pro.
  - Title 13/600, artist 12/400, times 10 tabular, panel labels 11/600, pill 10/600.
  - Shared page: headline 26/700, song 30/700.
- Motion:
  - arm swing 850 ms `(.34,1.22,.52,1)`; arm lift 480 ms `(.45,0,.2,1)`;
  - hover 120 ms; button spring `(.3,1.4,.5,1)` 180 ms;
  - record swap 700 / 220 / 760 ms.

## Assets
- No bitmap assets. Everything is drawn: pixel pets from character grids, records from gradients.
- Album art comes from the playback source, the iTunes Search API, or the user's own image.
- Icons are simple geometric glyphs; use SF Symbols in native code: `backward.end.fill`, `play.fill`, `pause.fill`, `forward.end.fill`, `square.and.arrow.up`, `line.3.horizontal`.

## Files
- `design/Vinyl Player Widget.dc.html` — the full Desktop Player prototype (open in a browser). Tweaks: theme, sound, drive, armFollowsGroove, petOperatesArm.
- `design/Shared Record.dc.html` — the shared-record receive page.
- `design/vinyl-shared.js` — artwork lookup and scoring, tint extraction, custom covers, audio synthesis.
- `design/support.js` — the prototype runtime (needed only to view the HTML).
- `design/iPhone Widget.dc.html` — reference for the WidgetKit visuals ("sleeve widgets", "Large widget"). The iPhone sizes differ from the Mac ones.
