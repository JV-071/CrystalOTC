#include <gtest/gtest.h>

#include <framework/rml/rmlmanager.h>

namespace {

    // The server and OTUI speak Latin-1, RmlUi speaks UTF-8: g_rml.utf8 / g_rml.latin1 are what
    // the Lua side uses to cross that border.
    TEST(RmlText, Latin1ToUtf8)
    {
        EXPECT_EQ(RmlManager::utf8("a\xE7\xE3o"), "a\xC3\xA7\xC3\xA3o"); // "ação"
    }

    TEST(RmlText, Utf8ToLatin1)
    {
        EXPECT_EQ(RmlManager::latin1("a\xC3\xA7\xC3\xA3o"), "a\xE7\xE3o");
    }

    TEST(RmlText, AsciiIsUntouched)
    {
        EXPECT_EQ(RmlManager::utf8("abc 123"), "abc 123");
        EXPECT_EQ(RmlManager::latin1("abc 123"), "abc 123");
    }

    // Text typed into an RmlUi field can hold anything; what Latin-1 cannot express is dropped,
    // never turned into garbage bytes or an exception.
    TEST(RmlText, CharactersOutsideLatin1AreDropped)
    {
        EXPECT_EQ(RmlManager::latin1("x\xE2\x82\xACy"), "xy"); // "x€y"
    }

    // Same policy as stdext::utf8_to_latin1 everywhere else in the client: malformed UTF-8 gives
    // an empty string, never an exception or half-converted bytes.
    TEST(RmlText, MalformedUtf8GivesEmptyTextWithoutThrowing)
    {
        std::string result = "untouched";
        EXPECT_NO_THROW(result = RmlManager::latin1("ab\xC3")); // truncated two-byte sequence
        EXPECT_EQ(result, "");
    }

}
