--[[
	Positions a capture client on one of the renderer baseline platforms.

	    !fixture            -> reports the available destinations
	    !fixture map        -> the "map-core" surface platform
	    !fixture lighting   -> the "lighting-overlap" underground platform
	    !fixture wide       -> the wide-radius light beacon

	groupType("normal") is GROUP_TYPE_NORMAL = 1
	(src/enums/account_group_type.hpp:26), the lowest value this build accepts:
	TalkActionFunctions::luaTalkActionRegister refuses to register a talkaction
	left at GROUP_TYPE_NONE (src/lua/functions/events/talk_action_functions.cpp:133),
	and TalkActions::checkWord only rejects callers whose group id is *lower*
	than the talkaction's group type (src/lua/creature/talkaction.cpp:56). The
	"player" group in data/XML/groups.xml is id 1, so a plain group-1 character
	passes. That matters: the lighting scene has to be captured by a character
	WITHOUT the hasfulllight flag, because that flag makes the server report
	creature light 255/215 for every creature including the player itself
	(src/server/network/protocol/protocolgame.cpp:9490), which washes the whole
	viewport white.

	The '!' prefix is what routes the message into the talkaction table
	(src/game/game.cpp:6796), so it works from g_game.talk() on the client.
]]

local fixtureTeleport = TalkAction("!fixture")

function fixtureTeleport.onSay(player, words, param)
	local key = param:lower():gsub("^%s+", ""):gsub("%s+$", "")
	local destination = RendererFixtures.DESTINATIONS[key]

	if not destination then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Renderer fixtures: !fixture map | !fixture lighting | !fixture wide")
		return true
	end

	player:teleportTo(destination)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, ("Renderer fixtures: moved to %s at %d, %d, %d."):format(key, destination.x, destination.y, destination.z))
	return true
end

fixtureTeleport:separator(" ")
fixtureTeleport:groupType("normal")
fixtureTeleport:register()
