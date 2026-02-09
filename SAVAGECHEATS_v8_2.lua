--[[
    ╔═══════════════════════════════════════════════════════════════╗
    ║              SAVAGECHEATS_ AIMBOT UNIVERSAL v8.2              ║
    ║                  UI LIMPA + NOVAS FUNÇÕES                     ║
    ╠═══════════════════════════════════════════════════════════════╣
    ║  • UI reorganizada e limpa                                    ║
    ║  • Seletor de Time para Aimbot                                ║
    ║  • Munição Infinita separada                                  ║
    ║  • Rapid Fire ultra ajustável                                 ║
    ║  • Compatível com Mobile                                      ║
    ╚═══════════════════════════════════════════════════════════════╝
]]

-- ═══════════════════════════════════════════════════════════════
--                          SERVIÇOS
-- ═══════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ═══════════════════════════════════════════════════════════════
--                      VARIÁVEIS GLOBAIS
-- ═══════════════════════════════════════════════════════════════

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

-- Detectar jogo
local GameId = game.PlaceId
local IsPrisonLife = GameId == 155615604 or GameId == 419601093
local GameName = IsPrisonLife and "Prison Life" or "Universal"

-- Limpar instância anterior
if _G.SAVAGE_V82 then
    pcall(function() _G.SAVAGE_V82_CLEANUP() end)
    task.wait(0.3)
end

-- ═══════════════════════════════════════════════════════════════
--                       CONFIGURAÇÕES
-- ═══════════════════════════════════════════════════════════════

local Config = {
    -- Aimbot
    AimbotEnabled = false,
    SilentAim = false,
    IgnoreWalls = false,
    SkipDowned = true,
    AimPart = "Head",
    
    -- Team Filter
    TeamFilter = "Todos", -- Todos, Prisioneiros, Guardas, Criminosos, Inimigos
    
    -- FOV
    FOVRadius = 150,
    FOVVisible = true,
    
    -- Smoothing
    Smoothness = 0.3,
    
    -- ESP
    ESPEnabled = false,
    ESPBox = true,
    ESPName = true,
    ESPHealth = true,
    ESPDistance = true,
    
    -- NoClip
    NoClipEnabled = false,
    
    -- Hitbox
    HitboxEnabled = false,
    HitboxSize = 5,
    
    -- Speed (CFrame apenas - seguro)
    SpeedEnabled = false,
    SpeedMultiplier = 0.2,
    
    -- Rapid Fire
    RapidFireEnabled = false,
    RapidFireRate = 0.05, -- 0.01 a 0.5
    
    -- Munição Infinita
    InfiniteAmmoEnabled = false,
    
    -- Misc
    ShowLine = false,
    MaxDistance = 1000,
}

local State = {
    Target = nil,
    TargetPart = nil,
    Locked = false,
}

local Connections = {}
local ESPObjects = {}

-- ═══════════════════════════════════════════════════════════════
--                         CORES DO TEMA
-- ═══════════════════════════════════════════════════════════════

local Theme = {
    Primary = Color3.fromRGB(200, 30, 30),
    Secondary = Color3.fromRGB(25, 25, 25),
    Background = Color3.fromRGB(15, 15, 15),
    Surface = Color3.fromRGB(35, 35, 35),
    SurfaceLight = Color3.fromRGB(45, 45, 45),
    Text = Color3.fromRGB(255, 255, 255),
    TextDim = Color3.fromRGB(150, 150, 150),
    Success = Color3.fromRGB(50, 200, 50),
    Warning = Color3.fromRGB(255, 180, 0),
    Border = Color3.fromRGB(60, 60, 60),
    Accent = Color3.fromRGB(255, 80, 80),
}

-- ═══════════════════════════════════════════════════════════════
--                    FUNÇÕES UTILITÁRIAS
-- ═══════════════════════════════════════════════════════════════

local function GetScreenCenter()
    return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
end

local function WorldToScreen(pos)
    local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
    return Vector2.new(screenPos.X, screenPos.Y), onScreen and screenPos.Z > 0
end

local function Distance2D(a, b)
    return (a - b).Magnitude
end

local function Distance3D(a, b)
    return (a - b).Magnitude
end

local function IsAlive(character)
    if not character then return false end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    
    if Config.SkipDowned then
        if character:FindFirstChild("Knocked") or 
           character:FindFirstChild("Downed") or
           hum:GetState() == Enum.HumanoidStateType.Physics then
            return false
        end
    end
    return true
end

-- ═══════════════════════════════════════════════════════════════
--                    SISTEMA DE TIMES
-- ═══════════════════════════════════════════════════════════════

local function GetPlayerTeamName(player)
    if not player.Team then return "Sem Time" end
    local teamName = player.Team.Name:lower()
    
    -- Prison Life teams
    if teamName:find("prisoner") or teamName:find("prisioneiro") then
        return "Prisioneiros"
    elseif teamName:find("guard") or teamName:find("guarda") or teamName:find("police") then
        return "Guardas"
    elseif teamName:find("criminal") or teamName:find("criminoso") then
        return "Criminosos"
    end
    
    return player.Team.Name
end

local function ShouldTarget(player)
    if player == LocalPlayer then return false end
    
    local filter = Config.TeamFilter
    
    if filter == "Todos" then
        return player ~= LocalPlayer
    elseif filter == "Inimigos" then
        if not LocalPlayer.Team or not player.Team then return true end
        return LocalPlayer.Team ~= player.Team
    else
        local playerTeam = GetPlayerTeamName(player)
        return playerTeam == filter
    end
end

local function HasLineOfSight(origin, target)
    if Config.IgnoreWalls then return true end
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
    
    local result = Workspace:Raycast(origin, (target - origin), params)
    if result then
        local model = result.Instance:FindFirstAncestorOfClass("Model")
        return model and model:FindFirstChildOfClass("Humanoid") ~= nil
    end
    return true
