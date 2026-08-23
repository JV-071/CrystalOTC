/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "soundmanager.h"
#include <AL/alext.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <nlohmann/json.hpp>
#include <sounds.pb.h>
#include <utility>

#include "soundbuffer.h"
#include "soundchannel.h"
#include "soundeffect.h"
#include "soundfile.h"
#include "soundsource.h"
#include "streamsoundsource.h"
#include "combinedsoundsource.h"
#include "client/game.h"
#include "client/gameconfig.h"
#include "framework/core/asyncdispatcher.h"
#include "framework/core/clock.h"
#include "framework/core/garbagecollection.h"
#include "framework/core/resourcemanager.h"
#include "framework/platform/platform.h"
#include "framework/util/stats.h"

using namespace otclient::protobuf;

using json = nlohmann::json;

// Following the operating system's default output needs two openal-soft
// extensions. Guard on the headers so a platform shipping an older OpenAL
// still builds - it just keeps the device it opened, as before.
#if defined(ALC_SOFT_system_events) && defined(ALC_SOFT_reopen_device)
#define SOUND_FOLLOW_DEFAULT_DEVICE
#endif

namespace
{
    // The official client keeps effect assets in stereo, preserves that stereo
    // image, and applies a linear distance fade instead of positional panning.
    // A sound reaches silence at 19 tiles. Using OpenAL positioning directly
    // cannot reproduce this: OpenAL deliberately ignores AL_POSITION for
    // stereo buffers.
    constexpr float POSITIONAL_EFFECT_MAX_DISTANCE_TILES = 19.0f;

    float positionalEffectGain(const Point& position)
    {
        const float spriteSize = std::max(1.0f, static_cast<float>(g_gameConfig.getSpriteSize()));
        const float distanceTiles = std::hypot(static_cast<float>(position.x), static_cast<float>(position.y)) / spriteSize;
        return std::clamp(1.0f - distanceTiles / POSITIONAL_EFFECT_MAX_DISTANCE_TILES, 0.0f, 1.0f);
    }

#ifdef SOUND_FOLLOW_DEFAULT_DEVICE
    LPALCREOPENDEVICESOFT pfnAlcReopenDevice{};
    LPALCEVENTISSUPPORTEDSOFT pfnAlcEventIsSupported{};
    LPALCEVENTCONTROLSOFT pfnAlcEventControl{};
    LPALCEVENTCALLBACKSOFT pfnAlcEventCallback{};

    // Raised from openal-soft's own event thread, which holds its event mutex
    // across the call, so the callback must not re-enter ALC. poll() consumes
    // the flag and does the reopen from the thread that owns the sources.
    std::atomic_bool g_defaultDeviceChanged{ false };

    void ALC_APIENTRY onAlcDeviceEvent(const ALCenum eventType, ALCenum, ALCdevice*, ALCsizei, const ALCchar*, void*) noexcept
    {
        if (eventType == ALC_EVENT_TYPE_DEFAULT_DEVICE_CHANGED_SOFT)
            g_defaultDeviceChanged.store(true, std::memory_order_relaxed);
    }
#endif
}

SoundManager g_sounds;

SoundManager::~SoundManager()
{
    stopSoundTrace();
}

void SoundManager::startSoundTrace(const std::string& path)
{
    if (path.empty())
        return;

    stopSoundTrace();

    try {
        const std::filesystem::path tracePath(path);
        if (tracePath.has_parent_path())
            std::filesystem::create_directories(tracePath.parent_path());

        m_soundTraceFile.open(tracePath, std::ios::out | std::ios::trunc);
    } catch (const std::exception& error) {
        g_logger.error("unable to create sound trace '{}': {}", path, error.what());
        return;
    }

    if (!m_soundTraceFile) {
        g_logger.error("unable to create sound trace '{}'", path);
        return;
    }

    m_soundTracePath = path;
    m_soundTraceStartMonoUs = static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
    m_soundTraceSequence.store(0, std::memory_order_relaxed);
    m_soundTraceDropped = 0;
    m_soundTraceStopping = false;
    m_soundTraceEnabled.store(true, std::memory_order_release);
    m_soundTraceThread = std::thread(&SoundManager::soundTraceWriterLoop, this);

    traceSoundEvent("session.start", json({
        { "producer", "CrystalOTC" },
        { "pid", g_platform.getProcessId() },
        { "trace_path", path },
        { "clock", "steady_clock+unix_epoch" },
    }).dump());
    g_logger.info("sound parity trace enabled: {}", path);
}

void SoundManager::stopSoundTrace()
{
    if (!m_soundTraceThread.joinable())
        return;

    traceSoundEvent("session.stop", json({ { "producer", "CrystalOTC" } }).dump());
    m_soundTraceEnabled.store(false, std::memory_order_release);
    {
        std::lock_guard lock(m_soundTraceMutex);
        m_soundTraceStopping = true;
    }
    m_soundTraceCondition.notify_one();
    m_soundTraceThread.join();
    m_soundTraceFile.flush();
    m_soundTraceFile.close();
}

void SoundManager::traceSoundEvent(const std::string_view event, const std::string& dataJson)
{
    if (!m_soundTraceEnabled.load(std::memory_order_acquire))
        return;

    const uint64_t monoUs = static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
    const uint64_t epochUs = static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count());
    const uint64_t sequence = m_soundTraceSequence.fetch_add(1, std::memory_order_relaxed);

    const std::string line = fmt::format(
        R"({{"schema":"crystal-sound-trace-v1","producer":"CrystalOTC","seq":{},"mono_us":{},"session_us":{},"epoch_us":{},"event":{},"data":{}}})",
        sequence, monoUs, monoUs - m_soundTraceStartMonoUs, epochUs, json(event).dump(), dataJson);

    {
        std::lock_guard lock(m_soundTraceMutex);
        static constexpr size_t MAX_QUEUED_EVENTS = 16384;
        if (m_soundTraceQueue.size() >= MAX_QUEUED_EVENTS) {
            m_soundTraceQueue.pop_front();
            ++m_soundTraceDropped;
        }
        m_soundTraceQueue.emplace_back(line);
    }
    m_soundTraceCondition.notify_one();
}

void SoundManager::soundTraceWriterLoop()
{
    std::deque<std::string> pending;
    for (;;) {
        uint64_t dropped = 0;
        {
            std::unique_lock lock(m_soundTraceMutex);
            m_soundTraceCondition.wait_for(lock, std::chrono::milliseconds(250), [this] {
                return m_soundTraceStopping || !m_soundTraceQueue.empty();
            });
            pending.swap(m_soundTraceQueue);
            dropped = std::exchange(m_soundTraceDropped, 0);
            if (m_soundTraceStopping && pending.empty() && dropped == 0)
                break;
        }

        if (dropped != 0) {
            const uint64_t epochUs = static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count());
            m_soundTraceFile << fmt::format(
                R"({{"schema":"crystal-sound-trace-v1","producer":"CrystalOTC","epoch_us":{},"event":"trace.dropped","data":{{"count":{}}}}})",
                epochUs, dropped) << '\n';
        }
        for (const auto& line : pending)
            m_soundTraceFile << line << '\n';
        pending.clear();
        m_soundTraceFile.flush();
    }
}

void SoundManager::tracePacketSoundEffect(const uint32_t effectId, const uint8_t source,
                                          const uint16_t worldX, const uint16_t worldY, const uint8_t worldZ,
                                          const Point& relativePosition, const bool secondary)
{
    traceSoundEvent("packet.sound_effect", json({
        { "effect_id", effectId },
        { "source", source },
        { "secondary", secondary },
        { "world", { { "x", worldX }, { "y", worldY }, { "z", worldZ } } },
        { "relative_px", { { "x", relativePosition.x }, { "y", relativePosition.y } } },
    }).dump());
}

void SoundManager::tracePacketAnthem(const uint8_t type, const uint16_t id)
{
    traceSoundEvent("packet.anthem", json({
        { "type", type },
        { "kind", type == 0 ? "ambience" : type == 1 ? "music" : "unknown" },
        { "id", id },
    }).dump());
}

void SoundManager::init()
{
    if (const char* tracePath = std::getenv("CRYSTALOTC_SOUND_TRACE"); tracePath && *tracePath)
        startSoundTrace(tracePath);

#ifdef ANDROID
    // The alcOpenDevice call needs to be executed on Android main thread
    g_androidManager.attachToAppMainThread();
#endif

    m_device = alcOpenDevice(nullptr);
    if (!m_device) {
        g_logger.error("unable to open audio device");
        return;
    }

    m_context = alcCreateContext(m_device, nullptr);
    if (!m_context) {
        g_logger.error(fmt::format("unable to create audio context: {}", alcGetString(m_device, alcGetError(m_device))));
        return;
    }

    if (alcMakeContextCurrent(m_context) != ALC_TRUE) {
        g_logger.error(fmt::format("unable to make context current: {}", alcGetString(m_device, alcGetError(m_device))));
    }

    subscribeDeviceEvents();
}

