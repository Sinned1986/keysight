# Hardware smoke test (before every release)

The automated self-test (`godot --headless --path step2-leren -- --selftest`) covers MIDI parsing,
calibration maths, scoring, notation and a regression test for the "piano unplugged" bug. It can't
cover real hardware, so run this checklist on a headset with a real USB-MIDI piano before pushing
a release. It takes about 10 minutes.

| # | Check | Expected |
|---|---|---|
| 1 | Start KeySight with the piano connected and switched on | Piano name in the diagnostics; no "MIDI-apparaat losgekoppeld" in the log |
| 2 | Leave the piano untouched for 2 minutes, then play | Notes register immediately: silence must never count as a disconnect |
| 3 | Hold a key, then release it | Key lights up and goes back; no keys stuck coloured |
| 4 | Play a full song in wait mode and in play-along mode | Hits, wrong and missed counts look plausible; results card appears |
| 5 | Sustain pedal and middle pedal | Sustain recorded; middle pedal starts/pauses |
| 6 | Calibrate (Kalibreren) with one controller, then with the other | Width close to your piano's real width (within ~2 %); no points at 0,0,0 in the log |
| 7 | Unplug the USB cable, wait 10 s, plug it back in | App keeps running; the log doesn't fill with ALSA errors; the device returns after a rescan |
| 8 | Check `[perf]` lines in the log | Average frame time at the target rate (13.9 ms at 72 Hz, 11.1 ms at 90 Hz) |
| 9 | Score view on Ode to Joy and one of your own songs | Readable at the music-desk position, page turns follow the cursor |

Write down the piano model, the result per row and the commit hash in the release notes.

## Why there is no automatic "unplugged" detection

A USB-MIDI keyboard is silent when nobody plays, so inferring a disconnect from silence (or from
polling a file) misfires on real hardware. An earlier build read `/proc/asound/cards` to guess
whether the piano was still there. Godot sees that file as empty, so every 3 seconds the app
closed MIDI and dropped notes. KeySight now only rescans while *no* device is connected, plus a
manual rescan. Real hotplug events (udev/ALSA sequencer announcements) would be the right signal,
but Godot doesn't expose them yet.