end

local function GetTargetPart(character)
    local part = character:FindFirstChild(Config.AimPart)
    if not part then
        part = character:FindFirstChild("Head") or 
               character:FindFirstChild("HumanoidRootPart")
    end
    return part
end

-- ═══════════════════════════════════════════════════════════════
--                    SISTEMA DE ALVO
-- ═══════════════════════════════════════════════════════════════

local function FindTarget()
    local bestTarget, bestPart = nil, nil
    local bestDist = Config.FOVRadius
    local center = GetScreenCenter()
    local camPos = Camera.CFrame.Position
    
    for _, player in pairs(Players:GetPlayers()) do
        if ShouldTarget(player) then
            local char = player.Character
            if char and IsAlive(char) then
                local part = GetTargetPart(char)
                if part then
                    local dist3D = Distance3D(camPos, part.Position)
                    if dist3D <= Config.MaxDistance then
                        local screenPos, visible = WorldToScreen(part.Position)
                        if visible then
                            local dist2D = Distance2D(center, screenPos)
                            if dist2D < bestDist then
                                if HasLineOfSight(camPos, part.Position) then
                                    bestDist = dist2D
                                    bestTarget = player
                                    bestPart = part
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return bestTarget, bestPart
end

-- ═══════════════════════════════════════════════════════════════
--                    SISTEMA DE MIRA
-- ═══════════════════════════════════════════════════════════════

local function AimAt(position)
    if not position then return end
    
    local camPos = Camera.CFrame.Position
    local targetCF = CFrame.lookAt(camPos, position)
    
    if Config.Smoothness > 0 then
        Camera.CFrame = Camera.CFrame:Lerp(targetCF, 1 - Config.Smoothness)
    else
        Camera.CFrame = targetCF
    end
end

-- ═══════════════════════════════════════════════════════════════
--                    SILENT AIM
-- ═══════════════════════════════════════════════════════════════

local SilentAimHooked = false
local OldIndex = nil

local function EnableSilentAim()
    if SilentAimHooked then return end
    
    pcall(function()
        local mt = getrawmetatable(game)
        local oldReadonly = isreadonly(mt)
        setreadonly(mt, false)
        
        OldIndex = mt.__index
        mt.__index = newcclosure(function(self, key)
            if Config.SilentAim and Config.AimbotEnabled then
                if typeof(self) == "Instance" and self:IsA("Mouse") then
                    local target, part = FindTarget()
                    if target and part then
                        if key == "Hit" then
                            return part.CFrame
                        elseif key == "Target" then
                            return part
                        end
                    end
                end
            end
            return OldIndex(self, key)
        end)
        
        setreadonly(mt, oldReadonly)
        SilentAimHooked = true
    end)
end

local function DisableSilentAim()
    if not SilentAimHooked then return end
    pcall(function()
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        if OldIndex then mt.__index = OldIndex end
        setreadonly(mt, true)
        SilentAimHooked = false
    end)
end

-- ═══════════════════════════════════════════════════════════════
--                    NOCLIP
-- ═══════════════════════════════════════════════════════════════

local NoClipConnection = nil
local NoClipBypassApplied = false

local function ApplyPrisonLifeBypass()
    if NoClipBypassApplied then return end
    pcall(function()
        local scripts = ReplicatedStorage:FindFirstChild("Scripts")
        if scripts then
            local collision = scripts:FindFirstChild("CharacterCollision")
            if collision then collision:Destroy() end
        end
        NoClipBypassApplied = true
    end)
end

local function EnableNoClip()
    if NoClipConnection then return end
    if IsPrisonLife then ApplyPrisonLifeBypass() end
    
    NoClipConnection = RunService.Stepped:Connect(function()
        if not Config.NoClipEnabled then return end
        local char = LocalPlayer.Character
        if char then
            for _, part in pairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end
    end)
end

local function DisableNoClip()
    if NoClipConnection then
        NoClipConnection:Disconnect()
        NoClipConnection = nil
    end
end

-- ═══════════════════════════════════════════════════════════════
--                    HITBOX
-- ═══════════════════════════════════════════════════════════════

local HitboxConnection = nil
local OriginalSizes = {}

local function UpdateHitboxes()
    for _, player in pairs(Players:GetPlayers()) do
        if ShouldTarget(player) then
            local char = player.Character
            if char then
                local root = char:FindFirstChild("HumanoidRootPart")
                if root then
                    if not OriginalSizes[player] then
                        OriginalSizes[player] = root.Size
                    end
                    
                    if Config.HitboxEnabled then
                        local size = Config.HitboxSize
                        root.Size = Vector3.new(size, size, size)
                        root.Transparency = 0.7
                        root.CanCollide = false
                        root.Material = Enum.Material.ForceField
                    else
                        root.Size = OriginalSizes[player] or Vector3.new(2, 2, 1)
                        root.Transparency = 1
                        root.Material = Enum.Material.SmoothPlastic
                    end
                end
            end
        end
    end
end

local function EnableHitbox()
    if HitboxConnection then return end
    HitboxConnection = RunService.Heartbeat:Connect(function()
        if Config.HitboxEnabled then UpdateHitboxes() end
    end)
end

local function DisableHitbox()
    if HitboxConnection then
        HitboxConnection:Disconnect()
        HitboxConnection = nil
    end
    Config.HitboxEnabled = false
    UpdateHitboxes()
    OriginalSizes = {}
end

-- ═══════════════════════════════════════════════════════════════
--                    CFRAME SPEED (SEGURO)
-- ═══════════════════════════════════════════════════════════════

local SpeedConnection = nil

