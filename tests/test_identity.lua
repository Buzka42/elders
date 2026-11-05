-- Player identity: WoW Forever puts a 2-part character's surname in UnitFullName's realm slot.
local T = dofile(os.getenv("WOW_STUB") or "tests/wow_stub.lua")
for _, f in ipairs({ "MetaKit", "Safe", "Addon", "DB", "Outbox", "Codec", "Comm" }) do dofile("MetaKit/" .. f .. ".lua") end
local MK = MetaKit

local stubFull, stubNorm, stubLabel = UnitFullName, GetNormalizedRealmName, GetRealmName
local function as(first, slot, norm, label)
  UnitFullName = function(u) if u == "player" then return first, slot end return stubFull(u) end
  GetNormalizedRealmName = function() return norm end
  GetRealmName = function() return label end
end
local function restore() UnitFullName, GetNormalizedRealmName, GetRealmName = stubFull, stubNorm, stubLabel end

local NORM, LABEL = "CAMWOWEU4Realm2PvP", "CAMWOW EU4 Realm 2 PvP"

T.test("surname in realm slot joins the name; realm comes from the realm API", function()
  as("Chad", "Gippity", NORM, LABEL)
  local key, name, realm = MK.PlayerKey()
  T.eq(key, "Chad Gippity-" .. NORM); T.eq(name, "Chad Gippity"); T.eq(realm, NORM)
  T.eq(MK.CommKey(), "Chad-Gippity")
  T.ok(MK.IsSelf("Chad-Gippity")); T.ok(MK.IsSelf("Chad Gippity-" .. NORM)); T.eq(MK.IsSelf("Bob-Gippity"), false)
  T.eq(MK.FullName("Bob"), "Bob-" .. NORM)
  restore()
end)

T.test("true realm in the slot keeps Name-Realm (normalized, label or spacing variants)", function()
  for _, slot in ipairs({ NORM, LABEL, "CAMWOWEU4 Realm2PvP" }) do
    as("Bob", slot, NORM, LABEL)
    local key, name, realm = MK.PlayerKey()
    T.eq(key, "Bob-" .. slot); T.eq(name, "Bob"); T.eq(realm, slot)
    T.eq(MK.CommKey(), key)
  end
  as("Bob", "Normal", nil, "Normal") -- only the label readable
  T.eq((MK.PlayerKey()), "Bob-Normal")
  restore()
end)

T.test("realmless: slot empty or nil falls back to the realm APIs", function()
  for _, slot in ipairs({ "", false }) do
    as("Solo", slot or nil, NORM, LABEL)
    local key, name, realm = MK.PlayerKey()
    T.eq(key, "Solo-" .. NORM); T.eq(name, "Solo"); T.eq(realm, NORM)
  end
  restore()
end)

T.test("fallbacks: unreadable realm APIs never reinterpret the slot; Unknown/Realm defaults", function()
  as("Chad", "Gippity", nil, nil)
  local key, name, realm, resolved = MK.PlayerKey()
  T.eq(key, "Chad-Gippity"); T.eq(name, "Chad"); T.eq(realm, "Realm"); T.eq(resolved, false) -- slot is never a realm
  T.eq(MK.CommKey(), "Chad-Gippity"); T.ok(MK.IsSelf("Chad-Gippity"))
  T.eq(MK.FullName("Bob"), "Bob-Gippity") -- peers still named the way WoW names them
  as(nil, nil, nil, nil)
  local stubName = UnitName
  UnitName = function() return nil end
  local key, name, realm = MK.PlayerKey()
  T.eq(key, "Unknown-Realm"); T.eq(name, "Unknown"); T.eq(realm, "Realm")
  UnitName = function(u) if u == "player" then return "Chad" end end
  T.eq((MK.PlayerKey()), "Chad-Realm")
  UnitName = stubName
  restore()
end)

