--[[
    LRN MM2 ULTIMATE V6 - SURVIVAL & ROLE KIT
    Modern UI / Mobile Friendly / Safer Cleanup

    Main features:
    - Survival awareness alert for nearby players in line of sight
    - Coin Route Assistant: marks one nearby, visible coin only
    - No auto movement / no teleport / no wall clipping for coin guidance
    - Optional practice crosshair
    - Manual practice timer (not tied to the game's actual cooldown)
    - Sheriff / Murderer / Innocent strategy tips
    - Own-role status card, using only role data available to the local client
    - Mobile-friendly UI, clean unload, and restore helpers
    - Legacy auto-aim, hitbox, noclip, and auto-farm controls retired from the UI
]]

--==============================================================
-- Compatibility helpers
--==============================================================
local function safeCall(fn, ...)
    local args = table.pack(...)
    local ok, a, b, c = pcall(function()
        return fn(table.unpack(args, 1, args.n))
    end)
    if ok then
        return true, a, b, c
    end
    return false, a
end

local function wrapCClosure(fn)
    if typeof(newcclosure) == "function" then
        return newcclosure(fn)
    end
    return fn
end

local function isCaller()
    if typeof(checkcaller) == "function" then
        local ok, result = pcall(checkcaller)
        return ok and result or false
    end
    return false
end

--==============================================================
-- Services
--==============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

--==============================================================
-- Global cleanup / rerun guard
--==============================================================
local GlobalEnv = (getgenv and getgenv()) or _G

if GlobalEnv.LRN_MM2_ULTIMATE and GlobalEnv.LRN_MM2_ULTIMATE.Unload then
    pcall(GlobalEnv.LRN_MM2_ULTIMATE.Unload)
end

local API = {}
GlobalEnv.LRN_MM2_ULTIMATE = API

--==============================================================
-- State / caches
--==============================================================
local State = {
    MenuOpen = true,
    CurrentTab = "Visuals",
    IsUnloaded = false,

    RoleESP = false,
    RoleAlerts = false,
    GunESP = false,
    TrapESP = false,
    Tracers = false,
    ProximityRadar = true,
    CoinRouteAssist = false,
    PracticeCrosshair = false,
    PracticeTimerRunning = false,
    PracticeTimerUntil = 0,
    AutoAim = false,
    AutoAimSmooth = 0.28,
    AimFOV = 260,
    AimPrediction = 0.08,
    HitboxExpander = false,
    HitboxSize = 8,

    AutoFarm = false,
    Noclip = false,
    WalkSpeed = 16,
    JumpPower = 50,

    FullBright = false,
    AutoScaleUI = true,
}

local Connections = {}
local Cache = {
    ESP = {},
    GunESP = nil,
    TrapESP = {},
    Tracers = {},
    OriginalParts = setmetatable({}, { __mode = "k" }),
    Role = {},
    RoleStamp = {},
    RoleAnnounced = {},
}

local OriginalLighting = {
    Ambient = Lighting.Ambient,
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd,
    GlobalShadows = Lighting.GlobalShadows,
    OutdoorAmbient = Lighting.OutdoorAmbient,
}

local RoleColors = {
    Murderer = Color3.fromRGB(255, 70, 85),
    Sheriff  = Color3.fromRGB(75, 160, 255),
    Hero     = Color3.fromRGB(255, 205, 75),
    Innocent = Color3.fromRGB(75, 220, 145),
    GunDrop  = Color3.fromRGB(255, 220, 75),
    Trap     = Color3.fromRGB(255, 140, 70),
    Unknown  = Color3.fromRGB(170, 178, 195),
}

local UI = {}
local currentFarmTween = nil
local PlayerConnections = {}
local OriginalCharacterCollision = setmetatable({}, { __mode = "k" })
local ProximityAlertFrame = nil
local lastTrapScan = 0
local ProximityAlertLabel = nil
local StatusRoleLabel = nil
local StatusInfoLabel = nil
local updateProximity, updateCoinRouteAssist, clearCoinRouteMarker
local showRoleTips, startPracticeTimer, updateStatusUI

local HasDrawing = (typeof(Drawing) == "table" and typeof(Drawing.new) == "function")

--==============================================================
-- Small utility helpers
--==============================================================
local function disconnect(name)
    local conn = Connections[name]
    if conn and typeof(conn) == "RBXScriptConnection" then
        pcall(function() conn:Disconnect() end)
    end
    Connections[name] = nil
end

local function disconnectAll()
    for name, conn in pairs(Connections) do
        if typeof(conn) == "RBXScriptConnection" then
            pcall(function() conn:Disconnect() end)
        end
        Connections[name] = nil
    end
end

local function tween(instance, info, props)
    if not instance or not instance.Parent then
        return
    end
    local ok, tw = pcall(function()
        local obj = TweenService:Create(instance, info, props)
        obj:Play()
        return obj
    end)
    return ok and tw or nil
end

local function addConnection(key, connection)
    if Connections[key] then
        pcall(function() Connections[key]:Disconnect() end)
    end
    Connections[key] = connection
end

local function getCharacter(plr)
    return plr and plr.Character
end

local function getRoot(char)
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(char)
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function isAlive(plr)
    local char = getCharacter(plr)
    local hum = getHumanoid(char)
    return char ~= nil and hum ~= nil and hum.Health > 0
end

local function notify(message, accent)
    if not UI.ToastHolder or not UI.ToastHolder.Parent then
        return
    end

    accent = accent or Color3.fromRGB(95, 165, 255)

    local toast = Instance.new("Frame")
    toast.Size = UDim2.new(0, 250, 0, 42)
    toast.BackgroundColor3 = Color3.fromRGB(20, 22, 31)
    toast.BackgroundTransparency = 0.02
    toast.BorderSizePixel = 0
    toast.LayoutOrder = -os.clock()
    toast.Parent = UI.ToastHolder

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = toast

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(48, 53, 72)
    stroke.Thickness = 1
    stroke.Parent = toast

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 3, 1, -16)
    bar.Position = UDim2.new(0, 8, 0, 8)
    bar.BackgroundColor3 = accent
    bar.BorderSizePixel = 0
    bar.Parent = toast

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(1, 0)
    barCorner.Parent = bar

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -30, 1, -4)
    label.Position = UDim2.new(0, 20, 0, 2)
    label.BackgroundTransparency = 1
    label.Text = tostring(message)
    label.TextColor3 = Color3.fromRGB(235, 240, 250)
    label.TextSize = 11
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = toast

    toast.Position = UDim2.new(1, 16, 0, 0)
    tween(toast, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Position = UDim2.new(0, 0, 0, 0)
    })

    task.delay(2.25, function()
        if toast and toast.Parent then
            local out = tween(toast, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
                Position = UDim2.new(1, 16, 0, 0)
            })
            if out then
                out.Completed:Wait()
            end
            if toast and toast.Parent then
                toast:Destroy()
            end
        end
    end)
end

--==============================================================
-- Role scanner
--==============================================================
local function classifyRoleString(value)
    if typeof(value) ~= "string" then
        return nil
    end

    local name = value:lower()
    if name:find("murder") or name:find("killer") then
        return "Murderer"
    end
    if name:find("sheriff") or name:find("hero") or name:find("gun") then
        return name:find("hero") and "Hero" or "Sheriff"
    end
    if name:find("innocent") or name:find("civilian") then
        return "Innocent"
    end
    return nil
end

local function readRoleAttributes(plr)
    local attrs = { "Role", "RoleName", "PlayerRole", "TeamRole" }
    for _, attr in ipairs(attrs) do
        local ok, value = pcall(function() return plr:GetAttribute(attr) end)
        if ok then
            local role = classifyRoleString(value)
            if role then
                return role
            end
        end
    end

    local char = plr.Character
    if char then
        for _, attr in ipairs(attrs) do
            local ok, value = pcall(function() return char:GetAttribute(attr) end)
            if ok then
                local role = classifyRoleString(value)
                if role then
                    return role
                end
            end
        end
    end

    return nil
end

local function cacheRole(plr, role, stamp)
    Cache.Role[plr] = role
    Cache.RoleStamp[plr] = stamp

    -- Alerts only fire when the client actually exposes a role signal.
    -- Unknown is deliberately not treated as Innocent.
    if State.RoleAlerts and (role == "Murderer" or role == "Sheriff" or role == "Hero")
        and Cache.RoleAnnounced[plr] ~= role then
        Cache.RoleAnnounced[plr] = role
        local isSelf = plr == LocalPlayer
        local playerName = isSelf and "YOU" or (plr.DisplayName or plr.Name)
        local message
        if isSelf then
            message = "YOUR ROLE  •  " .. role:upper()
        else
            message = "ROLE FOUND  •  " .. role:upper() .. "  •  " .. playerName
        end
        notify(message, RoleColors[role])
    end

    return role
