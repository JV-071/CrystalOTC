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

#include "localplayer.h"

#include "container.h"
#include "game.h"
#include "gameconfig.h"
#include "item.h"
#include "map.h"
#include "tile.h"
#include "framework/core/clock.h"
#include "framework/core/configmanager.h"
#include "framework/core/eventdispatcher.h"

namespace
{
    // Opt-in walk timing ([debug] perfLog = 1 in config.ini) for hunting walk stutters on player
    // machines. Only the local player goes through here and everything runs on the map thread,
    // so a plain static is enough. With the flag off none of this is touched.
    struct WalkTimeLog
    {
        static constexpr ticks_t WINDOW_MILLIS = 10 * 1000;
        // a pause between two steps shorter than this is not a stall
        static constexpr ticks_t STALL_MILLIS = 20;
        // a pause longer than this is the player stopping, not a stall
        static constexpr ticks_t CONTINUOUS_MILLIS = 500;
        static constexpr uint32_t MAX_LINES = 10;

        std::deque<std::pair<Position, ticks_t>> sent;
        ticks_t lastStepEnd{ 0 };
        ticks_t windowStart{ 0 };
        uint32_t steps{ 0 };
        uint32_t serverSteps{ 0 };
        uint32_t stalls{ 0 };
        uint32_t confirms{ 0 };
        uint32_t lateConfirms{ 0 };
        uint32_t cancels{ 0 };
        uint32_t timeouts{ 0 };
        uint32_t lines{ 0 };
        // set while cancelWalk runs the prewalk timeout handler by hand
        bool cancelling{ false };
        ticks_t maxStall{ 0 };
        ticks_t rttSum{ 0 };
        ticks_t maxRtt{ 0 };

        static bool enabled() { return g_configs.getPublicConfig().debug.perfLog; }

        bool canLogLine() { return lines++ < MAX_LINES; }

        void stepStarted(LocalPlayer& player, const bool server, const size_t unconfirmed)
        {
            const ticks_t now = stdext::millis();

            if (lastStepEnd != 0) {
                const ticks_t gap = now - lastStepEnd;
                if (gap >= STALL_MILLIS && gap < CONTINUOUS_MILLIS) {
                    ++stalls;
                    maxStall = std::max(maxStall, gap);
                    if (canLogLine()) {
                        g_logger.info("[walk] stall {} ms before {} step, {} unconfirmed, step {} ms, ping {} ms",
                                      gap, server ? "server" : "client", unconfirmed, player.getStepDuration(), g_game.getPing());
                    }
                }
            }

            lastStepEnd = 0;
            ++(server ? serverSteps : steps);
            reportIfDue(player, now);
        }

        void preWalkSent(const Position& pos)
        {
            sent.emplace_back(pos, stdext::millis());
            if (sent.size() > 8)
                sent.pop_front();
        }

        void preWalkConfirmed(LocalPlayer& player, const Position& pos, const bool animationDone)
        {
            const ticks_t now = stdext::millis();

            while (!sent.empty() && sent.front().first != pos)
                sent.pop_front();

            if (!sent.empty()) {
                const ticks_t rtt = now - sent.front().second;
                sent.pop_front();
                ++confirms;
                rttSum += rtt;
                maxRtt = std::max(maxRtt, rtt);
            }

            // the step animation finished before the server confirmed the step
            if (animationDone)
                ++lateConfirms;

            reportIfDue(player, now);
        }

        void dropped(const bool timeout, const size_t unconfirmed)
        {
            sent.clear();
            ++(timeout ? timeouts : cancels);
            if (canLogLine()) {
                g_logger.info("[walk] {}, {} unconfirmed steps", timeout ? "prewalk timeout" : "step cancelled",
                              unconfirmed);
            }
        }

