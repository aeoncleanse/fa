-----------------------------------------------------------------
-- File     :  /cdimage/units/UAL0401/UAL0401_script.lua
-- Author(s):  John Comes, Gordon Duclos
-- Summary  :  Aeon Galactic Colossus Script
-- Copyright © 2005 Gas Powered Games, Inc.  All rights reserved.
-----------------------------------------------------------------

local AWalkingLandUnit = import('/lua/aeonunits.lua').AWalkingLandUnit
local WeaponsFile = import ('/lua/aeonweapons.lua')
local ADFPhasonLaser = WeaponsFile.ADFPhasonLaser
local ADFTractorClaw = WeaponsFile.ADFTractorClaw
local utilities = import('/lua/utilities.lua')
local explosion = import('/lua/defaultexplosions.lua')
local CreateUnitDestructionDebris = import('/lua/EffectUtilities.lua').CreateUnitDestructionDebris
local CreateDefaultHitExplosionAtBone = explosion.CreateDefaultHitExplosionAtBone

UAL0401 = Class(AWalkingLandUnit) {
    Weapons = {
        EyeWeapon = Class(ADFPhasonLaser) {},
        RightArmTractor = Class(ADFTractorClaw) {},
        LeftArmTractor = Class(ADFTractorClaw) {},
    },

    OnKilled = function(self, instigator, type, overkillRatio)
        AWalkingLandUnit.OnKilled(self, instigator, type, overkillRatio)

        local wep = self:GetWeaponByLabel('EyeWeapon')
        local bp = wep:GetBlueprint()
        if bp.Audio.BeamStop then
            wep:PlaySound(bp.Audio.BeamStop)
        end

        if bp.Audio.BeamLoop and wep.Beams[1].Beam then
            wep.Beams[1].Beam:SetAmbientSound(nil, nil)
        end

        for k, v in wep.Beams do
            v.Beam:Disable()
        end
    end,

    DeathThread = function(self, overkillRatio , instigator)
		self:PlayUnitSound('Destroyed')

        CreateDefaultHitExplosionAtBone(self, 'Torso', 4.0)
        explosion.CreateDebrisProjectiles(self, explosion.GetAverageBoundingXYZRadius(self), {self:GetUnitSizes()})
        WaitSeconds(2)

        CreateDefaultHitExplosionAtBone(self, 'Right_Leg_B02', 1.0)
        WaitSeconds(0.1)

        CreateDefaultHitExplosionAtBone(self, 'Right_Leg_B01', 1.0)
        WaitSeconds(0.1)

        CreateDefaultHitExplosionAtBone(self, 'Left_Arm_B02', 1.0)
        WaitSeconds(0.3)

        CreateDefaultHitExplosionAtBone(self, 'Right_Arm_B01', 1.0)
        CreateDefaultHitExplosionAtBone(self, 'Right_Leg_B01', 1.0)
        WaitSeconds(3.5)

        CreateDefaultHitExplosionAtBone(self, 'Torso', 5.0)

        if self.DeathAnimManip then
            WaitFor(self.DeathAnimManip)
        end

        local bpWep = self:GetBlueprint().Weapon
        for i, numWeapons in bpWep do
            local wep = bpWep[i]
            if wep.Label == 'CollossusDeath' then
                DamageArea(self, self:GetPosition(), wep.DamageRadius, wep.Damage, wep.DamageType, wep.DamageFriendly)
                break
            end
        end

        self:DestroyAllDamageEffects()
        self:CreateWreckage(overkillRatio)

        -- CURRENTLY DISABLED UNTIL DESTRUCTION
        -- Create destruction debris out of the mesh, currently these projectiles look like crap,
        -- since projectile rotation and terrain collision doesn't work that great. These are left in
        -- hopes that this will look better in the future.. =)
        if self.ShowUnitDestructionDebris and overkillRatio then
            if overkillRatio <= 1 then
                CreateUnitDestructionDebris(self, true, true, false)
            elseif overkillRatio <= 2 then
                CreateUnitDestructionDebris(self, true, true, false)
            elseif overkillRatio <= 3 then
                CreateUnitDestructionDebris(self, true, true, true)
            else -- Vaporized
                self.CreateUnitDestructionDebris(self, true, true, true)
            end
        end

        self:Destroy()
    end,
}

TypeClass = UAL0401
