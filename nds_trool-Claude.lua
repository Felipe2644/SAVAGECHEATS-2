--[[
    ╔═══════════════════════════════════════════════════════════════════════════╗
    ║                     NDS TROLL HUB v7.5 - SERVER MAGNET                  ║
    ║                   Natural Disaster Survival                             ║
    ║                 Compatível com Executores Mobile                        ║
    ╚═══════════════════════════════════════════════════════════════════════════╝
--]]

-- HELPER DE CRIAÇÃO DE INSTÂNCIAS
local function Create(className, props)
    local inst = Instance.new(className)
    local children = props.Children
    props.Children = nil
    local parent = props.Parent
    props.Parent = nil
    for k, v in pairs(props) do
        inst[k] = v
    end
    if children then
        for _, child in ipairs(children) do
            child.Parent = inst
        end
    end
    if parent then inst.Parent = parent end
    return inst
end

-- SERVIÇOS
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- CONFIGURAÇÃO
local Config = {
    OrbitRadius = 25,
    OrbitSpeed = 2,
    OrbitHeight = 5,
    MagnetForce = 500,
    SpinRadius = 15,
    SpinSpeed = 4,
    FlySpeed = 60,
    SpeedMultiplier = 3,
    ThrottleInterval = 0.05,
    OrbitRecaptureInterval = 0.3,
    OrbitResponsiveness = 400,
    DefaultResponsiveness = 300,
    RecaptureInterval = 1,
    SkyLiftHeight = 3000,
    SkyLiftForce = 5000,
    SkyLiftVelocity = 500,
}

-- ESTADO
local State = {
    SelectedPlayer = nil,
    Magnet = false,
    Orbit = false,
    Blackhole = false,
    PartRain = false,
    Cage = false,
    Spin = false,
    HatFling = false,
    BodyFling = false,
    Launch = false,
    SlowPlayer = false,
    GodMode = false,
    Fly = false,
    View = false,
    Noclip = false,
    Speed = false,
    ESP = false,
    Telekinesis = false,
    SkyLift = false,
    ServerMagnet = false,
}

local Connections = {}
local CreatedObjects = {}
local TrackedParts = {}
local AnchorPart = nil
local MainAttachment = nil
local TelekinesisTarget = nil
local TelekinesisDistance = 15
local espObjects = {}
local originalSpeed = 16

-- FUNÇÕES UTILITÁRIAS

local function GetCharacter()
    return LocalPlayer.Character
end

local function GetHRP()
    local char = GetCharacter()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function GetHumanoid()
    local char = GetCharacter()
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function Notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 3
        })
    end)
end