        void reportIfDue(LocalPlayer& player, const ticks_t now)
        {
            if (windowStart == 0)
                windowStart = now;

            if (now - windowStart < WINDOW_MILLIS)
                return;

            if (steps + serverSteps > 0) {
                g_logger.info("[walk] last {} s: steps {} (server {}), stalls {} (max {} ms), confirms {} (rtt avg {} ms, max {} ms, after animation end {}), cancels {}, timeouts {}, step {} ms, ping {} ms",
                              (now - windowStart) / 1000, steps, serverSteps, stalls, maxStall, confirms,
                              confirms ? rttSum / confirms : 0, maxRtt, lateConfirms, cancels, timeouts,
                              player.getStepDuration(), g_game.getPing());
            }

            steps = serverSteps = stalls = confirms = lateConfirms = cancels = timeouts = lines = 0;
            maxStall = rttSum = maxRtt = 0;
            windowStart = now;
        }
    };

    WalkTimeLog s_walkLog;
}

void LocalPlayer::lockWalk(const uint16_t millis)
{
    m_walkLockExpiration = std::max<ticks_t>(m_walkLockExpiration, g_clock.millis() + millis);
}

bool LocalPlayer::canWalk(const bool ignoreLock)
{
    // Prevent movement if the player is dead
    if (isDead())
        return false;

    // Prevent movement if walking is locked, unless ignored
    if (isWalkLocked() && !ignoreLock)
        return false;

    // Ensure movement synchronization with the server
    if (g_game.getWalkMaxSteps() > 0) {
        if (m_preWalks.size() > g_game.getWalkMaxSteps())
            return false;
    } else if (getPosition() != getServerPosition())
        return false;

    // Handle ongoing movement cases
    if (isWalking()) {
        if (isAutoWalking()) return true;  // Allow auto-walking
        if (isPreWalking()) return false;  // Prevent pre-walk interruptions
    }

    // allow only if walk done, ex. diagonals may need additional ticks before taking another step
    return m_walkTimer.ticksElapsed() >= getNextStepWait();
}

// Time after the last step was sent at which the next one may be sent.
// The server takes a step when its walk delay ends (the step cost, 3x after a diagonal) and queues a
// step that arrives earlier; a newer step replaces the queued one (startAutoWalk clears the list).
// Like the official client, the step after a diagonal is sent diagonal-next-step-wait regular steps
// after it (2 of 3) and waits out the rest in the server queue. The time a step is queued is added,
// so the step after it is sent only once the server took the queued one: at most one step is queued
// and it is never replaced.
uint16_t LocalPlayer::getNextStepWait()
{
    uint32_t wait = getStepDuration();
    const uint32_t regular = getStepDuration(true);
    if (wait > regular) { // the last step was a diagonal
        const double factor = std::max<double>(1.0, g_gameConfig.getPlayerDiagonalNextStepWait());
        wait = std::min<uint32_t>(wait, static_cast<uint32_t>(regular * factor));
    }

    return static_cast<uint16_t>(std::min<uint32_t>(wait + m_walkQueueDelay, UINT16_MAX));
}

int LocalPlayer::getWalkWaitLeft()
{
    return std::max<int>(0, static_cast<int>(getNextStepWait()) - static_cast<int>(m_walkTimer.ticksElapsed()));
}

void LocalPlayer::walk(const Position& oldPos, const Position& newPos)
{
    m_autoWalkRetries = 0;

    if (isPreWalking() && newPos == m_preWalks.front()) {
        if (WalkTimeLog::enabled())
            s_walkLog.preWalkConfirmed(*this, newPos, !isWalking());

        m_preWalks.pop_front();

        // The step animation already ended, so a held walk may be waiting for this confirmation
        // (canWalk allows only a limited number of unconfirmed steps). Let it continue now
        // instead of on its next retry.
        if (!isWalking())
            callLuaField("onWalkConfirm");
        return;
    }

    cancelAdjustInvalidPosEvent();
    m_preWalks.clear();
    m_serverWalk = true;
    m_walkQueueDelay = 0;

    if (WalkTimeLog::enabled())
        s_walkLog.stepStarted(*this, true, 0);

    Creature::walk(oldPos, newPos);
}