void SoundManager::subscribeDeviceEvents()
{
#ifdef SOUND_FOLLOW_DEFAULT_DEVICE
    if (!m_device || !alcIsExtensionPresent(m_device, "ALC_SOFT_reopen_device") ||
        !alcIsExtensionPresent(m_device, "ALC_SOFT_system_events"))
        return;

    pfnAlcReopenDevice = reinterpret_cast<LPALCREOPENDEVICESOFT>(alcGetProcAddress(m_device, "alcReopenDeviceSOFT"));
    pfnAlcEventIsSupported = reinterpret_cast<LPALCEVENTISSUPPORTEDSOFT>(alcGetProcAddress(m_device, "alcEventIsSupportedSOFT"));
    pfnAlcEventControl = reinterpret_cast<LPALCEVENTCONTROLSOFT>(alcGetProcAddress(m_device, "alcEventControlSOFT"));
    pfnAlcEventCallback = reinterpret_cast<LPALCEVENTCALLBACKSOFT>(alcGetProcAddress(m_device, "alcEventCallbackSOFT"));
    alcGetError(m_device);

    // alcEventControlSOFT answers ALC_TRUE for event types the backend never
    // emits, so ask what it really supports rather than trusting that return.
    if (!pfnAlcReopenDevice || !pfnAlcEventIsSupported || !pfnAlcEventControl || !pfnAlcEventCallback ||
        pfnAlcEventIsSupported(ALC_EVENT_TYPE_DEFAULT_DEVICE_CHANGED_SOFT, ALC_PLAYBACK_DEVICE_SOFT) != ALC_EVENT_SUPPORTED_SOFT) {
        pfnAlcReopenDevice = nullptr;
        return;
    }

    constexpr ALCenum event = ALC_EVENT_TYPE_DEFAULT_DEVICE_CHANGED_SOFT;
    pfnAlcEventCallback(&onAlcDeviceEvent, nullptr);
    pfnAlcEventControl(1, &event, ALC_TRUE);
#endif
}

void SoundManager::unsubscribeDeviceEvents()
{
#ifdef SOUND_FOLLOW_DEFAULT_DEVICE
    if (pfnAlcEventControl && pfnAlcEventCallback) {
        constexpr ALCenum event = ALC_EVENT_TYPE_DEFAULT_DEVICE_CHANGED_SOFT;
        pfnAlcEventControl(1, &event, ALC_FALSE);
        pfnAlcEventCallback(nullptr, nullptr);
    }

    pfnAlcReopenDevice = nullptr;
    g_defaultDeviceChanged.store(false, std::memory_order_relaxed);
#endif
}

// The audio backend binds one physical output when the device is opened and
// keeps it for good, so plugging in headphones mid-session leaves the game
// playing out of the speakers everything else just left. Reopening moves it:
// the ALCdevice, the context and every source and buffer name survive, so
// whatever is playing simply continues on the new output.
void SoundManager::followDefaultDevice()
{
#ifdef SOUND_FOLLOW_DEFAULT_DEVICE
    if (!pfnAlcReopenDevice || !m_device)
        return;

    if (!g_defaultDeviceChanged.exchange(false, std::memory_order_relaxed))
        return;

    if (pfnAlcReopenDevice(m_device, nullptr, nullptr) == ALC_FALSE)
        g_logger.error("unable to move audio to the new default device: {}", alcGetString(m_device, alcGetError(m_device)));
#endif
}

void SoundManager::terminate()
{
    ensureContext();

    for (auto& streamFile : m_streamFiles) {
        auto& future = streamFile.second;
        future.wait();
    }
    m_streamFiles.clear();

    m_sources.clear();
    m_buffers.clear();
    m_channels.clear();

    m_audioEnabled = false;

    unsubscribeDeviceEvents();

    alcMakeContextCurrent(nullptr);

    if (m_context) {
        alcDestroyContext(m_context);
        m_context = nullptr;
    }

    if (m_device) {
        alcCloseDevice(m_device);
        m_device = nullptr;
    }

    stopSoundTrace();
}

void SoundManager::poll()
{
    AUTO_STAT(STATS_MAIN, "PollSounds");
    static ticks_t lastUpdate = 0;
    static uint_fast8_t soundsErased = 0;

    const ticks_t now = g_clock.millis();

    if (now - lastUpdate < POLL_DELAY)
        return;

    lastUpdate = now;

    ensureContext();
    followDefaultDevice();

    for (auto it = m_streamFiles.begin(); it != m_streamFiles.end();) {
        const auto& source = it->first;
        const auto& future = it->second;

        if (future.wait_for(std::chrono::seconds(0)) == std::future_status::ready) {
            const auto& sound = future.get();
            if (sound)
                source->setSoundFile(sound);
            else
                source->stop();

            it = m_streamFiles.erase(it);
        } else {
            ++it;
        }
    }

    for (auto it = m_sources.begin(); it != m_sources.end();) {
        const auto& source = *it;

        source->update();

        if (!source->isPlaying()) {
            traceSoundEvent("source.end", json({
                { "file", source->getName() },
                { "looping", source->isLooping() },
            }).dump());
            ++soundsErased;
            it = m_sources.erase(it);
        } else
            ++it;
    }

    for (const auto& it : m_channels) {
        it.second->update();
    }

    updateAmbientDelayedEffects();

    if (m_context) {
        alcProcessContext(m_context);
    }

    // temp fix for memory leak
    if (soundsErased > 25) {
        soundsErased = 0;
        GarbageCollection::lua();
    }
}

void SoundManager::setAudioEnabled(const bool enable)
{
    if (m_audioEnabled == enable)
        return;

    m_audioEnabled = enable;
    if (!enable) {
        ensureContext();
        for (const auto& source : m_sources) {
            source->stop();
        }
    }
}

void SoundManager::preload(std::string filename)
{
    filename = resolveSoundFile(filename);

    const auto it = m_buffers.find(filename);
    if (it != m_buffers.end())
        return;

    ensureContext();
    const auto& soundFile = SoundFile::loadSoundFile(filename);

    // only keep small files
    if (!soundFile || soundFile->getSize() > MAX_CACHE_SIZE)
        return;

    const auto& buffer = std::make_shared<SoundBuffer>();
    if (buffer->fillBuffer(soundFile))
        m_buffers[filename] = buffer;
}

SoundSourcePtr SoundManager::play(const std::string& fn, const float fadetime, const float gain, const float pitch)
{
    if (!m_audioEnabled)
        return nullptr;

    ensureContext();

    // Enforce the source limit before creating new ones. Whatever the channels
    // are playing is exempt: music and ambience are long-lived, so they are
    // always the oldest entries and a plain front-eviction would silence them
    // the moment enough effects are in flight. Testing the channels rather than
    // isLooping() matters because a one-shot effect can be looping too.
    const auto ownedByChannel = [this](const SoundSourcePtr& source) {
        for (const auto& [id, channel] : m_channels) {
            if (channel && channel->m_currentSource == source)
                return true;
        }
        return false;
    };

    // Raised from 16 when item ambients arrived: the exempt set used to be
    // music and ambience alone, and can now be nine or more, which would have
    // left effects fighting over the remainder.
    static constexpr size_t MAX_SOURCES = 24;
    while (m_sources.size() >= MAX_SOURCES) {
        auto it = m_sources.begin();
        while (it != m_sources.end() && ownedByChannel(*it))
            ++it;

        if (it == m_sources.end())
            break; // every live source belongs to a channel; let this one through

        (*it)->stop();
        m_sources.erase(it);
    }

    const std::string& filename = resolveSoundFile(fn);
    const auto& soundSource = createSoundSource(filename);
    if (!soundSource) {
        g_logger.error("unable to play '{}'", filename);
        return nullptr;
    }

    soundSource->setName(filename);
    soundSource->setRelative(true);
    soundSource->setGain(gain);
    soundSource->setPitch(pitch);

    if (fadetime > 0)
        soundSource->setFading(StreamSoundSource::FadingOn, fadetime);

    soundSource->play();

    m_sources.emplace_back(soundSource);

    traceSoundEvent("source.start", json({
        { "file", filename },
        { "fade_seconds", fadetime },
        { "gain", gain },
        { "pitch", pitch },
    }).dump());

    return soundSource;
}

SoundChannelPtr SoundManager::getChannel(int channel)
{
    ensureContext();
    if (!m_channels[channel])
        m_channels[channel] = std::make_shared<SoundChannel>(channel);
    return m_channels[channel];
}

void SoundManager::setClientSoundVolume(const int channel, const float volume)
{
    getChannel(channel)->setGain(std::clamp<float>(volume, 0.f, 1.f));
}

void SoundManager::setMasterVolume(const float volume)
{
    ensureContext();
    alListenerf(AL_GAIN, std::clamp<float>(volume, 0.f, 1.f));
}

