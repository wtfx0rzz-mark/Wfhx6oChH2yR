--[[
  99 Nights – Non-destructive Add-On (CeeGee build)
  - Keeps ALL existing Rayfield tabs. Only appends new controls.
  - Implements:
      • Chop/Kill aura with streamed-target requeue (range-gated) + optional Aggressive Preload
      • "Visible Only" mode (ignores radius when ON)
      • Big Trees toggle
      • Highlights: Trees & Animals (bright yellow)
      • Auto collect gold: Workspace.Items["Coin Stack"], scans & listens
      • Scrapper-vs-Campfire feed preference (prefers Scrapper movers in range)
      • Removes/neutralizes: "Auto Feed" toggle (UI removed if present), "Auto Stun Deer" (removed)
      • Tweakables with one-line comments
  - Safe to re-run (idempotent): uses getgenv() singletons and guarded connections
]]

-- =========== Bootstrap ===========
local HttpGet = (syn and syn.request) and game.HttpGet or game.HttpGet
local rfURL   = 'https://sirius.menu/rayfield'

local Rayfield = getgenv().Rayfield
if not Rayfield then
    Rayfield = loadstring(game:HttpGet(rfURL))()
    getgenv().Rayfield = Rayfield
end

-- Reuse/create a window without nuking existing tabs
local Window = getgenv().__MainWindow
if not Window or type(Window) ~= "table" or not Window.CreateTab then
    Window = Rayfield:CreateWindow({
        Name = "99 Nights – Utilities",
        LoadingTitle = "Initializing",
        LoadingSubtitle = "CeeGee",
        DisableRayfieldPrompts = true,
        ConfigurationSaving = { Enabled = false },
    })
    getgenv().__MainWindow = Window
end

local function getOrCreateTab(title, icon)
    if Window.Tabs then
        for _, t in ipairs(Window.Tabs) do
            if t.Name == title then return t end
        end
    end
    return Window:CreateTab(title, icon or 4483362458)
end

-- Use existing “Main” and “Settings” if you already have them; otherwise add.
local TabMain     = getOrCreateTab("Main",     4483362458)
local TabSettings = getOrCreateTab("Settings", 4483362458)

-- =========== Services / Handles ===========
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local function HRP()
    local c = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return c:FindFirstChild("HumanoidRootPart")
end

local function dist(a, b) return (a - b).Magnitude end
local function now() return os.clock() end

-- =========== Tweakables (short comments only) ===========
local CFG = getgenv().__CEE_CFG or {
    AURA_SWING_DELAY   = 0.45,   -- secs between kill-aura waves
    CHOP_SWING_DELAY   = 0.40,   -- secs between chop waves
    AURA_RADIUS        = 500,    -- default studs when VisibleOnly=false
    QUEUE_RETRY_SECS   = 0.20,   -- secs between requeue tries
    QUEUE_MAX          = 400,    -- max queued targets
    PRELOAD_NUDGE      = 6,      -- studs for streaming nudge
    HLINE_THICKNESS    = 0.08,   -- highlight line thickness
    HLINE_ZINDEX       = 10,     -- highlight draw order
    GOLD_SCAN_RATE     = 0.35,   -- secs between gold scans
    FEED_SCAN_RATE     = 0.60,   -- secs between feed checks
    SCRAPPER_PREF_RAD  = 35,     -- studs to prefer Scrapper
    CAMPFIRE_RAD       = 35,     -- studs to feed Campfire
}
getgenv().__CEE_CFG = CFG

-- =========== Runtime State ===========
local STATE = getgenv().__CEE_STATE or {
    KillAura        = false,
    ChopAura        = true,
    BigTrees        = false,
    VisibleOnly     = false,
    AggressivePre   = false,
    HL_Trees        = false,
    HL_Animals      = false,
    AutoGold        = false,
}
getgenv().__CEE_STATE = STATE

local auraRadiusSliderValue = CFG.AURA_RADIUS

-- =========== World Knowledge ===========
local SMALL_TREE_NAMES = { "Small Tree", "TreeSmall", "Tree_1", "Tree" }
local BIG_TREE_NAMES   = { "TreeBig1", "TreeBig2", "TreeBig3", "Big Tree", "Huge Tree" }

