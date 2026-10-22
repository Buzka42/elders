local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.Spells = {
  -- role signatures: casting these suggests the role
  heal = {
    PRIEST   = { 2050, 2054, 2061, 1004 },   -- Lesser Heal, Heal, Flash Heal, Renew
    PALADIN  = { 635, 19750 },               -- Holy Light, Flash of Light
    SHAMAN   = { 331, 8004, 1064 },          -- Healing Wave, Lesser Healing Wave, Chain Heal
    DRUID    = { 5185, 774, 8936 },          -- Healing Touch, Rejuvenation, Regrowth
  },
  tank = {
    WARRIOR  = { 71, 355, 7386, 2565, 6572 },  -- Defensive Stance, Taunt, Sunder Armor, Shield Block, Revenge
    DRUID    = { 5487, 6795, 6807 },           -- Bear Form, Growl, Maul
    PALADIN  = { 25780 },                      -- Righteous Fury
  },
  interrupt = {
    WARRIOR  = { 6552, 72 },                   -- Pummel, Shield Bash
    ROGUE    = { 1766 },                       -- Kick
    MAGE     = { 2139 },                       -- Counterspell
    SHAMAN   = { 8042 },                       -- Earth Shock
  },
  dispel = {
    PRIEST   = { 527, 528 },                   -- Dispel Magic, Cure Disease
    PALADIN  = { 4987, 1152, 552, 2893 },      -- Cleanse, Purify, Abolish Disease, Abolish Poison
    SHAMAN   = { 370, 526 },                   -- Purge, Cure Toxins ?
    DRUID    = { 2782, 8946 },                 -- Remove Curse, Cure Poison
    MAGE     = { 475 },                        -- Remove Lesser Curse ?
    WARLOCK  = { 19505 },                      -- Devour Magic (Felhunter pet)
  },
  cc = {
    MAGE     = { 118, 122 },                   -- Polymorph, Frost Nova
    ROGUE    = { 6770, 1776, 2094, 408, 1833 },-- Sap, Gouge, Blind, Kidney Shot, Cheap Shot
    WARLOCK  = { 5782, 5484, 6358 },           -- Fear, Howl of Terror, Seduction
    PRIEST   = { 8122, 605 },                  -- Psychic Scream, Mind Control
    HUNTER   = { 2637, 339, 1499, 19503 },    -- Hibernate, Entangling Roots, Freezing Trap, Scatter Shot
    PALADIN  = { 853, 20066, 9484, 710 },     -- Hammer of Justice, Repentance ?, Shackle Undead, Banish
    WARRIOR  = { 5246 },                       -- Intimidating Shout
  },
  taunt = {
    WARRIOR  = { 355, 1161 },                  -- Taunt, Challenging Shout
    DRUID    = { 6795, 5209 },                 -- Growl, Challenging Roar
  },
  hearthstone = 8690,
  mounts_note = "use IsMounted()",
}
