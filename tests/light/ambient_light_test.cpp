#include <gtest/gtest.h>

#include "client/ambientlight.h"

// These guard a transcription, not a design. Every number below was read out of TLightMap and
// TEffectsQMLOptionsPage in the 15.32 macOS client, and each one is easy to "fix" into
// something that looks more sensible and is wrong: the 127, the tint that is not white, the
// inverted Clouds & Indoor float, and the fact that a roofed tile squares its factor.

TEST(AmbientLight, TheOptionIsQuantisedToHalfStrength)
{
    // (uint8)(level * 127), truncating. Not 255 - this is the whole reason a night at 100%
    // ambient is still only half lit in the official client.
    EXPECT_FLOAT_EQ(AmbientLight::SCALE, 127.f);

    EXPECT_EQ(AmbientLight::level(0.f), 0);
    EXPECT_EQ(AmbientLight::level(.25f), 31);   // the shipped default: 31, not 32 and not 63
    EXPECT_EQ(AmbientLight::level(.5f), 63);
    EXPECT_EQ(AmbientLight::level(1.f), 127);

    EXPECT_EQ(AmbientLight::level(-1.f), 0);
    EXPECT_EQ(AmbientLight::level(2.f), 127);
}

TEST(AmbientLight, AmbienceIsBlueOutsideAndNeutralUnderground)
{
    EXPECT_EQ(AmbientLight::TINT_SURFACE.r(), 200);
    EXPECT_EQ(AmbientLight::TINT_SURFACE.g(), 200);
    EXPECT_EQ(AmbientLight::TINT_SURFACE.b(), 255);

    EXPECT_EQ(AmbientLight::TINT_UNDERGROUND.r(), 255);
    EXPECT_EQ(AmbientLight::TINT_UNDERGROUND.g(), 255);
    EXPECT_EQ(AmbientLight::TINT_UNDERGROUND.b(), 255);
}

TEST(AmbientLight, UndergroundTheLiftIsExactlyTheOptionByte)
{
    // Below the sea floor the world light is gone and the tint is white, so the formula
    // collapses to the byte itself. This is the clearest statement of the ceiling: 100% of the
    // slider buys 127/255, just under half brightness, and never more.
    for (const float option : { 0.f, .25f, .5f, .75f, 1.f }) {
        const uint8_t expected = AmbientLight::level(option);
        const Color lit = AmbientLight::lift(Color::black, expected, AmbientLight::TINT_UNDERGROUND);

        EXPECT_EQ(lit.r(), expected);
        EXPECT_EQ(lit.g(), expected);
        EXPECT_EQ(lit.b(), expected);
    }

    EXPECT_EQ(AmbientLight::lift(Color::black, AmbientLight::level(1.f), AmbientLight::TINT_UNDERGROUND).r(), 127)
        << "full slider must not reach full brightness";
}

TEST(AmbientLight, DaylightLeavesNothingToLift)
{
    // A channel at 255 has no headroom, so the option costs nothing at noon however far it is
    // pushed. A floor-shaped implementation gets this right by accident; a lerp gets it right
    // by construction, and this is the test that tells the two apart.
    for (const float option : { 0.f, .5f, 1.f }) {
        const Color lit = AmbientLight::lift(Color::white, AmbientLight::level(option), AmbientLight::TINT_SURFACE);

        EXPECT_EQ(lit.r(), 255);
        EXPECT_EQ(lit.g(), 255);
        EXPECT_EQ(lit.b(), 255);
    }
}

TEST(AmbientLight, OutdoorAmbienceCarriesTheBlueCast)
{
    // A dim night world light at the shipped 25%. Values hand-computed from the client's
    // integer arithmetic; the blue channel running ahead of the other two is the visible part.
    const Color night(40, 40, 40);
    const Color lit = AmbientLight::lift(night, AmbientLight::level(.25f), AmbientLight::TINT_SURFACE);

    EXPECT_EQ(lit.r(), 60);
    EXPECT_EQ(lit.g(), 60);
    EXPECT_EQ(lit.b(), 66);

    const Color full = AmbientLight::lift(night, AmbientLight::level(1.f), AmbientLight::TINT_SURFACE);

    EXPECT_EQ(full.r(), 123);
    EXPECT_EQ(full.g(), 123);
    EXPECT_EQ(full.b(), 147);
}

