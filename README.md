# Studio Display Control

A lightweight macOS menu bar utility that **simultaneously controls volume and brightness across all connected Apple Studio Displays** using your keyboard keys.

![App Icon](AppIcon.png)

## Why I Built This

I bought two Apple Studio Displays and wanted to use both of their built-in speakers together as a stereo pair — the sound quality is actually surprisingly good when they're working in unison.

So I went into Audio MIDI Setup, created a Multi-Output Device combining both displays, and it worked... until I tried to change the volume.

**macOS completely disables the keyboard volume keys for Multi-Output Devices.** The volume buttons on the keyboard? Grayed out. The menu bar volume slider? Gone. The only way to adjust volume is to dig back into Audio MIDI Setup and manually drag a tiny slider for each individual device. Every. Single. Time.

I looked for solutions. The free tools out there didn't quite solve this specific problem. The ones that did — like SoundSource — cost $39. For a volume slider.

So I wrote this app in a single afternoon. It intercepts the keyboard media keys and directly controls all your Studio Displays at once. Volume, brightness, mute — everything stays in sync. It sits quietly in your menu bar and just works.

If you're running multiple Studio Displays and this annoys you too, here you go. It's free.

## Features

- **Synced Volume Control** — F10/F11/F12 keys adjust volume on all Studio Displays at once
- **Synced Brightness Control** — F1/F2 keys adjust brightness on all Studio Displays at once
- **Mute Toggle** — Mute/unmute all displays simultaneously
- **Menu Bar Sliders** — Manual adjustment via sliders in the menu bar dropdown
- **Hot-Plug Support** — Automatically detects newly connected displays (polls every 10s)
- **Lightweight** — Single-file Swift app, no dependencies, minimal resource usage
- **Menu Bar Only** — No Dock icon, runs quietly in the background

## Screenshots

When you click the 🖥️ icon in the menu bar:

```
Studio Display: Audio ×2  Display ×2
────────────────────────────────
🔊 Volume
  Volume: 50%
  [━━━━━━━━━━━━━━━━━━━━]
  Mute
────────────────────────────────
☀️ Brightness
  Brightness: 75%
  [━━━━━━━━━━━━━━━━━━━━]
────────────────────────────────
Refresh Devices
────────────────────────────────
Quit
```

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Studio Display(s) connected via Thunderbolt/USB-C
- Xcode Command Line Tools (`xcode-select --install`)

## Installation

### Build from source

```bash
git clone https://github.com/gt1996md/StudioDisplayControl.git
cd StudioDisplayControl
chmod +x build_app.sh
./build_app.sh
```

### Install

```bash
cp -r StudioDisplayControl.app /Applications/
```

### First launch

1. **Open the app** — Right-click `StudioDisplayControl.app` in Applications → Open → Open again (required for unsigned apps)
2. **Grant Accessibility permission** — System Settings → Privacy & Security → Accessibility → Add and enable Studio Display Control
3. **Relaunch the app** after granting permission

### Launch at login (optional)

System Settings → General → Login Items → Add `StudioDisplayControl`

## How It Works

- **Volume**: Uses CoreAudio APIs to directly control each Studio Display's audio device volume
- **Brightness**: Uses Apple's private `DisplayServices` framework to control display brightness
- **Key Interception**: Creates a CGEvent tap to intercept system-defined media key events (NX_SYSDEFINED) before macOS processes them

## Technical Details

The app is a single Swift file (~400 lines) with no external dependencies. It uses:

| Component | Framework | Purpose |
|-----------|-----------|---------|
| Audio control | CoreAudio | Get/set volume and mute state per audio device |
| Brightness control | DisplayServices (private) | Get/set brightness per display |
| Key interception | Carbon / Quartz Events | Intercept media keys via CGEvent tap |
| Menu bar UI | AppKit | NSStatusItem with sliders |
| Display detection | CoreGraphics | Enumerate displays, filter by Apple vendor ID |

## Known Limitations

- **Brightness control uses a private Apple framework** (`DisplayServices`). This could break in future macOS updates, though it has been stable for years.
- **No native macOS OSD** — The system volume/brightness overlay won't appear since the app intercepts the keys before macOS processes them.
- **Unsigned app** — You'll need to right-click → Open on first launch since the app isn't signed with an Apple Developer certificate.
- **Apple displays only** — Currently only works with Apple Studio Display / Pro Display XDR. Non-Apple displays would require DDC/CI support (contributions welcome!).

## Uninstall

1. Quit the app from the menu bar (click 🖥️ → Quit)
2. Delete from Applications: `rm -rf /Applications/StudioDisplayControl.app`
3. Remove from Login Items if added
4. Remove from Accessibility in Privacy & Security settings

## License

MIT License — see [LICENSE](LICENSE) for details.

## Contributing

Pull requests welcome! Some ideas:

- [ ] Native macOS OSD overlay when adjusting volume/brightness
- [ ] Individual per-display volume/brightness control
- [ ] Keyboard shortcut customization
- [ ] Support for non-Apple external displays (via DDC/CI)
- [ ] Sparkle auto-updater
