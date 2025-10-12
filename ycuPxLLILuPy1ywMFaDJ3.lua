--// 99 Nights in the Forest | WindUI-agnostic LocalScript (Debug tab included)
--// Implements: Reliability bundle (index+lazy revalidate, token guard, sticky targeting),
--//             LOS gate, equip arbitration w/ swap lock + cooldowns, concurrency cap,
--//             ring scheduling/caps, and Gold "tap" collection on Workspace.Items["Coin Stack"].
--// UI: Uses a minimal built-in Debug panel if no UI framework is available.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HRP = Character:WaitForChild("HumanoidRootPart")

--========================================================
-- CONFIG (ON/OFF & TIMING VARIABLES) – EDIT THESE QUICKLY
--========================================================

-- Master bundle: gates index+revalidate, token guard, sticky, equip locks, concurrency, LOS
local RELIABILITY_BUNDLE_ENABLED_DEFAULT = true    -- turn the entire reliability stack ON/OFF at once

-- Debug menu visibility
local DEBUG_MENU_ENABLED = true                    -- show the Debug side panel

-- Debug HUD (compact line with waves/concurrency/latency, etc.)
local DEBUG_HUD_ENABLED_DEFAULT = true             -- show the per-wave HUD line at top-left

-- LOS gate (raycast attacker->trunk before sending a hit)
local LOS_ENABLED_DEFAULT = true                   -- require line-of-sight per target at hit time

-- Workspace tree index (event-driven + lazy revalidation)
local INDEX_ENABLED_DEFAULT = true                 -- maintain a workspace tree index for mid/far selection

-- Token guard (checks N_0000000000-like children before hitting)
local TOKEN_GUARD_ENABLED_DEFAULT = true           -- enforce per-tree cap/cooldown by token pattern
local TOKEN_MAX_PER_BURST_DEFAULT = 3              -- max tokens allowed on a tree before we skip this wave
local TOKEN_COOLDOWN_MS_DEFAULT = 450              -- ms since newest token before allowing another hit
local TOKEN_FAIL_BACKOFF_MS_DEFAULT = 600          -- ms cooldown on server refusal/invalid state
local TOKEN_CACHE_TTL_MS_DEFAULT = 700             -- ms to trust cached token count before re-read
local TOKEN_MAX_DEPTH_DEFAULT = 2                  -- 1=children only, 2=shallow descendants

-- Sticky targeting (stay on same tree until destroyed or early-release)
local STICKY_ENABLED_DEFAULT = true                -- keep hitting the same target while valid
local STICKY_TTL_MS_DEFAULT = 2000                 -- ms to try staying on the same tree
local STICKY_MAX_SKIPS_DEFAULT = 2                 -- consecutive token/LOS skips before dropping sticky
local STICKY_CONSEC_FAILS_DEFAULT = 2              -- consecutive server refuses/LOS fails before drop
local STICKY_RING_GRACE_MS_DEFAULT = 600           -- ms we allow sticky to continue after target crosses ring

-- Equip arbitration (Chainsaw priority, swap-lock and cooldowns)
local CHAINSAW_PRIORITY_DEFAULT = true             -- if Chainsaw exists, always use for trees; silent fail on fuel
local LOCK_TO_CHOP_ENABLED_DEFAULT = false         -- resist switching away from Chop tools during lock window
local SWAP_LOCK_MS_DEFAULT = 1200                  -- ms to resist switching tools away from Chop after an equip
local EQUIP_COOLDOWN_MS_DEFAULT = 600              -- ms cooldown after successful equip (avoid thrash)
local EQUIP_FAIL_COOLDOWN_MS_DEFAULT = 250         -- ms cooldown after failed equip (short backoff)
local CHAINSAW_USABLE_TTL_MS_DEFAULT = 7000        -- ms to suppress Chainsaw attempts after refusal (fuel empty)

