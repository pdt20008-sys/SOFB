--[[
    ╔═══════════════════════════════════════════════╗
    ║       Origin's SOFB Hub  v3.0                 ║
    ║  Login │ Key System │ UI Library │ Auto-TP    ║
    ╚═══════════════════════════════════════════════╝
]]

local Players       = game:GetService("Players")
local UIS           = game:GetService("UserInputService")
local RunService    = game:GetService("RunService")
local TweenService  = game:GetService("TweenService")
local Lighting      = game:GetService("Lighting")
local VirtualUser   = game:GetService("VirtualUser")
local HttpService   = game:GetService("HttpService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera    = workspace.CurrentCamera

-- ════════════════════════════════════════════
--  AUTH CONFIG
-- ════════════════════════════════════════════
local OWNER_KEY = "originsofbh21212026"
local WEBHOOK_URL = "https://discord.com/api/webhooks/1487277799046778971/dMkVYU53C6N8AQVmJ8Tp9I8kIAhTvO98UDjiPN-9E3rQGB0ck6pqa8CvdjHECpS2ULcs"

-- 🔴 REMOTE DATABASE INFO 🔴
-- To sync keys across different PCs for other users, you need a central database!
-- Recommended: Set up a free Firebase Realtime Database (with public read/write rules)
-- Paste the URL here (MUST end in .json). If left empty, keys will ONLY save locally to your PC.
local DATABASE_URL = "https://sofb-7bc89-default-rtdb.europe-west1.firebasedatabase.app/keys.json"

local KEY_STORE_NAME = "SOFBHub_Keys_v3"
local SESSION_STORE = "SOFBHub_Session_v3"

-- ════════════════════════════════════════════
--  KEY PERSISTENCE (writefile/readfile)
-- ════════════════════════════════════════════
--  FILE I/O  (executor-agnostic)
-- ════════════════════════════════════════════
local function safeWrite(filename, data)
    pcall(function() writefile(filename, data) end)
end

local function safeRead(filename)
    local ok, result = pcall(function() return readfile(filename) end)
    return ok and result or nil
end

local function universalRequest(options)
    local req = nil
    if syn and syn.request then req = syn.request
    elseif http and http.request then req = http.request
    elseif typeof(request) == "function" then req = request
    elseif fluxus and fluxus.request then req = fluxus.request
    end
    if req then
        local ok, res = pcall(req, options)
        return ok and res or nil
    end
    return nil
end

local function saveKeys(keys)
    if DATABASE_URL ~= "" and type(DATABASE_URL) == "string" then
        -- Sync to cloud database
        universalRequest({Url = DATABASE_URL, Method = "PUT", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(keys)})
    else
        -- Fallback to local file if no cloud DB configured
        safeWrite(KEY_STORE_NAME .. ".json", HttpService:JSONEncode(keys))
    end
end

local function loadKeys()
    if DATABASE_URL ~= "" and type(DATABASE_URL) == "string" then
        -- Read from cloud database
        local res = universalRequest({Url = DATABASE_URL, Method = "GET"})
        if res and res.Body and res.Body ~= "null" then
            local ok, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
            if ok and type(data) == "table" then return data end
        end
        return {}
    else
        -- Read from local file
        local raw = safeRead(KEY_STORE_NAME .. ".json")
        if not raw or raw == "" then return {} end
        local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
        return ok and type(data) == "table" and data or {}
    end
end

local function saveSession(key)
    safeWrite(SESSION_STORE .. ".txt", key)
end

local function loadSession()
    local raw = safeRead(SESSION_STORE .. ".txt")
    return (raw and raw ~= "") and raw or nil
end

-- ════════════════════════════════════════════
--  DISCORD WEBHOOK
-- ════════════════════════════════════════════
-- ════════════════════════════════════════════
--  DISCORD WEBHOOK  (executor-agnostic)
-- ════════════════════════════════════════════
local function sendWebhook(title, desc, color, fields)
    pcall(function()
        local embed = {
            title = title,
            description = desc,
            color = color or 9442302,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            footer = {text = "Origin's SOFB Hub v3.0"},
            fields = fields or {}
        }
        local payload = HttpService:JSONEncode({embeds = {embed}})
        universalRequest({Url = WEBHOOK_URL, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = payload})
    end)
end

-- ════════════════════════════════════════════
--  KEY VALIDATION
-- ════════════════════════════════════════════
local validKeys = loadKeys()
local isOwner = false
local isAuthenticated = false

local function generateKey()
    -- Use HttpService's native UUID generator to absolutely guarantee uniqueness
    local guid = HttpService:GenerateGUID(false):gsub("-", "")
    return ("SOFB-%s-%s-%s-%s"):format(
        guid:sub(1, 5),
        guid:sub(6, 10),
        guid:sub(11, 15),
        guid:sub(16, 20)
    ):upper()
end

local function validateKey(input)
    if input == OWNER_KEY then
        isOwner = true
        isAuthenticated = true
        return true, "owner"
    end
    -- Always reload keys from file to catch keys generated in previous sessions
    validKeys = loadKeys()
    for _, k in ipairs(validKeys) do
        if k.key == input and k.active then
            isAuthenticated = true
            return true, "user"
        end
    end
    return false, nil
end

-- ════════════════════════════════════════════
--  SETTINGS
-- ════════════════════════════════════════════
local Settings = {
    WalkSpeed    = 200,
    JumpPower    = 50,
    SpeedLock    = true,
    JumpLock     = false,
    AutoTP       = false,
    ScanRate     = 0.5,
    TPCooldown   = 2,
    AntiAFK      = true,
    Noclip       = false,
    Fullbright   = false,
    ESP          = false,
    Sounds       = true,
    Binds        = {
        Zone12     = "G",
        PlotBase   = "B",
        ToggleHub  = "RightShift",
        AdminPanel = "K",
    },
    Rarities     = {
        NORMAL = false, GOLDEN = false, DIAMOND = false, EMERALD = false,
        RUBY = true, RAINBOW = true, VOID = true, ETHEREAL = true, CELESTIAL = true,
    },
}

local RarityOrder = {"NORMAL","GOLDEN","DIAMOND","EMERALD","RUBY","RAINBOW","VOID","ETHEREAL","CELESTIAL"}

local Stats = {SessionStart = tick(), TotalTPs = 0, RarityFinds = {}}
for _,r in ipairs(RarityOrder) do Stats.RarityFinds[r]=0 end

local HttpService = game:GetService("HttpService")
local SETTINGS_FILE = "SOFB_Hub_Settings.json"

_G.saveSettings = function()
    pcall(function()
        if writefile then writefile(SETTINGS_FILE, HttpService:JSONEncode(Settings)) end
    end)
end

local function loadSettings()
    pcall(function()
        if readfile then
            local raw = readfile(SETTINGS_FILE)
            if raw then
                local data = HttpService:JSONDecode(raw)
                for k, v in pairs(data) do
                    if type(v) == "table" and type(Settings[k]) == "table" then
                        for k2, v2 in pairs(v) do Settings[k][k2] = v2 end
                    else
                        Settings[k] = v
                    end
                end
            end
        end
    end)
end
loadSettings()

-- Auto-saver daemon
task.spawn(function() while task.wait(5) do _G.saveSettings() end end)

-- ════════════════════════════════════════════
--  THEME v3 — Premium Dark
-- ════════════════════════════════════════════
local T = {
    Bg         = Color3.fromRGB(12, 11, 15),       -- Rich darker background
    BgSecondary= Color3.fromRGB(16, 15, 20),
    Surface    = Color3.fromRGB(24, 22, 29),       -- Upgraded surface brightness
    SurfaceHover= Color3.fromRGB(30, 28, 36),
    TopBar     = Color3.fromRGB(18, 16, 22),
    Section    = Color3.fromRGB(20, 18, 24),
    Accent     = Color3.fromRGB(150, 95, 255),     -- Deep violet accent
    AccentSoft = Color3.fromRGB(80, 50, 160),      -- Darker soft accent for panels
    AccentGlow = Color3.fromRGB(210, 170, 255),    -- Glow pop for text inside accents
    AccentDark = Color3.fromRGB(60, 35, 110),
    Text       = Color3.fromRGB(250, 250, 255),
    TextDim    = Color3.fromRGB(160, 155, 180),
    TextMuted  = Color3.fromRGB(100, 95, 120),
    Border     = Color3.fromRGB(38, 35, 48),
    BorderLight= Color3.fromRGB(50, 47, 60),
    Input      = Color3.fromRGB(16, 14, 20),
    InputFocus = Color3.fromRGB(28, 26, 32),
    LogBg      = Color3.fromRGB(10, 9, 13),
    Knob       = Color3.fromRGB(240, 240, 250),
    -- Toggles
    On         = Color3.fromRGB(35, 180, 110),     -- Vivid jade
    OnDark     = Color3.fromRGB(20, 110, 65),
    Off        = Color3.fromRGB(100, 95, 120),
    -- Notifications
    Success    = Color3.fromRGB(45, 230, 145),
    Warning    = Color3.fromRGB(255, 180, 55),
    Danger     = Color3.fromRGB(250, 65, 85),
    Info       = Color3.fromRGB(80, 150, 255),
    TabActive  = Color3.fromRGB(150, 95, 255),
    TabInactive= Color3.fromRGB(45, 45, 65),
    Rarity = {
        NORMAL = Color3.fromRGB(180,180,190), GOLDEN = Color3.fromRGB(255,190,30),
        DIAMOND = Color3.fromRGB(0,200,255), EMERALD = Color3.fromRGB(120,255,40),
        RUBY = Color3.fromRGB(255,30,80), RAINBOW = Color3.fromRGB(255,60,200),
        VOID = Color3.fromRGB(130,50,210), ETHEREAL = Color3.fromRGB(100,40,180),
        CELESTIAL = Color3.fromRGB(220,30,120),
    },
    RarityTier = {
        NORMAL="⬜ Common", GOLDEN="🟨 Uncommon", DIAMOND="🟦 Rare",
        EMERALD="🟩 Epic", RUBY="🟥 Legendary", RAINBOW="🌈 Mythic",
        VOID="🟪 Mythic+", ETHEREAL="👁 Godly", CELESTIAL="⭐ Supreme",
    },
}

-- ════════════════════════════════════════════
--  HELPERS
-- ════════════════════════════════════════════
local function corner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 6); c.Parent = p; return c
end
local function stroke(p, col, th)
    local s = Instance.new("UIStroke"); s.Color = col or T.Border; s.Thickness = th or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = p; return s
end
local function pad(p, t, b, l, r)
    local u = Instance.new("UIPadding")
    u.PaddingTop=UDim.new(0,t or 8); u.PaddingBottom=UDim.new(0,b or 8)
    u.PaddingLeft=UDim.new(0,l or 10); u.PaddingRight=UDim.new(0,r or 10)
    u.Parent = p; return u
end
local function tw(obj, props, dur, style, dir)
    local ti = TweenInfo.new(dur or 0.25, style or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out)
    local t = TweenService:Create(obj, ti, props); t:Play(); return t
end
local function formatTime(s)
    local h = math.floor(s/3600); local m = math.floor((s%3600)/60); local sec = math.floor(s%60)
    if h > 0 then return string.format("%dh %dm %ds",h,m,sec)
    elseif m > 0 then return string.format("%dm %ds",m,sec) end
    return string.format("%ds",sec)
end
local function gradient(p, c1, c2, rot)
    local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(c1, c2)
    g.Rotation = rot or 90; g.Parent = p; return g
end

-- ════════════════════════════════════════════
--  STATIC BOTTOM-UP GRADIENTS
-- ════════════════════════════════════════════
local function applyDarkGradient(frame)
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, Color3.new(0.4, 0.4, 0.4))
    })
    grad.Parent = frame
    return grad
end

-- ════════════════════════════════════════════
--  LOG SYSTEM
-- ════════════════════════════════════════════
local logLines = {}
local logRefresh
local function addLog(msg)
    table.insert(logLines, os.date("[%H:%M:%S] ") .. msg)
    if #logLines > 80 then table.remove(logLines, 1) end
    if logRefresh then logRefresh() end
end

-- ════════════════════════════════════════════
--  CLEAN OLD GUI
-- ════════════════════════════════════════════
for _, g in ipairs(playerGui:GetChildren()) do
    if g.Name == "SOFBHub" or g.Name == "SOFBLogin" then g:Destroy() end
end

local gui = Instance.new("ScreenGui")
gui.Name = "SOFBHub"; gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.DisplayOrder = 100
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- ════════════════════════════════════════════
--  NOTIFICATION SYSTEM v3 — Glass Toasts
-- ════════════════════════════════════════════
local notifContainer = Instance.new("Frame")
notifContainer.Name = "Notifications"
notifContainer.Size = UDim2.new(0, 320, 1, 0)
notifContainer.Position = UDim2.new(1, -330, 0, 0)
notifContainer.BackgroundTransparency = 1
notifContainer.Parent = gui