void SoundManager::stopAll()
{
    ensureContext();

    for (auto& streamFile : m_streamFiles) {
        auto& future = streamFile.second;
        if (future.wait_for(std::chrono::seconds(0)) == std::future_status::ready)
            future.get();
    }
    m_streamFiles.clear();

    for (const auto& source : m_sources) {
        source->stop();
    }
    m_sources.clear();

    for (const auto& it : m_channels) {
        it.second->stop();
    }

    m_currentMusicId = 0;
    m_currentAmbienceId = 0;
    m_ambientDelayedEffects.clear();
    stopItemAmbients();
}

SoundSourcePtr SoundManager::createSoundSource(const std::string& name)
{
    SoundSourcePtr source;

    try {
        const std::string& filename = resolveSoundFile(name);
        const auto it = m_buffers.find(filename);
        if (it != m_buffers.end()) {
            source = std::make_shared<SoundSource>();
            if (source->m_sourceId == 0) {
                return nullptr; // OpenAL source creation failed
            }
            source->setBuffer(it->second);
        } else {
#if defined __linux && !defined OPENGL_ES
            // due to OpenAL implementation bug, stereo buffers are always downmixed to mono on linux systems
            // this is hack to work around the issue
            // solution taken from http://opensource.creative.com/pipermail/openal/2007-April/010355.html
            const auto& combinedSource = std::make_shared<CombinedSoundSource>();
            StreamSoundSourcePtr streamSource;

            streamSource = std::make_shared<StreamSoundSource>();
            if (streamSource->m_sourceId == 0) {
                return nullptr;
            }
            streamSource->downMix(StreamSoundSource::DownMixLeft);
            streamSource->setRelative(true);
            streamSource->setPosition(Point(-128, 0));
            combinedSource->addSource(streamSource);
            m_streamFiles[streamSource] = g_asyncDispatcher.submit_task([=]() -> SoundFilePtr {
                stdext::timer a;
                try {
                    return SoundFile::loadSoundFile(filename);
                } catch (std::exception& e) {
                    g_logger.error(e.what());
                    return nullptr;
                }
            });

            streamSource = std::make_shared<StreamSoundSource>();
            if (streamSource->m_sourceId == 0) {
                return nullptr;
            }
            streamSource->downMix(StreamSoundSource::DownMixRight);
            streamSource->setRelative(true);
            streamSource->setPosition(Point(128, 0));
            combinedSource->addSource(streamSource);
            m_streamFiles[streamSource] = g_asyncDispatcher.submit_task([=]() -> SoundFilePtr {
                try {
                    return SoundFile::loadSoundFile(filename);
                } catch (std::exception& e) {
                    g_logger.error(e.what());
                    return nullptr;
                }
            });

            source = combinedSource;
#else
            const auto& streamSource = std::make_shared<StreamSoundSource>();
            if (streamSource->m_sourceId == 0) {
                return nullptr;
            }
            m_streamFiles[streamSource] = g_asyncDispatcher.submit_task([=]() -> SoundFilePtr {
                try {
                    return SoundFile::loadSoundFile(filename);
                } catch (std::exception& e) {
                    g_logger.error(e.what());
                    return nullptr;
                }
            });
            source = streamSource;
#endif
        }
    } catch (std::exception& e) {
        g_logger.error("failed to load sound source: '{}'", e.what());
        return nullptr;
    }

    return source;
}

std::string SoundManager::resolveSoundFile(const std::string& file)
{
    const auto it = m_resolvedFiles.find(file);
    if (it != m_resolvedFiles.end())
        return it->second;

    std::string _file = g_resources.guessFilePath(file, "ogg");
    _file = g_resources.resolvePath(_file);
    m_resolvedFiles[file] = _file;
    return _file;
}

void SoundManager::ensureContext() const
{
    if (m_context)
        alcMakeContextCurrent(m_context);
}

void SoundManager::setPosition(const Point& pos)
{
    alListener3f(AL_POSITION, pos.x, pos.y, 0);
}

SoundEffectPtr SoundManager::createSoundEffect()
{
    auto soundEffect = std::make_shared<SoundEffect>(m_device);
    return soundEffect;
}

bool SoundManager::isEaxEnabled()
{
    if (alGetEnumValue("AL_EFFECT_EAXREVERB") != 0) {
        return true;
    }
    return false;
}

using ProtobufSoundFiles = google::protobuf::RepeatedPtrField<sounds::Sound>;
using ProtobufSoundEffects = google::protobuf::RepeatedPtrField<sounds::NumericSoundEffect>;
using ProtobufLocationAmbiences = google::protobuf::RepeatedPtrField<sounds::AmbienceStream>;
using ProtobufItemAmbiences = google::protobuf::RepeatedPtrField<sounds::AmbienceObjectStream>;
using ProtobufMusicTracks = google::protobuf::RepeatedPtrField<sounds::MusicTemplate>;

bool SoundManager::loadFromProtobuf(const std::string& directory, const std::string& fileName)
{
    /*
        * file structure
        <struct> Sounds
        |
        |
        | * audio file id -> audio file name (ogg)
        |-+- <vector> (Sound) sound
        | |----> (u32) id
        | |----> (string) filename (sound-abcd.ogg)
        | |----> (string) original_filename (unused)
        | |----> (bool) is_stream
        |
        |
        | * sound effect
        |-+- <vector> (NumericSoundEffect) numeric_sound_effect
        | |----> (u32) id (the id you request in sound effect packet)
        | |----> (enum - ENumericSoundType) numeric_sound_type
        | |-+--> (MinMaxFloat) random_pitch
        | | |------> (float) min
        | | |------> (float) max
        | |
        | |-+--> (MinMaxFloat) random_volume
        | | |------> (float) min
        | | |------> (float) max
        | |
        | |-+--> (SimpleSoundEffect) simple_sound_effect
        | | |------> (u32) sound_id (audio file id)
        | |
        | |-+--> (RandomSoundEffect) random_sound_effect
        |   |------> <vector> (u32) random_sound_id (audio file id)
        |
        |
        | * ambient sound for location (needs to be triggered with a packet)
        |-+- <vector> (AmbienceStream) ambience_stream
        | |----> (u32) id
        | |----> (u32) looping_sound_id (audio file id)
        | |-+--> <vector> (DelayedSoundEffect) delayed_effects
        |   |------> (u32) numeric_sound_effect_id (sound effect id)
        |   |------> (u32) delay_seconds
        |
        |
        | * sound of items placed on the map
        |-+- <vector> (AmbienceObjectStream) ambience_object_stream
        | |----> (u32) id (ID OF THIS EFFECT, NOT ITEM ID!)
        | |----> <vector> (u32) counted_appearance_types (ITEM CLIENT IDS that will have this sound, eg. waterfall or campfire)
        | |-+--> <vector> (AppearanceTypesCountSoundEffect) sound_effects
        | | |------> (u32) count (how many on the screen are required to trigger, eg. 3 are required for the swamp tiles to play sound)
        | | |------> (u32) looping_sound_id (audio file id)
        | |----> (u32) max_sound_distance (how far can it be heard)
        |
        |
        | * music for location (needs to be triggered with a packet)
        |-+- <vector> (MusicTemplate) music_template
          |----> (u32) id
          |----> (u32) sound_id (audio file id)
          |----> (enum - EMusicType) music_type
    */

    // create the sound bank from protobuf file
    try {
        std::stringstream fileInputStream;
        g_resources.readFileStream(g_resources.resolvePath(fmt::format("{}{}", directory, fileName)), fileInputStream);

        // read the soundbank
        auto protobufSounds = sounds::Sounds();
        if (!protobufSounds.ParseFromIstream(&fileInputStream)) {
            throw stdext::exception("Couldn't parse appearances lib.");
        }

        // deserialize audio files
        for (const auto& protobufAudioFile : protobufSounds.sound()) {
            m_clientSoundFiles[protobufAudioFile.id()] = ClientSoundFile{
                protobufAudioFile.filename(),
                protobufAudioFile.is_stream()
            };
        }

        // deserialize sound effects
        for (const auto& protobufSoundEffect : protobufSounds.numeric_sound_effect()) {
            const auto& pitch = protobufSoundEffect.random_pitch();
            const auto& volume = protobufSoundEffect.random_volume();
            std::vector<uint32_t> randomSounds = {};
            if (protobufSoundEffect.has_random_sound_effect()) {
                for (const uint32_t& audioFileId : protobufSoundEffect.random_sound_effect().random_sound_id()) {
                    randomSounds.push_back(audioFileId);
                }
            }

            uint32_t effectId = protobufSoundEffect.id();
            m_clientSoundEffects.emplace(effectId, ClientSoundEffect{
                effectId,
                static_cast<ClientSoundType>(protobufSoundEffect.numeric_sound_type()),
                pitch.min_value(),
                pitch.max_value(),
                volume.min_value(),
                volume.max_value(),
                protobufSoundEffect.has_simple_sound_effect() ? protobufSoundEffect.simple_sound_effect().sound_id() : 0,
                std::move(randomSounds)
            });
        }

        // deserialize location ambients
        for (const auto& protobufLocationAmbient : protobufSounds.ambience_stream()) {
            uint32_t effectId = protobufLocationAmbient.id();
            DelayedSoundEffects effects = {};
            for (const auto& delayedEffect : protobufLocationAmbient.delayed_effects()) {
                effects.push_back({ delayedEffect.numeric_sound_effect_id(), delayedEffect.delay_seconds() });
            }

            m_clientAmbientEffects.emplace(effectId, ClientLocationAmbient{
                effectId,
                protobufLocationAmbient.looping_sound_id(),
                std::move(effects)
            });
        }

        // deserialize item ambients
        for (const auto& protobufItemAmbient : protobufSounds.ambience_object_stream()) {
            std::vector<uint32_t> itemClientIds = {};
            for (const auto& itemId : protobufItemAmbient.counted_appearance_types()) {
                itemClientIds.push_back(itemId);
            }

            ItemCountSoundEffects soundEffects = {};
            for (const auto& soundEffect : protobufItemAmbient.sound_effects()) {
                soundEffects.push_back({ soundEffect.count(), soundEffect.looping_sound_id() });
            }

            // the bank stores these unordered; selection wants the highest
            // threshold the count reaches
            std::sort(soundEffects.begin(), soundEffects.end(),
                      [](const ItemCountSoundEffect& a, const ItemCountSoundEffect& b) { return a.count < b.count; });

            uint32_t effectId = protobufItemAmbient.id();
            m_clientItemAmbientEffects.emplace(effectId, ClientItemAmbient{
                effectId,
                std::move(itemClientIds),
                std::move(soundEffects),
                protobufItemAmbient.max_sound_distance()
            });
        }

        // deserialize music
        for (const auto& protobufMusicTemplate : protobufSounds.music_template()) {
            uint32_t effectId = protobufMusicTemplate.id();
            m_clientMusic.emplace(effectId, ClientMusic{
                effectId,
                protobufMusicTemplate.sound_id(),
                static_cast<ClientMusicType>(protobufMusicTemplate.music_type())
            });
        }

        return true;
    } catch (const std::exception& e) {
        g_logger.error("Failed to load soundbank '{}': {}", fileName, e.what());
        return false;
    }
}