void LocalPlayer::preWalk(Otc::Direction direction)
{
    m_lastMapDuration = -1;

    if (WalkTimeLog::enabled())
        s_walkLog.stepStarted(*this, false, m_preWalks.size());

    // A step sent before the server is ready for it (the step after a diagonal, see getNextStepWait)
    // waits in the server queue until the walk delay of the previous step ends.
    m_walkQueuePrevCost = getStepDuration();
    const int queued = static_cast<int>(m_walkQueueDelay) + m_walkQueuePrevCost - static_cast<int>(m_walkTimer.ticksElapsed());
    m_walkQueueDelay = static_cast<uint16_t>(std::clamp<int>(queued, 0, UINT16_MAX));

    const auto& oldPos = getPosition();
    Creature::walk(oldPos, m_preWalks.emplace_back(oldPos.translatedToDirection(direction)));

    if (WalkTimeLog::enabled())
        s_walkLog.preWalkSent(m_preWalks.back());

    Creature::onPositionChange(getLastStepToPosition(), getLastStepFromPosition());
    registerAdjustInvalidPosEvent();
}

// The server computes the walk delay of the previous step with the speed it has when it checks it,
// so a slower speed (paralyze) set while the last step still waits in its queue makes the server hold
// that step longer. The step after it has to wait as long, or it would reach the server while the
// queued one is still there and replace it (snap back). The speed change arrives before the
// confirmation of the queued step only when the server changed it before taking the step.
void LocalPlayer::onSpeedChangeWhileQueued(const uint16_t oldStepDuration)
{
    if (m_walkQueueDelay == 0 || !isPreWalking() || oldStepDuration == 0)
        return;

    const uint16_t newStepDuration = getStepDuration(true);
    if (newStepDuration <= oldStepDuration) // faster: the server still takes the step when planned
        return;

    const uint32_t prevCost = static_cast<uint32_t>(m_walkQueuePrevCost) * newStepDuration / oldStepDuration;
    m_walkQueueDelay = static_cast<uint16_t>(std::min<uint32_t>(m_walkQueueDelay + prevCost - m_walkQueuePrevCost, UINT16_MAX));
    m_walkQueuePrevCost = static_cast<uint16_t>(std::min<uint32_t>(prevCost, UINT16_MAX));
}

void LocalPlayer::onWalking() {
    if (isPreWalking()) {
        if (const auto& tile = g_map.getTile(getPosition())) {
            for (const auto& creature : tile->getWalkingCreatures()) {
                // Cancel pre-walk movement if the local player tries to walk on an unwalkable tile.
                if (creature.get() != this && creature->getPosition() == getPosition() && !creature->isPassable()) {
                    cancelWalk();
                    g_map.notificateTileUpdate(getPosition(), asLocalPlayer(), Otc::OPERATION_CLEAN);
                    break;
                }
            }
        }
    }
}

void LocalPlayer::registerAdjustInvalidPosEvent() {
    cancelAdjustInvalidPosEvent();
    m_adjustInvalidPosEvent = g_dispatcher.scheduleEvent([this, self = asLocalPlayer()] {
        if (WalkTimeLog::enabled() && !s_walkLog.cancelling)
            s_walkLog.dropped(true, m_preWalks.size());

        m_preWalks.clear();
        g_game.resetMapUpdatedAt();
        m_adjustInvalidPosEvent = nullptr;
    }, std::min<int>(std::max<int>(getStepDuration(), g_game.getPing()) + 100, 1000) + m_walkQueueDelay); // a queued step is confirmed later
}

void LocalPlayer::cancelAdjustInvalidPosEvent() {
    if (!m_adjustInvalidPosEvent) return;
    m_adjustInvalidPosEvent->cancel();
    m_adjustInvalidPosEvent = nullptr;
}

bool LocalPlayer::retryAutoWalk()
{
    if (!m_autoWalkDestination.isValid()) {
        return false;
    }

    g_game.stop();

    if (m_autoWalkRetries <= 3) {
        if (m_autoWalkContinueEvent)
            m_autoWalkContinueEvent->cancel();

        m_autoWalkContinueEvent = g_dispatcher.scheduleEvent(
            [thisPtr = asLocalPlayer(), autoWalkDest = m_autoWalkDestination] { thisPtr->autoWalk(autoWalkDest, true); }, 200
        );

        m_autoWalkRetries += 1;

        return true;
    }

    m_autoWalkDestination = {};
    return false;
}