local notifLayout = Instance.new("UIListLayout")
notifLayout.SortOrder = Enum.SortOrder.LayoutOrder
notifLayout.Padding = UDim.new(0, 8)
notifLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
notifLayout.Parent = notifContainer

local notifPadding = Instance.new("UIPadding")
notifPadding.PaddingBottom = UDim.new(0, 16)
notifPadding.Parent = notifContainer

local notifCount = 0

local NOTIF_TYPES = {
    success = {icon = "✓", color = T.On, glow = Color3.fromRGB(40, 180, 80)},
    error   = {icon = "✕", color = T.Danger, glow = Color3.fromRGB(200, 40, 40)},
    warning = {icon = "⚠", color = T.Warning, glow = Color3.fromRGB(200, 160, 30)},
    info    = {icon = "◈", color = T.Accent, glow = T.AccentDark},
    rarity  = {icon = "⚡", color = T.Accent, glow = T.AccentDark},
}

local function notify(title, body, nType, duration, customColor)
    notifCount = notifCount + 1
    local order = notifCount
    local style = NOTIF_TYPES[nType or "info"] or NOTIF_TYPES.info
    local color = customColor or style.color
    duration = duration or 4

    local card = Instance.new("Frame")
    card.Name = "Notif_"..order; card.Size = UDim2.new(1, 0, 0, 0)
    card.BackgroundColor3 = Color3.fromRGB(14, 14, 24); card.BackgroundTransparency = 1
    card.BorderSizePixel = 0; card.LayoutOrder = order; card.ClipsDescendants = true
    card.Parent = notifContainer
    corner(card, 12)

    -- Glass overlay
    local glass = Instance.new("Frame")
    glass.Size = UDim2.new(1, 0, 1, 0); glass.BackgroundColor3 = color
    glass.BackgroundTransparency = 0.94; glass.BorderSizePixel = 0; glass.Parent = card

    local cardStroke = stroke(card, color, 1); cardStroke.Transparency = 1

    -- Accent bar
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 3, 1, -12); bar.Position = UDim2.new(0, 8, 0, 6)
    bar.BackgroundColor3 = color; bar.BorderSizePixel = 0; bar.BackgroundTransparency = 1
    bar.Parent = card; corner(bar, 2)

    -- Icon circle
    local iconBg = Instance.new("Frame")
    iconBg.Size = UDim2.new(0, 28, 0, 28); iconBg.Position = UDim2.new(0, 18, 0, 10)
    iconBg.BackgroundColor3 = color; iconBg.BackgroundTransparency = 0.85
    iconBg.BorderSizePixel = 0; iconBg.Parent = card; corner(iconBg, 14)

    local iconLbl = Instance.new("TextLabel")
    iconLbl.Size = UDim2.new(1, 0, 1, 0); iconLbl.BackgroundTransparency = 1
    iconLbl.Text = style.icon; iconLbl.TextColor3 = color; iconLbl.TextSize = 14
    iconLbl.Font = Enum.Font.GothamBold; iconLbl.TextTransparency = 1; iconLbl.Parent = iconBg

    -- Title
    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -60, 0, 16); titleLbl.Position = UDim2.new(0, 52, 0, 8)
    titleLbl.BackgroundTransparency = 1; titleLbl.Text = title; titleLbl.TextColor3 = T.Text
    titleLbl.TextSize = 13; titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.TextTransparency = 1
    titleLbl.Parent = card

    -- Body
    local bodyLbl = Instance.new("TextLabel")
    bodyLbl.Size = UDim2.new(1, -60, 0, 0); bodyLbl.Position = UDim2.new(0, 52, 0, 26)
    bodyLbl.BackgroundTransparency = 1; bodyLbl.Text = body; bodyLbl.TextColor3 = T.TextDim
    bodyLbl.TextSize = 11; bodyLbl.Font = Enum.Font.Gotham
    bodyLbl.TextXAlignment = Enum.TextXAlignment.Left; bodyLbl.TextWrapped = true
    bodyLbl.AutomaticSize = Enum.AutomaticSize.Y; bodyLbl.TextTransparency = 1
    bodyLbl.Parent = card

    -- Progress bar
    local progBg = Instance.new("Frame")
    progBg.Size = UDim2.new(1, -24, 0, 2); progBg.Position = UDim2.new(0, 12, 1, -6)
    progBg.BackgroundColor3 = T.Off; progBg.BorderSizePixel = 0
    progBg.BackgroundTransparency = 1; progBg.Parent = card; corner(progBg, 1)

    local progFill = Instance.new("Frame")
    progFill.Size = UDim2.new(1, 0, 1, 0); progFill.BackgroundColor3 = color
    progFill.BorderSizePixel = 0; progFill.BackgroundTransparency = 1
    progFill.Parent = progBg; corner(progFill, 1)

    -- Animate in
    tw(card, {Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 0.05}, 0.35, Enum.EasingStyle.Back)
    task.delay(0.1, function()
        tw(cardStroke, {Transparency = 0.4}, 0.3)
        tw(bar, {BackgroundTransparency = 0}, 0.3)
        tw(iconLbl, {TextTransparency = 0}, 0.3)
        tw(titleLbl, {TextTransparency = 0}, 0.3)
        tw(bodyLbl, {TextTransparency = 0}, 0.3)
        tw(progBg, {BackgroundTransparency = 0}, 0.3)
        tw(progFill, {BackgroundTransparency = 0}, 0.3)
    end)
    task.delay(0.4, function()
        tw(progFill, {Size = UDim2.new(0, 0, 1, 0)}, duration - 0.8, Enum.EasingStyle.Linear)
    end)
    task.delay(duration, function()
        tw(card, {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0)}, 0.3)
        tw(cardStroke, {Transparency = 1}, 0.2)
        tw(bar, {BackgroundTransparency = 1}, 0.2)
        tw(iconLbl, {TextTransparency = 1}, 0.2)
        tw(titleLbl, {TextTransparency = 1}, 0.2)
        tw(bodyLbl, {TextTransparency = 1}, 0.2)
        tw(progBg, {BackgroundTransparency = 1}, 0.2)
        tw(progFill, {BackgroundTransparency = 1}, 0.2)
        task.delay(0.35, function() card:Destroy() end)
    end)
end

local function notifyRarity(rarity, name)
    notify("🔥  "..rarity.." FOUND!", "Teleporting to: "..name.."\n"..(T.RarityTier[rarity] or ""), "rarity", 5, T.Rarity[rarity])
end
local function notifySuccess(t, b) notify(t, b, "success", 3) end
local function notifyInfo(t, b) notify(t, b, "info", 3) end
local function notifyWarn(t, b) notify(t, b, "warning", 4) end
local function notifyError(t, b) notify(t, b, "error", 4) end

-- ══════════════════════════════════════════════════
--  LOGIN SCREEN
-- ══════════════════════════════════════════════════
local loginFrame = Instance.new("Frame")
loginFrame.Name = "LoginFrame"; loginFrame.Size = UDim2.new(1, 0, 1, 0)
loginFrame.Position = UDim2.new(0, 0, 0, 0)
loginFrame.BackgroundColor3 = Color3.fromRGB(6, 6, 12); loginFrame.BorderSizePixel = 0
loginFrame.Parent = gui

-- Subtle vignette at edges
local vignette = Instance.new("ImageLabel")
vignette.Size = UDim2.new(1, 0, 1, 0); vignette.BackgroundTransparency = 1
vignette.Image = "rbxassetid://6014261993"   -- reuse shadow asset as vignette
vignette.ImageColor3 = Color3.new(0, 0, 0); vignette.ImageTransparency = 0.55
vignette.ScaleType = Enum.ScaleType.Slice; vignette.SliceCenter = Rect.new(49,49,450,450)
vignette.ZIndex = 0; vignette.Parent = loginFrame

-- Animated bg particles (subtle)
local bgPattern = Instance.new("Frame")
bgPattern.Size = UDim2.new(1, 0, 1, 0); bgPattern.BackgroundTransparency = 1
bgPattern.Parent = loginFrame

-- Login card — starts invisible+scaled down, animates in
local loginCard = Instance.new("Frame")
loginCard.Name = "LoginCard"; loginCard.Size = UDim2.new(0, 360, 0, 340)
loginCard.Position = UDim2.new(0.5, -180, 0.5, -170)
loginCard.BackgroundColor3 = Color3.fromRGB(12, 12, 22); loginCard.BorderSizePixel = 0
applyDarkGradient(loginCard)
loginCard.ClipsDescendants = true; loginCard.BackgroundTransparency = 1; loginCard.Parent = loginFrame
corner(loginCard, 16)
local loginCardStroke = stroke(loginCard, T.Accent, 1.5)
loginCardStroke.Transparency = 1

-- Card intro animation
task.defer(function()
    task.wait(0.05)
    tw(loginCard, {BackgroundTransparency = 0}, 0.45, Enum.EasingStyle.Quart)
    tw(loginCardStroke, {Transparency = 0}, 0.45, Enum.EasingStyle.Quart)
end)

-- Login card glow
local loginGlow = Instance.new("Frame")
loginGlow.Size = UDim2.new(1, 0, 0, 3); loginGlow.Position = UDim2.new(0, 0, 0, 0)
loginGlow.BackgroundColor3 = T.Accent; loginGlow.BorderSizePixel = 0
loginGlow.Parent = loginCard
local loginGlowGrad = Instance.new("UIGradient")
loginGlowGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, T.AccentDark),
    ColorSequenceKeypoint.new(0.5, T.AccentGlow),
    ColorSequenceKeypoint.new(1, T.AccentDark),
})
loginGlowGrad.Parent = loginGlow

-- Animate glow shimmer
task.spawn(function()
    while loginGlow and loginGlow.Parent do
        loginGlowGrad.Offset = Vector2.new(-1, 0)
        tw(loginGlowGrad, {Offset = Vector2.new(1, 0)}, 2, Enum.EasingStyle.Linear)
        task.wait(2)
    end
end)

-- Logo
local logoIcon = Instance.new("TextLabel")
logoIcon.Size = UDim2.new(0, 50, 0, 50); logoIcon.Position = UDim2.new(0.5, -25, 0, 30)
logoIcon.BackgroundColor3 = T.Accent; logoIcon.BackgroundTransparency = 0.85
logoIcon.Text = "◈"; logoIcon.TextColor3 = T.AccentGlow; logoIcon.TextSize = 28
logoIcon.Font = Enum.Font.GothamBold; logoIcon.Parent = loginCard; corner(logoIcon, 25)

local loginTitle = Instance.new("TextLabel")
loginTitle.Size = UDim2.new(1, 0, 0, 22); loginTitle.Position = UDim2.new(0, 0, 0, 90)
loginTitle.BackgroundTransparency = 1; loginTitle.Text = "Origin's SOFB Hub"
loginTitle.TextColor3 = T.Text; loginTitle.TextSize = 18; loginTitle.Font = Enum.Font.GothamBold
loginTitle.Parent = loginCard

local loginSub = Instance.new("TextLabel")
loginSub.Size = UDim2.new(1, 0, 0, 16); loginSub.Position = UDim2.new(0, 0, 0, 114)
loginSub.BackgroundTransparency = 1; loginSub.Text = "Enter your license key to continue"
loginSub.TextColor3 = T.TextDim; loginSub.TextSize = 12; loginSub.Font = Enum.Font.Gotham
loginSub.Parent = loginCard

-- Key input
local keyInputBg = Instance.new("Frame")
keyInputBg.Size = UDim2.new(0, 280, 0, 42); keyInputBg.Position = UDim2.new(0.5, -140, 0, 155)
keyInputBg.BackgroundColor3 = T.Input; keyInputBg.BorderSizePixel = 0; keyInputBg.Parent = loginCard
corner(keyInputBg, 10); stroke(keyInputBg, T.Border, 1)

local keyIcon = Instance.new("TextLabel")
keyIcon.Size = UDim2.new(0, 36, 1, 0); keyIcon.BackgroundTransparency = 1
keyIcon.Text = "🔑"; keyIcon.TextSize = 16; keyIcon.Font = Enum.Font.GothamBold
keyIcon.Parent = keyInputBg

local keyInput = Instance.new("TextBox")
keyInput.Size = UDim2.new(1, -40, 1, 0); keyInput.Position = UDim2.new(0, 38, 0, 0)
keyInput.BackgroundTransparency = 1; keyInput.PlaceholderText = "SOFB-XXXXX-XXXXX-XXXXX-XXXXX"
keyInput.PlaceholderColor3 = T.TextMuted; keyInput.Text = ""; keyInput.TextColor3 = T.Text
keyInput.TextSize = 13; keyInput.Font = Enum.Font.GothamBold; keyInput.ClearTextOnFocus = false
keyInput.Parent = keyInputBg

