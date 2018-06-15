StructureUnit = Class(Unit) {
    -- Stucture unit specific damage effects and smoke
    FxDamage1 = {EffectTemplate.DamageStructureSmoke01, EffectTemplate.DamageStructureSparks01},
    FxDamage2 = {EffectTemplate.DamageStructureFireSmoke01, EffectTemplate.DamageStructureSparks01},
    FxDamage3 = {EffectTemplate.DamageStructureFire01, EffectTemplate.DamageStructureSparks01},

    OnCreate = function(self)
        Unit.OnCreate(self)
        self.FxBlinkingLightsBag = {}
        self.CachePosition = self:GetCachePosition()
    end,
    
    GetCachePosition = function(self)
        return self.CachePosition or GetPosition(self)
    end,
    
    OnStopBeingBuilt = function(self, builder, layer)
        Unit.OnStopBeingBuilt(self, builder, layer)
        self:PlayActiveAnimation()
    end,
}

AmphibiousStructureUnit = Class(LandStructureUnit) {
    LandBuiltHiddenBones = {'Floatation'},
    
    HideLandBones = function(self)
        -- Hide the bones for buildings built on land
        if GetCurrentLayer(self) == 'Land' then
            HideBone(self, v, true)
        end
    end,
}

NavalStructureUnit = Class(StructureUnit) {
}

LandStructureUnit = Class(StructureUnit) {
    OnCreate = function(self)
        LandStructureUnit.OnCreate(self)
        if self:GetCurrentLayer() == 'Land' and self:GetBlueprint().Physics.FlattenSkirt then
            self:FlattenSkirt()
        end
    end,
}

UEFLandStructureUnit = Class(LandStructureUnit) {
    OnStartBeingBuilt = function(self, builder, layer)
        LandStructureUnit.OnStartBeingBuilt(self, builder, layer)
        local bp = self:GetBlueprint()
        if bp.Physics.FlattenSkirt and not self:HasTarmac() then
            if self.TarmacBag then
                self:CreateTarmac(true, true, true, self.TarmacBag.Orientation, self.TarmacBag.CurrentBP)
            else
                self:CreateTarmac(true, true, true, false, false)
            end
        end
    end,
}

CybranLandStructureUnit = Class(LandStructureUnit) {
    OnStartBeingBuilt = function(self, builder, layer)
        LandStructureUnit.OnStartBeingBuilt(self, builder, layer)
        local bp = self:GetBlueprint()
        if bp.Physics.FlattenSkirt and not self:HasTarmac() then
            if self.TarmacBag then
                self:CreateTarmac(true, true, true, self.TarmacBag.Orientation, self.TarmacBag.CurrentBP)
            else
                self:CreateTarmac(true, true, true, false, false)
            end
        end
    end,
}

AeonLandStructureUnit = Class(LandStructureUnit) {
    OnStartBeingBuilt = function(self, builder, layer)
        LandStructureUnit.OnStartBeingBuilt(self, builder, layer)
        local bp = self:GetBlueprint()
        if bp.Physics.FlattenSkirt and not self:HasTarmac() then
            if self.TarmacBag then
                self:CreateTarmac(true, true, true, self.TarmacBag.Orientation, self.TarmacBag.CurrentBP)
            else
                self:CreateTarmac(true, true, true, false, false)
            end
        end
    end,
}

SeraphimLandStructureUnit = Class(LandStructureUnit) {
    OnStopBeingBuilt = function(self, builder, layer)
        LandStructureUnit.OnStopBeingBuilt(self, builder, layer)
        self:CreateTarmac(true, true, true, false, false)
    end,
}

