# Vinyl Player

A tiny turntable for the Mac desktop. A little pixel pet lives on top of it: it walks over to lower or lift the tonearm when you press play or pause, swaps records when the song changes, and dances to the beat while music plays.

What's included:

- **Desktop player:** a borderless window pinned to the desktop (behind your other windows) with all the animation.
  - The record spins in 3D and resumes from the same angle.
  - The tonearm drops and lifts, and follows the groove.
  - The pet walks over, works the arm, swaps and flips records, dances, blinks, dozes off and unlocks headphones.
  - There's a needle-drop sound and crackle.
  - Covers are the real album art, and the colours come from the cover.
  - The crate has Up next, record colours and pets.
  - You can share a song as a record.
- **Widgets:** small, medium and large widgets for the desktop and Notification Center. They show the cover, song and pet, and have working play/pause and skip buttons.
- **Menu bar app:** a record icon in the menu bar with controls and settings. There's no Dock icon.

It uses six sample songs for now. Spotify sign-in is the next step.

## Install the test build (no Xcode)

Every change pushed to `main` is built automatically on GitHub, and the result is published as **[VinylPlayer.zip](https://github.com/azhaf7/vinyl-player/releases/download/latest/VinylPlayer.zip)** (also listed under **Releases → latest**).

1. Download **VinylPlayer.zip** and double-click it to unzip.
2. Drag **Vinyl Player** into your **Applications** folder.
3. Double-click it. The build isn't signed with an Apple ID, so macOS blocks it the first time:
   - **macOS 15 or later:** click **Done**, open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to "Vinyl Player". Then confirm.
   - **macOS 14:** right-click the app, choose **Open**, then **Open** again.

The turntable appears at the top right of the desktop, and a record icon appears in the menu bar.

The test build has the full desktop player and pet. The **widgets need the signed version** you build with Xcode (below), because macOS only loads widgets from apps signed with an Apple ID.

## Build it yourself with Xcode

### Requirements

- A Mac with **macOS 14 Sonoma** or later.
- **Xcode 16** or later (free from the Mac App Store).
- A free **Apple ID** to sign the app so it runs on your Mac.

### Run it

1. Clone or download this repository, then double-click **`VinylPlayer.xcodeproj`** to open it in Xcode.
2. Add your Apple ID if Xcode doesn't have it yet: **Xcode → Settings → Accounts → +**.
3. Click the blue **VinylPlayer** project at the top of the left sidebar. Set up signing for **both** targets:
   1. Select **VinylPlayer**, open **Signing & Capabilities**, and set **Team** to your name (Personal Team).
   2. Do the same for **VinylWidgets**.
   3. If Xcode says the bundle identifier is taken, change `com.azhaf7` to something of your own in both targets. Keep the `.widgets` ending on the widget target.
4. Choose **VinylPlayer** and **My Mac** in the toolbar, then press **⌘R** (Product → Run).

The turntable appears at the top right of your desktop, and a record icon appears in the menu bar.

#### Keep it after closing Xcode

Choose **Product → Archive**, then **Distribute App → Copy App**. Drag the exported **Vinyl Player.app** into **Applications**.

To have it start automatically, turn on **Settings… → Open at login** in its menu.

#### Add the widgets

1. Right-click an empty part of the desktop and choose **Edit Widgets…**.
2. Search for **Vinyl**, choose a size, and drag it onto the desktop or into Notification Center.

The app needs to have run at least once first.

## Using it

- **Play / pause:** the white button, a click on the record, or the menu bar menu. The pet walks over and works the tonearm.
- **Skip:** the back and next buttons. The pet lifts the record out and drops in the next one. Going between song 3 and song 4 flips the record from side A to side B.
- **Scrub:** drag along the progress bar. The tonearm follows.
- **Your own cover:** click the small cover next to the song title.
- **Crate (☰):**
  - **Up next:** tap a record to play it.
  - **Records:** pick a vinyl colour.
  - **Pets:** pick Mochi, Bao, Pip or Tofu. Headphones unlock after a while of listening.
- **Share (⇧):** copies a link that opens the song as a sealed record (see below).
- **Wake the pet:** click it after it falls asleep.
- **Move the player:** drag it by an empty part of the card.
- **Menu bar → Float Above Windows:** keeps it on top instead of on the desktop.
- **Menu bar → Move Player to Top Right:** brings it back if it gets lost.

## Sharing records

The share link opens `web/shared-record/`, a small web page that people without the app can open. Host the `web/` folder somewhere public, then paste the page's address into **Settings… → Sharing**.

[Netlify Drop](https://app.netlify.com/drop) works: drag the `web` folder onto it. GitHub Pages also works if the repository is public.

## Project layout

```
App/        Desktop player, menu bar, settings, artwork, sound, widget bridge
Widgets/    WidgetKit extension: small, medium and large widgets and their buttons
Shared/     Code both targets use: songs, records, pet sprites, shared storage
Config/     Info.plists and entitlements
web/        The Shared Record page
design/     The original HTML prototypes and design handoff (reference only)
```

How the parts fit together:

- **One clock drives all motion.** `PlayerModel` is updated by the display's refresh, or by a slow timer while the player is hidden. Nothing restarts an animation.
- **The 3D deck is real perspective.** Each part of the turntable is a flat layer placed at its own height and projected with the same perspective as the prototype's CSS (`App/Motion.swift`).
- **Widgets talk to the app through an App Group.** The app writes a snapshot of what's playing (plus cover images). Widget buttons send commands back. If the app isn't running, the widgets still update their own state.
- **Music sources plug in through `PlaybackService`** (`App/PlaybackService.swift`). Spotify will plug in there.

## Troubleshooting

- **"Signing for VinylWidgets requires a development team":** set the Team on the **VinylWidgets** target too (step 3 above).
- **Widgets show sample songs and don't follow the player:** both targets need the same Team, so they share the App Group. Run the app once after changing it.
- **No album covers:** covers are downloaded from Apple's iTunes catalogue, so the Mac needs internet the first time. After that they're cached.
- **Can't see the player:** use the menu bar icon → **Show Player**, then **Move Player to Top Right**.
