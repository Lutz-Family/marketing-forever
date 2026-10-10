-- Marketing Forever
-- WoW Forever (Interface 16001) - Minimap marketing message manager
-- Author: SirEggbert / Makers Forge

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

-- Safe chat send that prefers modern API
local function SafeSendChatMessage(msg, chatType, language, target)
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(msg, chatType, language, target)
    elseif SendChatMessage then
        SendChatMessage(msg, chatType, language, target)
    end
end

-- Place message in chat edit box, send it, then restore previous channel
local function SendMessageViaEditBox(message, chatType, target)
    local editBox = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if not editBox then
        editBox = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox
    end
    if not editBox then
        -- Fallback to direct send if no edit box
        SafeSendChatMessage(message, chatType, nil, target)
        return
    end

    -- Save previous state
    local oldType = editBox:GetAttribute("chatType") or "SAY"
    local oldTell = editBox:GetAttribute("tellTarget")
    local oldChannel = editBox:GetAttribute("channelTarget")
    local oldText = editBox:GetText() or ""

    -- Apply new channel
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

    -- Send
    if ChatEdit_SendText then
        ChatEdit_SendText(editBox, 1)
    else
        SafeSendChatMessage(message, chatType, nil, target)
    end

    -- Restore previous channel / text
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
        -- Resolve name to number if needed
        local num = tonumber(target)
        if not num then
            local id = GetChannelName(target)
            if id and id > 0 then target = id end
        end
    end
    SendMessageViaEditBox(msg.text, chatType, target)
end

-- ==================== Minimap Button ====================
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
    minimapButton.icon = icon

    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", -11, 11)

    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    minimapButton:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            MarketingForever_ToggleFrame()
        elseif button == "RightButton" then
            print("|cff00ccffMarketing Forever|r: Right-click reserved for future options.")
        end
    end)

    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Marketing Forever", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click: Open message manager", 1, 1, 1)
        GameTooltip:AddLine("Drag to reposition", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Dragging
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

-- ==================== Main Frame ====================
local mainFrame
local scrollChild
local messageButtons = {}

local function RefreshMessageList()
    if not scrollChild then return end

    -- Clear old
    for _, btn in ipairs(messageButtons) do
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(messageButtons)

    local y = -8
    for i, msg in ipairs(MarketingForeverDB.messages) do
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetSize(360, 36)
        row:SetPoint("TOPLEFT", 8, y)

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("LEFT", 4, 6)
        title:SetText(msg.title or ("Message " .. i))
        title:SetTextColor(1, 0.82, 0)

        local chan = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        chan:SetPoint("LEFT", 4, -10)
        local targetText = ""
        if msg.channel == "CHANNEL" and msg.target then
            targetText = " #" .. tostring(msg.target)
        elseif msg.channel == "WHISPER" and msg.target then
            targetText = " to " .. tostring(msg.target)
        end
        chan:SetText(GetChannelLabel(msg.channel) .. targetText)
        chan:SetTextColor(0.7, 0.7, 0.7)

        local sendBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        sendBtn:SetSize(60, 22)
        sendBtn:SetPoint("RIGHT", -4, 0)
        sendBtn:SetText("Send")
        sendBtn:SetScript("OnClick", function()
            SendSavedMessage(msg)
        end)

        local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        delBtn:SetSize(50, 22)
        delBtn:SetPoint("RIGHT", sendBtn, "LEFT", -4, 0)
        delBtn:SetText("Del")
        delBtn:SetScript("OnClick", function()
            table.remove(MarketingForeverDB.messages, i)
            RefreshMessageList()
        end)

        table.insert(messageButtons, row)
        y = y - 40
    end

    scrollChild:SetHeight(math.max(200, math.abs(y) + 20))
end

local function CreateMainFrame()
    if mainFrame then return end

    mainFrame = CreateFrame("Frame", "MarketingForeverFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(420, 480)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:SetClampedToScreen(true)
    mainFrame:Hide()

    mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mainFrame.title:SetPoint("TOP", 0, -6)
    mainFrame.title:SetText("Marketing Forever")

    -- Scroll frame for list
    local scroll = CreateFrame("ScrollFrame", nil, mainFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 80)

    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(360, 200)
    scroll:SetScrollChild(scrollChild)

    -- Add button
    local addBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    addBtn:SetSize(120, 24)
    addBtn:SetPoint("BOTTOMLEFT", 16, 16)
    addBtn:SetText("Add Message")
    addBtn:SetScript("OnClick", function()
        MarketingForever_OpenEditor()
    end)

    -- Close
    local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 24)
    closeBtn:SetPoint("BOTTOMRIGHT", -16, 16)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        mainFrame:Hide()
    end)

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

-- ==================== Editor Frame ====================
local editorFrame
local titleEdit, textEdit, channelDropdown, targetEdit

