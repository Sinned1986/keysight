#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_playback.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

#include <algorithm>
#include <array>
#include <atomic>
#include <memory>
#include <mutex>

#define TSF_IMPLEMENTATION
#include "tsf.h"
#include "sf2_validation.hpp"

namespace godot {

class KeySightSynthStream : public AudioStream {
    GDCLASS(KeySightSynthStream, AudioStream)

    static constexpr int channels = 49;
    std::mutex mutex;
    std::unique_ptr<tsf, decltype(&tsf_close)> font{nullptr, tsf_close};
    float gain = 0.5f;

protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("load_soundfont", "path", "rate", "voices"), &KeySightSynthStream::load_soundfont);
        ClassDB::bind_method(D_METHOD("midi", "message", "channel", "first", "second"), &KeySightSynthStream::midi);
        ClassDB::bind_method(D_METHOD("silence", "first_channel", "past_last_channel"), &KeySightSynthStream::silence);
        ClassDB::bind_method(D_METHOD("set_gain", "value"), &KeySightSynthStream::set_gain);
        ClassDB::bind_method(D_METHOD("render_peak", "frames"), &KeySightSynthStream::render_peak);
        ClassDB::bind_method(D_METHOD("active_voices"), &KeySightSynthStream::active_voices);
    }

public:
    Ref<AudioStreamPlayback> _instantiate_playback() const override;
    bool _is_monophonic() const override { return true; }

    bool load_soundfont(const String &path, int rate, int voices) {
        std::unique_ptr<FILE, decltype(&fclose)> file(fopen(path.utf8().get_data(), "rb"), fclose);
        uint32_t samples = 0;
        if (!file || !keysight::validate_sf2(file.get(), samples)) {
            return false;
        }
        std::rewind(file.get());
        tsf_stream input{
            file.get(),
            [](void *handle, void *buffer, unsigned int size) -> int {
                return std::fread(buffer, 1, size, static_cast<FILE *>(handle)) == size;
            },
            [](void *handle, unsigned int size) -> int {
                return std::fseek(static_cast<FILE *>(handle), size, SEEK_CUR) == 0;
            },
        };
        decltype(font) candidate{tsf_load(&input), tsf_close};
        if (!candidate || tsf_get_presetcount(candidate.get()) < 1 ||
                !tsf_set_max_voices(candidate.get(), std::clamp(voices, 1, 256))) {
            return false;
        }
        bool playable = false;
        for (int i = 0; i < candidate->presetNum; ++i) {
            const auto &preset = candidate->presets[i];
            for (int j = 0; j < preset.regionNum; ++j) {
                const auto &region = preset.regions[j];
                // The renderer interpolates with the next PCM sample.
                if (region.offset >= region.end || region.end >= samples || !region.sample_rate ||
                        region.loop_start >= samples || region.loop_end >= samples) {
                    return false;
                }
                playable = true;
            }
        }
        if (!playable) {
            return false;
        }
        tsf_set_output(candidate.get(), TSF_STEREO_INTERLEAVED, std::clamp(rate, 8000, 192000), 0);
        const int piano = tsf_get_presetindex(candidate.get(), 0, 0);
        for (int channel = 0; channel < channels; ++channel) {
            if (!tsf_channel_set_presetindex(candidate.get(), channel, std::max(piano, 0))) {
                return false;
            }
        }
        {
            std::lock_guard lock(mutex);
            font.swap(candidate);
        }
        return true;
    }

    void midi(int message, int channel, int first, int second) {
        if (channel < 0 || channel >= channels) {
            return;
        }
        std::lock_guard lock(mutex);
        tsf *synth = font.get();
        if (!synth) {
            return;
        }
        const int data = std::clamp(first, 0, 127);
        switch (message) {
            case 8:
                tsf_channel_note_off(synth, channel, data);
                break;
            case 9:
                if (second > 0) {
                    tsf_channel_note_on(synth, channel, data, std::min(second, 127) / 127.0f);
                } else {
                    tsf_channel_note_off(synth, channel, data);
                }
                break;
            case 11:
                tsf_channel_midi_control(synth, channel, data, std::clamp(second, 0, 127));
                if (data == 121) {
                    tsf_channel_set_sustain(synth, channel, 0);
                    tsf_channel_set_pitchwheel(synth, channel, 8192);
                }
                break;
            case 12:
                tsf_channel_set_presetnumber(synth, channel, data, 0);
                break;
            case 14:
                tsf_channel_set_pitchwheel(synth, channel, std::clamp(first, 0, 16383));
                break;
        }
    }

    void silence(int first, int end) {
        std::lock_guard lock(mutex);
        if (!font) {
            return;
        }
        for (int channel = std::max(0, first); channel < std::min(end, channels); ++channel) {
            tsf_channel_sounds_off_all(font.get(), channel);
            tsf_channel_set_sustain(font.get(), channel, 0);
        }
    }

    void set_gain(float value) {
        std::lock_guard lock(mutex);
        gain = std::clamp(value, 0.0f, 1.0f);
    }

    void mix(AudioFrame *buffer, int frames) {
        std::unique_lock lock(mutex, std::try_to_lock);
        if (!lock || !font) {
            std::fill_n(buffer, frames, AudioFrame{});
            return;
        }
        std::array<float, 512> samples;
        for (int offset = 0; offset < frames;) {
            const int count = std::min(256, frames - offset);
            tsf_render_float(font.get(), samples.data(), count, 0);
            for (int i = 0; i < count; ++i) {
                buffer[offset + i] = {samples[2 * i] * gain, samples[2 * i + 1] * gain};
            }
            offset += count;
        }
    }

    float render_peak(int frames) {
        std::array<AudioFrame, 256> buffer;
        float peak = 0;
        for (int remaining = std::clamp(frames, 0, 480000); remaining > 0;) {
            const int count = std::min(remaining, 256);
            mix(buffer.data(), count);
            for (int i = 0; i < count; ++i) {
                peak = std::max({peak, std::abs(buffer[i].left), std::abs(buffer[i].right)});
            }
            remaining -= count;
        }
        return peak;
    }

    int active_voices() {
        std::lock_guard lock(mutex);
        return font ? tsf_active_voice_count(font.get()) : 0;
    }
};