keyInput.Focused:Connect(function() tw(keyInputBg, {BackgroundColor3 = T.InputFocus}, 0.15) end)
keyInput.FocusLost:Connect(function() tw(keyInputBg, {BackgroundColor3 = T.Input}, 0.15) end)

-- Login button
local loginBtn = Instance.new("TextButton")
loginBtn.Size = UDim2.new(0, 280, 0, 40); loginBtn.Position = UDim2.new(0.5, -140, 0, 210)
loginBtn.BackgroundColor3 = T.Accent; loginBtn.Text = "AUTHENTICATE"
loginBtn.TextColor3 = Color3.new(1, 1, 1); loginBtn.TextSize = 14
loginBtn.Font = Enum.Font.GothamBold; loginBtn.BorderSizePixel = 0
loginBtn.AutoButtonColor = false; loginBtn.Parent = loginCard
corner(loginBtn, 10)
applyDarkGradient(loginBtn)

loginBtn.MouseEnter:Connect(function() tw(loginBtn, {BackgroundTransparency = 0.1, TextSize = 15}, 0.2, Enum.EasingStyle.Quint) end)
loginBtn.MouseLeave:Connect(function() tw(loginBtn, {BackgroundTransparency = 0, TextSize = 14}, 0.2, Enum.EasingStyle.Quint) end)
loginBtn.MouseButton1Down:Connect(function() tw(loginBtn, {BackgroundTransparency = 0.3, TextSize = 13}, 0.1) end)
loginBtn.MouseButton1Up:Connect(function() tw(loginBtn, {BackgroundTransparency = 0.1, TextSize = 15}, 0.15) end)

-- Status label
local loginStatus = Instance.new("TextLabel")
loginStatus.Size = UDim2.new(1, 0, 0, 14); loginStatus.Position = UDim2.new(0, 0, 0, 260)
loginStatus.BackgroundTransparency = 1; loginStatus.Text = ""
loginStatus.TextColor3 = T.Danger; loginStatus.TextSize = 11
loginStatus.Font = Enum.Font.Gotham; loginStatus.Parent = loginCard

-- Version footer
local loginFooter = Instance.new("TextLabel")
loginFooter.Size = UDim2.new(1, 0, 0, 14); loginFooter.Position = UDim2.new(0, 0, 1, -24)
loginFooter.BackgroundTransparency = 1; loginFooter.Text = "v3.0 • Made by Origin"
loginFooter.TextColor3 = T.TextMuted; loginFooter.TextSize = 10
loginFooter.Font = Enum.Font.Gotham; loginFooter.Parent = loginCard

-- ══════════════════════════════════════════════════
--  LOGIN HANDLER
-- ══════════════════════════════════════════════════
local mainHub -- forward declare

local function doLogin()
    local key = keyInput.Text:gsub("%s+", "")
    if key == "" then
        loginStatus.Text = "Please enter a key"
        loginStatus.TextColor3 = T.Warning
        return
    end
    local valid, role = validateKey(key)
    if valid then
        loginStatus.Text = "✓ Authenticated as " .. role
        loginStatus.TextColor3 = T.On
        saveSession(key)
        sendWebhook("🔓 Login Success", "**User:** "..player.Name.."\n**ID:** "..player.UserId.."\n**Role:** "..role.."\n**Key:** ||"..key.."||", 3066993, {
            {name = "Game", value = tostring(game.PlaceId), inline = true},
            {name = "Server", value = tostring(game.JobId):sub(1,8), inline = true},
        })
        -- Zoom pop exit
        task.delay(0.2, function()
            tw(loginCardStroke, {Transparency = 1}, 0.25, Enum.EasingStyle.Quart)
            tw(loginCard, {BackgroundTransparency = 1, Size = UDim2.new(0, 380, 0, 360), Position = UDim2.new(0.5, -190, 0.5, -180)}, 0.4, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
            for _, v in ipairs(loginCard:GetDescendants()) do
                if v:IsA("TextLabel") or v:IsA("TextBox") or v:IsA("TextButton") then
                    pcall(function() tw(v, {TextTransparency = 1, BackgroundTransparency = 1}, 0.2) end)
                end
            end
            tw(loginFrame, {BackgroundTransparency = 1}, 0.5)
            task.delay(0.42, function()
                loginFrame.Visible = false
                mainHub.Visible = true
                mainHub.Size = UDim2.new(0, 500, 0, 600)
                mainHub.Position = UDim2.new(0.5, -250, 0.5, -300)
                mainHub.BackgroundTransparency = 1
                tw(mainHub, {Size = UDim2.new(0, 460, 0, 560), Position = UDim2.new(0.5, -230, 0.5, -280), BackgroundTransparency = 0.2}, 0.65, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
                task.delay(0.65, function()
                    notify("◈  Origin's SOFB Hub", "v3.0 loaded! Welcome, "..player.Name, "success", 5)
                    
                    task.delay(1.5, function()
                        notify("⚠️ Early Beta Notice", "The hub is a very new indie project! More features are coming, but expect bugs and unoptimized features as it's still in early beta.", "warning", 8)
                    end)
                    
                    if isOwner then
                        task.delay(2.5, function()
                            notify("👑  Owner Mode", "Admin panel unlocked — go generate some keys!", "info", 5)
                        end)
                    end
                end)
            end)
        end)
    else
        loginStatus.Text = "✕ Invalid key — try again"
        loginStatus.TextColor3 = T.Danger
        sendWebhook("🔒 Login Failed", "**User:** "..player.Name.."\n**ID:** "..player.UserId.."\n**Key Attempted:** ||"..key.."||", 15158332)
        -- Shake animation
        local baseX = 0.5; local baseOff = -180
        tw(loginCard, {Position = UDim2.new(baseX, baseOff + 12, 0.5, -170)}, 0.06, Enum.EasingStyle.Linear)
        task.delay(0.06, function() tw(loginCard, {Position = UDim2.new(baseX, baseOff - 12, 0.5, -170)}, 0.06, Enum.EasingStyle.Linear) end)
        task.delay(0.12, function() tw(loginCard, {Position = UDim2.new(baseX, baseOff + 8, 0.5, -170)}, 0.06, Enum.EasingStyle.Linear) end)
        task.delay(0.18, function() tw(loginCard, {Position = UDim2.new(baseX, baseOff - 6, 0.5, -170)}, 0.06, Enum.EasingStyle.Linear) end)
        task.delay(0.24, function() tw(loginCard, {Position = UDim2.new(baseX, baseOff, 0.5, -170)}, 0.08, Enum.EasingStyle.Linear) end)
        -- Flash border red briefly
        tw(loginCardStroke, {Color = T.Danger}, 0.1)
        task.delay(0.5, function() tw(loginCardStroke, {Color = T.Accent}, 0.4) end)
    end
end

loginBtn.MouseButton1Click:Connect(doLogin)
keyInput.FocusLost:Connect(function(enter)
    if enter then doLogin() end
end)

-- Auto-login from saved session
task.spawn(function()
    local saved = loadSession()
    if saved then
        local valid, role = validateKey(saved)
        if valid then
            keyInput.Text = saved
            task.delay(0.3, doLogin)
        end
    end
end)

-- ══════════════════════════════════════════════════
--  MAIN HUB FRAME
-- ══════════════════════════════════════════════════
mainHub = Instance.new("Frame")
mainHub.Name = "MainHub"; mainHub.Size = UDim2.new(0, 460, 0, 560)
mainHub.Position = UDim2.new(0.5, -230, 0.5, -280)
mainHub.BackgroundColor3 = T.Bg; mainHub.BorderSizePixel = 0
applyDarkGradient(mainHub)
mainHub.BackgroundTransparency = 0.2  -- slightly see-through for the glass effect
mainHub.ClipsDescendants = true; mainHub.Visible = false; mainHub.Parent = gui
corner(mainHub, 14); stroke(mainHub, T.Accent, 1.5)



-- Shadow
local sh = Instance.new("ImageLabel")
sh.Size = UDim2.new(1, 50, 1, 50); sh.Position = UDim2.new(0, -25, 0, -25)
sh.BackgroundTransparency = 1; sh.Image = "rbxassetid://6014261993"
sh.ImageColor3 = Color3.new(0,0,0); sh.ImageTransparency = 0.4
sh.ScaleType = Enum.ScaleType.Slice; sh.SliceCenter = Rect.new(49,49,450,450)
sh.ZIndex = -1; sh.Parent = mainHub

-- ┌──── TOP BAR ────┐
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"; topBar.Size = UDim2.new(1, 0, 0, 44)
topBar.BackgroundColor3 = T.TopBar; topBar.BorderSizePixel = 0; topBar.Parent = mainHub
corner(topBar, 14)

local barFix = Instance.new("Frame")
barFix.Size = UDim2.new(1, 0, 0, 14); barFix.Position = UDim2.new(0, 0, 1, -14)
barFix.BackgroundColor3 = T.TopBar; barFix.BorderSizePixel = 0; barFix.Parent = topBar

local accentLine = Instance.new("Frame")
accentLine.Size = UDim2.new(1, 0, 0, 2); accentLine.Position = UDim2.new(0, 0, 1, 0)
accentLine.BackgroundColor3 = T.Accent; accentLine.BorderSizePixel = 0; accentLine.Parent = topBar
local lineGrad = Instance.new("UIGradient")
lineGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, T.AccentDark), ColorSequenceKeypoint.new(0.3, T.AccentGlow),
    ColorSequenceKeypoint.new(0.7, T.AccentGlow), ColorSequenceKeypoint.new(1, T.AccentDark),
})
lineGrad.Parent = accentLine
task.spawn(function()
    while accentLine and accentLine.Parent do
        lineGrad.Offset = Vector2.new(-1, 0)
        tw(lineGrad, {Offset = Vector2.new(1, 0)}, 2, Enum.EasingStyle.Linear)
        task.wait(2)
    end
end)

-- Title
local titleIcon = Instance.new("TextLabel")
titleIcon.Size = UDim2.new(0, 30, 1, 0); titleIcon.Position = UDim2.new(0, 10, 0, 0)
titleIcon.BackgroundTransparency = 1; titleIcon.Text = "◈"; titleIcon.TextColor3 = T.Accent
titleIcon.TextSize = 20; titleIcon.Font = Enum.Font.GothamBold; titleIcon.Parent = topBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -150, 1, 0); titleLabel.Position = UDim2.new(0, 38, 0, 0)
titleLabel.BackgroundTransparency = 1; titleLabel.Text = "Origin's SOFB Hub"
titleLabel.TextColor3 = T.Text; titleLabel.TextSize = 15; titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left; titleLabel.Parent = topBar

local verBadge = Instance.new("TextLabel")
verBadge.Size = UDim2.new(0, 38, 0, 17); verBadge.Position = UDim2.new(0, 202, 0.5, -8)
verBadge.BackgroundColor3 = T.Accent; verBadge.BackgroundTransparency = 0.82
verBadge.Text = "v3.0"; verBadge.TextColor3 = T.AccentGlow; verBadge.TextSize = 10
verBadge.Font = Enum.Font.GothamBold; verBadge.Parent = topBar; corner(verBadge, 4)

-- Top bar buttons
local function barBtn(txt, offX)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 32, 0, 32); b.Position = UDim2.new(1, offX, 0.5, -16)
    b.BackgroundColor3 = T.Input; b.BackgroundTransparency = 1; b.Text = txt
    b.TextColor3 = T.TextDim; b.TextSize = 16; b.Font = Enum.Font.GothamBold
    b.AutoButtonColor = false; b.Parent = topBar; corner(b, 6)
    b.MouseEnter:Connect(function() tw(b, {TextColor3 = T.Text, BackgroundTransparency = 0.7}, 0.12) end)
    b.MouseLeave:Connect(function() tw(b, {TextColor3 = T.TextDim, BackgroundTransparency = 1}, 0.12) end)
    return b
end
local closeBtn = barBtn("✕", -38)
local minBtn = barBtn("─", -72)

-- (FPS label removed per user request)

-- ┌──── TAB BAR ────┐
local TAB_DEFS = {
    {id = "combat",   icon = "🛡️", label = "Main"},
    {id = "visual",   icon = "👁", label = "Visuals"},
    {id = "teleport", icon = "⚡", label = "Teleport"},
    {id = "binds",    icon = "⌨",  label = "Binds"},
    {id = "misc",     icon = "⚙",  label = "Misc"},
}

