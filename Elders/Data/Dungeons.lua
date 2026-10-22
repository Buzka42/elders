local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.Dungeons = {
  -- Sources: instanceID = warcraft.wiki.gg/wiki/InstanceID (Classic/Dungeons lists), ID verified by fetch.
  -- Boss IDs: wowhead.com/classic/npc=ID fetch (verified) unless noted. Level ranges: general Classic consensus (medium).
  -- ENCOUNTER ids: not verified for any row (all unknown).
  [389] = { name = "Ragefire Chasm", min = 13, max = 18, finalBoss = { 11520 }, finalBossNames = { "Taragaman the Hungerer" }, -- Taragaman the Hungerer. Source: wowhead classic npc=11520 (verified). Confidence: high. ENCOUNTER: ?
  },
  [43] = { name = "Wailing Caverns", min = 15, max = 25, finalBoss = { 3654 }, finalBossNames = { "Mutanus the Devourer" }, -- Mutanus the Devourer. Source: wowhead classic npc=3654 (verified). Confidence: high. ENCOUNTER: ?
  },
  [36] = { name = "The Deadmines", min = 10, max = 20, finalBoss = { 639 }, finalBossNames = { "Edwin VanCleef" }, -- Edwin VanCleef. Source: wowhead classic npc=639 (verified). Confidence: high. ENCOUNTER: ?
  },
  [33] = { name = "Shadowfang Keep", min = 18, max = 26, finalBoss = { 4275 }, finalBossNames = { "Archmage Arugal" }, -- Archmage Arugal. Source: wowhead classic npc=4275 (verified). Confidence: high. ENCOUNTER: ?
  },
  [48] = { name = "Blackfathom Deeps", min = 20, max = 30, finalBoss = {}, finalBossNames = { "Aku'mai" }, -- Aku'mai (final). Aku'mai NPC ID NOT verified (wowhead npc=4830 is Old Serra'kis, a non-final boss). Confidence: low on ID. Fill in finalBoss. ENCOUNTER: ?
  },
  [34] = { name = "The Stockade", min = 22, max = 30, finalBoss = {}, finalBossNames = { "Bazil Thredd" }, -- Bazil Thredd (final). NPC ID NOT verified (npc=4017 is Wily Fey Dragon, not him). Confidence: low on ID. ENCOUNTER: ?
  },
  [90] = { name = "Gnomeregan", min = 24, max = 33, finalBoss = { 7800 }, finalBossNames = { "Mekgineer Thermaplugg" }, -- Mekgineer Thermaplugg. Source: wowhead classic npc=7800 (verified). Confidence: high. ENCOUNTER: ?
  },
  [47] = { name = "Razorfen Kraul", min = 25, max = 35, finalBoss = { 4421 }, finalBossNames = { "Charlga Razorflank" }, -- Charlga Razorflank. Source: wowhead classic npc=4421 (verified). Confidence: high. ENCOUNTER: ?
  },
  [189] = { name = "Scarlet Monastery", min = 28, max = 45, finalBoss = { 4543, 6487, 3975, 3977 }, finalBossNames = { "Bloodmage Thalnos", "Arcanist Doan", "Herod", "High Inquisitor Whitemane" }, -- Wing finals: Graveyard Bloodmage Thalnos 4543; Library Arcanist Doan 6487; Armory Herod 3975; Cathedral High Inquisitor Whitemane 3977. All verified via wowhead npc pages. InstanceID 189 (Complete list); 1004 also appears on the Dungeons list. Confidence: high for IDs, medium for level range. ENCOUNTER: ?
  },
  [129] = { name = "Razorfen Downs", min = 35, max = 45, finalBoss = { 7358 }, finalBossNames = { "Amnennar the Coldbringer" }, -- Amnennar the Coldbringer. Source: wowhead classic npc=7358 (verified). Confidence: high. ENCOUNTER: ?
  },
  [70] = { name = "Uldaman", min = 35, max = 45, finalBoss = { 2748 }, finalBossNames = { "Archaedas" }, -- Archaedas. Source: wowhead classic npc=2748 (verified). Confidence: high. ENCOUNTER: ?
  },
  [209] = { name = "Zul'Farrak", min = 44, max = 54, finalBoss = { 7267 }, finalBossNames = { "Chief Ukorz Sandscalp" }, -- Chief Ukorz Sandscalp. Source: wowhead classic npc=7267 (verified). Confidence: high. ENCOUNTER: ?
  },
  [349] = { name = "Maraudon", min = 45, max = 55, finalBoss = { 12201 }, finalBossNames = { "Princess Theradras" }, -- Princess Theradras. ID 12201 from wowclassicdb.com (not Wowhead; wowhead npc=13680 returned 404). Confidence: medium. ENCOUNTER: ?
  },
  [109] = { name = "The Temple of Atal'Hakkar", min = 50, max = 60, finalBoss = { 8443 }, finalBossNames = { "Shade of Eranikus", "Avatar of Hakkar" }, -- Avatar of Hakkar. Source: wowhead classic npc=8443 (verified). Confidence: high. ENCOUNTER: ?
  },
  [230] = { name = "Blackrock Depths", min = 52, max = 60, finalBoss = { 9019 }, finalBossNames = { "Emperor Dagran Thaurissan" }, -- Emperor Dagran Thaurissan. Source: wowhead classic npc=9019 (verified). Confidence: high. ENCOUNTER: ?
  },
  [229] = { name = "Blackrock Spire", min = 55, max = 60, finalBoss = { 9568, 10363 }, finalBossNames = { "Overlord Wyrmthalak", "General Drakkisath" }, -- Lower BRS final: Overlord Wyrmthalak 9568 (wowhead verified); Upper BRS final: General Drakkisath 10363 (wowhead verified). Both wings share instanceID 229 in Classic (1358 is the Warlords-era UBRS ID, not used). Confidence: high for IDs. ENCOUNTER: ?
  },
  [429] = { name = "Dire Maul", min = 55, max = 60, finalBoss = { 11492, 11486, 11501 }, finalBossNames = { "Alzzin the Wildshaper", "Prince Tortheldrin", "King Gordok" }, -- Wing finals: East Alzzin the Wildshaper 11492 (wowhead verified as Alzzin; wing assignment medium); West Prince Tortheldrin 11486 (wowhead verified as Tortheldrin; wing assignment medium); North King Gordok 11501 (ID from wowclassicdb.com, not Wowhead). Confidence: medium. ENCOUNTER: ?
  },
  [329] = { name = "Stratholme", min = 55, max = 60, finalBoss = { 10440 }, finalBossNames = { "Baron Rivendare", "Balnazzar" }, -- Live (Dathrohan/Balnazzar) ID NOT verified (npc=10435 is Magistrate Barthilas; not usable). Undead final: Baron Rivendare 10440 (wowhead verified). Add the live-side ID when known. Confidence: high for 10440, low for live side. ENCOUNTER: ?
  },
  [289] = { name = "Scholomance", min = 58, max = 60, finalBoss = { 1853 }, finalBossNames = { "Darkmaster Gandling" }, -- Darkmaster Gandling. Source: wowhead classic npc=1853 (verified). Confidence: high. ENCOUNTER: ?
  },
}
