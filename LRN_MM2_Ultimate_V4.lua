--[[
    LRN MM2 ULTIMATE V3.2 (FIXED & FULL ENHANCED)
    Modern UI / Mobile Friendly / High Performance & Full Feature Set

    Fixes:
    - Fixed UI drag lag & desync caused by dynamic UIScale on mobile
    - Optimized Noclip (removed heavy GetDescendants scan in Stepped)
    - Fixed Hitbox Expander (now targets HumanoidRootPart only to preserve player meshes)
    - Enhanced cleanup & connection management

    Added Features:
    - Auto Grab Gun (Otomatis ambil gun drop saat sheriff mati)
    - Knife Aura (Auto-slash pemain sekitar saat jadi Murderer)
    - Sky Safe Platform (Platform kokoh di udara agar tidak jatuh bebas)
    - Smart Coin Bag Limiter (Auto-stop farm & retreat ke safe spot saat koin penuh)
    - Spectate Murderer & Sheriff
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

    RoleESP = true,
    GunESP = true,
    TrapESP = true,
    Tracers = false,
    ProximityRadar = true,

    SilentAim = true,
    KnifeAura = false,
    HitboxExpander = false,
    HitboxSize = 14,

    AutoFarm = false,
    AutoGrabGun = false,
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
    OriginalHRP = setmetatable({}, { __mode = "k" }),
    Role = {},
    RoleStamp = {},
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
}

local UI = {}
local currentFarmTween = nil
local PlayerConnections = {}
local SkyPlatformPart = nil
local ProximityAlertFrame = nil
local ProximityAlertLabel = nil
local StatusRoleLabel = nil
local StatusInfoLabel = nil
local lastTrapScan = 0
local lastGrabAttempt = 0
local lastKnifeAuraSlash = 0

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
    if not instance or not instance.Parent then return end
    local ok, tw = pcall(function()
        local obj = TweenService:Create(instance, info, props)
        obj:Play()
        return obj
    end)
    return ok and tw or nil
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
    if not UI.ToastHolder or not UI.ToastHolder.Parent then return end

    accent = accent or Color3.fromRGB(95, 165, 255)

    local toast = Instance.new("Frame")
    toast.Size = UDim2.new(0, 250, 0, 42)
    toast.BackgroundColor3 = Color3.fromRGB(20, 22, 31)
    toast.BackgroundTransparency = 0.05
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
            if out then out.Completed:Wait() end
            if toast and toast.Parent then toast:Destroy() end
        end
    end)
end

--==============================================================
-- Role scanner
--==============================================================
local function classifyRoleString(value)
    if typeof(value) ~= "string" then return nil end
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
            if role then return role end
        end
    end

    local char = plr.Character
    if char then
        for _, attr in ipairs(attrs) do
            local ok, value = pcall(function() return char:GetAttribute(attr) end)
            if ok then
                local role = classifyRoleString(value)
                if role then return role end
            end
        end
    end
    return nil
end

local function getRole(plr, force)
    if not plr then return "Innocent" end

    local stamp = os.clock()
    if not force and Cache.Role[plr] and Cache.RoleStamp[plr] and (stamp - Cache.RoleStamp[plr] < 0.35) then
        return Cache.Role[plr]
    end

    local direct = readRoleAttributes(plr)
    if direct then
        Cache.Role[plr] = direct
        Cache.RoleStamp[plr] = stamp
        return direct
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
            Cache.Role[plr] = "Murderer"
            Cache.RoleStamp[plr] = stamp
            return "Murderer"
        end
    end

    for _, name in ipairs(toolNames) do
        if name:find("gun") or name:find("revolver") or name:find("pistol") or name:find("sheriff") then
            Cache.Role[plr] = "Sheriff"
            Cache.RoleStamp[plr] = stamp
            return "Sheriff"
        end
    end

    Cache.Role[plr] = "Innocent"
    Cache.RoleStamp[plr] = stamp
    return "Innocent"
