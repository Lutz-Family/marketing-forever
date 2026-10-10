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
    local radius = 80
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

    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Horn_01")
    icon:SetAllPoints()
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

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

local mainFrame
local scrollChild
local messageRows = {}
local titleEdit, textEdit, channelDropdown, targetEdit
local selectedChannel = "YELL"

local function RefreshMessageList()
    if not scrollChild then return end

    for _, row in ipairs(messageRows) do
        row:Hide()
        row:SetParent(nil)
    end
    wipe(messageRows)

    local y = -4
    for i, msg in ipairs(MarketingForeverDB.messages) do
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetSize(380, 40)
        row:SetPoint("TOPLEFT", 6, y)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.4)

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("LEFT", 8, 6)
        title:SetText(msg.title or ("Message " .. i))
        title:SetTextColor(1, 0.82, 0)

        local chan = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        chan:SetPoint("LEFT", 8, -10)
        local targetText = ""
        if msg.channel == "CHANNEL" and msg.target then
            targetText = " #" .. tostring(msg.target)
        elseif msg.channel == "WHISPER" and msg.target then
            targetText = " to " .. tostring(msg.target)
        end
        chan:SetText(GetChannelLabel(msg.channel) .. targetText)
        chan:SetTextColor(0.75, 0.75, 0.75)

        local sendBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        sendBtn:SetSize(54, 22)
        sendBtn:SetPoint("RIGHT", -6, 0)
        sendBtn:SetText("Send")
        sendBtn:SetScript("OnClick", function()
            SendSavedMessage(msg)
        end)

        local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        delBtn:SetSize(46, 22)
        delBtn:SetPoint("RIGHT", sendBtn, "LEFT", -4, 0)
        delBtn:SetText("Del")
        delBtn:SetScript("OnClick", function()
            table.remove(MarketingForeverDB.messages, i)
            RefreshMessageList()
        end)

        table.insert(messageRows, row)
        y = y - 44
    end

    scrollChild:SetHeight(math.max(100, math.abs(y) + 8))
end