local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"; tabBar.Size = UDim2.new(1, -16, 0, 36)
tabBar.Position = UDim2.new(0, 8, 0, 50); tabBar.BackgroundColor3 = T.Surface
tabBar.BorderSizePixel = 0; tabBar.Parent = mainHub; corner(tabBar, 8)

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Padding = UDim.new(0, 2); tabLayout.Parent = tabBar
pad(tabBar, 3, 3, 4, 4)

local tabButtons = {}
local tabPages = {}
local activeTab = nil

local contentFrame = Instance.new("Frame")
contentFrame.Name = "ContentFrame"; contentFrame.Size = UDim2.new(1, -16, 1, -96)
contentFrame.Position = UDim2.new(0, 8, 0, 90); contentFrame.BackgroundTransparency = 1
contentFrame.BorderSizePixel = 0; contentFrame.ClipsDescendants = true; contentFrame.Parent = mainHub

local function switchTab(id)
    if activeTab == id then return end
    activeTab = id
    for tid, page in pairs(tabPages) do
        page.Visible = (tid == id)
    end
    for tid, btn in pairs(tabButtons) do
        if tid == id then
            tw(btn, {BackgroundColor3 = T.Accent, BackgroundTransparency = 0.15}, 0.2)
            tw(btn:FindFirstChild("Label"), {TextColor3 = T.Text}, 0.2)
        else
            tw(btn, {BackgroundColor3 = T.TabInactive, BackgroundTransparency = 0.6}, 0.2)
            tw(btn:FindFirstChild("Label"), {TextColor3 = T.TextMuted}, 0.2)
        end
    end
end

for i, def in ipairs(TAB_DEFS) do
    -- Hide admin tab for non-owners
    local btn = Instance.new("TextButton")
    btn.Name = def.id; btn.Size = UDim2.new(1/#TAB_DEFS, -2, 1, -6)
    btn.BackgroundColor3 = T.TabInactive; btn.BackgroundTransparency = 0.6
    btn.Text = ""; btn.BorderSizePixel = 0; btn.AutoButtonColor = false
    btn.LayoutOrder = i; btn.Parent = tabBar; corner(btn, 6)

    local lbl = Instance.new("TextLabel")
    lbl.Name = "Label"; lbl.Size = UDim2.new(1, 0, 1, 0); lbl.BackgroundTransparency = 1
    lbl.Text = def.icon.." "..def.label; lbl.TextColor3 = T.TextMuted
    lbl.TextSize = 10; lbl.Font = Enum.Font.GothamBold; lbl.Parent = btn

    btn.MouseButton1Click:Connect(function() switchTab(def.id) end)
    btn.MouseEnter:Connect(function()
        if activeTab ~= def.id then tw(btn, {BackgroundTransparency = 0.4}, 0.12) end
    end)
    btn.MouseLeave:Connect(function()
        if activeTab ~= def.id then tw(btn, {BackgroundTransparency = 0.6}, 0.12) end
    end)
    tabButtons[def.id] = btn

    local page = Instance.new("ScrollingFrame")
    page.Name = def.id.."Page"; page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1; page.BorderSizePixel = 0; page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = T.Accent; page.CanvasSize = UDim2.new(0,0,0,0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y; page.Visible = false; page.Parent = contentFrame

    local pl = Instance.new("UIListLayout")
    pl.SortOrder = Enum.SortOrder.LayoutOrder; pl.Padding = UDim.new(0, 8); pl.Parent = page

    tabPages[def.id] = page
end

-- ════════════════════════════════════════════
--  UI FACTORIES (Enhanced)
-- ════════════════════════════════════════════
local function makeSection(parent, heading, order, icon)
    local s = Instance.new("Frame")
    s.Size = UDim2.new(1, 0, 0, 0); s.AutomaticSize = Enum.AutomaticSize.Y
    s.BackgroundColor3 = T.Section; s.BorderSizePixel = 0; s.LayoutOrder = order
    s.Parent = parent; corner(s, 10); stroke(s, T.Border, 1); pad(s, 10, 10, 12, 12)

    local lay = Instance.new("UIListLayout")
    lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Padding = UDim.new(0, 5); lay.Parent = s

    local h = Instance.new("TextLabel")
    h.Size = UDim2.new(1, 0, 0, 18); h.BackgroundTransparency = 1
    h.Text = (icon or "◆").."  "..heading; h.TextColor3 = T.Accent; h.TextSize = 13
    h.Font = Enum.Font.GothamBold; h.TextXAlignment = Enum.TextXAlignment.Left
    h.LayoutOrder = 0; h.Parent = s

    return s
end

local function makeToggle(parent, label, default, order, cb)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 28); row.BackgroundTransparency = 1
    row.LayoutOrder = order; row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -56, 1, 0); lbl.BackgroundTransparency = 1; lbl.Text = label
    lbl.TextColor3 = T.Text; lbl.TextSize = 13; lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row

    local bg = Instance.new("TextButton")
    bg.Size = UDim2.new(0, 44, 0, 22); bg.Position = UDim2.new(1, -44, 0.5, -11)
    bg.BackgroundColor3 = default and T.On or T.Off; bg.Text = ""
    bg.BorderSizePixel = 0; bg.AutoButtonColor = false; bg.Parent = row; corner(bg, 11)
    applyDarkGradient(bg)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = default and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    knob.BackgroundColor3 = T.Knob; knob.BorderSizePixel = 0; knob.Parent = bg; corner(knob, 9)

    row.MouseEnter:Connect(function() tw(bg, {Size = UDim2.new(0, 48, 0, 24), Position = UDim2.new(1, -48, 0.5, -12)}, 0.2, Enum.EasingStyle.Quint) end)
    row.MouseLeave:Connect(function() tw(bg, {Size = UDim2.new(0, 44, 0, 22), Position = UDim2.new(1, -44, 0.5, -11)}, 0.2, Enum.EasingStyle.Quint) end)

    local state = default
    local function set(v, silent)
        state = v
        tw(bg, {BackgroundColor3 = v and T.On or T.Off}, 0.2)
        tw(knob, {Position = v and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9)}, 0.2, Enum.EasingStyle.Back)
        if not silent and cb then cb(v) end
    end
    bg.MouseButton1Click:Connect(function() state = not state; set(state) end)
    return row, function() return state end, set
end

local function makeInputRow(parent, label, default, order, validator)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 28); row.BackgroundTransparency = 1
    row.LayoutOrder = order; row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -78, 1, 0); lbl.BackgroundTransparency = 1; lbl.Text = label
    lbl.TextColor3 = T.Text; lbl.TextSize = 13; lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0, 68, 0, 24); box.Position = UDim2.new(1, -68, 0.5, -12)
    box.BackgroundColor3 = T.Input; box.Text = tostring(default); box.TextColor3 = T.Text
    box.TextSize = 13; box.Font = Enum.Font.GothamBold; box.BorderSizePixel = 0
    box.ClearTextOnFocus = false; box.Parent = row; corner(box, 6); stroke(box, T.Border, 1)
    box.Focused:Connect(function() tw(box, {BackgroundColor3 = T.InputFocus}, 0.15) end)
    box.FocusLost:Connect(function() tw(box, {BackgroundColor3 = T.Input}, 0.15); if validator then validator(box) end; _G.saveSettings() end)
    return row, box
end

local function makeSlider(parent, label, min, max, default, order, cb)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 36); row.BackgroundTransparency = 1
    row.LayoutOrder = order; row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -50, 0, 16); lbl.BackgroundTransparency = 1; lbl.Text = label
    lbl.TextColor3 = T.Text; lbl.TextSize = 13; lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row

    local valLbl = Instance.new("TextLabel")
    valLbl.Size = UDim2.new(0, 50, 0, 16); valLbl.Position = UDim2.new(1, -50, 0, 0)
    valLbl.BackgroundTransparency = 1; valLbl.Text = tostring(default)
    valLbl.TextColor3 = T.Accent; valLbl.TextSize = 12; valLbl.Font = Enum.Font.GothamBold
    valLbl.TextXAlignment = Enum.TextXAlignment.Right; valLbl.Parent = row

    local trackBg = Instance.new("Frame")
    trackBg.Size = UDim2.new(1, 0, 0, 6); trackBg.Position = UDim2.new(0, 0, 1, -6)
    trackBg.BackgroundColor3 = T.Input; trackBg.BorderSizePixel = 0; trackBg.Parent = row
    corner(trackBg, 3)

    local fill = Instance.new("Frame")
    local fillPct = math.clamp((default - min) / (max - min), 0, 1)
    fill.Size = UDim2.new(fillPct, 0, 1, 0); fill.BackgroundColor3 = T.Accent
    fill.BorderSizePixel = 0; fill.Parent = trackBg; corner(fill, 3)
    applyDarkGradient(fill)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 12, 0, 12); knob.Position = UDim2.new(fillPct, -6, 0.5, -6)
    knob.BackgroundColor3 = Color3.new(1,1,1); knob.BorderSizePixel = 0; knob.Parent = trackBg
    corner(knob, 6); local kStroke = stroke(knob, T.Accent, 1)

    local dragging = false
    local function update(input, smooth)
        local pos = math.clamp((input.Position.X - trackBg.AbsolutePosition.X) / trackBg.AbsoluteSize.X, 0, 1)
        local value = math.floor(min + (max - min) * pos)
        valLbl.Text = tostring(value)
        
        if smooth then
            tw(fill, {Size = UDim2.new(pos, 0, 1, 0)}, 0.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
            tw(knob, {Position = UDim2.new(pos, -6, 0.5, -6)}, 0.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        else
            fill.Size = UDim2.new(pos, 0, 1, 0)
            knob.Position = UDim2.new(pos, -6, 0.5, -6)
        end
        if cb then cb(value) end
    end

    local dragBtn = Instance.new("TextButton")
    dragBtn.Size = UDim2.new(1, 0, 0, 20); dragBtn.Position = UDim2.new(0, 0, 1, -13)
    dragBtn.BackgroundTransparency = 1; dragBtn.Text = ""; dragBtn.Parent = row

    dragBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            tw(knob, {Size = UDim2.new(0, 18, 0, 18), Position = UDim2.new(fill.Size.X.Scale, -9, 0.5, -9)}, 0.2, Enum.EasingStyle.Back)
            update(input, true)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
            dragging = false
            tw(knob, {Size = UDim2.new(0, 12, 0, 12), Position = UDim2.new(fill.Size.X.Scale, -6, 0.5, -6)}, 0.2, Enum.EasingStyle.Back)
            _G.saveSettings()
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            update(input, false)
        end
    end)

    row.MouseEnter:Connect(function() tw(fill, {BackgroundColor3 = T.AccentGlow}, 0.2) end)
    row.MouseLeave:Connect(function() tw(fill, {BackgroundColor3 = T.Accent}, 0.2) end)

    return row
end

local function makeBindRow(parent, label, bindKey, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 28); row.BackgroundTransparency = 1
    row.LayoutOrder = order; row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -95, 1, 0); lbl.BackgroundTransparency = 1; lbl.Text = label
    lbl.TextColor3 = T.Text; lbl.TextSize = 13; lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 90, 0, 24); btn.Position = UDim2.new(1, -90, 0.5, -12)
    btn.BackgroundColor3 = T.Input; btn.Text = Settings.Binds[bindKey]
    btn.TextColor3 = T.Accent; btn.TextSize = 11; btn.Font = Enum.Font.GothamBold
    btn.BorderSizePixel = 0; btn.AutoButtonColor = false; btn.Parent = row
    corner(btn, 4); stroke(btn, T.BorderLight, 1)

    local listening = false
    btn.MouseButton1Click:Connect(function()
        if listening then return end
        listening = true; btn.Text = "..."
        tw(btn, {BackgroundColor3 = T.Accent, TextColor3 = Color3.new(1,1,1)}, 0.15)
        
        local conn
        conn = UIS.InputBegan:Connect(function(input, gp)
            if input.UserInputType == Enum.UserInputType.Keyboard then
                conn:Disconnect()
                local newKey = input.KeyCode.Name
                Settings.Binds[bindKey] = newKey
                btn.Text = newKey
                tw(btn, {BackgroundColor3 = T.Input, TextColor3 = T.Accent}, 0.15)
                listening = false
                _G.saveSettings()
            end
        end)
    end)
    return row, btn
end

