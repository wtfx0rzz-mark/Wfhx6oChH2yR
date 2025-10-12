-- 99 Nights – Full UI + Features (CeeGee)

-- libs / window
local Rayfield = getgenv().Rayfield or loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
getgenv().Rayfield = Rayfield

local Window = getgenv().__MainWindow
if not (Window and typeof(Window)=="table" and Window.CreateTab) then
    Window = Rayfield:CreateWindow({
        Name = "99 Nights – Utilities",
        LoadingTitle = "Initializing",
        LoadingSubtitle = "CeeGee",
        DisableRayfieldPrompts = true,
        ConfigurationSaving = { Enabled = false },
    })
    getgenv().__MainWindow = Window
end

-- tabs (create once; reuse if present)
local function getOrCreateTab(title, icon)
    if Window.Tabs then
        for _, t in ipairs(Window.Tabs) do
            if t.Name == title then return t end
        end
    end
    return Window:CreateTab(title, icon or 4483362458)
end

local TabCombat      = getOrCreateTab("Combat")
local TabMain        = getOrCreateTab("Main")
local TabEsp         = getOrCreateTab("Esp")
local TabBring       = getOrCreateTab("Bring")
local TabTeleport    = getOrCreateTab("Teleport")
local TabPlayer      = getOrCreateTab("Player")
local TabEnvironment = getOrCreateTab("Environment")

-- services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- small-comment tweakables
local CFG = getgenv().__CEE_CFG or {
    AURA_SWING_DELAY   = 0.45,   -- secs between kill-aura waves
    CHOP_SWING_DELAY   = 0.40,   -- secs between chop waves
    AURA_RADIUS        = 500,    -- studs when VisibleOnly=false
    QUEUE_RETRY_SECS   = 0.20,   -- secs between requeue checks
    QUEUE_MAX          = 400,    -- max queued targets held
    PRELOAD_NUDGE      = 6,      -- studs to ray-nudge for streaming
    HLINE_THICKNESS    = 0.08,   -- highlight line thickness
    HLINE_ZINDEX       = 10,     -- highlight draw order
    GOLD_SCAN_RATE     = 0.35,   -- secs between gold scans
    FEED_SCAN_RATE     = 0.60,   -- secs between feed checks
    SCRAPPER_PREF_RAD  = 35,     -- studs to prefer Scrapper movers
    CAMPFIRE_RAD       = 35,     -- studs for Campfire feed
}
getgenv().__CEE_CFG = CFG

-- state
local STATE = getgenv().__CEE_STATE or {
    KillAura      = false,
    ChopAura      = true,
    BigTrees      = false,
    VisibleOnly   = false,
    AggressivePre = false,
    HL_Trees      = false,
    HL_Animals    = false,
    AutoGold      = false,
}
getgenv().__CEE_STATE = STATE

local auraRadiusSliderValue = CFG.AURA_RADIUS

-- utils
local function HRP()
    local c = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return c:FindFirstChild("HumanoidRootPart")
end
local function dist(a,b) return (a-b).Magnitude end
local function now() return os.clock() end

-- world knowledge
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
    if m:FindFirstChildOfClass("Humanoid") and not m:FindFirstChild("PlayerGui") then return true end
    return false
end
local function hasTreeHealth(model)
    if model:GetAttribute("Health") then return true end
    local v = model:FindFirstChild("TreeHealth") or model:FindFirstChild("Health")
    return v and v:IsA("ValueBase") or false
end

-- highlights
local HFolder = Workspace:FindFirstChild("__AuraHighlights__") or (function()
    local f = Instance.new("Folder"); f.Name="__AuraHighlights__"; f.Parent=Workspace; return f
end)()
local activeBoxes = {}  -- [Instance]=SelectionBox
local function ensureBox(adorn)
    local sb = activeBoxes[adorn]
    if not sb then
        sb = Instance.new("SelectionBox")
        sb.Name="__AuraSB"
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
    for inst, box in pairs(activeBoxes) do if box then box:Destroy() end activeBoxes[inst]=nil end
end

