-- chunkname: @/corelib/keyboard.lua

g_keyboard = {}

function translateKeyCombo(keyCombo)
	if not keyCombo then
		return nil
	end

	local keyComboDesc = ""

	for _, v in ipairs(keyCombo) do
		if type(v) == "number" then
			local keyDesc = KeyCodeDescs[v]

			if keyDesc == nil then
				return nil
			end

			keyComboDesc = keyComboDesc .. "+" .. keyDesc
		elseif type(v) == "string" and v ~= "" then
			keyComboDesc = keyComboDesc .. "+" .. v
		else
			return nil
		end
	end

	if keyComboDesc == "" then
		return nil
	end

	return keyComboDesc:sub(2)
end

local KeyDescAliases = {
	numpad7 = "Num+7",
	numpad4 = "Num+4",
	numpad5 = "Num+5",
	numpad9 = "Num+9",
	numpad6 = "Num+6",
	numpad8 = "Num+8",
	numpad3 = "Num+3",
	numpad0 = "Num+0",
	["return"] = "Enter",
	numpaddivide = "Num+/",
	numpadmultiply = "Num+*",
	numpadsubtract = "Num+-",
	numpaddelete = "Num+Delete",
	numpaddecimal = "Num+.",
	numpadadd = "Num++",
	numpadenter = "Num+Enter",
	numpad2 = "Num+2",
	numpad1 = "Num+1"
}
local NumpadKeyTokens = {
	"Num++",
	"Num+-",
	"Num+*",
	"Num+/",
	"Num+."
}

local function getKeyCode(key)
	local normalized = KeyDescAliases[key:trim():lower()] or key:trim()

	for keyCode, keyDesc in pairs(KeyCodeDescs) do
		if keyDesc:lower() == normalized:lower() then
			return keyCode
		end
	end
end