bool SoundManager::loadClientFiles(const std::string& directory)
{
    // Cleared up front so a failed or partial load cannot leave the previous
    // soundbank's entries behind, and so the m_soundDirectory.empty() guards in
    // the play functions actually fire - they are the only thing standing
    // between a broken soundbank and every effect silently missing its lookup.
    m_soundDirectory.clear();
    m_currentMusicId = 0;
    m_currentAmbienceId = 0;
    m_ambientDelayedEffects.clear();
    stopItemAmbients();
    m_itemAmbientQueries.clear();
    m_itemAmbientEffectIds.clear();
    m_clientSoundFiles.clear();
    m_clientSoundEffects.clear();
    m_clientAmbientEffects.clear();
    m_clientItemAmbientEffects.clear();
    m_clientMusic.clear();

    // find catalog from json file
    try {
        bool loaded = false;
        json document = json::parse(g_resources.readFileContents(g_resources.resolvePath(g_resources.guessFilePath(directory + "catalog-sound", "json"))));
        for (const auto& obj : document) {
            const auto& type = obj["type"];
            if (type == "sounds") {
                // dat file encoded with protobuf
                loaded = loadFromProtobuf(directory, obj["file"]) || loaded;
            }
        }

        if (loaded) {
            m_soundDirectory = directory;
            buildItemAmbientQueries();
        }
        else
            g_logger.warning("no soundbank was loaded from '{}': the client has no effects, ambience or music", directory);

        return loaded;
    } catch (const std::exception& e) {
        if (g_game.getClientVersion() >= 1300) {
            g_logger.warning("Failed to load '{}' (Sounds): {}", directory, e.what());
        }

        return false;
    }
}

std::string SoundManager::getAudioFileNameById(int32_t audioFileId)
{
    if (m_clientSoundFiles.contains(audioFileId)) {
        return m_clientSoundFiles[audioFileId].filename;
    }

    return "";
}

namespace
{
    // The option checkboxes an effect answers to, from
    // modules/client_options/data_options.lua. Spells and weapons carry a
    // grouping box ("Spells") plus a specific one ("Attack"), so both are
    // returned and both have to be ticked.
    //
    // Chat messages answer to "consoleMessages" here and no further: the sound
    // packet names no chat channel, so this cannot tell a guild message from a
    // private one. The Console Messages sub-options are applied by
    // game_console instead, which knows the channel and plays the effect
    // itself - so this box is the parent of that decision, not a replacement.
    struct SoundFilterCategories
    {
        std::string_view group;
        std::string_view specific;
    };

    SoundFilterCategories soundFilterCategories(const ClientSoundType type, const uint8_t source)
    {
        const bool own = source == SOUND_SOURCE_OWN;
        const bool otherPlayer = source == SOUND_SOURCE_OTHER_PLAYER;

        switch (type) {
            case NUMERIC_SOUND_TYPE_SPELL_ATTACK:
                if (own) return { "ownSpells", "ownAttack" };
                if (otherPlayer) return { "otherSpells", "otherAttack" };
                return { "attackAndSpells", {} };
            case NUMERIC_SOUND_TYPE_SPELL_HEALING:
                if (own) return { "ownSpells", "ownHealing" };
                if (otherPlayer) return { "otherSpells", "otherHealing" };
                return { "attackAndSpells", {} };
            case NUMERIC_SOUND_TYPE_SPELL_SUPPORT:
                if (own) return { "ownSpells", "ownSupport" };
                if (otherPlayer) return { "otherSpells", "otherSupport" };
                return { "attackAndSpells", {} };
            case NUMERIC_SOUND_TYPE_SPELL_GENERIC:
                if (own) return { "ownSpells", {} };
                if (otherPlayer) return { "otherSpells", {} };
                return { "attackAndSpells", {} };
            case NUMERIC_SOUND_TYPE_WEAPON_ATTACK:
                if (own) return { "ownWeapons", {} };
                if (otherPlayer) return { "otherWeapons", {} };
                return { "attackAndSpells", {} };
            case NUMERIC_SOUND_TYPE_CREATURE_ATTACK: return { "attackAndSpells", {} };
            case NUMERIC_SOUND_TYPE_CREATURE_NOISE: return { "creatureNoises", {} };
            case NUMERIC_SOUND_TYPE_CREATURE_DEATH: return { "creatureDeath", {} };
            case NUMERIC_SOUND_TYPE_FOOD_AND_DRINK: return { "foodAndBeverages", {} };
            case NUMERIC_SOUND_TYPE_ITEM_MOVEMENT: return { "moveItem", {} };
            case NUMERIC_SOUND_TYPE_UI: return { "uiInteractions", {} };
            case NUMERIC_SOUND_TYPE_PARTY: return { "toggleParty", {} };
            case NUMERIC_SOUND_TYPE_VIP_LIST: return { "toggleVip", {} };
            case NUMERIC_SOUND_TYPE_WHISPER_WITHOUT_OPEN_CHAT:
            case NUMERIC_SOUND_TYPE_CHAT_MESSAGE: return { "consoleMessages", {} };
            case NUMERIC_SOUND_TYPE_RAID_ANNOUNCEMENT: return { "raidAnnouncements", {} };
            case NUMERIC_SOUND_TYPE_SERVER_MESSAGE: return { "systemAnnouncements", {} };
            default: return {};
        }
    }

    // The volume slider an effect belongs to. Battle sounds are split by who
    // made them, which is what the protocol's source byte is for.
    int soundEffectChannel(const ClientSoundType type, const uint8_t source)
    {
        switch (type) {
            case NUMERIC_SOUND_TYPE_UI:
            case NUMERIC_SOUND_TYPE_PARTY:
            case NUMERIC_SOUND_TYPE_VIP_LIST:
            case NUMERIC_SOUND_TYPE_WHISPER_WITHOUT_OPEN_CHAT:
            case NUMERIC_SOUND_TYPE_CHAT_MESSAGE:
            case NUMERIC_SOUND_TYPE_RAID_ANNOUNCEMENT:
            case NUMERIC_SOUND_TYPE_SERVER_MESSAGE:
                return SOUND_CHANNEL_UI;
            case NUMERIC_SOUND_TYPE_FOOD_AND_DRINK:
            case NUMERIC_SOUND_TYPE_ITEM_MOVEMENT:
                return SOUND_CHANNEL_ITEM;
            case NUMERIC_SOUND_TYPE_EVENT:
                return SOUND_CHANNEL_EVENT;
            case NUMERIC_SOUND_TYPE_CREATURE_NOISE:
            case NUMERIC_SOUND_TYPE_CREATURE_DEATH:
            case NUMERIC_SOUND_TYPE_CREATURE_ATTACK:
                return SOUND_CHANNEL_CREATURES;
            case NUMERIC_SOUND_TYPE_AMBIENCE_STREAM:
                return SOUND_CHANNEL_AMBIENT;
            case NUMERIC_SOUND_TYPE_SPELL_ATTACK:
            case NUMERIC_SOUND_TYPE_SPELL_HEALING:
            case NUMERIC_SOUND_TYPE_SPELL_SUPPORT:
            case NUMERIC_SOUND_TYPE_SPELL_GENERIC:
            case NUMERIC_SOUND_TYPE_WEAPON_ATTACK:
                if (source == SOUND_SOURCE_OWN)
                    return SOUND_CHANNEL_OWN_BATTLE;
                if (source == SOUND_SOURCE_OTHER_PLAYER)
                    return SOUND_CHANNEL_OTHER_PLAYERS;
                // anything else - a monster, a boss, or a sound with no actor
                // behind it such as an NPC's - answers to the Creatures slider,
                // matching the "attackAndSpells" box that filters it
                return SOUND_CHANNEL_CREATURES;
            default:
                return SOUND_CHANNEL_EFFECT;
        }
    }
}