local function EnableSpeed()
    if SpeedConnection then return end
    
    SpeedConnection = RunService.Stepped:Connect(function()
        if not Config.SpeedEnabled then return end
        
        local char = LocalPlayer.Character
        if not char then return end
        
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        
        if hrp and hum and hum.MoveDirection.Magnitude > 0 then
            hrp.CFrame = hrp.CFrame + hum.MoveDirection * Config.SpeedMultiplier
        end
    end)
end

local function DisableSpeed()
    if SpeedConnection then
        SpeedConnection:Disconnect()
        SpeedConnection = nil
    end
end

-- ═══════════════════════════════════════════════════════════════
--                    RAPID FIRE + MUNIÇÃO INFINITA
-- ═══════════════════════════════════════════════════════════════

local ModifiedGuns = {}

local function ModifyGun(gun)
    if not gun then return false end
    if ModifiedGuns[gun] then return true end
    
    local success = pcall(function()
        local gunStates = gun:FindFirstChild("GunStates")
        if gunStates then
            local sM = require(gunStates)
            
            -- Rapid Fire
            if Config.RapidFireEnabled then
                sM["FireRate"] = Config.RapidFireRate
                sM["AutoFire"] = true
            end
            
            -- Munição Infinita
            if Config.InfiniteAmmoEnabled then
                sM["MaxAmmo"] = 999999
                sM["StoredAmmo"] = 999999
                sM["AmmoPerClip"] = 999999
                sM["ReloadTime"] = 0.01
            end
            
            -- Bônus
            sM["Range"] = 9999
            
            ModifiedGuns[gun] = true
        end
    end)
    
    return success
end

local function ApplyGunMods()
    -- Modificar armas no Backpack
    for _, item in pairs(LocalPlayer.Backpack:GetChildren()) do
        if item:IsA("Tool") then
            ModifyGun(item)
        end
    end
    
    -- Modificar arma equipada
    if LocalPlayer.Character then
        for _, item in pairs(LocalPlayer.Character:GetChildren()) do
            if item:IsA("Tool") then
                ModifyGun(item)
            end
        end
    end
end

local function EnableRapidFire()
    ModifiedGuns = {} -- Reset para reaplicar
    ApplyGunMods()
    
    if not Connections.GunBackpack then
        Connections.GunBackpack = LocalPlayer.Backpack.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then
                task.wait(0.1)
                ModifyGun(child)
            end
        end)
    end
end

local function EnableInfiniteAmmo()
    ModifiedGuns = {} -- Reset para reaplicar
    ApplyGunMods()
    
    if not Connections.AmmoBackpack then
        Connections.AmmoBackpack = LocalPlayer.Backpack.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then
                task.wait(0.1)
                ModifyGun(child)
            end
        end)
    end
end

local function DisableGunMods()
    ModifiedGuns = {}
    
    if Connections.GunBackpack then
        Connections.GunBackpack:Disconnect()
        Connections.GunBackpack = nil
    end
    
    if Connections.AmmoBackpack then
        Connections.AmmoBackpack:Disconnect()
        Connections.AmmoBackpack = nil
    end
end

-- ═══════════════════════════════════════════════════════════════
--                    FOV CIRCLE
-- ═══════════════════════════════════════════════════════════════

local FOVCircle = nil
local AimLine = nil

local function CreateDrawings()
    pcall(function()
        if FOVCircle then FOVCircle:Remove() end
        if AimLine then AimLine:Remove() end
        
        FOVCircle = Drawing.new("Circle")
        FOVCircle.Thickness = 2
        FOVCircle.NumSides = 60
        FOVCircle.Radius = Config.FOVRadius
        FOVCircle.Filled = false
        FOVCircle.Visible = false
        FOVCircle.ZIndex = 999
        FOVCircle.Color = Theme.Primary
        
        AimLine = Drawing.new("Line")
        AimLine.Thickness = 2
        AimLine.Color = Theme.Success
        AimLine.Visible = false
        AimLine.ZIndex = 998
    end)
end

local function UpdateDrawings()
    if FOVCircle then
        FOVCircle.Position = GetScreenCenter()
        FOVCircle.Radius = Config.FOVRadius
        FOVCircle.Visible = Config.FOVVisible and Config.AimbotEnabled
        FOVCircle.Color = State.Locked and Theme.Success or Theme.Primary
    end
    
    if AimLine and Config.ShowLine and State.Locked and State.TargetPart then
        local targetPos, visible = WorldToScreen(State.TargetPart.Position)
        if visible then
            AimLine.From = GetScreenCenter()
            AimLine.To = targetPos
            AimLine.Visible = true
        else
            AimLine.Visible = false
        end
    elseif AimLine then
        AimLine.Visible = false
    end
end

local function DestroyDrawings()
    pcall(function()
        if FOVCircle then FOVCircle:Remove() FOVCircle = nil end
        if AimLine then AimLine:Remove() AimLine = nil end
    end)
end

-- ═══════════════════════════════════════════════════════════════
--                    NOVO ESP (BILLBOARD GUI + HIGHLIGHT)
--                    OTIMIZADO PARA MOBILE
-- ═══════════════════════════════════════════════════════════════

local activeESP = {}
local espConnections = {}
local updateRunning = false

-- Referência segura para o container pai dos GUIs
local function GetESPContainer()
    if game:GetService("CoreGui"):FindFirstChild("RobloxGui") then
        -- Tenta CoreGui (Executores com privilégios altos)
        local success, core = pcall(function() return game:GetService("CoreGui") end)
        if success and core then
            local folder = core:FindFirstChild("ESPContainer")
            if not folder then
                folder = Instance.new("Folder")
                folder.Name = "ESPContainer"
                folder.Parent = core
            end
            return folder
        end
    end
    -- Fallback para PlayerGui (Mais seguro para Delta/Fluxus)
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local folder = playerGui:FindFirstChild("ESPContainer")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "ESPContainer"
        folder.Parent = playerGui
    end
    return folder