local function makeButton(parent, label, color, order, cb)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 32); btn.BackgroundColor3 = color or T.Accent
    btn.BackgroundTransparency = 0.82; btn.Text = label; btn.TextColor3 = color or T.Accent
    btn.TextSize = 12; btn.Font = Enum.Font.GothamBold; btn.BorderSizePixel = 0
    btn.AutoButtonColor = false; btn.LayoutOrder = order; btn.Parent = parent
    corner(btn, 8); stroke(btn, color or T.Accent, 1)
    applyDarkGradient(btn)
    btn.MouseEnter:Connect(function() tw(btn, {BackgroundTransparency = 0.4, TextSize = 13}, 0.2, Enum.EasingStyle.Quint) end)
    btn.MouseLeave:Connect(function() tw(btn, {BackgroundTransparency = 0.82, TextSize = 12}, 0.2, Enum.EasingStyle.Quint) end)
    btn.MouseButton1Down:Connect(function() tw(btn, {BackgroundTransparency = 0.2, TextSize = 11}, 0.1, Enum.EasingStyle.Quint) end)
    btn.MouseButton1Up:Connect(function() tw(btn, {BackgroundTransparency = 0.4, TextSize = 13}, 0.1, Enum.EasingStyle.Quint) end)
    btn.MouseButton1Click:Connect(function() if cb then cb() end end)
    return btn
end

local function makeSeparator(parent, order)
    local sep = Instance.new("Frame")
    sep.Size = UDim2.new(1, 0, 0, 1); sep.BackgroundColor3 = T.Border
    sep.BackgroundTransparency = 0.5; sep.BorderSizePixel = 0; sep.LayoutOrder = order
    sep.Parent = parent; return sep
end

local function makeLabel(parent, text, color, order)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 16); lbl.BackgroundTransparency = 1; lbl.Text = text
    lbl.TextColor3 = color or T.TextDim; lbl.TextSize = 11; lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.LayoutOrder = order; lbl.Parent = parent
    return lbl
end

-- ════════════════════════════════════════════
--  RARITY CHECK FACTORY
-- ════════════════════════════════════════════
local function makeRarityCheck(parent, rarityName, order)
    local color = T.Rarity[rarityName]
    local default = Settings.Rarities[rarityName]
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 26); row.BackgroundTransparency = 1
    row.LayoutOrder = order; row.Parent = parent

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 20, 0, 20); btn.Position = UDim2.new(0, 0, 0.5, -10)
    btn.BackgroundColor3 = default and color or T.Off; btn.Text = default and "✓" or ""
    btn.TextColor3 = Color3.new(1,1,1); btn.TextSize = 12; btn.Font = Enum.Font.GothamBold
    btn.BorderSizePixel = 0; btn.AutoButtonColor = false; btn.Parent = row; corner(btn, 5)

    local stripe = Instance.new("Frame")
    stripe.Size = UDim2.new(0, 3, 0, 16); stripe.Position = UDim2.new(0, 28, 0.5, -8)
    stripe.BackgroundColor3 = color; stripe.BorderSizePixel = 0; stripe.Parent = row; corner(stripe, 2)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0, 80, 1, 0); lbl.Position = UDim2.new(0, 36, 0, 0)
    lbl.BackgroundTransparency = 1; lbl.Text = rarityName; lbl.TextColor3 = color
    lbl.TextSize = 12; lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row

    local tier = Instance.new("TextLabel")
    tier.Size = UDim2.new(0, 80, 1, 0); tier.Position = UDim2.new(0, 120, 0, 0)
    tier.BackgroundTransparency = 1; tier.Text = T.RarityTier[rarityName] or ""
    tier.TextColor3 = T.TextMuted; tier.TextSize = 10; tier.Font = Enum.Font.Gotham
    tier.TextXAlignment = Enum.TextXAlignment.Left; tier.Parent = row

    local countLbl = Instance.new("TextLabel")
    countLbl.Name = "Count"; countLbl.Size = UDim2.new(0, 30, 0, 16)
    countLbl.Position = UDim2.new(1, -34, 0.5, -8)
    countLbl.BackgroundColor3 = color; countLbl.BackgroundTransparency = 0.88
    countLbl.Text = "0"; countLbl.TextColor3 = color; countLbl.TextSize = 10
    countLbl.Font = Enum.Font.GothamBold; countLbl.Parent = row; corner(countLbl, 4)

    local state = default
    btn.MouseButton1Click:Connect(function()
        state = not state; Settings.Rarities[rarityName] = state
        tw(btn, {BackgroundColor3 = state and color or T.Off}, 0.15)
        btn.Text = state and "✓" or ""
        addLog(rarityName .. (state and "  ✔  enabled" or "  ✘  disabled"))
    end)
    return row, countLbl
end

-- ════════════════════════════════════════════
--  TAB 1 — COMBAT (Movement + Player Info)
-- ════════════════════════════════════════════
local pg = tabPages["combat"]

local secInfo = makeSection(pg, "PLAYER INFO", 1, "👤")
local infoName = makeLabel(secInfo, "👤  "..player.Name.."  (ID: "..player.UserId..")", T.Text, 1)
local infoSession = makeLabel(secInfo, "⏱  Session: 0s", T.TextDim, 2)
local infoStats = makeLabel(secInfo, "📊  Rares: 0  │  TPs: 0", T.TextDim, 3)

local secMove = makeSection(pg, "MOVEMENT", 2, "🏃")
makeToggle(secMove, "Speed Lock", Settings.SpeedLock, 1, function(v)
    Settings.SpeedLock = v
    if v and player.Character then
        local h = player.Character:FindFirstChild("Humanoid")
        if h then h.WalkSpeed = Settings.WalkSpeed end
    end
    addLog(v and "Speed Lock ON" or "Speed Lock OFF")
    notifyInfo("Speed Lock", v and "Locked at "..Settings.WalkSpeed or "Disabled")
end)
makeSlider(secMove, "Walk Speed", 0, 500, Settings.WalkSpeed, 2, function(val)
    Settings.WalkSpeed = val
    if Settings.SpeedLock and player.Character then
        local h = player.Character:FindFirstChild("Humanoid")
        if h then h.WalkSpeed = val end
    end
end)
makeSeparator(secMove, 3)
makeToggle(secMove, "Jump Lock", Settings.JumpLock, 4, function(v)
    Settings.JumpLock = v
    if v and player.Character then
        local h = player.Character:FindFirstChild("Humanoid")
        if h then h.JumpPower = Settings.JumpPower end
    end
    addLog(v and "Jump Lock ON" or "Jump Lock OFF")
end)
makeSlider(secMove, "Jump Power", 0, 500, Settings.JumpPower, 5, function(val)
    Settings.JumpPower = val
    if Settings.JumpLock and player.Character then
        local h = player.Character:FindFirstChild("Humanoid")
        if h then h.JumpPower = val end
    end
end)
makeSeparator(secMove, 6)
makeToggle(secMove, "Noclip", Settings.Noclip, 7, function(v)
    Settings.Noclip = v
    addLog(v and "Noclip ON" or "Noclip OFF")
    notifyInfo("Noclip", v and "Walk through everything" or "Disabled")
end)

-- ════════════════════════════════════════════
--  TAB 2 — VISUALS
-- ════════════════════════════════════════════
pg = tabPages["visual"]

local secVisual = makeSection(pg, "LIGHTING", 1, "💡")
local origLighting = {}
makeToggle(secVisual, "Fullbright", Settings.Fullbright, 1, function(v)
    Settings.Fullbright = v
    if v then
        origLighting.Ambient = Lighting.Ambient
        origLighting.ColorShift_Bottom = Lighting.ColorShift_Bottom
        origLighting.ColorShift_Top = Lighting.ColorShift_Top
        origLighting.GlobalShadows = Lighting.GlobalShadows
        origLighting.Brightness = Lighting.Brightness
        origLighting.ClockTime = Lighting.ClockTime
        origLighting.FogEnd = Lighting.FogEnd
        
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.ColorShift_Bottom = Color3.new(1, 1, 1)
        Lighting.ColorShift_Top = Color3.new(1, 1, 1)
        Lighting.GlobalShadows = false
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 1e9
    else
        Lighting.Ambient = origLighting.Ambient or Color3.fromRGB(127, 127, 127)
        Lighting.ColorShift_Bottom = origLighting.ColorShift_Bottom or Color3.new(0,0,0)
        Lighting.ColorShift_Top = origLighting.ColorShift_Top or Color3.new(0,0,0)
        if origLighting.GlobalShadows ~= nil then Lighting.GlobalShadows = origLighting.GlobalShadows end
        Lighting.Brightness = origLighting.Brightness or 1
        Lighting.ClockTime = origLighting.ClockTime or 14
        Lighting.FogEnd = origLighting.FogEnd or 1e5
    end
    addLog(v and "Fullbright ON" or "Fullbright OFF")
end)

local secESP = makeSection(pg, "ESP", 2, "👁")
makeToggle(secESP, "Brainrot ESP", Settings.ESP, 1, function(v)
    Settings.ESP = v
    if v then updateESP() end
    addLog(v and "ESP ON" or "ESP OFF")
    notifyInfo("ESP", v and "Highlighting target brainrots" or "Disabled")
end)
makeSeparator(secESP, 2)
makeLabel(secESP, "ESP FILTERS (uncheck to hide):", T.TextDim, 3)

_G.rarityCountLabels = {}
for i, rName in ipairs(RarityOrder) do
    if i == 5 then
        makeSeparator(secESP, 3+i)
        makeLabel(secESP, "▲ EXCLUDED  ╱  ▼ TARGETS", T.TextMuted, 3+i+1)
        makeSeparator(secESP, 3+i+2)
    end
    local orderOffset = i <= 4 and (3+i) or (6+i)
    local _, countLbl = makeRarityCheck(secESP, rName, orderOffset)
    _G.rarityCountLabels[rName] = countLbl
end

-- ════════════════════════════════════════════
--  TAB 3 — TELEPORT
-- ════════════════════════════════════════════
pg = tabPages["teleport"]

local secTP = makeSection(pg, "QUICK TELEPORTS", 1, "⚡")

local function hotkeyRow(parent, key, desc, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 26); row.BackgroundTransparency = 1
    row.LayoutOrder = order; row.Parent = parent
    local badge = Instance.new("TextLabel")
    badge.Size = UDim2.new(0, 34, 0, 22); badge.BackgroundColor3 = T.Input
    badge.Text = key; badge.TextColor3 = T.Accent; badge.TextSize = 11
    badge.Font = Enum.Font.GothamBold; badge.BorderSizePixel = 0; badge.Parent = row
    corner(badge, 4); stroke(badge, T.Border, 1)
    local d = Instance.new("TextLabel")
    d.Size = UDim2.new(1, -42, 1, 0); d.Position = UDim2.new(0, 40, 0, 0)
    d.BackgroundTransparency = 1; d.Text = "→  "..desc; d.TextColor3 = T.TextDim
    d.TextSize = 12; d.Font = Enum.Font.Gotham; d.TextXAlignment = Enum.TextXAlignment.Left
    d.Parent = row
end

hotkeyRow(secTP, "G", "Teleport to Zone 12", 1)
hotkeyRow(secTP, "B", "Teleport to Plot Base", 2)
hotkeyRow(secTP, "R⇧", "Toggle Hub (RightShift)", 3)
hotkeyRow(secTP, "N", "Test Notification", 4)
makeSeparator(secTP, 5)

-- Forward declare teleportTo
local teleportTo

makeButton(secTP, "⚡  Teleport to Zone 12", T.Accent, 6, function()
    local z = workspace:FindFirstChild("Zones")
    if z then
        local z12 = z:FindFirstChild("12")
        if z12 and teleportTo(z12) then
            addLog("TP → Zone 12"); notifySuccess("Teleported", "Arrived at Zone 12")
        end
    end
end)
makeButton(secTP, "🏠  Teleport to Plot Base", T.AccentGlow, 7, function()
    pcall(function()
        local base = workspace.Plots.Plot2.Base; local ch = base:GetChildren()
        if #ch >= 4 and teleportTo(ch[4]) then
            addLog("TP → Plot Base"); notifySuccess("Teleported", "Arrived at Plot Base")
        end
    end)
end)

-- ════════════════════════════════════════════
--  TAB 4 — BINDS
-- ════════════════════════════════════════════
pg = tabPages["binds"]

local secBinds = makeSection(pg, "CUSTOM KEYBINDS", 1, "⌨")
makeLabel(secBinds, "Click a button then press any key to rebind.", T.TextDim, 1)
makeSeparator(secBinds, 2)
makeBindRow(secBinds, "Teleport to Zone 12", "Zone12", 3)
makeBindRow(secBinds, "Teleport to Plot Base", "PlotBase", 4)
makeBindRow(secBinds, "Toggle UI Visibility", "ToggleHub", 5)
makeBindRow(secBinds, "Toggle Admin Panel", "AdminPanel", 6)

-- The Auto-Farm UI tab was removed by user request to migrate Target Filters directly into the Visuals ESP.

-- ════════════════════════════════════════════
--  TAB 5 — MISC (Utilities + Log + Credits)
-- ════════════════════════════════════════════
pg = tabPages["misc"]

