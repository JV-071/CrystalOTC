#include <gtest/gtest.h>

#include "client/protocolgame.h"
#include "framework/net/inputmessage.h"

#include <string>
#include <vector>

// Cyclopedia -> Character -> Defence Stats used to render blank. The version boundary in the
// parser was written as 1530, but getClientVersion() returns the protocol from Servers_init,
// which is 1525 - so the `< 1530` branches always ran and the client read a u16 after
// defenseWheel plus a sixth mitigation double that 15.25 no longer sends. That is 10 bytes more
// than the message contains, so the parse threw and the page was never populated.
//
// The payload below is the real 0xDA sub-type 14 message captured off crystalserver 15.25,
// minus the header, opcode and sub-type/error bytes that parseCyclopediaCharacterInfo consumes
// before dispatching. It is the same wire layout the server writes in
// ProtocolGame::sendCyclopediaCharacterDefenceStats: five defence fields and five mitigation
// doubles, then the absorb list.

namespace
{
    // 112 payload bytes, captured live.
    const std::vector<uint8_t> DEFENCE_STATS_1525 = {
        0x04, 0xFF, 0xFF, 0xFF, 0x7F, 0x04, 0xFF, 0xFF, 0xFF, 0x7F, 0x04, 0xFF,
        0xFF, 0xFF, 0x7F, 0x04, 0xFF, 0xFF, 0xFF, 0x7F, 0x04, 0xFF, 0xFF, 0xFF,
        0x7F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0xFF, 0xFF, 0xFF, 0x7F,
        0x00, 0x00, 0x26, 0x00, 0x00, 0x00, 0x0B, 0x00, 0x1C, 0x00, 0x06, 0x0B,
        0x00, 0x00, 0x00, 0x04, 0x38, 0x00, 0x00, 0x80, 0x04, 0xFF, 0xFF, 0xFF,
        0x7F, 0x04, 0x1B, 0x00, 0x00, 0x80, 0x04, 0x0C, 0x00, 0x00, 0x80, 0x04,
        0xFF, 0xFF, 0xFF, 0x7F, 0x05, 0x04, 0x00, 0x04, 0x6A, 0x03, 0x00, 0x80,
        0x04, 0x03, 0x04, 0x47, 0x05, 0x00, 0x80, 0x04, 0x01, 0x04, 0xB7, 0x06,
        0x00, 0x80, 0x04, 0x04, 0x04, 0x37, 0xFF, 0xFF, 0x7F, 0x04, 0x06, 0x04,
        0x5D, 0x06, 0x00, 0x80,
    };

    InputMessagePtr messageOf(const std::vector<uint8_t>& payload)
    {
        // setBuffer leaves the read position past the data it just wrote, so rewind it to the
        // header offset - that is where the payload starts and where a real parse would begin.
        const auto& msg = std::make_shared<InputMessage>();
        msg->setBuffer(std::string(reinterpret_cast<const char*>(payload.data()), payload.size()));
        msg->setReadPos(msg->getMaxHeaderSize());
        return msg;
    }
}

TEST(CyclopediaDefenceStatsWire, ConsumesExactlyTheServerMessageAt1525)
{
    const auto& msg = messageOf(DEFENCE_STATS_1525);
    const auto data = ProtocolGame::decodeCyclopediaDefenceStats(msg, 1525);

    // The regression in one assertion: nothing left over, and nothing read past the end.
    EXPECT_EQ(msg->getUnreadSize(), 0) << "decoder did not land on the end of the message";
    EXPECT_EQ(data.resistances.size(), 5u);
}

TEST(CyclopediaDefenceStatsWire, DecodesTheValuesTheServerSent)
{
    const auto& msg = messageOf(DEFENCE_STATS_1525);
    const auto data = ProtocolGame::decodeCyclopediaDefenceStats(msg, 1525);

    EXPECT_EQ(data.armor, 38);
    EXPECT_EQ(data.defense, 11);
    EXPECT_EQ(data.defenseEquipment, 28);
    EXPECT_EQ(data.defenseSkillType, 0x06);
    EXPECT_EQ(data.shieldingSkill, 11);
    EXPECT_NEAR(data.mitigation, 0.0057, 1e-9);
    EXPECT_EQ(data.mitigationCombatTactics, 0.0); // not on the wire at 15.25

    // One resistance is negative - that is a damage *increase*, which the UI renders with its
    // own wording. It is here because a decoder that silently clamped would still pass above.
    ASSERT_EQ(data.resistances.size(), 5u);
    EXPECT_NEAR(data.resistances[3].value, -0.02, 1e-9);
}

TEST(CyclopediaDefenceStatsWire, OlderClientsStillReadTheTwoRemovedFields)
{
    // Pre-15.25 servers send a sixth defence field and a sixth mitigation double. Feeding the
    // 15.25 payload to the legacy path must therefore over-read - if it does not, the boundary
    // has stopped meaning anything and the 1525 test above would pass for the wrong reason.
    const auto& msg = messageOf(DEFENCE_STATS_1525);
    EXPECT_ANY_THROW(ProtocolGame::decodeCyclopediaDefenceStats(msg, 1524));
}