-- Concurrency cap (global InvokeServer token limit + short wait)
local CONCURRENCY_CAP_ENABLED_DEFAULT = true       -- enable token bucket limiting for RPCs
local RPC_MAX_TOKENS_DEFAULT = 12                  -- max concurrent invoke tokens
local RPC_TOKEN_WAIT_MS_DEFAULT = 150              -- ms we are willing to wait for a token before skipping

-- Ring scheduling (Near/Mid/Far wave intervals & per-wave caps)
local RING_NEAR_DELAY_MS_DEFAULT = 550             -- ms between Near ring waves (match Axe cooldown)
local RING_MID_DELAY_MS_DEFAULT  = 1000            -- ms between Mid ring waves
local RING_FAR_DELAY_MS_DEFAULT  = 1800            -- ms between Far ring waves
local RING_JITTER_MS_DEFAULT     = 100             -- ±ms jitter added to each ring delay
local RING_CAP_NEAR_DEFAULT      = 8               -- max targets per Near wave
local RING_CAP_MID_DEFAULT       = 4               -- max targets per Mid wave
local RING_CAP_FAR_DEFAULT       = 2               -- max targets per Far wave

-- Aura radius and ring multipliers
local AURA_RADIUS_DEFAULT        = 100             -- studs; Near radius R
local RING_MID_MULTIPLIER        = 2.0             -- Mid ring distance upper bound = R * 2.0
local RING_FAR_MULTIPLIER        = 3.0             -- Far ring distance upper bound = R * 3.0

-- Chainsaw and Axe selection
local AXE_ORDER = { "Old Axe", "Axe", "Strong Axe" }  -- worst -> best; only used if Chainsaw not present

-- Gold collection (tap-only) under Workspace.Items["Coin Stack"]
local GOLD_COLLECT_ENABLED_DEFAULT = true          -- enable gold collector
local GOLD_COLLECT_PULSE_MS_DEFAULT = 300          -- ms frequency to scan & tap coin stacks
local GOLD_COLLECT_RADIUS_DEFAULT   = 30           -- studs; only tap within this distance
local GOLD_CONTAINER_NAME           = "Items"      -- parent under Workspace
local GOLD_ITEM_NAME                = "Coin Stack" -- exact item name to collect

--========================================================
-- RUNTIME STATE (do not edit)
--========================================================
local function nowMs() return math.floor(os.clock() * 1000) end

