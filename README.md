# MoonTV for Apple TV (tvOS)

Native SwiftUI + AVKit Apple TV client for self-hosted [MoonTV / LunaTV](https://github.com/MoonTechLab/LunaTV) and [MoonTVPlus](https://github.com/mtvpls/MoonTVPlus) instances running on a Raspberry Pi or home server.

Designed to be built completely without macOS via **GitHub Actions (`macos-15`)** + **XcodeGen** and sideloaded onto Apple TV using **[atvloadly](https://github.com/bitxeno/atvloadly)**.

## Features

- **Apple TV+ style Home & Discovery**: Full-width Hero Banner, Continue Watching progress shelves, Douban Trending Movies & TV rows (`/api/douban`), and a dedicated **Categories** tab (`/api/categories`).
- **Detail & Source Switching**: Poster header, synced **Favorite** toggle (`/api/favorites`), watched episode indicators, and a **Switch Source** sheet to jump between Raspberry Pi video sources if a CDN buffers.
- **Built-in HLS Ad-Blocker**: Intercepts `.m3u8` playlists via `AVAssetResourceLoaderDelegate` and strips spliced `#EXT-X-DISCONTINUITY` ad segments before playback (toggleable in Settings).
- **Subtitles & Up Next**: In-player **Subtitles** transport-bar button for MoonTVPlus tracks + OpenSubtitles.com search with `±0.5s` sync, plus an **Up Next** episode countdown overlay and **Next Episode** transport button.
- **Custom IP & Port + Zero Paid Entitlements**: Point to `192.168.x.x:3000` directly in Settings; zero CloudKit/App Group entitlements so `atvloadly` can re-sign cleanly with a free Apple ID.

## Build on GitHub Actions (No Mac Required)

1. Push these files to a new GitHub repository (`main` branch).
2. Open the **Actions** tab and run **Build Unsigned tvOS IPA** (runs automatically on every push to `main`).
3. Download the `MoonTV-tvOS-unsigned-ipa` artifact and unzip it to get `MoonTV-tvOS-unsigned.ipa`, or tag a release (`git tag v1.2.0 && git push origin v1.2.0`) so `atvloadly` can track your GitHub Releases directly.