end

local function CreateLabel(name, parent, textSize, anchorY, posY)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 0, textSize + 4)
    label.AnchorPoint = Vector2.new(0.5, anchorY)
    label.Position = UDim2.new(0.5, 0, posY, 0)
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeColor3 = Color3.black
    label.TextStrokeTransparency = 0.5
    label.TextSize = textSize
    label.Font = Enum.Font.GothamBold
    label.Text = ""
    label.Parent = parent
    return label
end

local function CreateESP(player)
    if player == LocalPlayer or activeESP[player] then return end
    local character = player.Character
    if not character then return end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- 1. Billboard
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESP_" .. player.Name
    billboard.Adornee = hrp
    billboard.Size = UDim2.new(4, 0, 5, 0)
    billboard.StudsOffset = Vector3.new(0, 0.5, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = GetESPContainer()

    -- 2. Box (UIStroke)
    local boxFrame = Instance.new("Frame")
    boxFrame.Size = UDim2.new(1, 0, 1, 0)
    boxFrame.BackgroundTransparency = 1
    boxFrame.Parent = billboard
    
    local boxStroke = Instance.new("UIStroke")
    boxStroke.Thickness = 1.5
    boxStroke.Color = Theme.Primary
    boxStroke.Parent = boxFrame

    -- 3. Labels
    local nameLabel = CreateLabel("Name", billboard, 13, 1, 0)
    nameLabel.Position = UDim2.new(0.5, 0, 0, -5)
    
    local distLabel = CreateLabel("Dist", billboard, 11, 0, 1)
    distLabel.Position = UDim2.new(0.5, 0, 1, 5)

    -- 4. Highlight (Chams)
    local highlight = Instance.new("Highlight")
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0.1
    highlight.Adornee = character
    highlight.Parent = character

    activeESP[player] = {
        Billboard = billboard,
        BoxStroke = boxStroke,
        NameLabel = nameLabel,
        DistLabel = distLabel,
        Highlight = highlight,
        Player = player
    }
end

local function RemoveESP(player)
    if activeESP[player] then
        if activeESP[player].Billboard then activeESP[player].Billboard:Destroy() end
        if activeESP[player].Highlight then activeESP[player].Highlight:Destroy() end
        activeESP[player] = nil
    end
end

local function UpdateESP_Logic()
    -- Loop lento (Task.Spawn) para não travar o celular
    while updateRunning do
        if Config.ESPEnabled then
            for _, player in pairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    if not activeESP[player] and player.Character then
                        CreateESP(player)
                    end
                    
                    local data = activeESP[player]
                    if data then
                        local char = player.Character
                        if char and IsAlive(char) then
                            -- Cor do Time
                            local isTarget = ShouldTarget(player)
                            local color = isTarget and Theme.Primary or Theme.Success
                            
                            -- Atualizar Visibilidade
                            data.Billboard.Enabled = true
                            data.Highlight.Enabled = true
                            data.Highlight.FillColor = color
                            data.Highlight.OutlineColor = color
                            
                            -- Box
                            data.BoxStroke.Transparency = Config.ESPBox and 0 or 1
                            data.BoxStroke.Color = color
                            
                            -- Nome
                            if Config.ESPName then
                                data.NameLabel.Visible = true
                                data.NameLabel.Text = player.DisplayName
                                data.NameLabel.TextColor3 = color
                            else
                                data.NameLabel.Visible = false
                            end
                            
                            -- Distância
                            if Config.ESPDistance then
                                local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                                local targetRoot = char:FindFirstChild("HumanoidRootPart")
                                if myRoot and targetRoot then
                                    local dist = math.floor((myRoot.Position - targetRoot.Position).Magnitude)
                                    data.DistLabel.Visible = true
                                    data.DistLabel.Text = "[" .. dist .. "m]"
                                end
                            else
                                data.DistLabel.Visible = false
                            end
                            
                        else
                            -- Esconde se estiver morto
                            data.Billboard.Enabled = false
                            data.Highlight.Enabled = false
                        end
                    end
                end
            end
        else
            -- Se ESP desativado, esconde tudo
            for _, data in pairs(activeESP) do
                data.Billboard.Enabled = false
                data.Highlight.Enabled = false
            end
        end
        task.wait(0.5) -- Atualiza a cada meio segundo (SUPER LEVE)
    end
end

local function InitESP()
    updateRunning = true
    task.spawn(UpdateESP_Logic)
    
    -- Reconectar ao morrer/respawn
    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function()
            task.wait(1)
            RemoveESP(player)
            CreateESP(player)
        end)
    end)
    
    Players.PlayerRemoving:Connect(RemoveESP)
end

local function DestroyESP()
    updateRunning = false
    for player, _ in pairs(activeESP) do
        RemoveESP(player)
    end
    
    local container = LocalPlayer.PlayerGui:FindFirstChild("ESPContainer")
    if container then container:Destroy() end
end

-- ═══════════════════════════════════════════════════════════════
-- UI MOBILE RESPONSIVA (CLAUDE OPUS 4.6)
-- ═══════════════════════════════════════════════════════════════

-- Variáveis de UI
local UI_Connections = {}
local ScreenGui = nil
local MainFrame = nil
local ToggleButton = nil
local MenuOpen = false

-- Constantes de Animação
local TWEEN_FAST = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_NORMAL = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_SPRING = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Utilitários de UI
local function Tween(instance, info, props)
    local tween = TweenService:Create(instance, info, props)
    tween:Play()
    return tween
end

local function AddCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
    return corner
end