-- requeue / streaming
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
            if pp and dist(centerPos, pp.Position) <= maxRange then keep[#keep+1]=q end
        end
    end
    table.clear(Requeue); for _,v in ipairs(keep) do Requeue[#Requeue+1]=v end
end
local function nudgeForStreaming(model)
    local pp = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not pp then return end
    local origin = pp.Position + Vector3.new(0,3,0)
    Workspace:Raycast(origin, Vector3.new(0,-CFG.PRELOAD_NUDGE,0))
end

-- remotes (best-effort)
local Remotes = getgenv().__CEE_REMOTES
if not Remotes then
    local R = ReplicatedStorage
    local function chain(...)
        local node = R
        for _,n in ipairs({...}) do node = node and node:FindFirstChild(n) end
        return node
    end
    Remotes = {
        ChopTree     = chain("Remotes","ChopTree")     or R:FindFirstChild("ChopTree"),
        HitEnemy     = chain("Remotes","HitEnemy")     or R:FindFirstChild("HitEnemy"),
        FeedCampfire = chain("Remotes","FeedCampfire") or R:FindFirstChild("FeedCampfire"),
        FeedScrapper = chain("Remotes","FeedScrapper") or R:FindFirstChild("FeedScrapper"),
        CollectCoin  = chain("Remotes","CollectCoin")  or R:FindFirstChild("CollectCoin"),
    }
    getgenv().__CEE_REMOTES = Remotes
end
local function serverChop(m)     if Remotes.ChopTree     and m then pcall(function() Remotes.ChopTree:FireServer(m) end) end end
local function serverHit(m)      if Remotes.HitEnemy     and m then pcall(function() Remotes.HitEnemy:FireServer(m) end) end end
local function serverCampfire(m) if Remotes.FeedCampfire and m then pcall(function() Remotes.FeedCampfire:FireServer(m) end) end end
local function serverScrapper(m) if Remotes.FeedScrapper and m then pcall(function() Remotes.FeedScrapper:FireServer(m) end) end end
local function serverCollect(m)
    if Remotes.CollectCoin and m then pcall(function() Remotes.CollectCoin:FireServer(m) end); return true end
    local prompt = m:FindFirstChildOfClass("ProximityPrompt") or m:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt and typeof(fireproximityprompt) == "function" then pcall(function() prompt.HoldDuration=0; fireproximityprompt(prompt) end); return true end
    return false
end

-- scanners
local function sweepTargets(centerPos, radius)
    local trees, animals = {}, {}
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("Model") then
            local pp = d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart")
            if pp and dist(centerPos, pp.Position) <= radius then
                if isTreeModel(d) and (STATE.BigTrees or not isBigTreeName(d.Name)) then
                    trees[#trees+1] = d
                elseif isAnimalModel(d) then
                    animals[#animals+1] = d
                end
            end
        end
    end
    return trees, animals
end
local function nearestByName(center, names, maxR)
    local best, bestD
    for _, m in ipairs(Workspace:GetDescendants()) do
        if m:IsA("Model") then
            for _, n in ipairs(names) do
                if m.Name == n then
                    local pp = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
                    if pp then
                        local d = dist(center, pp.Position)
                        if d <= maxR and (not bestD or d < bestD) then best, bestD = m, d end
                    end
                end
            end
        end
    end
    return best
end

-- stop old workers if present
if getgenv().__CEE_CHOP_THREAD then getgenv().__CEE_CHOP_THREAD:Disconnect(); getgenv().__CEE_CHOP_THREAD=nil end
if getgenv().__CEE_KILL_THREAD then getgenv().__CEE_KILL_THREAD:Disconnect(); getgenv().__CEE_KILL_THREAD=nil end
if getgenv().__CEE_FEED_THREAD then getgenv().__CEE_FEED_THREAD:Disconnect(); getgenv().__CEE_FEED_THREAD=nil end
if getgenv().__CEE_GOLD_THREAD then getgenv().__CEE_GOLD_THREAD:Disconnect(); getgenv().__CEE_GOLD_THREAD=nil end
if getgenv().__CEE_GOLD_CONN then getgenv().__CEE_GOLD_CONN:Disconnect(); getgenv().__CEE_GOLD_CONN=nil end

-- chop aura
getgenv().__CEE_CHOP_THREAD = RunService.Heartbeat:Connect(function()
    if not STATE.ChopAura then return end
    local root = HRP(); if not root then return end
    local center = root.Position
    local radius = STATE.VisibleOnly and 99999 or auraRadiusSliderValue

    local trees = ({sweepTargets(center, radius)})[1]

    if STATE.HL_Trees then
        for _, m in ipairs(trees) do
            local adorn = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
            if adorn then ensureBox(adorn) end
        end
    elseif next(activeBoxes) and not STATE.HL_Animals then
        clearHighlights()
    end

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

    if #Requeue > 0 then
        local lastQ = getgenv().__CEE_LAST_Q or 0
        if (now() - lastQ) >= CFG.QUEUE_RETRY_SECS then
            pruneQueue(center, STATE.ChopAura, radius)
            for i = #Requeue, 1, -1 do
                local q = Requeue[i]; local m = q.model
                if not m or not m.Parent then
                    table.remove(Requeue, i)
                else
                    if hasTreeHealth(m) then
                        serverChop(m)
                        table.remove(Requeue, i)
                    else
                        if STATE.AggressivePre then nudgeForStreaming(m) end
                    end
                end
            end
            getgenv().__CEE_LAST_Q = now()
        end
    end
end)

-- kill aura
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

-- feeder (prefers Scrapper movers over Campfire when both present)
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

-- gold collector
local function itemsFolder() return Workspace:FindFirstChild("Items") end
local function scanGold()
    local items = itemsFolder(); if not items then return end
    for _, ch in ipairs(items:GetChildren()) do
        if ch:IsA("Model") and ch.Name == "Coin Stack" then serverCollect(ch) end
    end
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
    if getgenv().__CEE_GOLD_CONN then getgenv().__CEE_GOLD_CONN:Disconnect(); getgenv().__CEE_GOLD_CONN=nil end
    if not enabled then return end
    local items = itemsFolder(); if not items then return end
    getgenv().__CEE_GOLD_CONN = items.ChildAdded:Connect(function(ch)
        if STATE.AutoGold and ch:IsA("Model") and ch.Name=="Coin Stack" then task.defer(serverCollect, ch) end
    end)
end

-- UI wiring (attach to specific tabs only; no new tabs)

-- Combat: auras + options
TabCombat:CreateToggle({ Name="Kill Aura", CurrentValue=STATE.KillAura, Flag="CEE_KillAura",
    Callback=function(v) STATE.KillAura=v end })
TabCombat:CreateToggle({ Name="Chop Aura", CurrentValue=STATE.ChopAura, Flag="CEE_ChopAura",
    Callback=function(v) STATE.ChopAura=v end })
TabCombat:CreateToggle({ Name="Big Trees", CurrentValue=STATE.BigTrees, Flag="CEE_BigTrees",
    Callback=function(v) STATE.BigTrees=v end })
TabCombat:CreateToggle({ Name="Visible Only (ignore radius)", CurrentValue=STATE.VisibleOnly, Flag="CEE_VisibleOnly",
    Callback=function(v) STATE.VisibleOnly=v end })
TabCombat:CreateToggle({ Name="Aggressive Preload (streaming nudge)", CurrentValue=STATE.AggressivePre, Flag="CEE_AggressivePre",
    Callback=function(v) STATE.AggressivePre=v end })

-- Main: highlights + gold
TabMain:CreateSection("Highlights")
TabMain:CreateToggle({ Name="Highlight Trees (Yellow)", CurrentValue=STATE.HL_Trees, Flag="CEE_HL_Trees",
    Callback=function(v) STATE.HL_Trees=v; if not v and not STATE.HL_Animals then clearHighlights() end end })
TabMain:CreateToggle({ Name="Highlight Animals (Yellow)", CurrentValue=STATE.HL_Animals, Flag="CEE_HL_Animals",
    Callback=function(v) STATE.HL_Animals=v; if not v and not STATE.HL_Trees then clearHighlights() end end })

TabMain:CreateSection("Gold")
TabMain:CreateToggle({ Name="Auto Collect Gold (Coin Stack)", CurrentValue=STATE.AutoGold, Flag="CEE_AutoGold",
    Callback=function(v) STATE.AutoGold=v; hookGold(v) end })

-- Main: aura sliders (since you didn't list a Settings tab)
TabMain:CreateSection("Aura Settings")
TabMain:CreateSlider({ Name="Aura Radius", Range={100,2000}, Increment=1, Suffix=" studs",
    CurrentValue=auraRadiusSliderValue, Flag="CEE_AuraRadius", Callback=function(v) auraRadiusSliderValue=v end })
TabMain:CreateSlider({ Name="Chop Wave Delay", Range={0.05,1.5}, Increment=0.01, Suffix=" s",
    CurrentValue=CFG.CHOP_SWING_DELAY, Flag="CEE_ChopDelay", Callback=function(v) CFG.CHOP_SWING_DELAY=v end })
TabMain:CreateSlider({ Name="Kill Wave Delay", Range={0.05,1.5}, Increment=0.01, Suffix=" s",
    CurrentValue=CFG.AURA_SWING_DELAY, Flag="CEE_KillDelay", Callback=function(v) CFG.AURA_SWING_DELAY=v end })
TabMain:CreateSlider({ Name="Queue Retry", Range={0.05,1.0}, Increment=0.01, Suffix=" s",
    CurrentValue=CFG.QUEUE_RETRY_SECS, Flag="CEE_QRetry", Callback=function(v) CFG.QUEUE_RETRY_SECS=v end })
TabMain:CreateParagraph({ Title="Visible Only", Content="When ON, only streamed-in targets are hit; the radius slider is ignored." })

-- Remove legacy toggles if they exist visually (best-effort)
pcall(function()
    local cg = game:GetService("CoreGui")
    local rfRoot = cg:FindFirstChild("Rayfield", true)
    if rfRoot then
        for _, kill in ipairs({ "Auto Feed", "Auto Stun Deer" }) do
            for _, n in ipairs(rfRoot:GetDescendants()) do
                if n:IsA("TextLabel") and n.Text == kill and n.Parent and n.Parent.Parent then
                    n.Parent.Parent:Destroy()
                end
            end
        end
    end
end)
