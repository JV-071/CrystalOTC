-- chunkname: @/game_textwindow/textwindow.lua

local windows = {}

local function isTextWindowWriteable(itemId, maxLength, text)
	local ok, itemType = pcall(function()
		return g_things.getThingType(itemId, ThingCategoryItem)
	end)

	if ok and itemType and not itemType:isWritable() and not itemType:isWritableOnce() then
		return false
	end

	return maxLength > #text or #text == 0 and maxLength > 0
end

-- Spellbooks (same ids as the server spellbook action) open the 15.33 Spellbook dialog:
-- the spell list plus a button to the Magical Archive.
local SPELLBOOK_ITEM_IDS = {
	[3059] = true,
	[6120] = true,
	[8072] = true,
	[8073] = true,
	[8074] = true,
	[8075] = true,
	[8076] = true,
	[8090] = true,
	[11691] = true,
	[14769] = true,
	[16107] = true,
	[20088] = true,
	[20089] = true,
	[20090] = true,
	[21400] = true,
	[22755] = true,
	[25699] = true,
	[29431] = true,
	[34153] = true
}

local function isSpellBookText(itemId, writeable)
	return not writeable and SPELLBOOK_ITEM_IDS[itemId] == true and g_game.getClientVersion() >= 1533
end

local function setTextWindowTitle(textWindow, writeable)
	textWindow:setText(tr(writeable and "Edit Text" or "Show Text"))
end

local function focusTextEditor(textEdit, text)
	if not textEdit or textEdit:isDestroyed() then
		return
	end

	textEdit:setFocusable(true)
	textEdit:focus()
	textEdit:grabKeyboard()
	textEdit:setCursorVisible(true)
	textEdit:setCursorPos(#text)
end

local function bindTextWindowEscape(textWindow, textEdit, callback)
	textWindow.onEscape = callback

	if not textEdit then
		return
	end

	function textEdit.onKeyDown(widget, keyCode, keyboardModifiers)
		if keyboardModifiers ~= KeyboardNoModifier then
			return false
		end

		if keyCode == KeyEscape then
			callback()

			return true
		end

		return false
	end
end

local function showTextWindow(textWindow)
	textWindow:raise()
	textWindow:show()

	if g_modalManager then
		g_modalManager.show(textWindow)
	end
end

local function hideTextWindow(textWindow)
	if not textWindow or textWindow:isDestroyed() then
		return
	end

	local textEdit = textWindow:recursiveGetChildById("textEdit")

	if textEdit and not textEdit:isDestroyed() then
		pcall(function()
			textEdit:ungrabKeyboard()
		end)
	end

	if g_modalManager then
		g_modalManager.hide(textWindow)
	end
end

function init()
	g_ui.importStyle("textwindow")
	connect(g_game, {
		onEditText = onGameEditText,
		onEditList = onGameEditList,
		onGameEnd = destroyWindows
	})
end

function terminate()
	disconnect(g_game, {
		onEditText = onGameEditText,
		onEditList = onGameEditList,
		onGameEnd = destroyWindows
	})
	destroyWindows()
end

function destroyWindows()
	if g_modalManager then
		g_modalManager.clear()
	end

	for _, window in pairs(windows) do
		if window and not window:isDestroyed() then
			window:destroy()
		end
	end

	windows = {}
end

function onGameEditText(id, itemId, maxLength, text, writer, time)
	local textWindow = g_ui.createWidget("TextWindow", rootWidget)
	local writeable = isTextWindowWriteable(itemId, maxLength, text)

	setTextWindowTitle(textWindow, writeable)

	local textItem = textWindow:getChildById("textItem")
	local description = textWindow:getChildById("description")
	local textEdit = textWindow:recursiveGetChildById("textEdit")
	local okButton = textWindow:getChildById("okButton")
	local cancelButton = textWindow:getChildById("cancelButton")
	local openArchiveButton = textWindow:getChildById("openArchiveButton")
	local spellBook = isSpellBookText(itemId, writeable)

	if textItem:isHidden() then
		textItem:show()
	end

	textItem:setBackgroundColor("#00000000")
	textItem:setItemId(itemId)
	textEdit:setMaxLength(maxLength)
	textEdit:setText(text)
	textEdit:setEditable(writeable)
	textEdit:setCursorVisible(writeable)

	local desc

	if writeable and #text == 0 then
		desc = tr("It is currently empty.") .. "\n"
	elseif #writer > 0 and #time > 0 then
		desc = tr("You read the following, written by %s on %s.\n", writer, time)
	elseif #writer > 0 then
		desc = tr("You read the following, written by %s.\n", writer)
	elseif #time > 0 then
		desc = tr("You read the following, written on %s.\n", time)
	else
		desc = tr("You read the following.\n")
	end

	if #text == 0 and not writeable then
		desc = desc .. tr("It is empty.")
	elseif writeable then
		desc = desc .. tr("You can enter new text.")
	end

	local lines = #{
		string.find(desc, "\n")
	}

	if lines < 2 then
		desc = desc .. "\n"
	end

	if spellBook then
		textWindow:setText(tr("Spellbook"))

		desc = tr("You know the following spells. Look them up in the Magical Archive for details.")
	end

	description:setText(desc)
	okButton:setText(tr("Ok"))
	cancelButton:setText(tr("Cancel"))

	if not writeable then
		cancelButton:hide()
		cancelButton:setWidth(0)
		okButton:setMarginRight(1)
	end

	if description:getHeight() < 64 then
		description:setHeight(64)
	end

	local function destroy()
		hideTextWindow(textWindow)
		textWindow:destroy()
		table.removevalue(windows, textWindow)
	end

	local function doneFunc()
		if writeable then
			g_game.editText(id, textEdit:getText())
		end

		destroy()
	end

	okButton.onClick = doneFunc
	cancelButton.onClick = destroy

	if spellBook and openArchiveButton then
		openArchiveButton:setVisible(true)

		function openArchiveButton.onClick()
			destroy()

			if modules.game_cyclopedia and modules.game_cyclopedia.show then
				modules.game_cyclopedia.show("magicalArchives")
			end
		end
	end

	if not writeable then
		textWindow.onEnter = doneFunc
	end

	bindTextWindowEscape(textWindow, writeable and textEdit or nil, destroy)
	table.insert(windows, textWindow)
	showTextWindow(textWindow)

	if writeable then
		addEvent(function()
			focusTextEditor(textEdit, text)
		end)
		scheduleEvent(function()
			focusTextEditor(textEdit, text)
		end, 50)
	end