local function CreateMainFrame()
    if mainFrame then return end

    mainFrame = CreateFrame("Frame", "MarketingForeverFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(440, 520)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:Hide()

    mainFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\AddOns\\MarketingForever\\SquareIron",
        tile = true,
        tileSize = 32,
        edgeSize = 24,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    mainFrame:SetBackdropColor(0.08, 0.08, 0.08, 0.92)
    mainFrame:SetBackdropBorderColor(0.7, 0.65, 0.55, 1)

    local titleText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    titleText:SetPoint("TOP", 0, -14)
    titleText:SetText("Marketing Forever")
    titleText:SetTextColor(1, 0.85, 0.6)

    local closeX = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", -4, -4)
    closeX:SetScript("OnClick", function() mainFrame:Hide() end)

    local adder = CreateFrame("Frame", nil, mainFrame)
    adder:SetPoint("TOPLEFT", 16, -40)
    adder:SetPoint("TOPRIGHT", -16, -40)
    adder:SetHeight(140)

    local adderBg = adder:CreateTexture(nil, "BACKGROUND")
    adderBg:SetAllPoints()
    adderBg:SetColorTexture(0.05, 0.05, 0.05, 0.5)

    local titleLabel = adder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLabel:SetPoint("TOPLEFT", 8, -8)
    titleLabel:SetText("Title:")

    titleEdit = CreateFrame("EditBox", nil, adder, "InputBoxTemplate")
    titleEdit:SetSize(280, 22)
    titleEdit:SetPoint("LEFT", titleLabel, "RIGHT", 6, 0)
    titleEdit:SetAutoFocus(false)
    titleEdit:SetMaxLetters(40)

    local msgLabel = adder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    msgLabel:SetPoint("TOPLEFT", 8, -36)
    msgLabel:SetText("Message:")

    textEdit = CreateFrame("EditBox", nil, adder, "InputBoxTemplate")
    textEdit:SetSize(340, 22)
    textEdit:SetPoint("TOPLEFT", msgLabel, "BOTTOMLEFT", 0, -4)
    textEdit:SetAutoFocus(false)
    textEdit:SetMaxLetters(255)

    local chanLabel = adder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chanLabel:SetPoint("TOPLEFT", 8, -78)
    chanLabel:SetText("Channel:")

    channelDropdown = CreateFrame("Frame", "MFChannelDrop", adder, "UIDropDownMenuTemplate")
    channelDropdown:SetPoint("LEFT", chanLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(channelDropdown, 130)
    UIDropDownMenu_SetText(channelDropdown, "Yell")

    local function OnChannelSelect(self)
        selectedChannel = self.value
        UIDropDownMenu_SetText(channelDropdown, self:GetText())
        if selectedChannel == "CHANNEL" or selectedChannel == "WHISPER" then
            targetEdit:Show()
        else
            targetEdit:Hide()
        end
    end

    UIDropDownMenu_Initialize(channelDropdown, function()
        for _, c in ipairs(CHANNELS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = c.label
            info.value = c.id
            info.func = OnChannelSelect
            info.checked = (c.id == selectedChannel)
            UIDropDownMenu_AddButton(info)
        end
    end)

    targetEdit = CreateFrame("EditBox", nil, adder, "InputBoxTemplate")
    targetEdit:SetSize(120, 22)
    targetEdit:SetPoint("LEFT", channelDropdown, "RIGHT", 4, 2)
    targetEdit:SetAutoFocus(false)
    targetEdit:SetMaxLetters(30)
    targetEdit:SetText("1")
    targetEdit:Hide()

    local saveBtn = CreateFrame("Button", nil, adder, "UIPanelButtonTemplate")
    saveBtn:SetSize(90, 22)
    saveBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        local title = titleEdit:GetText()
        local text = textEdit:GetText()
        if text == "" then
            print("|cffff0000Marketing Forever|r: Message cannot be empty.")
            return
        end
        if title == "" then
            title = text:sub(1, 22) .. (text:len() > 22 and "..." or "")
        end

        table.insert(MarketingForeverDB.messages, {
            title = title,
            text = text,
            channel = selectedChannel,
            target = (selectedChannel == "CHANNEL" or selectedChannel == "WHISPER") and targetEdit:GetText() or nil,
        })

        titleEdit:SetText("")
        textEdit:SetText("")
        targetEdit:SetText("1")
        RefreshMessageList()
        print("|cff00ccffMarketing Forever|r: Saved.")
    end)

    local listLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listLabel:SetPoint("TOPLEFT", 20, -188)
    listLabel:SetText("Saved Messages")
    listLabel:SetTextColor(0.9, 0.8, 0.5)

    local scroll = CreateFrame("ScrollFrame", nil, mainFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -208)
    scroll:SetPoint("BOTTOMRIGHT", -30, 48)

    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(380, 200)
    scroll:SetScrollChild(scrollChild)

    local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 24)
    closeBtn:SetPoint("BOTTOMRIGHT", -16, 12)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)

    mainFrame:SetScript("OnShow", RefreshMessageList)
end

function MarketingForever_ToggleFrame()
    CreateMainFrame()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        RefreshMessageList()
    end
end

function MarketingForever_OnCompartmentClick()
    MarketingForever_ToggleFrame()
end

function MarketingForever_OnCompartmentEnter(addonName, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
    GameTooltip:SetText("Marketing Forever", 1, 0.82, 0)
    GameTooltip:AddLine("Click to open", 1, 1, 1)
    GameTooltip:Show()
end

function MarketingForever_OnCompartmentLeave()
    GameTooltip:Hide()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        MarketingForeverDB = MarketingForeverDB or {}
        MarketingForeverDB.minimap = MarketingForeverDB.minimap or { angle = 225 }
        MarketingForeverDB.messages = MarketingForeverDB.messages or {}
        CreateMinimapButton()
    elseif event == "PLAYER_LOGIN" then
        CreateMinimapButton()
        print("|cff00ccffMarketing Forever|r loaded. Horn icon or /mf")
    end
end)

SLASH_MARKETINGFOREVER1 = "/mf"
SLASH_MARKETINGFOREVER2 = "/marketingforever"
SlashCmdList["MARKETINGFOREVER"] = function()
    MarketingForever_ToggleFrame()
end
