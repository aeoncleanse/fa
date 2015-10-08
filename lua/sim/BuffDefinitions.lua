-----------------------------------------------------------------
-- File     :  /lua/sim/buffdefinition.lua
-- Copyright © 2008 Gas Powered Games, Inc.  All rights reserved.
-----------------------------------------------------------------

import('/lua/sim/AdjacencyBuffs.lua')
import('/lua/sim/CheatBuffs.lua') -- Buffs for AI Cheating

-- Table of multipliers used by the mass-driven veterancy system
MultsTable = {
    VETERANCYREGEN = {
        TECH1 = 0.006,
        TECH2 = 0.003,
        TECH3 = 0.0007,
        EXPERIMENTAL = 0.0005,
        COMMAND = 0.00025,
    },
    VETERANCYREGENBOOST = {
        TECH1 = 0.01,
        TECH2 = 0.01,
        TECH3 = 0.01,
        EXPERIMENTAL = 0.01,
        COMMAND = 0.01,
    },
    VETERANCYMAXHEALTH = {
        TECH1 = 1.2,
        TECH2 = 1.2,
        TECH3 = 1.2,
        EXPERIMENTAL = 1.2,
        COMMAND = 1.2,
    },
}

-- VETERANCY BUFFS - UNIT MAX HEALTH ONLY
BuffBlueprint {
    Name = 'VeterancyMaxHealth1',
    DisplayName = 'VeterancyMaxHealth1',
    BuffType = 'VETERANCYHEALTH',
    Stacks = 'REPLACE',
    Duration = -1,
    Affects = {
        MaxHealth = {
            DoNotFill = true,
            Add = 0,
            Mult = 1.1,
        },
    },
}

BuffBlueprint {
    Name = 'VeterancyMaxHealth2',
    DisplayName = 'VeterancyMaxHealth2',
    BuffType = 'VETERANCYHEALTH',
    Stacks = 'REPLACE',
    Duration = -1,
    Affects = {
        MaxHealth = {
            DoNotFill = true,
            Add = 0,
            Mult = 1.2,
        },
    },
}

BuffBlueprint {
    Name = 'VeterancyMaxHealth3',
    DisplayName = 'VeterancyMaxHealth3',
    BuffType = 'VETERANCYHEALTH',
    Stacks = 'REPLACE',
    Duration = -1,
    Affects = {
        MaxHealth = {
            DoNotFill = true,
            Add = 0,
            Mult = 1.3,
        },
    },
}

BuffBlueprint {
    Name = 'VeterancyMaxHealth4',
    DisplayName = 'VeterancyMaxHealth4',
    BuffType = 'VETERANCYHEALTH',
    Stacks = 'REPLACE',
    Duration = -1,
    Affects = {
        MaxHealth = {
			DoNotFill = true,
            Add = 0,
            Mult = 1.4,
        },
    },
}

BuffBlueprint {
    Name = 'VeterancyMaxHealth5',
    DisplayName = 'VeterancyMaxHealth5',
    BuffType = 'VETERANCYHEALTH',
    Stacks = 'REPLACE',
    Duration = -1,
    Affects = {
        MaxHealth = {
            DoNotFill = true,
            Add = 0,
            Mult = 1.5,
        },
    },
}

-- VETERANCY BUFFS - UNIT REGEN
BuffBlueprint {
    Name = 'VeterancyRegen1',
    DisplayName = 'VeterancyRegen1',
    BuffType = 'VETERANCYREGEN',
    Stacks = 'REPLACE',
    Duration = -1,
    Affects = {
        Regen = {
            Add = 2,
            Mult = 1,
        },
    },
}

BuffBlueprint {
    Name = 'VeterancyRegen2',
    DisplayName = 'VeterancyRegen2',
    BuffType = 'VETERANCYREGEN',
    Stacks = 'REPLACE',
    Duration = -1,
    Affects = {
        Regen = {
            Add = 4,
            Mult = 1,
        },
    },
}

BuffBlueprint {
    Name = 'VeterancyRegen3',
    DisplayName = 'VeterancyRegen3',
    BuffType = 'VETERANCYREGEN',
    Stacks = 'REPLACE',
    Duration = -1,
    Affects = {
        Regen = {
            Add = 6,
            Mult = 1,
        },
    },
}

BuffBlueprint {
    Name = 'VeterancyRegen4',
    DisplayName = 'VeterancyRegen4',
    BuffType = 'VETERANCYREGEN',
    Stacks = 'REPLACE',
    Duration = -1,
    Affects = {
        Regen = {
            Add = 8,
            Mult = 1,
        },
    },
}

BuffBlueprint {
    Name = 'VeterancyRegen5',
    DisplayName = 'VeterancyRegen5',
    BuffType = 'VETERANCYREGEN',
    Stacks = 'REPLACE',
    Duration = -1,
    Affects = {
        Regen = {
            Add = 10,
            Mult = 1,
        },
    },
}

__moduleinfo.auto_reload = true