local cfg = {
    RELIABILITY = RELIABILITY_BUNDLE_ENABLED_DEFAULT,
    DEBUG_HUD   = DEBUG_HUD_ENABLED_DEFAULT,

    LOS         = LOS_ENABLED_DEFAULT,
    INDEX       = INDEX_ENABLED_DEFAULT,

    TOKEN_GUARD = TOKEN_GUARD_ENABLED_DEFAULT,
    TOKEN_MAX   = TOKEN_MAX_PER_BURST_DEFAULT,
    TOKEN_COOL  = TOKEN_COOLDOWN_MS_DEFAULT,
    TOKEN_BACK  = TOKEN_FAIL_BACKOFF_MS_DEFAULT,
    TOKEN_TTL   = TOKEN_CACHE_TTL_MS_DEFAULT,
    TOKEN_DEPTH = TOKEN_MAX_DEPTH_DEFAULT,

    STICKY      = STICKY_ENABLED_DEFAULT,
    STICKY_TTL  = STICKY_TTL_MS_DEFAULT,
    STICKY_SKIPS= STICKY_MAX_SKIPS_DEFAULT,
    STICKY_FAILS= STICKY_CONSEC_FAILS_DEFAULT,
    STICKY_GRACE= STICKY_RING_GRACE_MS_DEFAULT,

    CHAINSAW_PRIORITY = CHAINSAW_PRIORITY_DEFAULT,
    LOCK_TO_CHOP      = LOCK_TO_CHOP_ENABLED_DEFAULT,
    SWAP_LOCK_MS      = SWAP_LOCK_MS_DEFAULT,
    EQUIP_CD_MS       = EQUIP_COOLDOWN_MS_DEFAULT,
    EQUIP_FAIL_MS     = EQUIP_FAIL_COOLDOWN_MS_DEFAULT,
    CHAINSAW_TTL_MS   = CHAINSAW_USABLE_TTL_MS_DEFAULT,

    CONCURRENCY       = CONCURRENCY_CAP_ENABLED_DEFAULT,
    RPC_MAX_TOKENS    = RPC_MAX_TOKENS_DEFAULT,
    RPC_WAIT_MS       = RPC_TOKEN_WAIT_MS_DEFAULT,

    NEAR_MS   = RING_NEAR_DELAY_MS_DEFAULT,
    MID_MS    = RING_MID_DELAY_MS_DEFAULT,
    FAR_MS    = RING_FAR_DELAY_MS_DEFAULT,
    JITTER_MS = RING_JITTER_MS_DEFAULT,
    CAP_NEAR  = RING_CAP_NEAR_DEFAULT,
    CAP_MID   = RING_CAP_MID_DEFAULT,
    CAP_FAR   = RING_CAP_FAR_DEFAULT,

    RADIUS    = AURA_RADIUS_DEFAULT,
    MID_MULT  = RING_MID_MULTIPLIER,
    FAR_MULT  = RING_FAR_MULTIPLIER,

    GOLD      = GOLD_COLLECT_ENABLED_DEFAULT,
    GOLD_MS   = GOLD_COLLECT_PULSE_MS_DEFAULT,
    GOLD_R    = GOLD_COLLECT_RADIUS_DEFAULT,
}

local rpcTokens = {
    max = cfg.RPC_MAX_TOKENS,
    used = 0,
    queue = {},
}

local function takeToken()
    if not cfg.RELIABILITY or not cfg.CONCURRENCY then return true end
    if rpcTokens.used < rpcTokens.max then
        rpcTokens.used += 1
        return true
    end
    return false
end

local function releaseToken()
    if not cfg.RELIABILITY or not cfg.CONCURRENCY then return end
    rpcTokens.used = math.max(0, rpcTokens.used - 1)
end

local function waitForToken(timeoutMs)
    if not cfg.RELIABILITY or not cfg.CONCURRENCY then return true end
    local deadline = nowMs() + (timeoutMs or 0)
    while rpcTokens.used >= rpcTokens.max and nowMs() < deadline do
        RunService.Heartbeat:Wait()
    end
    return takeToken()
end

local function dist2(a, b) return (a - b).Magnitude^2 end

--========================================================
-- TREE INDEX + TOKEN GUARD + STICKY
--========================================================
local TreeIndex = {
    -- [Instance] = { model=Instance, trunk=BasePart, isBig=bool, lastSeen=ms, cooldownUntil=ms,
    --                token = { when=ms, count=int, newest=ms }, sticky={ owner="NEAR/MID/FAR", since=ms, skips=0, fails=0 } }
}
local TREE_NAMES = { -- you can expand via whitelist/blacklist if desired
    ["Small Tree"] = true,
    ["TreeBig1"] = true, ["TreeBig2"] = true, ["TreeBig3"] = true,
}

local function isTreeModel(m)
    if not m or not m:IsA("Model") then return false end
    return TREE_NAMES[m.Name] == true
end

local function findTrunk(model)
    if not model or not model:IsA("Model") then return nil end
    if model:FindFirstChild("Trunk") and model.Trunk:IsA("BasePart") then return model.Trunk end
    if model.PrimaryPart then return model.PrimaryPart end
    for _,c in ipairs(model:GetChildren()) do
        if c:IsA("BasePart") then return c end
    end
    return nil
end

local function evictTree(m)
    TreeIndex[m] = nil
end

