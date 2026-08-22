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
        POLL_DELAY = 100,

        // How long a looping item ambient keeps playing after the map stops
        // asking for it. Restarting one of these costs an ogg decode, a gap and
        // a ramp from sample 0, so a loop that is about to be wanted again is
        // better held than torn down. It only has to outlast the map being
        // momentarily wrong - a teleport rebuilding the visible-tile cache,
        // which settles in a scan or two - NOT to cover walking away, which is
        // the map being right. Held any longer and a waterfall trails a player
        // who ran off well out of sight of it.
        ITEM_AMBIENT_HOLD_MS = 500,

        // The hold used instead when the items that fed the loop are STILL ON
        // SCREEN and merely out of the entry's radius. That is a player pacing
        // around a brazier, not one who left: they are very likely to step back
        // in, and a restart costs a decode, a gap and a ramp from sample 0.
        // Walking clean away leaves nothing on screen and takes the short hold
        // above, so a waterfall still stops promptly once it is behind you.
        ITEM_AMBIENT_HOLD_NEAR_MS = 3000,

        // How long a DIFFERENT step of the same entry has to stay selected
        // before it takes over. An entry's steps are intensity layers of one
        // ambient, and a count that straddles a threshold - which is normal,
        // since a whole-screen entry gains and loses items at the screen edge
        // as the player walks - would otherwise swap the two files back and
        // forth indefinitely, each swap restarting a half-minute stream.
        ITEM_AMBIENT_STEP_MS = 2000
    };

    // Seconds. Also the window a held loop is faded out over once the hold
    // expires - and the window it is ridden back up over if it is wanted again
    // mid-fade. Fades are stepped from poll(), so this buys POLL_DELAY-sized
    // gain steps: much below half a second there are too few of them left for
    // the ramp to still sound like one.
    static constexpr float ITEM_AMBIENT_FADE = 0.5f;
public:
    // How the sound system measures space. The bank gives a radius in tiles per
    // item ambient, but three of its seven entries carry NO radius field at all
    // - proto2 decodes the absent field as 0, which is not a specification.
    // Rather than read that as "unlimited", those entries get a real default,
    // so proximity always means proximity.
    static constexpr uint32_t ITEM_AMBIENT_DEFAULT_RADIUS = 8;
    // What one floor costs, in tiles. Without a real cost a source directly
    // below the player reads as adjacent, and whether it is heard at all ends
    // up decided by which floors the renderer happens to be drawing.
    static constexpr uint32_t ITEM_AMBIENT_FLOOR_COST = 3;
    // How far past its radius an item still counts as "just out of reach"
    // rather than gone - what picks the long hold over the short one.
    static constexpr uint32_t ITEM_AMBIENT_NEAR_MARGIN = 4;

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
        uint32_t maxDistance;            // in tiles; the bank's absent case is
                                         // already resolved to the default here
        uint32_t effectId;               // the bank entry it came from, for tracing
    };
    const std::vector<ItemAmbientQuery>& getItemAmbientQueries() const { return m_itemAmbientQueries; }
    // bumped whenever the queries are rebuilt, so a cached index can tell that
    // a different soundbank loaded even if it happens to hold as many entries
    uint32_t getItemAmbientGeneration() const { return m_itemAmbientGeneration; }
    // counts: items in range per query. nearby: items that matched the query
    // but were out of its radius - the difference between "gone" and "just out
    // of reach", which is what decides how long a loop is held before it goes.
    void setItemAmbientCounts(const std::vector<uint16_t>& counts,
                              const std::vector<uint16_t>& nearby);

    // Sound tracing. Off by default; g_sounds.setSoundDebug(true) from the
    // in-client terminal (Ctrl+T) turns it on live. Every line it writes is
    // prefixed [snd] so a log or a console can be grepped down to just this.
    void setSoundDebug(bool enable);
    bool isSoundDebug() const { return m_soundDebug; }
    // What the bank holds: every item ambient, its radius, its steps and the
    // files they select. Answers "which entry is the sound I am hearing".
    void debugSoundbank();
    // What is audible right now: every looping voice with its channel, state
    // and gain, plus the music and location ambience ids.
    void debugPlaying();

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
    int acquireItemAmbientChannel();
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

    // One looping item ambient that has been started. A file the map stops
    // asking for is not torn down at once: it plays on untouched for
    // ITEM_AMBIENT_HOLD_MS, then fades out, and either of those states reverts
    // to plain playing the moment it is wanted again. The channel goes back to
    // the pool only once the fade has actually finished, so a channel handed
    // out again can never hard-cut a source that is still audible.
    struct ItemAmbientVoice
    {
        int channelId;
        ticks_t unwantedSince{ 0 }; // 0 while the map still wants it
        bool releasing{ false };    // the fade-out has been armed
    };

    // audio file id -> the voice looping it. Keyed on the FILE, not the
    // effect: two effects can select the same file at once and it must not be
    // started twice at double volume.
    std::unordered_map<uint32_t, ItemAmbientVoice> m_itemAmbientVoices;
    std::vector<int> m_freeItemAmbientChannels;
    // What each query has settled on, and what is currently trying to take
    // over. Only a change BETWEEN two steps is debounced: starting from
    // silence and falling to silence both commit at once, so walking up to a
    // fire still sounds it immediately and the release pass above still owns
    // the fade-out. Parallel to the queries.
    struct ItemAmbientSelection
    {
        uint32_t audioFileId{ 0 }; // committed - what is actually asked for
        uint32_t pending{ 0 };     // candidate waiting out ITEM_AMBIENT_STEP_MS
        ticks_t pendingSince{ 0 };
    };
    std::vector<ItemAmbientSelection> m_itemAmbientSelected;
    // Debug only: the counts of the previous scan, so tracing can report the
    // moments a count actually moves rather than four times a second.
    std::vector<uint16_t> m_itemAmbientLastCounts;
    bool m_soundDebug{ false };

    uint32_t m_uiSoundEffectId{ 0 };
    std::map<uint32_t, ClientLocationAmbient> m_clientAmbientEffects;
    std::map<uint32_t, ClientItemAmbient> m_clientItemAmbientEffects;
    std::map<uint32_t, ClientMusic> m_clientMusic;

    std::deque<SoundSourcePtr> m_sources;
    std::unordered_map<std::string, ticks_t> m_lastPlayTime;
    bool m_audioEnabled{ true };
};

extern SoundManager g_sounds;