T.test("Char migrates the pre-fix record to the new key and stores the joined name", function()
  as("Chad", "Gippity", NORM, LABEL)
  local A = MK.NewAddon("IdentTest")
  _G.IdentDB = { chars = { ["Chad-Gippity"] = { id = "abc", created = 1, name = "Chad", realm = "Gippity" } } }
  A:InitDB("IdentDB", { chars = {} }, nil, {})
  local c, key = A:Char()
  T.eq(key, "Chad Gippity-" .. NORM)
  T.eq(c.id, "abc"); T.eq(c.name, "Chad Gippity"); T.eq(c.realm, NORM)
  T.eq(A.db.chars["Chad-Gippity"], nil)
  T.eq(A.charKey, key)
  -- an existing new-key record is never overwritten by a stale old one
  A.db.chars["Chad-Gippity"] = { id = "old" }
  local c2 = A:Char()
  T.eq(c2.id, "abc"); T.ok(A.db.chars["Chad-Gippity"])
  restore()
end)

local function freshAddon(name, chars)
  local A = MK.NewAddon(name)
  _G[name .. "DB"] = { chars = chars or {} }
  A:InitDB(name .. "DB", { chars = {} }, nil, {})
  return A
end

T.test("Char never bakes an unresolved identity into an existing record", function()
  as("Chad", "Gippity", NORM, LABEL)
  local A = freshAddon("IdentKeep", { ["Chad Gippity-" .. NORM] = { id = "abc", name = "Chad Gippity", realm = NORM, comm = "Chad-Gippity" } })
  as("Chad", "Gippity", nil, nil) -- realm APIs unreadable (load time / secret scrub)
  local c, key = A:Char()
  T.eq(key, "Chad Gippity-" .. NORM); T.eq(c.id, "abc"); T.eq(c.name, "Chad Gippity"); T.eq(c.realm, NORM)
  T.eq(A.db.chars["Chad-Gippity"], nil)
  -- legacy record without a saved comm form is still found by its joined name
  A = freshAddon("IdentLegacy", { ["Chad Gippity-" .. NORM] = { id = "leg", name = "Chad Gippity", realm = NORM } })
  c, key = A:Char()
  T.eq(key, "Chad Gippity-" .. NORM); T.eq(c.id, "leg"); T.eq(c.realm, NORM)
  -- two candidates: no guessing, a placeholder under the comm key instead
  A = freshAddon("IdentAmbig", { a = { id = "a", name = "Chad Gippity", realm = "R1" }, b = { id = "b", name = "Chad Gippity", realm = "R2" } })
  c, key = A:Char()
  T.eq(key, "Chad-Gippity"); T.ok(c.id ~= "a" and c.id ~= "b")
  restore()
end)

T.test("load-time nil then readable: placeholder record migrates and is corrected", function()
  as("Chad", "Gippity", nil, nil)
  local A = freshAddon("IdentSeq")
  local c, key = A:Char()
  T.eq(key, "Chad-Gippity"); T.eq(c.name, "Chad"); T.eq(c.realm, nil); T.eq(c.unresolved, true)
  local id = c.id
  c = A:Char() -- still unresolved: same record, nothing rewritten
  T.eq(c.id, id); T.eq(c.realm, nil)
  as("Chad", "Gippity", NORM, LABEL)
  c, key = A:Char()
  T.eq(key, "Chad Gippity-" .. NORM); T.eq(c.id, id); T.eq(c.name, "Chad Gippity"); T.eq(c.realm, NORM)
  T.eq(c.comm, "Chad-Gippity"); T.eq(c.unresolved, nil); T.eq(A.db.chars["Chad-Gippity"], nil)
  as("Chad", "Gippity", nil, nil) -- APIs blink out again: stays on the resolved record, untouched
  c, key = A:Char()
  T.eq(key, "Chad Gippity-" .. NORM); T.eq(c.name, "Chad Gippity"); T.eq(c.realm, NORM)
  -- the live SV shape (baked old form) is corrected on the first resolved call
  as("Chad", "Gippity", nil, nil)
  A = freshAddon("IdentLive", { ["Chad-Gippity"] = { id = "live", name = "Chad", realm = "Gippity" } })
  c, key = A:Char()
  T.eq(key, "Chad-Gippity"); T.eq(c.id, "live"); T.eq(c.realm, "Gippity") -- not rewritten while unresolved
  as("Chad", "Gippity", NORM, LABEL)
  c, key = A:Char()
  T.eq(key, "Chad Gippity-" .. NORM); T.eq(c.id, "live"); T.eq(c.name, "Chad Gippity"); T.eq(c.realm, NORM)
  T.eq(A.db.chars["Chad-Gippity"], nil)
  restore()
end)

