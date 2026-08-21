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

#ifdef CRYSTALOTC_COCOA_WINDOW

#include "metalcontext.h"

#include <framework/core/logger.h>

namespace
{
    // Enough for a busy frame's geometry without a mid-frame growth on the first few frames;
    // it grows on demand anyway, so this is a warm-up figure rather than a limit.
    constexpr uint32_t INITIAL_ARENA_BYTES = 1u << 20;

    uint32_t alignUp(const uint32_t value, const size_t alignment)
    {
        const auto a = static_cast<uint32_t>(alignment);
        return (value + a - 1u) & ~(a - 1u);
    }
}

bool MetalContext::initialize(const NativeSurface& surface)
{
    if (surface.type != NativeSurfaceType::CocoaMetalLayer || !surface.layer || !surface.device) {
        g_logger.info("[metal] the platform window offers no Metal layer");
        return false;
    }

    // ARC is on for this translation unit and off for the window that produced these pointers,
    // so the bridging casts are the ones that transfer nothing: the layer belongs to the view
    // and the device to the window, and both outlive this object by construction.
    m_layer = (__bridge CAMetalLayer*)surface.layer;
    m_device = (__bridge id<MTLDevice>)surface.device;

    if (!m_device) {
        g_logger.warning("[metal] the platform window's Metal device is null");
        return false;
    }

    m_queue = [m_device newCommandQueue];
    if (!m_queue) {
        g_logger.warning("[metal] could not create a command queue on '{}'", [[m_device name] UTF8String]);
        m_device = nil;
        m_layer = nil;
        return false;
    }

    [m_queue setLabel:@"CrystalOTC"];

    // The layer keeps framebufferOnly = YES, which is what the window set it to and what lets
    // the compositor treat the drawable as a pure presentation surface. It stays true because
    // this backend never reads a drawable: it renders into its own offscreen backbuffer and
    // blits that into the drawable at the end of the frame, which is also what makes a screenshot
    // after presentation possible at all.

    m_frameSlots = dispatch_semaphore_create(MetalABI::MAX_FRAMES_IN_FLIGHT);
    m_arenas.assign(MetalABI::MAX_FRAMES_IN_FLIGHT, FrameArena{});
    m_frameIndex = 0;

    g_logger.info("[metal] device '{}' ready ({} frames in flight)",
                  [[m_device name] UTF8String], MetalABI::MAX_FRAMES_IN_FLIGHT);
    return true;
}

void MetalContext::shutdown()
{
    if (m_frameSlots) {
        // Drain every outstanding frame before letting the arenas go: their buffers are still
        // being read by whatever the GPU has not finished.
        for (uint32_t i = 0; i < MetalABI::MAX_FRAMES_IN_FLIGHT; ++i)
            dispatch_semaphore_wait(m_frameSlots, DISPATCH_TIME_FOREVER);
        for (uint32_t i = 0; i < MetalABI::MAX_FRAMES_IN_FLIGHT; ++i)
            dispatch_semaphore_signal(m_frameSlots);
    }

    m_arenas.clear();
    m_frameSlots = nil;
    m_queue = nil;
    m_device = nil;
    m_layer = nil;
}

Size MetalContext::drawableSize() const
{
    if (!m_layer)
        return {};

    const CGSize size = m_layer.drawableSize;
    return Size(static_cast<int>(size.width), static_cast<int>(size.height));
}

id<MTLCommandBuffer> MetalContext::beginFrame()
{
    if (!isReady())
        return nil;

    dispatch_semaphore_wait(m_frameSlots, DISPATCH_TIME_FOREVER);

    m_frameIndex = (m_frameIndex + 1) % MetalABI::MAX_FRAMES_IN_FLIGHT;
    resetFrameArena();

    id<MTLCommandBuffer> commands = [m_queue commandBuffer];
    [commands setLabel:@"CrystalOTC frame"];
    return commands;
}

void MetalContext::endFrame(id<MTLCommandBuffer> commands)
{
    if (!commands)
        return;

    // Captured by value so the block keeps the semaphore alive even if the context is torn down
    // while this frame is still executing.
    dispatch_semaphore_t slots = m_frameSlots;
    [commands addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        if (buffer.error)
            g_logger.warning("[metal] frame failed: {}", [[buffer.error localizedDescription] UTF8String]);
        dispatch_semaphore_signal(slots);
    }];

    [commands commit];
}

id<MTLCommandBuffer> MetalContext::utilityCommandBuffer(NSString* label)
{
    if (!isReady())
        return nil;

    id<MTLCommandBuffer> commands = [m_queue commandBuffer];
    [commands setLabel:label];
    return commands;
}

void MetalContext::resetFrameArena()
{
    if (m_frameIndex < m_arenas.size())
        m_arenas[m_frameIndex].used = 0;
}

MetalContext::BufferSlice MetalContext::allocate(const void* data, const size_t bytes, const size_t alignment)
{
    if (!isReady() || bytes == 0 || m_frameIndex >= m_arenas.size())
        return {};

    auto& arena = m_arenas[m_frameIndex];
    const uint32_t offset = alignUp(arena.used, alignment);
    const uint32_t required = offset + static_cast<uint32_t>(bytes);

    if (!arena.buffer || required > static_cast<uint32_t>([arena.buffer length])) {
        // Growth doubles from whatever this slot already had, so a frame that allocates in many
        // small pieces does not reallocate on each one. Only this frame index touches this
        // buffer, and this frame index is free by definition - the semaphore said so.
        //
        // Growing MID-FRAME abandons the old buffer with the cursor reset to zero, which reads
        // like it would corrupt everything already written this frame and does not: a BufferSlice
        // holds its buffer strongly, so slices handed out before the growth keep the old buffer
        // alive at the offsets they were given, and anything already encoded is retained by the
        // command buffer until it completes. The old allocation is released when the last slice
        // referring to it is dropped, which is the next frame.
        uint32_t capacity = arena.buffer ? static_cast<uint32_t>([arena.buffer length]) : INITIAL_ARENA_BYTES;
        while (capacity < required)
            capacity *= 2;

        arena.buffer = [m_device newBufferWithLength:capacity options:MTLResourceStorageModeShared];
        if (!arena.buffer)
            return {};

        [arena.buffer setLabel:[NSString stringWithFormat:@"CrystalOTC vertices %u", m_frameIndex]];
        arena.used = 0;

        // The alignment was computed against the old cursor; recompute against the reset one.
        return allocate(data, bytes, alignment);
    }

    if (data)
        std::memcpy(static_cast<uint8_t*>([arena.buffer contents]) + offset, data, bytes);

    arena.used = required;
    return { arena.buffer, offset };
}

#endif // CRYSTALOTC_COCOA_WINDOW