TEST(AmbientLight, TheLiftIsMonotoneAndNeverDarkens)
{
    // Whatever the setting, ambience only ever adds. A regression that let it subtract would
    // show up as an interior going darker when the player raises the slider.
    const Color base(40, 55, 70);
    int previous = -1;

    for (int pct = 0; pct <= 100; ++pct) {
        const Color lit = AmbientLight::lift(base, AmbientLight::level(pct / 100.f), AmbientLight::TINT_SURFACE);

        EXPECT_GE(lit.r(), base.r());
        EXPECT_GE(lit.g(), base.g());
        EXPECT_GE(lit.b(), base.b());
        EXPECT_GE(static_cast<int>(lit.r()), previous);

        previous = lit.r();
    }
}

TEST(AmbientLight, CloudsAndIndoorIsStoredInverted)
{
    // The option's float is the share of light a tile KEEPS: 1 at the "(off)" end, 0.5 at the
    // far one. `kept` here is what the client stores, so these are its own numbers.
    EXPECT_FLOAT_EQ(AmbientLight::keptUnderAttenuation(0.f), 1.f);
    EXPECT_FLOAT_EQ(AmbientLight::keptUnderAttenuation(.5f), .75f);   // the shipped 50%
    EXPECT_FLOAT_EQ(AmbientLight::keptUnderAttenuation(1.f), .5f);

    // The default the client ships is 0.75 - which its own slider draws as 50%, not 75%.
    EXPECT_FLOAT_EQ(AmbientLight::keptUnderAttenuation(.5f), .75f);
}

TEST(AmbientLight, ARoofSquaresTheAttenuation)
{
    // The one slider feeds both of the client's stored keys and it multiplies them together,
    // so a roofed tile is shaded twice over. At the shipped setting that is 0.5625, not 0.75.
    EXPECT_FLOAT_EQ(AmbientLight::indoorFactor(0.f), 1.f);
    EXPECT_FLOAT_EQ(AmbientLight::indoorFactor(.5f), .5625f);
    EXPECT_FLOAT_EQ(AmbientLight::indoorFactor(1.f), .25f);

    // Always at least as dark as an open tile under the deepest cloud, never darker than black.
    for (int pct = 0; pct <= 100; ++pct) {
        const float attenuation = pct / 100.f;

        EXPECT_LE(AmbientLight::indoorFactor(attenuation), AmbientLight::keptUnderAttenuation(attenuation));
        EXPECT_GE(AmbientLight::indoorFactor(attenuation), 0.f);
    }
}

TEST(AmbientLight, TheOptionOffCostsNothingAtAll)
{
    // Exactly 1 and exactly 0, not almost. LightView keys its pixel cache on the cloud depth
    // and skips mixing time into that key while it is zero, so a stray epsilon here would put
    // the light grid back on the every-frame path for everyone who turned the option off.
    EXPECT_EQ(1.f - AmbientLight::keptUnderAttenuation(0.f), 0.f);
    EXPECT_EQ(AmbientLight::indoorFactor(0.f), 1.f);
}

TEST(AmbientLight, BrightestChannelSeesTheBlueOne)
{
    // A luma would weight blue at about 7% and call a blue-tinted ambience black, which would
    // switch the light pass off in exactly the case it is drawn for.
    EXPECT_EQ(AmbientLight::brightestChannel(Color(0, 0, 0)), 0);
    EXPECT_EQ(AmbientLight::brightestChannel(Color(99, 99, 127)), 127);
    EXPECT_EQ(AmbientLight::brightestChannel(Color::white), 255);
}