local function splitKeyComboDesc(keyComboDesc)
	local parts = {}
	local i = 1

	while i <= #keyComboDesc do
		if keyComboDesc:sub(i, i + 3) == "Num+" then
			local matched = false

			for _, token in ipairs(NumpadKeyTokens) do
				if keyComboDesc:sub(i, i + #token - 1) == token then
					table.insert(parts, token)

					i = i + #token
					matched = true

					break
				end
			end

			if not matched then
				local after = keyComboDesc:sub(i + 4)
				local endPos = after:find("+", 1, true)

				if endPos then
					table.insert(parts, "Num+" .. after:sub(1, endPos - 1))

					i = i + 3 + endPos
				else
					table.insert(parts, "Num+" .. after)

					i = #keyComboDesc + 1
				end
			end
		else
			local rest = keyComboDesc:sub(i)
			local endPos = rest:find("+", 1, true)

			if endPos then
				table.insert(parts, rest:sub(1, endPos - 1))

				i = i + endPos
			else
				table.insert(parts, rest)

				i = #keyComboDesc + 1
			end
		end
	end

	return parts
end

local KEY_DISPLAY_ABBREVIATIONS = {
	Delete = "Del",
	ScrollLock = "ScrLk",
	PageDown = "PgDown",
	PageUp = "PgUp",
	Insert = "Ins"
}
local KEY_TOOLTIP_EXPANSIONS = {}

for fullName, shortName in pairs(KEY_DISPLAY_ABBREVIATIONS) do
	KEY_TOOLTIP_EXPANSIONS[shortName] = fullName
end

local function expandTooltipKeyPart(part)
	if part:sub(1, 4) == "Num+" then
		local suffix = part:sub(5)

		return "Num+" .. (KEY_TOOLTIP_EXPANSIONS[suffix] or suffix)
	end

	return KEY_TOOLTIP_EXPANSIONS[part] or part
end

-- Deliberately NOT routed through g_keyboard.getNativeKeyComboDesc: this is the action bar's
-- space-constrained slot label, where every modifier is already collapsed to one letter. The
-- portable names abbreviate correctly under the macOS swap anyway -- "Ctrl" is Command there
-- and still reads as "C" -- so renaming first would only churn every slot label.
local function abbreviateHotkeyDisplayPart(part)
	part = part:gsub("Shift", "S"):gsub("Alt", "A"):gsub("Ctrl", "C")

	if part:sub(1, 4) == "Num+" then
		local suffix = part:sub(5)

		return "N" .. (KEY_DISPLAY_ABBREVIATIONS[suffix] or suffix)
	end

	return KEY_DISPLAY_ABBREVIATIONS[part] or part
end

-- Portable text vs native text, the same split QKeySequence draws.
--
-- A key combo is *stored and compared* in portable form -- "Ctrl+B" -- on every platform, and
-- that is deliberate: the official client is a Qt application whose shipped defaults are
-- literally portable strings ("Ctrl+B", "Ctrl+F", "Ctrl+K"), and it lets Qt resolve "Ctrl" to
-- Command on macOS. CrystalOTC does the same swap in modifierBitFor() (platformwindow.cpp), so
-- one stored string means the same physical gesture everywhere and no config needs migrating.
--
-- Only the *rendering* is platform-specific, and only on macOS, where the Ctrl bit is raised
-- by Command and the Meta bit by the physical Control key.
--
-- ASCII names rather than the real U+2318/U+2325 glyphs: the engine's text pipeline is latin1
-- end to end (stdext::utf8_to_latin1 on every text input), so those code points cannot reach
-- the font intact.
local MACOS_NATIVE_MODIFIER_NAMES = {
	Ctrl = "Cmd",
	Alt = "Opt",
	Meta = "Ctrl"
}
local MACOS_PORTABLE_MODIFIER_NAMES = {}

for portable, native in pairs(MACOS_NATIVE_MODIFIER_NAMES) do
	MACOS_PORTABLE_MODIFIER_NAMES[native] = portable
end

local function usesMacOSModifierNames()
	return g_platform.getDevice().os == OsMacOS
end

local function translateModifierNames(keyComboDesc, names)
	if keyComboDesc == nil or keyComboDesc == "" then
		return keyComboDesc
	end

	if type(keyComboDesc) ~= "string" then
		keyComboDesc = tostring(keyComboDesc)
	end

	if not usesMacOSModifierNames() then
		return keyComboDesc
	end

	local parts = splitKeyComboDesc(keyComboDesc)

	for i, part in ipairs(parts) do
		parts[i] = names[part] or part
	end

	return table.concat(parts, "+")
end

-- Portable -> what the user should see. Use this for every combo shown in the UI.
function g_keyboard.getNativeKeyComboDesc(keyComboDesc)
	return translateModifierNames(keyComboDesc, MACOS_NATIVE_MODIFIER_NAMES)
end

-- What the user saw -> portable. Use this whenever a displayed combo is read back to be
-- stored, compared or bound.
function g_keyboard.getPortableKeyComboDesc(keyComboDesc)
	return translateModifierNames(keyComboDesc, MACOS_PORTABLE_MODIFIER_NAMES)
end

function g_keyboard.splitKeyComboDesc(keyComboDesc)
	if keyComboDesc == nil or keyComboDesc == "" then
		return {}
	end

	if type(keyComboDesc) ~= "string" then
		keyComboDesc = tostring(keyComboDesc)
	end

	return splitKeyComboDesc(keyComboDesc)
end

function g_keyboard.formatHotkeyDisplayText(combo)
	if combo == nil or combo == "" then
		return ""
	end

	local text = type(combo) == "string" and combo or tostring(combo)
	local parts = splitKeyComboDesc(text)
	local out = {}

	for _, part in ipairs(parts) do
		table.insert(out, abbreviateHotkeyDisplayPart(part))
	end

	return table.concat(out)
end

function g_keyboard.formatHotkeyTooltipText(combo)
	if combo == nil or combo == "" then
		return ""
	end

	-- Tooltips have room for the full modifier names, so show the platform's own: "Cmd+E" on
	-- macOS rather than the portable "Ctrl+E" the binding is stored as.
	local text = g_keyboard.getNativeKeyComboDesc(type(combo) == "string" and combo or tostring(combo))
	local parts = splitKeyComboDesc(text)
	local out = {}

	for _, part in ipairs(parts) do
		table.insert(out, expandTooltipKeyPart(part))
	end

	return table.concat(out, "+")
end

function g_keyboard.truncateHotkeySlotText(text, maxLen)
	maxLen = maxLen or 5

	if text == nil or text == "" then
		return ""
	end

	if maxLen >= #text then
		return text
	end

	return "..." .. text:sub(-3)
end

local RESERVED_MOVEMENT_HOTKEYS = {
	Right = true,
	Left = true,
	Down = true,
	Up = true,
	["Num+PgUp"] = true,
	["Num+Up"] = true,
	["Num+Home"] = true,
	["Num+Right"] = true,
	["Num+Left"] = true,
	["Num+PgDown"] = true,
	["Num+Down"] = true,
	["Num+End"] = true
}

function g_keyboard.isReservedMovementHotkey(combo)
	if combo == nil or combo == "" then
		return false
	end

	if type(combo) ~= "string" then
		combo = tostring(combo)
	end

	return RESERVED_MOVEMENT_HOTKEYS[combo] == true
end

function g_keyboard.getReservedHotkeyErrorText()
	return tr("This hotkey is already in use and cannot be overwritten.")
end

local function resolveKeyDescToCode(keyDesc)
	local normalizedDesc = KeyDescAliases[keyDesc:trim():lower()] or keyDesc:trim()

	for keyCode, desc in pairs(KeyCodeDescs) do
		if desc:lower() == normalizedDesc:lower() then
			return keyCode
		end
	end
end

function retranslateKeyComboDesc(keyComboDesc)
	if keyComboDesc == nil then
		error("Unable to translate key combo '" .. tostring(keyComboDesc) .. "'")
	end

	if type(keyComboDesc) == "number" then
		keyComboDesc = tostring(keyComboDesc)
	end

	local keyCombo = {}

	for _, currentKeyDesc in ipairs(splitKeyComboDesc(keyComboDesc)) do
		local keyCode = resolveKeyDescToCode(currentKeyDesc)

		if keyCode then
			table.insert(keyCombo, keyCode)
		elseif currentKeyDesc ~= "" then
			local text = currentKeyDesc

			if #text == 1 and text:match("%a") then
				text = text:upper()
			end

			table.insert(keyCombo, text)
		end
	end

	return translateKeyCombo(keyCombo)
end

function determineKeyComboDesc(keyCode, keyboardModifiers, keyText)
	if not keyText or keyText == "" or keyCode >= KeyNumpad0 and keyCode <= KeyNumpadDivide then
		keyText = KeyCodeDescs[keyCode]
	elseif #keyText == 1 and keyText:match("%a") then
		keyText = keyText:upper()
	end

	local keyCombo = {}

	if keyCode == KeyCtrl or keyCode == KeyShift or keyCode == KeyAlt then
		table.insert(keyCombo, keyCode)
	elseif keyText then
		-- Bit tests rather than an equality chain over the seven Ctrl/Alt/Shift combinations.
		-- KeyboardMetaModifier is a fourth bit now, and exact comparison would have produced
		-- no modifier prefix at all whenever it was set -- on macOS that is any combo held
		-- with the physical Control key. Order is Ctrl, Alt, Shift so the seven pre-existing
		-- combinations still serialise byte-for-byte identically; Meta is appended last.
		if bit.band(keyboardModifiers, KeyboardCtrlModifier) ~= 0 then
			table.insert(keyCombo, KeyCtrl)
		end

		if bit.band(keyboardModifiers, KeyboardAltModifier) ~= 0 then
			table.insert(keyCombo, KeyAlt)
		end

		if bit.band(keyboardModifiers, KeyboardShiftModifier) ~= 0 then
			table.insert(keyCombo, KeyShift)
		end

		if bit.band(keyboardModifiers, KeyboardMetaModifier) ~= 0 then
			table.insert(keyCombo, KeyMeta)
		end

		table.insert(keyCombo, keyText)
	end

	return translateKeyCombo(keyCombo)
end

local function onWidgetKeyDown(widget, keyCode, keyboardModifiers, keyText)
	if keyCode == KeyUnknown then
		return false
	end

	if not keyText or keyText == "" then
		keyText = KeyCodeDescs[keyCode]
	end

	local callback = widget.boundAloneKeyDownCombos[determineKeyComboDesc(keyCode, KeyboardNoModifier, keyText)]

	signalcall(callback, widget, keyCode)

	callback = widget.boundKeyDownCombos[determineKeyComboDesc(keyCode, keyboardModifiers, keyText)]

	return signalcall(callback, widget, keyCode, keyText)
end

local function onWidgetKeyUp(widget, keyCode, keyboardModifiers, keyText)
	if keyCode == KeyUnknown then
		return false
	end

	if not keyText or keyText == "" then
		keyText = KeyCodeDescs[keyCode]
	end

	local callback = widget.boundAloneKeyUpCombos[determineKeyComboDesc(keyCode, KeyboardNoModifier, keyText)]

	signalcall(callback, widget, keyCode)

	callback = widget.boundKeyUpCombos[determineKeyComboDesc(keyCode, keyboardModifiers, keyText)]

	return signalcall(callback, widget, keyCode)
end

local function onWidgetKeyPress(widget, keyCode, keyboardModifiers, autoRepeatTicks, keyText)
	if keyCode == KeyUnknown then
		return false
	end

	if not widget.boundKeyPressCombos then
		return false
	end

	if not keyText or keyText == "" then
		keyText = KeyCodeDescs[keyCode]
	end

	local callback = widget.boundKeyPressCombos[determineKeyComboDesc(keyCode, keyboardModifiers, keyText)]

	return signalcall(callback, widget, keyCode, autoRepeatTicks, keyText)
end

local function connectKeyDownEvent(widget)
	if widget.boundKeyDownCombos then
		return
	end

	connect(widget, {
		onKeyDown = onWidgetKeyDown
	})

	widget.boundKeyDownCombos = {}
	widget.boundAloneKeyDownCombos = {}
end

local function connectKeyUpEvent(widget)
	if widget.boundKeyUpCombos then
		return
	end

	connect(widget, {
		onKeyUp = onWidgetKeyUp
	})

	widget.boundKeyUpCombos = {}
	widget.boundAloneKeyUpCombos = {}
end

local function connectKeyPressEvent(widget)
	if widget.boundKeyPressCombos then
		return
	end

	connect(widget, {
		onKeyPress = onWidgetKeyPress
	})

	widget.boundKeyPressCombos = {}
end

function g_keyboard.setKeyDelay(key, delay)
	g_window.setKeyDelay(getKeyCode(key), delay)
end

function g_keyboard.bindKeyDown(keyComboDesc, callback, widget, alone)
	widget = widget or rootWidget

	connectKeyDownEvent(widget)

	local keyComboDesc = retranslateKeyComboDesc(keyComboDesc)

	if alone then
		connect(widget.boundAloneKeyDownCombos, keyComboDesc, callback)
	else
		connect(widget.boundKeyDownCombos, keyComboDesc, callback)
	end
end

function g_keyboard.bindKeyUp(keyComboDesc, callback, widget, alone)
	widget = widget or rootWidget

	connectKeyUpEvent(widget)

	local keyComboDesc = retranslateKeyComboDesc(keyComboDesc)

	if alone then
		connect(widget.boundAloneKeyUpCombos, keyComboDesc, callback)
	else
		connect(widget.boundKeyUpCombos, keyComboDesc, callback)
	end
end

function g_keyboard.bindKeyPress(keyComboDesc, callback, widget)
	widget = widget or rootWidget

	connectKeyPressEvent(widget)

	local keyComboDesc = retranslateKeyComboDesc(keyComboDesc)

	connect(widget.boundKeyPressCombos, keyComboDesc, callback)
end

local function getUnbindArgs(arg1, arg2)
	local callback, widget

	if type(arg1) == "function" then
		callback = arg1
	elseif type(arg2) == "function" then
		callback = arg2
	end

	if type(arg1) == "userdata" then
		widget = arg1
	elseif type(arg2) == "userdata" then
		widget = arg2
	end

	widget = widget or rootWidget

	return callback, widget
end

function g_keyboard.unbindKeyDown(keyComboDesc, arg1, arg2)
	local callback, widget = getUnbindArgs(arg1, arg2)
	local normalized = retranslateKeyComboDesc(keyComboDesc)

	if widget.boundKeyDownCombos then
		disconnect(widget.boundKeyDownCombos, normalized, callback)
	end

	if widget.boundAloneKeyDownCombos then
		disconnect(widget.boundAloneKeyDownCombos, normalized, callback)
	end
end

function g_keyboard.unbindKeyUp(keyComboDesc, arg1, arg2)
	local callback, widget = getUnbindArgs(arg1, arg2)
	local normalized = retranslateKeyComboDesc(keyComboDesc)

	if widget.boundKeyUpCombos then
		disconnect(widget.boundKeyUpCombos, normalized, callback)
	end

	if widget.boundAloneKeyUpCombos then
		disconnect(widget.boundAloneKeyUpCombos, normalized, callback)
	end
end

function g_keyboard.unbindKeyPress(keyComboDesc, arg1, arg2)
	local callback, widget = getUnbindArgs(arg1, arg2)

	if widget.boundKeyPressCombos == nil then
		return
	end

	if keyComboDesc == nil or keyComboDesc == "" then
		return
	end

	local ok, translated = pcall(retranslateKeyComboDesc, keyComboDesc)

	if not ok or not translated then
		return
	end

	disconnect(widget.boundKeyPressCombos, translated, callback)
end

function g_keyboard.getModifiers()
	return g_window.getKeyboardModifiers()
end

function g_keyboard.isEnterKey(keyCode)
	return keyCode == KeyEnter or keyCode == KeyNumpadEnter or keyCode == KeyReturn
end

function g_keyboard.isKeyPressed(key)
	if type(key) == "string" then
		key = getKeyCode(key)
	end

	return g_window.isKeyPressed(key)
end

function g_keyboard.isKeySetPressed(keys, all)
	all = all or false

	local result = {}

	for k, v in pairs(keys) do
		if type(v) == "string" then
			v = getKeyCode(v)
		end

		if g_window.isKeyPressed(v) then
			if not all then
				return true
			end

			table.insert(result, true)
		end
	end

	return #result == #keys
end

function g_keyboard.isInUse()
	-- Two bugs lived here: the loop tested an undefined global `key` instead of `i`, so this
	-- always returned false, and it ran to LastKey (167). The C++ Fw::Key enum stops at
	-- KeyNumpad9 (150), so simply passing `i` through would have indexed past the end of
	-- PlatformWindow::m_keyInfo -- that read is bounds-checked now, but stop at the last code
	-- a platform window can actually deliver rather than relying on it.
	for i = FirstKey, KeyNumpad9 do
		if g_window.isKeyPressed(i) then
			return true
		end
	end

	return false
end

function g_keyboard.isCtrlPressed()
	if g_platform.isMobile() then
		return false
	else
		return bit.band(g_window.getKeyboardModifiers(), KeyboardCtrlModifier) ~= 0
	end
end

function g_keyboard.isAltPressed()
	if g_platform.isMobile() then
		return false
	else
		return bit.band(g_window.getKeyboardModifiers(), KeyboardAltModifier) ~= 0
	end
end

function g_keyboard.isShiftPressed()
	if g_platform.isMobile() then
		return false
	else
		return bit.band(g_window.getKeyboardModifiers(), KeyboardShiftModifier) ~= 0
	end
end

-- The Windows/Super key on Windows and Linux, the physical Control key on macOS. Nothing
-- binds it; it is here so callers can tell "no modifier" from "a modifier we ignore".
function g_keyboard.isMetaPressed()
	if g_platform.isMobile() then
		return false
	else
		return bit.band(g_window.getKeyboardModifiers(), KeyboardMetaModifier) ~= 0
	end
end