class KeySightSynthPlayback : public AudioStreamPlayback {
    GDCLASS(KeySightSynthPlayback, AudioStreamPlayback)

    std::atomic<bool> playing{false};

protected:
    static void _bind_methods() {}

public:
    Ref<KeySightSynthStream> stream;

    void _start(double) override { playing = true; }
    void _stop() override { playing = false; }
    bool _is_playing() const override { return playing; }
    int32_t _get_loop_count() const override { return 0; }
    double _get_playback_position() const override { return 0; }
    int32_t _mix(AudioFrame *buffer, float, int32_t frames) override {
        if (!playing) {
            return 0;
        }
        stream->mix(buffer, frames);
        return frames;
    }
};

Ref<AudioStreamPlayback> KeySightSynthStream::_instantiate_playback() const {
    Ref<KeySightSynthPlayback> playback;
    playback.instantiate();
    playback->stream = Ref<KeySightSynthStream>(const_cast<KeySightSynthStream *>(this));
    return playback;
}

} // namespace godot

extern "C" GDExtensionBool GDE_EXPORT keysight_synth_init(
        GDExtensionInterfaceGetProcAddress get_proc, GDExtensionClassLibraryPtr library,
        GDExtensionInitialization *initialization) {
    godot::GDExtensionBinding::InitObject init(get_proc, library, initialization);
    init.register_initializer([](godot::ModuleInitializationLevel level) {
        if (level == godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
            godot::ClassDB::register_class<godot::KeySightSynthStream>();
            godot::ClassDB::register_internal_class<godot::KeySightSynthPlayback>();
        }
    });
    init.register_terminator([](godot::ModuleInitializationLevel) {});
    init.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