local function isBigTreeName(n)
    for _, s in ipairs(BIG_TREE_NAMES) do if n == s then return true end end
    return false
end

local function isTreeModel(m)
    if not m or not m:IsA("Model") then return false end
    local n = m.Name
    for _, s in ipairs(SMALL_TREE_NAMES) do if n == s then return true end end
    for _, s in ipairs(BIG_TREE_NAMES) do if n == s then return true end end
    return false
end

local function isAnimalModel(m)
    if not m or not m:IsA("Model") then return false end
    if m:FindFirstChildOfClass("Humanoid") and not m:FindFirstChild("PlayerGui") then
        return true
    end
    return false
end

local function hasTreeHealth(model)
    if model:GetAttribute("Health") then return true end
    local v = model:FindFirstChild("TreeHealth") or model:FindFirstChild("Health")
    return v and v:IsA("ValueBase") or false
end

-- =========== Highlights ===========
local HFolder = Workspace:FindFirstChild("__AuraHighlights__") or (function()
    local f = Instance.new("Folder")
    f.Name = "__AuraHighlights__"
    f.Parent = Workspace
    return f
end)()

local activeBoxes = {} -- [Instance]=SelectionBox

local function ensureBox(adorn)
    local sb = activeBoxes[adorn]
    if not sb then
        sb = Instance.new("SelectionBox")
        sb.Name = "__AuraSB"
        sb.LineThickness = CFG.HLINE_THICKNESS
        sb.SurfaceTransparency = 1
        sb.Color3 = Color3.new(1,1,0)
        sb.ZIndex = CFG.HLINE_ZINDEX
        sb.Adornee = adorn
        sb.Parent = HFolder
        activeBoxes[adorn] = sb
    else
        sb.Adornee = adorn
    end
    return sb
end

local function clearHighlights()
    for inst, box in pairs(activeBoxes) do
        if box then box:Destroy() end
        activeBoxes[inst] = nil
    end
end

-- =========== Queues / Streaming ===========
local Requeue = getgenv().__CEE_REQUEUE or {}
getgenv().__CEE_REQUEUE = Requeue

local function requeueTarget(model)
    if #Requeue >= CFG.QUEUE_MAX then return end
    table.insert(Requeue, { model = model, t = now() })
end

local function pruneQueue(centerPos, enabled, maxRange)
    local keep = {}
    for _, q in ipairs(Requeue) do
        local m = q.model
        if enabled and m and m.Parent then
            local pp = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
            if pp and dist(centerPos, pp.Position) <= maxRange then
                table.insert(keep, q)
            end
        end
    end
    table.clear(Requeue)
    for _, v in ipairs(keep) do table.insert(Requeue, v) end
end

local function nudgeForStreaming(model)
    local pp = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not pp then return end
    local origin = pp.Position + Vector3.new(0, 3, 0)
    Workspace:Raycast(origin, Vector3.new(0, -CFG.PRELOAD_NUDGE, 0))
end

-- =========== Remote Handles (best-effort) ===========
local Remotes = getgenv().__CEE_REMOTES
if not Remotes then
    local R = ReplicatedStorage
    local function findChain(...)
        local node = R
        for _, n in ipairs({...}) do
            node = node and node:FindFirstChild(n)
        end
        return node
    end
    Remotes = {
        ChopTree     = findChain("Remotes","ChopTree")     or R:FindFirstChild("ChopTree"),
        HitEnemy     = findChain("Remotes","HitEnemy")     or R:FindFirstChild("HitEnemy"),
        FeedCampfire = findChain("Remotes","FeedCampfire") or R:FindFirstChild("FeedCampfire"),
        FeedScrapper = findChain("Remotes","FeedScrapper") or R:FindFirstChild("FeedScrapper"),
        CollectCoin  = findChain("Remotes","CollectCoin")  or R:FindFirstChild("CollectCoin"),
    }
    getgenv().__CEE_REMOTES = Remotes
end