bool SoundManager::isFilterEnabled(const std::string_view category) const
{
    if (category.empty())
        return true;

    const auto it = m_clientSoundFilters.find(std::string(category));
    return it == m_clientSoundFilters.end() || it->second;
}

void SoundManager::setClientSoundFilter(const std::string& category, const bool enabled)
{
    m_clientSoundFilters[category] = enabled;

    // Turning "Anthem" off silences the track already playing rather than
    // waiting for the next anthem packet. Guarded on a soundbank track really
    // being current: stopMusic() empties the music channel's queue, and at the
    // login screen that queue is holding the startup music.
    if (!enabled && category == "anthem" && m_currentMusicId != 0)
        stopMusic();
}

void SoundManager::playSoundEffect(const uint32_t effectId, const uint8_t source)
{
    playSoundEffectInternal(effectId, source, nullptr);
}

void SoundManager::playPositionedSoundEffect(const uint32_t effectId, const uint8_t source, const Point& position)
{
    playSoundEffectInternal(effectId, source, &position);
}

void SoundManager::playSoundEffectInternal(const uint32_t effectId, const uint8_t source, const Point* position)
{
    traceSoundEvent("effect.request", json({
        { "effect_id", effectId },
        { "source", source },
        { "positioned", position != nullptr },
        { "relative_px", position ? json({ { "x", position->x }, { "y", position->y } }) : json(nullptr) },
    }).dump());

    if (!isAudioEnabled() || m_soundDirectory.empty()) {
        traceSoundEvent("effect.drop", json({
            { "effect_id", effectId },
            { "reason", !isAudioEnabled() ? "audio_disabled" : "soundbank_not_loaded" },
        }).dump());
        return;
    }

    // limit new sound effects to 4 per poll cycle to prevent burst lag
    static ticks_t lastResetTime = 0;
    static int effectsThisCycle = 0;
    const ticks_t now = g_clock.millis();
    if (now - lastResetTime >= POLL_DELAY) {
        lastResetTime = now;
        effectsThisCycle = 0;
    }
    if (effectsThisCycle >= 4) {
        traceSoundEvent("effect.drop", json({
            { "effect_id", effectId },
            { "reason", "cycle_limit" },
            { "limit", 4 },
            { "window_ms", POLL_DELAY },
        }).dump());
        return;
    }
    ++effectsThisCycle;

    const auto it = m_clientSoundEffects.find(effectId);
    if (it == m_clientSoundEffects.end()) {
        traceSoundEvent("effect.drop", json({ { "effect_id", effectId }, { "reason", "unknown_effect" } }).dump());
        return;
    }

    const auto& effect = it->second;

    const auto categories = soundFilterCategories(effect.type, source);
    if (!isFilterEnabled(categories.group) || !isFilterEnabled(categories.specific)) {
        traceSoundEvent("effect.drop", json({
            { "effect_id", effectId },
            { "reason", "filtered" },
            { "group", std::string(categories.group) },
            { "specific", std::string(categories.specific) },
        }).dump());
        return;
    }

    // resolve the audio file id
    uint32_t audioFileId = effect.soundId;
    if (audioFileId == 0 && !effect.randomSoundId.empty()) {
        audioFileId = effect.randomSoundId[rand() % effect.randomSoundId.size()];
    }
    if (audioFileId == 0) {
        traceSoundEvent("effect.drop", json({ { "effect_id", effectId }, { "reason", "no_audio_file" } }).dump());
        return;
    }

    const auto fileIt = m_clientSoundFiles.find(audioFileId);
    if (fileIt == m_clientSoundFiles.end()) {
        traceSoundEvent("effect.drop", json({
            { "effect_id", effectId }, { "audio_file_id", audioFileId }, { "reason", "unknown_audio_file" },
        }).dump());
        return;
    }

    const std::string filename = m_soundDirectory + fileIt->second.filename;

    // throttle: skip if same sound was played less than 150ms ago
    auto& lastTime = m_lastPlayTime[filename];
    if (now - lastTime < 150) {
        traceSoundEvent("effect.drop", json({
            { "effect_id", effectId },
            { "audio_file_id", audioFileId },
            { "reason", "duplicate_throttle" },
            { "elapsed_ms", now - lastTime },
            { "threshold_ms", 150 },
        }).dump());
        return;
    }
    lastTime = now;

    // Cache short effects as buffers for efficient playback (and to avoid
    // creating 2 streaming sources per effect on Linux). Files the bank flags as
    // streams are skipped: preload would decode them in full only to discard
    // them for exceeding MAX_CACHE_SIZE.
    if (!fileIt->second.isStream)
        preload(filename);

    // randomize pitch and volume
    float pitch = 1.0f;
    if (effect.pitchMax > effect.pitchMin && effect.pitchMin > 0) {
        pitch = effect.pitchMin + static_cast<float>(rand()) / (static_cast<float>(RAND_MAX / (effect.pitchMax - effect.pitchMin)));
    } else if (effect.pitchMin > 0) {
        pitch = effect.pitchMin;
    }

    float gain = 1.0f;
    if (effect.volumeMax > effect.volumeMin && effect.volumeMin > 0) {
        gain = effect.volumeMin + static_cast<float>(rand()) / (static_cast<float>(RAND_MAX / (effect.volumeMax - effect.volumeMin)));
    } else if (effect.volumeMax > 0) {
        gain = effect.volumeMax;
    }

    // apply the volume of the slider this kind of effect belongs to
    const int effectChannel = soundEffectChannel(effect.type, source);
    if (const auto& channel = getChannel(effectChannel))
        gain *= channel->getGain();

    const float positionGain = position ? positionalEffectGain(*position) : 1.0f;
    gain *= positionGain;

    traceSoundEvent("effect.resolve", json({
        { "effect_id", effectId },
        { "audio_file_id", audioFileId },
        { "file", fileIt->second.filename },
        { "channel", effectChannel },
        { "gain", gain },
        { "position_gain", positionGain },
        { "pitch", pitch },
        { "source", source },
        { "positioned", position != nullptr },
        { "relative_px", position ? json({ { "x", position->x }, { "y", position->y } }) : json(nullptr) },
    }).dump());

    const auto& soundSource = play(filename, 0, gain, pitch);
    if (!soundSource) {
        traceSoundEvent("effect.drop", json({
            { "effect_id", effectId }, { "audio_file_id", audioFileId }, { "reason", "source_refused" },
        }).dump());
        return;
    }

    traceSoundEvent("effect.play", json({
        { "effect_id", effectId },
        { "audio_file_id", audioFileId },
        { "file", fileIt->second.filename },
        { "channel", effectChannel },
        { "gain", gain },
        { "position_gain", positionGain },
        { "pitch", pitch },
        { "positioned", position != nullptr },
    }).dump());
}