local function upsertTree(m)
    if not isTreeModel(m) then return end
    local trunk = findTrunk(m)
    if not trunk then return end
    local t = TreeIndex[m]
    if not t then
        TreeIndex[m] = {
            model = m,
            trunk = trunk,
            isBig = string.find(m.Name, "TreeBig", 1, true) ~= nil,
            lastSeen = nowMs(),
            cooldownUntil = 0,
            token = { when = 0, count = 0, newest = 0 },
            sticky = nil,
        }
    else
        t.trunk = trunk
        t.lastSeen = nowMs()
    end
end

local function buildInitialIndex()
    if not cfg.RELIABILITY or not cfg.INDEX then return end
    for _,inst in ipairs(workspace:GetDescendants()) do
        if isTreeModel(inst) then
            upsertTree(inst)
        end
    end
end

local function hookIndexSignals()
    if not cfg.RELIABILITY or not cfg.INDEX then return end
    workspace.DescendantAdded:Connect(function(inst)
        if isTreeModel(inst) then upsertTree(inst) end
    end)
    workspace.DescendantRemoving:Connect(function(inst)
        if TreeIndex[inst] then evictTree(inst) end
    end)
end

local TOKEN_PATTERN = "^(%d+)_(%d%d%d%d%d%d%d%d%d%d)$"

local function readTokens(model, maxDepth, earlyStopAt)
    local count, newest = 0, 0
    local function check(inst)
        if count >= earlyStopAt then return true end
        local name = inst.Name
        local a,b = string.match(name, TOKEN_PATTERN)
        if a and b then
            count += 1
            local ts = tonumber(b) or 0
            if ts > newest then newest = ts end
            if count >= earlyStopAt then return true end
        end
        return false
    end
    for _,c in ipairs(model:GetChildren()) do
        if check(c) then return count, newest end
    end
    if maxDepth >= 2 then
        for _,d in ipairs(model:GetDescendants()) do
            if check(d) then return count, newest end
        end
    end
    return count, newest
end

local function tokenGuardPass(trec)
    if not cfg.RELIABILITY or not cfg.TOKEN_GUARD then return true end
    local now = nowMs()
    if trec.cooldownUntil and now < trec.cooldownUntil then return false end

    if (now - trec.token.when) > cfg.TOKEN_TTL then
        local c, newest = readTokens(trec.model, cfg.TOKEN_DEPTH, cfg.TOKEN_MAX)
        trec.token.when   = now
        trec.token.count  = c
        trec.token.newest = newest
    end

    if trec.token.count >= cfg.TOKEN_MAX then
        trec.cooldownUntil = now + cfg.TOKEN_COOL
        return false
    end
    if trec.token.newest > 0 and (now - trec.token.newest) < cfg.TOKEN_COOL then
        trec.cooldownUntil = now + cfg.TOKEN_COOL
        return false
    end
    return true
end

local function losPass(origin, targetPart)
    if not cfg.RELIABILITY or not cfg.LOS then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = { Character }
    local result = workspace:Raycast(origin, (targetPart.Position - origin).Unit * (HRP.Position - targetPart.Position).Magnitude, params)
    if not result then return true end
    return result.Instance:IsDescendantOf(targetPart.Parent) -- true if we hit the tree itself
end

--========================================================
-- EQUIP ARBITRATION
--========================================================
local lastEquipAt = 0
local lastEquipFailAt = 0
local swapLockUntil = 0
local chainsawSuppressedUntil = 0

local function hasTool(name)
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local function find(container)
        if not container then return nil end
        for _,t in ipairs(container:GetChildren()) do
            if t:IsA("Tool") and t.Name == name then return t end
        end
    end
    return find(Character) or find(backpack)
end

local function bestAxe()
    for i = #AXE_ORDER, 1, -1 do
        local t = hasTool(AXE_ORDER[i])
        if t then return t end
    end
    return nil
end

local function chainsawTool()
    return hasTool("Chainsaw")
end

local function toolEquipped(name)
    local tool = Character:FindFirstChildOfClass("Tool")
    return tool and tool.Name == name