end

local function getMurdererPlayer()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and isAlive(plr) and getRole(plr) == "Murderer" then
            return plr
        end
    end
    return nil
end

local function getSheriffPlayer()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and isAlive(plr) then
            local r = getRole(plr)
            if r == "Sheriff" or r == "Hero" then
                return plr
            end
        end
    end
    return nil
end

--==============================================================
-- Silent aim hook
--==============================================================
safeCall(function()
    if typeof(hookmetamethod) ~= "function" then return end

    local oldIndex
    oldIndex = hookmetamethod(game, "__index", wrapCClosure(function(self, idx)
        if not State.IsUnloaded and State.SilentAim and not isCaller() then
            if typeof(self) == "Instance" and self:IsA("Mouse") then
                if idx == "Hit" or idx == "Target" then
                    local char = LocalPlayer.Character
                    local tool = char and char:FindFirstChildWhichIsA("Tool")
                    local toolName = tool and tool.Name:lower() or ""

                    if tool and (toolName:find("gun") or toolName:find("revolver") or toolName:find("pistol")) then
                        local murderer = getMurdererPlayer()
                        local mchar = murderer and murderer.Character
                        if mchar then
                            local targetPart = mchar:FindFirstChild("UpperTorso")
                                or mchar:FindFirstChild("Torso")
                                or mchar:FindFirstChild("HumanoidRootPart")
                                or mchar:FindFirstChild("Head")

                            if targetPart then
                                if idx == "Hit" then
                                    return targetPart.CFrame
                                end
                                return targetPart
                            end
                        end
                    end
                end
            end
        end
        return oldIndex(self, idx)
    end))
end)

--==============================================================
-- ESP Features
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
    local color = RoleColors[role] or RoleColors.Innocent

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

    if not force and os.clock() - lastTrapScan < 1.0 then return end
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
        if next(Cache.Tracers) then clearTracers() end
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
                        local ok, obj = pcall(function() return Drawing.new("Line") end)
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
-- Hitbox Expander (Optimized: Targets HRP only to avoid mesh distortion)
--==============================================================
local function applyHitbox(plr)
    if State.IsUnloaded or not State.HitboxExpander or plr == LocalPlayer then return end

    local char = plr.Character
    if not char then return end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then
        if not Cache.OriginalHRP[hrp] then
            Cache.OriginalHRP[hrp] = {
                Size = hrp.Size,
                Transparency = hrp.Transparency,
                CanCollide = hrp.CanCollide,
            }
        end

        local role = getRole(plr)
        local color = RoleColors[role] or RoleColors.Innocent

        hrp.Size = Vector3.new(State.HitboxSize, State.HitboxSize, State.HitboxSize)
        hrp.Transparency = 0.72
        hrp.Color = color
        hrp.Material = Enum.Material.ForceField
        hrp.CanCollide = false
        pcall(function() hrp.CanQuery = true end)
    end
end

local function restoreHitbox(part)
    local original = Cache.OriginalHRP[part]
    if not original or not part or not part.Parent then return end

    pcall(function()
        part.Size = original.Size
        part.Transparency = original.Transparency
        part.CanCollide = original.CanCollide
    end)
    Cache.OriginalHRP[part] = nil
end

local function resetAllHitboxes()
    for part in pairs(Cache.OriginalHRP) do
        restoreHitbox(part)
    end
end

