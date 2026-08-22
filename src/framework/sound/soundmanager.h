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

#pragma once

#include "declarations.h"
#include <deque>

using DelayedSoundEffect = std::pair<uint32_t, uint32_t>;
using DelayedSoundEffects = std::vector<DelayedSoundEffect>;
// "once this many are on screen, loop this file". Deliberately a named struct:
// as a pair it was declared count-first and filled sound-id-first, and the
// thresholds are large enough (624, 786) to look like plausible counts, so the
// inversion would have gone unnoticed.
struct ItemCountSoundEffect
{
    uint32_t count;
    uint32_t loopingAudioFileId;
};
using ItemCountSoundEffects = std::vector<ItemCountSoundEffect>;

class StreamSoundSource;
class CombinedSoundSource;
class SoundFile;
class SoundBuffer;

enum ClientSoundType
{
    NUMERIC_SOUND_TYPE_UNKNOWN = 0,
    NUMERIC_SOUND_TYPE_SPELL_ATTACK = 1,
    NUMERIC_SOUND_TYPE_SPELL_HEALING = 2,
    NUMERIC_SOUND_TYPE_SPELL_SUPPORT = 3,
    NUMERIC_SOUND_TYPE_WEAPON_ATTACK = 4,
    NUMERIC_SOUND_TYPE_CREATURE_NOISE = 5,
    NUMERIC_SOUND_TYPE_CREATURE_DEATH = 6,
    NUMERIC_SOUND_TYPE_CREATURE_ATTACK = 7,
    NUMERIC_SOUND_TYPE_AMBIENCE_STREAM = 8,
    NUMERIC_SOUND_TYPE_FOOD_AND_DRINK = 9,
    NUMERIC_SOUND_TYPE_ITEM_MOVEMENT = 10,
    NUMERIC_SOUND_TYPE_EVENT = 11,
    NUMERIC_SOUND_TYPE_UI = 12,
    NUMERIC_SOUND_TYPE_WHISPER_WITHOUT_OPEN_CHAT = 13,
    NUMERIC_SOUND_TYPE_CHAT_MESSAGE = 14,
    NUMERIC_SOUND_TYPE_PARTY = 15,
    NUMERIC_SOUND_TYPE_VIP_LIST = 16,
    NUMERIC_SOUND_TYPE_RAID_ANNOUNCEMENT = 17,
    NUMERIC_SOUND_TYPE_SERVER_MESSAGE = 18,
    NUMERIC_SOUND_TYPE_SPELL_GENERIC = 19
};

// Who the protocol says a sound effect came from. Mirrors
// Otc::MagicEffectSources, restated here so the framework needs no game header.
enum ClientSoundSource : uint8_t
{
    SOUND_SOURCE_DEFAULT = 0,
    SOUND_SOURCE_OWN = 1,
    SOUND_SOURCE_OTHER_PLAYER = 2,
    SOUND_SOURCE_MONSTER = 3,
    SOUND_SOURCE_BOSS = 4
};

// The mixing channels the sound options drive, one per volume slider. Kept in
// step with SoundChannels in modules/corelib/const.lua.
enum ClientSoundChannel
{
    SOUND_CHANNEL_MUSIC = 1,
    SOUND_CHANNEL_AMBIENT = 2,
    SOUND_CHANNEL_EFFECT = 3, // anything no slider claims
    SOUND_CHANNEL_ITEM = 4,
    SOUND_CHANNEL_EVENT = 5,
    SOUND_CHANNEL_OWN_BATTLE = 6,
    SOUND_CHANNEL_OTHER_PLAYERS = 7,
    SOUND_CHANNEL_CREATURES = 8,
    SOUND_CHANNEL_UI = 9,
    // one per concurrently looping item ambient; the bank needs up to 7
    SOUND_CHANNEL_ITEM_AMBIENT_FIRST = 10,
    SOUND_CHANNEL_ITEM_AMBIENT_LAST = 20
};

