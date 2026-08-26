#include <gtest/gtest.h>

#include "client/cloudfield.h"

#include <cmath>
#include <numeric>

// The cloud field is transcribed from TLightMap in the official client, so what these tests
// guard is the transcription rather than any behaviour of our own: every constant was read out
// of the 15.32 macOS binary, and one drifting silently gives players a different sky from the
// one the official client shows them.

TEST(CloudField, WaveTableMatchesTheOfficialClient)
{
    EXPECT_EQ(CloudField::SPEED_FACTOR, 500);

    ASSERT_EQ(CloudField::WAVES.size(), 3u);

    EXPECT_EQ(CloudField::WAVES[0].period, 15500);
    EXPECT_FLOAT_EQ(CloudField::WAVES[0].dirX, 0.5f);
    EXPECT_FLOAT_EQ(CloudField::WAVES[0].dirY, 1.0f);
    EXPECT_FLOAT_EQ(CloudField::WAVES[0].amplitude, 0.25f);

    EXPECT_EQ(CloudField::WAVES[1].period, 21500);
    EXPECT_FLOAT_EQ(CloudField::WAVES[1].dirX, 0.25f);
    EXPECT_FLOAT_EQ(CloudField::WAVES[1].dirY, -0.25f);
    EXPECT_FLOAT_EQ(CloudField::WAVES[1].amplitude, 0.5f);

    EXPECT_EQ(CloudField::WAVES[2].period, 33500);
    EXPECT_FLOAT_EQ(CloudField::WAVES[2].dirX, 0.125f);
    EXPECT_FLOAT_EQ(CloudField::WAVES[2].dirY, 0.25f);
    EXPECT_FLOAT_EQ(CloudField::WAVES[2].amplitude, 1.0f);

    EXPECT_EQ(CloudField::PHASE_PERIOD_LCM, 44655500);
}

TEST(CloudField, TheFoldSpanIsTrulyTheLeastCommonMultiple)
{
    // coverage() folds time into PHASE_PERIOD_LCM to keep the floats small. That is only free
    // if the span really is a whole number of rotations for every wave - otherwise the fold
    // itself introduces a seam, once every twelve hours, that no other test here would see.
    for (const auto& wave : CloudField::WAVES)
        EXPECT_EQ(CloudField::PHASE_PERIOD_LCM % wave.period, 0)
            << "period " << wave.period << " does not divide the fold span";

    // And least, not merely common: the per-wave rotation counts share no factor, which is what
    // makes the pattern take the full twelve hours to repeat instead of some shorter cycle.
    int64_t g = 0;
    for (const auto& wave : CloudField::WAVES)
        g = std::gcd(g, CloudField::PHASE_PERIOD_LCM / wave.period);

    EXPECT_EQ(g, 1) << "the fold span is a common multiple but not the least one";
}

TEST(CloudField, CoverageMatchesTheDisassembledField)
{
    // Sampled from the recovered algorithm in double precision, then chosen for sensitivity:
    // every single-constant mutation tried against this table - any period, any direction, any
    // amplitude - moves each of these points by at least 0.37, so nothing here can pass by
    // coincidence. All eight sit in the responsive mid-band rather than clamped at an end.
    struct Sample { int64_t t; float x, y; float expected; };

    static constexpr Sample GOLDEN[] = {
        {  65000, 21.f, -3.f, 0.449834f },
        { 106250, 24.f,  0.f, 0.576595f },
        { 125000,  9.f, 15.f, 0.544023f },
        { 138750, 15.f,  0.f, 0.532924f },
        { 142750, 12.f, 24.f, 0.449964f },
        { 160500,  0.f, 18.f, 0.576494f },
        { 179750,  3.f,  6.f, 0.420788f },
        { 287500, 24.f, -6.f, 0.476849f },
    };

    // Loose enough for the float32 rounding the client itself has - it uses float and sinf too,
    // so matching its precision is part of matching it - and three orders tighter than the
    // smallest shift any wrong constant produces.
    for (const auto& s : GOLDEN)
        EXPECT_NEAR(CloudField::coverage(s.t, s.x, s.y), s.expected, 2e-3f)
            << "at t=" << s.t << " x=" << s.x << " y=" << s.y;
}

TEST(CloudField, PiStaysTheClientsHardCodedThreePointOneFour)
{
    // Its own test because the golden table above cannot see this one: swapping in a real pi
    // shifts phase by only 0.05%, which stays inside that table's float32 tolerance. Here the
    // sample is chosen where the difference peaks - about 0.007 of coverage - and the tolerance
    // is tightened to match, which is still a hundred times the float32 noise at these small
    // coordinates. Fidelity to the client, not a claim that anyone could see it.
    EXPECT_NEAR(CloudField::coverage(232250, -2.f, 2.f), 0.753041f, 1e-3f);
    EXPECT_NEAR(CloudField::coverage(300750, 0.f, 6.f), 0.235587f, 1e-3f);
}

TEST(CloudField, CoverageStaysWithinItsRange)
{
    for (int64_t t = 0; t < 400000; t += 977) {
        for (int x = -30; x <= 30; x += 7) {
            const float v = CloudField::coverage(t, static_cast<float>(x), static_cast<float>(x * 2));
            ASSERT_GE(v, 0.f);
            ASSERT_LE(v, 1.f);
        }
    }
}

TEST(CloudField, CrestsAreDiscardedSoOpenSunIsCommon)
{
    // Only troughs darken. Relaxing the one-sided clamp into a symmetric one would make full-sun
    // tiles vanish and the map would read as noisy rather than as sunlit ground with shadows
    // crossing it, so the count below collapses to zero if that ever happens.
    int atFullSun = 0, total = 0;

    for (int64_t t = 0; t < 120000; t += 1500) {
        for (int x = 0; x < 24; ++x) {
            for (int y = 0; y < 12; ++y) {
                if (CloudField::coverage(t, static_cast<float>(x), static_cast<float>(y)) >= 1.f)
                    ++atFullSun;
                ++total;
            }
        }
    }

    EXPECT_GT(atFullSun, total / 4);
}

TEST(CloudField, ShadowsDriftRatherThanFlicker)
{
    // Net motion is about half a tile per second, so one 50 ms step - the interval LightView
    // samples at - may only nudge a tile's coverage. A step that jumps is what a scroll divisor
    // transcribed an order of magnitude wrong looks like from here.
    for (int64_t t = 0; t < 60000; t += 500) {
        const float a = CloudField::coverage(t, 12.f, 9.f);
        const float b = CloudField::coverage(t + 50, 12.f, 9.f);
        EXPECT_LT(std::fabs(a - b), 0.2f) << "coverage jumped between samples at t=" << t;
    }
}