--==============================================================
-- Combat Features: Knife Aura
--==============================================================
local function runKnifeAura()
    if not State.KnifeAura or State.IsUnloaded then return end
    if os.clock() - lastKnifeAuraSlash < 0.25 then return end

    local char = LocalPlayer.Character
    if not char then return end

    local role = getRole(LocalPlayer)
    if role ~= "Murderer" then return end

    local knife = char:FindFirstChildOfClass("Tool")
    if not knife then return end
    local kName = knife.Name:lower()
    if not (kName:find("knife") or kName:find("blade") or kName:find("slash") or kName:find("dagger")) then
        return
    end

    local myRoot = getRoot(char)
    if not myRoot then return end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and isAlive(plr) and getRole(plr) ~= "Murderer" then
            local enemyRoot = getRoot(plr.Character)
            if enemyRoot then
                local dist = (enemyRoot.Position - myRoot.Position).Magnitude
                if dist <= 14 then
                    lastKnifeAuraSlash = os.clock()
                    pcall(function()
                        knife:Activate()
                    end)
                    break
                end
            end
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
-- Farming & World (Safe Platform & Auto Grab Gun)
--==============================================================
local function stopFarmTween()
    if currentFarmTween then
        pcall(function() currentFarmTween:Cancel() end)
        currentFarmTween = nil
    end
end

local function ensureSkyPlatform(pos)
    if not SkyPlatformPart or not SkyPlatformPart.Parent then
        SkyPlatformPart = Instance.new("Part")
        SkyPlatformPart.Name = "LRN3_SkyPlatform"
        SkyPlatformPart.Size = Vector3.new(24, 1.5, 24)
        SkyPlatformPart.Anchored = true
        SkyPlatformPart.CanCollide = true
        SkyPlatformPart.Transparency = 0.5
        SkyPlatformPart.Color = Color3.fromRGB(30, 35, 50)
        SkyPlatformPart.Material = Enum.Material.SmoothPlastic
        SkyPlatformPart.Parent = Workspace
    end
    SkyPlatformPart.CFrame = CFrame.new(pos - Vector3.new(0, 3, 0))
end

local function removeSkyPlatform()
    if SkyPlatformPart and SkyPlatformPart.Parent then
        pcall(function() SkyPlatformPart:Destroy() end)
    end
    SkyPlatformPart = nil
end

local function goToSky()
    local root = getRoot(LocalPlayer.Character)
    if not root then return end

    local targetPos = root.Position + Vector3.new(0, 110, 0)
    ensureSkyPlatform(targetPos)
    root.CFrame = CFrame.new(targetPos)
    notify("Safe platform aktif di langit.", Color3.fromRGB(130, 175, 255))
end

local function teleportToGun()
    local gun = findGunDropPart()
    local root = getRoot(LocalPlayer.Character)
    if not gun or not root then
        notify("Gun drop belum ketemu.", RoleColors.GunDrop)
        return
    end

    root.CFrame = gun.CFrame + Vector3.new(0, 2.5, 0)
    notify("Teleported ke gun drop.", RoleColors.GunDrop)
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

-- Smart Coin Bag Reader to prevent unnecessary farming when full
local function isCoinBagFull()
    local pgui = LocalPlayer:FindFirstChild("PlayerGui")
    if not pgui then return false end

    local mainGui = pgui:FindFirstChild("MainGUI")
    if not mainGui then return false end

    local gameFrame = mainGui:FindFirstChild("Game")
    if not gameFrame then return false end

    local coinBag = gameFrame:FindFirstChild("CoinBags", true) or gameFrame:FindFirstChild("CoinBag", true)
    if coinBag then
        local amount = coinBag:FindFirstChild("Amount", true)
        if amount and amount:IsA("TextLabel") then
            local cur, max = amount.Text:match("(%d+)%s*/%s*(%d+)")
            if cur and max and tonumber(cur) and tonumber(max) then
                if tonumber(cur) >= tonumber(max) then
                    return true
                end
            end
        end
    end
    return false
end