-- FIX: Match exato no início do prefixo (evita "ServerMagnet" casar com "Magnet")
local function ClearConnections(prefix)
    for name, conn in pairs(Connections) do
        if prefix then
            if name:sub(1, #prefix) == prefix then
                pcall(function() conn:Disconnect() end)
                Connections[name] = nil
            end
        else
            pcall(function() conn:Disconnect() end)
        end
    end
    if not prefix then Connections = {} end
end

local function TrackObject(obj)
    CreatedObjects[#CreatedObjects + 1] = obj
end

local function ClearCreatedObjects()
    for i, obj in ipairs(CreatedObjects) do
        pcall(function() obj:Destroy() end)
        CreatedObjects[i] = nil
    end
    CreatedObjects = {}
end

-- SISTEMA DE PARTES UNIFICADO

local function GetPlayerCharacters()
    local chars = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            chars[player.Character] = true
        end
    end
    return chars
end

local function IsPartOfPlayer(part, charCache)
    local parent = part.Parent
    while parent and parent ~= Workspace do
        if charCache[parent] then return true end
        parent = parent.Parent
    end
    return false
end

local function StripExternalControls(part)
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("AlignPosition") or child:IsA("AlignOrientation") or
           child:IsA("BodyPosition") or child:IsA("BodyVelocity") or
           child:IsA("BodyForce") or child:IsA("BodyGyro") or
           child:IsA("VectorForce") or child:IsA("LineForce") or
           child:IsA("BodyAngularVelocity") or child:IsA("BodyThrust") or
           child:IsA("RocketPropulsion") or child:IsA("Torque") then
            pcall(function() child:Destroy() end)
        end
    end
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("Attachment") and not child.Name:find("_NDS") then
            pcall(function() child:Destroy() end)
        end
    end
end

local function PreparePart(part)
    part:SetAttribute("_NDSOrigCanCollide", part.CanCollide)
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    pcall(function()
        part.CustomPhysicalProperties = PhysicalProperties.new(0, 0, 0, 0, 0)
    end)
end

local function GetUnanchoredParts()
    local parts = {}
    local charCache = GetPlayerCharacters()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") and not obj.Anchored
           and not obj.Name:find("_NDS")
           and obj.Name ~= "Terrain"
           and not IsPartOfPlayer(obj, charCache) then
            parts[#parts + 1] = obj
        end
    end
    return parts
end

local function GetMyAccessories()
    local handles = {}
    local char = GetCharacter()
    if char then
        for _, acc in ipairs(char:GetChildren()) do
            if acc:IsA("Accessory") then
                local handle = acc:FindFirstChild("Handle")
                if handle then handles[#handles + 1] = handle end
            end
        end
    end
    return handles
end

local function GetAvailableParts()
    local parts = GetUnanchoredParts()
    if #parts < 5 then
        for _, h in ipairs(GetMyAccessories()) do
            parts[#parts + 1] = h
        end
    end
    return parts
end

-- CONTROLE UNIFICADO DE PARTES (substitui 3 funções duplicadas)
local function SetupPartControl(part, targetAttachment, overrides)
    if not part or not part:IsA("BasePart") or part.Anchored then return end
    if part.Name:find("_NDS") then return end

    local charCache = GetPlayerCharacters()
    if IsPartOfPlayer(part, charCache) then return end

    pcall(function()
        local oldAlign = part:FindFirstChild("_NDSAlign")
        local oldAttach = part:FindFirstChild("_NDSAttach")
        if oldAlign then oldAlign:Destroy() end
        if oldAttach then oldAttach:Destroy() end
        StripExternalControls(part)
    end)

    PreparePart(part)

    local attach = Create("Attachment", {
        Name = "_NDSAttach",
        Parent = part
    })

    local resp = (overrides and overrides.Responsiveness) or Config.DefaultResponsiveness
    local maxVel = (overrides and overrides.MaxVelocity) or math.huge

    local align = Create("AlignPosition", {
        Name = "_NDSAlign",
        MaxForce = math.huge,
        MaxVelocity = maxVel,
        Responsiveness = resp,
        Attachment0 = attach,
        Attachment1 = targetAttachment or MainAttachment,
        Parent = part
    })

    return attach, align
end

local function CleanPartControl(part)
    if not part then return end
    pcall(function()
        local align = part:FindFirstChild("_NDSAlign")
        local attach = part:FindFirstChild("_NDSAttach")
        local torque = part:FindFirstChild("_NDSTorque")
        if align then align:Destroy() end
        if attach then attach:Destroy() end
        if torque then torque:Destroy() end
        local orig = part:GetAttribute("_NDSOrigCanCollide")
        part.CanCollide = (orig ~= nil) and orig or true
    end)
end

local function CleanTrackedParts(key)
    if TrackedParts[key] then
        for part in pairs(TrackedParts[key]) do
            CleanPartControl(part)
        end
        TrackedParts[key] = nil
    end
end

local function DisableAllFunctions()
    for key, _ in pairs(State) do
        if key ~= "SelectedPlayer" then
            State[key] = false
        end
    end
    ClearConnections()
    ClearCreatedObjects()

    for key in pairs(TrackedParts) do
        CleanTrackedParts(key)
    end
    TrackedParts = {}

    -- Safety sweep
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            pcall(function()
                local align = obj:FindFirstChild("_NDSAlign")
                local attach = obj:FindFirstChild("_NDSAttach")
                local torque = obj:FindFirstChild("_NDSTorque")
                local sky = obj:FindFirstChild("_NDSSkyForce")
                local sa = obj:FindFirstChild("_NDSServerAlign")
                local sat = obj:FindFirstChild("_NDSServerAttach")
                if align then align:Destroy() end
                if attach then attach:Destroy() end
                if torque then torque:Destroy() end
                if sky then sky:Destroy() end
                if sa then sa:Destroy() end
                if sat then sat:Destroy() end
            end)
        end
    end

    local hrp = GetHRP()
    if hrp then
        pcall(function()
            hrp.Velocity = Vector3.zero
            hrp.RotVelocity = Vector3.zero
        end)
    end
end

-- SISTEMA DE REDE
local function SetupNetworkControl()
    if AnchorPart then pcall(function() AnchorPart:Destroy() end) end

    AnchorPart = Create("Part", {
        Name = "_NDSAnchor",
        Size = Vector3.new(1, 1, 1),
        Transparency = 1,
        CanCollide = false,
        Anchored = true,
        CFrame = CFrame.new(0, 10000, 0),
        Parent = Workspace
    })
    TrackObject(AnchorPart)

    MainAttachment = Create("Attachment", {
        Name = "MainAttach",
        Parent = AnchorPart
    })

    task.spawn(function()
        local hasSHP = typeof(sethiddenproperty) == "function"
        local hasSR = typeof(setsimulationradius) == "function"
        if not hasSHP and not hasSR then return end
        while true do
            if hasSHP then pcall(sethiddenproperty, LocalPlayer, "SimulationRadius", math.huge) end
            if hasSR then pcall(setsimulationradius, math.huge, math.huge) end
            task.wait(0.5)
        end
    end)
end

-- VALIDAÇÃO DE ALVO
local function ValidateTarget()
    if not State.SelectedPlayer or not State.SelectedPlayer.Character then
        return nil
    end
    return State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
end

-- ═══════════════════════════════════════════
-- FUNÇÕES DE TROLAGEM
-- ═══════════════════════════════════════════

local function ToggleMagnet()
    State.Magnet = not State.Magnet
    if State.Magnet then
        if not ValidateTarget() then
            State.Magnet = false
            return false, "Selecione um player!"
        end

        TrackedParts.Magnet = {}
        for _, part in ipairs(GetAvailableParts()) do
            SetupPartControl(part, MainAttachment)
            TrackedParts.Magnet[part] = true
        end

        Connections.MagnetNew = Workspace.DescendantAdded:Connect(function(obj)
            if State.Magnet and obj:IsA("BasePart") then
                task.defer(function()
                    if not TrackedParts.Magnet[obj] then
                        SetupPartControl(obj, MainAttachment)
                        TrackedParts.Magnet[obj] = true
                    end
                end)
            end
        end)

        Connections.MagnetUpdate = RunService.Heartbeat:Connect(function()
            if State.Magnet and State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp and AnchorPart then
                    AnchorPart.CFrame = hrp.CFrame
                end
            end
        end)

        task.spawn(function()
            while State.Magnet do
                task.wait(Config.RecaptureInterval)
                if not State.Magnet then break end
                for part in pairs(TrackedParts.Magnet) do
                    if part and part.Parent then
                        if not part:FindFirstChild("_NDSAlign") then
                            SetupPartControl(part, MainAttachment)
                        end
                    else
                        TrackedParts.Magnet[part] = nil
                    end
                end
            end
        end)

        return true, "Ima ativado!"
    else
        ClearConnections("Magnet")
        CleanTrackedParts("Magnet")
        return false, "Ima desativado"
    end
end

local function ToggleOrbit()
    State.Orbit = not State.Orbit
    if State.Orbit then
        if not ValidateTarget() then
            State.Orbit = false
            return false, "Selecione um player!"
        end

        local angle = 0
        local parts = GetAvailableParts()
        local partData = {}
        local lastUpdate = 0
        TrackedParts.Orbit = {}

        for i, part in ipairs(parts) do
            local att = Create("Attachment", {
                Name = "_NDSOrbitAtt" .. i,
                Parent = AnchorPart
            })
            TrackObject(att)
            SetupPartControl(part, att, {Responsiveness = Config.OrbitResponsiveness})
            TrackedParts.Orbit[part] = true
            partData[i] = {part = part, attachment = att, baseAngle = (i / #parts) * math.pi * 2}
        end

        Connections.OrbitUpdate = RunService.Heartbeat:Connect(function(dt)
            angle = angle + dt * Config.OrbitSpeed
            local now = tick()
            if now - lastUpdate < Config.ThrottleInterval then return end
            lastUpdate = now

            if State.Orbit and State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local pos = hrp.Position
                    for _, data in ipairs(partData) do
                        if data.part and data.part.Parent and data.attachment then
                            local a = data.baseAngle + angle
                            data.attachment.WorldPosition = pos + Vector3.new(
                                math.cos(a) * Config.OrbitRadius,
                                Config.OrbitHeight + math.sin(a * 2) * 2,
                                math.sin(a) * Config.OrbitRadius
                            )
                        end
                    end
                end
            end
        end)

        task.spawn(function()
            while State.Orbit do
                task.wait(Config.OrbitRecaptureInterval)
                if not State.Orbit then break end
                for _, data in ipairs(partData) do
                    if data.part and data.part.Parent then
                        if not data.part:FindFirstChild("_NDSAlign") then
                            SetupPartControl(data.part, data.attachment, {Responsiveness = Config.OrbitResponsiveness})
                        end
                    end
                end
            end
        end)

        return true, "Orbit ativado!"
    else
        ClearConnections("Orbit")
        CleanTrackedParts("Orbit")
        return false, "Orbit desativado"
    end
end

local function ToggleBlackhole()
    State.Blackhole = not State.Blackhole
    if State.Blackhole then
        if not ValidateTarget() then
            State.Blackhole = false
            return false, "Selecione um player!"
        end

        local angle = 0
        local lastUpdate = 0
        TrackedParts.Blackhole = {}

        for _, part in ipairs(GetAvailableParts()) do
            SetupPartControl(part, MainAttachment)
            TrackedParts.Blackhole[part] = true
            local att = part:FindFirstChild("_NDSAttach")
            if att then
                Create("Torque", {
                    Name = "_NDSTorque",
                    Torque = Vector3.new(50000, 50000, 50000),
                    Attachment0 = att,
                    Parent = part
                })
            end
        end

        Connections.BlackholeUpdate = RunService.Heartbeat:Connect(function(dt)
            angle = angle + dt * 5
            local now = tick()
            if now - lastUpdate < Config.ThrottleInterval then return end
            lastUpdate = now

            if State.Blackhole and State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp and AnchorPart then
                    local spiral = Vector3.new(math.cos(angle) * 2, math.sin(angle * 2), math.sin(angle) * 2)
                    AnchorPart.CFrame = CFrame.new(hrp.Position + spiral)
                end
            end
        end)

        return true, "Blackhole ativado!"
    else
        ClearConnections("Blackhole")
        CleanTrackedParts("Blackhole")
        return false, "Blackhole desativado"
    end
end

local function TogglePartRain()
    State.PartRain = not State.PartRain
    if State.PartRain then
        if not ValidateTarget() then
            State.PartRain = false
            return false, "Selecione um player!"
        end

        TrackedParts.PartRain = {}
        for _, part in ipairs(GetAvailableParts()) do
            SetupPartControl(part, MainAttachment)
            TrackedParts.PartRain[part] = true
        end

        local lastUpdate = 0
        Connections.PartRainUpdate = RunService.Heartbeat:Connect(function()
            local now = tick()
            if now - lastUpdate < Config.ThrottleInterval then return end
            lastUpdate = now

            if State.PartRain and State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp and AnchorPart then
                    local offset = Vector3.new(math.random(-15, 15), 50, math.random(-15, 15))
                    AnchorPart.CFrame = CFrame.new(hrp.Position + offset)
                end
            end
        end)

        return true, "Part Rain ativado!"
    else
        ClearConnections("PartRain")
        CleanTrackedParts("PartRain")
        return false, "Part Rain desativado"
    end
end

local function ToggleSpin()
    State.Spin = not State.Spin
    if State.Spin then
        if not ValidateTarget() then
            State.Spin = false
            return false, "Selecione um player!"
        end

        local angle = 0
        local parts = GetAvailableParts()
        local partData = {}
        local lastUpdate = 0
        TrackedParts.Spin = {}

        for i, part in ipairs(parts) do
            local att = Create("Attachment", {
                Name = "_NDSSpinAtt" .. i,
                Parent = AnchorPart
            })
            TrackObject(att)
            SetupPartControl(part, att)
            TrackedParts.Spin[part] = true
            partData[i] = {part = part, attachment = att, baseAngle = (i / #parts) * math.pi * 2}
        end

        Connections.SpinUpdate = RunService.Heartbeat:Connect(function(dt)
            angle = angle + dt * Config.SpinSpeed
            local now = tick()
            if now - lastUpdate < Config.ThrottleInterval then return end
            lastUpdate = now

            if State.Spin and State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local pos = hrp.Position
                    for _, data in ipairs(partData) do
                        if data.part and data.part.Parent and data.attachment then
                            local a = data.baseAngle + angle
                            data.attachment.WorldPosition = pos + Vector3.new(
                                math.cos(a) * Config.SpinRadius, 1, math.sin(a) * Config.SpinRadius
                            )
                        end
                    end
                end
            end
        end)

        return true, "Spin ativado!"
    else
        ClearConnections("Spin")
        CleanTrackedParts("Spin")
        return false, "Spin desativado"
    end
end

local function ToggleCage()
    State.Cage = not State.Cage
    if State.Cage then
        if not ValidateTarget() then
            State.Cage = false
            return false, "Selecione um player!"
        end

        local parts = GetAvailableParts()
        local partData = {}
        local cageRadius = 4
        local lastUpdate = 0
        TrackedParts.Cage = {}

        for i, part in ipairs(parts) do
            if i > 24 then break end
            local att = Create("Attachment", {
                Name = "_NDSCageAtt" .. i,
                Parent = AnchorPart
            })
            TrackObject(att)
            SetupPartControl(part, att)
            TrackedParts.Cage[part] = true

            local layer = math.floor((i - 1) / 8)
            local indexInLayer = (i - 1) % 8
            local angle = (indexInLayer / 8) * math.pi * 2
            partData[i] = {attachment = att, angle = angle, height = (layer - 1) * 3}
        end

        Connections.CageUpdate = RunService.Heartbeat:Connect(function()
            local now = tick()
            if now - lastUpdate < Config.ThrottleInterval then return end
            lastUpdate = now

            if State.Cage and State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local pos = hrp.Position
                    for _, data in pairs(partData) do
                        if data.attachment then
                            data.attachment.WorldPosition = pos + Vector3.new(
                                math.cos(data.angle) * cageRadius,
                                data.height,
                                math.sin(data.angle) * cageRadius
                            )
                        end
                    end
                end
            end
        end)

        return true, "Cage ativado!"
    else
        ClearConnections("Cage")
        CleanTrackedParts("Cage")
        return false, "Cage desativado"
    end
end

local function ToggleSkyLift()
    State.SkyLift = not State.SkyLift
    if State.SkyLift then
        local parts = GetAvailableParts()
        TrackedParts.SkyLift = {}

        for _, part in ipairs(parts) do
            pcall(function()
                StripExternalControls(part)
                PreparePart(part)
                part.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 0, 0)

                local bf = Create("BodyForce", {
                    Name = "_NDSSkyForce",
                    Force = Vector3.new(0, part:GetMass() * Config.SkyLiftForce, 0),
                    Parent = part
                })
                TrackObject(bf)
                part.AssemblyLinearVelocity = Vector3.new(0, Config.SkyLiftVelocity, 0)
                TrackedParts.SkyLift[part] = true
            end)
        end

        task.spawn(function()
            while State.SkyLift do
                task.wait(0.1)
                if not State.SkyLift then break end
                for part in pairs(TrackedParts.SkyLift) do
                    if part and part.Parent then
                        pcall(function()
                            if not part:FindFirstChild("_NDSSkyForce") then
                                StripExternalControls(part)
                                local bf = Create("BodyForce", {
                                    Name = "_NDSSkyForce",
                                    Force = Vector3.new(0, part:GetMass() * Config.SkyLiftForce, 0),
                                    Parent = part
                                })
                                TrackObject(bf)
                            end
                            if part.Position.Y < Config.SkyLiftHeight then
                                part.AssemblyLinearVelocity = Vector3.new(0, Config.SkyLiftVelocity, 0)
                            end
                        end)
                    else
                        TrackedParts.SkyLift[part] = nil
                    end
                end
            end
        end)

        Notify("Sky Lift", "Partes sendo levantadas!", 3)
        return true, "Sky Lift ativado!"
    else
        for part in pairs(TrackedParts.SkyLift or {}) do
            if part and part.Parent then
                local sf = part:FindFirstChild("_NDSSkyForce")
                if sf then pcall(function() sf:Destroy() end) end
            end
        end
        TrackedParts.SkyLift = nil
        return false, "Sky Lift desativado"
    end
end

local function ToggleServerMagnet()
    State.ServerMagnet = not State.ServerMagnet
    if State.ServerMagnet then
        local function GetTargetPlayers()
            local targets = {}
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character then
                    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then targets[#targets + 1] = player end
                end
            end
            return targets
        end

        local playerAttachments = {}
        local partAssignments = {}
        TrackedParts.ServerMagnet = {}

        local function SetupPlayerAttachments()
            for _, att in pairs(playerAttachments) do
                if att and att.Parent then pcall(function() att:Destroy() end) end
            end
            playerAttachments = {}
            for i, player in ipairs(GetTargetPlayers()) do
                local att = Create("Attachment", {
                    Name = "_NDSServerMagnetAtt" .. i,
                    Parent = AnchorPart
                })
                TrackObject(att)
                playerAttachments[player] = att
            end
        end

        local function SetupSMPartControl(part, targetAtt)
            if not part or not part:IsA("BasePart") or part.Anchored then return end
            if part.Name:find("_NDS") then return end
            local charCache = GetPlayerCharacters()
            if IsPartOfPlayer(part, charCache) then return end

            pcall(function()
                local old1 = part:FindFirstChild("_NDSServerAlign")
                local old2 = part:FindFirstChild("_NDSServerAttach")
                if old1 then old1:Destroy() end
                if old2 then old2:Destroy() end
                StripExternalControls(part)
            end)

            PreparePart(part)

            local attach = Create("Attachment", {Name = "_NDSServerAttach", Parent = part})
            Create("AlignPosition", {
                Name = "_NDSServerAlign",
                MaxForce = math.huge,
                MaxVelocity = math.huge,
                Responsiveness = Config.DefaultResponsiveness,
                Attachment0 = attach,
                Attachment1 = targetAtt,
                Parent = part
            })
        end

        local function DistributeParts()
            local targets = GetTargetPlayers()
            if #targets == 0 then return end
            SetupPlayerAttachments()

            local parts = GetAvailableParts()
            local idx = 1
            for _, part in ipairs(parts) do
                if not TrackedParts.ServerMagnet[part] then
                    local tp = targets[idx]
                    local att = playerAttachments[tp]
                    if att then
                        SetupSMPartControl(part, att)
                        partAssignments[part] = tp
                        TrackedParts.ServerMagnet[part] = true
                    end
                    idx = idx + 1
                    if idx > #targets then idx = 1 end
                end
            end
        end

        DistributeParts()

        Connections.ServerMagnetNew = Workspace.DescendantAdded:Connect(function(obj)
            if State.ServerMagnet and obj:IsA("BasePart") then
                task.defer(function()
                    if not TrackedParts.ServerMagnet[obj] then
                        local targets = GetTargetPlayers()
                        if #targets > 0 then
                            local partCounts = {}
                            for _, p in ipairs(targets) do partCounts[p] = 0 end
                            for part, player in pairs(partAssignments) do
                                if part and part.Parent and partCounts[player] then
                                    partCounts[player] = partCounts[player] + 1
                                end
                            end
                            local minP, minC = targets[1], math.huge
                            for p, c in pairs(partCounts) do
                                if c < minC then minC = c; minP = p end
                            end
                            local att = playerAttachments[minP]
                            if att then
                                SetupSMPartControl(obj, att)
                                partAssignments[obj] = minP
                                TrackedParts.ServerMagnet[obj] = true
                            end
                        end
                    end
                end)
            end
        end)

        Connections.ServerMagnetUpdate = RunService.Heartbeat:Connect(function()
            if State.ServerMagnet then
                for player, att in pairs(playerAttachments) do
                    if player and player.Character and att and att.Parent then
                        local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                        if hrp then att.WorldPosition = hrp.Position end
                    end
                end
            end
        end)

        task.spawn(function()
            while State.ServerMagnet do
                task.wait(Config.RecaptureInterval)
                if not State.ServerMagnet then break end

                local needsRedist = false
                for player in pairs(playerAttachments) do
                    if not player or not player.Parent or not player.Character then
                        needsRedist = true; break
                    end
                end
                if not needsRedist then
                    for _, player in ipairs(GetTargetPlayers()) do
                        if not playerAttachments[player] then needsRedist = true; break end
                    end
                end

                if needsRedist then
                    partAssignments = {}
                    TrackedParts.ServerMagnet = {}
                    DistributeParts()
                else
                    for part, player in pairs(partAssignments) do
                        if part and part.Parent then
                            if not part:FindFirstChild("_NDSServerAlign") then
                                local att = playerAttachments[player]
                                if att then SetupSMPartControl(part, att) end
                            end
                        else
                            partAssignments[part] = nil
                            TrackedParts.ServerMagnet[part] = nil
                        end
                    end
                end
            end
        end)

        local tc = #GetTargetPlayers()
        Notify("Server Magnet", "Atacando " .. tc .. " players!", 3)
        return true, "Server Magnet ativado! (" .. tc .. " alvos)"
    else
        ClearConnections("ServerMagnet")
        for part in pairs(TrackedParts.ServerMagnet or {}) do
            if part and part.Parent then
                pcall(function()
                    local a = part:FindFirstChild("_NDSServerAlign")
                    local t = part:FindFirstChild("_NDSServerAttach")
                    if a then a:Destroy() end
                    if t then t:Destroy() end
                    local orig = part:GetAttribute("_NDSOrigCanCollide")
                    part.CanCollide = (orig ~= nil) and orig or true
                end)
            end
        end
        TrackedParts.ServerMagnet = nil
        return false, "Server Magnet desativado"
    end
end

local function ToggleHatFling()
    State.HatFling = not State.HatFling
    if State.HatFling then
        if not ValidateTarget() then
            State.HatFling = false
            return false, "Selecione um player!"
        end
        local angle = 0
        Connections.HatFlingUpdate = RunService.Heartbeat:Connect(function(dt)
            if State.HatFling and State.SelectedPlayer and State.SelectedPlayer.Character then
                local tHRP = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                local myHRP = GetHRP()
                if tHRP and myHRP then
                    angle = angle + dt * 30
                    myHRP.CFrame = CFrame.new(tHRP.Position + Vector3.new(math.cos(angle) * 3, 0, math.sin(angle) * 3))
                    myHRP.Velocity = Vector3.new(9e5, 9e5, 9e5)
                    myHRP.RotVelocity = Vector3.new(9e5, 9e5, 9e5)
                end
            end
        end)
        return true, "Hat Fling ativado!"
    else
        ClearConnections("HatFling")
        local hrp = GetHRP()
        if hrp then hrp.Velocity = Vector3.zero; hrp.RotVelocity = Vector3.zero end
        return false, "Hat Fling desativado"
    end
end

local function ToggleBodyFling()
    State.BodyFling = not State.BodyFling
    if State.BodyFling then
        if not ValidateTarget() then
            State.BodyFling = false
            return false, "Selecione um player!"
        end
        Connections.BodyFlingUpdate = RunService.Heartbeat:Connect(function()
            if State.BodyFling and State.SelectedPlayer and State.SelectedPlayer.Character then
                local tHRP = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                local myHRP = GetHRP()
                if tHRP and myHRP then
                    myHRP.CFrame = tHRP.CFrame
                    myHRP.Velocity = Vector3.new(9e7, 9e7, 9e7)
                end
            end
        end)
        return true, "Body Fling ativado!"
    else
        ClearConnections("BodyFling")
        local hrp = GetHRP()
        if hrp then hrp.Velocity = Vector3.zero end
        return false, "Body Fling desativado"
    end
end

local function ToggleLaunch()
    State.Launch = not State.Launch
    if State.Launch then
        if not ValidateTarget() then
            State.Launch = false
            return false, "Selecione um player!"
        end
        TrackedParts.Launch = {}
        for _, part in ipairs(GetAvailableParts()) do
            SetupPartControl(part, MainAttachment)
            TrackedParts.Launch[part] = true
        end
        Connections.LaunchUpdate = RunService.Heartbeat:Connect(function()
            if State.Launch and State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp and AnchorPart then
                    AnchorPart.CFrame = CFrame.new(hrp.Position + Vector3.new(0, -3, 0))
                end
            end
        end)
        return true, "Launch ativado!"
    else
        ClearConnections("Launch")
        CleanTrackedParts("Launch")
        return false, "Launch desativado"
    end
end

local function ToggleSlowPlayer()
    State.SlowPlayer = not State.SlowPlayer
    if State.SlowPlayer then
        if not ValidateTarget() then
            State.SlowPlayer = false
            return false, "Selecione um player!"
        end
        local slowParts = {}
        for i = 1, 6 do
            local part = Create("Part", {
                Name = "_NDSSlowPart",
                Size = Vector3.new(3, 3, 3),
                Transparency = 0.9,
                CanCollide = true,
                Anchored = false,
                Massless = false,
                CustomPhysicalProperties = PhysicalProperties.new(100, 1, 0, 1, 1),
                Parent = Workspace
            })
            slowParts[i] = part
            TrackObject(part)
        end

        local lastUpdate = 0
        Connections.SlowUpdate = RunService.Heartbeat:Connect(function()
            local now = tick()
            if now - lastUpdate < Config.ThrottleInterval then return end
            lastUpdate = now

            if State.SlowPlayer and State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    for i, part in ipairs(slowParts) do
                        if part and part.Parent then
                            local a = (i / #slowParts) * math.pi * 2
                            part.CFrame = CFrame.new(hrp.Position + Vector3.new(math.cos(a) * 2, 0, math.sin(a) * 2))
                        end
                    end
                end
            end
        end)

        return true, "Slow ativado!"
    else
        ClearConnections("Slow")
        return false, "Slow desativado"
    end
end

-- ═══════════════════════════════════════════
-- UTILIDADES
-- ═══════════════════════════════════════════

local function ToggleGodMode()
    State.GodMode = not State.GodMode
    if State.GodMode then
        local char = GetCharacter()
        local humanoid = GetHumanoid()
        if not char or not humanoid then
            State.GodMode = false
            return false, "Erro!"
        end

        local ff = Create("ForceField", {
            Name = "_NDSForceField",
            Visible = false,
            Parent = char
        })
        TrackObject(ff)

        Connections.GodModeHealth = humanoid.HealthChanged:Connect(function()
            if State.GodMode then humanoid.Health = humanoid.MaxHealth end
        end)

        Connections.GodModeHeartbeat = RunService.Heartbeat:Connect(function()
            if State.GodMode then
                local hum = GetHumanoid()
                if hum then hum.Health = hum.MaxHealth end
                local c = GetCharacter()
                if c and not c:FindFirstChild("_NDSForceField") then
                    Create("ForceField", {Name = "_NDSForceField", Visible = false, Parent = c})
                end
            end
        end)

        pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
        return true, "God Mode ativado!"
    else
        ClearConnections("GodMode")
        local char = GetCharacter()
        if char then
            local ff = char:FindFirstChild("_NDSForceField")
            if ff then ff:Destroy() end
        end
        local humanoid = GetHumanoid()
        if humanoid then
            pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true) end)
        end
        return false, "God Mode desativado"
    end
end

local function ToggleView()
    State.View = not State.View
    if State.View then
        if not State.SelectedPlayer then
            State.View = false
            return false, "Selecione um player!"
        end
        local targetPlayer = State.SelectedPlayer

        local function UpdateCameraTarget()
            if not State.View then return end
            if not targetPlayer or not targetPlayer.Parent then
                State.View = false
                Camera.CameraSubject = GetHumanoid()
                ClearConnections("View")
                Notify("View", "Player saiu do jogo", 2)
                return
            end
            local tc = targetPlayer.Character
            if tc then
                local th = tc:FindFirstChildOfClass("Humanoid")
                if th then Camera.CameraSubject = th end
            end
        end

        UpdateCameraTarget()

        Connections.ViewCharAdded = targetPlayer.CharacterAdded:Connect(function()
            task.wait(0.1)
            UpdateCameraTarget()
        end)

        Connections.ViewPlayerRemoving = Players.PlayerRemoving:Connect(function(player)
            if player == targetPlayer then
                State.View = false
                Camera.CameraSubject = GetHumanoid()
                ClearConnections("View")
                Notify("View", "Player saiu do jogo", 2)
            end
        end)

        task.spawn(function()
            while State.View do
                task.wait(0.5)
                if State.View and targetPlayer and targetPlayer.Parent then UpdateCameraTarget() end
            end
        end)

        return true, "View ativado em " .. targetPlayer.Name
    else
        ClearConnections("View")
        local myHum = GetHumanoid()
        if myHum then Camera.CameraSubject = myHum end
        return false, "View desativado"
    end
end

local function ToggleNoclip()
    State.Noclip = not State.Noclip
    if State.Noclip then
        Connections.NoclipUpdate = RunService.Stepped:Connect(function()
            if State.Noclip then
                local char = GetCharacter()
                if char then
                    for _, part in ipairs(char:GetDescendants()) do
                        if part:IsA("BasePart") then part.CanCollide = false end
                    end
                end
            end
        end)
        return true, "Noclip ativado!"
    else
        ClearConnections("Noclip")
        return false, "Noclip desativado"
    end
end

local function ToggleSpeed()
    State.Speed = not State.Speed
    if State.Speed then
        local humanoid = GetHumanoid()
        if humanoid then
            originalSpeed = humanoid.WalkSpeed
            humanoid.WalkSpeed = originalSpeed * Config.SpeedMultiplier
        end
        Connections.SpeedUpdate = RunService.Heartbeat:Connect(function()
            if State.Speed then
                local h = GetHumanoid()
                if h and h.WalkSpeed < originalSpeed * Config.SpeedMultiplier then
                    h.WalkSpeed = originalSpeed * Config.SpeedMultiplier
                end
            end
        end)
        return true, "Speed ativado!"
    else
        ClearConnections("Speed")
        local humanoid = GetHumanoid()
        if humanoid then humanoid.WalkSpeed = originalSpeed end
        return false, "Speed desativado"
    end
end

local function ToggleESP()
    State.ESP = not State.ESP
    if State.ESP then
        local function createESP(player)
            if player == LocalPlayer or not player.Character then return end
            local hl = Create("Highlight", {
                Name = "_NDSESP",
                FillColor = Color3.fromRGB(255, 0, 0),
                OutlineColor = Color3.fromRGB(255, 255, 255),
                FillTransparency = 0.5,
                DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                Adornee = player.Character,
                Parent = player.Character
            })
            espObjects[player] = hl
        end

        for _, player in ipairs(Players:GetPlayers()) do
            if player.Character then createESP(player) end
            Connections["ESPChar_" .. player.Name] = player.CharacterAdded:Connect(function()
                if State.ESP then task.wait(0.5); createESP(player) end
            end)
        end

        Connections.ESPPlayerAdded = Players.PlayerAdded:Connect(function(player)
            player.CharacterAdded:Connect(function()
                if State.ESP then task.wait(0.5); createESP(player) end
            end)
        end)

        return true, "ESP ativado!"
    else
        for _, hl in pairs(espObjects) do pcall(function() hl:Destroy() end) end
        espObjects = {}
        ClearConnections("ESP")
        return false, "ESP desativado"
    end
end

local function TeleportToPlayer()
    if not State.SelectedPlayer or not State.SelectedPlayer.Character then
        return false, "Selecione um player!"
    end
    local hrp = GetHRP()
    local tHRP = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
    if hrp and tHRP then
        hrp.CFrame = tHRP.CFrame * CFrame.new(0, 0, 3)
        return true, "Teleportado!"
    end
    return false, "Erro!"
end

local function ToggleTelekinesis()
    State.Telekinesis = not State.Telekinesis
    if State.Telekinesis then
        local indicator = Create("Part", {
            Name = "_NDSTelekIndicator",
            Size = Vector3.new(0.5, 0.5, 0.5),
            Shape = Enum.PartType.Ball,
            Material = Enum.Material.Neon,
            Color = Color3.fromRGB(138, 43, 226),
            Transparency = 0.3,
            CanCollide = false,
            Anchored = true,
            Parent = Workspace
        })
        TrackObject(indicator)

        Connections.TelekSelect = UserInputService.InputBegan:Connect(function(input)
            if not State.Telekinesis then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                local ray = Camera:ScreenPointToRay(input.Position.X, input.Position.Y)
                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = {GetCharacter()}
                local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, params)
                if result and result.Instance and result.Instance:IsA("BasePart") then
                    TelekinesisTarget = result.Instance
                    TelekinesisDistance = (result.Instance.Position - Camera.CFrame.Position).Magnitude
                    pcall(function() result.Instance.Anchored = false end)
                    SetupPartControl(result.Instance, MainAttachment)
                    Notify("Telecinese", "Objeto: " .. result.Instance.Name, 2)
                end
            end
        end)

        Connections.TelekMove = RunService.RenderStepped:Connect(function()
            if State.Telekinesis and TelekinesisTarget and TelekinesisTarget.Parent then
                local mousePos = UserInputService:GetMouseLocation()
                local ray = Camera:ScreenPointToRay(mousePos.X, mousePos.Y)
                local targetPos = ray.Origin + ray.Direction * TelekinesisDistance
                if AnchorPart then AnchorPart.CFrame = CFrame.new(targetPos) end
                if indicator and indicator.Parent then indicator.CFrame = CFrame.new(targetPos) end
            end
        end)

        Connections.TelekScroll = UserInputService.InputChanged:Connect(function(input)
            if State.Telekinesis and input.UserInputType == Enum.UserInputType.MouseWheel then
                TelekinesisDistance = math.clamp(TelekinesisDistance + input.Position.Z * 5, 5, 100)
            end
        end)

        Connections.TelekRelease = UserInputService.InputBegan:Connect(function(input)
            if State.Telekinesis and input.UserInputType == Enum.UserInputType.MouseButton2 then
                if TelekinesisTarget then
                    CleanPartControl(TelekinesisTarget)
                    TelekinesisTarget = nil
                    Notify("Telecinese", "Solto!", 1)
                end
            end
        end)

        return true, "Telecinese ativada!"
    else
        ClearConnections("Telek")
        if TelekinesisTarget then CleanPartControl(TelekinesisTarget); TelekinesisTarget = nil end
        return false, "Telecinese desativada"
    end
end

-- ═══════════════════════════════════════════
-- FLY GUI V3
-- ═══════════════════════════════════════════

local FlyV3 = {GUI = nil, Loaded = false, Flying = false}

local function CreateFlyGuiV3()
    if FlyV3.GUI then FlyV3.GUI:Destroy() end
    FlyV3.Loaded = true

    local main = Create("ScreenGui", {
        Name = "NDSFlyGuiV3",
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        ResetOnSpawn = false,
        Parent = LocalPlayer:WaitForChild("PlayerGui")
    })
    FlyV3.GUI = main

    local Frame = Create("Frame", {
        BackgroundColor3 = Color3.fromRGB(163, 255, 137),
        BorderColor3 = Color3.fromRGB(103, 221, 213),
        Position = UDim2.new(0.1, 0, 0.38, 0),
        Size = UDim2.new(0, 190, 0, 57),
        Active = true,
        Draggable = true,
        Parent = main
    })

    local up = Create("TextButton", {Name="up", BackgroundColor3=Color3.fromRGB(79,255,152), Size=UDim2.new(0,44,0,28), Font=Enum.Font.SourceSans, Text="UP", TextColor3=Color3.new(0,0,0), TextSize=14, Parent=Frame})
    local down = Create("TextButton", {Name="down", BackgroundColor3=Color3.fromRGB(215,255,121), Position=UDim2.new(0,0,0.491,0), Size=UDim2.new(0,44,0,28), Font=Enum.Font.SourceSans, Text="DOWN", TextColor3=Color3.new(0,0,0), TextSize=14, Parent=Frame})
    local onof = Create("TextButton", {Name="onof", BackgroundColor3=Color3.fromRGB(255,249,74), Position=UDim2.new(0.703,0,0.491,0), Size=UDim2.new(0,56,0,28), Font=Enum.Font.SourceSans, Text="fly", TextColor3=Color3.new(0,0,0), TextSize=14, Parent=Frame})
    Create("TextLabel", {BackgroundColor3=Color3.fromRGB(242,60,255), Position=UDim2.new(0.469,0,0,0), Size=UDim2.new(0,100,0,28), Font=Enum.Font.SourceSans, Text="FLY GUI V3", TextColor3=Color3.new(0,0,0), TextScaled=true, Parent=Frame})
    local plus = Create("TextButton", {Name="plus", BackgroundColor3=Color3.fromRGB(133,145,255), Position=UDim2.new(0.232,0,0,0), Size=UDim2.new(0,45,0,28), Font=Enum.Font.SourceSans, Text="+", TextColor3=Color3.new(0,0,0), TextScaled=true, Parent=Frame})
    local speedLabel = Create("TextLabel", {Name="speed", BackgroundColor3=Color3.fromRGB(255,85,0), Position=UDim2.new(0.468,0,0.491,0), Size=UDim2.new(0,44,0,28), Font=Enum.Font.SourceSans, Text="1", TextColor3=Color3.new(0,0,0), TextScaled=true, Parent=Frame})
    local mine = Create("TextButton", {Name="mine", BackgroundColor3=Color3.fromRGB(123,255,247), Position=UDim2.new(0.232,0,0.491,0), Size=UDim2.new(0,45,0,29), Font=Enum.Font.SourceSans, Text="-", TextColor3=Color3.new(0,0,0), TextScaled=true, Parent=Frame})
    local closebutton = Create("TextButton", {Name="Close", BackgroundColor3=Color3.fromRGB(225,25,0), Size=UDim2.new(0,45,0,28), Font=Enum.Font.SourceSans, Text="X", TextSize=30, Position=UDim2.new(0,0,-1,27), TextColor3=Color3.new(1,1,1), Parent=Frame})
    local mini = Create("TextButton", {Name="minimize", BackgroundColor3=Color3.fromRGB(192,150,230), Size=UDim2.new(0,45,0,28), Font=Enum.Font.SourceSans, Text="-", TextSize=40, Position=UDim2.new(0,44,-1,27), TextColor3=Color3.new(0,0,0), Parent=Frame})
    local mini2 = Create("TextButton", {Name="minimize2", BackgroundColor3=Color3.fromRGB(192,150,230), Size=UDim2.new(0,45,0,28), Font=Enum.Font.SourceSans, Text="+", TextSize=40, Position=UDim2.new(0,44,-1,57), Visible=false, TextColor3=Color3.new(0,0,0), Parent=Frame})

    local speeds = 1
    local nowe = false
    local tpwalking = false
    local ctrl = {f=0, b=0, l=0, r=0}
    local lastctrl = {f=0, b=0, l=0, r=0}
    local bg, bv

    local function startTpWalking()
        for i = 1, speeds do
            task.spawn(function()
                tpwalking = true
                local chr = GetCharacter()
                local hum = GetHumanoid()
                while tpwalking and chr and hum and hum.Parent do
                    RunService.Heartbeat:Wait()
                    if hum.MoveDirection.Magnitude > 0 then
                        chr:TranslateBy(hum.MoveDirection)
                    end
                end
            end)
        end
    end

    local humanoidStates = {
        Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.FallingDown,
        Enum.HumanoidStateType.Flying, Enum.HumanoidStateType.Freefall,
        Enum.HumanoidStateType.GettingUp, Enum.HumanoidStateType.Jumping,
        Enum.HumanoidStateType.Landed, Enum.HumanoidStateType.Physics,
        Enum.HumanoidStateType.PlatformStanding, Enum.HumanoidStateType.Ragdoll,
        Enum.HumanoidStateType.Running, Enum.HumanoidStateType.RunningNoPhysics,
        Enum.HumanoidStateType.Seated, Enum.HumanoidStateType.StrafingNoPhysics,
        Enum.HumanoidStateType.Swimming
    }

    local function setHumanoidStates(enabled)
        local hum = GetHumanoid()
        if not hum then return end
        for _, state in ipairs(humanoidStates) do
            hum:SetStateEnabled(state, enabled)
        end
        hum:ChangeState(enabled and Enum.HumanoidStateType.RunningNoPhysics or Enum.HumanoidStateType.Swimming)
    end

    local function stopFly()
        nowe = false
        FlyV3.Flying = false
        State.Fly = false
        tpwalking = false
        setHumanoidStates(true)
        ctrl = {f=0, b=0, l=0, r=0}
        lastctrl = {f=0, b=0, l=0, r=0}
        if bg then bg:Destroy(); bg = nil end
        if bv then bv:Destroy(); bv = nil end
        local hum = GetHumanoid()
        if hum then hum.PlatformStand = false end
        local char = GetCharacter()
        if char then
            local anim = char:FindFirstChild("Animate")
            if anim then anim.Disabled = false end
        end
        ClearConnections("FlyV3")
    end

    onof.MouseButton1Down:Connect(function()
        local char = GetCharacter()
        local hum = GetHumanoid()
        if not char or not hum then return end

        if nowe then stopFly(); return end

        nowe = true
        FlyV3.Flying = true
        State.Fly = true
        startTpWalking()

        local anim = char:FindFirstChild("Animate")
        if anim then anim.Disabled = true end
        for _, v in ipairs(hum:GetPlayingAnimationTracks()) do v:AdjustSpeed(0) end
        setHumanoidStates(false)

        local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
        if not torso then return end

        local maxspeed = 50
        local speed = 0

        bg = Instance.new("BodyGyro", torso)
        bg.P = 9e4
        bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        bg.CFrame = torso.CFrame

        bv = Instance.new("BodyVelocity", torso)
        bv.Velocity = Vector3.new(0, 0.1, 0)
        bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)

        hum.PlatformStand = true

        Connections.FlyV3KeyDown = UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.KeyCode == Enum.KeyCode.W then ctrl.f = 1 end
            if input.KeyCode == Enum.KeyCode.S then ctrl.b = -1 end
            if input.KeyCode == Enum.KeyCode.A then ctrl.l = -1 end
            if input.KeyCode == Enum.KeyCode.D then ctrl.r = 1 end
        end)

        Connections.FlyV3KeyUp = UserInputService.InputEnded:Connect(function(input)
            if input.KeyCode == Enum.KeyCode.W then ctrl.f = 0 end
            if input.KeyCode == Enum.KeyCode.S then ctrl.b = 0 end
            if input.KeyCode == Enum.KeyCode.A then ctrl.l = 0 end
            if input.KeyCode == Enum.KeyCode.D then ctrl.r = 0 end
        end)

        Connections.FlyV3Loop = RunService.RenderStepped:Connect(function()
            if not nowe or not bv or not bg or hum.Health == 0 then return end
            if ctrl.l + ctrl.r ~= 0 or ctrl.f + ctrl.b ~= 0 then
                speed = speed + 0.5 + (speed / maxspeed)
                if speed > maxspeed then speed = maxspeed end
            elseif speed ~= 0 then
                speed = speed - 1
                if speed < 0 then speed = 0 end
            end
            local cam = Workspace.CurrentCamera
            if (ctrl.l + ctrl.r) ~= 0 or (ctrl.f + ctrl.b) ~= 0 then
                bv.Velocity = ((cam.CFrame.LookVector * (ctrl.f + ctrl.b)) + ((cam.CFrame * CFrame.new(ctrl.l + ctrl.r, (ctrl.f + ctrl.b) * 0.2, 0).Position) - cam.CFrame.Position)) * speed
                lastctrl = {f = ctrl.f, b = ctrl.b, l = ctrl.l, r = ctrl.r}
            elseif speed ~= 0 then
                bv.Velocity = ((cam.CFrame.LookVector * (lastctrl.f + lastctrl.b)) + ((cam.CFrame * CFrame.new(lastctrl.l + lastctrl.r, (lastctrl.f + lastctrl.b) * 0.2, 0).Position) - cam.CFrame.Position)) * speed
            else
                bv.Velocity = Vector3.zero
            end
            bg.CFrame = cam.CFrame * CFrame.Angles(-math.rad((ctrl.f + ctrl.b) * 50 * speed / maxspeed), 0, 0)
        end)
    end)

    local upConn, downConn
    up.MouseButton1Down:Connect(function()
        upConn = up.MouseEnter:Connect(function()
            while upConn do task.wait(); local h = GetHRP(); if h then h.CFrame = h.CFrame * CFrame.new(0,1,0) end end
        end)
    end)
    up.MouseLeave:Connect(function() if upConn then upConn:Disconnect(); upConn = nil end end)
    down.MouseButton1Down:Connect(function()
        downConn = down.MouseEnter:Connect(function()
            while downConn do task.wait(); local h = GetHRP(); if h then h.CFrame = h.CFrame * CFrame.new(0,-1,0) end end
        end)
    end)
    down.MouseLeave:Connect(function() if downConn then downConn:Disconnect(); downConn = nil end end)

    plus.MouseButton1Down:Connect(function()
        speeds = speeds + 1; speedLabel.Text = tostring(speeds)
        if nowe then tpwalking = false; task.wait(0.1); startTpWalking() end
    end)

    mine.MouseButton1Down:Connect(function()
        if speeds == 1 then speedLabel.Text = "min!"; task.wait(1); speedLabel.Text = tostring(speeds)
        else speeds = speeds - 1; speedLabel.Text = tostring(speeds)
            if nowe then tpwalking = false; task.wait(0.1); startTpWalking() end
        end
    end)

    closebutton.MouseButton1Click:Connect(function()
        if nowe then stopFly() end
        FlyV3.Loaded = false; FlyV3.GUI = nil; main:Destroy()
    end)

    mini.MouseButton1Click:Connect(function()
        for _, v in ipairs({up,down,onof,plus,speedLabel,mine,mini}) do v.Visible = false end
        mini2.Visible = true; Frame.BackgroundTransparency = 1
        closebutton.Position = UDim2.new(0,0,-1,57)
    end)

    mini2.MouseButton1Click:Connect(function()
        for _, v in ipairs({up,down,onof,plus,speedLabel,mine,mini}) do v.Visible = true end
        mini2.Visible = false; Frame.BackgroundTransparency = 0
        closebutton.Position = UDim2.new(0,0,-1,27)
    end)

    LocalPlayer.CharacterAdded:Connect(function(newChar)
        task.wait(0.7)
        local hum = newChar:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = false end
        local anim = newChar:FindFirstChild("Animate")
        if anim then anim.Disabled = false end
        nowe = false; FlyV3.Flying = false; State.Fly = false; tpwalking = false
    end)

    return main
end

local function ToggleFly()
    if not FlyV3.Loaded then
        CreateFlyGuiV3()
        return true, "Fly GUI V3 aberto!"
    else
        if FlyV3.GUI then FlyV3.GUI:Destroy() end
        FlyV3.Loaded = false; FlyV3.GUI = nil; State.Fly = false
        return false, "Fly GUI V3 fechado"
    end
end

-- RECONEXÃO AO RESPAWNAR
LocalPlayer.CharacterAdded:Connect(function()
    DisableAllFunctions()
    task.wait(1)
    SetupNetworkControl()
end)

-- ═══════════════════════════════════════════
-- INTERFACE DO USUÁRIO
-- ═══════════════════════════════════════════

local function CreateUI()
    pcall(function() game:GetService("CoreGui"):FindFirstChild("NDSTrollHub"):Destroy() end)
    pcall(function() LocalPlayer.PlayerGui:FindFirstChild("NDSTrollHub"):Destroy() end)

    local BgColor = Color3.fromRGB(20, 20, 25)
    local SecColor = Color3.fromRGB(30, 30, 38)
    local AccColor = Color3.fromRGB(138, 43, 226)
    local TxtColor = Color3.fromRGB(255, 255, 255)
    local DimColor = Color3.fromRGB(120, 120, 120)
    local OkColor = Color3.fromRGB(50, 205, 50)

    local ScreenGui = Create("ScreenGui", {
        Name = "NDSTrollHub",
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        ResetOnSpawn = false
    })
    pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end)
    if not ScreenGui.Parent then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

    local MainFrame = Create("Frame", {
        Name = "MainFrame",
        Size = UDim2.new(0,320,0,450),
        Position = UDim2.new(0.5,-160,0.5,-225),
        BackgroundColor3 = BgColor,
        BorderSizePixel = 0,
        Active = true,
        Parent = ScreenGui,
        Children = {
            Create("UICorner", {CornerRadius = UDim.new(0,10)}),
            Create("UIStroke", {Color = AccColor, Thickness = 2})
        }
    })

    local Header = Create("Frame", {
        Name = "Header",
        Size = UDim2.new(1,0,0,40),
        BackgroundColor3 = SecColor,
        BorderSizePixel = 0,
        Parent = MainFrame,
        Children = {
            Create("UICorner", {CornerRadius = UDim.new(0,10)}),
            Create("Frame", {Size=UDim2.new(1,0,0,10), Position=UDim2.new(0,0,1,-10), BackgroundColor3=SecColor, BorderSizePixel=0})
        }
    })

    Create("TextLabel", {
        Size = UDim2.new(1,-100,1,0), Position = UDim2.new(0,10,0,0),
        BackgroundTransparency = 1, Text = "NDS Troll Hub v7.5",
        TextColor3 = TxtColor, Font = Enum.Font.GothamBold, TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = Header
    })

    local MinimizeBtn = Create("TextButton", {
        Size=UDim2.new(0,30,0,30), Position=UDim2.new(1,-70,0,5),
        BackgroundColor3=AccColor, Text="-", TextColor3=TxtColor,
        Font=Enum.Font.GothamBold, TextSize=18, Parent=Header,
        Children = {Create("UICorner", {CornerRadius=UDim.new(0,6)})}
    })

    local CloseBtn = Create("TextButton", {
        Size=UDim2.new(0,30,0,30), Position=UDim2.new(1,-35,0,5),
        BackgroundColor3=Color3.fromRGB(200,50,50), Text="X", TextColor3=TxtColor,
        Font=Enum.Font.GothamBold, TextSize=14, Parent=Header,
        Children = {Create("UICorner", {CornerRadius=UDim.new(0,6)})}
    })

    local ContentFrame = Create("Frame", {
        Name="ContentFrame", Size=UDim2.new(1,-20,1,-50), Position=UDim2.new(0,10,0,45),
        BackgroundTransparency=1, Parent=MainFrame
    })

    local PlayerSection = Create("Frame", {
        Size=UDim2.new(1,0,0,100), BackgroundColor3=SecColor, BorderSizePixel=0, Parent=ContentFrame,
        Children = {Create("UICorner", {CornerRadius=UDim.new(0,8)})}
    })

    Create("TextLabel", {
        Size=UDim2.new(1,-10,0,20), Position=UDim2.new(0,5,0,5),
        BackgroundTransparency=1, Text="Selecionar Player:", TextColor3=DimColor,
        Font=Enum.Font.Gotham, TextSize=11, TextXAlignment=Enum.TextXAlignment.Left,
        Parent=PlayerSection
    })

    local PlayerList = Create("ScrollingFrame", {
        Size=UDim2.new(1,-10,0,50), Position=UDim2.new(0,5,0,25),
        BackgroundColor3=BgColor, BorderSizePixel=0, ScrollBarThickness=4,
        ScrollBarImageColor3=AccColor, CanvasSize=UDim2.new(0,0,0,0),
        AutomaticCanvasSize=Enum.AutomaticSize.Y, Parent=PlayerSection,
        Children = {
            Create("UICorner", {CornerRadius=UDim.new(0,6)}),
            Create("UIListLayout", {SortOrder=Enum.SortOrder.Name, Padding=UDim.new(0,3)}),
            Create("UIPadding", {PaddingTop=UDim.new(0,3), PaddingBottom=UDim.new(0,3), PaddingLeft=UDim.new(0,3), PaddingRight=UDim.new(0,3)})
        }
    })

    local SelectedStatus = Create("TextLabel", {
        Size=UDim2.new(1,-10,0,18), Position=UDim2.new(0,5,1,-22),
        BackgroundTransparency=1, Text="Nenhum selecionado", TextColor3=DimColor,
        Font=Enum.Font.Gotham, TextSize=10, TextXAlignment=Enum.TextXAlignment.Left,
        Parent=PlayerSection
    })

    local function UpdatePlayerList()
        for _, child in ipairs(PlayerList:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        for _, player in ipairs(Players:GetPlayers()) do
            local btn = Create("TextButton", {
                Name=player.Name, Size=UDim2.new(1,-6,0,22),
                BackgroundColor3 = State.SelectedPlayer == player and AccColor or SecColor,
                Text=player.DisplayName, TextColor3=TxtColor, Font=Enum.Font.Gotham,
                TextSize=10, TextTruncate=Enum.TextTruncate.AtEnd, Parent=PlayerList,
                Children = {Create("UICorner", {CornerRadius=UDim.new(0,4)})}
            })
            btn.MouseButton1Click:Connect(function()
                State.SelectedPlayer = player
                SelectedStatus.Text = "Selecionado: " .. player.DisplayName
                SelectedStatus.TextColor3 = OkColor
                UpdatePlayerList()
            end)
        end
    end
    UpdatePlayerList()
    Players.PlayerAdded:Connect(UpdatePlayerList)
    Players.PlayerRemoving:Connect(UpdatePlayerList)

    local ButtonsScroll = Create("ScrollingFrame", {
        Size=UDim2.new(1,0,1,-110), Position=UDim2.new(0,0,0,105),
        BackgroundTransparency=1, BorderSizePixel=0, ScrollBarThickness=4,
        ScrollBarImageColor3=AccColor, CanvasSize=UDim2.new(0,0,0,0),
        AutomaticCanvasSize=Enum.AutomaticSize.Y, Parent=ContentFrame,
        Children = {Create("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,5)})}
    })

    local function CreateCategory(name, order)
        Create("Frame", {
            Size=UDim2.new(1,0,0,18), BackgroundTransparency=1, LayoutOrder=order, Parent=ButtonsScroll,
            Children = {Create("TextLabel", {
                Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text="-- "..name.." --",
                TextColor3=AccColor, Font=Enum.Font.GothamBold, TextSize=10
            })}
        })
    end

    local function CreateToggle(name, callback, order, stateKey)
        local btn = Create("TextButton", {
            Size=UDim2.new(1,0,0,32), BackgroundColor3=SecColor, Text="", LayoutOrder=order, Parent=ButtonsScroll,
            Children = {Create("UICorner", {CornerRadius=UDim.new(0,6)})}
        })
        Create("TextLabel", {
            Size=UDim2.new(1,-40,1,0), Position=UDim2.new(0,10,0,0),
            BackgroundTransparency=1, Text=name, TextColor3=TxtColor,
            Font=Enum.Font.Gotham, TextSize=11, TextXAlignment=Enum.TextXAlignment.Left,
            Parent=btn
        })
        local status = Create("Frame", {
            Size=UDim2.new(0,10,0,10), Position=UDim2.new(1,-22,0.5,-5),
            BackgroundColor3=DimColor, Parent=btn,
            Children = {Create("UICorner", {CornerRadius=UDim.new(1,0)})}
        })
        btn.MouseButton1Click:Connect(function()
            local ok, msg = callback()
            status.BackgroundColor3 = ok and OkColor or DimColor
            if msg then Notify(name, msg, 2) end
        end)
        return btn
    end

    local function CreateButton(name, callback, order)
        local btn = Create("TextButton", {
            Size=UDim2.new(1,0,0,32), BackgroundColor3=SecColor, Text=name,
            TextColor3=TxtColor, Font=Enum.Font.Gotham, TextSize=11,
            LayoutOrder=order, Parent=ButtonsScroll,
            Children = {Create("UICorner", {CornerRadius=UDim.new(0,6)})}
        })
        btn.MouseButton1Click:Connect(function()
            local ok, msg = callback()
            if msg then Notify(name, msg, 2) end
        end)
        return btn
    end

    -- TROLAGEM (todas as funções expostas na UI)
    CreateCategory("TROLAGEM", 1)
    CreateToggle("Ima de Objetos", ToggleMagnet, 2, "Magnet")
    CreateToggle("Orbit Attack", ToggleOrbit, 3, "Orbit")
    CreateToggle("Blackhole", ToggleBlackhole, 4, "Blackhole")
    CreateToggle("Part Rain", TogglePartRain, 5, "PartRain")
    CreateToggle("Spin", ToggleSpin, 6, "Spin")
    CreateToggle("Cage", ToggleCage, 7, "Cage")
    CreateToggle("Sky Lift", ToggleSkyLift, 8, "SkyLift")
    CreateToggle("Server Magnet", ToggleServerMagnet, 9, "ServerMagnet")
    CreateToggle("Launch", ToggleLaunch, 10, "Launch")
    CreateToggle("Slow Player", ToggleSlowPlayer, 11, "SlowPlayer")

    CreateCategory("FLING", 20)
    CreateToggle("Hat Fling", ToggleHatFling, 21, "HatFling")
    CreateToggle("Body Fling", ToggleBodyFling, 22, "BodyFling")

    CreateCategory("UTILIDADES", 30)
    CreateToggle("God Mode", ToggleGodMode, 31, "GodMode")
    CreateToggle("View Player", ToggleView, 32, "View")
    CreateToggle("Noclip", ToggleNoclip, 33, "Noclip")
    CreateToggle("Speed 3x", ToggleSpeed, 34, "Speed")
    CreateToggle("ESP", ToggleESP, 35, "ESP")
    CreateToggle("Telecinese", ToggleTelekinesis, 36, "Telekinesis")
    CreateButton("Teleport", TeleportToPlayer, 37)
    CreateButton("Fly GUI", ToggleFly, 38)

    CreateCategory("CONFIG", 50)

    -- Slider de Raio
    local sliderFrame = Create("Frame", {
        Size=UDim2.new(1,0,0,45), BackgroundColor3=SecColor, LayoutOrder=51, Parent=ButtonsScroll,
        Children = {Create("UICorner", {CornerRadius=UDim.new(0,6)})}
    })

    local sliderLabel = Create("TextLabel", {
        Size=UDim2.new(1,-10,0,18), Position=UDim2.new(0,5,0,3),
        BackgroundTransparency=1, Text="Raio Orbit: "..Config.OrbitRadius,
        TextColor3=TxtColor, Font=Enum.Font.Gotham, TextSize=10,
        TextXAlignment=Enum.TextXAlignment.Left, Parent=sliderFrame
    })

    local sliderBg = Create("Frame", {
        Size=UDim2.new(1,-10,0,8), Position=UDim2.new(0,5,0,25),
        BackgroundColor3=BgColor, Parent=sliderFrame,
        Children = {Create("UICorner", {CornerRadius=UDim.new(1,0)})}
    })

    local sliderFill = Create("Frame", {
        Size=UDim2.new(Config.OrbitRadius/50,0,1,0),
        BackgroundColor3=AccColor, Parent=sliderBg,
        Children = {Create("UICorner", {CornerRadius=UDim.new(1,0)})}
    })

    local sliderBtn = Create("TextButton", {
        Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text="", Parent=sliderBg
    })

    local draggingSlider = false
    sliderBtn.MouseButton1Down:Connect(function() draggingSlider = true end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = false
        end
    end)
    RunService.RenderStepped:Connect(function()
        if draggingSlider then
            local mouse = UserInputService:GetMouseLocation()
            local relX = math.clamp((mouse.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X, 0, 1)
            Config.OrbitRadius = math.floor(relX * 45) + 5
            sliderFill.Size = UDim2.new(relX, 0, 1, 0)
            sliderLabel.Text = "Raio Orbit: " .. Config.OrbitRadius
        end
    end)

    -- Botão flutuante
    local FloatBtn = Create("TextButton", {
        Name="FloatBtn", Size=UDim2.new(0,50,0,50), Position=UDim2.new(0,10,0.5,-25),
        BackgroundColor3=AccColor, Text="NDS", TextColor3=TxtColor,
        Font=Enum.Font.GothamBold, TextSize=12, Visible=false, Parent=ScreenGui,
        Children = {Create("UICorner", {CornerRadius=UDim.new(1,0)})}
    })

    -- Minimizar
    local minimized = false
    MinimizeBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            TweenService:Create(MainFrame, TweenInfo.new(0.2), {Size=UDim2.new(0,320,0,40)}):Play()
            MinimizeBtn.Text = "+"; ContentFrame.Visible = false
        else
            TweenService:Create(MainFrame, TweenInfo.new(0.2), {Size=UDim2.new(0,320,0,450)}):Play()
            MinimizeBtn.Text = "-"; task.wait(0.2); ContentFrame.Visible = true
        end
    end)

    CloseBtn.MouseButton1Click:Connect(function() MainFrame.Visible = false; FloatBtn.Visible = true end)
    FloatBtn.MouseButton1Click:Connect(function() MainFrame.Visible = true; FloatBtn.Visible = false end)

    -- Arrastar MainFrame
    local dragging, dragStart, startPos = false, nil, nil
    Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = MainFrame.Position
        end
    end)
    Header.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)

    -- Arrastar FloatBtn
    local draggingF, dragStartF, startPosF = false, nil, nil
    FloatBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingF = true; dragStartF = input.Position; startPosF = FloatBtn.Position
        end
    end)
    FloatBtn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then draggingF = false end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            if dragging and dragStart and startPos then
                local d = input.Position - dragStart
                MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
            if draggingF and dragStartF and startPosF then
                local d = input.Position - dragStartF
                FloatBtn.Position = UDim2.new(startPosF.X.Scale, startPosF.X.Offset + d.X, startPosF.Y.Scale, startPosF.Y.Offset + d.Y)
            end
        end
    end)

    return ScreenGui
end

-- ═══════════════════════════════════════════
-- INICIALIZAÇÃO
-- ═══════════════════════════════════════════

SetupNetworkControl()
CreateUI()

task.spawn(function()
    task.wait(1)
    Notify("NDS Troll Hub v7.5", "Carregado!", 3)
end)

print("NDS Troll Hub v7.5 SERVER MAGNET - Carregado!")