enum ClientMusicType
{
    MUSIC_TYPE_UNKNOWN = 0,
    MUSIC_TYPE_MUSIC = 1,
    MUSIC_TYPE_MUSIC_IMMEDIATE = 2,
    MUSIC_TYPE_MUSIC_TITLE = 3,
};

// client sound effect parsed from the protobuf file
struct ClientSoundEffect
{
    uint32_t clientId;
    ClientSoundType type;
    float pitchMin;
    float pitchMax;
    float volumeMin;
    float volumeMax;
    uint32_t soundId = 0;
    std::vector<uint32_t> randomSoundId;
};

// client location ambient parsed from the protobuf file
// an entry of the soundbank's audio file table
struct ClientSoundFile
{
    std::string filename;
    // the bank's own answer to "is this too long to hold in memory". Without it
    // preload() decodes a multi-megabyte track in full only to throw it away for
    // exceeding MAX_CACHE_SIZE.
    bool isStream;
};

struct ClientLocationAmbient
{
    uint32_t clientId;
    uint32_t loopedAudioFileId;

    // vector of pairs, where the pair is:
    // < effect clientId, delay in seconds >
    DelayedSoundEffects delayedSoundEffects;
};

// client item ambient parsed from the protobuf file
struct ClientItemAmbient
{
    uint32_t id;
    std::vector<uint32_t> clientIds;

    // this is a very specific client mechanic
    // depending on how many items are on the game screen
    // a different looped ambient effect will be played
    // for example, configuration like this:
    // 1 -> 630
    // 5 -> 625
    // means that when there is one item on the screen, an audio file number 630 should play
    // once there are 5 of them, the client should play an audio file number 625
    //
    // The bank does NOT store these in ascending order - one entry lists 5
    // before 1 - so they are sorted at load time and selection takes the
    // highest threshold that the count reaches.
    ItemCountSoundEffects itemCountSoundEffects;

    // how near the player an item has to be to count, in tiles. 0 means the
    // whole screen.
    uint32_t maxSoundDistance{ 0 };
};

struct ClientMusic
{
    uint32_t id; // track id
    uint32_t audioFileId; // audio file id
    ClientMusicType musicType;
};

//@bindsingleton g_sounds
class SoundManager
{
    enum
    {
        MAX_CACHE_SIZE = 2000000,
        POLL_DELAY = 100
    };
public:
    void init();
    void terminate();
    void poll();

    void setAudioEnabled(bool enable);
    bool isAudioEnabled() { return m_device && m_context && m_audioEnabled; }
    void enableAudio() { setAudioEnabled(true); }
    void disableAudio() { setAudioEnabled(false); }
    void stopAll();
    void setPosition(const Point& pos);
    bool isEaxEnabled();
    bool loadClientFiles(const std::string& directory);
    std::string getAudioFileNameById(int32_t audioFileId);

    void preload(std::string filename);
    SoundSourcePtr play(const std::string& filename, float fadetime = 0, float gain = 1.0f, float pitch = 1.0f);
    SoundChannelPtr getChannel(int channel);
    void setClientSoundVolume(int channel, float volume);
    void setMasterVolume(float volume);
    void setClientSoundFilter(const std::string& category, bool enabled);
    bool isClientSoundFilterEnabled(const std::string& category) { const auto it = m_clientSoundFilters.find(category); return it == m_clientSoundFilters.end() || it->second; }
    SoundEffectPtr createSoundEffect();

    // client sound playback by protobuf IDs
    void playSoundEffect(uint32_t effectId, uint8_t source = SOUND_SOURCE_DEFAULT);

    // The soundbank effect used for UI interactions. Set from Lua so the
    // framework carries no game-specific id.
    void setUiSoundEffect(const uint32_t effectId) { m_uiSoundEffectId = effectId; }
    void playUiSoundEffect() { if (m_uiSoundEffectId != 0) playSoundEffect(m_uiSoundEffectId); }
    void playAmbienceSound(uint32_t ambienceId);