local function runFarmStep()
    if not State.AutoFarm or State.IsUnloaded then return end

    if isCoinBagFull() then
        State.AutoFarm = false
        stopFarmTween()
        notify("Tas koin penuh! Mundur ke safe platform.", Color3.fromRGB(78, 230, 150))
        goToSky()
        return
    end

    local root = getRoot(LocalPlayer.Character)
    if not root then return end

    local coins = getTargetCoins()
    for _, coin in ipairs(coins) do
        if not State.AutoFarm or State.IsUnloaded then break end
        if coin and coin.Parent and coin:IsDescendantOf(Workspace) then
            root = getRoot(LocalPlayer.Character)
            if not root then break end

            local distance = (root.Position - coin.Position).Magnitude
            local speed = 26
            local duration = math.clamp(distance / speed, 0.08, 3.0)

            root.AssemblyLinearVelocity = Vector3.zero
            currentFarmTween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
                CFrame = coin.CFrame + Vector3.new(0, 1.2, 0)
            })
            currentFarmTween:Play()

            local ok = pcall(function() currentFarmTween.Completed:Wait() end)
            if not ok then break end
            task.wait(0.06)
        end
    end
end

local function runAutoGrabGun()
    if not State.AutoGrabGun or State.IsUnloaded then return end
    if os.clock() - lastGrabAttempt < 1.5 then return end

    local myRole = getRole(LocalPlayer)
    if myRole == "Murderer" or myRole == "Sheriff" or myRole == "Hero" then
        return
    end

    local gun = findGunDropPart()
    local root = getRoot(LocalPlayer.Character)
    if gun and root then
        lastGrabAttempt = os.clock()
        local originalCF = root.CFrame
        root.CFrame = gun.CFrame + Vector3.new(0, 1.5, 0)
        notify("Mengambil gun drop otomatis!", RoleColors.GunDrop)
        task.wait(0.35)
    end
end

--==============================================================
-- Spectate Functions
--==============================================================
local function spectatePlayer(plr)
    if not plr or not plr.Character then return end
    local hum = getHumanoid(plr.Character)
    if hum then
        Camera.CameraSubject = hum
        notify("Spectating: " .. (plr.DisplayName or plr.Name), RoleColors.Sheriff)
    end
end

local function resetSpectate()
    local hum = getHumanoid(LocalPlayer.Character)
    if hum then
        Camera.CameraSubject = hum
        notify("Spectate di-reset ke diri sendiri.", Color3.fromRGB(150, 160, 180))
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
-- UI Construction
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

local oldGui = uiHost:FindFirstChild("LRN_MM2_ULTIMATE_V3")
if oldGui then
    pcall(function() oldGui:Destroy() end)
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "LRN_MM2_ULTIMATE_V3"
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
alert.Size = UDim2.new(0, 310, 0, 42)
alert.Position = UDim2.new(0.5, -155, 0, 18)
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

-- Floating Pill button
local Pill = Instance.new("TextButton")
Pill.Name = "MenuPill"
Pill.Size = UDim2.new(0, 58, 0, 58)
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

-- Main Window
local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 370, 0, 435)
Main.Position = UDim2.new(0.5, -185, 0.5, -217)
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

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 72)
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
Subtitle.Text = "v3.2 • responsive & optimized"
Subtitle.TextColor3 = Color3.fromRGB(125, 134, 154)
Subtitle.TextSize = 9
Subtitle.Font = Enum.Font.GothamMedium
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.ZIndex = 72
Subtitle.Parent = Header

local Close = Instance.new("TextButton")
Close.Size = UDim2.new(0, 28, 0, 28)
Close.Position = UDim2.new(1, -38, 0, 14)
Close.BackgroundColor3 = Color3.fromRGB(31, 34, 47)
Close.BorderSizePixel = 0
Close.Text = "×"
Close.TextColor3 = Color3.fromRGB(190, 198, 214)
Close.TextSize = 16
Close.Font = Enum.Font.GothamMedium
Close.AutoButtonColor = false
Close.ZIndex = 73
Close.Parent = Header

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = Close

-- Status Card
local StatusCard = Instance.new("Frame")
StatusCard.Size = UDim2.new(1, -28, 0, 54)
StatusCard.Position = UDim2.new(0, 14, 0, 82)
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

