-- chunkname: @/corelib/ui/uibutton.lua

UIButton = extends(UIWidget, "UIButton")

function UIButton.create()
	local button = UIButton.internalCreate()

	button:setFocusable(false)

	return button
end

function UIButton:onMouseRelease(pos, button)
	local pressed = self:isPressed()

	if pressed and button == MouseLeftButton and self:isEnabled() then
		playUIClickSound()
	end

	return pressed
end