void LocalPlayer::cancelWalk(const Otc::Direction direction)
{
    // only cancel client side walks
    if (isWalking() && isPreWalking())
        stopWalk();

    g_map.notificateCameraMove(m_walkOffset);

    if (WalkTimeLog::enabled())
        s_walkLog.dropped(false, m_preWalks.size());

    if (m_adjustInvalidPosEvent) {
        s_walkLog.cancelling = true;
        m_adjustInvalidPosEvent->execute();
        s_walkLog.cancelling = false;
    }

    lockWalk();
    if (retryAutoWalk()) return;

    // turn to the cancel direction
    if (direction != Otc::InvalidDirection)
        setDirection(direction);

    callLuaField("onCancelWalk", direction);
}

bool LocalPlayer::autoWalk(const Position& destination, const bool retry)
{
    // reset state
    m_autoWalkDestination = {};
    m_lastAutoWalkPosition = {};
    if (m_autoWalkContinueEvent)
        m_autoWalkContinueEvent->cancel();
    m_autoWalkContinueEvent = nullptr;

    if (!retry)
        m_autoWalkRetries = 0;

    if (destination == m_position)
        return true;

    m_autoWalkDestination = destination;

    g_map.findPathAsync(m_position, destination, [self = asLocalPlayer()](const auto& result) {
        if (self->m_autoWalkDestination != result->destination)
            return;

        if (result->status != Otc::PathFindResultOk) {
            if (self->m_autoWalkRetries > 0 && self->m_autoWalkRetries <= 3) { // try again in 300, 700, 1200 ms if canceled by server
                self->m_autoWalkContinueEvent = g_dispatcher.scheduleEvent([self, capture0 = result->destination] { self->autoWalk(capture0, true); }, 200 + self->m_autoWalkRetries * 100);
                return;
            }
            self->m_autoWalkDestination = {};
            self->callLuaField("onAutoWalkFail", result->status);
            return;
        }

        if (result->path.size() > 127)
            result->path.resize(127);

        if (result->path.empty()) {
            self->m_autoWalkDestination = {};
            self->callLuaField("onAutoWalkFail", result->status);
            return;
        }

        if (self->m_autoWalkDestination != result->destination) {
            self->m_lastAutoWalkPosition = result->destination;
        }

        g_game.autoWalk(result->path, result->start);
    });

    if (!retry)
        lockWalk();

    return true;
}

bool LocalPlayer::isWalkLocked() { return m_walkLockExpiration != 0 && g_clock.millis() < m_walkLockExpiration; }

void LocalPlayer::stopAutoWalk()
{
    m_autoWalkDestination = {};
    m_lastAutoWalkPosition = {};
    m_knownCompletePath = false;

    if (m_autoWalkContinueEvent)
        m_autoWalkContinueEvent->cancel();
}

void LocalPlayer::terminateWalk()
{
    Creature::terminateWalk();
    m_serverWalk = false;

    if (WalkTimeLog::enabled())
        s_walkLog.lastStepEnd = stdext::millis();

    callLuaField("onWalkFinish");
}

void LocalPlayer::onPositionChange(const Position& newPos, const Position& oldPos)
{
    if (isPreWalking())
        return;

    Creature::onPositionChange(newPos, oldPos);

    if (newPos == m_autoWalkDestination)
        stopAutoWalk();
    else if (m_autoWalkDestination.isValid() && newPos == m_lastAutoWalkPosition)
        autoWalk(m_autoWalkDestination);

    m_serverWalk = false;
}

void LocalPlayer::setStates(const uint64_t states)
{
    if (m_states == states)
        return;

    const uint64_t oldStates = m_states;
    m_states = states;

    if (isParalyzed() && isWalking() && m_serverWalk)
        updateWalk();

    callLuaField("onStatesChange", states, oldStates);
}

