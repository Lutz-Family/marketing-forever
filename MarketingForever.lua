-- Marketing Forever
-- WoW Forever (Interface 16001) - Minimap marketing message manager
-- Author: SirEggbert / Makers Forge
-- Single-window UI with square iron border (common theme with CtrlMarks)

local ADDON_NAME = "MarketingForever"

MarketingForeverDB = MarketingForeverDB or {
    minimap = { angle = 225 },
    messages = {},
}

local CHANNELS = {
    { id = "SAY",            label = "Say" },
    { id = "YELL",           label = "Yell" },
    { id = "PARTY",          label = "Party" },
    { id = "RAID",           label = "Raid" },
    { id = "INSTANCE_CHAT",  label = "Instance" },
    { id = "GUILD",          label = "Guild" },
    { id = "OFFICER",        label = "Officer" },
    { id = "RAID_WARNING",   label = "Raid Warning" },
    { id = "CHANNEL",        label = "Channel (number)" },
    { id = "WHISPER",        label = "Whisper" },
}

local function GetChannelLabel(channelId)
    for _, c in ipairs(CHANNELS) do
        if c.id == channelId then return c.label end
    end
    return channelId or "Say"
end

local function SafeSendChatMessage(msg, chatType, language, target)
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(msg, chatType, language, target)
    elseif SendChatMessage then
        SendChatMessage(msg, chatType, language, target)
    end
end

local function SendMessageViaEditBox(message, chatType, target)
    local editBox = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if not editBox then
        editBox = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox
    end
    if not editBox then
        SafeSendChatMessage(message, chatType, nil, target)
        return
    end

    local oldType = editBox:GetAttribute("chatType") or "SAY"
    local oldTell = editBox:GetAttribute("tellTarget")
    local oldChannel = editBox:GetAttribute("channelTarget")
    local oldText = editBox:GetText() or ""

    editBox:SetAttribute("chatType", chatType)
    if chatType == "WHISPER" then
        editBox:SetAttribute("tellTarget", target or "")
        editBox:SetAttribute("channelTarget", nil)
    elseif chatType == "CHANNEL" then
        editBox:SetAttribute("channelTarget", tonumber(target) or 1)
        editBox:SetAttribute("tellTarget", nil)
    else
        editBox:SetAttribute("tellTarget", nil)
        editBox:SetAttribute("channelTarget", nil)
    end

    editBox:SetText(message)

    if ChatEdit_SendText then
        ChatEdit_SendText(editBox, 1)
    else
        SafeSendChatMessage(message, chatType, nil, target)
    end

    editBox:SetAttribute("chatType", oldType)
    editBox:SetAttribute("tellTarget", oldTell)
    editBox:SetAttribute("channelTarget", oldChannel)
    editBox:SetText(oldText)

    if ChatEdit_UpdateHeader then
        ChatEdit_UpdateHeader(editBox)
    end
end

local function SendSavedMessage(msg)
    if not msg or not msg.text or msg.text == "" then return end
    local chatType = msg.channel or "SAY"
    local target = msg.target
    if chatType == "CHANNEL" and target then
        local num = tonumber(target)
        if not num then
            local id = GetChannelName(target)
            if id and id > 0 then target = id end
        end
    end
    SendMessageViaEditBox(msg.text, chatType, target)
end

local minimapButton

local function UpdateMinimapButtonPosition()
    if not minimapButton then return end
    local angle = MarketingForeverDB.minimap.angle or 225
    local radius = (Minimap:GetWidth() / 2) + 4
    local x = math.cos(math.rad(angle)) * radius
    local y = math.sin(math.rad(angle)) * radius
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CreateMinimapButton()
    if minimapButton then return end

    minimapButton = CreateFrame("Button", "MarketingForeverMinimapButton", Minimap)
    minimapButton:SetSize(31, 31)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")

    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\MarketingForever\\GnomeIcon")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    minimapButton.icon = icon

    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", -11, 11)

    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    minimapButton:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            MarketingForever_ToggleFrame()
        end
    end)

    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Marketing Forever", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click: Open message manager", 1, 1, 1)
        GameTooltip:AddLine("Drag to reposition", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", GameTooltip.Hide)

    local isDragging = false
    minimapButton:SetScript("OnDragStart", function(self)
        isDragging = true
        self:SetScript("OnUpdate", function()
            if isDragging then
                local mx, my = Minimap:GetCenter()
                local cx, cy = GetCursorPosition()
                local scale = UIParent:GetEffectiveScale()
                cx, cy = cx / scale, cy / scale
                local angle = math.deg(math.atan2(cy - my, cx - mx))
                MarketingForeverDB.minimap.angle = angle
                UpdateMinimapButtonPosition()
            end
        end)
    end)
    minimapButton:SetScript("OnDragStop", function(self)
        isDragging = false
        self:SetScript("OnUpdate", nil)
    end)

    UpdateMinimapButtonPosition()
end

-- (remaining UI code unchanged from previous version)