end

local function getRole(plr, force)
    if not plr then
        return "Unknown"
    end

    local stamp = os.clock()
    if not force and Cache.Role[plr] and Cache.RoleStamp[plr]
        and stamp - Cache.RoleStamp[plr] < 0.35 then
        return Cache.Role[plr]
    end

    local direct = readRoleAttributes(plr)
    if direct then
        return cacheRole(plr, direct, stamp)
    end

    local char = plr.Character
    local backpack = plr:FindFirstChildOfClass("Backpack")
    local toolNames = {}

    local function scan(container)
        if not container then return end
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") then
                table.insert(toolNames, item.Name:lower())
            end
        end
    end

    scan(backpack)
    scan(char)

    for _, name in ipairs(toolNames) do
        if name:find("knife") or name:find("blade") or name:find("slash") or name:find("dagger") then
            return cacheRole(plr, "Murderer", stamp)
        end
    end

    for _, name in ipairs(toolNames) do
        if name:find("gun") or name:find("revolver") or name:find("pistol") or name:find("sheriff") then
            return cacheRole(plr, "Sheriff", stamp)
        end
    end

    return cacheRole(plr, "Unknown", stamp)
end

local function getMurdererPlayer()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and isAlive(plr) and getRole(plr) == "Murderer" then
            return plr
        end
    end
    return nil
end

--==============================================================
-- Sheriff auto-aim (camera based; mobile friendly)
--==============================================================
local function getEquippedGun()
    local char = LocalPlayer.Character
    if not char then return nil end

    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Tool") then
            local name = item.Name:lower()
            if name:find("gun") or name:find("revolver") or name:find("pistol") or name:find("sheriff") then
                return item
            end
        end
    end
    return nil
end

local function getAimPart(plr)
    local char = plr and plr.Character
    if not char then return nil end
    return char:FindFirstChild("Head")
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("HumanoidRootPart")
end

local function getBestSheriffTarget()
    if not Camera then return nil end
    local murderer = getMurdererPlayer()
    if not murderer then return nil end

    local part = getAimPart(murderer)
    if not part then return nil end

    local targetPos = part.Position
    local root = getRoot(murderer.Character)
    if root then
        local velocity = root.AssemblyLinearVelocity
        targetPos = targetPos + velocity * State.AimPrediction
    end

    local screenPos, onScreen = Camera:WorldToViewportPoint(targetPos)
    if not onScreen or screenPos.Z <= 0 then
        return nil
    end

    local center = Vector2.new(Camera.ViewportSize.X * 0.5, Camera.ViewportSize.Y * 0.5)
    local distanceFromCenter = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
    if distanceFromCenter > State.AimFOV then
        return nil
    end

    return targetPos, murderer
end

local function updateAutoAim()
    if State.IsUnloaded or not State.AutoAim then return end
    if not getEquippedGun() then return end

    local targetPos = getBestSheriffTarget()
    if not targetPos then return end

    local camPos = Camera.CFrame.Position
    local desired = CFrame.lookAt(camPos, targetPos)
    local alpha = math.clamp(State.AutoAimSmooth, 0.05, 1)
    Camera.CFrame = Camera.CFrame:Lerp(desired, alpha)
end

--==============================================================
-- ESP
--==============================================================
local function removePlayerESP(plr)
    local data = Cache.ESP[plr]
    if not data then return end
    for _, inst in pairs(data) do
        if typeof(inst) == "Instance" and inst.Parent then
            pcall(function() inst:Destroy() end)
        end
    end
    Cache.ESP[plr] = nil
end

local function createPlayerESP(plr)
    if plr == LocalPlayer or State.IsUnloaded or not State.RoleESP then return end

    local char = plr.Character
    if not char then return end

    removePlayerESP(plr)

    local role = getRole(plr)
    local color = RoleColors[role] or RoleColors.Unknown

    local highlight = Instance.new("Highlight")
    highlight.Name = "LRN3_PlayerHighlight"
    highlight.FillColor = color
    highlight.OutlineColor = color:Lerp(Color3.new(1, 1, 1), 0.65)
    highlight.FillTransparency = 0.55
    highlight.OutlineTransparency = 0.08
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Adornee = char
    highlight.Parent = char

    local root = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
    if not root then
        highlight:Destroy()
        return
    end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "LRN3_PlayerTag"
    billboard.Size = UDim2.new(0, 160, 0, 42)
    billboard.StudsOffset = Vector3.new(0, 3.1, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 1800
    billboard.Adornee = root
    billboard.Parent = char

    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 1, 0)
    holder.BackgroundTransparency = 1
    holder.Parent = billboard

    local roleText = Instance.new("TextLabel")
    roleText.Size = UDim2.new(1, 0, 0, 18)
    roleText.Position = UDim2.new(0, 0, 0, 0)
    roleText.BackgroundTransparency = 1
    roleText.Text = role:upper()
    roleText.TextColor3 = color
    roleText.TextStrokeTransparency = 0.45
    roleText.Font = Enum.Font.GothamBold
    roleText.TextSize = 11
    roleText.Parent = holder

    local nameText = Instance.new("TextLabel")
    nameText.Size = UDim2.new(1, 0, 0, 18)
    nameText.Position = UDim2.new(0, 0, 0, 17)
    nameText.BackgroundTransparency = 1
    nameText.Text = plr.DisplayName or plr.Name
    nameText.TextColor3 = Color3.fromRGB(242, 245, 252)
    nameText.TextStrokeTransparency = 0.45
    nameText.Font = Enum.Font.GothamMedium
    nameText.TextSize = 10
    nameText.Parent = holder

    Cache.ESP[plr] = {
        Highlight = highlight,
        Billboard = billboard,
        RoleText = roleText,
        NameText = nameText,
    }
end

local function clearAllESP()
    for plr in pairs(Cache.ESP) do
        removePlayerESP(plr)
    end
end

--==============================================================
-- Gun / Trap ESP
--==============================================================
local function destroyCacheList(list)
    if not list then return end
    for _, obj in pairs(list) do
        if typeof(obj) == "Instance" and obj.Parent then
            pcall(function() obj:Destroy() end)
        end
    end
end

local function clearGunESP()
    if Cache.GunESP then
        destroyCacheList(Cache.GunESP)
        Cache.GunESP = nil
    end
end

local function findGunDropPart()
    local direct = Workspace:FindFirstChild("GunDrop", true)
    if direct then
        if direct:IsA("BasePart") then
            return direct
        elseif direct:IsA("Model") then
            return direct.PrimaryPart or direct:FindFirstChildWhichIsA("BasePart")
        end
    end

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name:lower():find("gundrop") then
            return obj
        end
    end

    return nil
end

