-- Bring Test UI (non-moving drag/drop); includes two methods

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local LocalPlayer = Players.LocalPlayer

-- collision group for dragged items
local function ensureDragGroup()
    local g = "__DraggedItem__"
    pcall(function() PhysicsService:CreateCollisionGroup(g) end)
    PhysicsService:CollisionGroupSetCollidable(g, "Default", false)
    PhysicsService:CollisionGroupSetCollidable(g, g, false)
    return g
end
local DRAG_GROUP = ensureDragGroup()
local __origCollision = setmetatable({}, { __mode = "k" })

local function setItemNoClip(item, enabled)
    if not item or not item.Parent then return end
    for _, p in ipairs(item:GetDescendants()) do
        if p:IsA("BasePart") then
            if enabled then
                __origCollision[p] = { CanCollide = p.CanCollide, Group = p.CollisionGroup }
                p.CanCollide = false
                p.CollisionGroup = DRAG_GROUP
                p.Massless = true
                p.AssemblyLinearVelocity = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            else
                local o = __origCollision[p]
                if o then
                    p.CanCollide = o.CanCollide
                    p.CollisionGroup = o.Group
                    __origCollision[p] = nil
                else
                    p.CanCollide = true
                    p.CollisionGroup = "Default"
                end
                p.Massless = false
            end
        end
    end
end

local function tryStartDrag(item)
    return pcall(function()
        ReplicatedStorage:WaitForChild("RemoteEvents").RequestStartDraggingItem:FireServer(item)
    end)
end

local function stopDrag(item)
    pcall(function()
        ReplicatedStorage:WaitForChild("RemoteEvents").StopDraggingItem:FireServer(item)
    end)
end

local function getPartFor(item)
    if not item or not item.Parent then return nil end
    if item:IsA("Model") then
        local p = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
        if not item.PrimaryPart and p then pcall(function() item.PrimaryPart = p end) end
        return p
    elseif item:IsA("BasePart") then
        return item
    end
    return nil
end