local secUtil = makeSection(pg, "UTILITIES", 1, "⚙")
makeToggle(secUtil, "Anti-AFK", Settings.AntiAFK, 1, function(v)
    Settings.AntiAFK = v; addLog(v and "Anti-AFK ON" or "Anti-AFK OFF")
    notifyInfo("Anti-AFK", v and "You won't be kicked" or "Disabled")
end)
makeToggle(secUtil, "Notifications", Settings.Sounds, 2, function(v)
    Settings.Sounds = v; addLog(v and "Notifs ON" or "Notifs OFF")
end)
makeSeparator(secUtil, 3)
makeButton(secUtil, "🗑  Clear Log", T.TextDim, 4, function()
    logLines = {}; if logRefresh then logRefresh() end; addLog("Log cleared")
end)
makeButton(secUtil, "🔄  Reset Stats", T.Warning, 5, function()
    Stats.TotalTPs = 0; for _, r in ipairs(RarityOrder) do Stats.RarityFinds[r] = 0 end
    Stats.SessionStart = tick()
    for r, l in pairs(rarityCountLabels) do l.Text = "0" end
    addLog("Stats reset"); notifyInfo("Stats Reset", "All counters zeroed")
end)
makeButton(secUtil, "📋  Copy Stats", T.AccentGlow, 6, function()
    local lines = {"═══ Origin's SOFB Hub Stats ═══", "Session: "..formatTime(tick()-Stats.SessionStart), "TPs: "..Stats.TotalTPs}
    local rt = 0
    for _, r in ipairs(RarityOrder) do
        if Stats.RarityFinds[r] > 0 then table.insert(lines, "  "..r..": "..Stats.RarityFinds[r]); rt = rt + Stats.RarityFinds[r] end
    end
    table.insert(lines, "Total Rares: "..rt)
    if setclipboard then setclipboard(table.concat(lines, "\n")); notifySuccess("Copied!", "Stats on clipboard")
    else notifyWarn("Unavailable", "Clipboard not supported") end
end)
makeButton(secUtil, "🔔  Test Notification", T.Accent, 7, function()
    notifyRarity("CELESTIAL", "Test Brainrot")
end)

-- Status Log
local secLog = makeSection(pg, "STATUS LOG", 2, "📜")
local logScroll = Instance.new("ScrollingFrame")
logScroll.Size = UDim2.new(1, 0, 0, 100); logScroll.BackgroundColor3 = T.LogBg
logScroll.BorderSizePixel = 0; logScroll.ScrollBarThickness = 2
logScroll.ScrollBarImageColor3 = T.Accent; logScroll.CanvasSize = UDim2.new(0,0,0,0)
logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; logScroll.LayoutOrder = 1
logScroll.Parent = secLog; corner(logScroll, 6); pad(logScroll, 4, 4, 6, 6)

local logLayout = Instance.new("UIListLayout")
logLayout.SortOrder = Enum.SortOrder.LayoutOrder; logLayout.Padding = UDim.new(0, 1)
logLayout.Parent = logScroll

logRefresh = function()
    for _, c in ipairs(logScroll:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end
    local from = math.max(1, #logLines - 30)
    for i = from, #logLines do
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 0, 14); l.BackgroundTransparency = 1; l.Text = logLines[i]
        l.TextColor3 = T.TextMuted; l.TextSize = 10; l.Font = Enum.Font.Code
        l.TextXAlignment = Enum.TextXAlignment.Left; l.TextWrapped = true
        l.AutomaticSize = Enum.AutomaticSize.Y; l.LayoutOrder = i; l.Parent = logScroll
    end
    task.defer(function() logScroll.CanvasPosition = Vector2.new(0, logScroll.AbsoluteCanvasSize.Y) end)
end

-- Credits
local secCredit = makeSection(pg, "ABOUT", 3, "ℹ")
makeLabel(secCredit, "Made by Origin · SOFB Hub v3.0", T.TextDim, 1)
makeLabel(secCredit, "Press RightShift to toggle UI", T.TextMuted, 2)

-- ════════════════════════════════════════════
--  FLOATING ADMIN PANEL (K to toggle, owner only)
-- ════════════════════════════════════════════
local adminPanel = Instance.new("Frame")
adminPanel.Name = "AdminPanel"
adminPanel.Size = UDim2.new(0, 380, 0, 520)
adminPanel.Position = UDim2.new(0.5, 240, 0.5, -260)  -- right of main hub
adminPanel.BackgroundColor3 = T.Bg
applyDarkGradient(adminPanel)
adminPanel.BorderSizePixel = 0
adminPanel.ClipsDescendants = true
adminPanel.Visible = false
adminPanel.Parent = gui
corner(adminPanel, 14)
stroke(adminPanel, Color3.fromRGB(180, 130, 255), 1.5)

-- Shadow
local apSh = Instance.new("ImageLabel")
apSh.Size = UDim2.new(1, 40, 1, 40); apSh.Position = UDim2.new(0, -20, 0, -20)
apSh.BackgroundTransparency = 1; apSh.Image = "rbxassetid://6014261993"
apSh.ImageColor3 = Color3.new(0,0,0); apSh.ImageTransparency = 0.45
apSh.ScaleType = Enum.ScaleType.Slice; apSh.SliceCenter = Rect.new(49,49,450,450)
apSh.ZIndex = -1; apSh.Parent = adminPanel

-- Top bar
local apBar = Instance.new("Frame")
apBar.Size = UDim2.new(1, 0, 0, 44); apBar.BackgroundColor3 = T.TopBar
apBar.BorderSizePixel = 0; apBar.Parent = adminPanel; corner(apBar, 14)

local apBarFix = Instance.new("Frame")
apBarFix.Size = UDim2.new(1, 0, 0, 14); apBarFix.Position = UDim2.new(0, 0, 1, -14)
apBarFix.BackgroundColor3 = T.TopBar; apBarFix.BorderSizePixel = 0; apBarFix.Parent = apBar

local apAccent = Instance.new("Frame")
apAccent.Size = UDim2.new(1, 0, 0, 2); apAccent.Position = UDim2.new(0, 0, 1, 0)
apAccent.BackgroundColor3 = Color3.fromRGB(180, 130, 255); apAccent.BorderSizePixel = 0
apAccent.Parent = apBar
local apAccentGrad = Instance.new("UIGradient")
apAccentGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, T.AccentDark),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 160, 255)),
    ColorSequenceKeypoint.new(1, T.AccentDark),
}); apAccentGrad.Parent = apAccent
task.spawn(function()
    while apAccent and apAccent.Parent do
        apAccentGrad.Offset = Vector2.new(-1, 0)
        tw(apAccentGrad, {Offset = Vector2.new(1, 0)}, 2, Enum.EasingStyle.Linear)
        task.wait(2)
    end
end)

local apIcon = Instance.new("TextLabel")
apIcon.Size = UDim2.new(0, 28, 1, 0); apIcon.Position = UDim2.new(0, 10, 0, 0)
apIcon.BackgroundTransparency = 1; apIcon.Text = "👑"
apIcon.TextSize = 18; apIcon.Font = Enum.Font.GothamBold; apIcon.Parent = apBar

local apTitle = Instance.new("TextLabel")
apTitle.Size = UDim2.new(1, -90, 1, 0); apTitle.Position = UDim2.new(0, 40, 0, 0)
apTitle.BackgroundTransparency = 1; apTitle.Text = "Owner Admin Panel"
apTitle.TextColor3 = T.Text; apTitle.TextSize = 14; apTitle.Font = Enum.Font.GothamBold
apTitle.TextXAlignment = Enum.TextXAlignment.Left; apTitle.Parent = apBar

local apHint = Instance.new("TextLabel")
apHint.Size = UDim2.new(0, 40, 0, 16); apHint.Position = UDim2.new(1, -82, 0.5, -8)
apHint.BackgroundColor3 = T.Accent; apHint.BackgroundTransparency = 0.82
apHint.Text = "[K]"; apHint.TextColor3 = T.AccentGlow; apHint.TextSize = 10
apHint.Font = Enum.Font.GothamBold; apHint.Parent = apBar; corner(apHint, 4)

local apClose = Instance.new("TextButton")
apClose.Size = UDim2.new(0, 32, 0, 32); apClose.Position = UDim2.new(1, -38, 0.5, -16)
apClose.BackgroundTransparency = 1; apClose.Text = "✕"; apClose.TextColor3 = T.TextDim
apClose.TextSize = 16; apClose.Font = Enum.Font.GothamBold; apClose.AutoButtonColor = false
apClose.Parent = apBar; corner(apClose, 6)
apClose.MouseEnter:Connect(function() tw(apClose, {TextColor3 = T.Danger, BackgroundTransparency = 0.7, BackgroundColor3 = T.Danger}, 0.12) end)
apClose.MouseLeave:Connect(function() tw(apClose, {TextColor3 = T.TextDim, BackgroundTransparency = 1}, 0.12) end)

-- Drag
do
    local drag, ds, sp
    apBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            drag = true; ds = i.Position; sp = adminPanel.Position
            i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then drag = false end end)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
            local d = i.Position - ds
            adminPanel.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
        end
    end)
end

-- Content scroll
local apScroll = Instance.new("ScrollingFrame")
apScroll.Size = UDim2.new(1, -16, 1, -52); apScroll.Position = UDim2.new(0, 8, 0, 48)
apScroll.BackgroundTransparency = 1; apScroll.BorderSizePixel = 0; apScroll.ScrollBarThickness = 3
apScroll.ScrollBarImageColor3 = T.Accent; apScroll.CanvasSize = UDim2.new(0,0,0,0)
apScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; apScroll.Parent = adminPanel
local apLayout = Instance.new("UIListLayout")
apLayout.SortOrder = Enum.SortOrder.LayoutOrder; apLayout.Padding = UDim.new(0, 8)
apLayout.Parent = apScroll

-- Generate section
local secGenerate = makeSection(apScroll, "GENERATE KEY", 2, "⚡")

local keyOutputBg = Instance.new("Frame")
keyOutputBg.Size = UDim2.new(1, 0, 0, 38); keyOutputBg.BackgroundColor3 = T.Input
keyOutputBg.BorderSizePixel = 0; keyOutputBg.LayoutOrder = 1; keyOutputBg.Parent = secGenerate
corner(keyOutputBg, 8); stroke(keyOutputBg, T.Border, 1)

local keyOutputIcon2 = Instance.new("TextLabel")
keyOutputIcon2.Size = UDim2.new(0, 32, 1, 0); keyOutputIcon2.BackgroundTransparency = 1
keyOutputIcon2.Text = "🔐"; keyOutputIcon2.TextSize = 14; keyOutputIcon2.Font = Enum.Font.GothamBold
keyOutputIcon2.Parent = keyOutputBg

local keyOutputBox = Instance.new("TextBox")
keyOutputBox.Size = UDim2.new(1, -72, 1, 0); keyOutputBox.Position = UDim2.new(0, 32, 0, 0)
keyOutputBox.BackgroundTransparency = 1; keyOutputBox.PlaceholderText = "Click Generate → key appears here"
keyOutputBox.PlaceholderColor3 = T.TextMuted; keyOutputBox.Text = ""; keyOutputBox.TextColor3 = T.On
keyOutputBox.TextSize = 12; keyOutputBox.Font = Enum.Font.Code; keyOutputBox.ClearTextOnFocus = false
keyOutputBox.TextEditable = false; keyOutputBox.TextXAlignment = Enum.TextXAlignment.Left
keyOutputBox.Parent = keyOutputBg

local copyKeyBtn = Instance.new("TextButton")
copyKeyBtn.Size = UDim2.new(0, 34, 0, 28); copyKeyBtn.Position = UDim2.new(1, -38, 0.5, -14)
copyKeyBtn.BackgroundColor3 = T.AccentSoft; copyKeyBtn.BackgroundTransparency = 0.7
copyKeyBtn.Text = "📋"; copyKeyBtn.TextSize = 14; copyKeyBtn.Font = Enum.Font.GothamBold
copyKeyBtn.TextColor3 = T.AccentGlow; copyKeyBtn.BorderSizePixel = 0
copyKeyBtn.AutoButtonColor = false; copyKeyBtn.Parent = keyOutputBg; corner(copyKeyBtn, 6)
copyKeyBtn.MouseEnter:Connect(function() tw(copyKeyBtn, {BackgroundTransparency = 0.4}, 0.12) end)
copyKeyBtn.MouseLeave:Connect(function() tw(copyKeyBtn, {BackgroundTransparency = 0.7}, 0.12) end)
copyKeyBtn.MouseButton1Click:Connect(function()
    if keyOutputBox.Text ~= "" then
        if setclipboard then setclipboard(keyOutputBox.Text); notifySuccess("Copied!", "Key copied to clipboard")
        else notifyWarn("Unavailable", "Clipboard not supported") end
    end
end)

