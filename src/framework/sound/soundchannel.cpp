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

#include "soundchannel.h"
#include "soundmanager.h"
#include "streamsoundsource.h"

SoundSourcePtr SoundChannel::play(const std::string& filename, const float fadetime, float gain, float pitch, const bool looping)
{
    // An argument a Lua caller left out reaches us as 0 rather than as the C++
    // default, so normalise here - before the channel gain is folded in, since
    // normalising the product would turn a channel muted to 0% back to full.
    if (gain == 0)
        gain = 1.0f;

    if (pitch == 0)
        pitch = 1.0f;

    // remembered even when the channel turns it down, so unmuting resumes what
    // was asked for last rather than whatever happened to play before the mute
    m_lastPlayed.emplace(filename, fadetime, gain, pitch, looping);

    if (!g_sounds.isAudioEnabled() || !m_enabled)
        return nullptr;

    if (m_currentSource)
        m_currentSource->stop();

    m_currentSource = g_sounds.play(filename, fadetime, m_gain * gain, pitch);
    if (m_currentSource)
        m_currentSource->setLooping(looping);

    return m_currentSource;
}

void SoundChannel::stop(const float fadetime)
{
    m_queue.clear();
    m_lastPlayed.reset();

    if (m_currentSource) {
        g_sounds.ensureContext();
        if (fadetime > 0)
            m_currentSource->setFading(StreamSoundSource::FadingOff, fadetime);
        else {
            m_currentSource->stop();
            m_currentSource = nullptr;
        }
    }
}

void SoundChannel::enqueue(const std::string& filename, float fadetime, float gain, float pitch, const bool looping)
{
    // as in play(): Lua callers that omit these arguments hand us 0
    if (gain == 0)
        gain = 1.0f;

    if (pitch == 0)
        pitch = 1.0f;

    m_queue.emplace_back(g_sounds.resolveSoundFile(filename), fadetime, gain, pitch, looping);

    std::shuffle(m_queue.begin(), m_queue.end(), std::mt19937(std::random_device()()));
    //update();
}

void SoundChannel::update()
{
    if (m_currentSource && !m_currentSource->isPlaying())
        m_currentSource = nullptr;

    if (!m_currentSource && !m_queue.empty() && g_sounds.isAudioEnabled() && m_enabled) {
        const QueueEntry entry = m_queue.front();
        m_queue.pop_front();
        m_queue.emplace_back(entry);
        play(entry.filename, entry.fadetime, entry.gain, entry.pitch, entry.looping);
    }
}

void SoundChannel::setEnabled(const bool enable)
{
    if (m_enabled == enable)
        return;

    if (enable) {
        m_enabled = true;
        // the queue speaks first - the login music lives there and already
        // resumes this way; the remembered track covers the play() callers,
        // which leave the queue empty
        if (m_queue.empty() && m_lastPlayed) {
            const QueueEntry entry = *m_lastPlayed;
            play(entry.filename, entry.fadetime, entry.gain, entry.pitch, entry.looping);
        } else
            update();
    } else {
        m_enabled = false;
        if (m_currentSource) {
            m_currentSource->stop();
            m_currentSource = nullptr;
        }
    }
}

void SoundChannel::setGain(const float gain)
{
    m_gain = gain;

    // Keep the per-play factor play() folded in, and move the target rather
    // than the current level so a slider dragged during a fade is not undone
    // by the next update().
    if (m_currentSource)
        m_currentSource->setTargetGain(gain * (m_lastPlayed ? m_lastPlayed->gain : 1.0f));
}

void SoundChannel::setPitch(const float pitch)
{
    if (m_currentSource)
        m_currentSource->setPitch(pitch);
    m_pitch = pitch;
}

void SoundChannel::setPosition(const Point& pos)
{
    if (m_currentSource)
        m_currentSource->setPosition(pos);
    m_pos = pos;
}