end

function onGameEditList(id, doorId, text)
	local textWindow = g_ui.createWidget("TextWindow", rootWidget)
	local textEdit = textWindow:recursiveGetChildById("textEdit")
	local description = textWindow:getChildById("description")
	local okButton = textWindow:getChildById("okButton")
	local cancelButton = textWindow:getChildById("cancelButton")
	local textItem = textWindow:getChildById("textItem")

	if textItem and not textItem:isHidden() then
		textItem:hide()
	end

	textEdit:setMaxLength(8192)
	textEdit:setText(text)
	textEdit:setEditable(true)
	description:setText(tr("Enter one name per line."))
	textWindow:setText(tr("Edit List"))
	okButton:setText(tr("Ok"))
	cancelButton:setText(tr("Cancel"))

	if description:getHeight() < 64 then
		description:setHeight(64)
	end

	local function destroy()
		hideTextWindow(textWindow)
		textWindow:destroy()
		table.removevalue(windows, textWindow)
	end

	local function doneFunc()
		g_game.editList(id, doorId, textEdit:getText())
		destroy()
	end

	okButton.onClick = doneFunc
	cancelButton.onClick = destroy

	bindTextWindowEscape(textWindow, textEdit, destroy)
	table.insert(windows, textWindow)
	showTextWindow(textWindow)
	addEvent(function()
		focusTextEditor(textEdit, text)
	end)
	scheduleEvent(function()
		focusTextEditor(textEdit, text)
	end, 50)
end