local function findItemsByName(itemName, maxCount)
    local found, n = {}, 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if d.Name == itemName and (d:IsA("BasePart") or d:IsA("Model")) then
            local p = getPartFor(d)
            if p then
                n += 1
                found[#found+1] = { item = d, part = p }
                if maxCount and n >= maxCount then break end
            end
        end
    end
    return found
end

local function ringSlots(originCF, count, radius, yOffset)
    local slots, n = {}, math.max(1, count)
    local o = originCF.Position
    for i = 1, n do
        local t = (i - 1) / n * (math.pi * 2)
        slots[i] = CFrame.new(Vector3.new(o.X + math.cos(t)*radius, o.Y + (yOffset or 0), o.Z + math.sin(t)*radius))
    end
    return slots
end

local function placeAt(item, cf)
    local part = getPartFor(item)
    if not part then return end
    if item:IsA("Model") then
        item:SetPrimaryPartCFrame(cf)
    else
        part.CFrame = cf
    end
    part.AssemblyLinearVelocity = Vector3.new()
    part.AssemblyAngularVelocity = Vector3.new()
end

-- Method A: pure remote drag-at-distance (no visible movement; skips if server enforces range)
local function bring_NoMove(itemName, maxCount, radius, dropHeight, attachDelay)
    local player = LocalPlayer
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return 0 end
    local origin = hrp.CFrame
    local targets = findItemsByName(itemName, maxCount)
    if #targets == 0 then return 0 end
    local slots = ringSlots(origin, #targets, radius, dropHeight)
    local brought = 0
    for i, rec in ipairs(targets) do
        if not rec.item or not rec.item.Parent or not rec.part then continue end
        local ok = tryStartDrag(rec.item)
        if not ok then continue end
        setItemNoClip(rec.item, true)
        pcall(function()
            if rec.part.SetNetworkOwner then rec.part:SetNetworkOwner(player) end
            rec.part.Anchored = false
            rec.part.CanCollide = false
        end)
        task.wait(attachDelay)
        placeAt(rec.item, (slots[i] or origin))
        stopDrag(rec.item)
        setItemNoClip(rec.item, false)
        brought += 1
        task.wait(0.15)
    end
    return brought
end

-- Method B: instant attach-hop (teleports HRP to item and back within ~0.2s to satisfy range checks)
local function bring_AttachHop(itemName, maxCount, radius, dropHeight, attachDelay)
    local player = LocalPlayer
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return 0 end
    local origin = hrp.CFrame
    local targets = findItemsByName(itemName, maxCount)
    if #targets == 0 then return 0 end
    local slots = ringSlots(origin, #targets, radius, dropHeight)
    local brought = 0
    for i, rec in ipairs(targets) do
        if not rec.item or not rec.item.Parent or not rec.part then continue end
        local back = hrp.CFrame
        hrp.CFrame = rec.part.CFrame + Vector3.new(0, 2.5, 0)
        task.wait(0.05)
        local ok = tryStartDrag(rec.item)
        hrp.CFrame = back
        if not ok then continue end
        setItemNoClip(rec.item, true)
        pcall(function()
            if rec.part.SetNetworkOwner then rec.part:SetNetworkOwner(player) end
            rec.part.Anchored = false
            rec.part.CanCollide = false
        end)
        task.wait(attachDelay)
        placeAt(rec.item, (slots[i] or origin))
        stopDrag(rec.item)
        setItemNoClip(rec.item, false)
        brought += 1
        task.wait(0.15)
    end
    return brought
end

-- UI
if game.CoreGui:FindFirstChild("BringTestUI") then game.CoreGui.BringTestUI:Destroy() end
local gui = Instance.new("ScreenGui")
gui.Name = "BringTestUI"
gui.ResetOnSpawn = false
gui.Parent = game.CoreGui

local frame = Instance.new("Frame", gui)
frame.AnchorPoint = Vector2.new(1, 0)
frame.Position = UDim2.new(1, -20, 0, 20)
frame.Size = UDim2.new(0, 280, 0, 170)
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
frame.BorderSizePixel = 0
local corner = Instance.new("UICorner", frame) corner.CornerRadius = UDim.new(0, 10)

local uiList = Instance.new("UIListLayout", frame)
uiList.Padding = UDim.new(0, 6)
uiList.FillDirection = Enum.FillDirection.Vertical
uiList.HorizontalAlignment = Enum.HorizontalAlignment.Center
uiList.VerticalAlignment = Enum.VerticalAlignment.Top

local function mkLabel(txt)
    local l = Instance.new("TextLabel", frame)
    l.Size = UDim2.new(1, -20, 0, 20)
    l.Text = txt
    l.TextColor3 = Color3.fromRGB(220, 220, 230)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.GothamMedium
    l.TextSize = 14
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Position = UDim2.new(0, 10, 0, 0)
    return l
end

local function mkInput(defaultText)
    local b = Instance.new("TextBox", frame)
    b.Size = UDim2.new(1, -20, 0, 28)
    b.Position = UDim2.new(0, 10, 0, 0)
    b.Text = defaultText or ""
    b.PlaceholderText = defaultText or ""
    b.Font = Enum.Font.Gotham
    b.TextSize = 14
    b.TextColor3 = Color3.fromRGB(230, 230, 235)
    b.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
    b.BorderSizePixel = 0
    local c = Instance.new("UICorner", b) c.CornerRadius = UDim.new(0, 8)
    return b
end

local function mkButton(txt, cb)
    local btn = Instance.new("TextButton", frame)
    btn.Size = UDim2.new(1, -20, 0, 32)
    btn.Position = UDim2.new(0, 10, 0, 0)
    btn.Text = txt
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 14
    btn.TextColor3 = Color3.fromRGB(18, 18, 20)
    btn.BackgroundColor3 = Color3.fromRGB(120, 180, 255)
    btn.BorderSizePixel = 0
    local c = Instance.new("UICorner", btn) c.CornerRadius = UDim.new(0, 8)
    btn.MouseButton1Click:Connect(cb)
    return btn
end

mkLabel("Item Name")
local itemBox = mkInput("Log")

mkLabel("Max Count / Radius / Drop Y")
local row = Instance.new("Frame", frame)
row.Size = UDim2.new(1, -20, 0, 28)
row.Position = UDim2.new(0, 10, 0, 0)
row.BackgroundTransparency = 1
local rowList = Instance.new("UIListLayout", row)
rowList.FillDirection = Enum.FillDirection.Horizontal
rowList.Padding = UDim.new(0, 6)
rowList.HorizontalAlignment = Enum.HorizontalAlignment.Center

local countBox = Instance.new("TextBox", row)
countBox.Size = UDim2.new(0.33, -6, 1, 0)
countBox.Text = "10"
countBox.Font = Enum.Font.Gotham
countBox.TextSize = 14
countBox.TextColor3 = Color3.fromRGB(230, 230, 235)
countBox.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
countBox.BorderSizePixel = 0
Instance.new("UICorner", countBox).CornerRadius = UDim.new(0, 8)

local radiusBox = countBox:Clone()
radiusBox.Parent = row
radiusBox.Text = "6"

local dropBox = countBox:Clone()
dropBox.Parent = row
dropBox.Text = "3"

local status = mkLabel("Ready")

mkButton("Method A: No-Move Drag", function()
    local name = itemBox.Text ~= "" and itemBox.Text or "Log"
    local maxCount = tonumber(countBox.Text) or 10
    local radius = tonumber(radiusBox.Text) or 6
    local dropY = tonumber(dropBox.Text) or 3
    status.Text = "Running A..."
    local ok, brought = pcall(function()
        return bring_NoMove(name, maxCount, radius, dropY, 0.25)
    end)
    status.Text = ok and ("A done: "..brought) or ("A error")
end)

mkButton("Method B: Attach-Hop", function()
    local name = itemBox.Text ~= "" and itemBox.Text or "Log"
    local maxCount = tonumber(countBox.Text) or 10
    local radius = tonumber(radiusBox.Text) or 6
    local dropY = tonumber(dropBox.Text) or 3
    status.Text = "Running B..."
    local ok, brought = pcall(function()
        return bring_AttachHop(name, maxCount, radius, dropY, 0.2)
    end)
    status.Text = ok and ("B done: "..brought) or ("B error")
end)