void SoundManager::playAmbienceSound(uint32_t ambienceId)
{
    traceSoundEvent("ambience.request", json({ { "ambience_id", ambienceId } }).dump());

    if (!isAudioEnabled() || m_soundDirectory.empty()) {
        traceSoundEvent("ambience.drop", json({
            { "ambience_id", ambienceId },
            { "reason", !isAudioEnabled() ? "audio_disabled" : "soundbank_not_loaded" },
        }).dump());
        return;
    }

    if (ambienceId == 0) {
        stopAmbienceSound();
        return;
    }

    if (ambienceId == m_currentAmbienceId) {
        traceSoundEvent("ambience.drop", json({ { "ambience_id", ambienceId }, { "reason", "already_current" } }).dump());
        return; // already playing; restarting would clip it and reset its timers
    }

    const auto it = m_clientAmbientEffects.find(ambienceId);
    if (it == m_clientAmbientEffects.end()) {
        traceSoundEvent("ambience.drop", json({ { "ambience_id", ambienceId }, { "reason", "unknown_ambience" } }).dump());
        g_logger.traceError("unknown client ambience id {}", ambienceId);
        return;
    }

    const auto& ambient = it->second;
    const uint32_t audioFileId = ambient.loopedAudioFileId;
    if (audioFileId == 0) {
        traceSoundEvent("ambience.drop", json({ { "ambience_id", ambienceId }, { "reason", "no_audio_file" } }).dump());
        return;
    }

    // if (m_soundDebug)
        // g_logger.info("[snd] AMBIENCE zone {} -> file {} (was zone {}) - channel {}, 3s crossfade",
                      // ambienceId, audioFileId, m_currentAmbienceId, SOUND_CHANNEL_AMBIENT);

    const auto fileIt = m_clientSoundFiles.find(audioFileId);
    if (fileIt == m_clientSoundFiles.end()) {
        traceSoundEvent("ambience.drop", json({
            { "ambience_id", ambienceId }, { "audio_file_id", audioFileId }, { "reason", "unknown_audio_file" },
        }).dump());
        g_logger.traceError("ambience id {} names audio file {}, which the soundbank does not have", ambienceId, audioFileId);
        return;
    }

    const std::string filename = m_soundDirectory + fileIt->second.filename;

    const auto& channel = getChannel(SOUND_CHANNEL_AMBIENT);
    if (!channel) {
        traceSoundEvent("ambience.drop", json({ { "ambience_id", ambienceId }, { "reason", "channel_unavailable" } }).dump());
        return;
    }

    channel->stop(3.0f);
    // A location ambience loops, and saying so lets the stream recover from an
    // underrun instead of leaving the channel wedged on a source that stopped
    // but still claims to be playing.
    channel->enqueue(filename, 3.0f, 1.0f, 1.0f, true);

    m_currentAmbienceId = ambienceId;

    traceSoundEvent("ambience.play", json({
        { "ambience_id", ambienceId },
        { "audio_file_id", audioFileId },
        { "file", fileIt->second.filename },
        { "channel", SOUND_CHANNEL_AMBIENT },
        { "fade_seconds", 3.0f },
        { "looping", true },
    }).dump());

    // Arm the effects that punctuate this ambience. delay_seconds is read as a
    // period rather than a one-shot deadline: streams pair several effects with
    // the same delay, which as deadlines would fire them all on the same tick
    // and then never again. For that same reason the first play of each is
    // placed at a random point inside its own window, so identical periods do
    // not stack up on one another.
    m_ambientDelayedEffects.clear();
    const ticks_t now = g_clock.millis();
    for (const auto& [delayedEffectId, delaySeconds] : ambient.delayedSoundEffects) {
        if (delaySeconds == 0)
            continue;

        const ticks_t period = static_cast<ticks_t>(delaySeconds) * 1000;
        const ticks_t nextPlay = now + (rand() % period);
        m_ambientDelayedEffects.emplace_back(delayedEffectId, period, nextPlay);
        traceSoundEvent("ambience.delayed_schedule", json({
            { "ambience_id", ambienceId },
            { "effect_id", delayedEffectId },
            { "period_ms", period },
            { "first_delay_ms", nextPlay - now },
        }).dump());
    }
}

void SoundManager::updateAmbientDelayedEffects()
{
    if (m_ambientDelayedEffects.empty())
        return;

    const ticks_t now = g_clock.millis();
    for (auto& pending : m_ambientDelayedEffects) {
        if (now < pending.nextPlay)
            continue;

        // These carry NUMERIC_SOUND_TYPE_AMBIENCE_STREAM, so playSoundEffect
        // routes them to the ambience channel and they follow its slider.
        traceSoundEvent("ambience.delayed_fire", json({
            { "ambience_id", m_currentAmbienceId }, { "effect_id", pending.effectId }, { "period_ms", pending.period },
        }).dump());
        playSoundEffect(pending.effectId);
        pending.nextPlay = now + pending.period;
    }
}

void SoundManager::buildItemAmbientQueries()
{
    m_itemAmbientQueries.clear();
    m_itemAmbientEffectIds.clear();
    m_itemAmbientSelected.clear();
    ++m_itemAmbientGeneration;

    for (const auto& [effectId, ambient] : m_clientItemAmbientEffects) {
        if (ambient.clientIds.empty() || ambient.itemCountSoundEffects.empty())
            continue;

        auto ids = ambient.clientIds;
        std::sort(ids.begin(), ids.end());
        ids.erase(std::unique(ids.begin(), ids.end()), ids.end());

        std::vector<uint16_t> clientIds;
        clientIds.reserve(ids.size());
        for (const uint32_t id : ids) {
            // map thing ids are 16 bit; anything wider could never match one
            if (id <= std::numeric_limits<uint16_t>::max())
                clientIds.push_back(static_cast<uint16_t>(id));
        }

        if (clientIds.empty())
            continue;

        // Resolve the bank's missing-radius case once, here, so nothing
        // downstream has to know that an absent field decodes as zero.
        const uint32_t radius = ambient.maxSoundDistance == 0
            ? ITEM_AMBIENT_DEFAULT_RADIUS : ambient.maxSoundDistance;

        m_itemAmbientQueries.emplace_back(std::move(clientIds), radius, effectId);
        m_itemAmbientEffectIds.push_back(effectId);
    }
}

void SoundManager::stopItemAmbients()
{
    // Stopped outright rather than faded: both bookkeeping containers are being
    // wiped, so a channel left fading would be handed out again from a pool
    // that has forgotten it is still busy, and the same loop could end up
    // audible twice at different positions.
    for (const auto& [audioFileId, voice] : m_itemAmbientVoices) {
        if (const auto& channel = getChannel(voice.channelId))
            channel->stop();
    }

    m_itemAmbientVoices.clear();
    m_freeItemAmbientChannels.clear();
    std::ranges::fill(m_itemAmbientSelected, ItemAmbientSelection{});
}

// Called by the client with one count per query, in query order: how many of
// that entry's items are currently on screen (and near enough, where the entry
// asks for that).
// ---------------------------------------------------------------------------
// Sound tracing
//
// The item ambient system decides what loops purely from a count of items the
// renderer can see, which makes "why is this playing" impossible to answer from
// the outside. These print the two halves of that: the bank's static answer to
// what an entry COULD play, and the live state of what it currently IS playing.
// ---------------------------------------------------------------------------

void SoundManager::setSoundDebug(const bool enable)
{
    m_soundDebug = enable;
    g_logger.info("[snd] tracing {}", enable ? "ON" : "off");

    if (enable)
        debugPlaying();
}

void SoundManager::debugSoundbank()
{
    g_logger.info("[snd] --- soundbank: {} item ambient entries ---", m_clientItemAmbientEffects.size());

    for (const auto& [effectId, ambient] : m_clientItemAmbientEffects) {
        std::string steps;
        for (const auto& [threshold, audioFileId] : ambient.itemCountSoundEffects) {
            const auto fileIt = m_clientSoundFiles.find(audioFileId);
            steps += fmt::format("  >={} -> file {} ({})", threshold, audioFileId,
                                    fileIt != m_clientSoundFiles.end() ? fileIt->second.filename : "MISSING");
        }

        g_logger.info("[snd] entry {}: radius={} items={}{}", effectId,
                      ambient.maxSoundDistance == 0 ? std::string("whole-screen") : fmt::format("{} tiles", ambient.maxSoundDistance),
                      ambient.clientIds.size(), steps);

        // the ids themselves, so an item looked up in game can be traced back
        std::string ids;
        for (const uint32_t id : ambient.clientIds)
            ids += fmt::format(" {}", id);
        g_logger.info("[snd]   counts item ids:{}", ids);
    }
}

void SoundManager::debugPlaying()
{
    g_logger.info("[snd] --- playing: music={} ambience={} | {} item ambient voice(s), {} channel(s) free ---",
                  m_currentMusicId, m_currentAmbienceId, m_itemAmbientVoices.size(), m_freeItemAmbientChannels.size());

    const ticks_t now = g_clock.millis();
    for (const auto& [audioFileId, voice] : m_itemAmbientVoices) {
        const auto& channel = getChannel(voice.channelId);
        const auto fileIt = m_clientSoundFiles.find(audioFileId);

        std::string state = "playing";
        if (voice.releasing)
            state = "FADING OUT";
        else if (voice.unwantedSince != 0)
            state = fmt::format("held {}ms/{}", now - voice.unwantedSince, static_cast<int>(ITEM_AMBIENT_HOLD_MS));

        g_logger.info("[snd]   file {} ch{} {} gain={:.2f} audible={} ({})",
                      audioFileId, voice.channelId, state,
                      channel ? channel->getGain() : 0.f,
                      channel && channel->isSounding() ? "yes" : "no",
                      fileIt != m_clientSoundFiles.end() ? fileIt->second.filename : "MISSING");
    }
}

