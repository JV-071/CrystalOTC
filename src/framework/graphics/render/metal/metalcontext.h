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

#ifdef CRYSTALOTC_COCOA_WINDOW

#include "metalinternal.h"

#include <framework/platform/platformwindow.h>

#include <vector>

/*
 * MetalContext - the device, the queue, and the frame clock.
 *
 * It owns everything whose lifetime is "as long as the window exists" (device, command queue,
 * layer) and everything whose lifetime is "one frame" (command buffer, transient vertex
 * storage). What it deliberately does not own is anything a DRAW refers to - textures,
 * pipelines, targets - which live in the resource and pipeline caches beside it.
 *
 * The frame clock is a counting semaphore, the pattern Apple's "Synchronizing CPU and GPU work"
 * describes: the CPU may build up to MAX_FRAMES_IN_FLIGHT frames ahead of the GPU, and each
 * frame's completion handler releases one slot back. Without it the CPU would either stall on
 * every frame (waitUntilCompleted) or overwrite the transient buffers a frame still in flight is
 * reading, which is the same bug with a longer fuse.
 */
class MetalContext
{
public:
    bool initialize(const NativeSurface& surface);
    void shutdown();

    [[nodiscard]] bool isReady() const { return m_queue != nil; }
    [[nodiscard]] id<MTLDevice> device() const { return m_device; }
    [[nodiscard]] CAMetalLayer* layer() const { return m_layer; }

    // Size of the layer's drawable, in pixels. The window keeps this in step with the backing
    // store; the backend sizes its offscreen backbuffer from the FRAME instead, and the two are
    // reconciled at present time by a blit that simply does nothing when they disagree.
    [[nodiscard]] Size drawableSize() const;

    // Blocks until a frame slot is free, then opens a command buffer. Null only if the context
    // is not ready.
    id<MTLCommandBuffer> beginFrame();

    // Commits, and arranges for the frame slot to be released when the GPU is done with it.
    void endFrame(id<MTLCommandBuffer> commands);

    // One-off work outside the frame clock: readbacks, and the initial upload of a texture that
    // no frame has referenced yet. Caller commits and, if it needs the result, waits.
    id<MTLCommandBuffer> utilityCommandBuffer(NSString* label);

    // --- transient per-frame storage -----------------------------------------------------
    // The GL path draws straight out of client memory, with no buffer objects at all. Metal
    // needs the bytes in an MTLBuffer, so each in-flight frame owns one growable arena that is
    // reset - not freed - at the start of every frame it serves. A frame that needs more than
    // the current allocation grows its own buffer, which is safe precisely because no other
    // frame may be using that slot.
    struct BufferSlice
    {
        id<MTLBuffer> buffer{ nil };
        uint32_t offset{ 0 };

        [[nodiscard]] bool isValid() const { return buffer != nil; }
    };

    BufferSlice allocate(const void* data, size_t bytes, size_t alignment = 16);

private:
    void resetFrameArena();

    id<MTLDevice> m_device{ nil };
    id<MTLCommandQueue> m_queue{ nil };
    CAMetalLayer* m_layer{ nil };

    dispatch_semaphore_t m_frameSlots{ nil };
    uint32_t m_frameIndex{ 0 };

    struct FrameArena
    {
        id<MTLBuffer> buffer{ nil };
        uint32_t used{ 0 };
    };

    std::vector<FrameArena> m_arenas;
};

#endif // CRYSTALOTC_COCOA_WINDOW