StatusRoleLabel = Instance.new("TextLabel")
StatusRoleLabel.Size = UDim2.new(0, 155, 0, 20)
StatusRoleLabel.Position = UDim2.new(0, 12, 0, 17)
StatusRoleLabel.BackgroundTransparency = 1
StatusRoleLabel.Text = "ROLE  •  UNKNOWN"
StatusRoleLabel.TextColor3 = Color3.fromRGB(236, 240, 248)
StatusRoleLabel.TextSize = 10
StatusRoleLabel.Font = Enum.Font.GothamBold
StatusRoleLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusRoleLabel.Parent = StatusCard

StatusInfoLabel = Instance.new("TextLabel")
StatusInfoLabel.Size = UDim2.new(0, 170, 0, 16)
StatusInfoLabel.Position = UDim2.new(1, -182, 0, 19)
StatusInfoLabel.BackgroundTransparency = 1
StatusInfoLabel.Text = "ESP ON  •  AIM ON"
StatusInfoLabel.TextColor3 = Color3.fromRGB(132, 143, 166)
StatusInfoLabel.TextSize = 8
StatusInfoLabel.Font = Enum.Font.GothamMedium
StatusInfoLabel.TextXAlignment = Enum.TextXAlignment.Right
StatusInfoLabel.Parent = StatusCard

-- Tabs Navigation
local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, -28, 0, 32)
TabBar.Position = UDim2.new(0, 14, 0, 144)
TabBar.BackgroundTransparency = 1
TabBar.ZIndex = 72
TabBar.Parent = Main

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 5)
tabLayout.Parent = TabBar

local ContentArea = Instance.new("Frame")
ContentArea.Size = UDim2.new(1, -28, 1, -188)
ContentArea.Position = UDim2.new(0, 14, 0, 182)
ContentArea.BackgroundTransparency = 1
ContentArea.ZIndex = 71
ContentArea.Parent = Main

local TabFrames = {}
local TabButtons = {}

local function createTab(name)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0, 79, 0, 30)
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
    layout.Padding = UDim.new(0, 6)
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
    label.Size = UDim2.new(1, 0, 0, 16)
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
    row.Size = UDim2.new(1, 0, 0, 48)
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
    titleLabel.Size = UDim2.new(1, -82, 0, 18)
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
    subLabel.Position = UDim2.new(0, 12, 0, 25)
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
    return row
end

local function createAction(parent, title, subtitle, callback, accent)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 0, 44)
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
    bar.Size = UDim2.new(0, 3, 0, 24)
    bar.Position = UDim2.new(0, 10, 0.5, -12)
    bar.BackgroundColor3 = accent or Color3.fromRGB(84, 145, 230)
    bar.BorderSizePixel = 0
    bar.ZIndex = 74
    bar.Parent = button

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(1, 0)
    barCorner.Parent = bar

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -42, 0, 17)
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
    subLabel.Position = UDim2.new(0, 20, 0, 24)
    subLabel.BackgroundTransparency = 1
    subLabel.Text = subtitle or ""
    subLabel.TextColor3 = Color3.fromRGB(100, 112, 135)
    subLabel.TextSize = 7
    subLabel.Font = Enum.Font.Gotham
    subLabel.TextXAlignment = Enum.TextXAlignment.Left
    subLabel.ZIndex = 74
    subLabel.Parent = button

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

--==============================================================
-- Build Tabs Content
--==============================================================
-- Visuals
sectionLabel(visualsTab, "PLAYER VISIBILITY")
createToggle(visualsTab, "Role ESP", "Highlight + live role tag", State.RoleESP, function(on)
    State.RoleESP = on
    if on then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then createPlayerESP(plr) end
        end
    else
        clearAllESP()
    end
end)

createToggle(visualsTab, "Gun Drop ESP", "Track dropped sheriff gun", State.GunESP, function(on)
    State.GunESP = on
    updateGunDropESP()
end)

createToggle(visualsTab, "Trap ESP", "Detect trap / mine objects", State.TrapESP, function(on)
    State.TrapESP = on
    updateTrapESP(true)
end)