void SoundManager::setItemAmbientCounts(const std::vector<uint16_t>& counts,
                                        const std::vector<uint16_t>& nearby)
{
    if (counts.size() != m_itemAmbientQueries.size() || nearby.size() != counts.size())
        return;

    if (!isAudioEnabled() || m_soundDirectory.empty()) {
        stopItemAmbients();
        return;
    }

    if (m_itemAmbientSelected.size() != counts.size())
        m_itemAmbientSelected.assign(counts.size(), ItemAmbientSelection{});

    if (isSoundTraceEnabled() && m_itemAmbientLastCounts.size() != counts.size())
        m_itemAmbientLastCounts.assign(counts.size(), 0);

    const ticks_t now = g_clock.millis();

    // Files dropped this scan because another step of the SAME entry took over.
    // Those are a replacement, not a departure, so they skip the hold and
    // crossfade against their successor instead of doubling it at full volume.
    std::vector<uint32_t> replaced;

    // Files whose items are still on screen, just out of reach. Those get the
    // long hold: the player is beside the thing, not away from it.
    std::vector<uint32_t> nearHold;

    // Which files should be looping now. Deduped by file: two effects can
    // select the same one, and starting it twice would just double its volume.
    std::vector<uint32_t> wanted;
    for (size_t i = 0; i < counts.size(); ++i) {
        const auto it = m_clientItemAmbientEffects.find(m_itemAmbientEffectIds[i]);
        if (it == m_clientItemAmbientEffects.end())
            continue;

        // highest threshold the count reaches; none qualifying means silence,
        // which is the normal state at zero and below an entry's first step
        auto& selection = m_itemAmbientSelected[i];

        uint32_t raw = 0;
        for (const auto& [threshold, loopingAudioFileId] : it->second.itemCountSoundEffects) {
            // A step that is already sounding keeps it for one item below the
            // threshold it needed to start, so the smallest wobble does not
            // even register as a candidate. An entry's first step is at one
            // item and has no room beneath it - the hold in the release pass
            // below is what covers going silent.
            const uint32_t needed = threshold > 1 && selection.audioFileId == loopingAudioFileId
                ? threshold - 1 : threshold;

            if (counts[i] >= needed)
                raw = loopingAudioFileId;
        }

        const uint32_t previousFile = selection.audioFileId;

        if (raw == selection.audioFileId) {
            selection.pending = 0; // the candidate withdrew; nothing to commit
            selection.pendingSince = 0;
        } else if (raw == 0 || selection.audioFileId == 0) {
            // Silence at either end: starting has to be immediate to feel like
            // a response to walking up to something, and stopping is the
            // release pass's job, which already holds and fades.
            selection.audioFileId = raw;
            selection.pending = 0;
            selection.pendingSince = 0;
        } else if (raw != selection.pending) {
            selection.pending = raw; // a new candidate; start its clock
            selection.pendingSince = now;
        } else if (now - selection.pendingSince >= ITEM_AMBIENT_STEP_MS) {
            replaced.push_back(selection.audioFileId);
            selection.audioFileId = raw;
            selection.pending = 0;
            selection.pendingSince = 0;
        }

        const uint32_t audioFileId = selection.audioFileId;

        // Silent because everything drifted out of the radius rather than off
        // the screen: work out what this query WOULD be sounding if the near
        // ones counted, and mark that file to be held rather than dropped.
        if (audioFileId == 0 && nearby[i] > 0) {
            const uint32_t asIfInRange = counts[i] + nearby[i];
            uint32_t wouldSelect = 0;
            for (const auto& [threshold, loopingAudioFileId] : it->second.itemCountSoundEffects) {
                if (asIfInRange >= threshold)
                    wouldSelect = loopingAudioFileId;
            }

            if (wouldSelect != 0 && std::ranges::find(nearHold, wouldSelect) == nearHold.end())
                nearHold.push_back(wouldSelect);
        }

        // Record changes only: the scan runs four times a second, and an event
        // per unchanged scan would hide the transitions the parity lab needs.
        if (isSoundTraceEnabled() && (m_itemAmbientLastCounts[i] != counts[i] || previousFile != audioFileId)) {
            traceSoundEvent("item_ambience.selection", json({
                { "effect_id", m_itemAmbientEffectIds[i] },
                { "count_before", m_itemAmbientLastCounts[i] },
                { "count", counts[i] },
                { "nearby", nearby[i] },
                { "audio_file_before", previousFile },
                { "audio_file_id", audioFileId },
                { "pending_audio_file_id", selection.pending },
            }).dump());
            m_itemAmbientLastCounts[i] = counts[i];
        }

        if (audioFileId != 0 && std::ranges::find(wanted, audioFileId) == wanted.end())
            wanted.push_back(audioFileId);
    }

    // Release pass. Nothing is torn down on the scan it stops being wanted:
    // the counts come from whatever the renderer had cached a moment ago, and a
    // teleport, a floor change or one step can drop a loop for a scan or two.
    // So it plays on for a hold - long while its items are merely out of range,
    // short once they are off screen entirely - then fades, and the channel is
    // only handed back once that fade has actually finished, because a channel
    // reused any earlier would hard-cut a source that is still audible.
    for (auto it = m_itemAmbientVoices.begin(); it != m_itemAmbientVoices.end();) {
        auto& voice = it->second;

        if (std::ranges::find(wanted, it->first) != wanted.end()) {
            voice.unwantedSince = 0; // wanted again; the hold starts over
            ++it;
            continue;
        }

        const auto& channel = getChannel(voice.channelId);

        // Superseded by another step of its own entry: fade it now, against
        // the successor's fade-in, rather than holding it at full volume while
        // the new one is already sounding.
        if (!voice.releasing && std::ranges::find(replaced, it->first) != replaced.end()) {
            voice.unwantedSince = now;
            voice.releasing = true;
            if (channel)
                channel->fadeOut(ITEM_AMBIENT_FADE);

            traceSoundEvent("item_ambience.swap", json({
                { "audio_file_id", it->first }, { "channel", voice.channelId }, { "fade_seconds", ITEM_AMBIENT_FADE },
            }).dump());

            // if (m_soundDebug)
                // g_logger.info("[snd]   SWAP  file {} ch{} - replaced by another step, crossfading out",
                              // it->first, voice.channelId);
        }

        // Re-read every scan rather than latched at departure, so a loop whose
        // items come back into view - without coming back into range - has its
        // hold extended instead of expiring underneath the player.
        const bool stillOnScreen = std::ranges::find(nearHold, it->first) != nearHold.end();
        const ticks_t hold = stillOnScreen ? ITEM_AMBIENT_HOLD_NEAR_MS : ITEM_AMBIENT_HOLD_MS;

        if (!voice.releasing && voice.unwantedSince == 0) {
            voice.unwantedSince = now;
            traceSoundEvent("item_ambience.hold", json({
                { "audio_file_id", it->first },
                { "channel", voice.channelId },
                { "still_on_screen", stillOnScreen },
                { "hold_ms", hold },
            }).dump());
            // if (m_soundDebug)
                // g_logger.info("[snd]   HOLD  file {} ch{} - {}, holding {}ms",
                              // it->first, voice.channelId,
                              // stillOnScreen ? "out of range but still on screen" : "gone from screen",
                              // static_cast<int>(hold));
        }

        if (!voice.releasing && now - voice.unwantedSince >= hold) {
            voice.releasing = true;
            if (channel)
                channel->fadeOut(ITEM_AMBIENT_FADE);

            traceSoundEvent("item_ambience.fade", json({
                { "audio_file_id", it->first },
                { "channel", voice.channelId },
                { "held_ms", now - voice.unwantedSince },
                { "fade_seconds", ITEM_AMBIENT_FADE },
            }).dump());

            // if (m_soundDebug)
                // g_logger.info("[snd]   FADE  file {} ch{} - {}ms hold expired, fading out over {:.2f}s",
                              // it->first, voice.channelId, static_cast<int>(hold), ITEM_AMBIENT_FADE);
        }

        if (voice.releasing && (!channel || !channel->isSounding())) {
            // The fade has finished. Clear the channel out before parking it,
            // so it carries no memory of the track: a remembered one would
            // start itself again if the channel were ever muted and unmuted.
            if (channel)
                channel->stop();

            traceSoundEvent("item_ambience.stop", json({
                { "audio_file_id", it->first }, { "channel", voice.channelId },
            }).dump());

            // if (m_soundDebug)
                // g_logger.info("[snd]   STOP  file {} ch{} - silent, channel released", it->first, voice.channelId);

            m_freeItemAmbientChannels.push_back(voice.channelId);
            it = m_itemAmbientVoices.erase(it);
        } else {
            ++it;
        }
    }

    // item ambients are ambience, so they track that slider
    const auto& ambientChannel = getChannel(SOUND_CHANNEL_AMBIENT);
    const float gain = ambientChannel ? ambientChannel->getGain() : 1.0f;

    for (const uint32_t audioFileId : wanted) {
        if (const auto existing = m_itemAmbientVoices.find(audioFileId); existing != m_itemAmbientVoices.end()) {
            const auto& channel = getChannel(existing->second.channelId);
            if (channel && channel->isSounding()) {
                // Wanted again while it was on its way out: ride the fade back
                // up from wherever it reached. play() here would stop a source
                // that is still audible and restart the file at sample 0.
                // Turned around before the gain is applied, because a source
                // heading for silence ignores a change to what it aims at.
                if (existing->second.releasing) {
                    channel->resumeFade(ITEM_AMBIENT_FADE);
                    existing->second.releasing = false;

                    traceSoundEvent("item_ambience.resume", json({
                        { "audio_file_id", audioFileId },
                        { "channel", existing->second.channelId },
                        { "fade_seconds", ITEM_AMBIENT_FADE },
                    }).dump());

                    // if (m_soundDebug)
                        // g_logger.info("[snd]   RESUME file {} ch{} - wanted again mid-fade, riding back up",
                                      // audioFileId, existing->second.channelId);
                // } else if (m_soundDebug && existing->second.unwantedSince != 0) {
                    // g_logger.info("[snd]   KEEP  file {} ch{} - wanted again during hold, never interrupted",
                                  // audioFileId, existing->second.channelId);
                // }
                }

                channel->setGain(gain);
                continue;
            }

            // The source went away under us - the fade landed between passes,
            // or the channel refused it when it was started and it was never
            // audible at all. Give the channel back and start it properly.
            m_freeItemAmbientChannels.push_back(existing->second.channelId);
            m_itemAmbientVoices.erase(existing);
        }

        const auto fileIt = m_clientSoundFiles.find(audioFileId);
        if (fileIt == m_clientSoundFiles.end()) {
            traceSoundEvent("item_ambience.drop", json({
                { "audio_file_id", audioFileId }, { "reason", "unknown_audio_file" },
            }).dump());
            g_logger.traceError("item ambient names audio file {}, which the soundbank does not have", audioFileId);
            continue;
        }

        const int channelId = acquireItemAmbientChannel();
        if (channelId < 0) {
            traceSoundEvent("item_ambience.drop", json({
                { "audio_file_id", audioFileId }, { "reason", "voice_limit" },
            }).dump());
            continue; // more at once than the bank was ever meant to need
        }

        const auto& channel = getChannel(channelId);
        if (!channel) {
            m_freeItemAmbientChannels.push_back(channelId);
            traceSoundEvent("item_ambience.drop", json({
                { "audio_file_id", audioFileId }, { "channel", channelId }, { "reason", "channel_unavailable" },
            }).dump());
            continue;
        }

        channel->setGain(gain);
        if (!channel->play(m_soundDirectory + fileIt->second.filename, ITEM_AMBIENT_FADE, 1.0f, 1.0f, true)) {
            // Recording it as playing anyway would leave the file permanently
            // claimed by a silent channel, and nothing here ever revives one.
            m_freeItemAmbientChannels.push_back(channelId);
            traceSoundEvent("item_ambience.drop", json({
                { "audio_file_id", audioFileId }, { "channel", channelId }, { "reason", "source_refused" },
            }).dump());
            continue;
        }

        m_itemAmbientVoices[audioFileId] = ItemAmbientVoice{ channelId };

        traceSoundEvent("item_ambience.play", json({
            { "audio_file_id", audioFileId },
            { "file", fileIt->second.filename },
            { "channel", channelId },
            { "gain", gain },
            { "fade_seconds", ITEM_AMBIENT_FADE },
            { "looping", true },
        }).dump());

        // if (m_soundDebug)
            // g_logger.info("[snd]   START file {} ch{} gain={:.2f} ({})",
                          // audioFileId, channelId, gain, fileIt->second.filename);
    }
}

