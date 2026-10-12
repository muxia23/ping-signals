<div align="center">

<img src="docs/images/classic-wheel.png" width="200" alt="ping-signals classic wheel">

# ping-signals

**The League of Legends ping wheel, on your Mac desktop, and every ping actually does something.**

Hold <kbd>⌥</kbd> and drag to summon the wheel. Let go to drop the signal.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](#install)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-native-1f6feb)](#performance)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![App size](https://img.shields.io/badge/app-2.5%20MB-brightgreen)](#performance)

**English** · [简体中文](README.md)

<img src="docs/images/classic-strip.png" width="800" alt="classic ping wheel, each direction highlighted">

</div>

---

## ✨ Why

[lolPing](https://github.com/darrenprx/lolPing) brought Summoner's Rift pings to the desktop. It's fun, but it's Electron: about **490 MB** of memory, 7–12% CPU while idle, and a 175 MB installer.

ping-signals is a pure Swift rewrite that keeps only the pings, then turns each ping into a **signal**. A question mark is just a question mark. Assist Me calls Claude. Danger retreats you to a clean desktop in one move.

## 🎯 Signals

| Ping | Direction (classic) | Action |
|:---:|:---:|---|
| ❗ **Danger** | ↑ | **Retreat**: hides every window, leaving only the wallpaper, Dock and menu bar. Ping Danger again and everything comes back |
| ⬇️ **On My Way** | → | **Todo panel**: slides in from the right, ready to type. Records the app, window title and web address you were on; click it to jump back |
| 🚩 **Assist Me** | ↓ | **Call Claude**: opens Claude desktop's Quick Entry |
| ❓ **Enemy Missing** | ← | Nothing. It's just a question mark |
| 📍 **Generic ping** | <kbd>⌥</kbd> + click | Animation and sound only |

> Previews in the menu bar never trigger actions.

## 🕹️ Two wheels

<table>
<tr>
<td align="center" width="50%">
<img src="docs/images/classic-wheel.png" width="240"><br>
<b>Classic (pre-2022) · default</b><br>
<sub>4 slots, original 12.21 art and sounds</sub>
</td>
<td align="center" width="50%">
<img src="docs/images/modern-wheel.png" width="240"><br>
<b>Modern</b><br>
<sub>8 slots: Push, All In, Need Vision, Bait…</sub>
</td>
</tr>
</table>

## ⚡ Performance

| | lolPing (Electron) | **ping-signals** |
|---|---:|---:|
| Memory | ~490 MB | **~40 MB** |
| Idle CPU | 7–12% | **0.03%** |
| App size | 343 MB | **2.5 MB** |

<sub>M1 Pro / macOS, measured with `scripts/measure.sh`.</sub>

How: no plain mouse-move monitoring (events arrive only while the trigger key is held), overlay windows exist only while in use, audio runs on its own queue, and textures are cropped to what's drawn.

## 🧠 Details

- **Steps aside for full-screen games**: <kbd>⌥</kbd> + click passes straight through when a full-screen game is in front. Full-screen browsers, players and editors still get pings.
- **Never eats your clicks**: an <kbd>⌥</kbd> + click without a drag is replayed to the app underneath.
- **Pause anytime**: <kbd>⌃</kbd><kbd>⌥</kbd><kbd>P</kbd> pauses and resumes; the menu bar icon greys out.
- **Multi-display aware**: Retreat covers each screen with its own wallpaper.
- **Self-healing**: if Accessibility is revoked or the system disables the event tap, ping-signals notices and recovers.

## 📦 Install

> There's no release yet; build from source for now.

Requires macOS 14+, Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/muxia23/ping-signals.git
cd ping-signals
brew install xcodegen

scripts/make-cert.sh        # once: local signing identity, so rebuilds keep the Accessibility grant
xcodegen generate
xcodebuild build -project PingSignals.xcodeproj -scheme PingSignals \
  -configuration Release -derivedDataPath build -quiet

open build/Build/Products/Release/ping-signals.app
```

Grant **Accessibility** on first launch (needed to watch for <kbd>⌥</kbd> + drag). The first time On My Way reads a browser's address, macOS asks for **Automation**; declining still saves the todo.

## 🏗️ Layout

```
Core/      PingCore: pure logic (gesture machine, wheel geometry, ping catalog, signal bus, todo store, retreat plan)
App/       System-facing code (event tap, overlay, wheel drawing, animation, audio, menu bar, actions)
Tests/     Swift Testing unit tests
scripts/   Signing identity, asset import, performance measurement
docs/      Design specs and implementation plans
```

```bash
xcodebuild test -project PingSignals.xcodeproj -scheme PingSignals \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build
```

## 🗺️ Roadmap

- [x] Classic and modern wheels with animation and sound
- [x] Signal actions: Retreat, todo panel, call Claude
- [ ] Settings window: trigger key, drag threshold, modern wheel editor, pause hotkey recording
- [ ] Onboarding, launch at login
- [ ] Chinese / English UI
- [ ] Auto-update (Sparkle) and a first release
- [ ] More signals: let "?" record the question you had…

## 🙏 Thanks

- [darrenprx/lolPing](https://github.com/darrenprx/lolPing): the inspiration; the gesture logic is ported from it (MIT).
- [CommunityDragon](https://communitydragon.org): archive of the classic 12.21 wheel art.

## 📄 License

Code is released under the [MIT](LICENSE) license.

ping-signals isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games or anyone officially involved in producing or managing Riot Games properties. Riot Games, and all associated properties are trademarks or registered trademarks of Riot Games, Inc. Ping art and sounds are © Riot Games, Inc.

<div align="center">
<sub>If it made you smile, a ⭐ would be nice.</sub>
</div>