createToggle(visualsTab, "Tracers", HasDrawing and "Drawing API • role lines" or "Drawing API unavailable", State.Tracers, function(on)
    State.Tracers = on
    if not on then clearTracers() end
end)

createToggle(visualsTab, "Murderer Radar", "Alert when danger is nearby", State.ProximityRadar, function(on)
    State.ProximityRadar = on
    if not on and ProximityAlertFrame then ProximityAlertFrame.Visible = false end
end)

sectionLabel(visualsTab, "SPECTATE")
createAction(visualsTab, "Spectate Murderer", "Kamera fokus ke murderer", function()
    local m = getMurdererPlayer()
    if m then spectatePlayer(m) else notify("Murderer tidak ditemukan.", RoleColors.Murderer) end
end, RoleColors.Murderer)

createAction(visualsTab, "Spectate Sheriff", "Kamera fokus ke sheriff", function()
    local s = getSheriffPlayer()
    if s then spectatePlayer(s) else notify("Sheriff tidak ditemukan.", RoleColors.Sheriff) end
end, RoleColors.Sheriff)

createAction(visualsTab, "Reset Camera", "Kembalikan kamera ke dirimu", function()
    resetSpectate()
end, Color3.fromRGB(140, 150, 170))

-- Combat
sectionLabel(combatTab, "TARGETING & ATTACK")
createToggle(combatTab, "Sheriff Silent Aim", "Auto target murderer saat pegang gun", State.SilentAim, function(on)
    State.SilentAim = on
    notify(on and "Silent aim ON." or "Silent aim OFF.", RoleColors.Sheriff)
end)

createToggle(combatTab, "Knife Aura", "Auto-slash pemain saat dekat (Murderer)", State.KnifeAura, function(on)
    State.KnifeAura = on
    notify(on and "Knife Aura ON." or "Knife Aura OFF.", RoleColors.Murderer)
end)

createToggle(combatTab, "Custom Hitbox (HRP)", "Expand RootPart lawan tanpa bug visual", State.HitboxExpander, function(on)
    State.HitboxExpander = on
    if on then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then applyHitbox(plr) end
        end
    else
        resetAllHitboxes()
        notify("Hitbox asli dikembalikan.", Color3.fromRGB(130, 140, 160))
    end
end)

createAction(combatTab, "Hitbox Size 14", "Balanced size preset", function()
    State.HitboxSize = 14
    if State.HitboxExpander then
        for _, plr in ipairs(Players:GetPlayers()) do applyHitbox(plr) end
    end
    notify("Hitbox set to 14.", RoleColors.Murderer)
end, Color3.fromRGB(95, 165, 255))

createAction(combatTab, "Hitbox Size 25", "Large size preset", function()
    State.HitboxSize = 25
    if State.HitboxExpander then
        for _, plr in ipairs(Players:GetPlayers()) do applyHitbox(plr) end
    end
    notify("Hitbox set to 25.", RoleColors.Murderer)
end, RoleColors.Murderer)

-- Movement
sectionLabel(movementTab, "MOVEMENT")
createToggle(movementTab, "Noclip", "Disable collisions (Optimized)", State.Noclip, function(on)
    State.Noclip = on
end)

createAction(movementTab, "WalkSpeed 32", "Speed boost", function()
    State.WalkSpeed = 32
    updateWalkSpeed()
end, Color3.fromRGB(90, 170, 255))

createAction(movementTab, "JumpPower 85", "High jump", function()
    State.JumpPower = 85
    updateJumpPower()
end, Color3.fromRGB(130, 220, 160))

createAction(movementTab, "Reset Movement", "Kembalikan ke standar (16/50)", function()
    restoreMovement()
end, Color3.fromRGB(145, 155, 175))

-- Utility
sectionLabel(utilityTab, "AUTOMATION & SAFE ZONE")
createToggle(utilityTab, "Auto Grab Gun", "Otomatis ambil gun saat sheriff gugur", State.AutoGrabGun, function(on)
    State.AutoGrabGun = on
    notify(on and "Auto Grab Gun ON." or "Auto Grab Gun OFF.", RoleColors.GunDrop)
end)