local function updateGunDropESP()
    if State.IsUnloaded or not State.GunESP then
        clearGunESP()
        return
    end

    local gun = findGunDropPart()
    if not gun or not gun.Parent then
        clearGunESP()
        return
    end

    if Cache.GunESP and Cache.GunESP.Part == gun and Cache.GunESP.Billboard and Cache.GunESP.Billboard.Parent then
        local myRoot = getRoot(LocalPlayer.Character)
        local distance = myRoot and math.floor((myRoot.Position - gun.Position).Magnitude) or 0
        if Cache.GunESP.Label then
            Cache.GunESP.Label.Text = string.format("GUN DROP  •  %d studs", distance)
        end
        return
    end

    clearGunESP()

    local highlight = Instance.new("Highlight")
    highlight.Name = "LRN3_GunHighlight"
    highlight.FillColor = RoleColors.GunDrop
    highlight.OutlineColor = Color3.fromRGB(255, 240, 170)
    highlight.FillTransparency = 0.24
    highlight.OutlineTransparency = 0.08
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Adornee = gun
    highlight.Parent = gun

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "LRN3_GunTag"
    billboard.Size = UDim2.new(0, 170, 0, 24)
    billboard.StudsOffset = Vector3.new(0, 2.4, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = gun
    billboard.Parent = gun

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "GUN DROP"
    label.TextColor3 = RoleColors.GunDrop
    label.TextStrokeTransparency = 0.35
    label.Font = Enum.Font.GothamBold
    label.TextSize = 11
    label.Parent = billboard

    Cache.GunESP = {
        Highlight = highlight,
        Billboard = billboard,
        Label = label,
        Part = gun,
    }
end

local function clearTrapESP()
    for obj, data in pairs(Cache.TrapESP) do
        destroyCacheList(data)
        Cache.TrapESP[obj] = nil
    end
end

local function updateTrapESP(force)
    if State.IsUnloaded or not State.TrapESP then
        clearTrapESP()
        return
    end

    if not force and os.clock() - lastTrapScan < 1.0 then
        return
    end
    lastTrapScan = os.clock()

    local seen = {}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            local name = obj.Name:lower()
            if name:find("trap") or name:find("mine") then
                seen[obj] = true
                if not Cache.TrapESP[obj] then
                    local highlight = Instance.new("Highlight")
                    highlight.Name = "LRN3_TrapHighlight"
                    highlight.FillColor = RoleColors.Trap
                    highlight.OutlineColor = Color3.fromRGB(255, 220, 190)
                    highlight.FillTransparency = 0.5
                    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    highlight.Adornee = obj
                    highlight.Parent = obj

                    local billboard = Instance.new("BillboardGui")
                    billboard.Name = "LRN3_TrapTag"
                    billboard.Size = UDim2.new(0, 110, 0, 20)
                    billboard.StudsOffset = Vector3.new(0, 1.5, 0)
                    billboard.AlwaysOnTop = true
                    billboard.Adornee = obj
                    billboard.Parent = obj

                    local label = Instance.new("TextLabel")
                    label.Size = UDim2.new(1, 0, 1, 0)
                    label.BackgroundTransparency = 1
                    label.Text = "TRAP"
                    label.TextColor3 = RoleColors.Trap
                    label.TextStrokeTransparency = 0.35
                    label.Font = Enum.Font.GothamBold
                    label.TextSize = 10
                    label.Parent = billboard

                    Cache.TrapESP[obj] = { highlight, billboard, label }
                end
            end
        end
    end

    for obj, data in pairs(Cache.TrapESP) do
        if not seen[obj] or not obj.Parent then
            destroyCacheList(data)
            Cache.TrapESP[obj] = nil
        end
    end
end

--==============================================================
-- Tracers
--==============================================================
local function clearTracers()
    for plr, line in pairs(Cache.Tracers) do
        pcall(function()
            line.Visible = false
            line:Remove()
        end)
        Cache.Tracers[plr] = nil
    end
end

local function renderTracers()
    if State.IsUnloaded or not State.Tracers or not HasDrawing then
        if next(Cache.Tracers) then
            clearTracers()
        end
        return
    end

    Camera = Workspace.CurrentCamera or Camera
    if not Camera then return end

    local from = Vector2.new(Camera.ViewportSize.X * 0.5, Camera.ViewportSize.Y - 5)
    local alivePlayers = {}

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and isAlive(plr) then
            local role = getRole(plr)
            if role == "Murderer" or role == "Sheriff" or role == "Hero" then
                local root = getRoot(plr.Character)
                if root then
                    alivePlayers[plr] = true
                    local point, visible = Camera:WorldToViewportPoint(root.Position)
                    local line = Cache.Tracers[plr]

                    if not line then
                        local ok, obj = pcall(function()
                            return Drawing.new("Line")
                        end)
                        if ok and obj then
                            obj.Thickness = 1.4
                            obj.Transparency = 0.9
                            line = obj
                            Cache.Tracers[plr] = line
                        end
                    end

                    if line then
                        line.From = from
                        line.To = Vector2.new(point.X, point.Y)
                        line.Color = RoleColors[role] or Color3.new(1, 1, 1)
                        line.Visible = visible
                    end
                end
            end
        end
    end

    for plr, line in pairs(Cache.Tracers) do
        if not alivePlayers[plr] then
            pcall(function()
                line.Visible = false
                line:Remove()
            end)
            Cache.Tracers[plr] = nil
        end
    end
end

--==============================================================
-- Hitbox manager (stores original properties)
--==============================================================
local function cachePart(part)
    if not part or Cache.OriginalParts[part] then
        return
    end

    Cache.OriginalParts[part] = {
        Size = part.Size,
        Transparency = part.Transparency,
        Color = part.Color,
        Material = part.Material,
        CanCollide = part.CanCollide,
    }
end

local function applyHitbox(plr)
    if State.IsUnloaded or not State.HitboxExpander or plr == LocalPlayer then
        return
    end

    local char = plr.Character
    if not char then return end

    local role = getRole(plr)
    local color = RoleColors[role] or RoleColors.Unknown
    local parts = {
        char:FindFirstChild("HumanoidRootPart"),
        char:FindFirstChild("UpperTorso"),
        char:FindFirstChild("Torso"),
        char:FindFirstChild("Head"),
    }

    for _, part in ipairs(parts) do
        if part and part:IsA("BasePart") then
            cachePart(part)
            part.Size = Vector3.new(State.HitboxSize, State.HitboxSize, State.HitboxSize)
            part.Transparency = (part.Name == "HumanoidRootPart") and 0.68 or 0.78
            part.Color = color
            part.Material = Enum.Material.ForceField
            part.CanCollide = false
            pcall(function() part.CanQuery = true end)
        end
    end
end

local function restorePart(part)
    local original = Cache.OriginalParts[part]
    if not original then return end
    if not part or not part.Parent then return end

    pcall(function()
        part.Size = original.Size
        part.Transparency = original.Transparency
        part.Color = original.Color
        part.Material = original.Material
        part.CanCollide = original.CanCollide
    end)

    Cache.OriginalParts[part] = nil
end

local function resetAllHitboxes()
    for part in pairs(Cache.OriginalParts) do
        restorePart(part)
    end
end

--==============================================================
-- Local collision manager
--==============================================================
local function setLocalCollision(enabled)
    local char = LocalPlayer.Character
    if not char then return end

    if enabled then
        for part, original in pairs(OriginalCharacterCollision) do
            if part and part.Parent == char then
                pcall(function() part.CanCollide = original end)
            end
            OriginalCharacterCollision[part] = nil
        end
        return
    end

    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            if OriginalCharacterCollision[part] == nil then
                OriginalCharacterCollision[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end
end

--==============================================================
-- Movement
--==============================================================
local function updateWalkSpeed()
    local hum = getHumanoid(LocalPlayer.Character)
    if hum then
        hum.WalkSpeed = State.WalkSpeed
    end
end

local function updateJumpPower()
    local hum = getHumanoid(LocalPlayer.Character)
    if hum then
        hum.UseJumpPower = true
        hum.JumpPower = State.JumpPower
    end
end

local function restoreMovement()
    State.WalkSpeed = 16
    State.JumpPower = 50
    updateWalkSpeed()
    updateJumpPower()
end

--==============================================================
-- Farming
--==============================================================
local function stopFarmTween()
    if currentFarmTween then
        pcall(function() currentFarmTween:Cancel() end)
        currentFarmTween = nil
    end
end

local function getTargetCoins()
    local coins = {}
    local root = Workspace:FindFirstChild("CoinContainer", true)
        or Workspace:FindFirstChild("Normal", true)
        or Workspace

    for _, obj in ipairs(root:GetDescendants()) do
        if obj:IsA("BasePart") then
            local n = obj.Name:lower()
            if n:find("coin") and obj.Transparency < 1 then
                table.insert(coins, obj)
            end
        end
    end

    table.sort(coins, function(a, b)
        local myRoot = getRoot(LocalPlayer.Character)
        if not myRoot then return false end
        return (a.Position - myRoot.Position).Magnitude < (b.Position - myRoot.Position).Magnitude
    end)

    return coins
end

local function teleportToGun()
    local gun = findGunDropPart()
    local root = getRoot(LocalPlayer.Character)
    if not gun or not root then
        notify("Gun drop belum ketemu.", RoleColors.GunDrop)
        return
    end

    root.CFrame = gun.CFrame + Vector3.new(0, 3, 0)
    notify("Teleported ke gun drop.", RoleColors.GunDrop)
end

local function goToSky()
    local root = getRoot(LocalPlayer.Character)
    if root then
        root.CFrame = root.CFrame + Vector3.new(0, 100, 0)
        notify("Dipindahkan ke safe spot udara.", Color3.fromRGB(130, 175, 255))
    end
end

local function runFarmStep()
    if not State.AutoFarm or State.IsUnloaded then
        return
    end

    local root = getRoot(LocalPlayer.Character)
    if not root then return end

    local coins = getTargetCoins()
    for _, coin in ipairs(coins) do
        if not State.AutoFarm or State.IsUnloaded then
            break
        end
        if coin and coin.Parent and coin:IsDescendantOf(Workspace) then
            root = getRoot(LocalPlayer.Character)
            if not root then break end

            local distance = (root.Position - coin.Position).Magnitude
            local speed = 24
            local duration = math.clamp(distance / speed, 0.10, 3.25)

            root.AssemblyLinearVelocity = Vector3.zero
            currentFarmTween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
                CFrame = coin.CFrame + Vector3.new(0, 1.25, 0)
            })
            currentFarmTween:Play()

            local ok = pcall(function()
                currentFarmTween.Completed:Wait()
            end)
            if not ok then break end
            task.wait(0.08)
        end
    end
