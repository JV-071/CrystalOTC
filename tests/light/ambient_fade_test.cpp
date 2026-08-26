#include <gtest/gtest.h>

#include "client/ambientfade.h"

#include <cmath>

// The fade duration is transcribed from the official client, so what these tests guard is the
// transcription and the one property that makes the number work: it outlasts the interval the
// server sends light on. A silent drift either way gives players a visibly different dusk.

TEST(AmbientFade, DurationMatchesTheOfficialClient)
{
    // GRAPHICS/millisecondsForAmbientLightChange, read as the immediate 0x27d8 in the accessor
    // at 0x1009e1850 of the 15.32 macOS binary.
    EXPECT_EQ(AmbientFade::DURATION_MS, 10200);
    EXPECT_EQ(AmbientFade::SERVER_TICK_MS, 10000);
}

TEST(AmbientFade, TheFadeOutlastsTheServerTick)
{
    // This is the whole reason the constant is 10200 and not 10000. A fade must still be in
    // flight when the next world light lands, or the light comes to rest on each value for the
    // remainder of the tick and the ramp reads as a staircase again - which is the bug this
    // whole path exists to fix.
    EXPECT_GT(AmbientFade::DURATION_MS, AmbientFade::SERVER_TICK_MS);

    EXPECT_LT(AmbientFade::progress(AmbientFade::SERVER_TICK_MS), 1.f)
        << "a fade that finishes within one tick leaves the light standing still";
}

TEST(AmbientFade, ProgressRunsFromZeroToOneAndClamps)
{
    EXPECT_FLOAT_EQ(AmbientFade::progress(0), 0.f);
    EXPECT_FLOAT_EQ(AmbientFade::progress(AmbientFade::DURATION_MS), 1.f);
    EXPECT_FLOAT_EQ(AmbientFade::progress(AmbientFade::DURATION_MS * 10), 1.f);
    EXPECT_FLOAT_EQ(AmbientFade::progress(-500), 0.f);

    // Monotone in between, so the light only ever travels one way through a fade.
    float previous = -1.f;
    for (int64_t ms = 0; ms <= AmbientFade::DURATION_MS; ms += 250) {
        const float p = AmbientFade::progress(ms);
        EXPECT_GE(p, previous);
        previous = p;
    }
}

TEST(AmbientFade, EndpointsAreReproducedExactly)
{
    const auto from = AmbientFade::resolve(200, 166);  // golden hour
    const auto to = AmbientFade::resolve(89, 120);     // deep night blue

    const auto atStart = AmbientFade::blend(from, to, 0.f);
    EXPECT_EQ(atStart.base.r(), from.base.r());
    EXPECT_EQ(atStart.base.g(), from.base.g());
    EXPECT_EQ(atStart.base.b(), from.base.b());
    EXPECT_FLOAT_EQ(atStart.intensity, from.intensity);

    const auto atEnd = AmbientFade::blend(from, to, 1.f);
    EXPECT_EQ(atEnd.base.r(), to.base.r());
    EXPECT_EQ(atEnd.base.g(), to.base.g());
    EXPECT_EQ(atEnd.base.b(), to.base.b());
    EXPECT_FLOAT_EQ(atEnd.intensity, to.intensity);
}

TEST(AmbientFade, PaletteEntriesResolveToTheSixBySixCube)
{
    // index = r*36 + g*6 + b, each channel n*51. These four are the entries the day/night ramp
    // actually passes through, so an error in the cube would show up as the wrong sky.
    const auto white = AmbientFade::resolve(215, 255);
    EXPECT_EQ(white.base.r(), 255);
    EXPECT_EQ(white.base.g(), 255);
    EXPECT_EQ(white.base.b(), 255);

    // 207 is the entry CipSoft's own server sends at Tibia time 07:00, decoded from the
    // tutorial session dump shipped inside the client's graphics_resources.rcc.
    const auto cream = AmbientFade::resolve(207, 255);
    EXPECT_EQ(cream.base.r(), 255);
    EXPECT_EQ(cream.base.g(), 204);
    EXPECT_EQ(cream.base.b(), 153);

    const auto golden = AmbientFade::resolve(200, 166);
    EXPECT_EQ(golden.base.r(), 255);
    EXPECT_EQ(golden.base.g(), 153);
    EXPECT_EQ(golden.base.b(), 102);

    const auto night = AmbientFade::resolve(89, 120);
    EXPECT_EQ(night.base.r(), 102);
    EXPECT_EQ(night.base.g(), 102);
    EXPECT_EQ(night.base.b(), 255);
}