local genBtnRow = Instance.new("Frame")
genBtnRow.Size = UDim2.new(1, 0, 0, 36); genBtnRow.BackgroundTransparency = 1
genBtnRow.LayoutOrder = 2; genBtnRow.Parent = secGenerate
local genBtnLayout = Instance.new("UIListLayout")
genBtnLayout.FillDirection = Enum.FillDirection.Horizontal
genBtnLayout.SortOrder = Enum.SortOrder.LayoutOrder
genBtnLayout.Padding = UDim.new(0, 6); genBtnLayout.Parent = genBtnRow

local genBtn = Instance.new("TextButton")
genBtn.Size = UDim2.new(0.65, -3, 1, 0); genBtn.BackgroundColor3 = T.On
genBtn.BackgroundTransparency = 0.15; genBtn.Text = "⚡  Generate New Key"
genBtn.TextColor3 = Color3.new(1,1,1); genBtn.TextSize = 13; genBtn.Font = Enum.Font.GothamBold
genBtn.BorderSizePixel = 0; genBtn.AutoButtonColor = false; genBtn.LayoutOrder = 1
genBtn.Parent = genBtnRow; corner(genBtn, 8)
applyDarkGradient(genBtn)
genBtn.MouseEnter:Connect(function() tw(genBtn, {BackgroundTransparency = 0.05, TextSize = 14}, 0.2, Enum.EasingStyle.Quint) end)
genBtn.MouseLeave:Connect(function() tw(genBtn, {BackgroundTransparency = 0.15, TextSize = 13}, 0.2, Enum.EasingStyle.Quint) end)
genBtn.MouseButton1Down:Connect(function() tw(genBtn, {BackgroundTransparency = 0.0, TextSize = 12}, 0.1, Enum.EasingStyle.Quint) end)
genBtn.MouseButton1Up:Connect(function() tw(genBtn, {BackgroundTransparency = 0.05, TextSize = 14}, 0.1, Enum.EasingStyle.Quint) end)

local revokeAllBtn = Instance.new("TextButton")
revokeAllBtn.Size = UDim2.new(0.35, -3, 1, 0); revokeAllBtn.BackgroundColor3 = T.Danger
revokeAllBtn.BackgroundTransparency = 0.8; revokeAllBtn.Text = "🗑 Revoke All"
revokeAllBtn.TextColor3 = T.Danger; revokeAllBtn.TextSize = 12; revokeAllBtn.Font = Enum.Font.GothamBold
revokeAllBtn.BorderSizePixel = 0; revokeAllBtn.AutoButtonColor = false; revokeAllBtn.LayoutOrder = 2
revokeAllBtn.Parent = genBtnRow; corner(revokeAllBtn, 8); stroke(revokeAllBtn, T.Danger, 1)
applyDarkGradient(revokeAllBtn)
revokeAllBtn.MouseEnter:Connect(function() tw(revokeAllBtn, {BackgroundTransparency = 0.6, TextSize = 13}, 0.2, Enum.EasingStyle.Quint) end)
revokeAllBtn.MouseLeave:Connect(function() tw(revokeAllBtn, {BackgroundTransparency = 0.8, TextSize = 12}, 0.2, Enum.EasingStyle.Quint) end)
revokeAllBtn.MouseButton1Down:Connect(function() tw(revokeAllBtn, {BackgroundTransparency = 0.4, TextSize = 11}, 0.1, Enum.EasingStyle.Quint) end)
revokeAllBtn.MouseButton1Up:Connect(function() tw(revokeAllBtn, {BackgroundTransparency = 0.6, TextSize = 13}, 0.1, Enum.EasingStyle.Quint) end)

-- Key list
local secKeyList = makeSection(apScroll, "ACTIVE KEYS", 3, "📋")
local keyListScroll = Instance.new("ScrollingFrame")
keyListScroll.Size = UDim2.new(1, 0, 0, 180); keyListScroll.BackgroundColor3 = T.LogBg
keyListScroll.BorderSizePixel = 0; keyListScroll.ScrollBarThickness = 3
keyListScroll.ScrollBarImageColor3 = T.Accent; keyListScroll.CanvasSize = UDim2.new(0,0,0,0)
keyListScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; keyListScroll.LayoutOrder = 1
keyListScroll.Parent = secKeyList; corner(keyListScroll, 8); pad(keyListScroll, 6,6,6,6)
local klLayout = Instance.new("UIListLayout")
klLayout.SortOrder = Enum.SortOrder.LayoutOrder; klLayout.Padding = UDim.new(0, 4)
klLayout.Parent = keyListScroll

local function refreshKeyList()
    validKeys = loadKeys()
    for _, c in ipairs(keyListScroll:GetChildren()) do
        if c:IsA("Frame") and c.Name:sub(1,4) == "Key_" then c:Destroy() end
    end
    for _, c in ipairs(keyListScroll:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    if #validKeys == 0 then
        local empty = Instance.new("TextLabel")
        empty.Name = "Key_empty"; empty.Size = UDim2.new(1, 0, 0, 40)
        empty.BackgroundTransparency = 1
        empty.Text = "No keys yet — click Generate!"
        empty.TextColor3 = T.TextMuted; empty.TextSize = 11; empty.Font = Enum.Font.Gotham
        empty.LayoutOrder = 1; empty.Parent = keyListScroll
        return
    end
    for i, k in ipairs(validKeys) do
        local card = Instance.new("Frame")
        card.Name = "Key_"..i; card.Size = UDim2.new(1, 0, 0, 48)
        card.BackgroundColor3 = k.active and Color3.fromRGB(18,22,18) or Color3.fromRGB(22,16,16)
        card.BorderSizePixel = 0; card.LayoutOrder = i; card.Parent = keyListScroll
        corner(card, 8)
        stroke(card, k.active and Color3.fromRGB(40,80,50) or Color3.fromRGB(80,40,40), 1)

        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0,8,0,8); dot.Position = UDim2.new(0,10,0,10)
        dot.BackgroundColor3 = k.active and T.On or T.Danger; dot.BorderSizePixel = 0
        dot.Parent = card; corner(dot, 4)

        local keyLbl = Instance.new("TextLabel")
        keyLbl.Size = UDim2.new(1,-90,0,16); keyLbl.Position = UDim2.new(0,24,0,6)
        keyLbl.BackgroundTransparency = 1; keyLbl.Text = k.key
        keyLbl.TextColor3 = k.active and T.Text or T.TextMuted; keyLbl.TextSize = 11
        keyLbl.Font = Enum.Font.Code; keyLbl.TextXAlignment = Enum.TextXAlignment.Left
        keyLbl.Parent = card

        local metaLbl = Instance.new("TextLabel")
        metaLbl.Size = UDim2.new(1,-90,0,12); metaLbl.Position = UDim2.new(0,24,0,24)
        metaLbl.BackgroundTransparency = 1
        metaLbl.Text = (k.created or "unknown") .. " · " .. (k.active and "✓ Active" or "✕ Revoked")
        metaLbl.TextColor3 = T.TextMuted; metaLbl.TextSize = 9; metaLbl.Font = Enum.Font.Gotham
        metaLbl.TextXAlignment = Enum.TextXAlignment.Left; metaLbl.Parent = card

        local copyBtn = Instance.new("TextButton")
        copyBtn.Size = UDim2.new(0,28,0,28); copyBtn.Position = UDim2.new(1,-66,0.5,-14)
        copyBtn.BackgroundColor3 = T.AccentSoft; copyBtn.BackgroundTransparency = 0.75
        copyBtn.Text = "📋"; copyBtn.TextSize = 12; copyBtn.Font = Enum.Font.GothamBold
        copyBtn.BorderSizePixel = 0; copyBtn.AutoButtonColor = false; copyBtn.Parent = card
        corner(copyBtn, 6)
        copyBtn.MouseEnter:Connect(function() tw(copyBtn, {BackgroundTransparency = 0.5}, 0.12) end)
        copyBtn.MouseLeave:Connect(function() tw(copyBtn, {BackgroundTransparency = 0.75}, 0.12) end)
        copyBtn.MouseButton1Click:Connect(function()
            pcall(function()
                if setclipboard then setclipboard(k.key) end
            end)
            notifySuccess("Copied", k.key)
        end)

        local actionBtn = Instance.new("TextButton")
        actionBtn.Size = UDim2.new(0,28,0,28); actionBtn.Position = UDim2.new(1,-34,0.5,-14)
        if k.active then
            actionBtn.BackgroundColor3 = T.Danger; actionBtn.BackgroundTransparency = 0.75
            actionBtn.Text = "✕"; actionBtn.TextColor3 = T.Danger
        else
            actionBtn.BackgroundColor3 = T.On; actionBtn.BackgroundTransparency = 0.75
            actionBtn.Text = "✓"; actionBtn.TextColor3 = T.On
        end
        actionBtn.TextSize = 13; actionBtn.Font = Enum.Font.GothamBold
        actionBtn.BorderSizePixel = 0; actionBtn.AutoButtonColor = false
        actionBtn.Parent = card; corner(actionBtn, 6)
        actionBtn.MouseEnter:Connect(function() tw(actionBtn, {BackgroundTransparency = 0.45}, 0.12) end)
        actionBtn.MouseLeave:Connect(function() tw(actionBtn, {BackgroundTransparency = 0.75}, 0.12) end)
        actionBtn.MouseButton1Click:Connect(function()
            if k.active then
                k.active = false; saveKeys(validKeys); refreshKeyList()
                notifyWarn("Key Revoked", k.key)
                sendWebhook("🔒 Key Revoked", "**Key:** ||"..k.key.."||", 15158332)
            else
                k.active = true; saveKeys(validKeys); refreshKeyList()
                notifySuccess("Key Re-enabled", k.key)
                sendWebhook("🔓 Key Re-enabled", "**Key:** ||"..k.key.."||", 3066993)
            end
        end)
    end
end
refreshKeyList()

genBtn.MouseButton1Click:Connect(function()
    tw(genBtn, {BackgroundTransparency = 0.5}, 0.05)
    task.delay(0.1, function() tw(genBtn, {BackgroundTransparency = 0.15}, 0.2) end)
    local newKey = generateKey()
    validKeys = loadKeys()
    table.insert(validKeys, {key = newKey, active = true, created = os.date("%Y-%m-%d %H:%M"), createdBy = player.Name})
    saveKeys(validKeys)
    keyOutputBox.Text = newKey
    refreshKeyList()
    addLog("Generated key: "..newKey)
    notifySuccess("Key Generated", newKey)
    sendWebhook("🔑 Key Generated", "**By:** "..player.Name.."\n**Key:** ||"..newKey.."||", 3066993, {
        {name = "Total Keys", value = tostring(#validKeys), inline = true},
    })
end)

revokeAllBtn.MouseButton1Click:Connect(function()
    tw(revokeAllBtn, {BackgroundTransparency = 0.4}, 0.05)
    task.delay(0.1, function() tw(revokeAllBtn, {BackgroundTransparency = 0.8}, 0.2) end)
    validKeys = loadKeys()
    for _, k in ipairs(validKeys) do k.active = false end
    saveKeys(validKeys); refreshKeyList()
    notifyWarn("All Keys Revoked", "All keys deactivated")
    sendWebhook("⚠ All Keys Revoked", "**By:** "..player.Name, 15158332)
end)

apClose.MouseButton1Click:Connect(function()
    tw(adminPanel, {Size = UDim2.new(0, 380, 0, 0), BackgroundTransparency = 1}, 0.28, Enum.EasingStyle.Quart)
    task.delay(0.3, function() adminPanel.Visible = false; adminPanel.BackgroundTransparency = 0 end)
end)

-- Toggle function (called by K hotkey)
local function toggleAdminPanel()
    if not isOwner then return end
    if adminPanel.Visible then
        tw(adminPanel, {Size = UDim2.new(0, 380, 0, 0), BackgroundTransparency = 1}, 0.25, Enum.EasingStyle.Quart)
        task.delay(0.28, function() adminPanel.Visible = false; adminPanel.Size = UDim2.new(0, 380, 0, 520); adminPanel.BackgroundTransparency = 0 end)
    else
        adminPanel.Size = UDim2.new(0, 380, 0, 0)
        adminPanel.BackgroundTransparency = 1
        adminPanel.Visible = true
        refreshKeyList()
        tw(adminPanel, {Size = UDim2.new(0, 380, 0, 520), BackgroundTransparency = 0}, 0.35, Enum.EasingStyle.Back)
    end
end

-- Set default tab (already called above in the floating panel block)


-- ════════════════════════════════════════════
--  DRAGGING
-- ════════════════════════════════════════════
do
    local dragging, dragStart, startPos
    topBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = mainHub.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            mainHub.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

-- ════════════════════════════════════════════
--  CLOSE / MINIMIZE
-- ════════════════════════════════════════════
local minimized = false
local fullSize = UDim2.new(0, 460, 0, 560)

closeBtn.MouseButton1Click:Connect(function()
    tw(mainHub, {Size = UDim2.new(0, 460, 0, 0), BackgroundTransparency = 1}, 0.3)
    task.delay(0.35, function() gui:Destroy() end)
end)

minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        contentFrame.Visible = false; tabBar.Visible = false
        tw(mainHub, {Size = UDim2.new(0, 460, 0, 46)}, 0.3, Enum.EasingStyle.Quart)
    else
        contentFrame.Visible = true; tabBar.Visible = true
        tw(mainHub, {Size = fullSize}, 0.35, Enum.EasingStyle.Back)
    end
end)

-- ═══════════════════════════════════════════════════
--  CORE LOGIC
-- ═══════════════════════════════════════════════════

-- Character Setup
local function setupCharacter(char)
    local hum = char:WaitForChild("Humanoid")
    if Settings.SpeedLock then hum.WalkSpeed = Settings.WalkSpeed end
    if Settings.JumpLock then hum.JumpPower = Settings.JumpPower end
    hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if Settings.SpeedLock and hum.WalkSpeed ~= Settings.WalkSpeed then hum.WalkSpeed = Settings.WalkSpeed end
    end)
    hum:GetPropertyChangedSignal("JumpPower"):Connect(function()
        if Settings.JumpLock and hum.JumpPower ~= Settings.JumpPower then hum.JumpPower = Settings.JumpPower end
    end)
    addLog("Character loaded · speed "..Settings.WalkSpeed)