end

--==============================================================
-- Lighting
--==============================================================
local function setFullBright(enabled)
    State.FullBright = enabled
    if enabled then
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        Lighting.Brightness = 2.2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 100000
        Lighting.GlobalShadows = false
    else
        Lighting.Ambient = OriginalLighting.Ambient
        Lighting.OutdoorAmbient = OriginalLighting.OutdoorAmbient
        Lighting.Brightness = OriginalLighting.Brightness
        Lighting.ClockTime = OriginalLighting.ClockTime
        Lighting.FogEnd = OriginalLighting.FogEnd
        Lighting.GlobalShadows = OriginalLighting.GlobalShadows
    end
end

--==============================================================
-- UI creation helpers
--==============================================================
local uiHost = nil
if typeof(gethui) == "function" then
    local ok, result = pcall(gethui)
    if ok and result then uiHost = result end
end
uiHost = uiHost or CoreGui
if not uiHost then
    uiHost = LocalPlayer:WaitForChild("PlayerGui")
end

for _, oldName in ipairs({ "LRN_MM2_ULTIMATE_V4", "LRN_MM2_ULTIMATE_V5", "LRN_MM2_ULTIMATE_V6" }) do
    local oldGui = uiHost:FindFirstChild(oldName)
    if oldGui then
        pcall(function() oldGui:Destroy() end)
    end
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "LRN_MM2_ULTIMATE_V6"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent = uiHost
UI.ScreenGui = ScreenGui

local UIScale = Instance.new("UIScale")
UIScale.Scale = 1
UIScale.Parent = ScreenGui
UI.UIScale = UIScale

local ToastHolder = Instance.new("Frame")
ToastHolder.Name = "ToastHolder"
ToastHolder.Size = UDim2.new(0, 250, 0, 220)
ToastHolder.Position = UDim2.new(1, -266, 0, 72)
ToastHolder.BackgroundTransparency = 1
ToastHolder.Parent = ScreenGui
UI.ToastHolder = ToastHolder

local toastLayout = Instance.new("UIListLayout")
toastLayout.FillDirection = Enum.FillDirection.Vertical
toastLayout.VerticalAlignment = Enum.VerticalAlignment.Top
toastLayout.Padding = UDim.new(0, 6)
toastLayout.Parent = ToastHolder

-- Proximity alert
local alert = Instance.new("Frame")
alert.Name = "LRN3_ProximityAlert"
alert.Size = UDim2.new(0, 270, 0, 38)
alert.Position = UDim2.new(0.5, -135, 0, 12)
alert.BackgroundColor3 = Color3.fromRGB(36, 20, 26)
alert.BackgroundTransparency = 0.05
alert.BorderSizePixel = 0
alert.Visible = false
alert.ZIndex = 90
alert.Parent = ScreenGui

local alertCorner = Instance.new("UICorner")
alertCorner.CornerRadius = UDim.new(0, 12)
alertCorner.Parent = alert

local alertStroke = Instance.new("UIStroke")
alertStroke.Color = Color3.fromRGB(255, 90, 105)
alertStroke.Thickness = 1.25
alertStroke.Transparency = 0.2
alertStroke.Parent = alert

local alertLabel = Instance.new("TextLabel")
alertLabel.Size = UDim2.new(1, -20, 1, 0)
alertLabel.Position = UDim2.new(0, 10, 0, 0)
alertLabel.BackgroundTransparency = 1
alertLabel.Text = "MURDERER NEARBY"
alertLabel.TextColor3 = Color3.fromRGB(255, 235, 240)
alertLabel.TextSize = 12
alertLabel.Font = Enum.Font.GothamBold
alertLabel.ZIndex = 91
alertLabel.Parent = alert
ProximityAlertFrame = alert
ProximityAlertLabel = alertLabel

-- Optional center crosshair for manual aim practice (no target locking).
local CrosshairLabel = Instance.new("TextLabel")
CrosshairLabel.Name = "PracticeCrosshair"
CrosshairLabel.Size = UDim2.new(0, 28, 0, 28)
CrosshairLabel.Position = UDim2.new(0.5, -14, 0.5, -14)
CrosshairLabel.BackgroundTransparency = 1
CrosshairLabel.Text = "+"
CrosshairLabel.TextColor3 = Color3.fromRGB(245, 248, 255)
CrosshairLabel.TextStrokeTransparency = 0.25
CrosshairLabel.TextSize = 20
CrosshairLabel.Font = Enum.Font.GothamBold
CrosshairLabel.Visible = false
CrosshairLabel.ZIndex = 120
CrosshairLabel.Parent = ScreenGui

local PracticeTimerLabel = Instance.new("TextLabel")
PracticeTimerLabel.Name = "PracticeTimerLabel"
PracticeTimerLabel.Size = UDim2.new(0, 190, 0, 24)
PracticeTimerLabel.Position = UDim2.new(0.5, -95, 1, -72)
PracticeTimerLabel.BackgroundColor3 = Color3.fromRGB(19, 22, 31)
PracticeTimerLabel.BackgroundTransparency = 0.08
PracticeTimerLabel.BorderSizePixel = 0
PracticeTimerLabel.Text = "PRACTICE TIMER"
PracticeTimerLabel.TextColor3 = Color3.fromRGB(230, 236, 248)
PracticeTimerLabel.TextSize = 10
PracticeTimerLabel.Font = Enum.Font.GothamBold
PracticeTimerLabel.Visible = false
PracticeTimerLabel.ZIndex = 120
PracticeTimerLabel.Parent = ScreenGui
local PracticeTimerCorner = Instance.new("UICorner")
PracticeTimerCorner.CornerRadius = UDim.new(0, 8)
PracticeTimerCorner.Parent = PracticeTimerLabel

-- Floating pill
local Pill = Instance.new("TextButton")
Pill.Name = "MenuPill"
Pill.Size = UDim2.new(0, 52, 0, 52)
Pill.Position = UDim2.new(0, 16, 0.42, 0)
Pill.BackgroundColor3 = Color3.fromRGB(17, 19, 28)
Pill.BorderSizePixel = 0
Pill.AutoButtonColor = false
Pill.Text = "LRN"
Pill.TextColor3 = Color3.fromRGB(112, 182, 255)
Pill.TextSize = 13
Pill.Font = Enum.Font.GothamBold
Pill.ZIndex = 110
Pill.Parent = ScreenGui
UI.Pill = Pill

local pillCorner = Instance.new("UICorner")
pillCorner.CornerRadius = UDim.new(1, 0)
pillCorner.Parent = Pill

local pillStroke = Instance.new("UIStroke")
pillStroke.Color = Color3.fromRGB(83, 155, 255)
pillStroke.Thickness = 1.5
pillStroke.Transparency = 0.1
pillStroke.Parent = Pill

local pillDot = Instance.new("Frame")
pillDot.Size = UDim2.new(0, 6, 0, 6)
pillDot.Position = UDim2.new(1, -11, 0, 8)
pillDot.BackgroundColor3 = Color3.fromRGB(78, 230, 150)
pillDot.BorderSizePixel = 0
pillDot.ZIndex = 111
pillDot.Parent = Pill

local pillDotCorner = Instance.new("UICorner")
pillDotCorner.CornerRadius = UDim.new(1, 0)
pillDotCorner.Parent = pillDot

-- Main window
local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 320, 0, 365)
Main.Position = UDim2.new(0.5, -160, 0.5, -182)
Main.BackgroundColor3 = Color3.fromRGB(13, 15, 22)
Main.BorderSizePixel = 0
Main.Active = true
Main.Visible = true
Main.ZIndex = 70
Main.Parent = ScreenGui
UI.Main = Main

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 16)
mainCorner.Parent = Main

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(40, 45, 62)
mainStroke.Thickness = 1.2
mainStroke.Transparency = 0.1
mainStroke.Parent = Main