end

local function ensureChopTool()
    local now = nowMs()
    if cfg.RELIABILITY and cfg.LOCK_TO_CHOP and now < swapLockUntil then
        return true
    end
    if cfg.RELIABILITY and (now - lastEquipAt) < cfg.EQUIP_CD_MS then
        return toolEquipped("Chainsaw") or toolEquipped("Strong Axe") or toolEquipped("Axe") or toolEquipped("Old Axe")
    end
    if cfg.RELIABILITY and (now - lastEquipFailAt) < cfg.EQUIP_FAIL_MS then
        return toolEquipped("Chainsaw") or toolEquipped("Strong Axe") or toolEquipped("Axe") or toolEquipped("Old Axe")
    end

    local targetTool = nil
    if cfg.CHAINSAW_PRIORITY and now >= chainsawSuppressedUntil then
        targetTool = chainsawTool()
    end
    if not targetTool then
        targetTool = bestAxe()
    end
    if not targetTool then
        lastEquipFailAt = nowMs()
        return false
    end

    if targetTool.Parent ~= Character then
        targetTool.Parent = Character
    end

    lastEquipAt = nowMs()
    if cfg.RELIABILITY and cfg.LOCK_TO_CHOP then
        swapLockUntil = lastEquipAt + cfg.SWAP_LOCK_MS
    end
    return true
end

local function demoteChainsawTTL()
    chainsawSuppressedUntil = nowMs() + cfg.CHAINSAW_TTL_MS
end

--========================================================
-- RPC SEMAPHORE (PLACEHOLDER) & HIT SENDER
--========================================================
-- Replace these with the game’s actual remote invoke logic:
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage
local HitRemote = Remotes:FindFirstChild("ChopTree") or Remotes:FindFirstChild("DealTreeDamage")

local function sendHit(trec)
    if not HitRemote then return false, "no_remote" end
    -- example payload; adapt to your actual server contract
    local ok, err = pcall(function()
        HitRemote:InvokeServer(trec.model, trec.trunk.CFrame)
    end)
    if not ok then
        return false, tostring(err or "invoke_failed")
    end
    return true
end

--========================================================
-- RING SCHEDULERS
--========================================================
local STICKY = {
    NEAR = { target=nil, since=0, skips=0, fails=0 },
    MID  = { target=nil, since=0, skips=0, fails=0 },
    FAR  = { target=nil, since=0, skips=0, fails=0 },
}

local function ringBounds()
    local R = cfg.RADIUS
    return R, R*cfg.MID_MULT, R*cfg.FAR_MULT
end

local function ringForDist2(d2)
    local R, M, F = ringBounds()
    local R2, M2, F2 = R*R, M*M, F*F
    if d2 <= R2 then return "NEAR" end
    if d2 <= M2 then return "MID" end
    if d2 <= F2 then return "FAR" end
    return nil
end

local function selectCandidates(cap, ringName)
    local pos = HRP.Position
    local R, M, F = ringBounds()
    local near2, mid2, far2 = R*R, M*M, F*F

    local list = {}
    for m, t in pairs(TreeIndex) do
        if m and m.Parent and t.trunk and t.trunk.Parent then
            local d2 = dist2(pos, t.trunk.Position)
            if (ringName == "NEAR" and d2 <= near2)
            or (ringName == "MID"  and d2 > near2 and d2 <= mid2)
            or (ringName == "FAR"  and d2 > mid2  and d2 <= far2) then
                table.insert(list, t)
            end
        end
    end
    table.sort(list, function(a,b)
        return (a.trunk.Position - pos).Magnitude < (b.trunk.Position - pos).Magnitude
    end)
    if #list > cap then
        while #list > cap do table.remove(list) end
    end
    return list
end

local function ringSticky(ring)
    return STICKY[ring]
end