    // Item ambients: a waterfall or campfire loops while enough of its items are
    // on screen. The client counts them - only it can see the map - and the
    // framework decides what that means and plays it.
    struct ItemAmbientQuery
    {
        std::vector<uint16_t> clientIds; // item client ids that count
        uint32_t maxDistance;            // in tiles, 0 = the whole screen
    };
    const std::vector<ItemAmbientQuery>& getItemAmbientQueries() const { return m_itemAmbientQueries; }
    // bumped whenever the queries are rebuilt, so a cached index can tell that
    // a different soundbank loaded even if it happens to hold as many entries
    uint32_t getItemAmbientGeneration() const { return m_itemAmbientGeneration; }
    void setItemAmbientCounts(const std::vector<uint16_t>& counts);
    void playMusic(uint32_t musicId);
    void stopAmbienceSound();
    void stopMusic();

    const std::string& getSoundDirectory() const { return m_soundDirectory; }

    std::string resolveSoundFile(const std::string& file);
    void ensureContext() const;

private:
    SoundSourcePtr createSoundSource(const std::string& name);
    bool loadFromProtobuf(const std::string& directory, const std::string& fileName);

    bool isFilterEnabled(std::string_view category) const;
    void updateAmbientDelayedEffects();
    void buildItemAmbientQueries();
    void stopItemAmbients();
    void subscribeDeviceEvents();
    void unsubscribeDeviceEvents();
    void followDefaultDevice();

    ALCdevice* m_device{};
    ALCcontext* m_context{};
    ALuint m_effect;
    ALuint m_effectSlot;

    std::unordered_map<StreamSoundSourcePtr, std::shared_future<SoundFilePtr>> m_streamFiles;
    std::unordered_map<std::string, SoundBufferPtr> m_buffers;
    std::unordered_map<std::string, std::string> m_resolvedFiles;
    std::unordered_map<int, SoundChannelPtr> m_channels;
    std::unordered_map<std::string, bool> m_clientSoundFilters;
    std::unordered_map<std::string, SoundEffectPtr> m_effects;

    // soundbanks for protocol 13 and newer
    std::string m_soundDirectory;
    std::map<uint32_t, ClientSoundFile> m_clientSoundFiles;
    std::map<uint32_t, ClientSoundEffect> m_clientSoundEffects;

    // the music track currently playing, so a repeated anthem packet does not
    // restart it from the beginning
    uint32_t m_currentMusicId{ 0 };

    // the location ambience currently playing, for the same reason - and so a
    // repeat does not keep resetting the timers below
    uint32_t m_currentAmbienceId{ 0 };

    // The effects the bank pairs with the current location ambience: a bird
    // call, a distant splash, each on its own period.
    struct PendingAmbientEffect
    {
        uint32_t effectId;
        ticks_t period;
        ticks_t nextPlay;
    };
    std::vector<PendingAmbientEffect> m_ambientDelayedEffects;

    // built once per soundbank load, in the order setItemAmbientCounts expects
    std::vector<ItemAmbientQuery> m_itemAmbientQueries;
    std::vector<uint32_t> m_itemAmbientEffectIds; // parallel to the queries
    uint32_t m_itemAmbientGeneration{ 0 };

    // audio file id -> the channel looping it. Keyed on the FILE, not the
    // effect: two effects can select the same file at once and it must not be
    // started twice at double volume.
    std::unordered_map<uint32_t, int> m_itemAmbientChannels;
    std::vector<int> m_freeItemAmbientChannels;

    uint32_t m_uiSoundEffectId{ 0 };
    std::map<uint32_t, ClientLocationAmbient> m_clientAmbientEffects;
    std::map<uint32_t, ClientItemAmbient> m_clientItemAmbientEffects;
    std::map<uint32_t, ClientMusic> m_clientMusic;

    std::deque<SoundSourcePtr> m_sources;
    std::unordered_map<std::string, ticks_t> m_lastPlayTime;
    bool m_audioEnabled{ true };
};

extern SoundManager g_sounds;