TEST(AmbientFade, BlendingTravelsThroughColoursNeitherEndpointWouldReachByIndex)
{
    // The point of resolving to RGB before interpolating. Golden hour (200) and mauve (123) are
    // both muted in blue, but the index halfway between them is 161 - and 161 is a saturated
    // violet whose blue channel is pinned at maximum. Interpolating indices would flash that on
    // the way past; interpolating the colours they name goes straight from one to the other.
    const auto from = AmbientFade::resolve(200, 166);
    const auto to = AmbientFade::resolve(123, 166);

    const auto mid = AmbientFade::blend(from, to, 0.5f);

    // Halfway between (255,153,102) and (153,102,153).
    EXPECT_NEAR(mid.base.r(), 204, 1);
    EXPECT_NEAR(mid.base.g(), 127, 1);
    EXPECT_NEAR(mid.base.b(), 127, 1);

    // What the index route would have produced, for contrast: entry 161 is (204, 102, 255), and
    // its blue outruns both endpoints instead of sitting between them.
    const auto byIndex = AmbientFade::resolve((200 + 123) / 2, 166);
    EXPECT_EQ(byIndex.base.b(), 255);
    EXPECT_GT(byIndex.base.b(), std::max(from.base.b(), to.base.b()));
    EXPECT_GT(byIndex.base.b(), mid.base.b());
}

TEST(AmbientFade, EveryChannelStaysBetweenItsEndpoints)
{
    // No overshoot anywhere in the ramp - a fade that leaves the interval between its endpoints
    // would flash a colour the server never asked for, which is exactly the artefact the whole
    // change is meant to remove.
    const auto from = AmbientFade::resolve(215, 250);
    const auto to = AmbientFade::resolve(89, 120);

    for (int64_t ms = 0; ms <= AmbientFade::DURATION_MS; ms += 100) {
        const auto v = AmbientFade::blend(from, to, AmbientFade::progress(ms));

        EXPECT_GE(v.base.rF(), std::min(from.base.rF(), to.base.rF()) - 1e-5f);
        EXPECT_LE(v.base.rF(), std::max(from.base.rF(), to.base.rF()) + 1e-5f);
        EXPECT_GE(v.base.gF(), std::min(from.base.gF(), to.base.gF()) - 1e-5f);
        EXPECT_LE(v.base.gF(), std::max(from.base.gF(), to.base.gF()) + 1e-5f);
        EXPECT_GE(v.base.bF(), std::min(from.base.bF(), to.base.bF()) - 1e-5f);
        EXPECT_LE(v.base.bF(), std::max(from.base.bF(), to.base.bF()) + 1e-5f);

        EXPECT_GE(v.intensity, to.intensity - 1e-3f);
        EXPECT_LE(v.intensity, from.intensity + 1e-3f);
    }
}

TEST(AmbientFade, AnInterruptedFadeResumesWithoutAJump)
{
    // Server values land every 10 s while a fade runs for 10.2, so nearly every fade is
    // interrupted. MapView restarts the next one from the blended midpoint rather than from the
    // last value the server sent; this is the property that makes that safe - picking up where
    // the eye left off is continuous, where restarting from the old endpoint would snap back.
    const auto day = AmbientFade::resolve(215, 250);
    const auto dusk = AmbientFade::resolve(200, 166);
    const auto night = AmbientFade::resolve(89, 120);

    const float atInterrupt = AmbientFade::progress(AmbientFade::SERVER_TICK_MS);
    const auto midpoint = AmbientFade::blend(day, dusk, atInterrupt);

    // The next fade's first sample is the midpoint itself, to within rounding.
    const auto resumed = AmbientFade::blend(midpoint, night, 0.f);
    EXPECT_NEAR(resumed.base.rF(), midpoint.base.rF(), 1e-6f);
    EXPECT_NEAR(resumed.base.gF(), midpoint.base.gF(), 1e-6f);
    EXPECT_NEAR(resumed.base.bF(), midpoint.base.bF(), 1e-6f);
    EXPECT_NEAR(resumed.intensity, midpoint.intensity, 1e-6f);
}
