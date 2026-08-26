#include <gtest/gtest.h>

#include "client/protocolgame.h"
#include "client/protocolcodes.h"
#include "framework/net/outputmessage.h"

#include <vector>

// ClientChangeFightModes changed shape at 15.25 and the change is invisible on the wire: both
// layouts are a run of single bytes, so a server reading the wrong one sees no length mismatch
// and never complains. It just reads every field one place to the left. These tests exist
// because that happened - the boundary was written as 1530, the client runs 1525, and the
// server read the fight mode as the chase mode. Since the fight-mode byte is only ever 1, 2 or
// 3, chase was pinned on and "Stand While Fighting" did nothing at all.

namespace
{
    std::vector<uint8_t> encode(const int clientVersion, const bool pvpModeFeature,
                                const Otc::FightModes fightMode, const Otc::ChaseModes chaseMode,
                                const bool safeFight, const Otc::PVPModes pvpMode)
    {
        const auto& msg = std::make_shared<OutputMessage>();
        ProtocolGame::encodeChangeFightModes(msg, clientVersion, pvpModeFeature,
                                             fightMode, chaseMode, safeFight, pvpMode);

        const auto& buffer = msg->getBuffer();
        return { buffer.begin(), buffer.end() };
    }
}

TEST(FightModesWire, ModernLayoutStartsAtTheChaseByte)
{
    // 15.25 and later: [opcode][chase][secure][pvp][junk]. The trailing zero is what the
    // official client sends; crystalserver reads two bytes and stops, so it is parity only.
    EXPECT_EQ(encode(1525, true, Otc::FightBalanced, Otc::ChaseOpponent, true, Otc::YellowHand),
              (std::vector<uint8_t>{ Proto::ClientChangeFightModes, 1, 1, 2, 0 }));

    EXPECT_EQ(encode(1525, true, Otc::FightBalanced, Otc::DontChase, false, Otc::WhiteDove),
              (std::vector<uint8_t>{ Proto::ClientChangeFightModes, 0, 0, 0, 0 }));
}

TEST(FightModesWire, TheFightModeNeverReachesTheChaseSlot)
{
    // The regression in one assertion: standing still must put a 0 in the byte the server reads
    // as chase, whatever the fight mode happens to be. Every fight mode is non-zero, so a
    // layout that leaks it into that slot chases forever and cannot be switched off.
    for (const auto fightMode : { Otc::FightOffensive, Otc::FightBalanced, Otc::FightDefensive }) {
        const auto& wire = encode(1525, true, fightMode, Otc::DontChase, false, Otc::WhiteDove);

        ASSERT_GE(wire.size(), 2u);
        EXPECT_EQ(wire[1], 0) << "fight mode " << static_cast<int>(fightMode) << " leaked into the chase byte";
    }
}

TEST(FightModesWire, LegacyLayoutKeepsTheFightModeByte)
{
    // Before 15.25: [opcode][fight][chase][secure] and the PvP byte only with the feature on.
    EXPECT_EQ(encode(1524, true, Otc::FightDefensive, Otc::ChaseOpponent, true, Otc::RedFist),
              (std::vector<uint8_t>{ Proto::ClientChangeFightModes, 3, 1, 1, 3 }));

    EXPECT_EQ(encode(1524, false, Otc::FightDefensive, Otc::ChaseOpponent, true, Otc::RedFist),
              (std::vector<uint8_t>{ Proto::ClientChangeFightModes, 3, 1, 1 }));
}

TEST(FightModesWire, TheBoundaryIsTheVersionTheFightModeWasRemovedIn)
{
    // 1525, not the 1530 asset-catalogue number that sits beside it in the client log.
    EXPECT_EQ(Proto::FirstVersionWithoutFightMode, 1525);

    EXPECT_EQ(encode(1524, true, Otc::FightBalanced, Otc::DontChase, false, Otc::WhiteDove).size(), 5u);
    EXPECT_EQ(encode(1525, true, Otc::FightBalanced, Otc::DontChase, false, Otc::WhiteDove).size(), 5u);

    // Same length either side of the boundary, different meaning - which is exactly why this
    // drifted unnoticed. Only the second byte tells the two apart.
    EXPECT_EQ(encode(1524, true, Otc::FightBalanced, Otc::DontChase, false, Otc::WhiteDove)[1], Otc::FightBalanced);
    EXPECT_EQ(encode(1525, true, Otc::FightBalanced, Otc::DontChase, false, Otc::WhiteDove)[1], Otc::DontChase);
}
