-----------------------------------------------------------------
-- File      : /lua/unit.lua
-- Authors   : John Comes, David Tomandl, Gordon Duclos
-- Summary   : The Unit lua module
-- Copyright © 2005 Gas Powered Games, Inc.  All rights reserved.
-----------------------------------------------------------------

-- Imports. Localise commonly used subfunctions for speed
local Entity = import('/lua/sim/Entity.lua').Entity
local EffectTemplate = import('/lua/EffectTemplates.lua')
local explosion = import('/lua/defaultexplosions.lua')
local utilities = import('/lua/utilities.lua')
local ApplyBuff = import('/lua/sim/buff.lua').ApplyBuff
local ApplyCheatBuffs = import('/lua/ai/aiutilities.lua').ApplyCheatBuffs
local BuffFieldBlueprints = import('/lua/sim/BuffField.lua').BuffFieldBlueprints
local wreckageCreateWreckage = import('/lua/wreckage.lua').CreateWreckage
local setEmpty = import('/lua/system/setutils.lua').Empty

local EffectUtilities = import('/lua/EffectUtilities.lua')
local CleanupEffectBag = EffectUtilities.CleanupEffectBag
local CreateUnitDestructionDebris = EffectUtilities.CreateUnitDestructionDebris

local GetConstructEconomyModel = import('/lua/game.lua').GetConstructEconomyModel
local IsRestricted = import('/lua/game.lua').IsRestricted
local VeteranDefault = import('/lua/game.lua').VeteranDefault

local Shield = import('/lua/shield.lua').Shield
local PersonalBubble = import('/lua/shield.lua').PersonalBubble
local TransportShield = import('/lua/shield.lua').TransportShield
local PersonalShield = import('/lua/shield.lua').PersonalShield
local AntiArtilleryShield = import('/lua/shield.lua').AntiArtilleryShield

-- Localised global functions for speed. ~10% for single references, ~30% for double (eg table.insert)
local tableInsert = table.insert
local tableRemove = table.remove
local tableGetn = table.getn
local tableGetsize = table.getsize
local tableEmpty = table.empty
local tableDeepCopy = table.deepcopy

local mathMax = math.max
local mathMin = math.min
local mathATan2 = math.atan2
local mathAbs = math.abs
local mathFloor = math.floor
local mathCos = math.cos
local mathSin = math.sin
local mathPi = math.pi

-- Entity Methods
local SetMesh = moho.entity_methods.SetMesh
local PlaySound = moho.entity_methods.PlaySound
local GetArmy = moho.entity_methods.GetArmy
local GetBlueprint = moho.entity_methods.GetBlueprint
local GetEntityId = moho.entity_methods.GetEntityId
local GetHealth = moho.entity_methods.GetHealth
local GetMaxHealth = moho.entity_methods.GetMaxHealth
local IsValidBone = moho.entity_methods.IsValidBone
local GetPosition = moho.entity_methods.GetPosition

-- Unit methods
local GetWeapon = moho.unit_methods.GetWeapon
local GetWeaponCount = moho.unit_methods.GetWeaponCount
local HideBone = moho.unit_methods.HideBone
local ShowBone = moho.unit_methods.ShowBone
local SetProductionActive = moho.unit_methods.SetProductionActive
local SetConsumptionPerSecondEnergy = moho.unit_methods.SetConsumptionPerSecondEnergy
local SetConsumptionPerSecondMass = moho.unit_methods.SetConsumptionPerSecondMass
local SetProductionPerSecondEnergy = moho.unit_methods.SetProductionPerSecondEnergy
local SetProductionPerSecondMass = moho.unit_methods.SetProductionPerSecondMass
local GetCurrentLayer = moho.unit_methods.GetCurrentLayer
local MohoGetBuildRate = moho.unit_methods.GetBuildRate

-- Misc methods
local ChangeState = ChangeState
local ForkThread = ForkThread
local WaitFor = WaitFor
local WaitTicks = coroutine.yield
local EntityCategoryContains = EntityCategoryContains
local ParseEntityCategory = ParseEntityCategory
local CreateEmitterAtBone = CreateEmitterAtBone
local CreateAttachedEmitter = CreateAttachedEmitter
local AttachBeamEntityToEntity = AttachBeamEntityToEntity
local DamageArea = DamageArea
local GetTerrainHeight = GetTerrainHeight
local GetTerrainType = GetTerrainType
local IsAlly = IsAlly

-- Deprecated function warning flags
local GetUnitBeingBuiltWarning = false
local GetBuildCostsWarning = false
local OnCreatedWarning = false
local CheckCanTakeDamageWarning = false
local SetCanTakeDamageWarning = false
local SetCanBeKilledWarning = false
local IsDeadWarning = false
local GetEconomyBuildRateWarning = false
local GetMassBuildAdjModWarning = false
local GetEnergyBuildAdjModWarning = false
local SetEnergyMaintenanceConsumptionOverrideWarning = false
local SetBuildRateOverrideWarning = false
local GetBuildRateOverrideWarning = false
local CheckCanBeKilledWarning = false

SyncMeta = {
    __index = function(t, key)
        local id = rawget(t, 'id')
        return UnitData[id].Data[key]
    end,

    __newindex = function(t, key, val)
        local id = rawget(t, 'id')
        local army = rawget(t, 'army')
        if not UnitData[id] then
            UnitData[id] = {
                OwnerArmy = rawget(t, 'army'),
                Data = {}
            }
        end
        UnitData[id].Data[key] = val

        local focus = GetFocusArmy()
        if army == focus or focus == -1 then -- Let observers get unit data
            if not Sync.UnitData[id] then
                Sync.UnitData[id] = {}
            end
            Sync.UnitData[id][key] = val
        end
    end,
}