local function CreateEditor()
    if editorFrame then return end

    editorFrame = CreateFrame("Frame", "MarketingForeverEditor", UIParent, "BasicFrameTemplateWithInset")
    editorFrame:SetSize(400, 280)
    editorFrame:SetPoint("CENTER", 40, 40)
    editorFrame:SetMovable(true)
    editorFrame:EnableMouse(true)
    editorFrame:RegisterForDrag("LeftButton")
    editorFrame:SetScript("OnDragStart", editorFrame.StartMoving)
    editorFrame:SetScript("OnDragStop", editorFrame.StopMovingOrSizing)
    editorFrame:SetClampedToScreen(true)
    editorFrame:Hide()

    editorFrame.title = editorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    editorFrame.title:SetPoint("TOP", 0, -6)
    editorFrame.title:SetText("New Message")

    -- Title
    local titleLabel = editorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLabel:SetPoint("TOPLEFT", 16, -36)
    titleLabel:SetText("Title:")

    titleEdit = CreateFrame("EditBox", nil, editorFrame, "InputBoxTemplate")
    titleEdit:SetSize(260, 24)
    titleEdit:SetPoint("LEFT", titleLabel, "RIGHT", 8, 0)
    titleEdit:SetAutoFocus(false)
    titleEdit:SetMaxLetters(40)

    -- Message text
    local textLabel = editorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    textLabel:SetPoint("TOPLEFT", 16, -70)
    textLabel:SetText("Message:")

    textEdit = CreateFrame("EditBox", nil, editorFrame, "InputBoxTemplate")
    textEdit:SetSize(340, 24)
    textEdit:SetPoint("TOPLEFT", textLabel, "BOTTOMLEFT", 0, -6)
    textEdit:SetAutoFocus(false)
    textEdit:SetMaxLetters(255)
    textEdit:SetMultiLine(false)

    -- Channel
    local chanLabel = editorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chanLabel:SetPoint("TOPLEFT", 16, -130)
    chanLabel:SetText("Channel:")

    channelDropdown = CreateFrame("Frame", "MarketingForeverChannelDrop", editorFrame, "UIDropDownMenuTemplate")
    channelDropdown:SetPoint("LEFT", chanLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(channelDropdown, 140)
    UIDropDownMenu_SetText(channelDropdown, "Yell")

    local selectedChannel = "YELL"
    local function OnChannelSelect(self)
        selectedChannel = self.value
        UIDropDownMenu_SetText(channelDropdown, self:GetText())
        if targetEdit then
            if selectedChannel == "CHANNEL" or selectedChannel == "WHISPER" then
                targetEdit:Show()
            else
                targetEdit:Hide()
            end
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

    -- Target (for Channel / Whisper)
    targetEdit = CreateFrame("EditBox", nil, editorFrame, "InputBoxTemplate")
    targetEdit:SetSize(140, 24)
    targetEdit:SetPoint("LEFT", channelDropdown, "RIGHT", 8, 2)
    targetEdit:SetAutoFocus(false)
    targetEdit:SetMaxLetters(30)
    targetEdit:SetText("1")
    targetEdit:Hide()

    -- Save / Cancel
    local saveBtn = CreateFrame("Button", nil, editorFrame, "UIPanelButtonTemplate")
    saveBtn:SetSize(100, 24)
    saveBtn:SetPoint("BOTTOMLEFT", 16, 16)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        local title = titleEdit:GetText()
        local text = textEdit:GetText()
        if text == "" then
            print("|cffff0000Marketing Forever|r: Message text cannot be empty.")
            return
        end
        if title == "" then title = text:sub(1, 20) .. (text:len() > 20 and "..." or "") end

        local entry = {
            title = title,
            text = text,
            channel = selectedChannel,
            target = (selectedChannel == "CHANNEL" or selectedChannel == "WHISPER") and targetEdit:GetText() or nil,
        }
        table.insert(MarketingForeverDB.messages, entry)
        editorFrame:Hide()
        if mainFrame and mainFrame:IsShown() then
            RefreshMessageList()
        end
        print("|cff00ccffMarketing Forever|r: Message saved.")
    end)

    local cancelBtn = CreateFrame("Button", nil, editorFrame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 24)
    cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        editorFrame:Hide()
    end)

    -- Store selected for later use
    editorFrame.selectedChannel = function() return selectedChannel end
    editorFrame.setSelected = function(id)
        selectedChannel = id
        UIDropDownMenu_SetText(channelDropdown, GetChannelLabel(id))
    end
end

function MarketingForever_OpenEditor(existing)
    CreateEditor()
    titleEdit:SetText("")
    textEdit:SetText("")
    if editorFrame.setSelected then editorFrame.setSelected("YELL") end
    targetEdit:SetText("1")
    targetEdit:Hide()
    editorFrame:Show()
    titleEdit:SetFocus()
end

-- ==================== Addon Compartment ====================
function MarketingForever_OnCompartmentClick()
    MarketingForever_ToggleFrame()
end

function MarketingForever_OnCompartmentEnter(addonName, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
    GameTooltip:SetText("Marketing Forever", 1, 0.82, 0)
    GameTooltip:AddLine("Click to open message manager", 1, 1, 1)
    GameTooltip:Show()
end

function MarketingForever_OnCompartmentLeave()
    GameTooltip:Hide()
end

-- ==================== Events / Init ====================
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        -- Ensure structure
        MarketingForeverDB = MarketingForeverDB or {}
        MarketingForeverDB.minimap = MarketingForeverDB.minimap or { angle = 225 }
        MarketingForeverDB.messages = MarketingForeverDB.messages or {}
        CreateMinimapButton()
    elseif event == "PLAYER_LOGIN" then
        CreateMinimapButton()
        print("|cff00ccffMarketing Forever|r loaded. Click the horn icon or type /mf")
    end
end)

-- Slash commands
SLASH_MARKETINGFOREVER1 = "/mf"
SLASH_MARKETINGFOREVER2 = "/marketingforever"
SlashCmdList["MARKETINGFOREVER"] = function(msg)
    MarketingForever_ToggleFrame()
end