local shadow = Instance.new("ImageLabel")
shadow.Name = "Shadow"
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Position = UDim2.new(0.5, 0, 0.5, 8)
shadow.Size = UDim2.new(1, 30, 1, 30)
shadow.BackgroundTransparency = 1
shadow.Image = "rbxassetid://6014261993"
shadow.ImageTransparency = 0.7
shadow.ScaleType = Enum.ScaleType.Slice
shadow.SliceCenter = Rect.new(49, 49, 450, 450)
shadow.ZIndex = 69
shadow.Parent = Main

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 64)
Header.BackgroundColor3 = Color3.fromRGB(19, 22, 32)
Header.BorderSizePixel = 0
Header.ZIndex = 71
Header.Parent = Main

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 16)
headerCorner.Parent = Header

local Accent = Instance.new("Frame")
Accent.Size = UDim2.new(0, 3, 0, 38)
Accent.Position = UDim2.new(0, 14, 0, 17)
Accent.BackgroundColor3 = Color3.fromRGB(95, 165, 255)
Accent.BorderSizePixel = 0
Accent.ZIndex = 72
Accent.Parent = Header

local accentCorner = Instance.new("UICorner")
accentCorner.CornerRadius = UDim.new(1, 0)
accentCorner.Parent = Accent

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -112, 0, 22)
Title.Position = UDim2.new(0, 26, 0, 14)
Title.BackgroundTransparency = 1
Title.Text = "LRN  /  MM2 ULTIMATE"
Title.TextColor3 = Color3.fromRGB(245, 247, 252)
Title.TextSize = 15
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.ZIndex = 72
Title.Parent = Header

local Subtitle = Instance.new("TextLabel")
Subtitle.Size = UDim2.new(1, -112, 0, 18)
Subtitle.Position = UDim2.new(0, 26, 0, 38)
Subtitle.BackgroundTransparency = 1
Subtitle.Text = "clean • responsive • executor friendly"
Subtitle.TextColor3 = Color3.fromRGB(125, 134, 154)
Subtitle.TextSize = 9
Subtitle.Font = Enum.Font.GothamMedium
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.ZIndex = 72
Subtitle.Parent = Header

local HeaderDot = Instance.new("Frame")
HeaderDot.Size = UDim2.new(0, 7, 0, 7)
HeaderDot.Position = UDim2.new(1, -82, 0, 18)
HeaderDot.BackgroundColor3 = Color3.fromRGB(80, 228, 150)
HeaderDot.BorderSizePixel = 0
HeaderDot.ZIndex = 72
HeaderDot.Parent = Header

local headerDotCorner = Instance.new("UICorner")
headerDotCorner.CornerRadius = UDim.new(1, 0)
headerDotCorner.Parent = HeaderDot

local HeaderState = Instance.new("TextLabel")
HeaderState.Size = UDim2.new(0, 58, 0, 16)
HeaderState.Position = UDim2.new(1, -69, 0, 13)
HeaderState.BackgroundTransparency = 1
HeaderState.Text = "READY"
HeaderState.TextColor3 = Color3.fromRGB(150, 230, 185)
HeaderState.TextSize = 8
HeaderState.Font = Enum.Font.GothamBold
HeaderState.TextXAlignment = Enum.TextXAlignment.Right
HeaderState.ZIndex = 72
HeaderState.Parent = Header

local Close = Instance.new("TextButton")
Close.Size = UDim2.new(0, 28, 0, 28)
Close.Position = UDim2.new(1, -40, 1, -39)
Close.AnchorPoint = Vector2.new(0, 0)
Close.BackgroundColor3 = Color3.fromRGB(31, 34, 47)
Close.BorderSizePixel = 0
Close.Text = "×"
Close.TextColor3 = Color3.fromRGB(190, 198, 214)
Close.TextSize = 16
Close.Font = Enum.Font.GothamMedium
Close.AutoButtonColor = false
Close.ZIndex = 72
Close.Parent = Main

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = Close

-- Status card
local StatusCard = Instance.new("Frame")
StatusCard.Size = UDim2.new(1, -24, 0, 54)
StatusCard.Position = UDim2.new(0, 12, 0, 74)
StatusCard.BackgroundColor3 = Color3.fromRGB(18, 21, 31)
StatusCard.BorderSizePixel = 0
StatusCard.ZIndex = 71
StatusCard.Parent = Main

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 11)
statusCorner.Parent = StatusCard

local statusStroke = Instance.new("UIStroke")
statusStroke.Color = Color3.fromRGB(38, 43, 60)
statusStroke.Thickness = 1
statusStroke.Parent = StatusCard

local statusTitle = Instance.new("TextLabel")
statusTitle.Size = UDim2.new(0, 140, 0, 16)
statusTitle.Position = UDim2.new(0, 12, 0, 10)
statusTitle.BackgroundTransparency = 1
statusTitle.Text = "LIVE STATUS"
statusTitle.TextColor3 = Color3.fromRGB(102, 117, 145)
statusTitle.TextSize = 8
statusTitle.Font = Enum.Font.GothamBold
statusTitle.TextXAlignment = Enum.TextXAlignment.Left
statusTitle.Parent = StatusCard

StatusRoleLabel = Instance.new("TextLabel")
StatusRoleLabel.Size = UDim2.new(0, 155, 0, 20)
StatusRoleLabel.Position = UDim2.new(0, 12, 0, 25)
StatusRoleLabel.BackgroundTransparency = 1
StatusRoleLabel.Text = "ROLE  •  UNKNOWN"
StatusRoleLabel.TextColor3 = Color3.fromRGB(236, 240, 248)
StatusRoleLabel.TextSize = 10
StatusRoleLabel.Font = Enum.Font.GothamBold
StatusRoleLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusRoleLabel.Parent = StatusCard

StatusInfoLabel = Instance.new("TextLabel")
StatusInfoLabel.Size = UDim2.new(0, 170, 0, 16)
StatusInfoLabel.Position = UDim2.new(1, -182, 0, 29)
StatusInfoLabel.BackgroundTransparency = 1
StatusInfoLabel.Text = "SURVIVAL KIT ACTIVE"
StatusInfoLabel.TextColor3 = Color3.fromRGB(132, 143, 166)
StatusInfoLabel.TextSize = 8
StatusInfoLabel.Font = Enum.Font.GothamMedium
StatusInfoLabel.TextXAlignment = Enum.TextXAlignment.Right
StatusInfoLabel.Parent = StatusCard

-- Tabs
local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, -24, 0, 30)
TabBar.Position = UDim2.new(0, 12, 0, 142)
TabBar.BackgroundTransparency = 1
TabBar.ZIndex = 72
TabBar.Parent = Main

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
tabLayout.Padding = UDim.new(0, 5)
tabLayout.Parent = TabBar

local ContentArea = Instance.new("Frame")
ContentArea.Size = UDim2.new(1, -24, 1, -182)
ContentArea.Position = UDim2.new(0, 12, 0, 176)
ContentArea.BackgroundTransparency = 1
ContentArea.ZIndex = 71
ContentArea.Parent = Main

local TabFrames = {}
local TabButtons = {}

local function createTab(name)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0, 69, 0, 29)
    button.BackgroundColor3 = Color3.fromRGB(21, 24, 34)
    button.BorderSizePixel = 0
    button.Text = name
    button.TextColor3 = Color3.fromRGB(135, 145, 164)
    button.TextSize = 9
    button.Font = Enum.Font.GothamBold
    button.AutoButtonColor = false
    button.ZIndex = 73
    button.Parent = TabBar

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = button

    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "Tab_" .. name
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 2
    scroll.ScrollBarImageColor3 = Color3.fromRGB(81, 143, 235)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new()
    scroll.Visible = false
    scroll.ZIndex = 72
    scroll.Parent = ContentArea

    local padding = Instance.new("UIPadding")
    padding.PaddingRight = UDim.new(0, 2)
    padding.PaddingBottom = UDim.new(0, 6)
    padding.Parent = scroll

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = scroll

    TabFrames[name] = scroll
    TabButtons[name] = button

    button.MouseButton1Click:Connect(function()
        if State.IsUnloaded then return end
        State.CurrentTab = name
        for tabName, frame in pairs(TabFrames) do
            frame.Visible = (tabName == name)
        end
        for tabName, btn in pairs(TabButtons) do
            local selected = (tabName == name)
            tween(btn, TweenInfo.new(0.16, Enum.EasingStyle.Quad), {
                BackgroundColor3 = selected and Color3.fromRGB(42, 72, 132) or Color3.fromRGB(21, 24, 34),
                TextColor3 = selected and Color3.fromRGB(245, 248, 255) or Color3.fromRGB(135, 145, 164)
            })
        end
    end)

    return scroll