createToggle(utilityTab, "Auto Farm Coin", "Smart farming + auto retreat saat full", State.AutoFarm, function(on)
    State.AutoFarm = on
    if not on then stopFarmTween() end
    notify(on and "Coin farm aktif." or "Coin farm berhenti.", Color3.fromRGB(255, 213, 80))
end)

createAction(utilityTab, "Sky Safe Platform", "Pindah ke langit + buat pijakan aman", function()
    goToSky()
end, Color3.fromRGB(120, 180, 255))

createAction(utilityTab, "Teleport to Gun", "Lompat langsung ke pistol jatuh", function()
    teleportToGun()
end, RoleColors.GunDrop)

createToggle(utilityTab, "FullBright", "Hapus fog dan maksimalkan cahaya", State.FullBright, function(on)
    setFullBright(on)
end)

sectionLabel(utilityTab, "SYSTEM")
createAction(utilityTab, "Refresh Scanner", "Force refresh role & item", function()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            Cache.Role[plr] = nil
            Cache.RoleStamp[plr] = nil
            if State.RoleESP then createPlayerESP(plr) end
        end
    end
    updateGunDropESP()
    updateTrapESP(true)
    notify("Scanner refreshed.", Color3.fromRGB(105, 175, 255))
end, Color3.fromRGB(105, 175, 255))

createAction(utilityTab, "Unload Cleanly", "Hapus script & kembalikan setting", function()
    if API.Unload then API.Unload() end
end, Color3.fromRGB(255, 95, 110))

--==============================================================
-- Drag Helper (FIXED: Compensates for UIScale on Mobile)
--==============================================================
local function makeDraggable(frame, handle)
    local dragging = false
    local dragStart, startPos, dragInput

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

    return UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local currentScale = (UIScale and UIScale.Scale) or 1
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + (delta.X / currentScale),
                startPos.Y.Scale,
                startPos.Y.Offset + (delta.Y / currentScale)
            )
        end
    end)
end

Connections.MainDrag = makeDraggable(Main, Header)
Connections.PillDrag = makeDraggable(Pill, Pill)

local function setMenuVisible(visible)
    State.MenuOpen = visible
    if not Main then return end

    if visible then
        Main.Visible = true
        tween(Main, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Position = UDim2.new(0.5, -185, 0.5, -217)
        })
    else
        local out = tween(Main, TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            Position = UDim2.new(0.5, -185, 0.5, -198)
        })
        if out then
            out.Completed:Connect(function()
                if not State.MenuOpen and Main then
                    Main.Visible = false
                end
            end)
        end
    end
end

Pill.MouseButton1Click:Connect(function()
    setMenuVisible(not State.MenuOpen)
end)

Close.MouseButton1Click:Connect(function()
    setMenuVisible(false)
end)

Connections.Keybind = UserInputService.InputBegan:Connect(function(input, processed)
    if processed or State.IsUnloaded then return end
    if input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.Insert then
        setMenuVisible(not State.MenuOpen)
    end
end)

-- Responsive Scale
local function updateScale()
    if not State.AutoScaleUI then
        UIScale.Scale = 1
        return
    end
    Camera = Workspace.CurrentCamera or Camera
    if not Camera then return end
    local width = Camera.ViewportSize.X
    UIScale.Scale = math.clamp(width / 420, 0.75, 1)
end

--==============================================================
-- Optimized Runtime Connections
--==============================================================
Connections.CharacterAdded = LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.6)
    if State.IsUnloaded then return end
    updateWalkSpeed()
    updateJumpPower()
end)

-- Performance Fix: Fast Noclip without deep scanning
Connections.Noclip = RunService.Stepped:Connect(function()
    if State.IsUnloaded then return end
    if State.Noclip or State.AutoFarm then
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetChildren()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
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
    renderTracers()
    runKnifeAura()
end)

