local mapName = "stayfrosty"
if game.GetMap() != mapName then return end

if SERVER then
    util.AddNetworkString("StayFrosty_DeathEffects")
    util.AddNetworkString("StayFrosty_PlayerRespawned")
    util.AddNetworkString("StayFrosty_ExplosionFX")
    util.AddNetworkString("StayFrosty_EndingFX")
    util.AddNetworkString("StayFrosty_DisconnectMe")
    util.AddNetworkString("StayFrosty_CheckpointHUD")

    hook.Add("PlayerLoadout", "GiveWeapons", function(ply) return false end)
    hook.Add("PlayerSwitchFlashlight", "DisableFlashlight", function(ply, enabled) return false end)
    hook.Add("PlayerNoClip", "StayFrosty_AntiNoclip", function(ply, desiredState) return false end)

    hook.Add("PlayerInitialSpawn", "WelcomeMsg", function(ply)
        ply:SetNWString("StayFrosty_ActiveCheckpoint", "none")
    end)

    hook.Add("PlayerInitialSpawn", "StayFrosty_SoloOnlyCheck", function(ply)
        if not game.SinglePlayer() or #player.GetAll() > 1 then
            timer.Simple(1, function()
                if IsValid(ply) then
                    net.Start("StayFrosty_DisconnectMe")
                    net.Send(ply)
                end
            end)
            timer.Simple(8, function()
                if IsValid(ply) then
                    ply:ConCommand("disconnect")
                end
            end)
        end
    end)

    local CheckpointSavedLoadouts = {}

    function StayFrosty_SaveCheckpointLoadout(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        local plyID = ply:SteamID64() or "singleplayer"
        CheckpointSavedLoadouts[plyID] = { Weapons = {}, Ammo = {} }

        for _, wep in ipairs(ply:GetWeapons()) do
            if IsValid(wep) then
                table.insert(CheckpointSavedLoadouts[plyID].Weapons, {
                    class = wep:GetClass(),
                    clip1 = wep:Clip1(),
                    clip2 = wep:Clip2()
                })
                local primaryAmmoType = wep:GetPrimaryAmmoType()
                local secondaryAmmoType = wep:GetSecondaryAmmoType()

                if primaryAmmoType and primaryAmmoType != -1 then
                    CheckpointSavedLoadouts[plyID].Ammo[primaryAmmoType] = ply:GetAmmoCount(primaryAmmoType)
                end
                if secondaryAmmoType and secondaryAmmoType != -1 then
                    CheckpointSavedLoadouts[plyID].Ammo[secondaryAmmoType] = ply:GetAmmoCount(secondaryAmmoType)
                end
            end
        end
    end

    timer.Create("StayFrosty_DistanceCheckpointTracker", 0.15, 0, function()
        local checkpoints = {
            { name = "trigger_cp_garage", id = "cp_garage", wall = "wall_garage" },
            { name = "trigger_cp_factory", id = "cp_factory", wall = "wall_factory" },
            { name = "trigger_cp_home", id = "save_home", wall = "wall_home" }
        }

        for _, cp in ipairs(checkpoints) do
            local trEnt = ents.FindByName(cp.name)[1]
            if IsValid(trEnt) then
                local min, max = trEnt:WorldSpaceAABB()
                min.z = min.z - 32
                max.z = max.z + 32
                local targets = ents.FindInBox(min, max)

                for _, ent in ipairs(targets) do
                    if IsValid(ent) and ent:IsPlayer() and ent:Alive() then
                        local activeCP = ent:GetNWString("StayFrosty_ActiveCheckpoint")
                        local isAlreadySaved = (cp.id == "save_home") and (activeCP == "save_home" or activeCP == "cp_home") or (activeCP == cp.id)

                        if not isAlreadySaved then
                            ent:SetNWString("StayFrosty_ActiveCheckpoint", cp.id)
                            StayFrosty_SaveCheckpointLoadout(ent)

                            local wall = ents.FindByName(cp.wall)[1]
                            if IsValid(wall) then
                                wall:Fire("Enable")
                            end

                            net.Start("StayFrosty_CheckpointHUD")
                            net.Send(ent)
                        end
                    end
                end
            end
        end
    end)

    hook.Add("PostCleanupMap", "StayFrosty_BlockCutsceneOnCleanUp", function()
        local ply = Entity(1)
        if IsValid(ply) and ply:IsPlayer() then
            local activeCP = ply:GetNWString("StayFrosty_ActiveCheckpoint", "none")
            if activeCP != "none" then
                local cam = ents.FindByName("camera_start")[1]
                if IsValid(cam) then
                    cam:Fire("Disable")
                    cam:Remove()
                end

                local logicAutos = ents.FindByClass("logic_auto")
                for _, auto in ipairs(logicAutos) do
                    if IsValid(auto) then auto:Remove() end
                end

                local fades = ents.FindByClass("env_fade")
                for _, fade in ipairs(fades) do
                    if IsValid(fade) then fade:Fire("EndFade") end
                end
            end
        end
    end)

    hook.Add("PlayerSpawn", "StayFrosty_PlayerSpawn", function(ply)
        if not ply:GetNWBool("IsFadingOut") then
            ply:SetNWBool("IsEndingGame", false)
            ply:SetNWBool("IsPsychoActive", false)
            ply:SetNoDraw(false)
            ply:DrawShadow(true)

            if IsValid(ply:GetActiveWeapon()) then
                ply:GetActiveWeapon():SetNoDraw(false)
            end

            ply:RemoveFlags(FL_NOTARGET)

            if ply:GetNWInt("StayFrosty_Lives", 0) <= 0 then
                ply:SetNWInt("StayFrosty_Lives", 6)
            end

            ply:SetMaxHealth(6)
            ply:SetHealth(ply:GetNWInt("StayFrosty_Lives", 6))
            ply:SetNWFloat("Stamina", 100)

            timer.Simple(0.05, function()
                if not IsValid(ply) then return end
                local plyID = ply:SteamID64() or "singleplayer"
                local loadout = CheckpointSavedLoadouts[plyID]

                if loadout then
                    ply:StripWeapons()
                    ply:RemoveAllAmmo()

                    if loadout.Ammo then
                        for ammoID, count in pairs(loadout.Ammo) do
                            ply:SetAmmo(count, ammoID)
                        end
                    end

                    if loadout.Weapons then
                        for _, wepData in ipairs(loadout.Weapons) do
                            local wep = ply:Give(wepData.class)
                            if IsValid(wep) then
                                if wepData.clip1 then wep:SetClip1(wepData.clip1) end
                                if wepData.clip2 then wep:SetClip2(wepData.clip2) end
                            end
                        end
                    end
                end
            end)

            local activeCP = ply:GetNWString("StayFrosty_ActiveCheckpoint", "none")
            if activeCP != "none" then
                local spawnTarget = ents.FindByName(activeCP)[1]
                if not IsValid(spawnTarget) and (activeCP == "save_home" or activeCP == "cp_home") then
                    spawnTarget = ents.FindByName("save_home")[1] or ents.FindByName("cp_home")[1]
                end

                if IsValid(spawnTarget) then
                    timer.Simple(0.08, function()
                        if IsValid(ply) and IsValid(spawnTarget) then
                            ply:SetMoveType(MOVETYPE_WALK)
                            ply:SetPos(spawnTarget:GetPos() + Vector(0, 0, 5))
                            ply:SetEyeAngles(spawnTarget:GetAngles())
                            ply:ConCommand("r_cleardecals")

                            local wallName = "wall_garage"
                            if activeCP == "cp_factory" then
                                wallName = "wall_factory"
                            elseif activeCP == "save_home" or activeCP == "cp_home" then
                                wallName = "wall_home"
                            end

                            local currentWall = ents.FindByName(wallName)[1]
                            if IsValid(currentWall) then
                                currentWall:Fire("Enable")
                            end
                        end
                    end)
                end
            end

            net.Start("StayFrosty_PlayerRespawned")
            net.Send(ply)
        end
    end)

    hook.Add("EntityTakeDamage", "StayFrosty_OneHitOneLife", function(target, dmginfo)
        if IsValid(target) and target:IsPlayer() then
            if target:GetNWBool("IsFadingOut") or target:GetNWBool("IsEndingGame") then
                dmginfo:SetDamage(0)
                return true
            end

            if target:Alive() then
                local currentLives = target:GetNWInt("StayFrosty_Lives", 6)
                if currentLives > 0 then
                    local newLives = currentLives - 1
                    target:SetNWInt("StayFrosty_Lives", newLives)
                    target:SetHealth(newLives)
                    target:EmitSound("player/pl_pain" .. math.random(5, 7) .. ".wav", 75, 100)

                    if newLives <= 0 then
                        target:SetNWBool("IsFadingOut", true)
                        target:AddFlags(FL_NOTARGET)

                        net.Start("StayFrosty_DeathEffects")
                        net.WriteVector(target:EyePos())
                        net.WriteAngle(target:EyeAngles())
                        net.Send(target)

                        target:EmitSound("physics/body/body_medium_break" .. math.random(2, 4) .. ".wav", 80, 90)

                        timer.Simple(0.5, function()
                            if IsValid(target) then
                                target:EmitSound("player/death" .. math.random(1, 4) .. ".wav", 85, 85)
                                target:StripWeapons()
                                target:RemoveAllAmmo()
                            end
                        end)

                        timer.Simple(3.5, function()
                            if IsValid(target) then
                                target:SetNWBool("IsFadingOut", false)
                                target:SetNWInt("StayFrosty_Lives", 6)
                                target:SetNWFloat("Stamina", 100)
                                StayFrosty_PlayedTrigger1 = false
                                StayFrosty_PlayedTrigger2 = false
                                game.CleanUpMap()
                                target:KillSilent()
                                target:Spawn()
                            end
                        end)
                    end
                end
                dmginfo:SetDamage(0)
                return true
            end
        end
    end)

    hook.Add("PlayerCanPickupItem", "StayFrosty_HealthKits", function(ply, item)
        if not IsValid(ply) or not IsValid(item) or not ply:Alive() then return end
        if item.IsStayFrostyPicked then return false end

        local itemClass = item:GetClass()
        local healAmount = 0

        if itemClass == "item_healthvial" then healAmount = 1
        elseif itemClass == "item_healthkit" then healAmount = 3 end

        if healAmount > 0 then
            local currentLives = ply:GetNWInt("StayFrosty_Lives", 6)
            local maxLives = 6
            if currentLives >= maxLives then return false end

            item.IsStayFrostyPicked = true
            local newLives = math.min(currentLives + healAmount, maxLives)
            ply:SetNWInt("StayFrosty_Lives", newLives)
            ply:SetHealth(newLives)
            ply:EmitSound("items/smallmedkit1.wav", 65, 100)
            item:Remove()
            return false
        end
    end)

    function TriggerExplosionEffect(duration, target_ply)
        duration = duration or 5
        local ply = IsValid(target_ply) and target_ply or Entity(1)
        if IsValid(ply) and ply:IsPlayer() and ply:Alive() and not ply:GetNWBool("IsEndingGame") then
            net.Start("StayFrosty_ExplosionFX")
            net.WriteFloat(duration)
            net.Send(ply)
        end
    end

    function TriggerGameEnding()
        local WAIT_DURATION = 38
        local FX_DURATION = 30
        local TOTAL_DURATION = WAIT_DURATION + FX_DURATION
        local ply = Entity(1)

        if IsValid(ply) and ply:Alive() and not ply:GetNWBool("IsEndingGame") then
            ply:SetNWBool("IsEndingGame", true)
            ply:SetNWBool("IsPsychoActive", true)
            ply:StripWeapons()
            ply:RemoveAllAmmo()

            net.Start("StayFrosty_EndingFX")
            net.WriteFloat(TOTAL_DURATION)
            net.Send(ply)
        end
    end

    StayFrosty_PlayedTrigger1 = false
    function PlayTriggerMusic()
        if StayFrosty_PlayedTrigger1 then return end
        local ply = Entity(1)
        if IsValid(ply) and ply:IsPlayer() then
            StayFrosty_PlayedTrigger1 = true
            ply:EmitSound("stayfrosty/stayfrostyescape.mp3", 0, 100, 1.5, CHAN_STATIC)
        end
    end

    StayFrosty_PlayedTrigger2 = false
    function PlayTriggerMusic2()
        if StayFrosty_PlayedTrigger2 then return end
        local ply = Entity(1)
        if IsValid(ply) and ply:IsPlayer() then
            StayFrosty_PlayedTrigger2 = true
            ply:EmitSound("stayfrosty/tragedy.mp3", 0, 100, 1, CHAN_STATIC)
        end
    end

    hook.Add("Think", "StayFrosty_AntiCheatThink", function()
        if GetConVar("sv_cheats"):GetBool() then
            RunConsoleCommand("sv_cheats", "0")
        end
        local ply = Entity(1)
        if IsValid(ply) and ply:IsPlayer() then
            if ply:HasGodMode() then ply:DisableGodMode() end
        end
    end)

    local blockedCommands = {
        ["god"] = true,
        ["give"] = true,
        ["ent_create"] = true,
        ["ent_fire"] = true,
        ["ent_remove"] = true,
        ["noclip"] = true,
        ["impulse"] = true
    }

    hook.Add("PlayerSay", "StayFrosty_BlockChatCheats", function(ply, text)
        local cmd = string.match(text, "^[/!]?(%w+)")
        if cmd and blockedCommands[string.lower(cmd)] then return "" end
    end)
end

local function RestrictPlayerMovement(ply, mv)
    if not IsValid(ply) or not ply:Alive() then return end

    if ply:GetNWBool("IsFadingOut") then
        mv:SetForwardSpeed(0)
        mv:SetSideSpeed(0)
        mv:SetUpSpeed(0)
        mv:SetVelocity(Vector(0,0,0))
        return
    end

    if mv:KeyDown(IN_JUMP) then
        mv:SetButtons(mv:GetButtons() - IN_JUMP)
    end

    local walkSpeed = 120
    local runSpeed = 190
    local currentStamina = ply:GetNWFloat("Stamina", 100)
    local isMoving = ply:GetVelocity():Length2D() > 10

    if SERVER then
        if mv:KeyDown(IN_SPEED) and isMoving and ply:OnGround() and currentStamina > 0 then
            currentStamina = math.Approach(currentStamina, 0, FrameTime() * 14)
        else
            local recoveryRate = isMoving and 3 or 4
            currentStamina = math.Approach(currentStamina, 100, FrameTime() * recoveryRate)
        end
        ply:SetNWFloat("Stamina", currentStamina)
    end

    if mv:KeyDown(IN_SPEED) and currentStamina > 5 and isMoving then
        mv:SetMaxSpeed(runSpeed)
        mv:SetMaxClientSpeed(runSpeed)
    else
        mv:SetMaxSpeed(walkSpeed)
        mv:SetMaxClientSpeed(walkSpeed)
    end
end
hook.Add("SetupMove", "RestrictPlayerMovement_WithRun_Hook", RestrictPlayerMovement)

if CLIENT then
    local deathStartTime = 0
    local isDyingClient = false
    local deathPos = Vector(0, 0, 0)
    local deathAng = Angle(0, 0, 0)
    local currentDeathRoll = 0
    local explosionStartTime = 0
    local explosionDuration = 0
    local isExploded = false
    local endingStartTime = 0
    local endingDuration = 0
    local isEndingActive = false
    local bgMusic

    local checkpointNotifyTime = 0
    local checkpointDuration = 4.0

    net.Receive("StayFrosty_DisconnectMe", function()
        local frame = vgui.Create("DFrame")
        frame:SetSize(ScrW(), ScrH())
        frame:Center()
        frame:SetTitle("")
        frame:SetDraggable(false)
        frame:ShowCloseButton(false)
        frame:MakePopup()

        frame.Paint = function(self, w, h)
            surface.SetDrawColor(0, 0, 0, 255)
            surface.DrawRect(0, 0, w, h)
        end

        local label = vgui.Create("DLabel", frame)
        label:SetFont("StayFrosty_CheckpointFont")
        label:SetText("ATTENTION!\n\nThis mod is designed STRICTLY for single-player gameplay. Multiplayer is not supported.\n\nReturning to the main menu...")
        label:SetTextColor(Color(255, 50, 50))
        label:SizeToContents()
        label:Center()
    end)

    surface.CreateFont("StayFrosty_CheckpointFont", {
        font = "Trebuchet MS",
        size = ScreenScale(14),
        weight = 800,
        antialias = true,
        shadow = true
    })

    local function StartBackgroundMusic()
        if IsValid(bgMusic) then
            bgMusic:Stop()
            bgMusic = nil
        end
        sound.PlayFile("sound/stayfrosty/659966__beussa__ambiant-generator.mp3", "noplay ignorefx", function(station, errCode, errStr)
            if IsValid(station) then
                bgMusic = station
                bgMusic:SetVolume(18)
                bgMusic:EnableLooping(true)
                bgMusic:Play()
            else
                print("[StayFrosty] Error ", errStr)
            end
        end)
    end

    net.Receive("StayFrosty_CheckpointHUD", function()
        checkpointNotifyTime = CurTime()
    end)

    net.Receive("StayFrosty_DeathEffects", function()
        deathPos = net.ReadVector()
        deathAng = net.ReadAngle()
        deathStartTime = CurTime()
        currentDeathRoll = 0
        isDyingClient = true
        LocalPlayer():SetDSP(31)
    end)

    net.Receive("StayFrosty_PlayerRespawned", function()
        isDyingClient = false
        currentDeathRoll = 0
        isExploded = false
        isEndingActive = false
        checkpointNotifyTime = 0
        if IsValid(LocalPlayer()) and LocalPlayer().SetDSP then
            LocalPlayer():SetDSP(0)
        end
        timer.Simple(0.5, function()
            StartBackgroundMusic()
        end)
    end)

    net.Receive("StayFrosty_ExplosionFX", function()
        if isEndingActive then return end
        explosionDuration = net.ReadFloat()
        explosionStartTime = CurTime()
        isExploded = true
        LocalPlayer():SetDSP(33)
        timer.Simple(explosionDuration, function()
            if IsValid(LocalPlayer()) and not isDyingClient and not isEndingActive then
                LocalPlayer():SetDSP(0)
            end
        end)
    end)

    net.Receive("StayFrosty_EndingFX", function()
        endingDuration = net.ReadFloat()
        endingStartTime = CurTime()
        isEndingActive = true
        isExploded = false
        if IsValid(LocalPlayer()) then
            LocalPlayer():SetNWBool("IsPsychoActive", true)
            LocalPlayer():SetDSP(0)
        end
    end)

    hook.Add("SpawnMenuOpen", "BlockQMenu", function() return false end)
    hook.Add("ContextMenuOpen", "BlockCMenu", function() return false end)

    local blockedHUD = {
        ["CHudHealth"] = true,
        ["CHudBattery"] = true,
        ["CHudAmmo"] = true,
        ["CHudSecondaryAmmo"] = true,
        ["CHudCrosshair"] = false,
        ["CHudDamageIndicator"] = true,
        ["CHudDeathNotice"] = true,
        ["CHudHintDisplay"] = true,
        ["CHudSquadStatus"] = true,
        ["CHudPoisonDamageIndicator"] = true
    }

    hook.Add("HUDShouldDraw", "HideSpecificHUD", function(name)
        if blockedHUD[name] then return false end
    end)

    hook.Add("DrawDeathNotice", "HideDeathNotice", function() return false end)
    hook.Add("CHudGModTargetID", "HideTargetID", function() return false end)

    hook.Add("HUDPaint", "MyCustomHUD", function()
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:Alive() or ply:GetNWBool("IsFadingOut") or ply:GetNWBool("IsEndingGame") or isDyingClient or isEndingActive then
            return
        end

        local lives = ply:GetNWInt("StayFrosty_Lives", 6)
        local stamina = ply:GetNWFloat("Stamina", 100)

        local livesY = ScrH() - 135
        draw.RoundedBox(8, 50, livesY, 240, 45, Color(0, 0, 0, 200))
        for i = 1, 6 do
            local boxX = 55 + (i - 1) * 38
            local boxColor = (i <= lives) and Color(255, 50, 50, 255) or Color(50, 50, 50, 150)
            draw.RoundedBox(4, boxX, livesY + 10, 32, 25, boxColor)
        end

        local staminaY = ScrH() - 75
        draw.RoundedBox(8, 50, staminaY, 200, 35, Color(0, 0, 0, 200))
        local staminaBarWidth = math.Clamp(stamina, 0, 100) * 1.9
        local staminaColor = (stamina < 25) and Color(210, 110, 30, 255) or Color(225, 225, 205, 255)
        draw.RoundedBox(4, 55, staminaY + 4, staminaBarWidth, 27, staminaColor)

        local elapsedNotify = CurTime() - checkpointNotifyTime
        if elapsedNotify < checkpointDuration and checkpointNotifyTime > 0 then
            local alpha = 255
            if elapsedNotify < 0.5 then
                alpha = (elapsedNotify / 0.5) * 255
            elseif elapsedNotify > (checkpointDuration - 1.0) then
                alpha = ((checkpointDuration - elapsedNotify) / 1.0) * 255
            end

            surface.SetFont("StayFrosty_CheckpointFont")
            local text = "CheckPoint saved"
            local textWidth, textHeight = surface.GetTextSize(text)
            local textX = (ScrW() - textWidth) / 2
            local textY = (ScrH() / 2) + (ScrH() * 0.15)

            surface.SetTextColor(255, 193, 64, alpha)
            surface.SetTextPos(textX, textY)
            surface.DrawText(text)
        end
    end)

    hook.Add("RenderScreenspaceEffects", "Horror_Screen_FX", function()
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:Alive() then return end

        local speed = ply:GetVelocity():Length2D()
        local colorModify = {
            ["$pp_colour_addr"] = 0,
            ["$pp_colour_addg"] = 0,
            ["$pp_colour_addb"] = 0,
            ["$pp_colour_brightness"] = 0.04,
            ["$pp_colour_contrast"] = 1.15,
            ["$pp_colour_colour"] = 0.6,
            ["$pp_colour_mulr"] = 0,
            ["$pp_colour_mulg"] = 0,
            ["$pp_colour_mulb"] = 0
        }

        if isDyingClient then
            local elapsed = CurTime() - deathStartTime
            colorModify["$pp_colour_colour"] = math.Clamp(0.85 - (elapsed * 0.25), 0, 0.85)
            colorModify["$pp_colour_contrast"] = math.Clamp(1.15 - (elapsed * 0.2), 0.3, 1.15)
            colorModify["$pp_colour_brightness"] = math.Clamp(0.04 - (elapsed * 0.3), -1, 0.04)
            DrawColorModify(colorModify)
            DrawMotionBlur(0.4, math.Clamp(elapsed * 0.35, 0.1, 0.98), 0.05)
            return
        end

        if isEndingActive and ply:GetNWBool("IsPsychoActive") then
            local elapsed = CurTime() - endingStartTime
            DrawColorModify(colorModify)
            cam.Start2D()
                if elapsed >= 35 then
                    local flashAlpha = math.Clamp((elapsed - 35) / 5, 0, 1) * 255
                    surface.SetDrawColor(255, 255, 255, flashAlpha)
                    surface.DrawRect(0, 0, ScrW(), ScrH())
                end
                if elapsed >= 42 then
                    surface.SetFont("DermaLarge")
                    local text = "No..."
                    local w, h = surface.GetTextSize(text)
                    local textAlpha = math.Clamp((elapsed - 42) / 3, 0, 1) * 255
                    surface.SetTextColor(180, 30, 30, textAlpha)
                    surface.SetTextPos((ScrW() - w) / 2, (ScrH() - h) / 2)
                    surface.DrawText(text)
                end
            cam.End2D()
            return
        end

        if isExploded then
            local elapsed = CurTime() - explosionStartTime
            if elapsed < explosionDuration then
                local fade = 1 - (elapsed / explosionDuration)
                colorModify["$pp_colour_colour"] = Lerp(fade, 0.85, 0.0)
                colorModify["$pp_colour_contrast"] = Lerp(fade, 1.15, 1.6)
                colorModify["$pp_colour_brightness"] = Lerp(fade, 0.04, -0.05)
                DrawMotionBlur(0.01, fade * 0.92, 0.02)
                DrawBloom(0.1, fade * 4.5, fade * 15, fade * 15, 1, 0, 1, 1, 1)
                DrawSharpen(fade * 12, fade * 3)
            else
                isExploded = false
            end
        end

        if not isExploded then
            local blurAmount = (speed > 130) and 0.35 or 0.6
            DrawMotionBlur(blurAmount, 0.8, 0.01)
        end

        DrawColorModify(colorModify)

        if not isExploded then
            local shift = 0.002 + (math.sin(CurTime() * 5) * 0.0005)
            if speed > 130 then shift = shift + 0.002 end
            DrawSharpen(shift * 500, 0.5)

            cam.Start2D()
                surface.SetDrawColor(0, 0, 0, 10)
                for y = 0, ScrH(), 4 do
                    local scanlineY = y + math.floor(math.sin(CurTime() * 10 + y) * 0.5)
                    surface.DrawRect(0, scanlineY, ScrW(), 1)
                end
                surface.SetDrawColor(255, 255, 255, math.random(2, 5))
                for i = 1, 12 do
                    surface.DrawRect(math.random(0, ScrW() - 200), math.random(0, ScrH() - 2), math.random(150, 400), math.random(1, 3))
                end
            cam.End2D()
        end
    end)

    local flashlightOn = false
    local lastPressedF = 0
    local smoothFlashlightDir, smoothFlashlightPos, hl2Flashlight

    local function RemoveHL2Flashlight()
        if IsValid(hl2Flashlight) then
            hl2Flashlight:Remove()
            hl2Flashlight = nil
        end
    end

    hook.Add("Think", "FlashlightToggle", function()
        if isDyingClient or (isEndingActive and LocalPlayer():GetNWBool("IsPsychoActive")) then
            RemoveHL2Flashlight()
            return
        end
        if input.IsKeyDown(KEY_F) and CurTime() - lastPressedF > 0.3 then
            flashlightOn = not flashlightOn
            lastPressedF = CurTime()
            LocalPlayer():EmitSound("items/flashlight1.wav", 60, 100)
            if not flashlightOn then RemoveHL2Flashlight() end
        end
    end)

    hook.Add("PreRender", "DynamicHorrorFlashlight", function()
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:Alive() or not flashlightOn or isDyingClient or (isEndingActive and ply:GetNWBool("IsPsychoActive")) then
            RemoveHL2Flashlight()
            return
        end

        local viewPos, viewDir = ply:EyePos(), ply:GetAimVector()
        smoothFlashlightDir = LerpVector(FrameTime() * 6, smoothFlashlightDir or viewDir, viewDir)
        smoothFlashlightDir:Normalize()
        smoothFlashlightPos = LerpVector(FrameTime() * 20, smoothFlashlightPos or viewPos, viewPos)

        if not IsValid(hl2Flashlight) then
            hl2Flashlight = ProjectedTexture()
            if not IsValid(hl2Flashlight) then return end
            hl2Flashlight:SetTexture("effects/flashlight001")
            hl2Flashlight:SetFOV(60)
            hl2Flashlight:SetFarZ(1000)
            hl2Flashlight:SetNearZ(4)
            hl2Flashlight:SetEnableShadows(true)
        end

        local speed = ply:GetVelocity():Length2D()
        local isRunning = speed > 130
        local baseSine = math.sin(CurTime() * 4) * 0.05
        local currentIntensity = 0.95 + baseSine
        local flickerChance = isRunning and 82 or 96

        if math.random(1, 100) > flickerChance then
            currentIntensity = currentIntensity - math.Rand(0.3, 0.65)
        end

        if isExploded then
            local elapsed = CurTime() - explosionStartTime
            if elapsed < explosionDuration then
                local fade = 1 - (elapsed / explosionDuration)
                currentIntensity = currentIntensity * Lerp(fade, 1.0, 0.2)
            end
        end

        currentIntensity = math.Clamp(currentIntensity, 0.15, 1.0)
        hl2Flashlight:SetColor(Color(245 * currentIntensity, 235 * currentIntensity, 205 * currentIntensity, 255))
        hl2Flashlight:SetPos(smoothFlashlightPos)
        hl2Flashlight:SetAngles(smoothFlashlightDir:Angle())
        hl2Flashlight:Update()
    end)

    hook.Add("PreRender", "MuteAmbientOnEnding", function()
        if isEndingActive and IsValid(bgMusic) and LocalPlayer():GetNWBool("IsPsychoActive") then
            local elapsed = CurTime() - endingStartTime
            bgMusic:SetVolume(Lerp(math.Clamp(elapsed / endingDuration, 0, 1), 0.2, 0))
        end
    end)

    hook.Add("ShutDown", "RemoveFlashlightOnShutdown", RemoveHL2Flashlight)

    local bobCycle = 0
    local currentFOV = 75
    local function CoF_HeadBob_Fixed(ply, pos, angles, fov)
        if not IsValid(ply) then return end

        if isDyingClient then
            local elapsed = CurTime() - deathStartTime
            local fallProgress = math.Clamp(elapsed / 1.0, 0, 1)
            local smoothFall = math.ease.OutQuad(fallProgress)
            local targetPos = deathPos - Vector(0, 0, smoothFall * 54)
            local targetAng = Angle(deathAng.p, deathAng.y, deathAng.r)

            targetAng.Pitch = Lerp(smoothFall, deathAng.p, 20)
            currentDeathRoll = Lerp(FrameTime() * 5, currentDeathRoll, 75)
            targetAng.Roll = targetAng.Roll + currentDeathRoll

            if fallProgress >= 1 then
                local shake = math.Clamp(2.0 - (elapsed - 1.0), 0, 2.0)
                targetPos = targetPos + Vector(math.sin(CurTime() * 30) * 0.2 * shake, math.cos(CurTime() * 30) * 0.2 * shake, math.sin(CurTime() * 45) * 0.3 * shake)
            end

            local tr = util.TraceLine({ start = deathPos, endpos = targetPos, filter = ply })
            if tr.Hit then targetPos = tr.HitPos + tr.HitNormal * 3 end

            return { pos = targetPos, angles = targetAng, fov = math.Clamp(75 - (elapsed * 6), 45, 75), drawviewer = false }
        end

        local speed = ply:GetVelocity():Length2D()
        local currentStamina = ply:GetNWFloat("Stamina", 100)
        local targetFOV = (ply:KeyDown(IN_SPEED) and speed > 130 and currentStamina > 5 and ply:OnGround()) and 85 or 75

        if isExploded then
            local elapsed = CurTime() - explosionStartTime
            if elapsed < explosionDuration then
                local fade = 1 - (elapsed / explosionDuration)
                local shakeIntensity = fade * 4
                pos = pos + Vector(math.Rand(-shakeIntensity, shakeIntensity), math.Rand(-shakeIntensity, shakeIntensity), math.Rand(-shakeIntensity, shakeIntensity))
                angles.roll = angles.roll + math.Rand(-shakeIntensity, shakeIntensity)
            end
        end

        currentFOV = math.Approach(currentFOV, targetFOV, FrameTime() * 40)

        if ply:OnGround() and speed > 10 and not (isEndingActive and ply:GetNWBool("IsPsychoActive")) then
            bobCycle = bobCycle + (FrameTime() * speed * 0.06)
            local mul = math.Clamp(speed / 190, 0.1, 1.0)
            pos = pos + angles:Up() * (math.sin(bobCycle * 2) * 0.7 * mul)
            pos = pos + angles:Right() * (math.cos(bobCycle) * 0.4 * mul)
            angles.roll = angles.roll + (math.sin(bobCycle) * 0.7 * mul)
        end

        return { pos = pos + angles:Forward() * 1.5, angles = angles, fov = currentFOV }
    end
    hook.Add("CalcView", "CoF_Running_Shake_Hook", CoF_HeadBob_Fixed)

    hook.Add("InitPostEntity", "StartMapAmbient", function()
        timer.Simple(5, StartBackgroundMusic)
    end)

    hook.Add("ShutDown", "StopMapAmbient", function()
        if IsValid(bgMusic) then bgMusic:Stop() end
    end)
end