WeaponStructureUnit = Class(StructureUnit, WeaponUnit) {
    OnStartBeingBuilt = function(self, builder, layer)
        StructureUnit.OnStartBeingBuilt(self, builder, layer)
        WeaponUnit.OnStartBeingBuilt(self, builder, layer)
        self:RotateTowardsEnemy()
    end,

    RotateTowardsEnemy = function(self)
        local bp = self:GetBlueprint()
        local army = self:GetArmy()
        local brain = self:GetAIBrain()
        local pos = self:GetCachePosition()
        local x, y = GetMapSize()
        local threats = {{pos = {x / 2, 0, y / 2}, dist = VDist2(pos[1], pos[3], x, y), threat = -1}}
        local cats = EntityCategoryContains(categories.ANTIAIR, self) and categories.AIR or (categories.STRUCTURE + categories.LAND + categories.NAVAL)
        local units = brain:GetUnitsAroundPoint(cats, pos, 2 * (bp.AI.GuardScanRadius or 100), 'Enemy')
        for _, u in units do
            local blip = u:GetBlip(army)
            if blip then
                local on_radar = blip:IsOnRadar(army)
                local seen = blip:IsSeenEver(army)

                if on_radar or seen then
                    local epos = u:GetCachePosition()
                    local threat = seen and (u:GetBlueprint().Defense.SurfaceThreatLevel or 0) or 1

                    table.insert(threats, {pos = epos, threat = threat, dist = VDist2(pos[1], pos[3], epos[1], epos[3])})
                end
            end
        end

        table.sort(threats, function(a, b)
            if a.threat <= 0 and b.threat <= 0 then
                return a.threat == b.threat and a.dist < b.dist or a.threat > b.threat
            elseif a.threat <= 0 then return false
            elseif b.threat <= 0 then return true
            else return a.dist < b.dist end
        end)

        local t = threats[1]
        local rad = math.atan2(t.pos[1]-pos[1], t.pos[3]-pos[3])
        local degrees = rad * (180 / math.pi)

        if EntityCategoryContains(categories.ARTILLERY * (categories.TECH3 + categories.EXPERIMENTAL), self) then
            degrees = math.floor((degrees + 45) / 90) * 90
        end

        self:SetRotation(degrees)
    end,
}

CreationUnit = Class(Unit) {
    MinConsumptionPerSecondEnergy = 1,
}

ProductionUnit = Class(Unit) {
    MinConsumptionPerSecondEnergy = 1,
}