void LocalPlayer::setSkill(const Otc::Skill skillId, const uint16_t level, const uint16_t levelPercent)
{
    if (skillId >= Otc::LastSkill) {
        g_logger.traceError("invalid skill");
        return;
    }

    auto& skill = m_skills[skillId];

    const uint16_t oldLevel = skill.level;
    const uint16_t oldLevelPercent = skill.levelPercent;

    if (level == oldLevel && levelPercent == oldLevelPercent)
        return;

    skill.level = level;
    skill.levelPercent = levelPercent;

    callLuaField("onSkillChange", skillId, level, levelPercent, oldLevel, oldLevelPercent);
}

void LocalPlayer::setBaseSkill(const Otc::Skill skill, const uint16_t baseLevel)
{
    if (skill >= Otc::LastSkill) {
        g_logger.traceError("invalid skill");
        return;
    }

    const uint16_t oldBaseLevel = m_skills[skill].baseLevel;
    if (baseLevel == oldBaseLevel)
        return;

    m_skills[skill].baseLevel = baseLevel;

    callLuaField("onBaseSkillChange", skill, baseLevel, oldBaseLevel);
}

void LocalPlayer::setHealth(const uint32_t health, const uint32_t maxHealth)
{
    if (m_health != health || m_maxHealth != maxHealth) {
        const uint32_t oldHealth = m_health;
        const uint32_t oldMaxHealth = m_maxHealth;
        m_health = health;
        m_maxHealth = maxHealth;

        callLuaField("onHealthChange", health, maxHealth, oldHealth, oldMaxHealth);

        if (isDead()) {
            if (isPreWalking())
                stopWalk();
            lockWalk();
        }
    }
}

void LocalPlayer::setFreeCapacity(const uint32_t freeCapacity)
{
    if (m_freeCapacity == freeCapacity)
        return;

    const uint32_t oldFreeCapacity = m_freeCapacity;
    m_freeCapacity = freeCapacity;

    callLuaField("onFreeCapacityChange", freeCapacity, oldFreeCapacity);
}

void LocalPlayer::setTotalCapacity(const uint32_t totalCapacity)
{
    if (m_totalCapacity == totalCapacity)
        return;

    const uint32_t oldTotalCapacity = m_totalCapacity;
    m_totalCapacity = totalCapacity;

    callLuaField("onTotalCapacityChange", totalCapacity, oldTotalCapacity);
}

void LocalPlayer::setBaseCapacity(const uint32_t baseCapacity)
{
    if (m_baseCapacity == baseCapacity)
        return;

    m_baseCapacity = baseCapacity;
    callLuaField("onBaseCapacityChange", baseCapacity);
}

void LocalPlayer::setExperience(const uint64_t experience)
{
    if (m_experience == experience)
        return;

    const uint64_t oldExperience = m_experience;
    m_experience = experience;

    callLuaField("onExperienceChange", experience, oldExperience);
}

void LocalPlayer::setLevel(const uint16_t level, const uint16_t levelPercent)
{
    if (m_level == level && m_levelPercent == levelPercent)
        return;

    const uint16_t oldLevel = m_level;
    const uint16_t oldLevelPercent = m_levelPercent;

    m_level = level;
    m_levelPercent = levelPercent;

    callLuaField("onLevelChange", level, levelPercent, oldLevel, oldLevelPercent);
}

uint16_t LocalPlayer::getLevelPercent()
{
    return g_game.getFeature(Otc::GameLevelPercentU16) ? m_levelPercent / 100 : m_levelPercent;
}

void LocalPlayer::setMana(const uint32_t mana, const uint32_t maxMana)
{
    if (m_mana == mana && m_maxMana == maxMana)
        return;

    const uint32_t oldMana = m_mana;
    const uint32_t oldMaxMana = m_maxMana;
    m_mana = mana;
    m_maxMana = maxMana;

    callLuaField("onManaChange", mana, maxMana, oldMana, oldMaxMana);
}

