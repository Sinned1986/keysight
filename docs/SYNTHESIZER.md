# Internal SoundFont synthesizer

KeySight can use external SF2 files for sound synthesis on Linux x86_64 and
Steam Frame ARM64. The **Audio** menu controls the synthesizer, SoundFont,
volume, polyphony, and individual audio sources. The new controls follow
Godot's language setting and are available in English, German, and Dutch.

## SoundFont setup and controls

Place an extracted `.sf2` file in one of these directories.

- `~/soundfonts/`
- `~/keysight/soundfonts/`
- `~/.local/share/KeySight/soundfonts/`
- `user://soundfonts/` in KeySight's Godot user data directory

Select **Rescan** in the Audio menu to refresh the list, then use **‹** and **›**
to choose a file. Enable **Internal synthesizer** and use **Test tone** to
check playback. The Yamaha-based **YDP Grand Piano** from FreePats is licensed
under CC BY 3.0. Follow the attribution instructions if you redistribute it.
KeySight ships with a small synthetic SF2 test fixture. Instrument SoundFonts
are supplied separately. [FreePats and license information](https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html)

The internal synthesizer is off on first launch. Once enabled, it plays live
MIDI by default, even when no lesson is loaded. You can enable lesson reference
notes and demo playback independently. The defaults are 50% volume, 128 voices,
and reverb and chorus off. KeySight saves changes in `user://audio.cfg` and
reloads the selected SoundFont when launched with the synthesizer enabled.
**Silence all** stops voices from every source. Turning off **Internal
synthesizer** unloads the SoundFont and saves that preference. Use
`--no-synth` to turn it off for the current launch only.

| Option | Effect for this launch |
| --- | --- |
| `--synth` / `--no-synth` | Enable or disable the internal synthesizer |
| `--soundfont /path/to/piano.sf2` | Override the selected file |
| `--gain 0.5` | Set linear volume between 0 and 1 |
| `--polyphony 128` | Set the voice limit between 1 and 256 |
| `--synth-selftest` | Run the audio self-test and exit |

## Architecture and library selection

`MidiMonitor` opens the RawMIDI input through Godot. Its existing signals drive
calibration, visualization, and scoring. The audio component receives the same
`InputEventMIDI` and passes it to the native extension, which loads SoundFonts
and synthesizes audio. Godot's existing RawMIDI input is sufficient, so the
synthesizer requires neither the ALSA sequencer at `/dev/snd/seq` nor its own
access to `/dev/snd/midiC*`. Godot's mixer handles output and provides optional
reverb and chorus through bus effects.

The extension uses **TinySoundFont 0.9**
(`a3621a19c6504885cd9583e6e26c35bc954fc8ec`, MIT) and statically links the
**godot-cpp** bindings from `godot-4.4-stable` (MIT). The build verifies both
sources against pinned SHA-256 checksums. The resulting GDExtension was
loaded successfully with Godot 4.7.2. [License notices](../step2-leren/addons/keysight_synth/LICENSES.txt)