end

local visualsTab = createTab("Visuals")
local combatTab = createTab("Combat")
local movementTab = createTab("Move")
local utilityTab = createTab("Utility")

local function sectionLabel(parent, text)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 18)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(92, 106, 132)
    label.TextSize = 8
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 73
    label.Parent = parent
    return label
end

local function createToggle(parent, title, subtitle, initial, callback)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 46)
    row.BackgroundColor3 = Color3.fromRGB(18, 21, 31)
    row.BorderSizePixel = 0
    row.ZIndex = 73
    row.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 11)
    corner.Parent = row

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(32, 37, 52)
    stroke.Thickness = 1
    stroke.Parent = row

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -82, 0, 20)
    titleLabel.Position = UDim2.new(0, 12, 0, 7)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title
    titleLabel.TextColor3 = Color3.fromRGB(230, 235, 245)
    titleLabel.TextSize = 10
    titleLabel.Font = Enum.Font.GothamMedium
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.ZIndex = 74
    titleLabel.Parent = row

    local subLabel = Instance.new("TextLabel")
    subLabel.Size = UDim2.new(1, -82, 0, 13)
    subLabel.Position = UDim2.new(0, 12, 0, 27)
    subLabel.BackgroundTransparency = 1
    subLabel.Text = subtitle or ""
    subLabel.TextColor3 = Color3.fromRGB(104, 115, 137)
    subLabel.TextSize = 7
    subLabel.Font = Enum.Font.Gotham
    subLabel.TextXAlignment = Enum.TextXAlignment.Left
    subLabel.ZIndex = 74
    subLabel.Parent = row

    local hit = Instance.new("TextButton")
    hit.Size = UDim2.new(0, 42, 0, 23)
    hit.Position = UDim2.new(1, -54, 0.5, -11.5)
    hit.BackgroundColor3 = Color3.fromRGB(47, 51, 66)
    hit.BorderSizePixel = 0
    hit.Text = ""
    hit.AutoButtonColor = false
    hit.ZIndex = 74
    hit.Parent = row

    local hitCorner = Instance.new("UICorner")
    hitCorner.CornerRadius = UDim.new(1, 0)
    hitCorner.Parent = hit

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 17, 0, 17)
    knob.Position = UDim2.new(0, 3, 0.5, -8.5)
    knob.BackgroundColor3 = Color3.fromRGB(210, 216, 230)
    knob.BorderSizePixel = 0
    knob.ZIndex = 75
    knob.Parent = hit

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local value = initial == true

    local function render(animated)
        local info = animated and TweenInfo.new(0.17, Enum.EasingStyle.Quint, Enum.EasingDirection.Out) or TweenInfo.new(0)
        tween(hit, info, { BackgroundColor3 = value and Color3.fromRGB(66, 135, 226) or Color3.fromRGB(47, 51, 66) })
        tween(knob, info, { Position = value and UDim2.new(1, -20, 0.5, -8.5) or UDim2.new(0, 3, 0.5, -8.5) })
        tween(knob, info, { BackgroundColor3 = value and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(210, 216, 230) })
    end

    hit.MouseButton1Click:Connect(function()
        value = not value
        render(true)
        pcall(callback, value)
    end)

    render(false)
    return row, function(newValue)
        value = newValue == true
        render(true)
    end
end

local function createAction(parent, title, subtitle, callback, accent)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 0, 42)
    button.BackgroundColor3 = Color3.fromRGB(18, 21, 31)
    button.BorderSizePixel = 0
    button.Text = ""
    button.AutoButtonColor = false
    button.ZIndex = 73
    button.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 11)
    corner.Parent = button

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(32, 37, 52)
    stroke.Thickness = 1
    stroke.Parent = button

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 3, 0, 25)
    bar.Position = UDim2.new(0, 10, 0.5, -12.5)
    bar.BackgroundColor3 = accent or Color3.fromRGB(84, 145, 230)
    bar.BorderSizePixel = 0
    bar.ZIndex = 74
    bar.Parent = button

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(1, 0)
    barCorner.Parent = bar

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -42, 0, 18)
    titleLabel.Position = UDim2.new(0, 20, 0, 6)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title
    titleLabel.TextColor3 = Color3.fromRGB(232, 237, 247)
    titleLabel.TextSize = 10
    titleLabel.Font = Enum.Font.GothamMedium
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.ZIndex = 74
    titleLabel.Parent = button

    local subLabel = Instance.new("TextLabel")
    subLabel.Size = UDim2.new(1, -42, 0, 12)
    subLabel.Position = UDim2.new(0, 20, 0, 25)
    subLabel.BackgroundTransparency = 1
    subLabel.Text = subtitle or ""
    subLabel.TextColor3 = Color3.fromRGB(100, 112, 135)
    subLabel.TextSize = 7
    subLabel.Font = Enum.Font.Gotham
    subLabel.TextXAlignment = Enum.TextXAlignment.Left
    subLabel.ZIndex = 74
    subLabel.Parent = button

    local arrow = Instance.new("TextLabel")
    arrow.Size = UDim2.new(0, 18, 0, 18)
    arrow.Position = UDim2.new(1, -25, 0.5, -9)
    arrow.BackgroundTransparency = 1
    arrow.Text = ">"
    arrow.TextColor3 = Color3.fromRGB(100, 113, 136)
    arrow.TextSize = 11
    arrow.Font = Enum.Font.GothamBold
    arrow.ZIndex = 74
    arrow.Parent = button

    button.MouseButton1Click:Connect(function()
        tween(button, TweenInfo.new(0.08), { BackgroundColor3 = Color3.fromRGB(26, 31, 45) })
        task.delay(0.08, function()
            if button and button.Parent then
                tween(button, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(18, 21, 31) })
            end
        end)
        pcall(callback)
    end)

    return button
end

local function switchTab(tabName)
    local btn = TabButtons[tabName]
    if not btn then return end
    State.CurrentTab = tabName
    for name, frame in pairs(TabFrames) do
        frame.Visible = (name == tabName)
    end
    for name, tabButton in pairs(TabButtons) do
        local selected = name == tabName
        tabButton.BackgroundColor3 = selected and Color3.fromRGB(42, 72, 132) or Color3.fromRGB(21, 24, 34)
        tabButton.TextColor3 = selected and Color3.fromRGB(245, 248, 255) or Color3.fromRGB(135, 145, 164)
    end
end

--==============================================================
-- Build tabs: fair-play awareness and practice helpers
--==============================================================
sectionLabel(visualsTab, "SURVIVAL AWARENESS")
createToggle(visualsTab, "Nearby Player Alert", "Line-of-sight warning • no role guessing", State.ProximityRadar, function(on)
    State.ProximityRadar = on
    if not on and ProximityAlertFrame then ProximityAlertFrame.Visible = false end
    notify(on and "Nearby alert enabled." or "Nearby alert disabled.", Color3.fromRGB(255, 125, 135))
end)

createToggle(visualsTab, "Coin Route Assistant", "Marks one visible coin • manual movement only", State.CoinRouteAssist, function(on)
    State.CoinRouteAssist = on
    if not on then clearCoinRouteMarker() end
    updateCoinRouteAssist()
    notify(on and "Coin guide enabled: walk around obstacles." or "Coin guide disabled.", Color3.fromRGB(115, 220, 160))
end)

createAction(visualsTab, "Survival Tips", "Quick advice based on your own detected role", function()
    showRoleTips(getRole(LocalPlayer, true))
end, Color3.fromRGB(255, 115, 125))

createAction(visualsTab, "Escape Checklist", "Cover • exits • avoid dead ends", function()
    notify("ESCAPE CHECK • Keep an exit in view, use corners for cover, and do not run into dead ends.", Color3.fromRGB(255, 170, 105))
end, Color3.fromRGB(255, 170, 105))

sectionLabel(combatTab, "SHERIFF PRACTICE")
createToggle(combatTab, "Practice Crosshair", "Center marker only • no auto aim", State.PracticeCrosshair, function(on)
    State.PracticeCrosshair = on
    if CrosshairLabel then CrosshairLabel.Visible = on end
    notify(on and "Practice crosshair enabled." or "Practice crosshair disabled.", RoleColors.Sheriff)
end)