void LocalPlayer::setManaShield(const uint32_t manaShield, const uint32_t maxManaShield)
{
    if (m_manaShield == manaShield && m_maxManaShield == maxManaShield)
        return;

    const uint32_t oldManaShield = m_manaShield;
    const uint32_t oldMaxManaShield = m_maxManaShield;
    m_manaShield = manaShield;
    m_maxManaShield = maxManaShield;

    callLuaField("onManaShieldChange", manaShield, maxManaShield, oldManaShield, oldMaxManaShield);
}

void LocalPlayer::setMagicLevel(const uint16_t magicLevel, const uint16_t magicLevelPercent)
{
    if (m_magicLevel == magicLevel && m_magicLevelPercent == magicLevelPercent)
        return;

    const uint16_t oldMagicLevel = m_magicLevel;
    const uint16_t oldMagicLevelPercent = m_magicLevelPercent;

    m_magicLevel = magicLevel;
    m_magicLevelPercent = magicLevelPercent;

    callLuaField("onMagicLevelChange", magicLevel, magicLevelPercent, oldMagicLevel, oldMagicLevelPercent);
}

void LocalPlayer::setBaseMagicLevel(const uint16_t baseMagicLevel)
{
    if (m_baseMagicLevel == baseMagicLevel)
        return;

    const uint16_t oldBaseMagicLevel = m_baseMagicLevel;
    m_baseMagicLevel = baseMagicLevel;

    callLuaField("onBaseMagicLevelChange", baseMagicLevel, oldBaseMagicLevel);
}

void LocalPlayer::setSoul(const uint8_t soul)
{
    if (m_soul == soul)
        return;

    const uint8_t oldSoul = m_soul;
    m_soul = soul;

    callLuaField("onSoulChange", soul, oldSoul);
}

void LocalPlayer::setStamina(const uint16_t stamina)
{
    if (m_stamina == stamina)
        return;

    const uint16_t oldStamina = m_stamina;
    m_stamina = stamina;

    callLuaField("onStaminaChange", stamina, oldStamina);
}

void LocalPlayer::setInventoryItem(const Otc::InventorySlot inventory, const ItemPtr& item)
{
    if (inventory >= Otc::LastInventorySlot) {
        g_logger.traceError("invalid slot");
        return;
    }

    if (m_inventoryItems[inventory] == item)
        return;

    const auto& oldItem = m_inventoryItems[inventory];
    m_inventoryItems[inventory] = item;

    if (item && g_game.getFeature(Otc::GameThingClock) && item->getDurationTime() > 0
        && item->getClothSlot() == static_cast<int>(inventory)) {
        item->setDecaying(true);
    }

    callLuaField("onInventoryChange", inventory, item, oldItem);
}

void LocalPlayer::setInventoryCountCache(std::map<std::pair<uint16_t, uint8_t>, uint32_t> counts)
{
    m_inventoryCountCache = std::move(counts);
}

bool LocalPlayer::hasEquippedItemId(const uint16_t itemId, const uint8_t tier)
{
    if (itemId == 0)
        return false;

    for (const auto& item : m_inventoryItems) {
        if (!item)
            continue;

        if (item->getId() != itemId)
            continue;

        if (item->getTier() != tier)
            continue;

        return true;
    }

    return false;
}

uint32_t LocalPlayer::getInventoryCount(const uint16_t itemId, const uint8_t tier)
{
    if (std::cmp_equal(itemId, 0))
        return 0;

    const auto key = std::make_pair(itemId, tier);
    const auto it = m_inventoryCountCache.find(key);
    if (it != m_inventoryCountCache.end()) {
        return it->second;
    }

    uint32_t total = 0;

    const auto accumulate = [&](const ItemPtr& item) {
        if (item && std::cmp_equal(item->getId(), itemId) && item->getTier() == tier) {
            total += item->getCount();
        }
    };

    for (const auto& item : m_inventoryItems)
        accumulate(item);

    for (const auto& [containerId, container] : g_game.getContainers()) {
        if (!container)
            continue;

        for (const auto& item : container->getItems())
            accumulate(item);
    }

    if (const uint64_t maxUint32 = std::numeric_limits<uint32_t>::max(); total > maxUint32) {
        total = maxUint32;
    }

    return total;
}