StructureUnit = Class(Unit) {
    --LandBuiltHiddenBones = {'Floatation'},
    --MinConsumptionPerSecondEnergy = 1,
    --MinWeaponRequiresEnergy = 0, -- Unused

    -- Stucture unit specific damage effects and smoke
    --FxDamage1 = {EffectTemplate.DamageStructureSmoke01, EffectTemplate.DamageStructureSparks01},
    --FxDamage2 = {EffectTemplate.DamageStructureFireSmoke01, EffectTemplate.DamageStructureSparks01},
    --FxDamage3 = {EffectTemplate.DamageStructureFire01, EffectTemplate.DamageStructureSparks01},

    --OnCreate = function(self)
        --Unit.OnCreate(self)
        --self.WeaponMod = {} -- unused
        --self.FxBlinkingLightsBag = {}
        --self.CachePosition = self:GetCachePosition()
        --if self:GetCurrentLayer() == 'Land' and self:GetBlueprint().Physics.FlattenSkirt then
            --self:FlattenSkirt()
        --end
    --end,

    --GetCachePosition = function(self)
        --return self.CachePosition or GetPosition(self)
    --end,

    --[[RotateTowardsEnemy = function(self)
        local bp = self:GetBlueprint()
        local army = self:GetArmy()
        local brain = self:GetAIBrain()
        local pos = self:GetCachePosition()
        local x, y = GetMapSize()
        local threats = {{pos = {x / 2, 0, y / 2}, dist = VDist2(pos[1], pos[3], x, y), threat = -1}}
        local cats = EntityCategoryContains(categories.ANTIAIR, self) and categories.AIR or (categories.STRUCTURE + categories.LAND + categories.NAVAL)
        local units = brain:GetUnitsAroundPoint(cats, pos, 2 * (bp.AI.GuardScanRadius or 100), 'Enemy')
        for _, u in units do
            local blip = u:GetBlip(army)
            if blip then
                local on_radar = blip:IsOnRadar(army)
                local seen = blip:IsSeenEver(army)

                if on_radar or seen then
                    local epos = u:GetCachePosition()
                    local threat = seen and (u:GetBlueprint().Defense.SurfaceThreatLevel or 0) or 1

                    table.insert(threats, {pos = epos, threat = threat, dist = VDist2(pos[1], pos[3], epos[1], epos[3])})
                end
            end
        end

        table.sort(threats, function(a, b)
            if a.threat <= 0 and b.threat <= 0 then
                return a.threat == b.threat and a.dist < b.dist or a.threat > b.threat
            elseif a.threat <= 0 then return false
            elseif b.threat <= 0 then return true
            else return a.dist < b.dist end
        end)

        local t = threats[1]
        local rad = math.atan2(t.pos[1]-pos[1], t.pos[3]-pos[3])
        local degrees = rad * (180 / math.pi)

        if EntityCategoryContains(categories.ARTILLERY * (categories.TECH3 + categories.EXPERIMENTAL), self) then
            degrees = math.floor((degrees + 45) / 90) * 90
        end

        self:SetRotation(degrees)
    end,--]]

    --[[OnStartBeingBuilt = function(self, builder, layer)
        if EntityCategoryContains(categories.STRUCTURE * (categories.DIRECTFIRE + categories.INDIRECTFIRE) * (categories.DEFENSE + categories.ARTILLERY), self) then
            self:RotateTowardsEnemy()
        end

        Unit.OnStartBeingBuilt(self, builder, layer)
        local bp = self:GetBlueprint()
        if bp.Physics.FlattenSkirt and not self:HasTarmac() and bp.General.FactionName ~= "Seraphim" then
            if self.TarmacBag then
                self:CreateTarmac(true, true, true, self.TarmacBag.Orientation, self.TarmacBag.CurrentBP)
            else
                self:CreateTarmac(true, true, true, false, false)
            end
        end
    end,--]]

    --[[OnStopBeingBuilt = function(self, builder, layer)
        Unit.OnStopBeingBuilt(self, builder, layer)
        -- Whaa why can't we have sane inheritance chains :/
        if self:GetBlueprint().General.FactionName == "Seraphim" then
            self:CreateTarmac(true, true, true, false, false)
        end
        self:PlayActiveAnimation()
    end,--]]

    OnFailedToBeBuilt = function(self)
        Unit.OnFailedToBeBuilt(self)
        self:DestroyTarmac()
    end,

    FlattenSkirt = function(self)
        local x, y, z = unpack(self:GetCachePosition())
        local x0, z0, x1, z1 = self:GetSkirtRect()
        x0, z0, x1, z1 = math.floor(x0), math.floor(z0), math.ceil(x1), math.ceil(z1)
        FlattenMapRect(x0, z0, x1 - x0, z1 - z0, y)
    end,

    -- Returns 4 numbers: skirt x0, skirt z0, skirt.x1, skirt.z1
    GetSkirtRect = function(self)
        local bp = GetBlueprint(self)
        local x, y, z = unpack(GetPosition(self))
        local fx = x - bp.Footprint.SizeX * 0.5
        local fz = z - bp.Footprint.SizeZ * 0.5
        local sx = fx + bp.Physics.SkirtOffsetX
        local sz = fz + bp.Physics.SkirtOffsetZ
        return sx, sz, sx + bp.Physics.SkirtSizeX, sz + bp.Physics.SkirtSizeZ
    end,

    CreateTarmac = function(self, albedo, normal, glow, orientation, specTarmac, lifeTime)
        if self:GetCurrentLayer() ~= 'Land' then return end
        local tarmac
        local bp = self:GetBlueprint().Display.Tarmacs
        if not specTarmac then
            if bp and table.getn(bp) > 0 then
                local num = Random(1, table.getn(bp))
                tarmac = bp[num]
            else
                return false
            end
        else
            tarmac = specTarmac
        end

        local army = self:GetArmy()
        local w = tarmac.Width
        local l = tarmac.Length
        local fadeout = tarmac.FadeOut

        local x, y, z = unpack(self:GetCachePosition())

        -- I'm disabling this for now since there are so many things wrong with it
        local orient = orientation
        if not orientation then
            if tarmac.Orientations and table.getn(tarmac.Orientations) > 0 then
                orient = tarmac.Orientations[Random(1, table.getn(tarmac.Orientations))]
                orient = (0.01745 * orient)
            else
                orient = 0
            end
        end

        if not self.TarmacBag then
            self.TarmacBag = {
                Decals = {},
                Orientation = orient,
                CurrentBP = tarmac,
            }
        end

        local GetTarmac = import('/lua/tarmacs.lua').GetTarmacType

        local terrain = GetTerrainType(x, z)
        local terrainName
        if terrain then
            terrainName = terrain.Name
        end

        -- Players and AI can build buildings outside of their faction. Get the *building's* faction to determine the correct tarrain-specific tarmac
        local factionTable = {e = 1, a = 2, r = 3, s = 4}
        local faction  = factionTable[string.sub(self:GetUnitId(), 2, 2)]
        if albedo and tarmac.Albedo then
            local albedo2 = tarmac.Albedo2
            if albedo2 then
                albedo2 = albedo2 .. GetTarmac(faction, terrain)
            end

            local tarmacHndl = CreateDecal(self:GetCachePosition(), orient, tarmac.Albedo .. GetTarmac(faction, terrainName) , albedo2 or '', 'Albedo', w, l, fadeout, lifeTime or 0, army, 0)
            table.insert(self.TarmacBag.Decals, tarmacHndl)
            if tarmac.RemoveWhenDead then
                self.Trash:Add(tarmacHndl)
            end
        end

        if normal and tarmac.Normal then
            local tarmacHndl = CreateDecal(self:GetCachePosition(), orient, tarmac.Normal .. GetTarmac(faction, terrainName), '', 'Alpha Normals', w, l, fadeout, lifeTime or 0, army, 0)

            table.insert(self.TarmacBag.Decals, tarmacHndl)
            if tarmac.RemoveWhenDead then
                self.Trash:Add(tarmacHndl)
            end
        end

        if glow and tarmac.Glow then
            local tarmacHndl = CreateDecal(self:GetCachePosition(), orient, tarmac.Glow .. GetTarmac(faction, terrainName), '', 'Glow', w, l, fadeout, lifeTime or 0, army, 0)

            table.insert(self.TarmacBag.Decals, tarmacHndl)
            if tarmac.RemoveWhenDead then
                self.Trash:Add(tarmacHndl)
            end
        end
    end,

    DestroyTarmac = function(self)
        if not self.TarmacBag then return end

        for k, v in self.TarmacBag.Decals do
            v:Destroy()
        end

        self.TarmacBag.Orientation = nil
        self.TarmacBag.CurrentBP = nil
    end,

    HasTarmac = function(self)
        if not self.TarmacBag then return false end
        return table.getn(self.TarmacBag.Decals) ~= 0
    end,

    OnMassStorageStateChange = function(self, state)
    end,

    OnEnergyStorageStateChange = function(self, state)
    end,

    CreateBlinkingLights = function(self, color)
        self:DestroyBlinkingLights()
        local bp = self:GetBlueprint().Display.BlinkingLights
        local bpEmitters = self:GetBlueprint().Display.BlinkingLightsFx
        if bp then
            local fxbp = bpEmitters[color]
            for _, v in bp do
                if type(v) == 'table' then
                    local fx = CreateAttachedEmitter(self, v.BLBone, self:GetArmy(), fxbp)
                    fx:OffsetEmitter(v.BLOffsetX or 0, v.BLOffsetY or 0, v.BLOffsetZ or 0)
                    fx:ScaleEmitter(v.BLScale or 1)
                    table.insert(self.FxBlinkingLightsBag, fx)
                    self.Trash:Add(fx)
                end
            end
        end
    end,

    DestroyBlinkingLights = function(self)
        for _, v in self.FxBlinkingLightsBag do
            v:Destroy()
        end
        self.FxBlinkingLightsBag = {}
    end,

    CreateDestructionEffects = function(self, overkillRatio)
        if explosion.GetAverageBoundingXZRadius(self) < 1.0 then
            explosion.CreateScalableUnitExplosion(self, overkillRatio)
        else
            explosion.CreateTimedStuctureUnitExplosion(self)
            WaitSeconds(0.5)
            explosion.CreateScalableUnitExplosion(self, overkillRatio)
        end
    end,

    -- Modified to use same upgrade logic as the ui. This adds more upgrade options via General.UpgradesFromBase blueprint option
    OnStartBuild = function(self, unitBeingBuilt, order)
        -- Check for death loop
        if not Unit.OnStartBuild(self, unitBeingBuilt, order) then
            return
        end
        self.UnitBeingBuilt = unitBeingBuilt

        local builderBp = self:GetBlueprint()
        local targetBp = unitBeingBuilt:GetBlueprint()
        local performUpgrade = false

        if targetBp.General.UpgradesFrom == builderBp.BlueprintId then
            performUpgrade = true
        elseif targetBp.General.UpgradesFrom == builderBp.General.UpgradesTo then
            performUpgrade = true
        elseif targetBp.General.UpgradesFromBase ~= "none" then
            -- Try testing against the base
            if targetBp.General.UpgradesFromBase == builderBp.BlueprintId then
                performUpgrade = true
            elseif targetBp.General.UpgradesFromBase == builderBp.General.UpgradesFromBase then
                performUpgrade = true
            end
        end

        if performUpgrade and order == 'Upgrade' then
            ChangeState(self, self.UpgradingState)
        end
     end,

    IdleState = State {
        Main = function(self)
        end,
    },

    UpgradingState = State {
        Main = function(self)
            self:StopRocking()
            local bp = self:GetBlueprint().Display
            self:DestroyTarmac()
            self:PlayUnitSound('UpgradeStart')
            self:DisableDefaultToggleCaps()
            if bp.AnimationUpgrade then
                local unitBuilding = self.UnitBeingBuilt
                self.AnimatorUpgradeManip = CreateAnimator(self)
                self.Trash:Add(self.AnimatorUpgradeManip)
                local fractionOfComplete = 0
                self:StartUpgradeEffects(unitBuilding)
                self.AnimatorUpgradeManip:PlayAnim(bp.AnimationUpgrade, false):SetRate(0)

                while fractionOfComplete < 1 and not self.Dead do
                    fractionOfComplete = unitBuilding:GetFractionComplete()
                    self.AnimatorUpgradeManip:SetAnimationFraction(fractionOfComplete)
                    WaitTicks(1)
                end

                if not self.Dead then
                    self.AnimatorUpgradeManip:SetRate(1)
                end
            end
        end,

        OnStopBuild = function(self, unitBuilding)
            Unit.OnStopBuild(self, unitBuilding)
            self:EnableDefaultToggleCaps()

            if unitBuilding:GetFractionComplete() == 1 then
                NotifyUpgrade(self, unitBuilding)
                self:StopUpgradeEffects(unitBuilding)
                self:PlayUnitSound('UpgradeEnd')
                self:Destroy()
            end
        end,

        OnFailedToBuild = function(self)
            Unit.OnFailedToBuild(self)
            self:EnableDefaultToggleCaps()

            if self.AnimatorUpgradeManip then self.AnimatorUpgradeManip:Destroy() end

            if self:GetCurrentLayer() == 'Water' then
                self:StartRocking()
            end
            self:PlayUnitSound('UpgradeFailed')
            self:PlayActiveAnimation()
            self:CreateTarmac(true, true, true, self.TarmacBag.Orientation, self.TarmacBag.CurrentBP)
            ChangeState(self, self.IdleState)
        end,
    },

    StartBeingBuiltEffects = function(self, builder, layer)
        Unit.StartBeingBuiltEffects(self, builder, layer)
        local bp = self:GetBlueprint()
        local FactionName = bp.General.FactionName

        if FactionName == 'UEF' then
            self:HideBone(0, true)
            self.BeingBuiltShowBoneTriggered = false
            if bp.General.UpgradesFrom ~= builder:GetUnitId() then
                self:ForkThread(EffectUtil.CreateBuildCubeThread, builder, self.OnBeingBuiltEffectsBag)
            end
        elseif FactionName == 'Aeon' then
            if bp.General.UpgradesFrom ~= builder:GetUnitId() then
                self:ForkThread(EffectUtil.CreateAeonBuildBaseThread, builder, self.OnBeingBuiltEffectsBag)
            end
        elseif FactionName == 'Seraphim' then
            if bp.General.UpgradesFrom ~= builder:GetUnitId() then
                self:ForkThread(EffectUtil.CreateSeraphimBuildBaseThread, builder, self.OnBeingBuiltEffectsBag)
            end
        end
    end,

    StopBeingBuiltEffects = function(self, builder, layer)
        local FactionName = self:GetBlueprint().General.FactionName
        if FactionName == 'Aeon' then
            WaitSeconds(2.0)
        elseif FactionName == 'UEF' and not self.BeingBuiltShowBoneTriggered then
            self:ShowBone(0, true)
            self:HideLandBones()
        end
        Unit.StopBeingBuiltEffects(self, builder, layer)
    end,

    StartBuildingEffects = function(self, unitBeingBuilt, order)
        Unit.StartBuildingEffects(self, unitBeingBuilt, order)
    end,

    StopBuildingEffects = function(self, unitBeingBuilt)
        Unit.StopBuildingEffects(self, unitBeingBuilt)
    end,

    StartUpgradeEffects = function(self, unitBeingBuilt)
        unitBeingBuilt:HideBone(0, true)
    end,

    StopUpgradeEffects = function(self, unitBeingBuilt)
        unitBeingBuilt:ShowBone(0, true)
    end,

    PlayActiveAnimation = function(self)

    end,

    -- Adding into OnDestroy the ability to destroy the tarmac but put a new one down that looks exactly like it but
    -- will time out over the time spec'd or 300 seconds.
    OnDestroy = function(self)
        Unit.OnDestroy(self)
        local orient = self.TarmacBag.Orientation
        local currentBP = self.TarmacBag.CurrentBP
        self:DestroyTarmac()
        self:CreateTarmac(true, true, true, orient, currentBP, currentBP.DeathLifetime or 300)
    end,

    OnKilled = function(self, instigator, type, overkillRatio)
        local scus = EntityCategoryFilterDown(categories.SUBCOMMANDER, self:GetGuards())
        if scus[1] then
            for _, u in scus do
                u:SetFocusEntity(self)
                self.Repairers[u:GetEntityId()] = u
            end
        end

        Unit.OnKilled(self, instigator, type, overkillRatio)
    end,

    CheckRepairersForRebuild = function(self, wreckage)
        local units = {}
        for id, u in self.Repairers do
            if u:BeenDestroyed() then
                self.Repairers[id] = nil
            else
                local focus = u:GetFocusUnit()
                if focus == self and ((u:IsUnitState('Repairing') and not u:GetGuardedUnit()) or
                                      EntityCategoryContains(categories.SUBCOMMANDER, u)) then
                    table.insert(units, u)
                end
            end
        end

        if not units[1] then return end

        wreckage:Rebuild(units)
    end,

    CreateWreckage = function(self, overkillRatio)
        local wreckage = Unit.CreateWreckage(self, overkillRatio)
        if wreckage then
            self:CheckRepairersForRebuild(wreckage)
        end

        return wreckage
    end,

    -- Adjacency
    -- When we're adjacent, try to apply all the possible bonuses
    OnAdjacentTo = function(self, adjacentUnit, triggerUnit) -- What is triggerUnit?
        if self:IsBeingBuilt() then return end
        if adjacentUnit:IsBeingBuilt() then return end

        -- Does the unit have any adjacency buffs to use?
        local adjBuffs = self:GetBlueprint().Adjacency
        if not adjBuffs then return end

        -- Apply each buff needed to you and/or adjacent unit
        for k, v in AdjacencyBuffs[adjBuffs] do
            Buff.ApplyBuff(adjacentUnit, v, self)
        end

        -- Keep track of adjacent units
        if not self.AdjacentUnits then
            self.AdjacentUnits = {}
        end
        table.insert(self.AdjacentUnits, adjacentUnit)

        self:RequestRefreshUI()
        adjacentUnit:RequestRefreshUI()
     end,

    -- When we're not adjacent, try to remove all the possible bonuses
    OnNotAdjacentTo = function(self, adjacentUnit)
        if not self.AdjacentUnits then
            WARN("Precondition Failed: No AdjacentUnits registered for entity: " .. repr(self.GetEntityId))
            return
        end

        local adjBuffs = self:GetBlueprint().Adjacency

        if adjBuffs and AdjacencyBuffs[adjBuffs] then
            for k, v in AdjacencyBuffs[adjBuffs] do
                if Buff.HasBuff(adjacentUnit, v) then
                    Buff.RemoveBuff(adjacentUnit, v)
                end
            end
        end
        self:DestroyAdjacentEffects()

        -- Keep track of units losing adjacent structures
        for k, u in self.AdjacentUnits do
            if u == adjacentUnit then
                table.remove(self.AdjacentUnits, k)
                adjacentUnit:RequestRefreshUI()
            end
        end
        self:RequestRefreshUI()
    end,

    -- Add/Remove Adjacency Functionality
    -- Applies all appropriate buffs to all adjacent units
    ApplyAdjacencyBuffs = function(self)
        local adjBuffs = self:GetBlueprint().Adjacency
        if not adjBuffs then return end

        -- There won't be any adjacentUnit if this is a producer just built...
        if self.AdjacentUnits then
            for k, adjacentUnit in self.AdjacentUnits do
                for k, v in AdjacencyBuffs[adjBuffs] do
                    Buff.ApplyBuff(adjacentUnit, v, self)
                    adjacentUnit:RequestRefreshUI()
                end
            end
            self:RequestRefreshUI()
        end
    end,

    -- Removes all appropriate buffs from all adjacent units
    RemoveAdjacencyBuffs = function(self)
        local adjBuffs = self:GetBlueprint().Adjacency
        if not adjBuffs then return end

        if self.AdjacentUnits then
            for k, adjacentUnit in self.AdjacentUnits do
                for key, v in AdjacencyBuffs[adjBuffs] do
                    if Buff.HasBuff(adjacentUnit, v) then
                        Buff.RemoveBuff(adjacentUnit, v, false, self)
                        adjacentUnit:RequestRefreshUI()
                    end
                end
            end
            self:RequestRefreshUI()
        end
    end,

    -- Add/Remove Adjacency Effects
    CreateAdjacentEffect = function(self, adjacentUnit)
        -- Create trashbag to hold all these entities and beams
        if not self.AdjacencyBeamsBag then
            self.AdjacencyBeamsBag = {}
        end

        for k, v in self.AdjacencyBeamsBag do
            if v.Unit:GetEntityId() == adjacentUnit:GetEntityId() then
                return
            end
        end
        self:ForkThread(EffectUtil.CreateAdjacencyBeams, adjacentUnit, self.AdjacencyBeamsBag)
    end,

    DestroyAdjacentEffects = function(self, adjacentUnit)
        if not self.AdjacencyBeamsBag then return end

        for k, v in self.AdjacencyBeamsBag do
            if v.Unit:BeenDestroyed() or v.Unit.Dead then
                v.Trash:Destroy()
                self.AdjacencyBeamsBag[k] = nil
            end
        end
    end,
    
    DoTakeDamage = function(self, instigator, amount, vector, damageType)
	    -- Handle incoming OC damage
        if damageType == 'Overcharge' then
            local wep = instigator:GetWeaponByLabel('OverCharge')
            amount = wep:GetBlueprint().Overcharge.structureDamage
        end
        Unit.DoTakeDamage(self, instigator, amount, vector, damageType)
    end,
}