local function AddStroke(parent, color, thickness)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = thickness
    stroke.Parent = parent
    return stroke
end

local function CreateRipple(parent, pos)
    local ripple = Instance.new("Frame")
    ripple.BackgroundColor3 = Color3.new(1,1,1)
    ripple.BackgroundTransparency = 0.8
    ripple.BorderSizePixel = 0
    ripple.AnchorPoint = Vector2.new(0.5, 0.5)
    ripple.Position = UDim2.new(0, pos.X - parent.AbsolutePosition.X, 0, pos.Y - parent.AbsolutePosition.Y)
    ripple.Size = UDim2.new(0, 0, 0, 0)
    ripple.Parent = parent
    AddCorner(ripple, 100)
    
    local size = math.max(parent.AbsoluteSize.X, parent.AbsoluteSize.Y) * 1.5
    local tween = Tween(ripple, TweenInfo.new(0.5), {Size = UDim2.new(0, size, 0, size), BackgroundTransparency = 1})
    tween.Completed:Connect(function() ripple:Destroy() end)
end

-- Componentes
local function CreateSectionHeader(parent, text)
    local frame = Instance.new("Frame")
    frame.BackgroundTransparency = 1
    frame.Size = UDim2.new(1, 0, 0, 30)
    frame.Parent = parent
    
    local label = Instance.new("TextLabel")
    label.Text = string.upper(text)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 11
    label.TextColor3 = Theme.Primary
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Size = UDim2.new(1, -10, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.BackgroundTransparency = 1
    label.Parent = frame
    
    local line = Instance.new("Frame")
    line.BackgroundColor3 = Theme.Primary
    line.Size = UDim2.new(0, 3, 0, 14)
    line.Position = UDim2.new(0, 0, 0.5, -7)
    line.BorderSizePixel = 0
    line.Parent = frame
    AddCorner(line, 2)
end

local function CreateToggle(parent, text, configKey, callback)
    local container = Instance.new("TextButton") -- Usar TextButton pro container facilita o clique
    container.AutoButtonColor = false
    container.BackgroundColor3 = Theme.Surface
    container.Size = UDim2.new(1, 0, 0, 45)
    container.Text = ""
    container.Parent = parent
    AddCorner(container, 8)
    
    local label = Instance.new("TextLabel")
    label.Text = text
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextColor3 = Theme.Text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Size = UDim2.new(1, -60, 1, 0)
    label.Position = UDim2.new(0, 15, 0, 0)
    label.BackgroundTransparency = 1
    label.Parent = container
    
    local track = Instance.new("Frame")
    track.Size = UDim2.new(0, 40, 0, 22)
    track.Position = UDim2.new(1, -55, 0.5, -11)
    track.BackgroundColor3 = Config[configKey] and Theme.Primary or Theme.SurfaceLight
    track.Parent = container
    AddCorner(track, 11)
    
    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = Config[configKey] and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    knob.BackgroundColor3 = Color3.new(1,1,1)
    knob.Parent = track
    AddCorner(knob, 9)
    
    container.MouseButton1Click:Connect(function()
        Config[configKey] = not Config[configKey]
        local state = Config[configKey]
        
        Tween(track, TWEEN_FAST, {BackgroundColor3 = state and Theme.Primary or Theme.SurfaceLight})
        Tween(knob, TWEEN_SPRING, {Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)})
        
        if callback then callback(state) end
    end)
    
    container.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
             CreateRipple(container, input.Position)
        end
    end)
end

local function CreateSlider(parent, text, configKey, min, max, step, callback)
    local container = Instance.new("Frame")
    container.BackgroundColor3 = Theme.Surface
    container.Size = UDim2.new(1, 0, 0, 60)
    container.Parent = parent
    AddCorner(container, 8)
    
    local label = Instance.new("TextLabel")
    label.Text = text
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextColor3 = Theme.Text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Size = UDim2.new(1, 0, 0, 20)
    label.Position = UDim2.new(0, 15, 0, 8)
    label.BackgroundTransparency = 1
    label.Parent = container
    
    local valueLabel = Instance.new("TextLabel")
    valueLabel.Text = tostring(Config[configKey])
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextSize = 13
    valueLabel.TextColor3 = Theme.Primary
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.Size = UDim2.new(1, -30, 0, 20)
    valueLabel.Position = UDim2.new(0, 0, 0, 8)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Parent = container
    
    local sliderBg = Instance.new("Frame")
    sliderBg.BackgroundColor3 = Theme.SurfaceLight
    sliderBg.Size = UDim2.new(1, -30, 0, 6)
    sliderBg.Position = UDim2.new(0, 15, 0, 40)
    sliderBg.Parent = container
    AddCorner(sliderBg, 3)
    
    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = Theme.Primary
    fill.Size = UDim2.new((Config[configKey] - min)/(max - min), 0, 1, 0)
    fill.Parent = sliderBg
    AddCorner(fill, 3)
    
    local knob = Instance.new("Frame")
    knob.BackgroundColor3 = Color3.new(1,1,1)
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(1, 0, 0.5, 0)
    knob.Parent = fill
    AddCorner(knob, 8)
    AddStroke(knob, Theme.Primary, 2)
    
    local isDragging = false
    local touchBtn = Instance.new("TextButton")
    touchBtn.BackgroundTransparency = 1
    touchBtn.Size = UDim2.new(1, 20, 1, 20)
    touchBtn.Position = UDim2.new(0, -10, 0, -10)
    touchBtn.Text = ""
    touchBtn.Parent = sliderBg
    
    local function Update(input)
        local pos = math.clamp((input.Position.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X, 0, 1)
        local newVal = math.floor((min + (max - min) * pos) / step + 0.5) * step
        
        Config[configKey] = newVal
        valueLabel.Text = tostring(newVal)
        fill.Size = UDim2.new(pos, 0, 1, 0)
        
        if callback then callback(newVal) end
    end
    
    touchBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            isDragging = true
            Tween(knob, TWEEN_FAST, {Size = UDim2.new(0, 22, 0, 22)})
            Update(input)
        end
    end)
    
    touchBtn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            isDragging = false
            Tween(knob, TWEEN_SPRING, {Size = UDim2.new(0, 16, 0, 16)})
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if isDragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
            Update(input)
        end
    end)