local function serverChop(m)     if Remotes.ChopTree     and m then pcall(function() Remotes.ChopTree:FireServer(m) end) end end
local function serverHit(m)      if Remotes.HitEnemy     and m then pcall(function() Remotes.HitEnemy:FireServer(m) end) end end
local function serverCampfire(m) if Remotes.FeedCampfire and m then pcall(function() Remotes.FeedCampfire:FireServer(m) end) end end
local function serverScrapper(m) if Remotes.FeedScrapper and m then pcall(function() Remotes.FeedScrapper:FireServer(m) end) end end
local function serverCollect(m)
    if Remotes.CollectCoin and m then
        pcall(function() Remotes.CollectCoin:FireServer(m) end)
        return true
    end
    local prompt = m:FindFirstChildOfClass("ProximityPrompt") or m:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt and typeof(fireproximityprompt) == "function" then
        pcall(function() prompt.HoldDuration = 0; fireproximityprompt(prompt) end)
        return true
    end
    return false
end

-- =========== Scanners ===========
local function sweepTargets(centerPos, radius)
    local trees, animals = {}, {}
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("Model") then
            local pp = d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart")
            if pp then
                local within = dist(centerPos, pp.Position) <= radius
                if within then
                    if isTreeModel(d) and (STATE.BigTrees or not isBigTreeName(d.Name)) then
                        trees[#trees+1] = d
                    elseif isAnimalModel(d) then
                        animals[#animals+1] = d
                    end
                end
            end
        end
    end
    return trees, animals
end

-- =========== Auras ===========
if getgenv().__CEE_CHOP_THREAD then
    getgenv().__CEE_CHOP_THREAD:Disconnect()
    getgenv().__CEE_CHOP_THREAD = nil
end
if getgenv().__CEE_KILL_THREAD then
    getgenv().__CEE_KILL_THREAD:Disconnect()
    getgenv().__CEE_KILL_THREAD = nil
end

getgenv().__CEE_CHOP_THREAD = RunService.Heartbeat:Connect(function()
    if not STATE.ChopAura then return end
    local root = HRP(); if not root then return end
    local center = root.Position
    local radius = STATE.VisibleOnly and 99999 or auraRadiusSliderValue

    local trees = ({sweepTargets(center, radius)})[1]

    -- highlights
    if STATE.HL_Trees then
        for _, m in ipairs(trees) do
            local adorn = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
            if adorn then ensureBox(adorn) end
        end
    end
    if not STATE.HL_Trees and next(activeBoxes) then clearHighlights() end

    -- chop or requeue
    local lastWave = getgenv().__CEE_LAST_CHOP or 0
    if (now() - lastWave) >= CFG.CHOP_SWING_DELAY then
        for _, t in ipairs(trees) do
            if hasTreeHealth(t) then
                serverChop(t)
            else
                local pp = t.PrimaryPart or t:FindFirstChildWhichIsA("BasePart")
                if pp and dist(center, pp.Position) <= radius then
                    if STATE.AggressivePre then nudgeForStreaming(t) end
                    requeueTarget(t)
                end
            end
        end
        getgenv().__CEE_LAST_CHOP = now()
    end

    -- queue retry
    if #Requeue > 0 then
        local lastQ = getgenv().__CEE_LAST_Q or 0
        if (now() - lastQ) >= CFG.QUEUE_RETRY_SECS then
            pruneQueue(center, STATE.ChopAura, radius)
            for i = #Requeue, 1, -1 do
                local q = Requeue[i]
                local m = q.model
                if not m or not m.Parent then
                    table.remove(Requeue, i)
                else
                    if hasTreeHealth(m) then
                        serverChop(m)
                        table.remove(Requeue, i)
                    else
                        if STATE.AggressivePre then nudgeForStreaming(m) end
                        -- keep queued if still valid; prune handles range
                    end
                end
            end
            getgenv().__CEE_LAST_Q = now()
        end
    end
end)

getgenv().__CEE_KILL_THREAD = RunService.Heartbeat:Connect(function()
    if not STATE.KillAura then return end
    local root = HRP(); if not root then return end
    local center = root.Position
    local radius = STATE.VisibleOnly and 99999 or auraRadiusSliderValue

    local _, animals = sweepTargets(center, radius)

    if STATE.HL_Animals then
        for _, m in ipairs(animals) do
            local adorn = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
            if adorn then ensureBox(adorn) end
        end
    elseif next(activeBoxes) and not STATE.HL_Trees then
        clearHighlights()
    end

    local lastWave = getgenv().__CEE_LAST_KILL or 0
    if (now() - lastWave) >= CFG.AURA_SWING_DELAY then
        for _, mob in ipairs(animals) do serverHit(mob) end
        getgenv().__CEE_LAST_KILL = now()
    end
end)

-- =========== Scrapper/Campfire Feeder ===========
if getgenv().__CEE_FEED_THREAD then
    getgenv().__CEE_FEED_THREAD:Disconnect()
    getgenv().__CEE_FEED_THREAD = nil
end

local function nearestByName(center, names, maxR)
    local best, bestD = nil, math.huge
    for _, m in ipairs(Workspace:GetDescendants()) do
        if m:IsA("Model") then
            for _, n in ipairs(names) do
                if m.Name == n then
                    local pp = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
                    if pp then
                        local d = dist(center, pp.Position)
                        if d < bestD and d <= maxR then best, bestD = m, d end
                    end
                end
            end
        end
    end
    return best
end

getgenv().__CEE_FEED_THREAD = RunService.Heartbeat:Connect(function()
    local last = getgenv().__CEE_LAST_FEED or 0
    if (now() - last) < CFG.FEED_SCAN_RATE then return end
    local root = HRP(); if not root then return end
    local center = root.Position

    local scrapper = nearestByName(center, { "Scrapper" }, CFG.SCRAPPER_PREF_RAD)
    if scrapper then
        serverScrapper(scrapper)
    else
        local camp = nearestByName(center, { "Campfire" }, CFG.CAMPFIRE_RAD)
        if camp then serverCampfire(camp) end
    end
    getgenv().__CEE_LAST_FEED = now()
end)

-- =========== Auto Gold Collector ===========
local function itemsFolder() return Workspace:FindFirstChild("Items") end

local function scanGold()
    local items = itemsFolder(); if not items then return end
    for _, ch in ipairs(items:GetChildren()) do
        if ch:IsA("Model") and ch.Name == "Coin Stack" then
            serverCollect(ch)
        end
    end
end

if getgenv().__CEE_GOLD_THREAD then
    getgenv().__CEE_GOLD_THREAD:Disconnect()
    getgenv().__CEE_GOLD_THREAD = nil
end
if getgenv().__CEE_GOLD_CONN then
    getgenv().__CEE_GOLD_CONN:Disconnect()
    getgenv().__CEE_GOLD_CONN = nil
end

getgenv().__CEE_GOLD_THREAD = RunService.Heartbeat:Connect(function()
    if not STATE.AutoGold then return end
    local last = getgenv().__CEE_LAST_GOLD or 0
    if (now() - last) >= CFG.GOLD_SCAN_RATE then
        scanGold()
        getgenv().__CEE_LAST_GOLD = now()
    end
end)

local function hookGold(enabled)
    if getgenv().__CEE_GOLD_CONN then
        getgenv().__CEE_GOLD_CONN:Disconnect()
        getgenv().__CEE_GOLD_CONN = nil
    end
    if not enabled then return end
    local items = itemsFolder()
    if not items then return end
    getgenv().__CEE_GOLD_CONN = items.ChildAdded:Connect(function(ch)
        if STATE.AutoGold and ch:IsA("Model") and ch.Name == "Coin Stack" then
            task.defer(serverCollect, ch)
        end
    end)
end

-- =========== UI: ONLY add/adjust; do not remove existing tabs ===========
-- Main
local ui_KillAura = TabMain:CreateToggle({
    Name = "Kill Aura",
    CurrentValue = STATE.KillAura,
    Flag = "CEE_KillAura",
    Callback = function(v) STATE.KillAura = v end
})
local ui_ChopAura = TabMain:CreateToggle({
    Name = "Chop Aura",
    CurrentValue = STATE.ChopAura,
    Flag = "CEE_ChopAura",
    Callback = function(v) STATE.ChopAura = v end
})
local ui_BigTrees = TabMain:CreateToggle({
    Name = "Big Trees",
    CurrentValue = STATE.BigTrees,
    Flag = "CEE_BigTrees",
    Callback = function(v) STATE.BigTrees = v end
})
local ui_VisibleOnly = TabMain:CreateToggle({
    Name = "Visible Only (Ignores Radius)",
    CurrentValue = STATE.VisibleOnly,
    Flag = "CEE_VisibleOnly",
    Callback = function(v) STATE.VisibleOnly = v end
})
local ui_Aggressive = TabMain:CreateToggle({
    Name = "Aggressive Preload (Streaming Nudge)",
    CurrentValue = STATE.AggressivePre,
    Flag = "CEE_AggressivePre",
    Callback = function(v) STATE.AggressivePre = v end
})

TabMain:CreateSection("Highlights")
local ui_HL_Trees = TabMain:CreateToggle({
    Name = "Highlight Trees (Yellow)",
    CurrentValue = STATE.HL_Trees,
    Flag = "CEE_HL_Trees",
    Callback = function(v) STATE.HL_Trees = v if not v and not STATE.HL_Animals then clearHighlights() end end
})
local ui_HL_Animals = TabMain:CreateToggle({
    Name = "Highlight Animals (Yellow)",
    CurrentValue = STATE.HL_Animals,
    Flag = "CEE_HL_Animals",
    Callback = function(v) STATE.HL_Animals = v if not v and not STATE.HL_Trees then clearHighlights() end end
})

TabMain:CreateSection("Gold")
local ui_Gold = TabMain:CreateToggle({
    Name = "Auto Collect Gold (Coin Stack)",
    CurrentValue = STATE.AutoGold,
    Flag = "CEE_AutoGold",
    Callback = function(v) STATE.AutoGold = v; hookGold(v) end
})

-- Settings
local ui_Radius = TabSettings:CreateSlider({
    Name = "Aura Radius",
    Range = {100, 2000},
    Increment = 1,
    Suffix = " studs",
    CurrentValue = auraRadiusSliderValue,
    Flag = "CEE_AuraRadius",
    Callback = function(v) auraRadiusSliderValue = v end
})
local ui_ChopDelay = TabSettings:CreateSlider({
    Name = "Chop Wave Delay",
    Range = {0.05, 1.5},
    Increment = 0.01,
    Suffix = " s",
    CurrentValue = CFG.CHOP_SWING_DELAY,
    Flag = "CEE_ChopDelay",
    Callback = function(v) CFG.CHOP_SWING_DELAY = v end
})
local ui_KillDelay = TabSettings:CreateSlider({
    Name = "Kill Wave Delay",
    Range = {0.05, 1.5},
    Increment = 0.01,
    Suffix = " s",
    CurrentValue = CFG.AURA_SWING_DELAY,
    Flag = "CEE_KillDelay",
    Callback = function(v) CFG.AURA_SWING_DELAY = v end
})
local ui_QRetry = TabSettings:CreateSlider({
    Name = "Queue Retry",
    Range = {0.05, 1.0},
    Increment = 0.01,
    Suffix = " s",
    CurrentValue = CFG.QUEUE_RETRY_SECS,
    Flag = "CEE_QRetry",
    Callback = function(v) CFG.QUEUE_RETRY_SECS = v end
})
TabSettings:CreateParagraph({
    Title = "Visible Only",
    Content = "When ON, only streamed-in targets are hit and the radius slider is ignored."
})

-- =========== Remove/neutralize requested legacy toggles if they exist ===========
-- Try best-effort UI cleanup in CoreGui (does not touch your other tabs).
pcall(function()
    local cg = game:GetService("CoreGui")
    local rfRoot = cg:FindFirstChild("Rayfield"):FindFirstChildWhichIsA("ScreenGui", true)
    if rfRoot then
        for _, txt in ipairs({ "Auto Feed", "Auto Stun Deer" }) do
            for _, lab in ipairs(rfRoot:GetDescendants()) do
                if lab:IsA("TextLabel") and lab.Text == txt and lab.Parent and lab.Parent.Parent then
                    lab.Parent.Parent:Destroy() -- destroy the whole control container
                end
            end
        end
    end
end)

-- Done; all features active without altering your existing side tabs.