end
if player.Character then setupCharacter(player.Character) end
player.CharacterAdded:Connect(setupCharacter)

-- Teleport Util
teleportTo = function(dest)
    local c = player.Character; if not c then return false end
    local rp = c:FindFirstChild("HumanoidRootPart"); if not rp then return false end
    if dest and dest:IsA("BasePart") then rp.CFrame = dest.CFrame + Vector3.new(0, 5, 0); return true end
    return false
end

-- Noclip Loop
RunService.Stepped:Connect(function()
    if Settings.Noclip then
        local char = player.Character
        if char then for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end end
    end
end)

-- Anti-AFK
if VirtualUser then
    player.Idled:Connect(function()
        if Settings.AntiAFK then
            VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new())
            addLog("Anti-AFK triggered")
        end
    end)
end

-- Hotkeys
UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local kn = input.KeyCode.Name
    
    if kn == Settings.Binds.Zone12 then
        local z = workspace:FindFirstChild("Zones")
        if z then local z12 = z:FindFirstChild("12")
            if z12 and teleportTo(z12) then addLog("TP → Zone 12"); notifySuccess("Teleported", "Zone 12")
            else addLog("Zone 12 not found") end
        end
    elseif kn == Settings.Binds.PlotBase then
        pcall(function()
            local base = workspace.Plots.Plot2.Base; local ch = base:GetChildren()
            if #ch >= 4 and teleportTo(ch[4]) then addLog("TP → Plot Base"); notifySuccess("Teleported", "Plot Base")
            else addLog("Plot Base missing") end
        end)
    elseif kn == Settings.Binds.ToggleHub then
        mainHub.Visible = not mainHub.Visible
    elseif kn == Settings.Binds.AdminPanel then
        toggleAdminPanel()
    end
end)

-- ESP System
local espHighlights = {}
local rarityMapping = {
    ["COMMON"] = "NORMAL", ["UNCOMMON"] = "GOLDEN", ["RARE"] = "DIAMOND",
    ["EPIC"] = "EMERALD", ["LEGENDARY"] = "RUBY", ["MYTHIC+"] = "VOID",
    ["MYTHIC"] = "RAINBOW", ["GODLY"] = "ETHEREAL", ["SUPREME"] = "CELESTIAL",
    ["NORMAL"] = "NORMAL", ["GOLDEN"] = "GOLDEN", ["DIAMOND"] = "DIAMOND",
    ["EMERALD"] = "EMERALD", ["RUBY"] = "RUBY", ["RAINBOW"] = "RAINBOW",
    ["VOID"] = "VOID", ["ETHEREAL"] = "ETHEREAL", ["CELESTIAL"] = "CELESTIAL"
}

local function updateESP()
    local currentCounts = {}
    
    if not Settings.ESP then
        for _, cache in pairs(espHighlights) do 
            if cache.bg and cache.bg.Parent then cache.bg:Destroy() end 
            if cache.hl and cache.hl.Parent then cache.hl:Destroy() end 
        end
        table.clear(espHighlights)
        
        if _G.rarityCountLabels then
            for _, countLbl in pairs(_G.rarityCountLabels) do
                if countLbl.Text ~= "0" then countLbl.Text = "0" end
            end
        end
        return
    end
    
    local folder = workspace:FindFirstChild("ActiveBrainrots"); if not folder then return end
    
    local seen = {}
    for _, hitbox in ipairs(folder:GetChildren()) do
        if hitbox.Name == "ServerHitbox" and hitbox:IsA("BasePart") then
            seen[hitbox] = true
            
            -- Deep rarity analysis to update counters even if not highlighted
            local matchRarity = "NORMAL"
            local nameTxt = "Brainrot"
            local rankTxt = ""
            local earnTxt = ""
            
            local b = hitbox:FindFirstChild("LevelBoard", true)
            local f = b and b:FindFirstChild("Frame")
            if f then
                local rl = f:FindFirstChild("Rarity")
                if rl and rl:IsA("TextLabel") and rl.Text ~= "" then
                    txt = rl.Text:upper()
                    for word, key in pairs(rarityMapping) do
                        if txt:find(word) then matchRarity = key; break end
                    end
                end
                local nLbl = f:FindFirstChild("NameRot")
                local rLbl = f:FindFirstChild("Rank")
                local cF = f:FindFirstChild("CurrencyFrame")
                local eLbl = cF and cF:FindFirstChild("Earnings")
                nameTxt = nLbl and nLbl.Text or "Brainrot"
                rankTxt = rLbl and rLbl.Text or ""
                if eLbl and eLbl:IsA("TextLabel") and eLbl.Text ~= "" then
                    earnTxt = "🪙 " .. eLbl.Text
                end
            end
            
            currentCounts[matchRarity] = (currentCounts[matchRarity] or 0) + 1
            
            local isEnabled = Settings.Rarities[matchRarity]
            
            if espHighlights[hitbox] and not isEnabled then
                -- Rarity was toggled off, clean it up immediately
                local cache = espHighlights[hitbox]
                if cache.bg and cache.bg.Parent then cache.bg:Destroy() end
                if cache.hl and cache.hl.Parent then cache.hl:Destroy() end
                espHighlights[hitbox] = nil
                
            elseif not espHighlights[hitbox] and isEnabled then
                -- Needs to be created
                if f then
                    local cache = {}
                    
                    -- 1. Billboard Text & Button
                    local bg = Instance.new("BillboardGui")
                    bg.Name = "SOFBEsp"
                    bg.Adornee = hitbox
                    bg.Size = UDim2.new(0, 200, 0, 115)
                    bg.StudsOffset = Vector3.new(0, 5, 0)
                    bg.AlwaysOnTop = true
                    bg.Active = true  -- Allows clicks
                                
                                local t1 = Instance.new("TextLabel")
                                t1.Size = UDim2.new(1,0,0,25)
                                t1.BackgroundTransparency = 1
                                t1.Text = rankTxt .. " " .. nameTxt
                                t1.TextColor3 = Color3.new(1,1,1)
                                t1.TextStrokeTransparency = 0
                                t1.Font = Enum.Font.GothamBold
                                t1.TextSize = 14
                                t1.Parent = bg
                                
                                local t2 = Instance.new("TextLabel")
                                t2.Size = UDim2.new(1,0,0,20)
                                t2.Position = UDim2.new(0,0,0,25)
                                t2.BackgroundTransparency = 1
                                t2.Text = "["..txt.."]"
                                t2.TextColor3 = T.Rarity[matchRarity] or T.Accent
                                t2.TextStrokeTransparency = 0
                                t2.Font = Enum.Font.Code
                                t2.TextSize = 13
                                t2.Parent = bg
                                
                                local t3 = Instance.new("TextLabel")
                                t3.Size = UDim2.new(1,0,0,20)
                                t3.Position = UDim2.new(0,0,0,45)
                                t3.BackgroundTransparency = 1
                                t3.Text = earnTxt
                                t3.TextColor3 = Color3.fromRGB(120, 255, 140)
                                t3.TextStrokeTransparency = 0
                                t3.Font = Enum.Font.GothamBold
                                t3.TextSize = 12
                                t3.Parent = bg
                                
                                local tpBtn = Instance.new("TextButton")
                                tpBtn.Size = UDim2.new(0, 70, 0, 22)
                                tpBtn.Position = UDim2.new(0.5, -35, 0, 68)
                                tpBtn.BackgroundColor3 = T.InputFocus
                                tpBtn.Text = "TELEPORT"
                                tpBtn.TextColor3 = T.TextDim
                                tpBtn.Font = Enum.Font.GothamBold
                                tpBtn.TextSize = 11
                                tpBtn.AutoButtonColor = false
                                tpBtn.Parent = bg
                                corner(tpBtn, 6)
                                stroke(tpBtn, T.BorderLight, 1)
                                
                                tpBtn.MouseEnter:Connect(function() tw(tpBtn, {BackgroundColor3 = T.Accent, TextColor3 = Color3.new(1,1,1)}, 0.15) end)
                                tpBtn.MouseLeave:Connect(function() tw(tpBtn, {BackgroundColor3 = T.InputFocus, TextColor3 = T.TextDim}, 0.15) end)
                                tpBtn.MouseButton1Click:Connect(function()
                                    if typeof(teleportTo) == "function" and teleportTo(hitbox) then
                                        addLog("ESP TP → " .. nameTxt)
                                        notifySuccess("Teleported", "Arrived at " .. nameTxt)
                                    end
                                end)
                                
                                bg.Parent = gui.Parent  -- Must root to PlayerGui to accept clicks over 3D space
                                cache.bg = bg
                                
                                -- 2. Model Highlight
                                local hl = Instance.new("Highlight")
                                hl.Name = "SOFBEspHl"
                                hl.Adornee = hitbox
                                hl.FillColor = T.Rarity[matchRarity] or T.Accent
                                hl.FillTransparency = 0.6
                                hl.OutlineColor = T.Rarity[matchRarity] or T.Accent
                                hl.OutlineTransparency = 0
                                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                                hl.Parent = hitbox
                                cache.hl = hl
                                
                                espHighlights[hitbox] = cache
                end
            end
        end
    end
    
    -- Cleanup destroyed/removed brainrots
    for hitbox, cache in pairs(espHighlights) do
        if not seen[hitbox] then
            if cache.bg and cache.bg.Parent then cache.bg:Destroy() end
            if cache.hl and cache.hl.Parent then cache.hl:Destroy() end
            espHighlights[hitbox] = nil
        end
    end
    
    -- Update live UI counters in the ESP filters
    local activeTotal = 0
    if _G.rarityCountLabels then
        for rName, countLbl in pairs(_G.rarityCountLabels) do
            local n = currentCounts[rName] or 0
            activeTotal = activeTotal + n
            if countLbl.Text ~= tostring(n) then
                countLbl.Text = tostring(n)
                task.spawn(function()
                    tw(countLbl, {BackgroundTransparency = 0.3}, 0.1)
                    task.wait(0.3)
                    tw(countLbl, {BackgroundTransparency = 0.88}, 0.3)
                end)
            end
        end
    end
    
    -- Update main stat board
    local elapsed = tick() - Stats.SessionStart
    infoSession.Text = "⏱  Session: "..formatTime(elapsed)
    infoStats.Text = "📊  Active Targets: "..activeTotal.."  │  TPs: "..Stats.TotalTPs
end

-- Refresh ESP loop
task.spawn(function()
    while task.wait(0.5) do
        pcall(updateESP)
    end
end)

-- ESP cleanup
task.spawn(function()
    local lastESP = Settings.ESP
    while task.wait(0.5) do
        if lastESP and not Settings.ESP then clearESP() end
        lastESP = Settings.ESP
    end
end)

-- Startup
addLog("Origin's SOFB Hub v3.0 loaded!")
addLog("[G] Zone 12  [B] Plot  [R⇧] Toggle  [N] Test Notif")
addLog("Enable Auto-TP to start scanning…")