Connections.Camera = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = Workspace.CurrentCamera or Camera
    updateScale()
end)

--==============================================================
-- Background Worker Loops
--==============================================================
-- Scanner & UI Update
task.spawn(function()
    while not State.IsUnloaded do
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                if State.RoleESP then
                    local data = Cache.ESP[plr]
                    if not data or not data.Highlight or not data.Highlight.Parent then
                        createPlayerESP(plr)
                    else
                        local role = getRole(plr)
                        local color = RoleColors[role] or RoleColors.Innocent
                        data.Highlight.FillColor = color
                        data.Highlight.OutlineColor = color:Lerp(Color3.new(1, 1, 1), 0.65)
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

        updateGunDropESP()
        updateTrapESP()

        -- Proximity Warning
        if State.ProximityRadar and ProximityAlertFrame then
            local root = getRoot(LocalPlayer.Character)
            local murderer = getMurdererPlayer()
            local mroot = murderer and getRoot(murderer.Character)
            if root and mroot then
                local dist = (root.Position - mroot.Position).Magnitude
                if dist <= 38 then
                    ProximityAlertFrame.Visible = true
                    ProximityAlertLabel.Text = string.format("WARNING  •  %s  •  %d studs", murderer.DisplayName or murderer.Name, math.floor(dist))
                else
                    ProximityAlertFrame.Visible = false
                end
            else
                ProximityAlertFrame.Visible = false
            end
        end

        -- Update Role Card
        local myRole = getRole(LocalPlayer, true)
        if StatusRoleLabel then
            StatusRoleLabel.Text = "ROLE  •  " .. myRole:upper()
            StatusRoleLabel.TextColor3 = RoleColors[myRole] or RoleColors.Innocent
        end

        task.wait(0.5)
    end
end)

-- Automation worker (Farming & Auto Grab)
task.spawn(function()
    while not State.IsUnloaded do
        if State.AutoGrabGun then
            runAutoGrabGun()
        end
        if State.AutoFarm then
            runFarmStep()
        end
        task.wait(0.35)
    end
end)

task.spawn(function()
    while not State.IsUnloaded do
        updateScale()
        task.wait(1.5)
    end
end)

--==============================================================
-- Unload Routine
--==============================================================
function API.Unload()
    if State.IsUnloaded then return end
    State.IsUnloaded = true

    State.AutoFarm = false
    State.AutoGrabGun = false
    State.KnifeAura = false
    State.Noclip = false
    State.SilentAim = false
    State.HitboxExpander = false
    State.Tracers = false
    stopFarmTween()

    resetSpectate()
    removeSkyPlatform()
    resetAllHitboxes()
    clearAllESP()
    clearTracers()
    clearGunESP()
    clearTrapESP()

    for plr, conn in pairs(PlayerConnections) do
        pcall(function() conn:Disconnect() end)
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

    print("[LRN] MM2 Ultimate V3.2 unloaded cleanly.")
end

API.State = State
API.Notify = notify

--==============================================================
-- Initialization
--==============================================================
for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer then
        bindPlayer(plr)
        if State.RoleESP then createPlayerESP(plr) end
    end
end

-- Select default tab & configure start settings
for name, frame in pairs(TabFrames) do
    frame.Visible = (name == "Visuals")
end
for name, btn in pairs(TabButtons) do
    local sel = (name == "Visuals")
    btn.BackgroundColor3 = sel and Color3.fromRGB(42, 72, 132) or Color3.fromRGB(21, 24, 34)
    btn.TextColor3 = sel and Color3.fromRGB(245, 248, 255) or Color3.fromRGB(135, 145, 164)
end

updateScale()
updateWalkSpeed()
updateJumpPower()
notify("LRN MM2 Ultimate V3.2 loaded.", Color3.fromRGB(95, 165, 255))
print("[LRN] MM2 Ultimate V3.2 ready.")