| Library | Evaluation |
| --- | --- |
| Clef (MIT) | The MIDI file player supports Godot 4.6+, SF2, CC64, and configurable polyphony. Note On and Note Off are processed through an internal event list. ADSR and release transitions use scene processing and a pool of players. Live input would need an additional interface and its timing would still depend on scene processing. [Source](https://github.com/kenyonxu/clef/tree/main/addons/clef/player) |
| SoundFont Godot (MIT) | Native Godot extension for scheduled SF2 playback with its own scheduler, TinySoundFont, and a Vorbis decoder. An ARM64 Linux build and the required MIDI CC interface would need separate integration. [Source and license](https://github.com/amberwhitehead/soundfont-godot) |
| Godot MIDI Player (MIT) | The linked version targets Godot 3 and plays MIDI files. Clef's player builds on this project. [Source](https://github.com/arlez80/Godot-MIDI-Player) |
| TinySoundFont (MIT) | Native SF2 synthesis with a channel API, velocity, CC64, program changes, pitch bend, and preallocated voices. A single header whose ARM64 runtime dependencies are the system libc and libm. [Source](https://github.com/schellingb/TinySoundFont/tree/a3621a19c6504885cd9583e6e26c35bc954fc8ec) |
| FluidSynth (LGPL-2.1) | Embeddable C API with extensive SF2 and General MIDI support. The native library uses GLib, which adds dependencies to build and verify. [Source](https://github.com/FluidSynth/fluidsynth) |

Live MIDI uses 16 channels. Reference notes, demo playback, and the test tone
use dedicated synth channels and share the same voice limit. Layered SF2 sounds
can use multiple voices per note. Reference notes follow the lesson clock and
use the SoundFont's default preset. Lesson scoring continues to use its
existing inputs.

The SoundFont is read and validated in the background. Godot's mix callback
synthesizes audio without allocating buffers. If the callback encounters lock
contention, it outputs a silent block. The project requests 48 kHz and the
synth uses Godot's active mix rate. On Linux, KeySight detects a disconnected
MIDI device when its RawMIDI device node disappears, provided the process can
see the node. You can also stop all sounds manually.

## Building on Arch Linux

The development machine needs Godot 4.7.2 with matching export templates,
CMake, Python 3, GNU Make or Ninja, and a C++17 compiler. The first native build
downloads the two pinned dependencies. KeySight runs offline.

Run from the repository root.

```bash
cd step2-leren
./tools/build_synth.sh x86_64
mkdir -p build/pc-linux
godot --headless --xr-mode off --path . --export-release "PC Linux x86_64 (test)"
cp addons/keysight_synth/LICENSES.txt build/pc-linux/
./build/pc-linux/KeySight.x86_64 --xr-mode off --synth --soundfont "$HOME/soundfonts/piano.sf2"
```

To run the project through Godot with the same audio settings:

```bash
godot --path . --xr-mode off -- --synth --soundfont "$HOME/soundfonts/piano.sf2" --gain 0.5
```

### Cross-compiling for ARM64

The verified ARM64 build uses Bootlin AArch64 glibc stable 2024.05-1.
This avoids the glibc 2.43 requirement of the tested Arch cross-build.
The toolchain is needed on the development machine only.
[Bootlin toolchain archive](https://toolchains.bootlin.com/downloads/releases/toolchains/aarch64/tarballs/)

```bash
mkdir -p "$PWD/build/toolchains"
cd "$PWD/build/toolchains"
curl -fLO https://toolchains.bootlin.com/downloads/releases/toolchains/aarch64/tarballs/aarch64--glibc--stable-2024.05-1.tar.xz
printf '%s  %s\n' b0fad860eb94b503a56d66ca8b9ba06d2d4826943e37ebd1d7217423f6ea5bb2 aarch64--glibc--stable-2024.05-1.tar.xz | sha256sum -c -
tar -xf aarch64--glibc--stable-2024.05-1.tar.xz
./aarch64--glibc--stable-2024.05-1/relocate-sdk.sh
cd ../..
KEYSIGHT_AARCH64_CXX="$PWD/build/toolchains/aarch64--glibc--stable-2024.05-1/bin/aarch64-linux-g++" \
  ./tools/build_synth.sh aarch64
mkdir -p build/frame-arm64
godot --headless --xr-mode off --path . --export-release "Steam Frame Arm64"
cp addons/keysight_synth/LICENSES.txt build/frame-arm64/
file build/frame-arm64/{KeySight.arm64,libkeysight_synth.aarch64.so}
readelf -d build/frame-arm64/libkeysight_synth.aarch64.so
readelf -V build/frame-arm64/libkeysight_synth.aarch64.so
```

Run these commands from `step2-leren`. If your default cross-toolchain already
matches the target glibc version, use `./tools/build_synth.sh aarch64`.
Set `KEYSIGHT_BUILD_DIR` to a new build directory when switching toolchains.

### Deploying to Steam Frame

Copy all files from the export directory. The ARM64 executable contains the
PCK and Godot loads the ARM64 library alongside it. Replace `FRAME` with your
SSH host or `user@ip-address`. The SoundFont can stay in `~/soundfonts/`.

```bash
ssh FRAME 'mkdir -p ~/keysight-frame'
scp build/frame-arm64/{KeySight.arm64,libkeysight_synth.aarch64.so,LICENSES.txt} FRAME:~/keysight-frame/
ssh FRAME
cd ~/keysight-frame
chmod +x KeySight.arm64
./KeySight.arm64 --synth --soundfont "$HOME/soundfonts/piano.sf2"
```

To launch from Steam, point the shortcut to `KeySight.arm64` and set its
working directory to the copied directory. If you omit the command-line
options, KeySight uses the settings saved in the Audio menu.

## Tests and troubleshooting

```bash
godot --headless --xr-mode off --path . --import
godot --headless --xr-mode off --path . -- --selftest
godot --headless --xr-mode off --path . -- --synth-selftest
godot --headless --xr-mode off --path . -- --synth-selftest --soundfont "$HOME/soundfonts/piano.sf2"
godot --path . --xr-mode off -- --demo --song 3 --nowait
```

- **Library missing**. Build the library for the target architecture and copy
  the full export directory.
- **SoundFont missing or invalid**. Check the path and permissions and confirm
  that the `.sf2` file is extracted. The backend supports PCM SF2. SF3/Vorbis
  and the full SF2 modulation matrix are unsupported.
- **Test tone works but live MIDI is silent**. Check that Live MIDI is enabled
  and that KeySight's diagnostics list the MIDI input. Godot's Dummy audio
  driver skips MIDI input on Linux. Use a working PulseAudio or ALSA audio
  driver for physical MIDI devices.
- **Chords sound distorted**. Lower the master volume. Voice usage and peak
  levels depend on the SoundFont.

The project and synth self-tests passed with Godot 4.7.2. Both the x86_64 export
and the ARM64 export running under QEMU loaded and rendered the FreePats YDP
SoundFont. According to `readelf`, the ARM64 build requires symbols up to
glibc 2.38. The x86_64 export was built and tested on Arch Linux.

On the Ryzen 9 7950X3D, the x86_64 export took about 12 ms to render 48,000
frames with 89 initially active voices, including peak measurement. This
offline YDP SoundFont benchmark excludes input, buffering, and output latency.

On physical Steam Frame hardware, runtime and OpenXR compatibility, audio
output, the SL88 MK2 with sustain, MIDI device disconnects, and dropouts under
high voice counts still need testing. To measure Note On latency on the device,
capture the key trigger and the first audio signal together, for example using
a triggered recording setup. Callback or render time measures only part of
the end-to-end latency.