local function withinRing(trec, ring)
    local d2 = dist2(HRP.Position, trec.trunk.Position)
    local R, M, F = ringBounds()
    if ring == "NEAR" then return d2 <= R*R end
    if ring == "MID"  then return d2 > R*R  and d2 <= M*M end
    if ring == "FAR"  then return d2 > M*M  and d2 <= F*F end
    return false
end

local function tryHitOne(trec, ring)
    if not cfg.RELIABILITY then
        if not takeToken() then return false end
        local ok, err = sendHit(trec)
        releaseToken()
        return ok
    end

    local now = nowMs()
    if cfg.TOKEN_GUARD and not tokenGuardPass(trec) then
        local s = ringSticky(ring)
        if s.target == trec then s.skips += 1 end
        return false
    end

    if cfg.LOS and not losPass(HRP.Position, trec.trunk) then
        local s = ringSticky(ring)
        if s.target == trec then s.fails += 1 end
        return false
    end

    if not ensureChopTool() then
        return false
    end

    if cfg.CONCURRENCY then
        if not waitForToken(cfg.RPC_WAIT_MS) then
            return false
        end
    end

    local ok, err = sendHit(trec)
    if cfg.CONCURRENCY then releaseToken() end

    if not ok then
        if err and string.find(err, "fuel", 1, true) then
            demoteChainsawTTL()
        end
        trec.cooldownUntil = now + cfg.TOKEN_BACK
        local s = ringSticky(ring)
        if s.target == trec then s.fails += 1 end
        return false
    else
        -- optimistic token cache invalidate for freshness
        trec.token.when = 0
        return true
    end
end

local function updateStickyOwnership(ring, candidates)
    local s = ringSticky(ring)
    local now = nowMs()

    if s.target and (not s.target.model or not s.target.model.Parent) then
        s.target, s.since, s.skips, s.fails = nil, 0, 0, 0
    end

    if s.target then
        if not withinRing(s.target, ring) then
            if (now - s.since) > cfg.STICKY_GRACE then
                s.target, s.since, s.skips, s.fails = nil, 0, 0, 0
            end
        end
        if cfg.STICKY and (now - s.since) > cfg.STICKY_TTL then
            s.target, s.since, s.skips, s.fails = nil, 0, 0, 0
        end
        if s.skips >= cfg.STICKY_SKIPS or s.fails >= cfg.STICKY_FAILS then
            s.target, s.since, s.skips, s.fails = nil, 0, 0, 0
        end
    end

    if not s.target and #candidates > 0 then
        s.target = candidates[1]
        s.since, s.skips, s.fails = now, 0, 0
    end
end

local WaveStats = { near=0, mid=0, far=0, conc=0, max=cfg.RPC_MAX_TOKENS, rtt=0, skips=0, losSkips=0 }

local function ringWave(ring, cap)
    local candidates = selectCandidates(cap, ring)
    updateStickyOwnership(ring, candidates)

    local s = ringSticky(ring)
    local sent = 0
    if s.target then
        if tryHitOne(s.target, ring) then
            sent += 1
        end
    end

    for _,trec in ipairs(candidates) do
        if sent >= cap then break end
        if s.target ~= trec then
            if tryHitOne(trec, ring) then
                sent += 1
            end
        end
    end

    if ring == "NEAR" then WaveStats.near = sent
    elseif ring == "MID" then WaveStats.mid = sent
    else WaveStats.far = sent end
    WaveStats.conc = rpcTokens.used
    WaveStats.max  = rpcTokens.max
end

--========================================================
-- GOLD COLLECTION (TAP ONLY)
--========================================================
local CoinSet = {}  -- [Instance]=true

local function hookGold()
    if not cfg.GOLD then return end
    local container = workspace:WaitForChild(GOLD_CONTAINER_NAME, 10)
    if not container then return end
    local function tryAdd(inst)
        if inst.Name == GOLD_ITEM_NAME then
            CoinSet[inst] = true
            inst.AncestryChanged:Connect(function(_, parent)
                if not parent then CoinSet[inst] = nil end
            end)
        end
    end
    for _,c in ipairs(container:GetChildren()) do tryAdd(c) end
    container.ChildAdded:Connect(tryAdd)
    container.ChildRemoved:Connect(function(c) CoinSet[c] = nil end)