end

local function CreateDropdown(parent, text, configKey, options, callback)
    local container = Instance.new("Frame")
    container.BackgroundColor3 = Theme.Surface
    container.Size = UDim2.new(1, 0, 0, 45) -- Altura fechado
    container.ClipsDescendants = true
    container.Parent = parent
    AddCorner(container, 8)
    
    local headerBtn = Instance.new("TextButton")
    headerBtn.Size = UDim2.new(1, 0, 0, 45)
    headerBtn.BackgroundTransparency = 1
    headerBtn.Text = ""
    headerBtn.Parent = container
    
    local label = Instance.new("TextLabel")
    label.Text = text
    label.Font = Enum.Font.GothamMedium
    label.TextColor3 = Theme.Text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Size = UDim2.new(0.5, 0, 1, 0)
    label.Position = UDim2.new(0, 15, 0, 0)
    label.BackgroundTransparency = 1
    label.Parent = headerBtn
    
    local selected = Instance.new("TextLabel")
    selected.Text = Config[configKey]
    selected.Font = Enum.Font.GothamBold
    selected.TextColor3 = Theme.Primary
    selected.TextXAlignment = Enum.TextXAlignment.Right
    selected.Size = UDim2.new(0.5, -35, 1, 0)
    selected.Position = UDim2.new(0.5, 0, 0, 0)
    selected.BackgroundTransparency = 1
    selected.Parent = headerBtn
    
    local arrow = Instance.new("TextLabel")
    arrow.Text = "▼"
    arrow.TextColor3 = Theme.TextDim
    arrow.Size = UDim2.new(0, 20, 1, 0)
    arrow.Position = UDim2.new(1, -25, 0, 0)
    arrow.BackgroundTransparency = 1
    arrow.Parent = headerBtn
    
    local optionList = Instance.new("UIListLayout")
    optionList.Parent = container
    
    local expanded = false
    local height = 45 + (#options * 35) + 5
    
    -- Criar opções
    local optionFrame = Instance.new("Frame")
    optionFrame.Size = UDim2.new(1, 0, 0, #options * 35)
    optionFrame.Position = UDim2.new(0, 0, 0, 45)
    optionFrame.BackgroundTransparency = 1
    optionFrame.Parent = container
    
    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 2)
    list.Parent = optionFrame
    
    for _, opt in ipairs(options) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -10, 0, 33)
        btn.BackgroundColor3 = Theme.SurfaceLight
        btn.Text = opt
        btn.TextColor3 = Theme.TextDim
        btn.Font = Enum.Font.Gotham
        btn.Parent = optionFrame
        AddCorner(btn, 6)
        
        btn.MouseButton1Click:Connect(function()
            Config[configKey] = opt
            selected.Text = opt
            if callback then callback(opt) end
            
            -- Fechar
            expanded = false
            Tween(container, TWEEN_NORMAL, {Size = UDim2.new(1, 0, 0, 45)})
            Tween(arrow, TWEEN_FAST, {Rotation = 0})
        end)
    end
    
    headerBtn.MouseButton1Click:Connect(function()
        expanded = not expanded
        Tween(container, TWEEN_NORMAL, {Size = expanded and UDim2.new(1, 0, 0, height) or UDim2.new(1, 0, 0, 45)})
        Tween(arrow, TWEEN_FAST, {Rotation = expanded and 180 or 0})
    end)
end

