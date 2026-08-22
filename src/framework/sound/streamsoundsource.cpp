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

#include "streamsoundsource.h"

#include "soundbuffer.h"
#include "soundfile.h"
#include "framework/core/resourcemanager.h"

StreamSoundSource::StreamSoundSource()
{
    m_freeBuffers.reserve(STREAM_FRAGMENTS);
    for (auto& buffer : m_buffers) {
        buffer = std::make_shared<SoundBuffer>();
        m_freeBuffers.push_back(buffer->getBufferId());
    }
    m_downMix = NoDownMix;
}

StreamSoundSource::~StreamSoundSource()
{
    stop();
}

void StreamSoundSource::setFile(std::string filename)
{
    filename = g_resources.guessFilePath(filename, "ogg");
    filename = g_resources.resolvePath(filename);

    const SoundFilePtr soundFile = SoundFile::loadSoundFile(filename);

    if (!soundFile) {
        g_logger.error("unable to load sound file '{}'", filename);
        return;
    }

    setSoundFile(soundFile);
}

void StreamSoundSource::setSoundFile(const SoundFilePtr& soundFile)
{
    m_soundFile = soundFile;
    if (m_waitingFile) {
        m_waitingFile = false;
        if (m_playing) {
            restartFading();
            play();
        }
    }
}

void StreamSoundSource::play()
{
    m_playing = true;

    if (!m_soundFile) {
        m_waitingFile = true;
        return;
    }

    if (m_eof) {
        m_soundFile->reset();
        m_eof = false;
    }

    queueBuffers();

    SoundSource::play();
}

void StreamSoundSource::stop()
{
    m_playing = false;

    if (m_waitingFile) {
        m_waitingFile = false;
        return;
    }

    SoundSource::stop();
    unqueueBuffers();
}

void StreamSoundSource::setLooping(const bool looping)
{
    // Streaming sources queue multiple OpenAL buffers, so AL_LOOPING cannot be
    // used. Rewind the stream in fillBufferAndQueue() instead.
    m_looping = looping;
}

void StreamSoundSource::queueBuffers()
{
    if (m_sourceId == 0) return;

    // Refilling a buffer the source still has queued is rejected with
    // AL_INVALID_OPERATION, so only ever hand fillBufferAndQueue a free one.
    while (!m_freeBuffers.empty()) {
        if (!fillBufferAndQueue(m_freeBuffers.back()))
            break;
        m_freeBuffers.pop_back();
    }
}

void StreamSoundSource::unqueueBuffers()
{
    if (m_sourceId == 0) return;
    int queued;
    alGetSourcei(m_sourceId, AL_BUFFERS_QUEUED, &queued);
    for (int i = 0; i < queued; ++i) {
        uint32_t buffer;
        alSourceUnqueueBuffers(m_sourceId, 1, &buffer);
        if (alGetError() == AL_NO_ERROR)
            m_freeBuffers.push_back(buffer);
    }
}

void StreamSoundSource::update()
{
    if (m_waitingFile || m_sourceId == 0)
        return;

    SoundSource::update();

    // the fade-out above may have ended the sound; stop() already handed the
    // buffers back, so there is nothing left to refill
    if (!m_playing)
        return;

    int processed = 0;
    alGetSourcei(m_sourceId, AL_BUFFERS_PROCESSED, &processed);
    for (int i = 0; i < processed; ++i) {
        uint32_t buffer;
        alSourceUnqueueBuffers(m_sourceId, 1, &buffer);
        if (alGetError() == AL_NO_ERROR)
            m_freeBuffers.push_back(buffer);
    }

    queueBuffers();

    if (!isBuffering() && m_playing) {
        if (!m_looping && m_eof) {
            stop();
        } else {
            // The source ran dry before this refill reached it. Whatever is
            // queued now has to be started by hand: OpenAL will not resume a
            // stopped source on its own, and nothing else here ever would, so
            // the stream would stay silent while it still believes it plays.
            if (processed == 0)
                g_logger.traceError("audio buffer underrun");
            play();
        }
    }
}

bool StreamSoundSource::fillBufferAndQueue(const uint32_t buffer)
{
    if (m_waitingFile || m_sourceId == 0)
        return false;

    // fill buffer
    static std::vector<char> bufferData(2 * STREAM_FRAGMENT_SIZE);
    ALenum format = m_soundFile->getSampleFormat();

    int maxRead = STREAM_FRAGMENT_SIZE;
    if (m_downMix != NoDownMix)
        maxRead *= 2;

    int bytesRead = 0;
    bool rewound = false;
    while (bytesRead < maxRead) {
        const int read = m_soundFile->read(bufferData.data() + bytesRead, maxRead - bytesRead);
        bytesRead += read;

        if (bytesRead >= maxRead)
            break;

        // Short read: the sound file ended. A loop starts it over, unless it
        // came up empty on the rewind too - that file has nothing to give and
        // asking again would spin here forever.
        if (!m_looping || (rewound && read == 0)) {
            m_eof = true;
            break;
        }

        rewound = true;
        m_soundFile->reset();
    }

    if (bytesRead > 0) {
        if (m_downMix != NoDownMix) {
            if (format == AL_FORMAT_STEREO16) {
                assert(bytesRead % 2 == 0);
                bytesRead /= 2;
                auto* const data = reinterpret_cast<uint16_t*>(bufferData.data());
                for (int i = 0; i < bytesRead / 2; ++i)
                    data[i] = data[2 * i + (m_downMix == DownMixLeft ? 0 : 1)];
                format = AL_FORMAT_MONO16;
            }
        }

        alBufferData(buffer, format, bufferData.data(), bytesRead, m_soundFile->getRate());
        ALenum err = alGetError();
        if (err != AL_NO_ERROR)
            g_logger.error("unable to refill audio buffer for '{}': {}", m_soundFile->getName(), alGetString(err));

        alSourceQueueBuffers(m_sourceId, 1, &buffer);
        err = alGetError();
        if (err != AL_NO_ERROR) {
            g_logger.error("unable to queue audio buffer for '{}': {}", m_soundFile->getName(), alGetString(err));
            return false;
        }

        return true;
    }

    // nothing left to read, so the buffer stays free
    return false;
}

void StreamSoundSource::downMix(const DownMix downMix)
{
    m_downMix = downMix;
}