end

local function tapCoin(inst)
    local cd = inst:FindFirstChildOfClass("ClickDetector")
    if cd then
        pcall(function() fireclickdetector(cd) end)
        return true
    end
    -- If the game uses a remote for pickup instead of ClickDetector, add it here when known.
    return false
end

local function goldLoop()
    while task.wait(cfg.GOLD and (cfg.GOLD_MS/1000) or 1) do
        if not cfg.GOLD then continue end
        for inst,_ in pairs(CoinSet) do
            if inst and inst.Parent then
                local d2 = dist2(HRP.Position, inst:GetPivot().Position)
                if d2 <= (cfg.GOLD_R * cfg.GOLD_R) then
                    tapCoin(inst)
                end
            else
                CoinSet[inst] = nil
            end
        end
    end
end

--========================================================
-- DEBUG UI (MINIMAL PANEL)
--========================================================
local DebugGui, DebugLabel

local function makeDebugUI()
    if not DEBUG_MENU_ENABLED then return end

    local gui = Instance.new("ScreenGui")
    gui.Name = "__DebugPanel__"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    DebugGui = gui

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(1, 0.5)
    panel.Position = UDim2.new(1, -12, 0.5, 0)
    panel.Size = UDim2.new(0, 260, 0, 370)
    panel.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
    panel.BackgroundTransparency = 0.1
    panel.BorderSizePixel = 0
    panel.Parent = gui

    local ui = Instance.new("UIListLayout")
    ui.Padding = UDim.new(0, 6)
    ui.FillDirection = Enum.FillDirection.Vertical
    ui.HorizontalAlignment = Enum.HorizontalAlignment.Center
    ui.VerticalAlignment = Enum.VerticalAlignment.Top
    ui.Parent = panel

    local function mkToggle(text, getter, setter)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -16, 0, 28)
        btn.Text = ""
        btn.BackgroundColor3 = Color3.fromRGB(30,30,36)
        btn.AutoButtonColor = true
        btn.Parent = panel

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -80, 1, 0)
        lbl.Position = UDim2.new(0, 10, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextColor3 = Color3.fromRGB(220,220,230)
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 14
        lbl.Text = text
        lbl.Parent = btn

        local state = Instance.new("TextLabel")
        state.Size = UDim2.new(0, 52, 0, 20)
        state.Position = UDim2.new(1, -62, 0.5, -10)
        state.BackgroundColor3 = Color3.fromRGB(50,50,56)
        state.TextColor3 = Color3.fromRGB(255,255,255)
        state.Font = Enum.Font.Code
        state.TextSize = 13
        state.Text = getter() and "ON" or "OFF"
        state.Parent = btn

        btn.MouseButton1Click:Connect(function()
            local newVal = not getter()
            setter(newVal)
            state.Text = newVal and "ON" or "OFF"
        end)
    end

    local function mkTextbox(label, getter, setter, width)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, -16, 0, 28)
        frame.BackgroundColor3 = Color3.fromRGB(30,30,36)
        frame.Parent = panel

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -90, 1, 0)
        lbl.Position = UDim2.new(0, 10, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextColor3 = Color3.fromRGB(220,220,230)
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 14
        lbl.Text = label
        lbl.Parent = frame

        local tb = Instance.new("TextBox")
        tb.Size = UDim2.new(0, width or 60, 0, 22)
        tb.Position = UDim2.new(1, -(width or 60) - 10, 0.5, -11)
        tb.BackgroundColor3 = Color3.fromRGB(50,50,56)
        tb.TextColor3 = Color3.fromRGB(255,255,255)
        tb.Font = Enum.Font.Code
        tb.TextSize = 14
        tb.Text = tostring(getter())
        tb.Parent = frame

        tb.FocusLost:Connect(function(enter)
            local v = tonumber(tb.Text)
            if v and v > 0 then setter(v) else tb.Text = tostring(getter()) end
        end)
    end

    mkToggle("Reliability Bundle", function() return cfg.RELIABILITY end, function(v) cfg.RELIABILITY=v end)
    mkToggle("LOS Gate",          function() return cfg.LOS end,         function(v) cfg.LOS=v end)
    mkToggle("Tree Index",        function() return cfg.INDEX end,       function(v) cfg.INDEX=v end)
    mkToggle("Token Guard",       function() return cfg.TOKEN_GUARD end, function(v) cfg.TOKEN_GUARD=v end)
    mkToggle("Sticky Targeting",  function() return cfg.STICKY end,      function(v) cfg.STICKY=v end)
    mkToggle("Lock to Chop",      function() return cfg.LOCK_TO_CHOP end,function(v) cfg.LOCK_TO_CHOP=v end)
    mkToggle("Chainsaw Priority", function() return cfg.CHAINSAW_PRIORITY end, function(v) cfg.CHAINSAW_PRIORITY=v end)
    mkToggle("Concurrency Cap",   function() return cfg.CONCURRENCY end, function(v) cfg.CONCURRENCY=v end)
    mkToggle("Debug HUD",         function() return cfg.DEBUG_HUD end,   function(v) cfg.DEBUG_HUD=v end)

    mkTextbox("Max Tokens", function() return cfg.RPC_MAX_TOKENS end, function(v)
        cfg.RPC_MAX_TOKENS = math.floor(v)
        rpcTokens.max = cfg.RPC_MAX_TOKENS
    end, 70)

    local hud = Instance.new("TextLabel")
    hud.Name = "HUD"
    hud.Position = UDim2.new(0, 12, 0, 12)
    hud.Size = UDim2.new(0, 460, 0, 20)
    hud.BackgroundTransparency = 1
    hud.TextXAlignment = Enum.TextXAlignment.Left
    hud.TextColor3 = Color3.fromRGB(235,235,240)
    hud.Font = Enum.Font.Code
    hud.TextSize = 14
    hud.Text = ""
    hud.Parent = gui
    DebugLabel = hud
end

local function updateHUD()
    if not DebugLabel then return end
    if not cfg.DEBUG_HUD then DebugLabel.Text = "" return end
    DebugLabel.Text = string.format(
        "Waves N/M/F: %d/%d/%d  | Concurrency: %d/%d",
        WaveStats.near, WaveStats.mid, WaveStats.far, WaveStats.conc, WaveStats.max
    )
end

--========================================================
-- MAIN LOOPS
--========================================================
local function jitter(ms)
    local j = cfg.JITTER_MS
    if j <= 0 then return ms end
    local r = (math.random() * 2 - 1) * j
    return math.max(10, ms + r)
end

local function scheduler(ms, fn)
    while task.wait(ms/1000) do
        fn()
    end
end

local function nearLoop()
    while task.wait(jitter(cfg.NEAR_MS)/1000) do
        ringWave("NEAR", cfg.CAP_NEAR)
        updateHUD()
    end
end

local function midLoop()
    while task.wait(jitter(cfg.MID_MS)/1000) do
        ringWave("MID", cfg.CAP_MID)
        updateHUD()
    end
end

local function farLoop()
    while task.wait(jitter(cfg.FAR_MS)/1000) do
        ringWave("FAR", cfg.CAP_FAR)
        updateHUD()
    end
end

--========================================================
-- BOOTSTRAP
--========================================================
task.spawn(function()
    buildInitialIndex()
    hookIndexSignals()
    makeDebugUI()
    hookGold()
    task.spawn(goldLoop)
    task.spawn(nearLoop)
    task.spawn(midLoop)
    task.spawn(farLoop)
end)