createAction(combatTab, "Sheriff Tips", "Manual aim and clear line of sight", function()
    notify("SHERIFF • Keep distance, wait for a clear line, and aim manually. Avoid firing into a crowd.", RoleColors.Sheriff)
end, RoleColors.Sheriff)

sectionLabel(combatTab, "MURDERER PRACTICE")
createAction(combatTab, "Murderer Tips", "Use map corners and avoid straight chases", function()
    notify("MURDERER • Use corners for cover, watch escape routes, and avoid chasing in a straight line.", RoleColors.Murderer)
end, RoleColors.Murderer)

createAction(combatTab, "Start Practice Timer", "Generic manual timer • not the game's cooldown", function()
    startPracticeTimer(1.5)
end, Color3.fromRGB(255, 190, 90))

sectionLabel(movementTab, "LEGIT SURVIVAL MOVEMENT")
createAction(movementTab, "Escape Reminder", "Move normally; route around walls and doors", function()
    notify("MOVE SMART • Use normal movement, cut around corners, and keep an exit route open.", Color3.fromRGB(135, 190, 255))
end, Color3.fromRGB(135, 190, 255))

createAction(movementTab, "Reset Movement", "Restore normal WalkSpeed / JumpPower", function()
    State.Noclip = false
    State.AutoFarm = false
    State.WalkSpeed = 16
    State.JumpPower = 50
    stopFarmTween()
    setLocalCollision(true)
    updateWalkSpeed()
    updateJumpPower()
    notify("Normal movement restored.", Color3.fromRGB(145, 220, 170))
end, Color3.fromRGB(145, 220, 170))

sectionLabel(utilityTab, "COIN ROUTE")
createAction(utilityTab, "Refresh Coin Target", "Find another visible coin in line of sight", function()
    if not State.CoinRouteAssist then
        notify("Enable Coin Route Assistant in Visuals first.", Color3.fromRGB(150, 165, 190))
        return
    end
    updateCoinRouteAssist()
    notify("Coin target refreshed. Walk to it manually and go around obstacles.", Color3.fromRGB(115, 220, 160))
end, Color3.fromRGB(115, 220, 160))

createToggle(utilityTab, "FullBright", "Local lighting adjustment", State.FullBright, function(on)
    setFullBright(on)
end)

sectionLabel(utilityTab, "SCRIPT")
createAction(utilityTab, "Refresh Helpers", "Refresh nearby alert and coin guide", function()
    updateProximity()
    updateCoinRouteAssist()
    updateStatusUI()
    notify("Helpers refreshed.", Color3.fromRGB(105, 175, 255))
end, Color3.fromRGB(105, 175, 255))

createAction(utilityTab, "Unload Cleanly", "Restore changes + destroy UI", function()
    if API.Unload then API.Unload() end
end, Color3.fromRGB(255, 95, 110))

--==============================================================
-- Runtime status
--==============================================================
updateStatusUI = function()
    if State.IsUnloaded then return end

    local myRole = getRole(LocalPlayer, true)
    local color = RoleColors[myRole] or RoleColors.Unknown

    if StatusRoleLabel then
        StatusRoleLabel.Text = "ROLE  •  " .. myRole:upper()
        StatusRoleLabel.TextColor3 = color
    end

    if StatusInfoLabel then
        local bits = {}
        if State.PracticeCrosshair then table.insert(bits, "CROSSHAIR") end
        if State.ProximityRadar then table.insert(bits, "ALERT") end
        if State.CoinRouteAssist then table.insert(bits, "COIN GUIDE") end
        if #bits == 0 then
            StatusInfoLabel.Text = "STANDBY"
        else
            StatusInfoLabel.Text = table.concat(bits, "  •  ")
        end
    end
end

local function hasLineOfSightToCharacter(targetCharacter, targetPosition)
    local camera = Workspace.CurrentCamera or Camera
    local origin = camera and camera.CFrame.Position
    if not origin then return false end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character }
    params.IgnoreWater = true

    local direction = targetPosition - origin
    local result = Workspace:Raycast(origin, direction, params)
    if not result then
        return true
    end
    return targetCharacter and result.Instance and result.Instance:IsDescendantOf(targetCharacter) or false
end

updateProximity = function()
    if not ProximityAlertFrame or State.IsUnloaded or not State.ProximityRadar then
        if ProximityAlertFrame then ProximityAlertFrame.Visible = false end
        return
    end

    local myRoot = getRoot(LocalPlayer.Character)
    if not myRoot then
        ProximityAlertFrame.Visible = false
        return
    end

    local nearestPlayer, nearestRoot, nearestDistance = nil, nil, 28
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and isAlive(plr) then
            local otherRoot = getRoot(plr.Character)
            if otherRoot then
                local distance = (myRoot.Position - otherRoot.Position).Magnitude
                if distance < nearestDistance and hasLineOfSightToCharacter(plr.Character, otherRoot.Position + Vector3.new(0, 1.25, 0)) then
                    nearestPlayer, nearestRoot, nearestDistance = plr, otherRoot, distance
                end
            end
        end
    end

    if nearestPlayer and nearestRoot then
        local camera = Workspace.CurrentCamera or Camera
        local screenPoint, onScreen = camera:WorldToViewportPoint(nearestRoot.Position)
        local side = "NEARBY"
        if onScreen then
            side = screenPoint.X < camera.ViewportSize.X * 0.42 and "LEFT"
                or (screenPoint.X > camera.ViewportSize.X * 0.58 and "RIGHT" or "AHEAD")
        end
        ProximityAlertFrame.Visible = true
        ProximityAlertLabel.Text = string.format("PLAYER %s  •  %d STUDS", side, math.floor(nearestDistance))
        return
    end

    ProximityAlertFrame.Visible = false
end

local CoinRouteBillboard = nil
local CoinRouteTarget = nil

clearCoinRouteMarker = function()
    if CoinRouteBillboard then
        pcall(function() CoinRouteBillboard:Destroy() end)
    end
    CoinRouteBillboard = nil
    CoinRouteTarget = nil
end

updateCoinRouteAssist = function()
    if State.IsUnloaded or not State.CoinRouteAssist then
        clearCoinRouteMarker()
        return
    end

    local myRoot = getRoot(LocalPlayer.Character)
    local camera = Workspace.CurrentCamera or Camera
    if not myRoot or not camera then
        clearCoinRouteMarker()
        return
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character }
    params.IgnoreWater = true

    local bestCoin, bestDistance = nil, 80
    for _, coin in ipairs(getTargetCoins()) do
        if coin and coin.Parent and coin:IsDescendantOf(Workspace) then
            local distance = (coin.Position - myRoot.Position).Magnitude
            if distance < bestDistance then
                local origin = camera.CFrame.Position
                local result = Workspace:Raycast(origin, coin.Position - origin, params)
                -- Only mark the coin if the camera has a clear line to it; never show targets through walls.
                local visible = (result == nil) or (result.Instance == coin)
                if visible then
                    bestCoin, bestDistance = coin, distance
                end
            end
        end
    end

    if not bestCoin then
        clearCoinRouteMarker()
        return
    end

    if CoinRouteTarget ~= bestCoin or not CoinRouteBillboard or not CoinRouteBillboard.Parent then
        clearCoinRouteMarker()
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "LRN_CoinRouteTarget"
        billboard.Adornee = bestCoin
        billboard.Size = UDim2.new(0, 176, 0, 34)
        billboard.StudsOffset = Vector3.new(0, 2.4, 0)
        billboard.AlwaysOnTop = false
        billboard.MaxDistance = 85
        billboard.LightInfluence = 0
        billboard.Parent = uiHost

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundColor3 = Color3.fromRGB(22, 29, 25)
        label.BackgroundTransparency = 0.12
        label.BorderSizePixel = 0
        label.Text = "NEXT COIN  •  WALK MANUALLY"
        label.TextColor3 = Color3.fromRGB(150, 245, 190)
        label.TextSize = 9
        label.Font = Enum.Font.GothamBold
        label.Parent = billboard
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = label
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(83, 180, 125)
        stroke.Thickness = 1
        stroke.Parent = label

        CoinRouteBillboard = billboard
        CoinRouteTarget = bestCoin
    else
        CoinRouteBillboard.Adornee = bestCoin
    end
end

