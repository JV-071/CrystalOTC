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
#include <atomic>
#include <nlohmann/json.hpp>
#include <sounds.pb.h>

#include "soundbuffer.h"
#include "soundchannel.h"
#include "soundeffect.h"
#include "soundfile.h"
#include "soundsource.h"
#include "streamsoundsource.h"
#include "combinedsoundsource.h"
#include "client/game.h"
#include "framework/core/asyncdispatcher.h"
#include "framework/core/clock.h"
#include "framework/core/garbagecollection.h"
#include "framework/core/resourcemanager.h"
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

void SoundManager::init()
{
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
    // The seven Console Messages sub-options - party, guild, npcs, global,
    // teamFinder, privateMessages, privateMessagesLocalChat - have no
    // counterpart: the sound packet names no chat channel, so they all fall
    // under "consoleMessages" and cannot be told apart.
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

void SoundManager::playSoundEffect(uint32_t effectId, const uint8_t source)
{
    if (!isAudioEnabled() || m_soundDirectory.empty())
        return;

    // limit new sound effects to 4 per poll cycle to prevent burst lag
    static ticks_t lastResetTime = 0;
    static int effectsThisCycle = 0;
    const ticks_t now = g_clock.millis();
    if (now - lastResetTime >= POLL_DELAY) {
        lastResetTime = now;
        effectsThisCycle = 0;
    }
    if (effectsThisCycle >= 4)
        return;
    ++effectsThisCycle;

    const auto it = m_clientSoundEffects.find(effectId);
    if (it == m_clientSoundEffects.end())
        return;

    const auto& effect = it->second;

    const auto categories = soundFilterCategories(effect.type, source);
    if (!isFilterEnabled(categories.group) || !isFilterEnabled(categories.specific))
        return;

    // resolve the audio file id
    uint32_t audioFileId = effect.soundId;
    if (audioFileId == 0 && !effect.randomSoundId.empty()) {
        audioFileId = effect.randomSoundId[rand() % effect.randomSoundId.size()];
    }
    if (audioFileId == 0)
        return;

    const auto fileIt = m_clientSoundFiles.find(audioFileId);
    if (fileIt == m_clientSoundFiles.end())
        return;

    const std::string filename = m_soundDirectory + fileIt->second.filename;

    // throttle: skip if same sound was played less than 150ms ago
    auto& lastTime = m_lastPlayTime[filename];
    if (now - lastTime < 150)
        return;
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
    if (const auto& channel = getChannel(soundEffectChannel(effect.type, source)))
        gain *= channel->getGain();

    play(filename, 0, gain, pitch);
}

void SoundManager::playAmbienceSound(uint32_t ambienceId)
{
    if (!isAudioEnabled() || m_soundDirectory.empty())
        return;

    if (ambienceId == 0) {
        stopAmbienceSound();
        return;
    }

    if (ambienceId == m_currentAmbienceId)
        return; // already playing; restarting would clip it and reset its timers

    const auto it = m_clientAmbientEffects.find(ambienceId);
    if (it == m_clientAmbientEffects.end()) {
        g_logger.traceError("unknown client ambience id {}", ambienceId);
        return;
    }

    const auto& ambient = it->second;
    const uint32_t audioFileId = ambient.loopedAudioFileId;
    if (audioFileId == 0)
        return;

    const auto fileIt = m_clientSoundFiles.find(audioFileId);
    if (fileIt == m_clientSoundFiles.end()) {
        g_logger.traceError("ambience id {} names audio file {}, which the soundbank does not have", ambienceId, audioFileId);
        return;
    }

    const std::string filename = m_soundDirectory + fileIt->second.filename;

    const auto& channel = getChannel(SOUND_CHANNEL_AMBIENT);
    if (!channel)
        return;

    channel->stop(3.0f);
    // A location ambience loops, and saying so lets the stream recover from an
    // underrun instead of leaving the channel wedged on a source that stopped
    // but still claims to be playing.
    channel->enqueue(filename, 3.0f, 1.0f, 1.0f, true);

    m_currentAmbienceId = ambienceId;

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
        m_ambientDelayedEffects.emplace_back(delayedEffectId, period, now + (rand() % period));
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
        playSoundEffect(pending.effectId);
        pending.nextPlay = now + pending.period;
    }
}

void SoundManager::buildItemAmbientQueries()
{
    m_itemAmbientQueries.clear();
    m_itemAmbientEffectIds.clear();
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

        m_itemAmbientQueries.emplace_back(std::move(clientIds), ambient.maxSoundDistance);
        m_itemAmbientEffectIds.push_back(effectId);
    }
}

void SoundManager::stopItemAmbients()
{
    for (const auto& [audioFileId, channelId] : m_itemAmbientChannels) {
        if (const auto& channel = getChannel(channelId))
            channel->stop(1.0f);
    }

    m_itemAmbientChannels.clear();
    m_freeItemAmbientChannels.clear();
}