void LocalPlayer::setPremium(const bool premium)
{
    if (m_premium == premium)
        return;

    m_premium = premium;

    callLuaField("onPremiumChange", premium);
}

void LocalPlayer::setRegenerationTime(const uint16_t regenerationTime)
{
    if (m_regenerationTime == regenerationTime)
        return;

    const uint16_t oldRegenerationTime = m_regenerationTime;
    m_regenerationTime = regenerationTime;

    callLuaField("onRegenerationChange", regenerationTime, oldRegenerationTime);
}

void LocalPlayer::setOfflineTrainingTime(const uint16_t offlineTrainingTime)
{
    if (m_offlineTrainingTime == offlineTrainingTime)
        return;

    const uint16_t oldOfflineTrainingTime = m_offlineTrainingTime;
    m_offlineTrainingTime = offlineTrainingTime;

    callLuaField("onOfflineTrainingChange", offlineTrainingTime, oldOfflineTrainingTime);
}

void LocalPlayer::setSpells(const std::vector<uint16_t>& spells)
{
    if (m_spells == spells)
        return;

    const std::vector<uint16_t> oldSpells = m_spells;
    m_spells = spells;

    callLuaField("onSpellsChange", spells, oldSpells);
}

void LocalPlayer::setBlessings(const uint16_t blessings, const uint8_t blessVisualState)
{
    if (blessings == m_blessings && blessVisualState == m_blessVisualState)
        return;

    const uint16_t oldBlessings = m_blessings;
    m_blessings = blessings;
    m_blessVisualState = blessVisualState;

    callLuaField("onBlessingsChange", blessings, oldBlessings, blessVisualState);
}

void LocalPlayer::takeScreenshot(const uint8_t type)
{
    callLuaField("onTakeScreenshot", type);
}

void LocalPlayer::openMultiOfflineTrainingDialog()
{
    callLuaField("onMultiOfflineTrainingDialog");
}

void LocalPlayer::setResourceBalance(const Otc::ResourceTypes_t type, const uint64_t value)
{
    const uint64_t oldBalance = getResourceBalance(type);
    if (value == oldBalance)
        return;

    m_resourcesBalance[type] = value;
    g_lua.callGlobalField("g_game", "onResourcesBalanceChange", value, oldBalance, type);
    // the ported modules (prey, taskboard, market, imbuing, proficiency) listen to
    // onResourceBalance(type, value) - without this the wildcard/token/gold counters did not refresh
    g_lua.callGlobalField("g_game", "onResourceBalance", type, value);
}

bool LocalPlayer::hasSight(const Position& pos)
{
    return m_position.isInRange(pos, g_map.getAwareRange().left - 1, g_map.getAwareRange().top - 1);
}

void LocalPlayer::setFlatDamageHealing(uint16_t flatBonus)
{
    if (m_flatDamageHealing == flatBonus)
        return;

    const uint16_t oldFlatBonus = m_flatDamageHealing;
    m_flatDamageHealing = flatBonus;

    callLuaField("onFlatDamageHealingChange", flatBonus);
}

void LocalPlayer::setAttackInfo(uint16_t attackValue, uint8_t attackElement)
{
    if (m_attackValue == attackValue && m_attackElement == attackElement)
        return;

    const uint16_t oldAttackValue = m_attackValue;
    const uint8_t oldAttackElement = m_attackElement;
    m_attackValue = attackValue;
    m_attackElement = attackElement;

    callLuaField("onAttackInfoChange", attackValue, attackElement);
}

void LocalPlayer::setConvertedDamage(double convertedDamage, uint8_t convertedElement)
{
    if (m_convertedDamage == convertedDamage && m_convertedElement == convertedElement)
        return;

    const double oldConvertedDamage = m_convertedDamage;
    const uint8_t oldConvertedElement = m_convertedElement;
    m_convertedDamage = convertedDamage;
    m_convertedElement = convertedElement;

    callLuaField("onConvertedDamageChange", convertedDamage, convertedElement);
}