-- Função Principal da UI
local function CreateUI()
    -- Cleanup
    if ScreenGui then ScreenGui:Destroy() end
    
    ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "SAVAGE_V8_MOBILE"
    ScreenGui.IgnoreGuiInset = true
    ScreenGui.ResetOnSpawn = false
    
    -- Tenta colocar no CoreGui (seguro), senão PlayerGui
    pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end)
    if not ScreenGui.Parent then ScreenGui.Parent = LocalPlayer.PlayerGui end
    
    -- 1. Botão Flutuante (Arrastável)
    ToggleButton = Instance.new("TextButton")
    ToggleButton.Size = UDim2.new(0, 50, 0, 50)
    ToggleButton.Position = UDim2.new(0, 20, 0.4, 0)
    ToggleButton.BackgroundColor3 = Theme.Primary
    ToggleButton.Text = "S"
    ToggleButton.TextSize = 24
    ToggleButton.Font = Enum.Font.GothamBlack
    ToggleButton.TextColor3 = Color3.white
    ToggleButton.Parent = ScreenGui
    AddCorner(ToggleButton, 25)
    AddStroke(ToggleButton, Color3.white, 2)
    
    local draggingToggle = false
    local dragStart, startPos
    
    ToggleButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingToggle = true
            dragStart = input.Position
            startPos = ToggleButton.Position
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if draggingToggle and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
            local delta = input.Position - dragStart
            if delta.Magnitude > 5 then -- Threshold para diferenciar clique de arraste
                ToggleButton.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end
    end)
    
    ToggleButton.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingToggle = false
            if (input.Position - dragStart).Magnitude < 5 then
                -- Foi um clique rápido -> Abrir Menu
                MenuOpen = not MenuOpen
                MainFrame.Visible = MenuOpen
                
                if MenuOpen then
                    MainFrame.Position = UDim2.new(0.5, 0, 0.55, 0)
                    Tween(MainFrame, TWEEN_NORMAL, {Position = UDim2.new(0.5, 0, 0.5, 0), GroupTransparency = 0})
                else
                    Tween(MainFrame, TWEEN_NORMAL, {Position = UDim2.new(0.5, 0, 0.55, 0), GroupTransparency = 1}).Completed:Connect(function()
                        if not MenuOpen then MainFrame.Visible = false end
                    end)
                end
            end
        end
    end)
    
    -- 2. Janela Principal (Responsiva)
    MainFrame = Instance.new("CanvasGroup")
    MainFrame.Size = UDim2.new(0.45, 0, 0.6, 0) -- 45% da tela (ajusta pra mobile)
    MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    MainFrame.BackgroundColor3 = Theme.Background
    MainFrame.Visible = false
    MainFrame.GroupTransparency = 1
    MainFrame.Parent = ScreenGui
    AddCorner(MainFrame, 16)
    
    -- Constraint para não ficar muito pequeno/grande
    local sizeC = Instance.new("UISizeConstraint")
    sizeC.MinSize = Vector2.new(320, 300)
    sizeC.MaxSize = Vector2.new(500, 700)
    sizeC.Parent = MainFrame
    
    -- Title Bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 45)
    titleBar.BackgroundColor3 = Theme.Secondary
    titleBar.Parent = MainFrame
    
    local titleLbl = Instance.new("TextLabel")
    titleLbl.Text = "SAVAGE v8.2"
    titleLbl.Font = Enum.Font.GothamBlack
    titleLbl.TextColor3 = Theme.Text
    titleLbl.TextSize = 16
    titleLbl.Size = UDim2.new(1, 0, 1, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Parent = titleBar
    
    -- Abas
    local tabContainer = Instance.new("Frame")
    tabContainer.Size = UDim2.new(1, -20, 0, 35)
    tabContainer.Position = UDim2.new(0, 10, 0, 50)
    tabContainer.BackgroundColor3 = Theme.Secondary
    tabContainer.Parent = MainFrame
    AddCorner(tabContainer, 8)
    
    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 5)
    tabLayout.Parent = tabContainer
    
    local contentContainer = Instance.new("ScrollingFrame")
    contentContainer.Size = UDim2.new(1, -20, 1, -100)
    contentContainer.Position = UDim2.new(0, 10, 0, 90)
    contentContainer.BackgroundTransparency = 1
    contentContainer.ScrollBarThickness = 2
    contentContainer.Parent = MainFrame
    
    local contentLayout = Instance.new("UIListLayout")
    contentLayout.Padding = UDim.new(0, 8)
    contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    contentLayout.Parent = contentContainer
    
    -- Lógica de Abas Simples
    local tabs = {"Aim", "Visual", "Misc"}
    local currentTab = "Aim"
    local uiElements = {} -- Armazena elementos pra mostrar/esconder
    
    for _, tabName in ipairs(tabs) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.33, -3, 1, 0)
        btn.BackgroundColor3 = (tabName == currentTab) and Theme.Primary or Theme.Surface
        btn.Text = tabName
        btn.TextColor3 = Theme.Text
        btn.Font = Enum.Font.GothamBold
        btn.Parent = tabContainer
        AddCorner(btn, 6)
        
        btn.MouseButton1Click:Connect(function()
            currentTab = tabName
            -- Atualiza botões
            for _, b in pairs(tabContainer:GetChildren()) do
                if b:IsA("TextButton") then
                    Tween(b, TWEEN_FAST, {BackgroundColor3 = (b.Text == tabName) and Theme.Primary or Theme.Surface})
                end
            end
            -- Atualiza conteúdo
            for _, el in pairs(uiElements) do
                el.Object.Visible = (el.Tab == tabName)
            end
            contentContainer.CanvasSize = UDim2.new(0, 0, 0, contentLayout.AbsoluteContentSize.Y + 20)
        end)
    end
    
    -- Função helper para adicionar na lista e vincular a aba
    local function AddToTab(tab, obj)
        table.insert(uiElements, {Tab = tab, Object = obj})
        obj.Visible = (tab == currentTab)
    end

    -- === CONTEÚDO DAS ABAS ===
    
    -- [ AIM ]
    local h1 = Instance.new("Frame", contentContainer); h1.Size = UDim2.new(1,0,0,30); h1.BackgroundTransparency=1
    CreateSectionHeader(h1, "Combat")
    AddToTab("Aim", h1)
    
    local t1 = Instance.new("Frame", contentContainer); t1.BackgroundTransparency=1; t1.Size=UDim2.new(1,0,0,45)
    CreateToggle(t1, "Aimbot Ativado", "AimbotEnabled", function(v) if v then EnableSilentAim() end end)
    AddToTab("Aim", t1)
    
    local t2 = Instance.new("Frame", contentContainer); t2.BackgroundTransparency=1; t2.Size=UDim2.new(1,0,0,45)
    CreateToggle(t2, "Silent Aim", "SilentAim")
    AddToTab("Aim", t2)
    
    local s1 = Instance.new("Frame", contentContainer); s1.BackgroundTransparency=1; s1.Size=UDim2.new(1,0,0,60)
    CreateSlider(s1, "FOV Radius", "FOVRadius", 50, 400, 10)
    AddToTab("Aim", s1)
    
    local d1 = Instance.new("Frame", contentContainer); d1.BackgroundTransparency=1; d1.Size=UDim2.new(1,0,0,45)
    CreateDropdown(d1, "Alvo (Bone)", "AimPart", {"Head", "HumanoidRootPart", "Torso"})
    AddToTab("Aim", d1)
    
    local d2 = Instance.new("Frame", contentContainer); d2.BackgroundTransparency=1; d2.Size=UDim2.new(1,0,0,45)
    CreateDropdown(d2, "Time", "TeamFilter", {"Todos", "Inimigos", "Guardas", "Prisioneiros"})
    AddToTab("Aim", d2)

    -- [ VISUAL ]
    local h2 = Instance.new("Frame", contentContainer); h2.Size = UDim2.new(1,0,0,30); h2.BackgroundTransparency=1
    CreateSectionHeader(h2, "ESP Visual")
    AddToTab("Visual", h2)
    
    local t3 = Instance.new("Frame", contentContainer); t3.BackgroundTransparency=1; t3.Size=UDim2.new(1,0,0,45)
    CreateToggle(t3, "ESP Master Switch", "ESPEnabled")
    AddToTab("Visual", t3)
    
    local t4 = Instance.new("Frame", contentContainer); t4.BackgroundTransparency=1; t4.Size=UDim2.new(1,0,0,45)
    CreateToggle(t4, "Box", "ESPBox")
    AddToTab("Visual", t4)
    
    local t5 = Instance.new("Frame", contentContainer); t5.BackgroundTransparency=1; t5.Size=UDim2.new(1,0,0,45)
    CreateToggle(t5, "Nomes", "ESPName")
    AddToTab("Visual", t5)
    
    local t6 = Instance.new("Frame", contentContainer); t6.BackgroundTransparency=1; t6.Size=UDim2.new(1,0,0,45)
    CreateToggle(t6, "Chams (Wallhack)", "ESPHealth") -- Reutilizando a var ESPHealth pra ativar o Highlight
    AddToTab("Visual", t6)

    -- [ MISC ]
    local h3 = Instance.new("Frame", contentContainer); h3.Size = UDim2.new(1,0,0,30); h3.BackgroundTransparency=1
    CreateSectionHeader(h3, "Personagem")
    AddToTab("Misc", h3)
    
    local t7 = Instance.new("Frame", contentContainer); t7.BackgroundTransparency=1; t7.Size=UDim2.new(1,0,0,45)
    CreateToggle(t7, "Speed", "SpeedEnabled", function(v) if v then EnableSpeed() else DisableSpeed() end end)
    AddToTab("Misc", t7)
    
    local s2 = Instance.new("Frame", contentContainer); s2.BackgroundTransparency=1; s2.Size=UDim2.new(1,0,0,60)
    CreateSlider(s2, "Velocidade", "SpeedMultiplier", 0.1, 2, 0.1)
    AddToTab("Misc", s2)
    
    local t8 = Instance.new("Frame", contentContainer); t8.BackgroundTransparency=1; t8.Size=UDim2.new(1,0,0,45)
    CreateToggle(t8, "Rapid Fire", "RapidFireEnabled", function(v) if v then EnableRapidFire() end end)
    AddToTab("Misc", t8)

    -- Atualiza tamanho do scroll
    contentContainer.CanvasSize = UDim2.new(0, 0, 0, #uiElements * 50)
end

-- ═══════════════════════════════════════════════════════════════
--                    LOOP PRINCIPAL
-- ═══════════════════════════════════════════════════════════════

local MainConnection = nil

local function MainLoop()
    MainConnection = RunService.RenderStepped:Connect(function()
        if Config.AimbotEnabled then
            local target, part = FindTarget()
            
            if target and part then
                State.Target = target
                State.TargetPart = part
                State.Locked = true
                
                if not Config.SilentAim then
                    AimAt(part.Position)
                end
            else
                State.Target = nil
                State.TargetPart = nil
                State.Locked = false
            end
        else
            State.Target = nil
            State.TargetPart = nil
            State.Locked = false
        end
        
        UpdateDrawings()
        
    end)
end

-- ═══════════════════════════════════════════════════════════════
--                    CLEANUP
-- ═══════════════════════════════════════════════════════════════

local function DestroyAll()
    if MainConnection then MainConnection:Disconnect() end
    
    for _, conn in pairs(Connections) do
        pcall(function() conn:Disconnect() end)
    end
    
    DisableSilentAim()
    DisableNoClip()
    DisableHitbox()
    DisableSpeed()
    DisableGunMods()
    DestroyDrawings()
    DestroyESP()
    
    if ScreenGui then ScreenGui:Destroy() end
    
    _G.SAVAGE_V82 = nil
end

_G.SAVAGE_V82 = true
_G.SAVAGE_V82_CLEANUP = DestroyAll

-- ═══════════════════════════════════════════════════════════════
--                    INICIALIZAÇÃO
-- ═══════════════════════════════════════════════════════════════

local function Initialize()
    print("═══════════════════════════════════════════════════")
    print("       SAVAGECHEATS_ AIMBOT UNIVERSAL v8.2")
    print("═══════════════════════════════════════════════════")
    print("Jogo: " .. GameName)
    
    CreateUI()
    CreateDrawings()
    InitESP()
    MainLoop()
    
    LocalPlayer.CharacterAdded:Connect(function(char)
        task.wait(1)
        
        if Config.NoClipEnabled then EnableNoClip() end
        if Config.SpeedEnabled then EnableSpeed() end
        if Config.RapidFireEnabled or Config.InfiniteAmmoEnabled then
            ModifiedGuns = {}
            ApplyGunMods()
        end
        
        if IsPrisonLife then
            NoClipBypassApplied = false
            ApplyPrisonLifeBypass()
        end
        
        -- Reconectar eventos de armas
        if char then
            char.ChildAdded:Connect(function(child)
                if child:IsA("Tool") then
                    task.wait(0.1)
                    ModifyGun(child)
                end
            end)
        end
    end)
    
    print("═══════════════════════════════════════════════════")
    print("✓ Carregado! Clique no botão 'S' vermelho")
    print("═══════════════════════════════════════════════════")
end

Initialize()