// A channel for a loop that is starting: the free pool first, then a fresh id
// while the block has room. Holding loops past the moment they stop being
// wanted keeps channels busy for longer, so as a last resort the loop that has
// been unwanted longest gives its channel up rather than letting a hold starve
// a loop the map is asking for now. Returns -1 when there is nothing to give.
int SoundManager::acquireItemAmbientChannel()
{
    if (!m_freeItemAmbientChannels.empty()) {
        const int channelId = m_freeItemAmbientChannels.back();
        m_freeItemAmbientChannels.pop_back();
        return channelId;
    }

    const int channelId = SOUND_CHANNEL_ITEM_AMBIENT_FIRST + static_cast<int>(m_itemAmbientVoices.size());
    if (channelId <= SOUND_CHANNEL_ITEM_AMBIENT_LAST)
        return channelId;

    auto oldest = m_itemAmbientVoices.end();
    for (auto it = m_itemAmbientVoices.begin(); it != m_itemAmbientVoices.end(); ++it) {
        if (it->second.unwantedSince == 0)
            continue; // still wanted; not ours to take

        if (oldest == m_itemAmbientVoices.end() || it->second.unwantedSince < oldest->second.unwantedSince)
            oldest = it;
    }

    if (oldest == m_itemAmbientVoices.end())
        return -1;

    if (const auto& channel = getChannel(oldest->second.channelId))
        channel->stop();

    const int reclaimed = oldest->second.channelId;
    m_itemAmbientVoices.erase(oldest);
    return reclaimed;
}

void SoundManager::stopAmbienceSound()
{
    const uint32_t previous = m_currentAmbienceId;
    m_currentAmbienceId = 0;
    m_ambientDelayedEffects.clear();

    const auto& channel = getChannel(SOUND_CHANNEL_AMBIENT);
    if (channel)
        channel->stop(3.0f);

    traceSoundEvent("ambience.stop", json({ { "ambience_id", previous }, { "fade_seconds", 3.0f } }).dump());
}

void SoundManager::playMusic(uint32_t musicId)
{
    traceSoundEvent("music.request", json({ { "music_id", musicId } }).dump());

    if (!isAudioEnabled() || m_soundDirectory.empty()) {
        traceSoundEvent("music.drop", json({
            { "music_id", musicId },
            { "reason", !isAudioEnabled() ? "audio_disabled" : "soundbank_not_loaded" },
        }).dump());
        return;
    }

    // Handled before the dedupe below: "no music here" has to get through even
    // when nothing is playing, because it is also what clears the track the
    // music channel remembers for an unmute.
    if (musicId == 0) {
        stopMusic();
        return;
    }

    const auto& channel = getChannel(SOUND_CHANNEL_MUSIC);
    if (musicId == m_currentMusicId && channel && channel->isSounding()) {
        traceSoundEvent("music.drop", json({ { "music_id", musicId }, { "reason", "already_playing" } }).dump());
        return; // already playing; restarting would clip it back to the start
    }

    m_currentMusicId = 0;

    // The "Anthem" option. Checked here rather than through the effect filters,
    // which are keyed on a soundbank type music tracks do not carry.
    if (!isFilterEnabled("anthem")) {
        traceSoundEvent("music.drop", json({ { "music_id", musicId }, { "reason", "filtered" } }).dump());
        return;
    }

    const auto it = m_clientMusic.find(musicId);
    if (it == m_clientMusic.end()) {
        traceSoundEvent("music.drop", json({ { "music_id", musicId }, { "reason", "unknown_music" } }).dump());
        g_logger.traceError("unknown client music id {}", musicId);
        return;
    }

    const auto& music = it->second;
    const uint32_t audioFileId = music.audioFileId;
    if (audioFileId == 0) {
        traceSoundEvent("music.drop", json({ { "music_id", musicId }, { "reason", "no_audio_file" } }).dump());
        return;
    }

    // if (m_soundDebug)
        // g_logger.info("[snd] MUSIC track {} -> file {} (type {})", musicId, audioFileId,
                      // static_cast<int>(music.musicType));

    const auto fileIt = m_clientSoundFiles.find(audioFileId);
    if (fileIt == m_clientSoundFiles.end()) {
        traceSoundEvent("music.drop", json({
            { "music_id", musicId }, { "audio_file_id", audioFileId }, { "reason", "unknown_audio_file" },
        }).dump());
        return;
    }

    const std::string filename = m_soundDirectory + fileIt->second.filename;

    if (!channel) {
        traceSoundEvent("music.drop", json({ { "music_id", musicId }, { "reason", "channel_unavailable" } }).dump());
        return;
    }

    // MUSIC_IMMEDIATE is meant to cut in without a crossfade.
    const float fadetime = music.musicType == MUSIC_TYPE_MUSIC_IMMEDIATE ? 0.0f : 3.0f;

    // Signature tracks are one-shots. The server schedules a new play after a
    // long randomized pause; looping here would turn them into constant
    // background music and make those server packets ineffective.
    const auto& source = channel->play(filename, fadetime, 1.0f, 1.0f, false);
    if (!source) {
        // The channel turned it down - muted, or audio off. Claiming the track
        // as current here would make every later anthem carrying the same id
        // return early, so it would never be heard again this session.
        g_logger.traceError("music id {} was refused by the music channel", musicId);
        traceSoundEvent("music.drop", json({ { "music_id", musicId }, { "reason", "source_refused" } }).dump());
        return;
    }

    m_currentMusicId = musicId;
    traceSoundEvent("music.play", json({
        { "music_id", musicId },
        { "audio_file_id", audioFileId },
        { "file", fileIt->second.filename },
        { "music_type", static_cast<int>(music.musicType) },
        { "fade_seconds", fadetime },
        { "looping", false },
    }).dump());
}

void SoundManager::stopMusic()
{
    const uint32_t previous = m_currentMusicId;
    m_currentMusicId = 0;

    const auto& channel = getChannel(SOUND_CHANNEL_MUSIC);
    if (channel)
        channel->stop(3.0f);

    traceSoundEvent("music.stop", json({ { "music_id", previous }, { "fade_seconds", 3.0f } }).dump());
}
