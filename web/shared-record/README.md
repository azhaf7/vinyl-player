# Shared Record page

The page a friend opens from a "share as a record" link. It is a static page with no build step and no dependencies, implemented from `design/Shared Record.dc.html` and §2 of `design/HANDOFF.md`.

## Link format

```
https://<host>/shared-record/#song=Dreams&by=Fleetwood%20Mac&from=Sam&pet=Mochi
```

| param  | meaning                    | default      |
|--------|----------------------------|--------------|
| `song` | track title                | `Get Lucky`  |
| `by`   | artist                     | `Daft Punk`  |
| `from` | sender name                | `A friend`   |
| `pet`  | sender's pet name (optional) | (none)       |
| `spotify` | Spotify track id (optional): "Open in Spotify" opens that exact song | (search) |

Parameters go in the URL fragment so they never reach a server. Query-string parameters also work as a fallback. Native app users get the same parameters through `vinyl://record?song=…&by=…&from=…&pet=…`, which the Mac app handles.

## Behaviour

- **Sealed:** the sleeve shows the song's cover with a "Tap to open" sticker.
- **On tap:**
  - the record slides out (`translateX(76%)`, 1100 ms `cubic-bezier(.22,1,.36,1)`);
  - the needle-drop sound plays;
  - the record spins up to 33⅓ rpm (τ 600 ms);
  - the title, artist and the Spotify / Apple Music search buttons appear.
- **Cover art:** looked up with the iTunes Search API, using the same scoring as `vinyl-shared.js`, and cached in `localStorage` (`vinyl-art-v3`). The cover tint fades into the page background.
- **Offline:** the cover falls back to an abstract gradient.
- **Reduced motion:** the slide-out is instant and the record spins at 12% speed.

## Run locally

```
cd web && python3 -m http.server 8000
# open http://localhost:8000/shared-record/#song=Dreams&by=Fleetwood%20Mac&from=Sam&pet=Mochi
```

Host the `web/` folder anywhere static, such as GitHub Pages or Netlify, so that recipients can open the links.