Unit = Class(moho.unit_methods) {
    Weapons = {},

    FxScale = 1,
    FxDamageScale = 1,
    -- FX Damage tables. A random damage effect table of emitters is chosen out of this table
    FxDamage1 = {EffectTemplate.DamageSmoke01, EffectTemplate.DamageSparks01},
    FxDamage2 = {EffectTemplate.DamageFireSmoke01, EffectTemplate.DamageSparks01},
    FxDamage3 = {EffectTemplate.DamageFire01, EffectTemplate.DamageSparks01},

    -- Disables all collisions. This will be true for all units being constructed as upgrades
    DisallowCollisions = false,

    -- Destruction parameters
    PlayDestructionEffects = true,
    PlayEndAnimDestructionEffects = true,
    ShowUnitDestructionDebris = true,
    DestructionExplosionWaitDelayMin = 0,
    DestructionExplosionWaitDelayMax = 0.5,
    DeathThreadDestructionWaitTime = 0.1,
    DestructionPartsHighToss = {},
    DestructionPartsLowToss = {},
    DestructionPartsChassisToss = {},
    EconomyProductionInitiallyActive = true,

    GetSync = function(self)
        if not Sync.UnitData[self.EntityId] then
            Sync.UnitData[self.EntityId] = {}
        end
        return Sync.UnitData[self.EntityId]
    end,

    -- The original builder of this unit, set by OnStartBeingBuilt. Used for calculating differential
    -- upgrade costs, and tracking the original owner of a unit (for tracking gifting and so on)
    originalBuilder = nil,

    -------------------------------------------------------------------------------------------
    ---- INITIALIZATION
    -------------------------------------------------------------------------------------------
    OnPreCreate = function(self)
        self.EntityId = GetEntityId(self)

        -- Each unit has a sync table to replicate values to the global sync table to be copied to the user layer at sync time.
        self.Sync = {}
        self.Sync.id = self.EntityId
        self.Sync.army = GetArmy(self)

        setmetatable(self.Sync, SyncMeta)

        if not self.Trash then
            self.Trash = TrashBag()
        end

        self.IntelDisables = {
            Radar = {NotInitialized = true},
            Sonar = {NotInitialized = true},
            Omni = {NotInitialized = true},
            RadarStealth = {NotInitialized = true},
            SonarStealth = {NotInitialized = true},
            RadarStealthField = {NotInitialized = true},
            SonarStealthField = {NotInitialized = true},
            Cloak = {NotInitialized = true},
            CloakField = {NotInitialized = true}, -- We really shouldn't use this. Cloak/Stealth fields are pretty busted
            Spoof = {NotInitialized = true},
            Jammer = {NotInitialized = true},
        }

        self.EventCallbacks = {
            OnKilled = {},
            OnUnitBuilt = {},
            OnStartBuild = {},
            OnReclaimed = {},
            OnStartReclaim = {},
            OnStopReclaim = {},
            OnStopBeingBuilt = {},
            OnHorizontalStartMove = {},
            OnCaptured = {},
            OnCapturedNewUnit = {},
            OnDamaged = {},
            OnStartCapture = {},
            OnStopCapture = {},
            OnFailedCapture = {},
            OnStartBeingCaptured = {},
            OnStopBeingCaptured = {},
            OnFailedBeingCaptured = {},
            OnFailedToBuild = {},
            OnVeteran = {},
            OnGiven = {},
            ProjectileDamaged = {},
            SpecialToggleEnableFunction = false,
            SpecialToggleDisableFunction = false,

            OnAttachedToTransport = {}, -- Returns self, transport, bone
            OnDetachedFromTransport = {}, -- Returns self, transport, bone
        }
    end,

    OnCreate = function(self)
        Entity.OnCreate(self)
        -- Turn off land bones if this unit has them.
        self:HideLandBones()

        -- Set number of effects per damage depending on its volume
        local x, y, z = self:GetUnitSizes()
        local vol = x * y * z

        local damageamounts = 1
        if vol >= 20 then
            damageamounts = 6
            self.FxDamageScale = 2
        elseif vol >= 10 then
            damageamounts = 4
            self.FxDamageScale = 1.5
        elseif vol >= 0.5 then
            damageamounts = 2
        end

        self.FxDamage1Amount = self.FxDamage1Amount or damageamounts
        self.FxDamage2Amount = self.FxDamage2Amount or damageamounts
        self.FxDamage3Amount = self.FxDamage3Amount or damageamounts
        self.DamageEffectsBag = {
            {},
            {},
            {},
        }

        -- Set up effect emitter bags
        self.MovementEffectsBag = {}
        self.IdleEffectsBag = {}
        self.TopSpeedEffectsBag = {}
        self.BeamExhaustEffectsBag = {}
        self.TransportBeamEffectsBag = {}
        self.BuildEffectsBag = TrashBag()
        self.ReclaimEffectsBag = TrashBag()
        self.OnBeingBuiltEffectsBag = TrashBag()
        self.CaptureEffectsBag = TrashBag()
        self.UpgradeEffectsBag = TrashBag()
        self.TeleportFxBag = TrashBag()

        -- Store targets and attackers for proper Stealth management
        self.Targets = {}
        self.WeaponTargets = {}
        self.WeaponAttackers = {}

        -- Set up veterancy
        self.xp = 0
        self.Instigators = {}
        self.totalDamageTaken = 0

        self.debris_Vector = Vector(0, 0, 0)

        self.ID = self:GetUnitId()
        local bp = GetBlueprint(self)

        -- Save common lookup info
        self.techCategory = bp.TechCategory
        self.layerCategory = bp.LayerCategory
        self.factionCategory = bp.FactionCategory

        -- Define Economic modifications
        local bpEcon = bp.Economy
        SetConsumptionPerSecondEnergy(self, bpEcon.MaintenanceConsumptionPerSecondEnergy or 0)
        SetConsumptionPerSecondMass(self, bpEcon.MaintenanceConsumptionPerSecondMass or 0)
        SetProductionPerSecondEnergy(self, bpEcon.ProductionPerSecondEnergy or 0)
        SetProductionPerSecondMass(self, bpEcon.ProductionPerSecondMass or 0)

        if self.EconomyProductionInitiallyActive then
            SetProductionActive(self, true)
        end

        self.Buffs = {
            BuffTable = {},
            Affects = {},
        }

        self:SetIntelRadius('Vision', bp.Intel.VisionRadius or 0)

        self.CanTakeDamage = true
        self.CanBeKilled = true

        local bpDeathAnim = bp.Display.AnimationDeath
        if bpDeathAnim and tableGetn(bpDeathAnim) > 0 then
            self.PlayDeathAnimation = true
        end

        -- Used for keeping track of resource consumption
        self.MaintenanceConsumption = false
        self.ActiveConsumption = false
        self.ProductionEnabled = true
        self.EnergyModifier = 0
        self.MassModifier = 0

        -- Cheating
        if self:GetAIBrain().CheatEnabled then
            ApplyCheatBuffs(self)
        end

        self.Dead = false

        self:InitBuffFields()

        -- Ensure transport slots are available
        self.attachmentBone = nil

        -- Set up Adjacency container
        self.AdjacentUnits = {}

        self.Repairers = {}
    end,

    OnGotTarget = function(self, Weapon)
    end,

    OnLostTarget = function(self, Weapon)
    end,

    -------------------------------------------------------------------------------------------
    ---- MISC FUNCTIONS
    -------------------------------------------------------------------------------------------
    GetCachePosition = function(self)
        return GetPosition(self)
    end,

    GetFootPrintSize = function(self)
        if self.FootprintSize then
            return self.FootprintSize
        else
            local fp = GetBlueprint(self).Footprint
            self.FootprintSize = mathMax(fp.SizeX, fp.SizeZ)

            return self.FootprintSize
        end
    end,

    -- Returns collision box size
    GetUnitSizes = function(self)
        local bp = GetBlueprint(self)
        return bp.SizeX, bp.SizeY, bp.SizeZ
    end,

    GetRandomOffset = function(self, scalar)
        local sx, sy, sz = self:GetUnitSizes()
        local heading = self:GetHeading()
        sx = sx * scalar
        sy = sy * scalar
        sz = sz * scalar
        local rx = Random() * sx - (sx * 0.5)
        local y  = Random() * sy + (GetBlueprint(self).CollisionOffsetY or 0)
        local rz = Random() * sz - (sz * 0.5)
        local x = mathCos(heading) * rx - mathSin(heading) * rz
        local z = mathSin(heading) * rx - mathCos(heading) * rz

        return x, y, z
    end,

    ForkThread = function(self, fn, ...)
        if fn then
            local thread = ForkThread(fn, self, unpack(arg))
            self.Trash:Add(thread)
            return thread
        else
            return nil
        end
    end,

    SetTargetPriorities = function(self, priTable)
        for i = 1, GetWeaponCount(self) do
            local wep = GetWeapon(self, i)
            wep:SetWeaponPriorities(priTable)
        end
    end,

    SetLandTargetPriorities = function(self, priTable)
        for i = 1, GetWeaponCount(self) do
            local wep = GetWeapon(self, i)

            for onLayer, targetLayers in GetBlueprint(wep).FireTargetLayerCapsTable do
                if string.find(targetLayers, 'Land') then
                    wep:SetWeaponPriorities(priTable)
                    break
                end
            end
        end
    end,

    -- Updates build restrictions of any unit passed, used for support factories
    updateBuildRestrictions = function(self)
        local bp = GetBlueprint(self)
        local faction = categories[bp.FactionCategory]
        local type = categories[bp.LayerCategory]
        local aiBrain = self:GetAIBrain()
        local supportfactory = false

        -- Sanity check.
        if not faction then
            return
        end

        -- Add build restrictions
        if bp.CategoriesHash.FACTORY then
            if bp.CategoriesHash.SUPPORTFACTORY then
                -- Add support factory cannot build higher tech units at all, until there is a HQ factory
                self:AddBuildRestriction(categories.TECH2 * categories.MOBILE)
                self:AddBuildRestriction(categories.TECH3 * categories.MOBILE)
                self:AddBuildRestriction(categories.TECH3 * categories.FACTORY)
                supportfactory = true
            else
                -- A normal factory cannot build a support factory until there is a HQ factory
                self:AddBuildRestriction(categories.SUPPORTFACTORY)
                supportfactory = false
            end
        elseif bp.CategoriesHash.ENGINEER then
            -- Engineers also cannot build a support factory until there is a HQ factory
            self:AddBuildRestriction(categories.SUPPORTFACTORY)
        end

        -- Check for the existence of HQs
        if supportfactory then
            if not type then
                return
            end
            for id, unit in aiBrain:GetListOfUnits(categories.RESEARCH * categories.TECH2 * faction, false, true) do
                if not unit.Dead and not unit:IsBeingBuilt() then
                    self:RemoveBuildRestriction(categories.TECH2 * categories.MOBILE * categories.CONSTRUCTION)
                end
            end
            for id, unit in aiBrain:GetListOfUnits(categories.RESEARCH * categories.TECH3 * faction, false, true) do
                if not unit.Dead and not unit:IsBeingBuilt() then
                    self:RemoveBuildRestriction(categories.TECH2 * categories.MOBILE * categories.CONSTRUCTION)
                    self:RemoveBuildRestriction(categories.TECH3 * categories.MOBILE * categories.CONSTRUCTION)
                    break
                end
            end
            for id, unit in aiBrain:GetListOfUnits(categories.RESEARCH * categories.TECH2 * faction * type, false, true) do
                if not unit.Dead and not unit:IsBeingBuilt() then
                    self:RemoveBuildRestriction(categories.TECH2 * categories.MOBILE)
                    break
                end
            end
            for id, unit in aiBrain:GetListOfUnits(categories.RESEARCH * categories.TECH3 * faction * type, false, true) do
                if not unit.Dead and not unit:IsBeingBuilt() then
                    self:RemoveBuildRestriction(categories.TECH2 * categories.MOBILE)
                    self:RemoveBuildRestriction(categories.TECH3 * categories.MOBILE)
                    self:RemoveBuildRestriction(categories.TECH3 * categories.FACTORY * categories.SUPPORTFACTORY)
                    break
                end
            end
        else
            for _, researchType in ipairs({categories.LAND, categories.AIR, categories.NAVAL}) do
                -- If there is a research station of the appropriate type, enable support factory construction
                for id, unit in aiBrain:GetListOfUnits(categories.RESEARCH * categories.TECH2 * faction * researchType, false, true) do
                    if not unit.Dead and not unit:IsBeingBuilt() then
                        -- Special case for the Commander, since its engineering upgrades are implemented using build restrictions
                        -- In future, figure out a way to query existing legal builds? For example, check if you can build T2, if you can, enable support factory too
                        if bp.CategoriesHash.COMMAND then
                            if self:HasEnhancement('AdvancedEngineering') or self:HasEnhancement('T3Engineering') then
                                self:RemoveBuildRestriction(categories.TECH2 * categories.SUPPORTFACTORY * faction * researchType)
                            end
                        else
                            self:RemoveBuildRestriction(categories.TECH2 * categories.SUPPORTFACTORY * faction * researchType)
                        end
                        break
                    end
                end
                for id, unit in aiBrain:GetListOfUnits(categories.RESEARCH * categories.TECH3 * faction * researchType, false, true) do
                    if not unit.Dead and not unit:IsBeingBuilt() then

                        -- Special case for the commander, since its engineering upgrades are implemented using build restrictions
                        if bp.CategoriesHash.COMMAND then
                            if self:HasEnhancement('AdvancedEngineering') then
                                self:RemoveBuildRestriction(categories.TECH2 * categories.SUPPORTFACTORY * faction * researchType)
                            elseif self:HasEnhancement('T3Engineering') then
                                self:RemoveBuildRestriction(categories.TECH2 * categories.SUPPORTFACTORY * faction * researchType)
                                self:RemoveBuildRestriction(categories.TECH3 * categories.SUPPORTFACTORY * faction * researchType)
                            end
                        else
                            self:RemoveBuildRestriction(categories.TECH2 * categories.SUPPORTFACTORY * faction * researchType)
                            self:RemoveBuildRestriction(categories.TECH3 * categories.SUPPORTFACTORY * faction * researchType)
                        end

                        break
                    end
                end
            end
        end
    end,

    -------------------------------------------------------------------------------------------
    ---- TOGGLES
    -------------------------------------------------------------------------------------------
     OnScriptBitSet = function(self, bit)
        if bit == 0 then -- Shield toggle
            self:PlayUnitAmbientSound('ActiveLoop')
            self:EnableShield()
        elseif bit == 1 then -- Weapon toggle
            -- Amended in individual unit's script file
        elseif bit == 2 then -- Jamming toggle
            self:StopUnitAmbientSound('ActiveLoop')
            self:SetMaintenanceConsumptionInactive()
            self:DisableUnitIntel('ToggleBit2', 'Jammer')
        elseif bit == 3 then -- Intel toggle
            self:StopUnitAmbientSound('ActiveLoop')
            self:SetMaintenanceConsumptionInactive()
            self:DisableUnitIntel('ToggleBit3', 'RadarStealth')
            self:DisableUnitIntel('ToggleBit3', 'RadarStealthField')
            self:DisableUnitIntel('ToggleBit3', 'SonarStealth')
            self:DisableUnitIntel('ToggleBit3', 'SonarStealthField')
            self:DisableUnitIntel('ToggleBit3', 'Sonar')
            self:DisableUnitIntel('ToggleBit3', 'Omni')
            self:DisableUnitIntel('ToggleBit3', 'Cloak')
            self:DisableUnitIntel('ToggleBit3', 'CloakField') -- We really shouldn't use this. Cloak/Stealth fields are pretty busted
            self:DisableUnitIntel('ToggleBit3', 'Spoof')
            self:DisableUnitIntel('ToggleBit3', 'Jammer')
            self:DisableUnitIntel('ToggleBit3', 'Radar')
        elseif bit == 4 then -- Production toggle
            self:OnProductionPaused()
        elseif bit == 5 then -- Stealth toggle
            self:StopUnitAmbientSound('ActiveLoop')
            self:SetMaintenanceConsumptionInactive()
            self:DisableUnitIntel('ToggleBit5', 'RadarStealth')
            self:DisableUnitIntel('ToggleBit5', 'RadarStealthField')
            self:DisableUnitIntel('ToggleBit5', 'SonarStealth')
            self:DisableUnitIntel('ToggleBit5', 'SonarStealthField')
        elseif bit == 6 then -- Generic pause toggle
            self:SetPaused(true)
        elseif bit == 7 then -- Special toggle
            self:EnableSpecialToggle()
        elseif bit == 8 then -- Cloak toggle
            self:StopUnitAmbientSound('ActiveLoop')
            self:SetMaintenanceConsumptionInactive()
            self:DisableUnitIntel('ToggleBit8', 'Cloak')
        end

        if not self.MaintenanceConsumption then
            self.ToggledOff = true
        end
    end,

    OnScriptBitClear = function(self, bit)
        if bit == 0 then -- Shield toggle
            self:StopUnitAmbientSound('ActiveLoop')
            self:DisableShield()
        elseif bit == 1 then -- Weapon toggle
        elseif bit == 2 then -- Jamming toggle
            self:PlayUnitAmbientSound('ActiveLoop')
            self:SetMaintenanceConsumptionActive()
            self:EnableUnitIntel('ToggleBit2', 'Jammer')
        elseif bit == 3 then -- Intel toggle
            self:PlayUnitAmbientSound('ActiveLoop')
            self:SetMaintenanceConsumptionActive()
            self:EnableUnitIntel('ToggleBit3', 'Radar')
            self:EnableUnitIntel('ToggleBit3', 'RadarStealth')
            self:EnableUnitIntel('ToggleBit3', 'RadarStealthField')
            self:EnableUnitIntel('ToggleBit3', 'SonarStealth')
            self:EnableUnitIntel('ToggleBit3', 'SonarStealthField')
            self:EnableUnitIntel('ToggleBit3', 'Sonar')
            self:EnableUnitIntel('ToggleBit3', 'Omni')
            self:EnableUnitIntel('ToggleBit3', 'Cloak')
            self:EnableUnitIntel('ToggleBit3', 'CloakField') -- We really shouldn't use this. Cloak/Stealth fields are pretty busted
            self:EnableUnitIntel('ToggleBit3', 'Spoof')
            self:EnableUnitIntel('ToggleBit3', 'Jammer')
        elseif bit == 4 then -- Production toggle
            self:OnProductionUnpaused()
        elseif bit == 5 then -- Stealth toggle
            self:PlayUnitAmbientSound('ActiveLoop')
            self:SetMaintenanceConsumptionActive()
            self:EnableUnitIntel('ToggleBit5', 'RadarStealth')
            self:EnableUnitIntel('ToggleBit5', 'RadarStealthField')
            self:EnableUnitIntel('ToggleBit5', 'SonarStealth')
            self:EnableUnitIntel('ToggleBit5', 'SonarStealthField')
        elseif bit == 6 then -- Generic pause toggle
            self:SetPaused(false)
        elseif bit == 7 then -- Special toggle
            self:DisableSpecialToggle()
        elseif bit == 8 then -- Cloak toggle
            self:PlayUnitAmbientSound('ActiveLoop')
            self:SetMaintenanceConsumptionActive()
            self:EnableUnitIntel('ToggleBit8', 'Cloak')
        end

        if self.MaintenanceConsumption then
            self.ToggledOff = false
        end
    end,

    OnPaused = function(self)
        self:SetActiveConsumptionInactive()
        self:StopUnitAmbientSound('ConstructLoop')
    end,

    OnUnpaused = function(self)
        if self:IsUnitState('Building') or self:IsUnitState('Upgrading') or self:IsUnitState('Repairing') then
            self:SetActiveConsumptionActive()
            self:PlayUnitAmbientSound('ConstructLoop')
        end
    end,

    EnableSpecialToggle = function(self)
        if self.EventCallbacks.SpecialToggleEnableFunction then
            self.EventCallbacks.SpecialToggleEnableFunction(self)
        end
    end,

    DisableSpecialToggle = function(self)
        if self.EventCallbacks.SpecialToggleDisableFunction then
            self.EventCallbacks.SpecialToggleDisableFunction(self)
        end
    end,

    AddSpecialToggleEnable = function(self, fn)
        if fn then
            self.EventCallbacks.SpecialToggleEnableFunction = fn
        end
    end,

    AddSpecialToggleDisable = function(self, fn)
        if fn then
            self.EventCallbacks.SpecialToggleDisableFunction = fn
        end
    end,

    EnableDefaultToggleCaps = function(self)
        if self.ToggleCaps then
            for _, v in self.ToggleCaps do
                self:AddToggleCap(v)
            end
        end
    end,

    DisableDefaultToggleCaps = function(self)
        self.ToggleCaps = {}
        local capsCheckTable = {'RULEUTC_WeaponToggle', 'RULEUTC_ProductionToggle', 'RULEUTC_GenericToggle', 'RULEUTC_SpecialToggle'}
        for _, v in capsCheckTable do
            if self:TestToggleCaps(v) == true then
                tableInsert(self.ToggleCaps, v)
            end
            self:RemoveToggleCap(v)
        end
    end,

    -------------------------------------------------------------------------------------------
    ---- MISC EVENTS
    -------------------------------------------------------------------------------------------
    OnSpecialAction = function(self, location)
    end,

    OnProductionActive = function(self)
    end,

    OnActive = function(self)
    end,

    OnInactive = function(self)
    end,

    OnStartCapture = function(self, target)
        self:DoUnitCallbacks('OnStartCapture', target)
        self:StartCaptureEffects(target)
        self:PlayUnitSound('StartCapture')
        self:PlayUnitAmbientSound('CaptureLoop')
    end,

    OnStopCapture = function(self, target)
        self:DoUnitCallbacks('OnStopCapture', target)
        self:StopCaptureEffects(target)
        self:PlayUnitSound('StopCapture')
        self:StopUnitAmbientSound('CaptureLoop')
    end,

    StartCaptureEffects = function(self, target)
        self.CaptureEffectsBag:Add(self:ForkThread(self.CreateCaptureEffects, target))
    end,

    CreateCaptureEffects = function(self, target)
    end,

    StopCaptureEffects = function(self, target)
        self.CaptureEffectsBag:Destroy()
    end,

    OnFailedCapture = function(self, target)
        self:DoUnitCallbacks('OnFailedCapture', target)
        self:StopCaptureEffects(target)
        self:StopUnitAmbientSound('CaptureLoop')
        self:PlayUnitSound('FailedCapture')
    end,

    CheckCaptor = function(self, captor)
        if captor.Dead or captor:GetFocusUnit() ~= self then
            self:RemoveCaptor(captor)
        else
            local progress = captor:GetWorkProgress()
            if not self.CaptureProgress or progress > self.CaptureProgress then
                self.CaptureProgress = progress
            elseif progress < self.CaptureProgress then
                captor:SetWorkProgress(self.CaptureProgress)
            end
        end
    end,

    AddCaptor = function(self, captor)
        if not self.Captors then
            self.Captors = {}
        end

        self.Captors[captor.EntityId] = captor

        if not self.CaptureThread then
            self.CaptureThread = self:ForkThread(function()
                local captors = self.Captors or {}
                while tableGetsize(captors) > 0 do
                    for _, c in captors do
                        self:CheckCaptor(c)
                    end

                    WaitTicks(1)
                    captors = self.Captors or {}
                end
            end)
        end
    end,

    ResetCaptors = function(self)
        if self.CaptureThread then
            KillThread(self.CaptureThread)
        end
        self.Captors = {}
        self.CaptureThread = nil
        self.CaptureProgress = nil
    end,

    RemoveCaptor = function(self, captor)
        self.Captors[captor.EntityId] = nil

        if tableGetsize(self.Captors) == 0 then
            self:ResetCaptors()
        end
    end,

    OnStartBeingCaptured = function(self, captor)
        self:AddCaptor(captor)
        self:DoUnitCallbacks('OnStartBeingCaptured', captor)
        self:PlayUnitSound('StartBeingCaptured')
    end,

    OnStopBeingCaptured = function(self, captor)
        self:RemoveCaptor(captor)
        self:DoUnitCallbacks('OnStopBeingCaptured', captor)
        self:PlayUnitSound('StopBeingCaptured')
    end,

    OnFailedBeingCaptured = function(self, captor)
        self:RemoveCaptor(captor)
        self:DoUnitCallbacks('OnFailedBeingCaptured', captor)
        self:PlayUnitSound('FailedBeingCaptured')
    end,

    OnReclaimed = function(self, entity)
        self:DoUnitCallbacks('OnReclaimed', entity)
        self.CreateReclaimEndEffects(entity, self)
        self:Destroy()
    end,

    OnStartRepair = function(self, unit)
        unit.Repairers[self.EntityId] = self

        if unit.WorkItem ~= self.WorkItem then
            self:InheritWork(unit)
        end

        self:SetUnitState('Repairing', true)

        -- Force assist over repair when unit is assisting something
        if unit:GetFocusUnit() and unit:IsUnitState('Building') then
            self:ForkThread(function()
                self:CheckAssistFocus()
            end)
        end
    end,

    OnStopRepair = function(self, unit)
    end,

    OnStartReclaim = function(self, target)
        self:SetUnitState('Reclaiming', true)
        self:SetFocusEntity(target)
        self:CheckAssistersFocus()
        self:DoUnitCallbacks('OnStartReclaim', target)
        self:StartReclaimEffects(target)
        self:PlayUnitSound('StartReclaim')
        self:PlayUnitAmbientSound('ReclaimLoop')

        -- Force me to move on to the guard properly when done
        local guard = self:GetGuardedUnit()
        if guard then
            IssueClearCommands({self})
            IssueReclaim({self}, target)
            IssueGuard({self}, guard)
        end
    end,

    OnStopReclaim = function(self, target)
        self:DoUnitCallbacks('OnStopReclaim', target)
        self:StopReclaimEffects(target)
        self:StopUnitAmbientSound('ReclaimLoop')
        self:PlayUnitSound('StopReclaim')
        self:SetUnitState('Reclaiming', false)
        if target.MaxMassReclaim then -- This is a prop
            target:UpdateReclaimLeft()
        end
    end,

    StartReclaimEffects = function(self, target)
        self.ReclaimEffectsBag:Add(self:ForkThread(self.CreateReclaimEffects, target))
    end,

    CreateReclaimEffects = function(self, target)
    end,

    CreateReclaimEndEffects = function(self, target)
    end,

    StopReclaimEffects = function(self, target)
        self.ReclaimEffectsBag:Destroy()
    end,

    OnDecayed = function(self)
        self:Destroy()
    end,

    OnCaptured = function(self, captor)
        if self and not self.Dead and captor and not captor.Dead and self:GetAIBrain() ~= captor:GetAIBrain() then
            if not self:IsCapturable() then
                self:Kill()
                return
            end

            -- Kill non-capturable things which are in a transport
            local bp = GetBlueprint(self)
            if bp.CategoriesHash.TRANSPORTATION then
                local cargo = self:GetCargo()
                for _, v in cargo do
                    if not v.Dead and not v:IsCapturable() then
                        v:Kill()
                    end
                end
            end

            self:DoUnitCallbacks('OnCaptured', captor)
            local newUnitCallbacks = {}
            if self.EventCallbacks.OnCapturedNewUnit then
                newUnitCallbacks = self.EventCallbacks.OnCapturedNewUnit
            end

            local captorArmyIndex = GetArmy(captor)
            local captorBrain = false

            -- Ignore army cap during unit transfer in Campaign
            if ScenarioInfo.CampaignMode then
                captorBrain = captor:GetAIBrain()
                SetIgnoreArmyUnitCap(captorArmyIndex, true)
            end

            if ScenarioInfo.CampaignMode and not captorBrain.IgnoreArmyCaps then
                SetIgnoreArmyUnitCap(captorArmyIndex, false)
            end

            -- Fix captured units not retaining their data
            self:ResetCaptors()
            local newUnits = import('/lua/SimUtils.lua').TransferUnitsOwnership({self}, captorArmyIndex) or {}

            -- The unit transfer function returns a table of units. Since we transferred 1 unit, the table contains 1 unit (The new unit).
            -- If table would have been nil (Set to {} above), was empty, or contains more than one, kill this sequence
            if tableEmpty(newUnits) or tableGetn(newUnits) ~= 1 then
                return
            end

            local newUnit = newUnits[1]

            -- Because the old unit is lost we cannot call a member function for newUnit callbacks
            for _, cb in newUnitCallbacks do
                if cb then
                    cb(newUnit, captor)
                end
            end
        end
    end,

    OnGiven = function(self, newUnit)
        newUnit:SendNotifyMessage('transferred')
        self:DoUnitCallbacks('OnGiven', newUnit)
    end,

    AddOnGivenCallback = function(self, fn)
        self:AddUnitCallback(fn, 'OnGiven')
    end,

    -------------------------------------------------------------------------------------------
    -- ECONOMY
    -------------------------------------------------------------------------------------------
    OnConsumptionActive = function(self)
    end,

    OnConsumptionInActive = function(self)
    end,

    -- We are splitting Consumption into two catagories:
    -- Maintenance -- for units that are usually "on": radar, mass extractors, etc.
    -- Active -- when upgrading, constructing, or something similar.
    --
    -- It will be possible for both or neither of these consumption methods to be
    -- in operation at the same time.  Here are the functions to turn them off and on.
    SetMaintenanceConsumptionActive = function(self)
        self.MaintenanceConsumption = true
        self:UpdateConsumptionValues()
    end,

    SetMaintenanceConsumptionInactive = function(self)
        self.MaintenanceConsumption = false
        self:UpdateConsumptionValues()
    end,

    SetActiveConsumptionActive = function(self)
        self.ActiveConsumption = true
        self:UpdateConsumptionValues()
    end,

    SetActiveConsumptionInactive = function(self)
        self.ActiveConsumption = false
        self:UpdateConsumptionValues()
    end,

    OnProductionPaused = function(self)
        self:SetMaintenanceConsumptionInactive()
        SetProductionActive(self, false)
    end,

    OnProductionUnpaused = function(self)
        self:SetMaintenanceConsumptionActive()
        SetProductionActive(self, true)
    end,

    SetBuildTimeMultiplier = function(self, time_mult)
        self.BuildTimeMultiplier = time_mult
    end,

    GetBuildRate = function(self)
        return mathMax(MohoGetBuildRate(self), 0.00001) -- Make sure we're never returning 0, this value will be used to divide with
    end,

    UpdateAssistersConsumption = function(self)
        local units = {}
        -- We need to check all the units assisting.
        for _, v in self:GetGuards() do
            if not v.Dead then
                tableInsert(units, v)
            end
        end

        local workers = self:GetAIBrain():GetUnitsAroundPoint(categories.REPAIR, GetPosition(self), 50, 'Ally')
        for _, v in workers do
            if not v.Dead and v:IsUnitState('Repairing') and v:GetFocusUnit() == self then
                tableInsert(units, v)
            end
        end

        for _, v in units do
            if not v.updatedConsumption then
                v.updatedConsumption = true -- Recursive protection
                v:UpdateConsumptionValues()
                v.updatedConsumption = false
            end
        end
    end,

    -- Called when we start building a unit, turn on/off, get/lose bonuses, or on
    -- any other change that might affect our build rate or resource use.
    UpdateConsumptionValues = function(self)
        local energy_rate = 0
        local mass_rate = 0
        local bpEconomy = GetBlueprint(self).Economy

        if self.ActiveConsumption then
            local focus = self:GetFocusUnit()
            local time = 1
            local mass = 0
            local energy = 0
            local targetData
            local baseData
            local bpFocus = GetBlueprint(focus)

            if focus then -- Always inherit work status of focus
                self:InheritWork(focus)
            end

            if self.WorkItem then -- Enhancement
                targetData = self.WorkItem
            elseif focus then -- Handling upgrades
                local originalBuilder = focus.originalBuilder

                if self:IsUnitState('Upgrading') then
                    baseData = bpEconomy -- Upgrading myself, subtract ev. baseCost
                elseif originalBuilder and not originalBuilder.Dead and originalBuilder:IsUnitState('Upgrading') and originalBuilder:GetFocusUnit() == focus then
                    baseData = bpEconomy
                end

                if baseData then
                    targetData = bpFocus.Economy
                end
            end

            if targetData then -- Upgrade/enhancement
                time, energy, mass = GetConstructEconomyModel(self, targetData, baseData)
            elseif focus then -- Building/repairing something
                if focus:IsUnitState('SiloBuildingAmmo') then
                    local siloBuildRate = focus:GetBuildRate() or 1
                    time, energy, mass = GetConstructEconomyModel(focus, focus.SiloProjectile)
                    energy = (energy / siloBuildRate) * (self:GetBuildRate() or 1)
                    mass = (mass / siloBuildRate) * (self:GetBuildRate() or 1)
                else
                    time, energy, mass = GetConstructEconomyModel(self, bpFocus)
                end
            end

            energy = mathMax(1, energy * (self.EnergyBuildAdjMod or 1))
            mass = mathMax(1, mass * (self.MassBuildAdjMod or 1))
            energy_rate = energy / time
            mass_rate = mass / time
        end

        self:UpdateAssistersConsumption()

        if self.MaintenanceConsumption then
            local mai_energy = (self.EnergyMaintenanceConsumptionOverride or bpEconomy.MaintenanceConsumptionPerSecondEnergy)  or 0
            local mai_mass = bpEconomy.MaintenanceConsumptionPerSecondMass or 0

            -- Apply economic bonuses
            mai_energy = mai_energy * (100 + self.EnergyModifier) * (self.EnergyMaintAdjMod or 1) * 0.01
            mai_mass = mai_mass * (100 + self.MassModifier) * (self.MassMaintAdjMod or 1) * 0.01

            energy_rate = energy_rate + mai_energy
            mass_rate = mass_rate + mai_mass
        end

         -- Apply minimum rates
        energy_rate = mathMax(energy_rate, bpEconomy.MinConsumptionPerSecondEnergy or 0)
        mass_rate = mathMax(mass_rate, bpEconomy.MinConsumptionPerSecondMass or 0)

        SetConsumptionPerSecondEnergy(self, energy_rate)
        SetConsumptionPerSecondMass(self, mass_rate)
        self:SetConsumptionActive(energy_rate > 0 or mass_rate > 0)
    end,

    UpdateProductionValues = function(self)
        local bpEcon = GetBlueprint(self).Economy
        if not bpEcon then return end

        SetProductionPerSecondEnergy(self, (bpEcon.ProductionPerSecondEnergy or 0) * (self.EnergyProdAdjMod or 1))
        SetProductionPerSecondMass(self, (bpEcon.ProductionPerSecondMass or 0) * (self.MassProdAdjMod or 1))
    end,

    -------------------------------------------------------------------------------------------
    -- DAMAGE
    -------------------------------------------------------------------------------------------

    OnDamage = function(self, instigator, amount, vector, damageType)
        if self.CanTakeDamage then
            self:DoOnDamagedCallbacks(instigator)

            -- Pass damage to an active personal shield, as personal shields no longer have collisions
            local shield = self.Shield
            if shield and shield.ShieldType == 'Personal' and shield:IsOn() and not shield.Charging then
                self.MyShield:ApplyDamage(instigator, amount, vector, damageType)
            else
                self:DoTakeDamage(instigator, amount, vector, damageType)
            end
        end
    end,

    DoTakeDamage = function(self, instigator, amount, vector, damageType)
        local preAdjHealth = GetHealth(self)

        -- Keep track of incoming damage, but only if it is from a unit
        if instigator and IsUnit(instigator) and instigator ~= self then
            amountForVet = math.min(amount, preAdjHealth) -- Don't let massive alpha (OC, Percy etc) skew which unit gets vet
            self.totalDamageTaken = self.totalDamageTaken + amountForVet

            -- We want to keep track of damage from things that cannot gain vet (deathweps etc)
            -- But not enter them into the table to have credit dispersed later
            if instigator.gainsVeterancy then
                local previousDamage = self.Instigators[instigator.EntityId].damage
                if previousDamage then
                    self.Instigators[instigator.EntityId].damage = previousDamage + amountForVet
                else
                    self.Instigators[instigator.EntityId] = {unit = instigator, damage = amountForVet}
                end
            end
        end

        self:AdjustHealth(instigator, -amount)

        local health = GetHealth(self)
        if health < 1 then
            if damageType == 'Reclaimed' then
                self:Destroy()
            else
                local excessDamageRatio = 0.0
                -- Calculate the excess damage amount
                local excess = preAdjHealth - amount
                local maxHealth = GetMaxHealth(self)
                if excess < 0 and maxHealth > 0 then
                    excessDamageRatio = -excess / maxHealth
                end

                self:Kill(instigator, damageType, excessDamageRatio)
            end
        end

        if health < 1 or self.Dead then
            self.debris_Vector = vector or ''
        end
    end,

    ManageDamageEffects = function(self, newHealth, oldHealth)
        -- Health values come in at fixed 25% intervals
        if newHealth < oldHealth then
            if oldHealth == 0.75 then
                for i = 1, self.FxDamage1Amount do
                    self:PlayDamageEffect(self.FxDamage1, self.DamageEffectsBag[1])
                end
            elseif oldHealth == 0.5 then
                for i = 1, self.FxDamage2Amount do
                    self:PlayDamageEffect(self.FxDamage2, self.DamageEffectsBag[2])
                end
            elseif oldHealth == 0.25 then
                for i = 1, self.FxDamage3Amount do
                    self:PlayDamageEffect(self.FxDamage3, self.DamageEffectsBag[3])
                end
            end
        else
            if newHealth <= 0.25 and newHealth > 0 then
                for _, v in self.DamageEffectsBag[3] do
                    v:Destroy()
                end
            elseif newHealth <= 0.5 and newHealth > 0.25 then
                for _, v in self.DamageEffectsBag[2] do
                    v:Destroy()
                end
            elseif newHealth <= 0.75 and newHealth > 0.5 then
                for _, v in self.DamageEffectsBag[1] do
                    v:Destroy()
                end
            elseif newHealth > 0.75 then
                self:DestroyAllDamageEffects()
            end
        end
    end,

    PlayDamageEffect = function(self, fxTable, fxBag)
        local effects = fxTable[Random(1, tableGetn(fxTable))]
        if not effects then return end

        local totalBones = self:GetBoneCount()
        local bone = Random(1, totalBones) - 1
        local bpDE = GetBlueprint(self).Display.DamageEffects
        local army = GetArmy(self)
        for _, v in effects do
            local fx
            if bpDE then
                local num = Random(1, tableGetsize(bpDE))
                local bpFx = bpDE[num]
                fx = CreateAttachedEmitter(self, bpFx.Bone or 0, army, v):ScaleEmitter(self.FxDamageScale):OffsetEmitter(bpFx.OffsetX or 0, bpFx.OffsetY or 0, bpFx.OffsetZ or 0)
            else
                fx = CreateAttachedEmitter(self, bone, army, v):ScaleEmitter(self.FxDamageScale)
            end
            tableInsert(fxBag, fx)
        end
    end,

    OnHealthChanged = function(self, new, old)
        self:ManageDamageEffects(new, old)
    end,

    DestroyAllDamageEffects = function(self)
        for kb, vb in self.DamageEffectsBag do
            for ke, ve in vb do
                ve:Destroy()
            end
        end
    end,

    -- On killed: this function plays when the unit takes a mortal hit. Plays death effects and spawns wreckage, dependant on overkill
    OnKilled = function(self, instigator, type, overkillRatio)
        local layer = GetCurrentLayer(self)
        self.Dead = true

        -- Units killed while being invisible because they're teleporting should show when they're killed
        if self.TeleportFx_IsInvisible then
            ShowBone(self, 0, true)
            self:ShowEnhancementBones()
        end

        local bp = GetBlueprint(self)
        if layer == 'Water' and bp.Physics.MotionType == 'RULEUMT_Hover' then
            self:PlayUnitSound('HoverKilledOnWater')
        elseif layer == 'Land' and bp.Physics.MotionType == 'RULEUMT_AmphibiousFloating' then
            -- Handle ships that can walk on land
            self:PlayUnitSound('AmphibiousFloatingKilledOnLand')
        else
            self:PlayUnitSound('Killed')
        end

        if self.PlayDeathAnimation and self:GetFractionComplete() > 0.5 then
            self:ForkThread(self.PlayAnimationThread, 'AnimationDeath')
            self.DisallowCollisions = true
        end

        self:DoUnitCallbacks('OnKilled')

        if self.UnitBeingTeleported and not self.UnitBeingTeleported.Dead then
            self.UnitBeingTeleported:Destroy()
            self.UnitBeingTeleported = nil
        end

        -- Notify instigator of kill and spread veterancy
        -- We prevent any vet spreading if the instigator isn't part of the vet system (EG - Self destruct)
        -- This is so that you can bring a damaged Experimental back to base, kill, and rebuild, without granting
        -- instant vet to the enemy army, as well as other obscure reasons
        if self.totalDamageTaken > 0 and not self.veterancyDispersed then
            self:VeterancyDispersal(not instigator or not IsUnit(instigator))
        end

        ArmyBrains[GetArmy(self)].LastUnitKilledBy = GetArmy(instigator or self)

        if self.DeathWeaponEnabled ~= false then
            self:DoDeathWeapon()
        end

        self:DisableShield()
        self:DisableUnitIntel('Killed')
        self:ForkThread(self.DeathThread, overkillRatio , instigator)

        ArmyBrains[GetArmy(self)]:AddUnitStat(self:GetUnitId(), "lost", 1)
    end,

    -- This section contains functions used by the new mass-based veterancy system
    ------------------------------------------------------------------------------

    -- Tell any living instigators that they need to gain some veterancy
    VeterancyDispersal = function(self, suicide)
        local bp = GetBlueprint(self)
        local mass = self:GetVeterancyValue()
        -- Adjust mass based on current health when a unit is self destructed
        if suicide then
            mass = mass * (1 - GetHealth(self) / GetMaxHealth(self))
        end

        -- Non-combat structures only give 50% veterancy
        if not self.gainsVeterancy and EntityCategoryContains(categories.STRUCTURE, self) then
            mass = mass * 0.5
        end

        for _, data in self.Instigators do
            local unit = data.unit
            -- Make sure the unit is something which can vet, and is not maxed
            if unit and not unit.Dead and unit.gainsVeterancy and unit.Sync.VeteranLevel < 5 then
                -- Find the proportion of yourself that each instigator killed
                local massKilled = math.floor(mass * (data.damage / self.totalDamageTaken))
                unit:OnKilledUnit(self, massKilled)
            end
        end
    end,

    GetVeterancyValue = function(self)
        local bp = self:GetBlueprint()
        local mass = bp.Economy.BuildCostMass
        local fractionComplete = self:GetFractionComplete()

        if fractionComplete == 1 then
            -- Add the value of any enhancements
            local enhancements = SimUnitEnhancements[self.EntityId]
            if enhancements then
                for _, name in enhancements do
                    mass = mass + bp.Enhancements[name].BuildCostMass or 0
                end
            end

            -- Subtract the value of any enhancements from a preset because their value is included in bp.Economy.BuildCostMass
            if bp.EnhancementPresetAssigned.Enhancements then
                for _, name in bp.EnhancementPresetAssigned.Enhancements do
                    mass = mass - bp.Enhancements[name].BuildCostMass or 0
                end
            end
        end

        -- Allow units to count for more or less than their real mass if needed.
        return mass * fractionComplete * (bp.VeteranImportanceMult or 1) + (self.cargoMass or 0)
    end,

    --- Called when this unit kills another. Chiefly responsible for the veterancy system for now.
    OnKilledUnit = function(self, unitKilled, massKilled)
        if not massKilled or massKilled == 0 then return end -- Make sure engine calls aren't passed with massKilled == 0
        if IsAlly(GetArmy(self), GetArmy(unitKilled)) then return end -- No XP for friendly fire...

        self:CalculateVeterancyLevel(massKilled) -- Bails if we've not gone up

        ArmyBrains[GetArmy(self)]:AddUnitStat(unitKilled:GetUnitId(), "kills", 1)
    end,

    CalculateVeterancyLevel = function(self, massKilled)
        local bp = self:GetBlueprint()

        -- Limit the veterancy gain from one kill to one level worth
        massKilled = math.min(massKilled, self.Sync.myValue)

        -- Total up the mass the unit has killed overall, and store it
        self.Sync.totalMassKilled = math.floor(self.Sync.totalMassKilled + massKilled)

        -- Calculate veterancy level. By default killing your own mass value (Build cost mass * 2 by default) grants a level
        local newVetLevel = math.min(math.floor(self.Sync.totalMassKilled / self.Sync.myValue), 5)

        -- Bail if our veterancy hasn't increased
        if newVetLevel == self.Sync.VeteranLevel then return end

        -- Update our recorded veterancy level
        self.Sync.VeteranLevel = newVetLevel

        self:SetVeteranLevel(self.Sync.VeteranLevel)
    end,

    -- Use this to set a veterancy level directly, usually used by a scenario
    SetVeterancy = function(self, veteranLevel)
        if veteranLevel <= 0 or veteranLevel > 5 then return end
        if not self.gainsVeterancy then return end

        self:CalculateVeterancyLevel(self.Sync.myValue * veteranLevel)
    end,

    -- Set the veteran level to the level specified
    SetVeteranLevel = function(self, level)
        local buffs = self:CreateVeterancyBuffs(level)
        if buffs then
            for _, buffName in buffs do
                Buff.ApplyBuff(self, buffName)
            end
        end

        self:GetAIBrain():OnBrainUnitVeterancyLevel(self, level)
        self:DoVeterancyHealing(level)

        self:DoUnitCallbacks('OnVeteran')
    end,

    -- Veterancy can't be 'Undone', so we heal the unit directly, one-off, rather than using a buff. Much more flexible.
    DoVeterancyHealing = function(self, level)
        local bp = self:GetBlueprint()
        local maxHealth = bp.Defense.MaxHealth
        local mult = bp.VeteranHealingMult[level] or 0.1

        self:AdjustHealth(self, maxHealth * mult) -- Adjusts health by the given value (Can be +tv or -tv), not to the given value
    end,

    CreateVeterancyBuffs = function(self, level)
        local healthBuffName = 'VeterancyMaxHealth' .. level -- Currently there is no difference between units, therefore no need for unique buffs
        local regenBuffName = self:GetUnitId() .. 'VeterancyRegen' .. level -- Generate a buff based on the unitId - eg. uel0001VeterancyRegen3

        if not Buffs[regenBuffName] then
            -- Maps self.techCategory to a number so we can do math on it for naval units
            local techLevels = {
                TECH1 = 1,
                TECH2 = 2,
                TECH3 = 3,
                COMMAND = 3,
                SUBCOMMANDER = 4,
                EXPERIMENTAL = 5,
            }
            
            local techLevel = techLevels[self.techCategory] or 1
            
            -- Treat naval units as one level higher
            if techLevel < 4 and EntityCategoryContains(categories.NAVAL, self) then
                techLevel = techLevel + 1
            end
            
            -- Regen values by tech level and veterancy level
            local regenBuffs = {
                {1,  2,  3,  4,  5}, -- T1
                {3,  6,  9,  12, 15}, -- T2
                {6,  12, 18, 24, 30}, -- T3 / ACU
                {9,  18, 27, 36, 45}, -- SACU
                {25, 50, 75, 100,125}, -- Experimental
            }
        
            BuffBlueprint {
                Name = regenBuffName,
                DisplayName = regenBuffName,
                BuffType = 'VeterancyRegen',
                Stacks = 'REPLACE',
                Duration = -1,
                Affects = {
                    Regen = {
                        Add = regenBuffs[techLevel][level],
                    },
                },
            }
        end
        
        return {regenBuffName, healthBuffName}
    end,

    -- Returns true if a unit can gain veterancy (Has a weapon)
    ShouldUseVetSystem = function(self)
        local weps = self:GetBlueprint().Weapon

        -- Bail if we don't have any weapons
        if not weps[1] then
            return false
        end

        -- Find a weapon which is not a DeathWeapon
        for index, wep in weps do
            if wep.Label ~= 'DeathWeapon' then
                return true
            end
        end

        -- We only have a DeathWeapon. Bail.
        return false
    end,

    -- End of Veterancy Section
    ------------------------------------------------------------------------------

    DoDeathWeapon = function(self)
        if self:IsBeingBuilt() then return end

        local bp = GetBlueprint(self)
        for _, v in bp.Weapon do
            if v.Label == 'DeathWeapon' then
                if v.FireOnDeath == true then
                    self:SetWeaponEnabledByLabel('DeathWeapon', true)
                    self:GetWeaponByLabel('DeathWeapon'):Fire()
                else
                    self:ForkThread(self.DeathWeaponDamageThread, v.DamageRadius, v.Damage, v.DamageType, v.DamageFriendly)
                end
                break
            end
        end
    end,

    OnCollisionCheck = function(self, other, firingWeapon)
        if self.DisallowCollisions then
            return false
        end

        local bp = GetBlueprint(self)

        if bp.CategoriesHash.PROJECTILE then
            if GetArmy(self) == GetArmy(other) then
                return other.CollideFriendly
            end
        end

        for _, v in pairs(bp.DoNotCollideList) do
            if EntityCategoryContains(ParseEntityCategory(v), other) then
                return false
            end
        end

        -- Check for specific non-collisions
        bp = GetBlueprint(other)
        for _, v in pairs(bp.DoNotCollideList) do
            if EntityCategoryContains(ParseEntityCategory(v), self) then
                return false
            end
        end

        return true
    end,

    OnCollisionCheckWeapon = function(self, firingWeapon)
        if self.DisallowCollisions then
            return false
        end

        -- Skip friendly collisions
        local weaponBP = GetBlueprint(firingWeapon)
        local collide = weaponBP.CollideFriendly
        if collide == false then
            if GetArmy(self) == GetArmy(firingWeapon.unit) then
                return false
            end
        end

        -- Check for specific non-collisions
        if weaponBP.DoNotCollideList then
            for _, v in pairs(weaponBP.DoNotCollideList) do
                if EntityCategoryContains(ParseEntityCategory(v), self) then
                    return false
                end
            end
        end

        return true
    end,

    ChooseAnimBlock = function(self, bp)
        local totWeight = 0
        for _, v in bp do
            if v.Weight then
                totWeight = totWeight + v.Weight
            end
        end

        local val = 1
        local num = Random(0, totWeight)
        for _, v in bp do
            if v.Weight then
                val = val + v.Weight
            end
            if num < val then
                return v
            end
        end
    end,

    PlayAnimationThread = function(self, anim, rate)
        local bp = GetBlueprint(self)
        local bpAnim = bp.Display[anim]
        if bpAnim then
            local animBlock = self:ChooseAnimBlock(bpAnim)
            if animBlock.Mesh then
                SetMesh(self, animBlock.Mesh)
            end
            if animBlock.Animation and (self:ShallSink() or not bp.CategoriesHash.NAVAL) then
                local sinkAnim = CreateAnimator(self)
                self:StopRocking()
                self.DeathAnimManip = sinkAnim
                sinkAnim:PlayAnim(animBlock.Animation)
                rate = rate or 1
                if animBlock.AnimationRateMax and animBlock.AnimationRateMin then
                    rate = Random(animBlock.AnimationRateMin * 10, animBlock.AnimationRateMax * 10) / 10
                end
                sinkAnim:SetRate(rate)
                self.Trash:Add(sinkAnim)
                WaitFor(sinkAnim)
                self.StopSink = true
            end
        end
    end,

    -- Create a unit's wrecked mesh blueprint from its regular mesh blueprint, by changing the shader and albedo
    CreateWreckage = function (self, overkillRatio)
        if overkillRatio and overkillRatio > 1.0 then
            return
        end

        return self:CreateWreckageProp(overkillRatio)
    end,

    CreateWreckageProp = function(self, overkillRatio)
        local bp = GetBlueprint(self)

        local wreck = bp.Wreckage.Blueprint
        if not wreck then
            return nil
        end

        local mass = bp.Economy.BuildCostMass * (bp.Wreckage.MassMult or 0)
        local energy = bp.Economy.BuildCostEnergy * (bp.Wreckage.EnergyMult or 0)
        local time = (bp.Wreckage.ReclaimTimeMultiplier or 1)
        local pos = GetPosition(self)
        local layer = GetCurrentLayer(self)

        -- Reduce the mass value of submerged wrecks
        if layer == 'Water' or layer == 'Sub' then
            mass = mass * 0.5
            energy = energy * 0.5
        end

        local halfBuilt = self:GetFractionComplete() < 1

        -- Make sure air / naval wrecks stick to ground / seabottom, unless they're in a factory.
        if not halfBuilt and (layer == 'Air' or EntityCategoryContains(categories.NAVAL - categories.STRUCTURE, self)) then
            pos[2] = GetTerrainHeight(pos[1], pos[3]) + GetTerrainTypeOffset(pos[1], pos[3])
        end

        local overkillMultiplier = 1 - (overkillRatio or 1)
        mass = mass * overkillMultiplier * self:GetFractionComplete()
        energy = energy * overkillMultiplier * self:GetFractionComplete()
        time = time * overkillMultiplier

        -- Now we adjust the global multiplier. This is used for balance purposes to adjust global reclaim rate.
        local time  = time * 2

        local prop = wreckageCreateWreckage(bp, pos, self:GetOrientation(), mass, energy, time)

        -- Attempt to copy our animation pose to the prop. Only works if
        -- the mesh and skeletons are the same, but will not produce an error if not.
        if (layer ~= 'Air' and self.PlayDeathAnimation) or (layer == "Air" and halfBuilt) then
            TryCopyPose(self, prop, true)
        end

        -- Create some ambient wreckage smoke
        explosion.CreateWreckageEffects(self, prop)

        return prop
    end,

    CreateDestructionEffects = function(self, overKillRatio)
        explosion.CreateScalableUnitExplosion(self, overKillRatio)
    end,

    DeathWeaponDamageThread = function(self, damageRadius, damage, damageType, damageFriendly)
        WaitSeconds(0.1)
        DamageArea(self, GetPosition(self), damageRadius or 1, damage or 1, damageType or 'Normal', damageFriendly or false)
    end,

    SinkDestructionEffects = function(self)
        local Util = utilities
        local sx, sy, sz = self:GetUnitSizes()
        local vol = sx * sy * sz
        local army = GetArmy(self)
        local numBones = self:GetBoneCount() - 1
        local pos = GetPosition(self)
        local surfaceHeight = GetSurfaceHeight(pos[1], pos[3])
        local i = 0

        while i < 1 do
            local randBone = Util.GetRandomInt(0, numBones)
            local boneHeight = GetPosition(self, randBone)[2]
            local toSurface = surfaceHeight - boneHeight
            local y = toSurface
            local rx, ry, rz = self:GetRandomOffset(0.3)
            local rs = mathMax(mathMin(2.5, vol / 20), 0.5)
            local scale = Util.GetRandomFloat(rs/2, rs)

            self:DestroyAllDamageEffects()
            if toSurface < 1 then
                CreateAttachedEmitter(self, randBone, army, '/effects/emitters/destruction_water_sinking_ripples_01_emit.bp'):OffsetEmitter(rx, y, rz):ScaleEmitter(scale)
                CreateAttachedEmitter(self, randBone, army, '/effects/emitters/destruction_water_sinking_wash_01_emit.bp'):OffsetEmitter(rx, y, rz):ScaleEmitter(scale)
            end

            if toSurface < 0 then
                explosion.CreateDefaultHitExplosionAtBone(self, randBone, scale*1.5)
            else
                local lifetime = Util.GetRandomInt(50, 200)

                if toSurface > 1 then
                    CreateEmitterAtBone(self, randBone, army, '/effects/emitters/underwater_bubbles_01_emit.bp'):OffsetEmitter(rx, ry, rz)
                        :ScaleEmitter(scale)
                        :SetEmitterParam('LIFETIME', lifetime)

                    CreateAttachedEmitter(self, -1, army, '/effects/emitters/destruction_underwater_sinking_wash_01_emit.bp'):OffsetEmitter(rx, ry, rz):ScaleEmitter(scale)
                end
                CreateEmitterAtBone(self, randBone, army, '/effects/emitters/destruction_underwater_explosion_flash_01_emit.bp'):OffsetEmitter(rx, ry, rz):ScaleEmitter(scale)
                CreateEmitterAtBone(self, randBone, army, '/effects/emitters/destruction_underwater_explosion_splash_01_emit.bp'):OffsetEmitter(rx, ry, rz):ScaleEmitter(scale)
            end
            local rd = Util.GetRandomFloat(0.4, 1.0)
            WaitSeconds(i + rd)
            i = i + 0.3
        end
    end,

    StartSinking = function(self, callback)
        local bp = GetBlueprint(self)
        local scale = ((bp.SizeX or 0 + bp.SizeZ or 0) * 0.5)
        local bone = 0

        -- Create sinker projectile
        local proj = self:CreateProjectileAtBone('/projectiles/Sinker/Sinker_proj.bp', bone)

        -- Start the sinking after a delay of the given number of seconds, attaching to a given bone
        -- and entity.
        proj:Start(10 * mathMax(2, mathMin(7, scale)), self, bone, callback)
        self.Trash:Add(proj)
    end,

    SeabedWatcher = function(self)
        local pos = GetPosition(self)
        local seafloor = GetTerrainHeight(pos[1], pos[3]) + GetTerrainTypeOffset(pos[1], pos[3])
        local watchBone = GetBlueprint(self).WatchBone or 0

        self.StopSink = false
        while not self.StopSink do
            WaitTicks(1)
            if GetPosition(self, watchBone)[2] - 0.2 <= seafloor then
                self.StopSink = true
            end
        end
    end,

    ShallSink = function(self)
        local layer = GetCurrentLayer(self)
        local bp = GetBlueprint(self)
        local shallSink = (
            (layer == 'Water' or layer == 'Sub') and  -- In a layer for which sinking is meaningful
            not bp.CategoriesHash.STRUCTURE  -- Exclude structures
        )
        return shallSink
    end,

    DeathThread = function(self, overkillRatio, instigator)
        local bp = GetBlueprint(self)
        local isNaval = bp.CategoriesHash.NAVAL
        local shallSink = self:ShallSink()

        WaitSeconds(utilities.GetRandomFloat(self.DestructionExplosionWaitDelayMin, self.DestructionExplosionWaitDelayMax))

        self:DestroyAllDamageEffects()
        self:DestroyTopSpeedEffects()
        self:DestroyIdleEffects()
        self:DestroyBeamExhaust()
        self:DestroyAllBuildEffects()

        -- Stop any motion sounds we may have
        self:StopUnitAmbientSound('AmbientMove')
        self:StopUnitAmbientSound('AmbientMoveLand')
        self:StopUnitAmbientSound('AmbientMoveWater')

        -- BOOM!
        if self.PlayDestructionEffects then
            self:CreateDestructionEffects(overkillRatio)
        end

        -- Flying bits of metal and whatnot. More bits for more overkill.
        if self.ShowUnitDestructionDebris and overkillRatio then
            self.CreateUnitDestructionDebris(self, true, true, overkillRatio > 2)
        end

        if shallSink then
            self.DisallowCollisions = true

            -- Bubbles and stuff coming off the sinking wreck.
            self:ForkThread(self.SinkDestructionEffects)

            -- Avoid slightly ugly need to propagate this through callback hell...
            self.overkillRatio = overkillRatio

            if isNaval and bp.Display.AnimationDeath then
                -- Waits for wreck to hit bottom or end of animation
                if self:GetFractionComplete() > 0.5 then
                    self:SeabedWatcher()
                else
                    self:DestroyUnit(overkillRatio)
                end
            else
                -- A non-naval unit or boat with no sinking animation dying over water needs to sink, but lacks an animation for it. Let's make one up.
                local this = self
                self:StartSinking(
                    function()
                        this:DestroyUnit(overkillRatio)
                    end
                )

                -- Wait for the sinking callback to actually destroy the unit.
                return
            end
        elseif self.DeathAnimManip then -- wait for non-sinking animations
            WaitFor(self.DeathAnimManip)
        end

        -- If we're not doing fancy sinking rubbish, just blow the damn thing up.
        self:PlayUnitSound('Destroyed')
        self:DestroyUnit(overkillRatio)
    end,

    --- Called at the end of the destruction thread: create the wreckage and Destroy this unit.
    DestroyUnit = function(self, overkillRatio)
        self:CreateWreckage(overkillRatio or self.overkillRatio)

        -- wait at least 1 tick before destroying unit
        WaitSeconds(mathMax(0.1, self.DeathThreadDestructionWaitTime))

        self:Destroy()
    end,

    DestroyAllBuildEffects = function(self)
        if self.BuildEffectsBag then
            self.BuildEffectsBag:Destroy()
        end
        if self.CaptureEffectsBag then
            self.CaptureEffectsBag:Destroy()
        end
        if self.ReclaimEffectsBag then
            self.ReclaimEffectsBag:Destroy()
        end
        if self.OnBeingBuiltEffectsBag then
            self.OnBeingBuiltEffectsBag:Destroy()
        end
        if self.UpgradeEffectsBag then
            self.UpgradeEffectsBag:Destroy()
        end
        if self.TeleportFxBag then
            self.TeleportFxBag:Destroy()
        end
    end,

    OnDestroy = function(self)
        self.Dead = true

        if self:GetFractionComplete() < 1 then
            self:SendNotifyMessage('cancelled')
        end

        -- Clear out our sync data
        UnitData[self.EntityId] = false
        Sync.UnitData[self.EntityId] = false

        -- Don't allow anyone to stuff anything else in the table
        self.Sync = false

        -- Let the user layer know this id is gone
        Sync.ReleaseIds[self.EntityId] = true

        -- Destroy everything added to the trash
        self.Trash:Destroy()

        self:DestroyAllBuildEffects()

        if self.TeleportDrain then
            RemoveEconomyEvent(self, self.TeleportDrain)
        end

        RemoveAllUnitEnhancements(self)
        ChangeState(self, self.DeadState)
    end,

    HideLandBones = function(self)
        -- Hide the bones for buildings built on land
        if self.LandBuiltHiddenBones and GetCurrentLayer(self) == 'Land' then
            for _, v in self.LandBuiltHiddenBones do
                if IsValidBone(self, v) then
                    HideBone(self, v, true)
                end
            end
        end
    end,

    -- Generic function for showing a table of bones
    -- Table = List of bones
    -- Childrend = True/False to show child bones
    ShowBones = function(self, table, children)
        for _, v in table do
            if IsValidBone(self, v) then
                ShowBone(self, v, children)
            else
                WARN('*WARNING: TRYING TO SHOW BONE ', repr(v), ' ON UNIT ', repr(self:GetUnitId()), ' BUT IT DOES NOT EXIST IN THE MODEL. PLEASE CHECK YOUR SCRIPT IN THE BUILD PROGRESS BONES.')
            end
        end
    end,

    --- Called under mysterous circumstances, previously held logic for nonexistent sound effects.
    OnDamageBy = function(self, index) end,

    --- Called when a nuke is armed, played a nonexistent sound effect
    OnNukeArmed = function(self) end,

    OnNukeLaunched = function(self)
    end,

    --- STRATEGIC LAUNCH DETECTED
    NukeCreatedAtUnit = function(self)
        if self:GetNukeSiloAmmoCount() <= 0 then
            return
        end

        local bp = GetBlueprint(self).Audio
        if bp then
            for num, aiBrain in ArmyBrains do
                local factionIndex = aiBrain:GetFactionIndex()

                if bp['NuclearLaunchDetected'] then
                    aiBrain:NuclearLaunchDetected(bp['NuclearLaunchDetected'])
                end
            end
        end
    end,

    SetAllWeaponsEnabled = function(self, enable)
        for i = 1, GetWeaponCount(self) do
            local wep = GetWeapon(self, i)
            wep:SetWeaponEnabled(enable)
            wep:AimManipulatorSetEnabled(enable)
        end
    end,

    SetWeaponEnabledByLabel = function(self, label, enable)
        local wep = self:GetWeaponByLabel(label)
        if not wep then return end

        if not enable then
            wep:OnLostTarget()
        end
        wep:SetWeaponEnabled(enable)
        wep:AimManipulatorSetEnabled(enable)
    end,

    GetWeaponManipulatorByLabel = function(self, label)
        local wep = self:GetWeaponByLabel(label)
        return wep:GetAimManipulator()
    end,

    GetWeaponByLabel = function(self, label)
        local wep
        for i = 1, GetWeaponCount(self) do
            wep = GetWeapon(self, i)
            if GetBlueprint(wep).Label == label then
                return wep
            end
        end

        return nil
    end,

    ResetWeaponByLabel = function(self, label)
        local wep = self:GetWeaponByLabel(label)
        wep:ResetTarget()
    end,

    SetDeathWeaponEnabled = function(self, enable)
        self.DeathWeaponEnabled = enable
    end,

    ----------------------------------------------------------------------------------------------
    -- CONSTRUCTING - BEING BUILT
    ----------------------------------------------------------------------------------------------
    OnBeingBuiltProgress = function(self, unit, oldProg, newProg)
    end,

    SetRotation = function(self, angle)
        local qx, qy, qz, qw = explosion.QuatFromRotation(angle, 0, 1, 0)
        self:SetOrientation({qx, qy, qz, qw}, true)
    end,

    Rotate = function(self, angle)
        local qx, qy, qz, qw = unpack(self:GetOrientation())
        local a = mathATan2(2.0 * (qx * qz + qw * qy), qw * qw + qx * qx - qz * qz - qy * qy)
        local current_yaw = mathFloor(mathAbs(a) * (180 / mathPi) + 0.5)

        self:SetRotation(angle + current_yaw)
    end,

    RotateTowards = function(self, tpos)
        local pos = GetPosition(self)
        local rad = mathATan2(tpos[1] - pos[1], tpos[3] - pos[3])

        self:SetRotation(rad * (180 / mathPi))
    end,

    RotateTowardsMid = function(self)
        local x, y = GetMapSize()
        self:RotateTowards({x / 2, 0, y / 2})
    end,

    OnStartBeingBuilt = function(self, builder, layer)
        self:StartBeingBuiltEffects(builder, layer)

        local aiBrain = self:GetAIBrain()
        if tableGetn(aiBrain.UnitBuiltTriggerList) > 0 then
            for _, v in aiBrain.UnitBuiltTriggerList do
                if EntityCategoryContains(v.Category, self) then
                    self:ForkThread(self.UnitBuiltPercentageCallbackThread, v.Percent, v.Callback)
                end
            end
        end

        self.originalBuilder = builder

        self:SendNotifyMessage('started')
    end,

    UnitBuiltPercentageCallbackThread = function(self, percent, callback)
        while not self.Dead and self:GetHealthPercent() < percent do
            WaitSeconds(1)
        end

        local aiBrain = self:GetAIBrain()
        for k, v in aiBrain.UnitBuiltTriggerList do
            if v.Callback == callback then
                callback(self)
                aiBrain.UnitBuiltTriggerList[k] = nil
            end
        end
    end,

    OnStopBeingBuilt = function(self, builder, layer)
        if self.Dead or self:BeenDestroyed() then -- Sanity check, can prevent strange shield bugs and stuff
            self:Kill()
            return false
        end

        local bp = GetBlueprint(self)

        -- Set up Veterancy tracking here. Avoids needing to check completion later.
        -- Do all this here so we only have to do for things which get completed
        -- Don't need to track damage for things which cannot attack!
        self.gainsVeterancy = self:ShouldUseVetSystem()

        if self.gainsVeterancy then
            self.Sync.totalMassKilled = 0
            self.Sync.VeteranLevel = 0

            -- Allow units to require more or less mass to level up. Decimal multipliers mean
            -- faster leveling, >1 mean slower. Doing this here means doing it once instead of every kill.
            local defaultMult = 2
            self.Sync.myValue = math.max(math.floor(bp.Economy.BuildCostMass * (bp.VeteranMassMult or defaultMult)), 1)
        end

        self:EnableUnitIntel('NotInitialized', nil)
        self:ForkThread(self.StopBeingBuiltEffects, builder, layer)

        if GetCurrentLayer(self) == 'Water' then
            self:StartRocking()
            local surfaceAnim = bp.Display.AnimationSurface
            if not self.SurfaceAnimator and surfaceAnim then
                self.SurfaceAnimator = CreateAnimator(self)
            end
            if surfaceAnim and self.SurfaceAnimator then
                self.SurfaceAnimator:PlayAnim(surfaceAnim):SetRate(1)
            end
        end

        self:PlayUnitSound('DoneBeingBuilt')
        self:PlayUnitAmbientSound('ActiveLoop')

        if self.IsUpgrade and builder then
            -- Set correct hitpoints after upgrade
            local hpDamage = GetMaxHealth(builder) - GetHealth(builder) -- Current damage
            local damagePercent = hpDamage / GetMaxHealth(self) -- Resulting % with upgraded building
            local newHealthAmount = GetMaxHealth(builder) * (1 - damagePercent) -- HP for upgraded building
            builder:SetHealth(builder, newHealthAmount) -- Seems like the engine uses builder to determine new HP
            self.DisallowCollisions = false
            self.CanTakeDamage = true
            self:RevertCollisionShape()
            self.IsUpgrade = nil
        end

        -- Turn off land bones if this unit has them.
        self:HideLandBones()
        self:DoUnitCallbacks('OnStopBeingBuilt')

        -- Create any idle effects on unit
        if tableGetn(self.IdleEffectsBag) == 0 then
            self:CreateIdleEffects()
        end

        -- If we have a shield specified, create it.
        -- Blueprint registration always creates a dummy Shield entry:
        -- {
        --     ShieldSize = 0
        --     RegenAssistMult = 1
        -- }
        -- ... Which we must carefully ignore.
        local bpShield = bp.Defense.Shield
        if bpShield.ShieldSize ~= 0 then
            self:CreateShield(bpShield)
        end

        -- Create spherical collisions if defined
        if bp.SizeSphere then
            self:SetCollisionShape(
                'Sphere',
                bp.CollisionSphereOffsetX or 0,
                bp.CollisionSphereOffsetY or 0,
                bp.CollisionSphereOffsetZ or 0,
                bp.SizeSphere
            )
        end

        if bp.Display.AnimationPermOpen then
            self.PermOpenAnimManipulator = CreateAnimator(self):PlayAnim(bp.Display.AnimationPermOpen)
            self.Trash:Add(self.PermOpenAnimManipulator)
        end

        -- Initialize movement effects subsystems, idle effects, beam exhaust, and footfall manipulators
        local bpTable = bp.Display.MovementEffects
        if bpTable.Land or bpTable.Air or bpTable.Water or bpTable.Sub or bpTable.BeamExhaust then
            self.MovementEffectsExist = true
            if bpTable.BeamExhaust and (bpTable.BeamExhaust.Idle ~= false) then
                self:UpdateBeamExhaust('Idle')
            end
            if not self.Footfalls and bpTable[layer].Footfall then
                self.Footfalls = self:CreateFootFallManipulators(bpTable[layer].Footfall)
            end
        else
            self.MovementEffectsExist = false
        end

        local id = self:GetUnitId()
        local index = GetArmy(self)

        ArmyBrains[index]:AddUnitStat(id, "built", 1)

        -- Prevent UI mods from violating game/scenario restrictions
        if not ScenarioInfo.CampaignMode and IsRestricted(id, index) then
            WARN('Unit.OnStopBeingBuilt() Army ' ..index.. ' cannot create restricted unit: ' .. (bp.Description or id))
            if self ~= nil then self:Destroy() end

            return false -- Report failure of OnStopBeingBuilt
        end

        -- Don't try sending a Notify message from here if we're an ACU
        if self.techCategory ~= 'COMMAND' then
            self:SendNotifyMessage('completed')
        end

        return true
    end,

    StartBeingBuiltEffects = function(self, builder, layer)
        local BuildMeshBp = GetBlueprint(self).Display.BuildMeshBlueprint
        if BuildMeshBp then
            SetMesh(self, BuildMeshBp, true)
        end
    end,

    StopBeingBuiltEffects = function(self, builder, layer)
        local bp = GetBlueprint(self).Display
        local useTerrainType = false

        if bp.TerrainMeshes then
            local bpTM = bp.TerrainMeshes
            local pos = GetPosition(self)
            local terrainType = GetTerrainType(pos[1], pos[3])

            if bpTM[terrainType.Style] then
                SetMesh(self, bpTM[terrainType.Style])
                useTerrainType = true
            end
        end

        if not useTerrainType then
            SetMesh(self, bp.MeshBlueprint, true)
        end

        self.OnBeingBuiltEffectsBag:Destroy()
    end,

    OnFailedToBeBuilt = function(self)
        self:ForkThread(function()
            WaitTicks(1)
            self:Destroy()
        end)
    end,

    OnSiloBuildStart = function(self, weapon)
        self.SiloWeapon = weapon
        self.SiloProjectile = weapon:GetProjectileBlueprint()
    end,

    OnSiloBuildEnd = function(self, weapon)
        self.SiloWeapon = nil
        self.SiloProjectile = nil
    end,

    ----------------------------------------------------------------------------------------------
    -- CONSTRUCTING - BUILDING - REPAIR
    ----------------------------------------------------------------------------------------------
    SetupBuildBones = function(self)
        local bp = GetBlueprint(self)
        if not bp.General.BuildBones or
           not bp.General.BuildBones.YawBone or
           not bp.General.BuildBones.PitchBone or
           not bp.General.BuildBones.AimBone then
           return
        end

        -- Syntactical reference:
        -- CreateBuilderArmController(unit, turretBone, [barrelBone], [aimBone])
        -- BuilderArmManipulator:SetAimingArc(minHeading, maxHeading, headingMaxSlew, minPitch, maxPitch, pitchMaxSlew)
        self.BuildArmManipulator = CreateBuilderArmController(self, bp.General.BuildBones.YawBone or 0 , bp.General.BuildBones.PitchBone or 0, bp.General.BuildBones.AimBone or 0)
        self.BuildArmManipulator:SetAimingArc(-180, 180, 360, -90, 90, 360)
        self.BuildArmManipulator:SetPrecedence(5)
        if self.BuildingOpenAnimManip and self.BuildArmManipulator then
            self.BuildArmManipulator:Disable()
        end
        self.Trash:Add(self.BuildArmManipulator)
    end,

    BuildManipulatorSetEnabled = function(self, enable)
        if self.Dead or not self.BuildArmManipulator then return end
        if enable then
            self.BuildArmManipulator:Enable()
        else
            self.BuildArmManipulator:Disable()
        end
    end,

    GetRebuildBonus = function(self, bp)
        -- The engine intends to delete a wreck when our next build job starts. Remember this so we
        -- can regenerate the wreck if it's got the wrong one.
        self.EngineIsDeletingWreck = true

        return 0
    end,

    --- Look for a wreck of the thing we just started building at the same location. If there is
    -- one, give the rebuild bonus.
    SetRebuildProgress = function(self, unit)
        local upos = GetPosition(unit)
        local props = GetReclaimablesInRect(Rect(upos[1], upos[3], upos[1], upos[3]))
        local wreckage = {}
        local bpid = unit:GetUnitId()

        for _, p in props do
            local pos = p.CachePosition
            if p.IsWreckage and p.AssociatedBP == bpid and upos[1] == pos[1] and upos[3] == pos[3] then
                local progress = p:GetFractionComplete() * 0.5
                -- Set health according to how much is left of the wreck
                unit:SetHealth(self, GetMaxHealth(unit) * progress)

                -- Clear up wreck after rebuild bonus applied if engine won't
                if not unit.EngineIsDeletingWreck then
                    p:Destroy()
                end

                return
            end
        end

        if self.EngineIsDeletingWreck then
            -- Control reaches this point when:
            -- A structure build template was created atop a wreck of the same building type.
            -- The build template was then moved somewhere else.
            -- The build template was not moved back onto the wreck before construction started.

            -- This is a pretty hilariously rare case (in reality, it's probably only going to arise
            -- rarely, or when someone is trying to use the remote-wreck-deletion exploit).
            -- As such, I don't feel especially guilty doing the following. This approach means we
            -- don't have to waste a ton of memory keeping lists of wrecks of various sorts, we just
            -- do this one hideously expensive routine in the exceptionally rare circumstance that
            -- the badness happens.

            local x, y = GetMapSize()
            local reclaimables = GetReclaimablesInRect(0, 0, x, y)

            for _, r in reclaimables do
                if r.IsWreckage and r.AssociatedBP == bpid and r:BeenDestroyed() then
                    r:Clone()
                    return
                end
            end
        end
    end,

    CheckAssistFocus = function(self)
        local bp = GetBlueprint(self)
        if not (self and bp.CategoriesHash.ENGINEER) or self.Dead then
            return
        end

        local guarded = self:GetGuardedUnit()
        if guarded and not guarded.Dead then
            local focus = guarded:GetFocusUnit()
            if not focus then return end

            local cmd
            if guarded:IsUnitState('Reclaiming') then
                cmd = IssueReclaim
            elseif guarded:IsUnitState('Building') then
                cmd = IssueRepair
            end

            if cmd then
                IssueClearCommands({self})
                cmd({self}, focus)
                IssueGuard({self}, guarded)
            end
        end
    end,

    CheckAssistersFocus = function(self)
        for _, u in self:GetGuards() do
            if u:IsUnitState('Repairing') then
                u:CheckAssistFocus()
            end
        end
    end,

    OnStartBuild = function(self, built, order)
        -- Prevent UI mods from violating game/scenario restrictions
        local id = built:GetUnitId()
        local bpBuilt = GetBlueprint(built)
        local index = GetArmy(self)

        if not ScenarioInfo.CampaignMode and IsRestricted(id, index) then
            WARN('Unit.OnStartBuild() Army ' ..index.. ' cannot build restricted unit: ' .. (bpBuilt.Description or id))
            self:OnFailedToBuild() -- Don't use: self:OnStopBuild()
            IssueClearFactoryCommands({self})
            IssueClearCommands({self})
            return false -- Report failure of OnStartBuild
        end

        -- We just started a construction (and haven't just been tasked to work on a half-done
        -- project.)
        if GetHealth(built) == 1 then
            self:SetRebuildProgress(built)
            self.EngineIsDeletingWreck = nil
        end

        -- OnStartBuild() is called on paused engineers when they roll up to their next construction
        -- task. This is a native-code bug: it shouldn't be calling OnStartBuild at all in this case
        if self:IsPaused() then
            return true
        end

        if order == 'Repair' then
            self:OnStartRepair(built)
        elseif GetHealth(self) < GetMaxHealth(self) and tableGetsize(self:GetGuards()) > 0 then
            -- Unit building something is damaged and has assisters, check their focus
            self:CheckAssistersFocus()
        end

        local bpSelf = GetBlueprint(self)
        if order ~= 'Upgrade' or bpSelf.Display.ShowBuildEffectsDuringUpgrade then
            self:StartBuildingEffects(built, order)
        end

        self:SetActiveConsumptionActive()
        self:PlayUnitSound('Construct')
        self:PlayUnitAmbientSound('ConstructLoop')

        self:DoOnStartBuildCallbacks(built)

        if order == 'Upgrade' and bpBuilt.General.UpgradesFrom == self:GetUnitId() then
            built.DisallowCollisions = true
            built.CanTakeDamage = false
            built:SetCollisionShape('None')
            built.IsUpgrade = true
        end

        return true
    end,

    OnStopBuild = function(self, built)
        self:StopBuildingEffects(built)
        self:SetActiveConsumptionInactive()
        self:DoOnUnitBuiltCallbacks(built)
        self:StopUnitAmbientSound('ConstructLoop')
        self:PlayUnitSound('ConstructStop')

        if built.Repairers[self.EntityId] then
            self:OnStopRepair(self, built)
            built.Repairers[self.EntityId] = nil
        end
    end,

    OnFailedToBuild = function(self)
        self:DoOnFailedToBuildCallbacks()
        self:StopUnitAmbientSound('ConstructLoop')
    end,

    OnPrepareArmToBuild = function(self)
    end,

    OnStartBuilderTracking = function(self)
    end,

    OnStopBuilderTracking = function(self)
    end,

    OnBuildProgress = function(self, unit, oldProg, newProg)
    end,

    StartBuildingEffects = function(self, built, order)
        self.BuildEffectsBag:Add(self:ForkThread(self.CreateBuildEffects, built, order))
    end,

    CreateBuildEffects = function(self, built, order)
    end,

    StopBuildingEffects = function(self, built)
        self.BuildEffectsBag:Destroy()
    end,

    OnStartSacrifice = function(self, target_unit)
        EffectUtilities.PlaySacrificingEffects(self, target_unit)
    end,

    OnStopSacrifice = function(self, target_unit)
        EffectUtilities.PlaySacrificeEffects(self, target_unit)
        self:SetDeathWeaponEnabled(false)
        self:Destroy()
    end,

    -------------------------------------------------------------------------------------------
    -- INTEL
    -------------------------------------------------------------------------------------------
    -- There are several ways to disable a unit's intel: The intel actually being part of an upgrade
    -- (enhancement) that is not present, the intel requiring energy and energy being stalled, etc.
    -- The intel is turned on using the EnableIntel engine call if all disablers are removed.
    -- As an optimisation, EnableIntel and DisableIntel are only called when going from one disabler
    -- present to zero, and when going from zero disablers to one.

    DisableUnitIntel = function(self, disabler, intel)
        local function DisableOneIntel(disabler, intel)
            local intDisabled = false
            if Set.Empty(self.IntelDisables[intel]) then
                local active = GetBlueprint(self).Intel.ActiveIntel
                if active and active[intel] then
                    return
                end

                self:DisableIntel(intel)

                -- Handle the cloak FX timing
                if intel == 'Cloak' or intel == 'CloakField' then
                    if disabler ~= 'NotInitialized' and GetBlueprint(self).Intel[intel] then
                        self:UpdateCloakEffect(false, intel)
                    end
                end

                intDisabled = true
            end
            self.IntelDisables[intel][disabler] = true
            return intDisabled
        end

        local intDisabled = false

        -- We need this guard because the engine emits an early OnLayerChange event that would screw us up here with certain units that have Intel changes on layer change
        -- The NotInitialized disabler is removed in OnStopBeingBuilt, when the Unit's intel engine state is properly initialized.
        if self.IntelDisables['Radar']['NotInitialized'] then
            return
        end

        if intel then
            intDisabled = DisableOneIntel(disabler, intel)
        else
            -- Loop over all intels and add disabler
            for intel, v in self.IntelDisables do
                intDisabled = DisableOneIntel(disabler, intel) or intDisabled -- Beware of short-circuiting
            end
        end

        if intDisabled then
            self:OnIntelDisabled(disabler, intel)
        end
    end,

    EnableUnitIntel = function(self, disabler, intel)
        local function EnableOneIntel(disabler, intel)
            local intEnabled = false
            if self.IntelDisables[intel][disabler] then -- Must check for explicit true contained
                self.IntelDisables[intel][disabler] = nil
                if setEmpty(self.IntelDisables[intel]) then
                    self:EnableIntel(intel)

                    -- Handle the cloak FX timing
                    if intel == 'Cloak' or intel == 'CloakField' then
                        if disabler ~= 'NotInitialized' and GetBlueprint(self).Intel[intel] then
                            self:UpdateCloakEffect(true, intel)
                        end
                    end

                    intEnabled = true
                end
            end
            return intEnabled
        end

        local intEnabled = false

        -- We need this guard because the engine emits an early OnLayerChange event that would screw us up here.
        -- The NotInitialized disabler is removed in OnStopBeingBuilt, when the Unit's intel engine state is properly initialized.
        if self.IntelDisables['Radar']['NotInitialized'] == true and disabler ~= 'NotInitialized' then
            return
        end

        if intel then
            intEnabled = EnableOneIntel(disabler, intel)
        else
            -- Loop over all intels and remove disabler
            for intel, v in self.IntelDisables do
                intEnabled = EnableOneIntel(disabler, intel) or intEnabled -- Beware of short-circuiting
            end
        end

        local bp = GetBlueprint(self)
        if not self.IntelThread and (bp.WatchPowerForIntel or bp.EnhancementAddsEnergyDrain) then
            self.IntelThread = self:ForkThread(self.IntelWatchThread)
        end

        if intEnabled then
            self:OnIntelEnabled()
        end
    end,

    OnIntelEnabled = function(self)
    end,

    OnIntelDisabled = function(self)
    end,

    UpdateCloakEffect = function(self, cloaked, intel)
        -- When debugging cloak FX issues, remember that once a structure unit is seen by the enemy,
        -- recloaking won't make it vanish again, and they'll see the new FX.
        if self and not self.Dead then
            if intel == 'Cloak' then
                local bpDisplay = GetBlueprint(self).Display

                if cloaked then
                    SetMesh(self, bpDisplay.CloakMeshBlueprint, true)
                else
                    SetMesh(self, bpDisplay.MeshBlueprint, true)
                end
            elseif intel == 'CloakField' then
                if self.CloakFieldWatcherThread then
                    KillThread(self.CloakFieldWatcherThread)
                    self.CloakFieldWatcherThread = nil
                end

                if cloaked then
                    self.CloakFieldWatcherThread = self:ForkThread(self.CloakFieldWatcher)
                end
            end
        end
    end,

    CloakFieldWatcher = function(self)
        if self and not self.Dead then
            local bp = GetBlueprint(self)
            local radius = bp.Intel.CloakFieldRadius - 2 -- Need to take off 2, because engine reasons
            local brain = self:GetAIBrain()

            while self and not self.Dead and self:IsIntelEnabled('CloakField') do
                local pos = GetPosition(self)
                local units = brain:GetUnitsAroundPoint(categories.ALLUNITS, pos, radius, 'Ally')

                for _, unit in units do
                    if unit and not unit.Dead and unit ~= self then
                        if unit.CloakFXWatcherThread then
                            KillThread(unit.CloakFXWatcherThread)
                            unit.CloakFXWatcherThread = nil
                        end

                        unit:UpdateCloakEffect(true, 'Cloak') -- Turn on the FX for the unit
                        unit.CloakFXWatcherThread = unit:ForkThread(unit.CloakFXWatcher)
                    end
                end

                WaitTicks(6)
            end
        end
    end,

    CloakFXWatcher = function(self)
        WaitTicks(6)

        if self and not self.Dead then
            self:UpdateCloakEffect(false, 'Cloak')
        end
    end,

    -- This function is called only by units which can upgrade into requiring energy maintenance
    ShouldWatchIntel = function(self)
        local bp = GetBlueprint(self)
        local drain = false

        for k, v in bp.Enhancements do
            if self:HasEnhancement(k) and v.MaintenanceConsumptionPerSecondEnergy and v.MaintenanceConsumptionPerSecondEnergy > 0 then
                drain = true
                break
            end
        end

        if drain then
            local intelTypeTbl = {'JamRadius', 'SpoofRadius'}
            local intelTypeBool = {'RadarStealth', 'SonarStealth', 'Cloak'}
            local intelTypeNum = {'RadarRadius', 'SonarRadius', 'OmniRadius', 'RadarStealthFieldRadius', 'SonarStealthFieldRadius', 'CloakFieldRadius'}
            local bpInt = bp.Intel
            if bpInt then
                for _, v in intelTypeTbl do
                    if bpInt[v] then
                        for ki, vi in bpInt[v] do
                            if vi > 0 then
                                return true
                            end
                        end
                    end
                end
                for _, v in intelTypeBool do
                    if bpInt[v] then
                        return true
                    end
                end
                for _, v in intelTypeNum do
                    if bpInt[v] > 0 then
                        return true
                    end
                end
            end
        end
    end,

    -- This thread is only activated if the unit is known to have to watch its intel, or if it is capable of upgrading such that it has to
    IntelWatchThread = function(self)
        local aiBrain = self:GetAIBrain()
        local bp = GetBlueprint(self)
        local recharge = bp.Intel.ReactivateTime or 10
        local watchIntel = bp.WatchPowerForIntel

        -- This will be permanent for units that don't upgrade into their drains
        while watchIntel or (bp.EnhancementAddsEnergyDrain and self:ShouldWatchIntel()) do
            WaitSeconds(0.5)

            -- Checking for less than 1 because sometimes there's more
            -- than 0 and less than 1 in stock and that last bit of
            -- energy isn't used. This results in the radar being
            -- on even though there's no energy to run it. Shields
            -- have a similar bug with a similar fix.
            if aiBrain:GetEconomyStored('ENERGY') < 1 and not self.ToggledOff then
                self:DisableUnitIntel('Energy', nil)
                WaitSeconds(recharge)
                self:EnableUnitIntel('Energy', nil)
            end
        end
        if self.IntelThread then
            self.IntelThread = nil
        end
    end,

    AddDetectedByHook = function(self, hook)
        if not self.DetectedByHooks then
            self.DetectedByHooks = {}
        end
        tableInsert(self.DetectedByHooks, hook)
    end,

    RemoveDetectedByHook = function(self, hook)
        if self.DetectedByHooks then
            for k, v in self.DetectedByHooks do
                if v == hook then
                    tableRemove(self.DetectedByHooks, k)
                    return
                end
            end
        end
    end,

    OnDetectedBy = function(self, index)
        if self.DetectedByHooks then
            for _, v in self.DetectedByHooks do
                v(self, index)
            end
        end
    end,

    -------------------------------------------------------------------------------------------
    -- GENERIC WORK
    -------------------------------------------------------------------------------------------
    InheritWork = function(self, target)
        self.WorkItem = target.WorkItem
        self.WorkItemBuildCostEnergy = target.WorkItemBuildCostEnergy
        self.WorkItemBuildCostMass = target.WorkItemBuildCostMass
        self.WorkItemBuildTime = target.WorkItemBuildTime
    end,

    ClearWork = function(self)
        self.WorkProgress = 0
        self.WorkItem = nil
        self.WorkItemBuildCostEnergy = nil
        self.WorkItemBuildCostMass = nil
        self.WorkItemBuildTime = nil
    end,

    OnWorkBegin = function(self, work)
        local enhCommon = import('/lua/enhancementcommon.lua')
        local restrictions = enhCommon.GetRestricted()
        if restrictions[work] then
            self:OnWorkFail(work)
            return false
        end

        local unitEnhancements = enhCommon.GetEnhancements(self.EntityId)
        local tempEnhanceBp = GetBlueprint(self).Enhancements[work]
        if tempEnhanceBp.Prerequisite then
            if unitEnhancements[tempEnhanceBp.Slot] ~= tempEnhanceBp.Prerequisite then
                error('*ERROR: Ordered enhancement does not have the proper prereq!', 2)
                return false
            end
        elseif unitEnhancements[tempEnhanceBp.Slot] then
            error('*ERROR: Ordered enhancement does not have the proper slot available!', 2)
            return false
        end

        self.WorkItem = tempEnhanceBp
        self.WorkItemBuildCostEnergy = tempEnhanceBp.BuildCostEnergy
        self.WorkItemBuildCostMass = tempEnhanceBp.BuildCostEnergy
        self.WorkItemBuildTime = tempEnhanceBp.BuildTime
        self.WorkProgress = 0

        self:PlayUnitSound('EnhanceStart')
        self:PlayUnitAmbientSound('EnhanceLoop')
        self:CreateEnhancementEffects(work)
        if not self:IsPaused() then
            self:SetActiveConsumptionActive()
        end

        ChangeState(self, self.WorkingState)

        -- Inform EnhanceTask that enhancement is not restricted
        return true
    end,

    OnWorkEnd = function(self, work)
        self:ClearWork()
        self:SetActiveConsumptionInactive()
        self:PlayUnitSound('EnhanceEnd')
        self:StopUnitAmbientSound('EnhanceLoop')
        self:CleanupEnhancementEffects()
    end,

    OnWorkFail = function(self, work)
        self:ClearWork()
        self:SetActiveConsumptionInactive()
        self:PlayUnitSound('EnhanceFail')
        self:StopUnitAmbientSound('EnhanceLoop')
        self:CleanupEnhancementEffects()
    end,

    CreateEnhancement = function(self, enh)
        local bp = GetBlueprint(self).Enhancements[enh]
        if not bp then
            error('*ERROR: Got CreateEnhancement call with an enhancement that doesnt exist in the blueprint.', 2)
            return false
        end

        for _, v in bp.ShowBones do
            if IsValidBone(self, v) then
                ShowBone(self, v, true)
            end
        end

        for _, v in bp.HideBones do
            if IsValidBone(self, v) then
                HideBone(self, v, true)
            end
        end

        AddUnitEnhancement(self, enh, bp.Slot or '')
        for _, v in bp.RemoveEnhancements do
            RemoveUnitEnhancement(self, v)
        end

        self:RequestRefreshUI()
    end,

    CreateEnhancementEffects = function(self, enhancement)
        local bp = GetBlueprint(self).Enhancements[enhancement]
        local effects = TrashBag()
        local scale = mathMin(4, mathMax(1, (bp.BuildCostEnergy / bp.BuildTime or 1) / 50))

        for _, v in bp.UpgradeEffectBones do
            if IsValidBone(self, v) then
                EffectUtilities.CreateEnhancementEffectAtBone(self, v, self.UpgradeEffectsBag)
            end
        end

        for _, v in bp.UpgradeUnitAmbientBones do
            if IsValidBone(self, v) then
                EffectUtilities.CreateEnhancementUnitAmbient(self, v, self.UpgradeEffectsBag)
            end
        end

        for _, e in effects do
            e:ScaleEmitter(scale)
            self.UpgradeEffectsBag:Add(e)
        end
    end,

    CleanupEnhancementEffects = function(self)
        self.UpgradeEffectsBag:Destroy()
    end,

    HasEnhancement = function(self, enh)
        local unitEnh = SimUnitEnhancements[self.EntityId]
        if unitEnh then
            for k, v in unitEnh do
                if v == enh then
                    return true
                end
            end
        end

        return false
    end,

    -------------------------------------------------------------------------------------------
    -- LAYER EVENTS
    -------------------------------------------------------------------------------------------
    OnLayerChange = function(self, new, old)
        -- Bail out early if dead. The engine calls this function AFTER entity:Destroy() has killed
        -- the C object. Any functions down this line which expect a live C object (self:CreateAnimator())
        -- for example, will throw an error.
        if self.Dead then return end

        for i = 1, GetWeaponCount(self) do
            GetWeapon(self, i):SetValidTargetsForCurrentLayer(new)
        end

        if (old == 'Seabed' or old == 'Water' or old == 'Sub' or old == 'None') and new == 'Land' then
            self:DisableIntel('WaterVision')
        elseif (old == 'Land' or old == 'None') and (new == 'Seabed' or new == 'Water' or new == 'Sub') then
            self:EnableIntel('WaterVision')
        end

        -- All units want normal vision!
        if old == 'None' then
            self:EnableIntel('Vision')
        end

        if new == 'Land' then
            self:PlayUnitSound('TransitionLand')
            self:PlayUnitAmbientSound('AmbientMoveLand')
        elseif new == 'Water' or new == 'Seabed' then
            self:PlayUnitSound('TransitionWater')
            self:PlayUnitAmbientSound('AmbientMoveWater')
        elseif new == 'Sub' then
            self:PlayUnitAmbientSound('AmbientMoveSub')
        end

        local footfall = GetBlueprint(self).Display.MovementEffects[new].Footfall
        if not self.Footfalls and footfall then
            self.Footfalls = self:CreateFootFallManipulators(footfall)
        end
        self:CreateLayerChangeEffects(new, old)

        -- Trigger the re-worded stuff that used to be inherited, no longer because of the engine bug above.
        if self.LayerChangeTrigger then
            self:LayerChangeTrigger(new, old)
        end
    end,

    OnMotionHorzEventChange = function(self, new, old)
        if self.Dead then
            return
        end
        local layer = GetCurrentLayer(self)

        if old == 'Stopped' or (old == 'Stopping' and (new == 'Cruise' or new == 'TopSpeed')) then
            -- Try the specialised sound, fall back to the general one.
            if not self:PlayUnitSound('StartMove' .. layer) then
                self:PlayUnitSound('StartMove')
            end

            -- Initiate the unit's ambient movement sound
            -- Note that there is not currently an 'Air' version, and that
            -- AmbientMoveWater plays if the unit is in either the Water or Seabed layer.
            if not (
                ((layer == 'Water' or layer == 'Seabed') and self:PlayUnitAmbientSound('AmbientMoveWater')) or
                (layer == 'Sub' and self:PlayUnitAmbientSound('AmbientMoveSub')) or
                (layer == 'Land' and self:PlayUnitAmbientSound('AmbientMoveLand'))
                )
            then
                self:PlayUnitAmbientSound('AmbientMove')
            end

            self:StopRocking()
        end

        if (new == 'Stopped' or new == 'Stopping') and (old == 'Cruise' or old == 'TopSpeed') then
            -- Try the specialised sound, fall back to the general one.
            if not self:PlayUnitSound('StopMove' .. layer) then
                self:PlayUnitSound('StopMove')
            end

            -- Units in the water will rock back and forth a bit
            if layer == 'Water' then
                self:StartRocking()
            end
        end

        if new == 'Stopped' or new == 'Stopping' then
            -- Stop ambient sounds
            self:StopUnitAmbientSound('AmbientMove')
            self:StopUnitAmbientSound('AmbientMoveWater')
            self:StopUnitAmbientSound('AmbientMoveSub')
            self:StopUnitAmbientSound('AmbientMoveLand')
        end

        if self.MovementEffectsExist then
            self:UpdateMovementEffectsOnMotionEventChange(new, old)
        end

        if old == 'Stopped' then
            self:DoOnHorizontalStartMoveCallbacks()
        end

        for i = 1, GetWeaponCount(self) do
            local wep = GetWeapon(self, i)
            wep:OnMotionHorzEventChange(new, old)
        end
    end,

    OnMotionVertEventChange = function(self, new, old)
        if self.Dead then
            return
        end

        if new == 'Down' then
            -- Play the "landing" sound
            self:PlayUnitSound('Landing')
        elseif new == 'Bottom' or new == 'Hover' then
            -- Play the "landed" sound
            self:PlayUnitSound('Landed')
        elseif new == 'Up' or (new == 'Top' and (old == 'Down' or old == 'Bottom')) then
            -- Play the "takeoff" sound
            self:PlayUnitSound('TakeOff')
        end

        -- Adjust any beam exhaust
        if new == 'Bottom' then
            self:UpdateBeamExhaust('Landed')
        elseif old == 'Bottom' then
            self:UpdateBeamExhaust('Cruise')
        end

        -- Surfacing and sinking, landing and take off idle effects
        local layer = GetCurrentLayer(self)
        if (new == 'Up' and old == 'Bottom') or (new == 'Down' and old == 'Top') then
            self:DestroyIdleEffects()

            if new == 'Up' and layer == 'Sub' then
                self:PlayUnitSound('SurfaceStart')
            end
            if new == 'Down' and layer == 'Water' then
                self:PlayUnitSound('SubmergeStart')
                if self.SurfaceAnimator then
                    self.SurfaceAnimator:SetRate(-1)
                end
            end
        end

        if (new == 'Top' and old == 'Up') or (new == 'Bottom' and old == 'Down') then
            self:CreateIdleEffects()

            if new == 'Bottom' and layer == 'Sub' then
                self:PlayUnitSound('SubmergeEnd')
            end
            if new == 'Top' and layer == 'Water' then
                self:PlayUnitSound('SurfaceEnd')
                local surfaceAnim = GetBlueprint(self).Display.AnimationSurface
                if not self.SurfaceAnimator and surfaceAnim then
                    self.SurfaceAnimator = CreateAnimator(self)
                end
                if surfaceAnim and self.SurfaceAnimator then
                    self.SurfaceAnimator:PlayAnim(surfaceAnim):SetRate(1)
                end
            end
        end
        self:CreateMotionChangeEffects(new, old)
    end,

    -- Called as planes whoosh round corners. No sounds were shipped for use with this and it was a
    -- cycle eater, so we killed it.
    OnMotionTurnEventChange = function() end,

    OnTerrainTypeChange = function(self, new, old)
        if self.MovementEffectsExist then
            self:DestroyMovementEffects()
            self:CreateMovementEffects(self.MovementEffectsBag, nil, new)
        end
    end,

    OnAnimCollision = function(self, bone, x, y, z)
        local layer = GetCurrentLayer(self)
        local bpTable = GetBlueprint(self).Display.MovementEffects

        if bpTable[layer].Footfall then
            bpTable = bpTable[layer].Footfall
            local effects = {}
            local scale = 1
            local offset
            local army = GetArmy(self)
            local boneTable

            if bpTable.Damage then
                local bpDamage = bpTable.Damage
                DamageArea(self, GetPosition(self, bone), bpDamage.Radius, bpDamage.Amount, bpDamage.Type, bpDamage.DamageFriendly)
            end

            if bpTable.CameraShake then
                local shake = bpTable.CameraShake
                self:ShakeCamera(shake.Radius, shake.MaxShakeEpicenter, shake.MinShakeAtRadius, shake.Interval)
            end

            for _, v in bpTable.Bones do
                if bone == v.FootBone then
                    boneTable = v
                    bone = v.FootBone
                    scale = boneTable.Scale or 1
                    offset = bone.Offset
                    if v.Type then
                        effects = self.GetTerrainTypeEffects('FXMovement', layer, GetPosition(self, v.FootBone), v.Type)
                    end

                    break
                end
            end

            if boneTable.Tread and self:GetTTTreadType(GetPosition(self, bone)) ~= 'None' then
                CreateSplatOnBone(self, boneTable.Tread.TreadOffset, 0, boneTable.Tread.TreadMarks, boneTable.Tread.TreadMarksSizeX, boneTable.Tread.TreadMarksSizeZ, 100, boneTable.Tread.TreadLifeTime or 15, army)

                local treadOffsetX = boneTable.Tread.TreadOffset[1]
                if x and x > 0 then
                    if layer ~= 'Seabed' then
                    self:PlayUnitSound('FootFallLeft')
                    else
                        self:PlayUnitSound('FootFallLeftSeabed')
                    end
                elseif x and x < 0 then
                    if layer ~= 'Seabed' then
                    self:PlayUnitSound('FootFallRight')
                    else
                        self:PlayUnitSound('FootFallRightSeabed')
                    end
                end
            end

            for k, v in effects do
                CreateEmitterAtBone(self, bone, army, v):ScaleEmitter(scale):OffsetEmitter(offset.x or 0, offset.y or 0, offset.z or 0)
            end
        end

        if layer ~= 'Seabed' then
            self:PlayUnitSound('FootFallGeneric')
        else
            self:PlayUnitSound('FootFallGenericSeabed')
        end
    end,

    UpdateMovementEffectsOnMotionEventChange = function(self, new, old)
        if old == 'TopSpeed' then
            -- Destroy top speed contrails and exhaust effects
            self:DestroyTopSpeedEffects()
        end

        local layer = GetCurrentLayer(self)
        local bp = GetBlueprint(self).Display.MovementEffects
        if new == 'TopSpeed' and self.HasFuel then
            local layer = bp[layer]
            if layer.Contrails and self.ContrailEffects then
                self:CreateContrails(layer.Contrails)
            end
            if layer.TopSpeedFX then
                self:CreateMovementEffects(self.TopSpeedEffectsBag, 'TopSpeed')
            end
        end

        if (old == 'Stopped' and new ~= 'Stopping') or (old == 'Stopping' and new ~= 'Stopped') then
            self:DestroyIdleEffects()
            self:DestroyMovementEffects()
            self:CreateMovementEffects(self.MovementEffectsBag, nil)
            if bp.BeamExhaust then
                self:UpdateBeamExhaust('Cruise')
            end
            if self.Detector then
                self.Detector:Enable()
            end
        end

        if new == 'Stopped' then
            self:DestroyMovementEffects()
            self:DestroyIdleEffects()
            self:CreateIdleEffects()
            if bp.BeamExhaust then
                self:UpdateBeamExhaust('Idle')
            end
            if self.Detector then
                self.Detector:Disable()
            end
        end
    end,

    GetTTTreadType = function(self, pos)
        local TerrainType = GetTerrainType(pos.x, pos.z)
        return TerrainType.Treads or 'None'
    end,

    GetTerrainTypeEffects = function(FxType, layer, pos, type, typesuffix)
        local TerrainType

        -- Get terrain type mapped to local position and if none defined use default
        if type then
            TerrainType = GetTerrainType(pos.x, pos.z)
        else
            TerrainType = GetTerrainType(-1, -1)
            type = 'Default'
        end

        -- Add in type suffix to type mask name
        if typesuffix then
            type = type .. typesuffix
        end

        -- If our current masking is empty try and get the default layer effect
        if TerrainType[FxType][layer][type] == nil then
            TerrainType = GetTerrainType(-1, -1)
        end

        return TerrainType[FxType][layer][type] or {}
    end,

    CreateTerrainTypeEffects = function(self, effectTypeGroups, FxBlockType, FxBlockKey, TypeSuffix, EffectBag, TerrainType)
        local army = GetArmy(self)
        local pos = GetPosition(self)
        local effects = {}
        local emit

        for kBG, vTypeGroup in effectTypeGroups do
            local groupType = vTypeGroup.Type
            local bones = vTypeGroup.Bones
            local offset = vTypeGroup.Offset

            if TerrainType then
                effects = TerrainType[FxBlockType][FxBlockKey][groupType] or {}
            else
                effects = self.GetTerrainTypeEffects(FxBlockType, FxBlockKey, pos, groupType, TypeSuffix)
            end

            if not bones or (bones and tableGetn(bones) == 0) then
                WARN('*WARNING: No effect bones defined for layer group ', repr(self:GetUnitId()), ', Add these to a table in Display.[EffectGroup].', GetCurrentLayer(self), '.Effects {Bones ={}} in unit blueprint.')
            else
                for kb, vBone in bones do
                    for ke, vEffect in effects do
                        emit = CreateAttachedEmitter(self, vBone, army, vEffect):ScaleEmitter(vTypeGroup.Scale or 1)
                        if offset then
                            emit:OffsetEmitter(offset[1] or 0, offset[2] or 0, offset[3] or 0)
                        end
                        if EffectBag then
                            tableInsert(EffectBag, emit)
                        end
                    end
                end
            end
        end
    end,

    CreateIdleEffects = function(self)
        local layer = GetCurrentLayer(self)
        local bpLayer = GetBlueprint(self).Display.IdleEffects[layer]

        if bpLayer and bpLayer.Effects then
            self:CreateTerrainTypeEffects(bpLayer.Effects, 'FXIdle',  layer, nil, self.IdleEffectsBag)
        end
    end,

    CreateMovementEffects = function(self, EffectsBag, TypeSuffix, TerrainType)
        local layer = GetCurrentLayer(self)
        local bpTable = GetBlueprint(self).Display.MovementEffects

        if bpTable[layer] then
            bpTable = bpTable[layer]
            local effectTypeGroups = bpTable.Effects

            if bpTable.Treads then
                self:CreateTreads(bpTable.Treads)
            else
                self:RemoveScroller()
            end

            if not effectTypeGroups or (effectTypeGroups and (tableGetn(effectTypeGroups) == 0)) then
                if not self.Footfalls and bpTable.Footfall then
                    WARN('*WARNING: No movement effect groups defined for unit ', repr(self:GetUnitId()), ', Effect groups with bone lists must be defined to play movement effects. Add these to the Display.MovementEffects', layer, '.Effects table in unit blueprint. ')
                end
                return false
            end

            if bpTable.CameraShake then
                self.CamShakeT1 = self:ForkThread(self.MovementCameraShakeThread, bpTable.CameraShake)
            end

            self:CreateTerrainTypeEffects(effectTypeGroups, 'FXMovement', layer, TypeSuffix, EffectsBag, TerrainType)
        end
    end,

    CreateLayerChangeEffects = function(self, new, old)
        local key = old..new
        local bpTable = GetBlueprint(self).Display.LayerChangeEffects[key]

        if bpTable then
            self:CreateTerrainTypeEffects(bpTable.Effects, 'FXLayerChange', key)
        end
    end,

    CreateMotionChangeEffects = function(self, new, old)
        local key = GetCurrentLayer(self)..old..new
        local bpTable = GetBlueprint(self).Display.MotionChangeEffects[key]

        if bpTable then
            self:CreateTerrainTypeEffects(bpTable.Effects, 'FXMotionChange', key)
        end
    end,

    DestroyMovementEffects = function(self)
        CleanupEffectBag(self, 'MovementEffectsBag')

        -- Clean up any camera shake going on.
        local layer = GetBlueprint(self).Display.MovementEffects[GetCurrentLayer(self)]

        if self.CamShakeT1 then
            KillThread(self.CamShakeT1)

            local shake = layer.CameraShake
            if shake and shake.Radius and shake.MaxShakeEpicenter and shake.MinShakeAtRadius then
                self:ShakeCamera(shake.Radius, shake.MaxShakeEpicenter * 0.25, shake.MinShakeAtRadius * 0.25, 1)
            end
        end

        -- Clean up treads
        if self.TreadThreads then
            for _, v in self.TreadThreads do
                KillThread(v)
            end
            self.TreadThreads = {}
        end

        if layer.Treads.ScrollTreads then
            self:RemoveScroller()
        end
    end,

    DestroyTopSpeedEffects = function(self)
        CleanupEffectBag(self, 'TopSpeedEffectsBag')
    end,

    DestroyIdleEffects = function(self)
        CleanupEffectBag(self, 'IdleEffectsBag')
    end,

    UpdateBeamExhaust = function(self, motionState)
        local bpTable = GetBlueprint(self).Display.MovementEffects.BeamExhaust
        if not bpTable then
            return false
        end

        if motionState == 'Idle' then
            if self.BeamExhaustCruise  then
                self:DestroyBeamExhaust()
            end
            if self.BeamExhaustIdle and tableGetn(self.BeamExhaustEffectsBag) == 0 and bpTable.Idle ~= false then
                self:CreateBeamExhaust(bpTable, self.BeamExhaustIdle)
            end
        elseif motionState == 'Cruise' then
            if self.BeamExhaustIdle and self.BeamExhaustCruise then
                self:DestroyBeamExhaust()
            end
            if self.BeamExhaustCruise and bpTable.Cruise ~= false then
                self:CreateBeamExhaust(bpTable, self.BeamExhaustCruise)
            end
        elseif motionState == 'Landed' then
            if not bpTable.Landed then
                self:DestroyBeamExhaust()
            end
        end
    end,

    CreateBeamExhaust = function(self, bpTable, beamBP)
        local effectBones = bpTable.Bones
        if not effectBones or (effectBones and tableGetn(effectBones) == 0) then
            WARN('*WARNING: No beam exhaust effect bones defined for unit ', repr(self:GetUnitId()), ', Effect Bones must be defined to play beam exhaust effects. Add these to the Display.MovementEffects.BeamExhaust.Bones table in unit blueprint.')
            return false
        end
        local army = GetArmy(self)
        for _, vb in effectBones do
            tableInsert(self.BeamExhaustEffectsBag, CreateBeamEmitterOnEntity(self, vb, army, beamBP))
        end
    end,

    DestroyBeamExhaust = function(self)
        CleanupEffectBag(self, 'BeamExhaustEffectsBag')
    end,

    CreateContrails = function(self, tableData)
        local effectBones = tableData.Bones
        if not effectBones or (effectBones and tableGetn(effectBones) == 0) then
            WARN('*WARNING: No contrail effect bones defined for unit ', repr(self:GetUnitId()), ', Effect Bones must be defined to play contrail effects. Add these to the Display.MovementEffects.Air.Contrail.Bones table in unit blueprint. ')
            return false
        end
        local army = GetArmy(self)
        local ZOffset = tableData.ZOffset or 0.0
        for ke, ve in self.ContrailEffects do
            for _, vb in effectBones do
                tableInsert(self.TopSpeedEffectsBag, CreateTrail(self, vb, army, ve):SetEmitterParam('POSITION_Z', ZOffset))
            end
        end
    end,

    MovementCameraShakeThread = function(self, camShake)
        local radius = camShake.Radius or 5.0
        local maxShakeEpicenter = camShake.MaxShakeEpicenter or 1.0
        local minShakeAtRadius = camShake.MinShakeAtRadius or 0.0
        local interval = camShake.Interval or 10.0
        if interval ~= 0.0 then
            while true do
                self:ShakeCamera(radius, maxShakeEpicenter, minShakeAtRadius, interval)
                WaitSeconds(interval)
            end
        end
    end,

    CreateTreads = function(self, treads)
        if treads.ScrollTreads then
            self:AddThreadScroller(1.0, treads.ScrollMultiplier or 0.2)
        end

        self.TreadThreads = {}
        if treads.TreadMarks then
            local type = self:GetTTTreadType(GetPosition(self))
            if type ~= 'None' then
                for k, v in treads.TreadMarks do
                    tableInsert(self.TreadThreads, self:ForkThread(self.CreateTreadsThread, v, type))
                end
            end
        end
    end,

    CreateTreadsThread = function(self, treads, type)
        local sizeX = treads.TreadMarksSizeX
        local sizeZ = treads.TreadMarksSizeZ
        local interval = treads.TreadMarksInterval
        local treadOffset = treads.TreadOffset
        local treadBone = treads.BoneName or 0
        local treadTexture = treads.TreadMarks
        local duration = treads.TreadLifeTime or 10
        local army = GetArmy(self)

        while true do
            -- Syntactic reference
            -- CreateSplatOnBone(entity, offset, boneName, textureName, sizeX, sizeZ, lodParam, duration, army)
            CreateSplatOnBone(self, treadOffset, treadBone, treadTexture, sizeX, sizeZ, 130, duration, army)
            WaitSeconds(interval)
        end
    end,

    CreateFootFallManipulators = function(self, footfall)
        if not footfall.Bones or (footfall.Bones and (tableGetn(footfall.Bones) == 0)) then
            WARN('*WARNING: No footfall bones defined for unit ', repr(self:GetUnitId()), ', ', 'these must be defined to animation collision detector and foot plant controller')
            return false
        end

        self.Detector = CreateCollisionDetector(self)
        self.Trash:Add(self.Detector)
        for _, v in footfall.Bones do
            self.Detector:WatchBone(v.FootBone)
            if v.FootBone and v.KneeBone and v.HipBone then
                CreateFootPlantController(self, v.FootBone, v.KneeBone, v.HipBone, v.StraightLegs or true, v.MaxFootFall or 0):SetPrecedence(10)
            end
        end

        return true
    end,

    GetWeaponClass = function(self, label)
        return self.Weapons[label] or import('/lua/sim/Weapon.lua').Weapon
    end,

    SetReclaimTimeMultiplier = function(self, time_mult)
        self.ReclaimTimeMultiplier = time_mult
    end,

    -- Return the total time in seconds, cost in energy, and cost in mass to reclaim the given target from 100%.
    -- The energy and mass costs will normally be negative, to indicate that you gain mass/energy back.
    GetReclaimCosts = function(self, target_entity)
        local bp = GetBlueprint(self)
        local target_bp = GetBlueprint(target_entity)
        if IsUnit(target_entity) then
            local mtime = target_bp.Economy.BuildCostEnergy / self:GetBuildRate()
            local etime = target_bp.Economy.BuildCostMass / self:GetBuildRate()
            local time = mtime
            if mtime < etime then
                time = etime
            end

            time = time * (self.ReclaimTimeMultiplier or 1)
            time = mathMax((time / 10), 0.0001)  -- This should never be 0 or we'll divide by 0

            return time, target_bp.Economy.BuildCostEnergy, target_bp.Economy.BuildCostMass
        elseif IsProp(target_entity) then
            return target_entity:GetReclaimCosts(self)
        end
    end,

    SetCaptureTimeMultiplier = function(self, time_mult)
        self.CaptureTimeMultiplier = time_mult
    end,

    -- Return the total time in seconds, cost in energy, and cost in mass to capture the given target.
    GetCaptureCosts = function(self, target_entity)
        local target_bp = GetBlueprint(target_entity).Economy
        local bp = GetBlueprint(self).Economy
        local time = ((target_bp.BuildTime or 10) / self:GetBuildRate()) / 2
        local energy = target_bp.BuildCostEnergy or 100
        time = time * (self.CaptureTimeMultiplier or 1)

        return time, energy, 0
    end,

    GetHealthPercent = function(self)
        local health = GetHealth(self)
        local maxHealth = GetBlueprint(self).Defense.MaxHealth
        return health / maxHealth
    end,

    ValidateBone = function(self, bone)
        if IsValidBone(self, bone) then
            return true
        end
        error('*ERROR: Trying to use the bone, ' .. bone .. ' on unit ' .. self:GetUnitId() .. ' and it does not exist in the model.', 2)

        return false
    end,

    CheckBuildRestriction = function(self, target_bp)
        if self:CanBuild(target_bp.BlueprintId) then
            return true
        else
            return false
        end
    end,

    GetSoundEntity = function(self, type)
        if not self.Sounds then self.Sounds = {} end

        if not self.Sounds[type] then
            local sndEnt
            if self.SoundEntities[1] then
                sndEnt = tableRemove(self.SoundEntities, 1)
            else
                sndEnt = Entity()
                Warp(sndEnt, GetPosition(self))
                sndEnt:AttachTo(self, -1)
                self.Trash:Add(sndEnt)
            end
            self.Sounds[type] = sndEnt
        end

        return self.Sounds[type]
    end,

    PlayUnitSound = function(self, sound)
        local bp = GetBlueprint(self)
        if not bp.Audio[sound] then return end

        local entity = self.Sounds['UnitSound'] or self:GetSoundEntity('UnitSound')
        PlaySound(entity, bp.Audio[sound])

        return true
    end,

    PlayUnitAmbientSound = function(self, sound)
        local bp = GetBlueprint(self)
        if not bp.Audio[sound] then return end

        local entity = self:GetSoundEntity('Ambient' .. sound)
        entity:SetAmbientSound(bp.Audio[sound], nil)
    end,

    StopUnitAmbientSound = function(self, sound)
        local bp = GetBlueprint(self)
        if not bp.Audio[sound] then return end

        local type = 'Ambient' .. sound
        local entity = self.Sounds[type] or self:GetSoundEntity(type)
        if entity and not entity:BeenDestroyed() then
            self.Sounds[type] = nil
            entity:SetAmbientSound(nil, nil)
            self.SoundEntities = self.SoundEntities or {}
            tableInsert(self.SoundEntities, entity)
        end
    end,

    -------------------------------------------------------------------------------------------
    -- UNIT CALLBACKS
    -------------------------------------------------------------------------------------------
    AddUnitCallback = function(self, fn, type)
        if not fn then
            error('*ERROR: Tried to add a callback type - ' .. type .. ' with a nil function')
            return
        end
        tableInsert(self.EventCallbacks[type], fn)
    end,

    DoUnitCallbacks = function(self, type, param)
        local callbacks = self.EventCallbacks[type]
        if callbacks then
            for num, cb in callbacks do
                cb(self, param)
            end
        end
    end,

    AddProjectileDamagedCallback = function(self, fn)
        self:AddUnitCallback(fn, "ProjectileDamaged")
    end,

    AddOnCapturedCallback = function(self, cbOldUnit, cbNewUnit)
        if not cbOldUnit and not cbNewUnit then
            error('*ERROR: Tried to add an OnCaptured callback without any functions', 2)
            return
        end
        if cbOldUnit then
            self:AddUnitCallback(cbOldUnit, 'OnCaptured')
        end
        if cbNewUnit then
            self:AddUnitCallback(cbNewUnit, 'OnCapturedNewUnit')
        end
    end,

    --- Add a callback to be invoked when this unit starts building another. The unit being built is
    -- passed as a parameter to the callback function.
    AddOnStartBuildCallback = function(self, fn)
        self:AddUnitCallback(fn, "OnStartBuild")
    end,

    DoOnStartBuildCallbacks = function(self, unit)
        self:DoUnitCallbacks("OnStartBuild", unit)
    end,

    DoOnFailedToBuildCallbacks = function(self)
        self:DoUnitCallbacks("OnFailedToBuild")
    end,

    AddOnUnitBuiltCallback = function(self, fn, category)
        tableInsert(self.EventCallbacks['OnUnitBuilt'], {category=category, cb=fn})
    end,

    DoOnUnitBuiltCallbacks = function(self, unit)
        for _, v in self.EventCallbacks['OnUnitBuilt'] or {} do
            if unit and not unit.Dead and EntityCategoryContains(v.category, unit) then
                v.cb(self, unit)
            end
        end
    end,

    AddOnHorizontalStartMoveCallback = function(self, fn)
        self:AddUnitCallback(fn, "OnHorizontalStartMove")
    end,

    DoOnHorizontalStartMoveCallbacks = function(self)
        self:DoUnitCallbacks("OnHorizontalStartMove")
    end,

    RemoveCallback = function(self, fn)
        for k, v in self.EventCallbacks do
            if type(v) == "table" then
                for kcb, vcb in v do
                    if vcb == fn then
                        v[kcb] = nil
                    end
                end
            end
        end
    end,

    AddOnDamagedCallback = function(self, fn, amount, repeatNum)
        if not fn then
            error('*ERROR: Tried to add an OnDamaged callback with a nil function')
            return
        end
        local num = amount or -1
        repeatNum = repeatNum or 1
        tableInsert(self.EventCallbacks.OnDamaged, {Func = fn, Amount=num, Called=0, Repeat = repeatNum})
    end,

    DoOnDamagedCallbacks = function(self, instigator)
        if self.EventCallbacks.OnDamaged then
            for num, callback in self.EventCallbacks.OnDamaged do
                local called = callback.Called
                local Repeat = callback.Repeat
                local amount = callback.Amount
                if (called < Repeat or Repeat == -1) and (amount == -1 or (1 - self:GetHealthPercent() > amount)) then
                    called = called + 1
                    callback.Func(self, instigator)
                end
            end
        end
    end,

    -------------------------------------------------------------------------------------------
    -- STATES
    -------------------------------------------------------------------------------------------
    IdleState = State {
        Main = function(self)
        end,
    },

    DeadState = State {
        Main = function(self)
        end,
    },

    WorkingState = State {
        Main = function(self)
            while self.WorkProgress < 1 and not self.Dead do
                WaitSeconds(0.1)
            end
        end,

        OnWorkEnd = function(self, work)
            self:ClearWork()
            self:SetActiveConsumptionInactive()
            AddUnitEnhancement(self, work)
            self:CleanupEnhancementEffects(work)
            self:CreateEnhancement(work)
            self:PlayUnitSound('EnhanceEnd')
            self:StopUnitAmbientSound('EnhanceLoop')
            self:EnableDefaultToggleCaps()
            ChangeState(self, self.IdleState)
        end,
    },

    -------------------------------------------------------------------------------------------
    -- BUFFS
    -------------------------------------------------------------------------------------------
    AddBuff = function(self, buffTable, PosEntity)
        local bt = buffTable.BuffType
        if not bt then
            error('*ERROR: Tried to add a unit buff in unit.lua but got no buff table.  Wierd.', 1)
            return
        end

        -- When adding debuffs we have to make sure that we check for permissions
        local category = buffTable.TargetAllow and ParseEntityCategory(buffTable.TargetAllow) or categories.ALLUNITS
        if buffTable.TargetDisallow then
            category = category - ParseEntityCategory(buffTable.TargetDisallow)
        end

        if bt == 'STUN' then
            local targets
            if buffTable.Radius and buffTable.Radius > 0 then
                -- If the radius is bigger than 0 then we will use the unit as the center of the stun blast
                targets = utilities.GetTrueEnemyUnitsInSphere(self, PosEntity or GetPosition(self), buffTable.Radius, category)
            else
                -- The buff will be applied to the unit only
                if EntityCategoryContains(category, self) then
                    targets = {self}
                end
            end

            -- Exclude things currently flying around
            for _, target in targets or {} do
                if GetCurrentLayer(target) ~= 'Air' then
                    target:SetStunned(buffTable.Duration or 1)
                end
            end
        elseif bt == 'MAXHEALTH' then
            self:SetMaxHealth(GetMaxHealth(self) + (buffTable.Value or 0))
        elseif bt == 'HEALTH' then
            self:SetHealth(self, GetHealth(self) + (buffTable.Value or 0))
        elseif bt == 'SPEEDMULT' then
            self:SetSpeedMult(buffTable.Value or 0)
        elseif bt == 'MAXFUEL' then
            self:SetFuelUseTime(buffTable.Value or 0)
        elseif bt == 'FUELRATIO' then
            self:SetFuelRatio(buffTable.Value or 0)
        elseif bt == 'HEALTHREGENRATE' then
            self:SetRegenRate(buffTable.Value or 0)
        end
    end,

    AddWeaponBuff = function(self, buffTable, weapon)
        local bt = buffTable.BuffType
        if not bt then
            error('*ERROR: Tried to add a weapon buff in unit.lua but got no buff table.  Wierd.', 1)
            return
        end

        if bt == 'RATEOFFIRE' then
            weapon:ChangeRateOfFire(buffTable.Value or 1)
        elseif bt == 'TURRETYAWSPEED' then
            weapon:SetTurretYawSpeed(buffTable.Value or 0)
        elseif bt == 'TURRETPITCHSPEED' then
            weapon:SetTurretPitchSpeed(buffTable.Value or 0)
        elseif bt == 'DAMAGE' then
            weapon:AddDamageMod(buffTable.Value or 0)
        elseif bt == 'MAXRADIUS' then
            weapon:ChangeMaxRadius(buffTable.Value or GetBlueprint(weapon).MaxRadius)
        elseif bt == 'FIRINGRANDOMNESS' then
            weapon:SetFiringRandomness(buffTable.Value or 0)
        else
            self:AddBuff(buffTable)
        end
    end,

    SetRegen = function(self, value)
        self:SetRegenRate(value)
        self.Sync.regen = value
    end,

    -------------------------------------------------------------------------------------------
    -- SHIELDS
    -------------------------------------------------------------------------------------------
    CreateShield = function(self, bpShield)
        -- Copy the shield template so we don't alter the blueprint table.
        local bpShield = tableDeepCopy(bpShield)
        self:DestroyShield()

        if bpShield.PersonalShield then
            self.MyShield = PersonalShield(bpShield, self)
        elseif bpShield.AntiArtilleryShield then
            self.MyShield = AntiArtilleryShield(bpShield, self)
        elseif bpShield.PersonalBubble then
            self.MyShield = PersonalBubble(bpShield, self)
        elseif bpShield.TransportShield then
            self.MyShield = TransportShield(bpShield, self)
        else
            self.MyShield = Shield(bpShield, self)
        end

        self:SetFocusEntity(self.MyShield)
        self:EnableShield()
        self.Trash:Add(self.MyShield)
    end,

    EnableShield = function(self)
        self:SetScriptBit('RULEUTC_ShieldToggle', true)
        if self.MyShield then
            self.MyShield:TurnOn()
        end
    end,

    DisableShield = function(self)
        self:SetScriptBit('RULEUTC_ShieldToggle', false)
        if self.MyShield then
            self.MyShield:TurnOff()
        end
    end,

    DestroyShield = function(self)
        if self.MyShield then
            self:ClearFocusEntity()
            self.MyShield:Destroy()
            self.MyShield = nil
        end
    end,

    ShieldIsOn = function(self)
        if self.MyShield then
            return self.MyShield:IsOn()
        end
    end,

    GetShieldType = function(self)
        if self.MyShield then
            return self.MyShield.ShieldType or 'Unknown'
        end
        return 'None'
    end,

    OnAdjacentBubbleShieldDamageSpillOver = function(self, instigator, spillingUnit, damage, type)
        if self.MyShield then
            self.MyShield:OnAdjacentBubbleShieldDamageSpillOver(instigator, spillingUnit, damage, type)
        end
    end,

    OnShieldEnabled = function(self)
    end,

    OnShieldDisabled = function(self)
    end,

    -------------------------------------------------------------------------------------------
    -- TRANSPORTING
    -------------------------------------------------------------------------------------------

    GetTransportClass = function(self)
        return GetBlueprint(self).Transport.TransportClass or 1
    end,

    OnStartTransportBeamUp = function(self, transport, bone)
        local slot = transport.slots[bone]
        if slot then
            self:GetAIBrain():OnTransportFull()
            IssueClearCommands({self})
            return
        end

        self:DestroyIdleEffects()
        self:DestroyMovementEffects()

        local army =  GetArmy(self)
        tableInsert(self.TransportBeamEffectsBag, AttachBeamEntityToEntity(self, -1, transport, bone, army, EffectTemplate.TTransportBeam01))
        tableInsert(self.TransportBeamEffectsBag, AttachBeamEntityToEntity(transport, bone, self, -1, army, EffectTemplate.TTransportBeam02))
        tableInsert(self.TransportBeamEffectsBag, CreateEmitterAtBone(transport, bone, army, EffectTemplate.TTransportGlow01))
        self:TransportAnimation()
    end,

    OnStopTransportBeamUp = function(self)
        self:DestroyIdleEffects()
        self:DestroyMovementEffects()
        for k, v in self.TransportBeamEffectsBag do
            v:Destroy()
        end

        -- Reset weapons to ensure torso centres and unit survives drop
        for i = 1, GetWeaponCount(self) do
            local wep = GetWeapon(self, i)
            wep:ResetTarget()
        end
    end,

    MarkWeaponsOnTransport = function(self, bool)
        for i = 1, GetWeaponCount(self) do
            local wep = GetWeapon(self, i)
            wep:SetOnTransport(bool)
        end
    end,

    OnStorageChange = function(self, loading)
        self:MarkWeaponsOnTransport(loading)

        if loading then
            HideBone(self, 0, true)
        else
            ShowBone(self, 0, true)
        end

        self.CanTakeDamage = not loading
        self:SetDoNotTarget(loading)
        self:SetReclaimable(not loading)
        self:SetCapturable(not loading)
    end,

    OnAddToStorage = function(self, unit)
        self:OnStorageChange(true)
    end,

    OnRemoveFromStorage = function(self, unit)
        self:OnStorageChange(false)
    end,

    -- Animation when being dropped from a transport.
    TransportAnimation = function(self, rate)
        self:ForkThread(self.TransportAnimationThread, rate)
    end,

    TransportAnimationThread = function(self, rate)
        local bp = GetBlueprint(self).Display.TransportAnimation

        if rate and rate < 0 and GetBlueprint(self).Display.TransportDropAnimation then
            bp = GetBlueprint(self).Display.TransportDropAnimation
            rate = -rate
        end

        WaitSeconds(.5)
        if bp then
            local animBlock = self:ChooseAnimBlock(bp)
            if animBlock.Animation then
                if not self.TransAnimation then
                    self.TransAnimation = CreateAnimator(self)
                    self.Trash:Add(self.TransAnimation)
                end
                self.TransAnimation:PlayAnim(animBlock.Animation)
                rate = rate or 1
                self.TransAnimation:SetRate(rate)
                WaitFor(self.TransAnimation)
            end
        end
    end,

    -------------------------------------------------------------------------------------------
    -- TELEPORTING
    -------------------------------------------------------------------------------------------
    OnTeleportUnit = function(self, teleporter, location, orientation)
        if self.TeleportDrain then
            RemoveEconomyEvent(self, self.TeleportDrain)
            self.TeleportDrain = nil
        end

        if self.TeleportThread then
            KillThread(self.TeleportThread)
            self.TeleportThread = nil
        end

        self:CleanupTeleportChargeEffects()
        self.TeleportThread = self:ForkThread(self.InitiateTeleportThread, teleporter, location, orientation)
    end,

    OnFailedTeleport = function(self)
        if self.TeleportDrain then
            RemoveEconomyEvent(self, self.TeleportDrain)
            self.TeleportDrain = nil
        end

        if self.TeleportThread then
            KillThread(self.TeleportThread)
            self.TeleportThread = nil
        end

        self:StopUnitAmbientSound('TeleportLoop')
        self:CleanupTeleportChargeEffects()
        self:CleanupRemainingTeleportChargeEffects()
        self:SetWorkProgress(0.0)
        self:SetImmobile(false)
        self.UnitBeingTeleported = nil
    end,

    InitiateTeleportThread = function(self, teleporter, location, orientation)
        self.UnitBeingTeleported = self
        self:SetImmobile(true)
        self:PlayUnitSound('TeleportStart')
        self:PlayUnitAmbientSound('TeleportLoop')

        local bp = GetBlueprint(self).Economy
        local energyCost, time
        if bp then
            local mass = (bp.TeleportMassCost or bp.BuildCostMass or 1) * (bp.TeleportMassMod or 0.01)
            local energy = (bp.TeleportEnergyCost or bp.BuildCostEnergy or 1) * (bp.TeleportEnergyMod or 0.01)
            energyCost = mass + energy
            time = energyCost * (bp.TeleportTimeMod or 0.01)
        end

        self.TeleportDrain = CreateEconomyEvent(self, energyCost or 100, 0, time or 5, self.UpdateTeleportProgress)

        -- Create teleport charge effect
        self:PlayTeleportChargeEffects(location, orientation)
        WaitFor(self.TeleportDrain)

        if self.TeleportDrain then
            RemoveEconomyEvent(self, self.TeleportDrain)
            self.TeleportDrain = nil
        end

        self:PlayTeleportOutEffects()
        self:CleanupTeleportChargeEffects()
        WaitSeconds(0.1)
        self:SetWorkProgress(0.0)
        Warp(self, location, orientation)
        self:PlayTeleportInEffects()
        self:CleanupRemainingTeleportChargeEffects()

        WaitSeconds(0.1) -- Perform cooldown Teleportation FX here

        -- Landing Sound
        self:StopUnitAmbientSound('TeleportLoop')
        self:PlayUnitSound('TeleportEnd')
        self:SetImmobile(false)
        self.UnitBeingTeleported = nil
        self.TeleportThread = nil
    end,

    UpdateTeleportProgress = function(self, progress)
        self:SetWorkProgress(progress)
        EffectUtilities.TeleportChargingProgress(self, progress)
    end,

    PlayTeleportChargeEffects = function(self, location, orientation, teleDelay)
        EffectUtilities.PlayTeleportChargingEffects(self, location, self.TeleportFxBag, teleDelay)
    end,

    CleanupTeleportChargeEffects = function(self)
        EffectUtilities.DestroyTeleportChargingEffects(self, self.TeleportFxBag)
    end,

    CleanupRemainingTeleportChargeEffects = function(self)
        EffectUtilities.DestroyRemainingTeleportChargingEffects(self, self.TeleportFxBag)
    end,

    PlayTeleportOutEffects = function(self)
        EffectUtilities.PlayTeleportOutEffects(self, self.TeleportFxBag)
    end,

    PlayTeleportInEffects = function(self)
        EffectUtilities.PlayTeleportInEffects(self, self.TeleportFxBag)
    end,

    ------------------------------------------------------------------------------------------
    -- ROCKING
    -------------------------------------------------------------------------------------------
    -- Causes units to rock from side to side on water
    StartRocking = function(self)
        KillThread(self.StopRockThread)
        self.StartRockThread = self:ForkThread(self.RockingThread)
    end,

    StopRocking = function(self)
        KillThread(self.StartRockThread)
        self.StopRockThread = self:ForkThread(self.EndRockingThread)
    end,

    RockingThread = function(self)
        local bp = GetBlueprint(self).Display
        if not self.RockManip and not self.Dead and bp.MaxRockSpeed and bp.MaxRockSpeed > 0 then
            self.RockManip = CreateRotator(self, 0, 'z', nil, 0, (bp.MaxRockSpeed or 1.5) / 5, (bp.MaxRockSpeed or 1.5) * 3 / 5)
            self.Trash:Add(self.RockManip)
            self.RockManip:SetPrecedence(0)

            while true do
                WaitFor(self.RockManip)

                if self.Dead then break end -- Abort if the unit died

                self.RockManip:SetTargetSpeed(- bp.MaxRockSpeed or 1.5)
                WaitFor(self.RockManip)

                if self.Dead then break end -- Abort if the unit died

                self.RockManip:SetTargetSpeed(bp.MaxRockSpeed or 1.5)
            end
        end
    end,

    EndRockingThread = function(self)
        local bp = GetBlueprint(self).Display
        local manip = self.RockManip

        if manip then
            manip:SetGoal(0)
            manip:SetSpeed((bp.MaxRockSpeed or 1.5) / 4)
            WaitFor(manip)

            if manip then
                manip:Destroy()
                self.RockManip = nil
            end
        end
    end,

    -- Buff Fields
    InitBuffFields = function(self)
        -- Creates all buff fields
        local bpBuffFields = GetBlueprint(self).BuffFields
        if self.BuffFields and bpBuffFields then
            for scriptName, field in self.BuffFields do
                -- Getting buff field blueprint

                local BuffFieldBp = BuffFieldBlueprints[bpBuffFields[scriptName]]
                if not BuffFieldBp or type(BuffFieldBp) ~= 'table' then
                    WARN('BuffField: no blueprint data for buff field '..repr(scriptName))
                else
                    -- We need a different buff field instance for each unit. This takes care of that.
                    if not self.MyBuffFields then
                        self.MyBuffFields = {}
                    end
                    self.MyBuffFields[scriptName] = self:CreateBuffField(scriptName, BuffFieldBp)
                end
            end
        end
    end,

    CreateBuffField = function(self, name, buffFieldBP) -- Buff field stuff
        local spec = {
            Name = buffFieldBP.Name,
            Owner = self,
        }
        return (self.BuffFields[name](spec))
    end,

    GetBuffFieldByName = function(self, name)
        if self.BuffFields and self.MyBuffFields then
            for k, field in self.MyBuffFields do
                local fieldBP = GetBlueprint(field)
                if fieldBP.Name == name then
                    return field
                end
            end
        end
    end,

    OnAttachedToTransport = function(self, transport, bone)
        self:MarkWeaponsOnTransport(true)
        if self:ShieldIsOn() then
            self:DisableShield()
            self:DisableDefaultToggleCaps()
        end
        self:DoUnitCallbacks('OnAttachedToTransport', transport, bone)
    end,

    OnDetachedFromTransport = function(self, transport, bone)
        self:MarkWeaponsOnTransport(false)
        self:EnableShield()
        self:EnableDefaultToggleCaps()
        self:TransportAnimation(-1)
        self:DoUnitCallbacks('OnDetachedFromTransport', transport, bone)
    end,

    -- Utility Functions
    SendNotifyMessage = function(self, trigger, source)
        local focusArmy = GetFocusArmy()
        local army = self:GetArmy()
        if focusArmy == -1 or focusArmy == army then
            local id
            local unitType
            local category

            if not source then
                local bp = self:GetBlueprint()
                if bp.CategoriesHash.RESEARCH then
                    unitType = string.lower('research' .. self.layerCategory .. self.techCategory)
                    category = 'tech'
                elseif EntityCategoryContains(categories.NUKE * categories.STRUCTURE - categories.EXPERIMENTAL, self) then -- Ensure to exclude Yolona Oss, which gets its own message
                    unitType = 'nuke'
                    category = 'other'
                elseif EntityCategoryContains(categories.TECH3 * categories.STRUCTURE * categories.ARTILLERY, self) then
                    unitType = 'arty'
                    category = 'other'
                elseif self.techCategory == 'EXPERIMENTAL' then
                    unitType = bp.BlueprintId
                    category = 'experimentals'
                else
                    return
                end
            else -- We are being called from the Enhancements chain (ACUs)
                id = self.EntityId
                category = string.lower(self.factionCategory)
            end

            if trigger == 'transferred' then
                if not Sync.EnhanceMessage then return end
                for index, msg in Sync.EnhanceMessage do
                    if msg.source == (source or unitType) and msg.trigger == 'completed' and msg.category == category and msg.id == id then
                        table.remove(Sync.EnhanceMessage, index)
                        break
                    end
                end
            else
                if not Sync.EnhanceMessage then Sync.EnhanceMessage = {} end
                local message = {source = source or unitType, trigger = trigger, category = category, id = id, army = army}
                table.insert(Sync.EnhanceMessage, message)
            end
        end
    end,

    --- Deprecated functionality
    GetUnitBeingBuilt = function(self)
        if not GetUnitBeingBuiltWarning then
            WARN("Deprecated function GetUnitBeingBuilt called at")
            WARN(debug.traceback())
            WARN("Further warnings of this will be suppressed")
            GetUnitBeingBuiltWarning = true
        end

        return self.UnitBeingBuilt
    end,

    -- Return the total time in seconds, cost in energy, and cost in mass to build the given target type.
    GetBuildCosts = function(self, target_bp)
        if not GetBuildCostsWarning then
            WARN("Deprecated function GetBuildCosts called at")
            WARN(debug.traceback())
            WARN("Further warnings of this will be suppressed")
            GetBuildCostsWarning = true
        end

        return GetConstructEconomyModel(self, target_bp.Economy)
    end,

    OnCreated = function(self)
        if not OnCreatedWarning then
            WARN("Deprecated function OnCreated called at")
            WARN(debug.traceback())
            WARN("Further warnings of this will be suppressed")
            OnCreatedWarning = true
        end
    end,

    CheckCanTakeDamage = function(self)
        if not CheckCanTakeDamageWarning then
            WARN("Deprecated function CheckCanTakeDamage called at")
            WARN(debug.traceback())
            WARN("Further warnings of this will be suppressed")
            CheckCanTakeDamageWarning = true
        end

        return self.CanTakeDamage
    end,

    SetCanTakeDamage = function(self, val)
        if not SetCanTakeDamageWarning then
            WARN("Deprecated function SetCanTakeDamage called at")
            WARN(debug.traceback())
            WARN("Further warnings of this will be suppressed")
            SetCanTakeDamageWarning = true
        end

        self.CanTakeDamage = val
    end,

    -- Argument val is true or false. False = cannot be killed
    SetCanBeKilled = function(self, val)
        if not SetCanBeKilledWarning then
            WARN("Deprecated function SetCanBeKilled called at")
            WARN(debug.traceback())
            WARN("Further warnings of this will be suppressed")
            SetCanBeKilledWarning = true
        end

        self.CanBeKilled = val
    end,

    -- Deprecated, but too common in the base game files to just remove
    -- TODO: Remove all references to this function
    IsDead = function(self)
        if not IsDeadWarning then
            WARN("Deprecated function IsDead called at")
            WARN(debug.traceback())
            WARN("Further warnings of this will be suppressed")
            IsDeadWarning = true
        end

        return self.Dead
    end,

    -- This is called from the engine in the Kill() function.
    SetDead = function(self)
        self.Dead = true
    end,

    GetEconomyBuildRate = function(self)
        if not GetEconomyBuildRateWarning then
            WARN("Deprecated function GetEconomyBuildRate called at")
            WARN(debug.traceback())
            WARN("Further warnings of this will be suppressed")
            GetEconomyBuildRateWarning = true
        end

        return self:GetBuildRate()
    end,

    GetMassBuildAdjMod = function(self)
        if not GetMassBuildAdjModWarning then
            WARN("Deprecated function GetMassBuildAdjMod called at")
            WARN(debug.traceback())
            WARN("Further warnings of this will be suppressed")
            GetMassBuildAdjModWarning = true
        end

        return self.MassBuildAdjMod or 1
    end,

    GetEnergyBuildAdjMod = function(self)
        if not GetEnergyBuildAdjModWarning then
            WARN("Deprecated function GetEnergyBuildAdjMod called at")
            WARN(debug.traceback())
            WARN("Further warnings of this will be suppressed")
            GetEnergyBuildAdjModWarning = true
        end

        return self.EnergyBuildAdjMod or 1
    end,

    SetEnergyMaintenanceConsumptionOverride = function(self, override)
        if not SetEnergyMaintenanceConsumptionOverrideWarning then
            WARN("Deprecated function SetEnergyMaintenanceConsumptionOverride called at")
            WARN(debug.traceback())
            WARN("Further warnings of this will be suppressed")
            SetEnergyMaintenanceConsumptionOverrideWarning = true
        end

        self.EnergyMaintenanceConsumptionOverride = override or 0
    end,

    SetBuildRateOverride = function(self, overRide)
        if not SetBuildRateOverrideWarning then
            WARN("Deprecated function SetBuildRateOverride called at")
            WARN(debug.traceback())
            WARN("Further warnings of this will be suppressed")
            SetBuildRateOverrideWarning = true
        end

        self.BuildRateOverride = overRide
    end,

    GetBuildRateOverride = function(self)
        if not GetBuildRateOverrideWarning then
            WARN("Deprecated function GetBuildRateOverride called at")
            WARN(debug.traceback())
            WARN("Further warnings of this will be suppressed")
            GetBuildRateOverrideWarning = true
        end

        return self.BuildRateOverride
    end,

    -- DO NOT REMOVE THIS FUNCTION. Though it looks useless, and is rarely if ever called from lua, removal causes a nearly 25% increase in execution time!
    CheckCanBeKilled = function(self, other)
        if not CheckCanBeKilledWarning then
            WARN("Deprecated function CheckCanBeKilled called at")
            WARN(debug.traceback())
            WARN("Further warnings of this will be suppressed")
            CheckCanBeKilledWarning = true
        end

        return self.CanBeKilled
    end,
}