void LocalPlayer::setImbuements(double lifeLeech, double manaLeech, double critChance, double critDamage, double onslaught)
{
    if (m_lifeLeech == lifeLeech && m_manaLeech == manaLeech && m_critChance == critChance &&
        m_critDamage == critDamage && m_onslaught == onslaught)
        return;

    const double oldLifeLeech = m_lifeLeech;
    const double oldManaLeech = m_manaLeech;
    const double oldCritChance = m_critChance;
    const double oldCritDamage = m_critDamage;
    const double oldOnslaught = m_onslaught;

    m_lifeLeech = lifeLeech;
    m_manaLeech = manaLeech;
    m_critChance = critChance;
    m_critDamage = critDamage;
    m_onslaught = onslaught;

    callLuaField("onImbuementsChange", lifeLeech, manaLeech, critChance, critDamage, onslaught);
}

void LocalPlayer::setDefenseInfo(uint16_t defense, uint16_t armor, uint16_t mantra, double mitigation, double dodge, uint16_t damageReflection)
{
    if (m_defense == defense && m_armor == armor && m_mantra == mantra && m_mitigation == mitigation &&
        m_dodge == dodge && m_damageReflection == damageReflection)
        return;

    const uint16_t oldDefense = m_defense;
    const uint16_t oldArmor = m_armor;
    const uint16_t oldMantra = m_mantra;
    const double oldMitigation = m_mitigation;
    const double oldDodge = m_dodge;
    const uint16_t oldDamageReflection = m_damageReflection;

    m_defense = defense;
    m_armor = armor;
    m_mantra = mantra;
    m_mitigation = mitigation;
    m_dodge = dodge;
    m_damageReflection = damageReflection;

    callLuaField("onDefenseInfoChange", defense, armor,mantra, mitigation, dodge, damageReflection);
}

void LocalPlayer::setCombatAbsorbValues(const std::map<uint8_t, double>& absorbValues)
{
    if (m_combatAbsorbValues == absorbValues)
        return;

    const auto oldAbsorbValues = m_combatAbsorbValues;
    m_combatAbsorbValues = absorbValues;

    callLuaField("onCombatAbsorbValuesChange", absorbValues);
}

void LocalPlayer::setForgeBonuses(double momentum, double transcendence, double amplification)
{
    if (m_momentum == momentum && m_transcendence == transcendence && m_amplification == amplification)
        return;

    const double oldMomentum = m_momentum;
    const double oldTranscendence = m_transcendence;
    const double oldAmplification = m_amplification;

    m_momentum = momentum;
    m_transcendence = transcendence;
    m_amplification = amplification;

    callLuaField("onForgeBonusesChange", momentum, transcendence, amplification);
}

void LocalPlayer::setExperienceRate(Otc::ExperienceRate_t type, uint16_t value)
{
    if (m_experienceRates[type] == value)
        return;

    const uint16_t oldValue = m_experienceRates[type];
    m_experienceRates[type] = value;

    callLuaField("onExperienceRateChange", type, value);
}

void LocalPlayer::setStoreExpBoostTime(uint16_t value)
{
    if (m_storeExpBoostTime == value)
        return;

    m_storeExpBoostTime = value;
    callLuaField("onExpBoostTimeChange");
}

void LocalPlayer::setDailyExpBoostTime(uint16_t value)
{
    if (m_dailyExpBoostTime == value)
        return;

    m_dailyExpBoostTime = value;
    callLuaField("onExpBoostTimeChange");
}

void LocalPlayer::setHarmony(const uint8_t harmony)
{
    const uint8_t oldHarmony = m_harmony;
    m_harmony = harmony;

    callLuaField("onHarmonyChange", harmony, oldHarmony);
}

void LocalPlayer::setSerene(const bool serene)
{
    const bool oldSerene = m_serene;
    m_serene = serene;

    callLuaField("onSereneChange", serene, oldSerene);
}