// Called by the client with one count per query, in query order: how many of
// that entry's items are currently on screen (and near enough, where the entry
// asks for that).
void SoundManager::setItemAmbientCounts(const std::vector<uint16_t>& counts)
{
    if (counts.size() != m_itemAmbientQueries.size())
        return;

    if (!isAudioEnabled() || m_soundDirectory.empty()) {
        stopItemAmbients();
        return;
    }

    // Which files should be looping now. Deduped by file: two entries can
    // select the same one, and starting it twice would just double its volume.
    std::vector<uint32_t> wanted;
    for (size_t i = 0; i < counts.size(); ++i) {
        const auto it = m_clientItemAmbientEffects.find(m_itemAmbientEffectIds[i]);
        if (it == m_clientItemAmbientEffects.end())
            continue;

        // highest threshold the count reaches; none qualifying means silence,
        // which is the normal state at zero and below an entry's first step
        uint32_t audioFileId = 0;
        for (const auto& [threshold, loopingAudioFileId] : it->second.itemCountSoundEffects) {
            if (counts[i] >= threshold)
                audioFileId = loopingAudioFileId;
        }

        if (audioFileId != 0 && std::ranges::find(wanted, audioFileId) == wanted.end())
            wanted.push_back(audioFileId);
    }

    // stop what is no longer wanted, freeing its channel
    for (auto it = m_itemAmbientChannels.begin(); it != m_itemAmbientChannels.end();) {
        if (std::ranges::find(wanted, it->first) != wanted.end()) {
            ++it;
            continue;
        }

        if (const auto& channel = getChannel(it->second))
            channel->stop(1.0f);

        m_freeItemAmbientChannels.push_back(it->second);
        it = m_itemAmbientChannels.erase(it);
    }

    // item ambients are ambience, so they track that slider
    const auto& ambientChannel = getChannel(SOUND_CHANNEL_AMBIENT);
    const float gain = ambientChannel ? ambientChannel->getGain() : 1.0f;

    for (const uint32_t audioFileId : wanted) {
        if (const auto existing = m_itemAmbientChannels.find(audioFileId); existing != m_itemAmbientChannels.end()) {
            if (const auto& channel = getChannel(existing->second))
                channel->setGain(gain);
            continue;
        }

        const auto fileIt = m_clientSoundFiles.find(audioFileId);
        if (fileIt == m_clientSoundFiles.end()) {
            g_logger.traceError("item ambient names audio file {}, which the soundbank does not have", audioFileId);
            continue;
        }

        int channelId;
        if (!m_freeItemAmbientChannels.empty()) {
            channelId = m_freeItemAmbientChannels.back();
            m_freeItemAmbientChannels.pop_back();
        } else {
            channelId = SOUND_CHANNEL_ITEM_AMBIENT_FIRST + static_cast<int>(m_itemAmbientChannels.size());
            if (channelId > SOUND_CHANNEL_ITEM_AMBIENT_LAST)
                continue; // more at once than the bank was ever meant to need
        }

        const auto& channel = getChannel(channelId);
        if (!channel)
            continue;

        channel->setGain(gain);
        channel->play(m_soundDirectory + fileIt->second.filename, 1.0f, 1.0f, 1.0f, true);
        m_itemAmbientChannels[audioFileId] = channelId;
    }
}

void SoundManager::stopAmbienceSound()
{
    m_currentAmbienceId = 0;
    m_ambientDelayedEffects.clear();

    const auto& channel = getChannel(SOUND_CHANNEL_AMBIENT);
    if (channel)
        channel->stop(3.0f);
}

void SoundManager::playMusic(uint32_t musicId)
{
    if (!isAudioEnabled() || m_soundDirectory.empty())
        return;

    // Handled before the dedupe below: "no music here" has to get through even
    // when nothing is playing, because it is also what clears the track the
    // music channel remembers for an unmute.
    if (musicId == 0) {
        stopMusic();
        return;
    }

    if (musicId == m_currentMusicId)
        return; // already playing; restarting would clip it back to the start

    m_currentMusicId = 0;

    // The "Anthem" option. Checked here rather than through the effect filters,
    // which are keyed on a soundbank type music tracks do not carry.
    if (!isFilterEnabled("anthem"))
        return;

    const auto it = m_clientMusic.find(musicId);
    if (it == m_clientMusic.end()) {
        g_logger.traceError("unknown client music id {}", musicId);
        return;
    }

    const auto& music = it->second;
    const uint32_t audioFileId = music.audioFileId;
    if (audioFileId == 0)
        return;

    const auto fileIt = m_clientSoundFiles.find(audioFileId);
    if (fileIt == m_clientSoundFiles.end())
        return;

    const std::string filename = m_soundDirectory + fileIt->second.filename;

    const auto& channel = getChannel(SOUND_CHANNEL_MUSIC);
    if (!channel)
        return;

    // MUSIC_IMMEDIATE is meant to cut in without a crossfade.
    const float fadetime = music.musicType == MUSIC_TYPE_MUSIC_IMMEDIATE ? 0.0f : 3.0f;

    // play() rather than enqueue(): a looping source never reaches EOF, so the
    // channel queue would never cycle it anyway, and looping the stream itself
    // is gapless where a queue restart is not.
    const auto& source = channel->play(filename, fadetime, 1.0f, 1.0f, true);
    if (!source) {
        // The channel turned it down - muted, or audio off. Claiming the track
        // as current here would make every later anthem carrying the same id
        // return early, so it would never be heard again this session.
        g_logger.traceError("music id {} was refused by the music channel", musicId);
        return;
    }

    m_currentMusicId = musicId;
}

void SoundManager::stopMusic()
{
    m_currentMusicId = 0;

    const auto& channel = getChannel(SOUND_CHANNEL_MUSIC);
    if (channel)
        channel->stop(3.0f);
}