showRoleTips = function(role)
    role = role or getRole(LocalPlayer, true)
    if role == "Murderer" then
        notify("KILLER TIP • Use corners for cover; avoid chasing in a straight line.", RoleColors.Murderer)
    elseif role == "Sheriff" or role == "Hero" then
        notify("SHERIFF TIP • Keep a clear line of sight and aim manually before firing.", RoleColors.Sheriff)
    elseif role == "Innocent" then
        notify("INNOCENT TIP • Keep exits in view; turn corners and avoid dead ends.", RoleColors.Innocent)
    else
        notify("ROLE UNKNOWN • Stay near exits and use cover until your role is clear.", RoleColors.Unknown)
    end
end

startPracticeTimer = function(seconds)
    if State.PracticeTimerRunning then
        notify("Practice timer is already running.", Color3.fromRGB(150, 165, 190))
        return
    end
    seconds = math.clamp(tonumber(seconds) or 1.5, 0.5, 5)
    State.PracticeTimerRunning = true
    State.PracticeTimerUntil = os.clock() + seconds
    PracticeTimerLabel.Visible = true
    task.spawn(function()
        while not State.IsUnloaded and State.PracticeTimerRunning do
            local remaining = State.PracticeTimerUntil - os.clock()
            if remaining <= 0 then break end
            PracticeTimerLabel.Text = string.format("PRACTICE TIMER  •  %.1fs", remaining)
            task.wait(0.05)
        end
        State.PracticeTimerRunning = false
        if PracticeTimerLabel and PracticeTimerLabel.Parent then
            PracticeTimerLabel.Text = "PRACTICE READY"
            task.wait(0.45)
            if PracticeTimerLabel and PracticeTimerLabel.Parent then
                PracticeTimerLabel.Visible = false
            end
        end
    end)
end

--==============================================================
-- Drag helpers
--==============================================================
local function makeDraggable(frame, handle)
    local dragging = false
    local dragStart = nil
    local startPos = nil
    local dragInput = nil

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    local conn = UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
    return conn
end

Connections.MainDrag = makeDraggable(Main, Header)
Connections.PillDrag = makeDraggable(Pill, Pill)

local function setMenuVisible(visible)
    State.MenuOpen = visible
    if not Main then return end

    if visible then
        Main.Visible = true
        Main.Position = UDim2.new(0.5, -160, 0.5, -172)
        tween(Main, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Position = UDim2.new(0.5, -160, 0.5, -182)
        })
    else
        tween(Main, TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            Position = UDim2.new(0.5, -160, 0.5, -168)
        })
        task.delay(0.16, function()
            if not State.MenuOpen and Main then
                Main.Visible = false
            end
        end)
    end
end

Pill.MouseButton1Click:Connect(function()
    setMenuVisible(not State.MenuOpen)
end)

Close.MouseButton1Click:Connect(function()
    setMenuVisible(false)
end)

local keybindConn = UserInputService.InputBegan:Connect(function(input, processed)
    if processed or State.IsUnloaded then return end
    if input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.Insert then
        setMenuVisible(not State.MenuOpen)
    end
end)
Connections.Keybind = keybindConn

-- Responsive scale
local function updateScale()
    if not State.AutoScaleUI then
        UIScale.Scale = 1
        return
    end
    Camera = Workspace.CurrentCamera or Camera
    if not Camera then return end

    local width = Camera.ViewportSize.X
    local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    local scale
    if touchOnly then
        scale = math.clamp(width / 900, 0.62, 0.78)
    else
        scale = math.clamp(width / 1050, 0.78, 0.92)
    end
    UIScale.Scale = scale
end

--==============================================================
-- Runtime connections
--==============================================================
Connections.CharacterAdded = LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.6)
    if State.IsUnloaded then return end
    updateWalkSpeed()
    updateJumpPower()
end)

Connections.Noclip = RunService.Stepped:Connect(function()
    if State.IsUnloaded then return end
    if State.Noclip or State.AutoFarm then
        setLocalCollision(false)
    else
        setLocalCollision(true)
    end
end)

local function bindPlayer(plr)
    if not plr or plr == LocalPlayer then return end
    if PlayerConnections[plr] then
        pcall(function() PlayerConnections[plr]:Disconnect() end)
    end

    PlayerConnections[plr] = plr.CharacterAdded:Connect(function()
        if State.IsUnloaded then return end
        task.wait(0.45)
        Cache.Role[plr] = nil
        Cache.RoleStamp[plr] = nil
        if State.RoleESP then createPlayerESP(plr) end
        if State.HitboxExpander then applyHitbox(plr) end
    end)
end

Connections.PlayerAdded = Players.PlayerAdded:Connect(function(plr)
    bindPlayer(plr)
end)

Connections.PlayerRemoving = Players.PlayerRemoving:Connect(function(plr)
    removePlayerESP(plr)
    Cache.Role[plr] = nil
    Cache.RoleStamp[plr] = nil
    Cache.RoleAnnounced[plr] = nil
    if PlayerConnections[plr] then
        pcall(function() PlayerConnections[plr]:Disconnect() end)
        PlayerConnections[plr] = nil
    end
    local line = Cache.Tracers[plr]
    if line then
        pcall(function() line:Remove() end)
        Cache.Tracers[plr] = nil
    end
end)

Connections.Render = RunService.RenderStepped:Connect(function()
    if State.IsUnloaded then return end
    updateAutoAim()
    renderTracers()
end)

Connections.Camera = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = Workspace.CurrentCamera or Camera
    updateScale()
end)

--==============================================================
-- Scanner workers
--==============================================================
task.spawn(function()
    while not State.IsUnloaded do
        local players = Players:GetPlayers()
        for _, plr in ipairs(players) do
            if plr ~= LocalPlayer and plr.Character then
                if State.RoleESP then
                    local data = Cache.ESP[plr]
                    if not data or not data.Highlight or not data.Highlight.Parent then
                        createPlayerESP(plr)
                    else
                        local role = getRole(plr)
                        local color = RoleColors[role] or RoleColors.Unknown
                        data.Highlight.FillColor = color
                        data.Highlight.OutlineColor = color:Lerp(Color3.new(1,1,1), 0.65)
                        if data.RoleText then
                            data.RoleText.Text = role:upper()
                            data.RoleText.TextColor3 = color
                        end
                    end
                end

                if State.HitboxExpander then
                    applyHitbox(plr)
                end
            end
        end

        if State.GunESP then updateGunDropESP() end
        if State.TrapESP then updateTrapESP() end
        updateProximity()
        updateCoinRouteAssist()
        updateStatusUI()
        task.wait(0.55)
    end
end)

task.spawn(function()
    while not State.IsUnloaded do
        if State.AutoFarm then
            runFarmStep()
        end
        task.wait(0.4)
    end
end)

task.spawn(function()
    while not State.IsUnloaded do
        updateScale()
        task.wait(1.2)
    end
end)

--==============================================================
-- Unload
--==============================================================
function API.Unload()
    if State.IsUnloaded then return end
    State.IsUnloaded = true

    State.AutoFarm = false
    State.Noclip = false
    State.AutoAim = false
    State.HitboxExpander = false
    State.Tracers = false
    State.CoinRouteAssist = false
    State.PracticeCrosshair = false
    State.PracticeTimerRunning = false
    if CrosshairLabel then CrosshairLabel.Visible = false end
    clearCoinRouteMarker()
    stopFarmTween()

    resetAllHitboxes()
    clearAllESP()
    clearTracers()
    clearGunESP()
    clearTrapESP()
    setLocalCollision(true)
    for plr, conn in pairs(PlayerConnections) do
        pcall(function() conn:Disconnect() end)
        PlayerConnections[plr] = nil
    end
    disconnectAll()

    setFullBright(false)
    restoreMovement()

    if ProximityAlertFrame then
        ProximityAlertFrame.Visible = false
    end

    if ScreenGui and ScreenGui.Parent then
        pcall(function() ScreenGui:Destroy() end)
    end

    if GlobalEnv.LRN_MM2_ULTIMATE == API then
        GlobalEnv.LRN_MM2_ULTIMATE = nil
    end

    print("[LRN] MM2 Ultimate V6 unloaded cleanly.")
end

API.State = State
API.Notify = notify

--==============================================================
-- Initial setup
--==============================================================
for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer then
        bindPlayer(plr)
        if State.RoleESP then createPlayerESP(plr) end
    end
end

switchTab("Visuals")
updateScale()
updateWalkSpeed()
updateJumpPower()
notify("V6 loaded • Survival & Role Kit", Color3.fromRGB(95, 165, 255))

print("[LRN] MM2 Ultimate V6 ready.")