T.test("Char: true realm and realmless characters keep Name-Realm records", function()
  as("Bob", "Normal", "Normal", "Normal")
  local A = freshAddon("IdentTrue")
  local c, key = A:Char()
  T.eq(key, "Bob-Normal"); T.eq(c.name, "Bob"); T.eq(c.realm, "Normal")
  as("Bob", "Normal", nil, nil)
  c, key = A:Char()
  T.eq(key, "Bob-Normal"); T.eq(c.realm, "Normal")
  as("Solo", nil, NORM, LABEL)
  A = freshAddon("IdentSolo")
  c, key = A:Char()
  T.eq(key, "Solo-" .. NORM); T.eq(c.name, "Solo"); T.eq(c.realm, NORM)
  restore()
end)

T.test("Elders: unresolved at PLAYER_LOGIN, resolved at PLAYER_ENTERING_WORLD migrates + corrects", function()
  as("Chad", "Gippity", nil, nil) -- loading screen: realm APIs unreadable
  local saved = { chars = { ["Chad-Gippity"] = { id = "live", name = "Chad", realm = "Gippity", level = 12,
    brackets = { [2] = { sec = 99 } }, levels = {}, played = {} } } }
  local ns = T.LoadAddon("Elders/Elders.toc", { saved = { EldersDB = saved }, login = false })
  T.Fire("PLAYER_LOGIN")
  local A = ns.A
  T.eq(A.charKey, "Chad-Gippity"); T.eq(ns.char.id, "live"); T.eq(ns.char.realm, "Gippity") -- untouched while unresolved
  as("Chad", "Gippity", NORM, LABEL) -- world loaded: realm APIs readable
  T.Fire("PLAYER_ENTERING_WORLD", true, false)
  local key = "Chad Gippity-" .. NORM
  T.eq(A.charKey, key); T.ok(ns.char == A.db.chars[key]); T.eq(A.db.chars["Chad-Gippity"], nil)
  T.eq(ns.char.id, "live"); T.eq(ns.char.name, "Chad Gippity"); T.eq(ns.char.realm, NORM); T.eq(ns.char.comm, "Chad-Gippity")
  T.eq(ns.char.brackets[2].sec, 99) -- data carried over
  T.eq(MK.CommKey(), "Chad-Gippity"); T.ok(MK.IsSelf("Chad-Gippity"))
  ns.Agg.Add("kills", 1) -- collectors now write to the resolved record
  local _, b = ns.Agg.Bracket()
  T.eq(A.db.chars[key].brackets[b].kills, 1)
  as("Chad", "Gippity", nil, nil) -- a later loading screen with unreadable APIs keeps the resolved record
  T.Fire("PLAYER_ENTERING_WORLD", false, true)
  T.eq(A.charKey, key); T.eq(ns.char.realm, NORM); T.eq(A.db.chars["Chad-Gippity"], nil)
  restore()
end)

T.test("comm drops the player's own messages in both key forms", function()
  as("Chad", "Gippity", NORM, LABEL)
  local A = MK.NewAddon("IdentComm")
  local comm = MK.Comm.New(A, "IDNT")
  local got = {}
  comm:On("HI", function(sender) got[#got + 1] = sender end)
  comm:OnAddon("IDNT", "HI", "PARTY", "Chad-Gippity")
  comm:OnAddon("IDNT", "HI", "PARTY", "Chad Gippity-" .. NORM)
  comm:OnAddon("IDNT", "HI", "PARTY", "Bob-Smith")
  T.eq(#got, 1); T.eq(got[1], "Bob-Smith")
  restore()
  T.noErrors()
end)

T.done()
