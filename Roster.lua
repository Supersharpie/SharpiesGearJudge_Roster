-- =========================================================================
-- Sharpie's Gear Judge - Roster (Alt Upgrades)
-- Shows which of your other characters an item would upgrade, and a grid of
-- every character's gear scores.
--
-- Each character saves a snapshot when it logs in, levels, changes talents
-- or changes gear: the finished Gear Judge weights for its active spec (and
-- any tracked specs), plus the score of every equipped item. Other
-- characters score new items against those saved weights. Nothing is rebuilt
-- for an alt, so its talents, level curves and caps are already baked in.
--
-- Items are always scored by their full link, so random suffixes ("of the
-- Bear" vs "of the Tiger") stay correct.
-- =========================================================================
local ADDON_NAME = ...
local MSC = _G.MSC
local L = (MSC and MSC.L) or setmetatable({}, { __index = function(t, k) return k end })

local pairs, ipairs, type, select, next = pairs, ipairs, type, select, next
local math_max, math_floor = math.max, math.floor
local string_format, string_find, string_match = string.format, string.find, string.match
local table_insert, table_sort = table.insert, table.sort
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemInfoInstant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
local IsEquippableItem = IsEquippableItem or (C_Item and C_Item.IsEquippableItem)

local DB  -- SGJ_RosterDB
local DEFAULTS = {
    ShowTooltip = true,   -- alt upgrade lines on item tooltips
    BoEOnly     = true,   -- only for items that can still be traded to an alt
    SameRealm   = true,   -- only characters on this realm and faction
    ShowFuture  = true,   -- include alts below the item's required level
    MaxLines    = 3,      -- alts listed per tooltip (biggest upgrades first)
}
local MAX_LINE_CHOICES = { 1, 2, 3, 5, 10 }

-- Upgrade size, as a percent of the alt's total gear score.
local BIG_PCT, MID_PCT = 6, 2
local STALE_DAYS = 7

local GEAR_SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
local SLOT_LABELS = {
    [1] = HEADSLOT, [2] = NECKSLOT, [3] = SHOULDERSLOT, [15] = BACKSLOT, [5] = CHESTSLOT,
    [9] = WRISTSLOT, [10] = HANDSSLOT, [6] = WAISTSLOT, [7] = LEGSSLOT, [8] = FEETSLOT,
    [11] = FINGER0SLOT_UNIQUE or ((FINGER0SLOT or "Finger") .. " 1"),
    [12] = FINGER1SLOT_UNIQUE or ((FINGER1SLOT or "Finger") .. " 2"),
    [13] = TRINKET0SLOT_UNIQUE or ((TRINKET0SLOT or "Trinket") .. " 1"),
    [14] = TRINKET1SLOT_UNIQUE or ((TRINKET1SLOT or "Trinket") .. " 2"),
    [16] = MAINHANDSLOT, [17] = SECONDARYHANDSLOT, [18] = RANGEDSLOT,
}
local TWO_HAND = { INVTYPE_2HWEAPON = true, INVTYPE_STAFF = true, INVTYPE_POLEARM = true }
-- Relic subclasses (armour class 4) and the class that uses them.
local RELIC_CLASS = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" }
-- Account-wide scoring options saved with each snapshot, so an alt's new
-- items are scored the same way as its saved gear.
local SCORING_KEYS = { "EnchantMode", "GemMode", "GemQuality", "AssumeCampingBuffs" }

local Roster = { rev = 0, cache = {}, cacheSize = 0 }

-- =========================================================================
-- 1. SMALL HELPERS
-- =========================================================================
-- A character's Roster key is its GUID: WoW Forever names have two parts and
-- UnitName returns only the first, so names can repeat across characters.
local function PlayerKey()
    local guid = UnitGUID and UnitGUID("player")
    if guid then return guid end
    if MSC and MSC.GetPlayerKey then return MSC:GetPlayerKey() end
    return (UnitName("player") or "Unknown") .. "-" .. (GetRealmName() or "Local")
end

local function BumpRevision()
    Roster.rev = Roster.rev + 1
    wipe(Roster.cache)
    Roster.cacheSize = 0
end

local function CopyScalars(t)
    local out = {}
    for k, v in pairs(t) do
        local tv = type(v)
        if tv == "number" or tv == "boolean" or tv == "string" then out[k] = v end
    end
    return out
end

-- "Fury: Raid (Dual Wield)" -> "Fury"
local function ShortSpec(pretty)
    if not pretty then return "?" end
    return string_match(pretty, "^([^:]+):") or pretty
end

-- A saved spec's short label: "Protection", or with Dual Specialization
-- "Secondary: Protection" (groupName is set only for two-spec characters).
local function SpecLabel(sd)
    local short = ShortSpec(sd and sd.pretty)
    if sd and sd.groupName then return sd.groupName .. ": " .. short end
    return short
end

local function ClassColor(class)
    local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
    if c then return c.colorStr or string_format("ff%02x%02x%02x", math_floor(c.r * 255), math_floor(c.g * 255), math_floor(c.b * 255)) end
    return "ffffffff"
end

local function ColoredName(alt)
    return "|c" .. ClassColor(alt.class) .. (alt.name or "?") .. "|r"
end

local function DaysOld(alt)
    if not alt.updated then return 0 end
    return math_floor((time() - alt.updated) / 86400)
end

local function IsShieldTank(class, spec)
    if class ~= "WARRIOR" and class ~= "PALADIN" and class ~= "SHAMAN" then return false end
    local up = string.upper(spec or "")
    return string_find(up, "TANK", 1, true) or string_find(up, "PROT", 1, true)
end

-- =========================================================================
-- 2. SCORING
-- One item in one slot against one set of weights. "Current Only" enchant
-- mode reads the enchant off whoever is logged in, which is meaningless for
-- an alt, so Roster scores it as raw stats (on both sides of the compare).
-- =========================================================================
-- Weapon types a class can wear but not attack with (Forever Hunters and
-- thrown weapons) score on stats only. The core applies the logged-in
-- class's list, so for an alt Roster applies the alt's list instead.
local DPS_KEYS = { "MSC_WEAPON_DPS", "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", "MSC_WEAPON_SPEED" }
local function StatsOnlyFor(alt, link, stats)
    if not alt then return stats end
    local _, _, _, _, _, classID, subID = GetItemInfoInstant(link)
    if classID ~= 2 or not subID then return stats end
    local mine = MSC.CurrentClass and MSC.CurrentClass.StatsOnlyWeapons
    local altOnly = (alt.statsOnly and alt.statsOnly[subID]) and true or false
    local myOnly = (mine and mine[subID]) and true or false
    if altOnly == myOnly then return stats end
    local out = {}
    for k, v in pairs(stats) do out[k] = v end
    if altOnly then
        for _, k in ipairs(DPS_KEYS) do out[k] = nil end
    elseif MSC.GetRawItemStats then
        -- the core stripped the DPS for the logged-in class: put it back
        local raw = MSC.GetRawItemStats(link) or {}
        for _, k in ipairs(DPS_KEYS) do out[k] = raw[k] end
        if MSC.IsForever and out.MSC_WEAPON_DPS and not out.ITEM_MOD_DAMAGE_PER_SECOND_SHORT then
            out.ITEM_MOD_DAMAGE_PER_SECOND_SHORT = out.MSC_WEAPON_DPS
        end
    end
    return out
end

-- A Libram, Idol or Totem judged for an alt of another class than the
-- logged-in one: returns its item ID (nil for anything else).
local function CrossClassRelic(alt, link)
    if not alt or not alt.class then return nil end
    local id, _, _, _, _, classID, subID = GetItemInfoInstant(link)
    if classID ~= 4 or not RELIC_CLASS[subID] then return nil end
    if alt.class == select(2, UnitClass("player")) then return nil end
    return id
end

-- Cross-class relics need the core's per-class relic table (3.2.1+); on
-- older cores they're skipped rather than scored as ~0.
local function RelicBlocked(alt, link)
    return (CrossClassRelic(alt, link) and not MSC.GetClassRelicBonus) and true or false
end

-- The core adds relic stats for the logged-in class only: swap them for the alt's class.
local function RelicFor(alt, link, stats, spec)
    local relicID = CrossClassRelic(alt, link)
    if not relicID or not MSC.GetClassRelicBonus then return stats end
    local out = {}
    for k, v in pairs(stats) do out[k] = v end
    local cc = MSC.CurrentClass
    if cc and cc.GetRelicBonus then
        local ok, mine = pcall(cc.GetRelicBonus, cc, relicID, spec or "")
        if ok and type(mine) == "table" then
            for k, v in pairs(mine) do
                if type(v) == "number" and v > 0 and type(out[k]) == "number" then
                    out[k] = out[k] - v
                    if out[k] <= 0 then out[k] = nil end
                end
            end
        end
    end
    local ok, theirs = pcall(MSC.GetClassRelicBonus, alt.class, relicID, spec or "")
    if ok and type(theirs) == "table" then
        for k, v in pairs(theirs) do
            if type(v) == "number" and v > 0 then out[k] = (out[k] or 0) + v end
        end
    end
    return out
end

local function RawScore(link, slotId, weights, spec, alt)
    local stats = StatsOnlyFor(alt, link, MSC.SafeGetItemStats(link, slotId, weights, spec))
    stats = RelicFor(alt, link, stats, spec)
    return MSC.GetItemScore(stats, weights, spec, slotId) or 0
end

-- The scoring options a character's snapshot was taken with (live ones for
-- old snapshots). "Current Only" enchants read as raw stats (see above).
local function ScoringOptions()
    local s = SGJ_Settings
    if not s then return nil end
    local out = {}
    for _, k in ipairs(SCORING_KEYS) do out[k] = s[k] end
    out.AssumeCampingBuffs = s.AssumeCampingBuffs and true or false
    return out
end

local function ScoringSig(alt)
    local src = (alt and alt.scoring) or SGJ_Settings or {}
    local live = SGJ_Settings or {}
    local function V(k) local v = src[k]; if v == nil then v = live[k] end; return tostring(v) end
    return V("EnchantMode") .. "|" .. V("GemMode") .. "|" .. V("GemQuality") .. "|" .. V("AssumeCampingBuffs")
end

-- alt: the saved character the item is scored for (nil = the logged-in one).
-- The alt's saved scoring options are applied for the call and always restored.
local function ScoreItem(link, slotId, weights, spec, alt)
    local s = SGJ_Settings
    local e, g, q, c
    if s then
        e, g, q, c = s.EnchantMode, s.GemMode, s.GemQuality, s.AssumeCampingBuffs
        local want = alt and alt.scoring
        if want then
            for _, k in ipairs(SCORING_KEYS) do
                if want[k] ~= nil then s[k] = want[k] end
            end
        end
        if s.EnchantMode == 2 then s.EnchantMode = 1 end
    end
    local ok, score = pcall(RawScore, link, slotId, weights, spec, alt)
    if s then s.EnchantMode, s.GemMode, s.GemQuality, s.AssumeCampingBuffs = e, g, q, c end
    if ok then return score end
    if MSC.Debug then print("|cff00ccffSGJ Roster|r score error:", score) end
    return nil
end

-- Class and racial weapon bonuses (Weaponmaster, Hack and Slash, Sword
-- Specialization...), main and off hand only, like the core. For an alt the
-- core runs the alt's class code with the alt's saved race, level, attack
-- power and talent ranks (MSC.BonusContext). Cores without that support
-- (before 3.2.1) skip weapon bonuses on both sides of the compare.
local function HasBonusContext() return MSC.ClassWeaponBonus and MSC.CtxRace and true or false end

local function WeaponBonus(link, slotId, weights, spec, alt, sd, otherLink)
    if (slotId ~= 16 and slotId ~= 17) or not link or not HasBonusContext() then return 0 end
    if not alt then
        local ok, b = pcall(MSC.GetWeaponSpecBonus, MSC, link, MSC.CurrentClass, spec, weights, slotId, otherLink)
        return (ok and tonumber(b)) or 0
    end
    local fn = MSC.ClassWeaponBonus[alt.class or ""]
    if not fn then return 0 end
    local prev = MSC.BonusContext
    MSC.BonusContext = { race = alt.raceToken, level = alt.level, ap = alt.ap, talentRanks = (sd and sd.talentRanks) or {} }
    local ok, b = pcall(fn, nil, link, weights, slotId, spec, otherLink)
    MSC.BonusContext = prev
    return (ok and tonumber(b)) or 0
end

-- Item score plus weapon bonus. otherLink: the weapon in the other hand.
local function FullScore(link, slotId, weights, spec, alt, sd, otherLink)
    local score = ScoreItem(link, slotId, weights, spec, alt)
    if not score then return nil end
    return score + WeaponBonus(link, slotId, weights, spec, alt, sd, otherLink)
end

-- ---------------------------------------------------------------- set bonuses
-- Scored with the character's own weights, the same way the core scores them.
local function SetIDOf(link)
    local id = link and GetItemInfoInstant(link)
    return id and MSC.ItemSetMap and MSC.ItemSetMap[id]
end

local equivScratch = {}
local function BonusDataScore(data, weights, spec)
    local score = 0
    if data.stats then score = score + (MSC.GetItemScore(data.stats, weights, spec) or 0) end
    if data.equiv then
        local best = 0
        for stat, val in pairs(data.equiv) do
            equivScratch[stat] = val
            local v = MSC.GetItemScore(equivScratch, weights, spec) or 0
            equivScratch[stat] = nil
            if v > best then best = v end
        end
        score = score + best
    end
    if not data.stats and not data.equiv and data.score then score = score + data.score end
    return score
end

-- Value of a set's bonuses at `count` pieces; also the highest tier reached.
local function SetValue(setID, count, weights, spec)
    local tiers = MSC.SetBonusScores and MSC.SetBonusScores[setID]
    if not tiers or count <= 0 then return 0, 0 end
    local total, top = 0, 0
    for req, data in pairs(tiers) do
        local r = tonumber(req)
        if r and count >= r and type(data) == "table" then
            total = total + BonusDataScore(data, weights, spec)
            if r > top then top = r end
        end
    end
    return total, top
end

-- Set bonus change from putting newLink in place of the items in `replaced`
-- slots. Returns score delta, tier gained (or nil), tier broken (or nil).
local function SetDelta(sd, spec, newLink, replaced)
    if not MSC.ItemSetMap then return 0 end
    local slots = sd.slots
    local counts = {}
    for _, e in pairs(slots) do
        local id = SetIDOf(e.link)
        if id then counts[id] = (counts[id] or 0) + 1 end
    end
    local newSet = SetIDOf(newLink)
    local after = {}
    if newSet then after[newSet] = (counts[newSet] or 0) + 1 end
    for _, slotId in ipairs(replaced) do
        local id = slots[slotId] and SetIDOf(slots[slotId].link)
        if id then after[id] = (after[id] or counts[id] or 0) - 1 end
    end
    local delta, gained, broken = 0, nil, nil
    for id, n in pairs(after) do
        local before = counts[id] or 0
        if n ~= before then
            local vb, tb = SetValue(id, before, sd.weights, spec)
            local va, ta = SetValue(id, n, sd.weights, spec)
            delta = delta + (va - vb)
            if ta > tb then gained = math_max(gained or 0, ta) end
            if ta < tb then broken = math_max(broken or 0, tb) end
        end
    end
    return delta, gained, broken
end

-- =========================================================================
-- 3. SNAPSHOT (this character -> SGJ_RosterDB)
-- =========================================================================
local function PrettyName(spec)
    local pn = MSC.CurrentClass and MSC.CurrentClass.PrettyNames
    return (pn and pn[spec]) or spec
end

local function CanDualWieldNow()
    if CanDualWield then
        local ok, r = pcall(CanDualWield)
        if ok and r ~= nil then return r and true or false end
    end
    local _, cls = UnitClass("player")
    local lvl = UnitLevel("player") or 0
    if cls == "ROGUE" or cls == "WARRIOR" then return lvl >= 10 end
    if cls == "HUNTER" then return lvl >= 20 end
    if cls == "SHAMAN" and MSC.GetTalentRank then return (MSC:GetTalentRank("DUAL_WIELD") or 0) > 0 end
    return false
end

-- Slots an item could go in, for scoring stashed (bag/bank/mail) items.
-- One-handers only count for the off hand on characters that can dual wield.
local function CandidateSlots(equipLoc, canDW)
    if equipLoc == "INVTYPE_FINGER" then return { 11 } end
    if equipLoc == "INVTYPE_TRINKET" then return { 13 } end
    if equipLoc == "INVTYPE_WEAPON" then return canDW and { 16, 17 } or { 16 } end
    local s = MSC.SlotMap and MSC.SlotMap[equipLoc]
    if s and s ~= 4 then return { s } end
    return nil
end

-- What a two-hander has to beat: both hands' items plus their combined
-- weapon bonus (a racial counts once).
local function BothHandsScore(slots, pairBonus)
    local mh, oh = slots[16], slots[17]
    local mh2H = mh and mh.twoHand
    return (mh and (mh.raw or mh.score) or 0) + ((not mh2H and oh) and (oh.raw or oh.score) or 0) + (pairBonus or 0)
end

-- The lowest equipped score an item in this slot would have to beat (a ring
-- or trinket only has to beat the weaker of the pair).
local function EquippedFloor(slots, slotId)
    local function S(x) local e = slots[x]; return e and e.score or 0 end
    if slotId == 11 or slotId == 13 then return math.min(S(slotId), S(slotId + 1)) end
    return S(slotId)
end

-- Bag and bank items this character is keeping for later: only the ones that
-- score above what's equipped in their slot (so they'd be worn eventually).
local function OtherHandLink(slots, slotId)
    local other = (slotId == 16 and slots[17]) or (slotId == 17 and slots[16]) or nil
    return other and other.link
end

local function SnapshotStash(weights, spec, slots, stashItems, state, canDW, pairBonus)
    local out = {}
    for _, it in ipairs(stashItems) do
        local cands = CandidateSlots(it.loc, canDW)
        if cands then
            local scores, keep = {}, false
            for _, slotId in ipairs(cands) do
                local other = (not TWO_HAND[it.loc]) and OtherHandLink(slots, slotId) or nil
                local sc = FullScore(it.link, slotId, weights, spec, nil, nil, other)
                if not sc then state.missing = true; sc = 0 end
                scores[slotId] = sc
                -- a two-hander replaces both hands, so it has to beat both
                local floor = TWO_HAND[it.loc] and BothHandsScore(slots, pairBonus) or EquippedFloor(slots, slotId)
                if sc > floor + 0.05 then keep = true end
            end
            if keep then
                out[#out + 1] = { link = it.link, req = it.req, where = it.where, twoHand = TWO_HAND[it.loc] or nil, scores = scores }
            end
        end
    end
    return out
end

-- This character's talent ranks by key, for weapon bonuses scored later on another character.
local function TalentRanks()
    local out = {}
    local talents = MSC.CurrentClass and MSC.CurrentClass.Talents
    if talents and MSC.GetTalentRank then
        for key in pairs(talents) do
            local ok, r = pcall(MSC.GetTalentRank, MSC, key)
            if ok and type(r) == "number" and r > 0 then out[key] = r end
        end
    end
    return out
end

local function SnapshotSpec(weights, spec, gear, state, stashItems, canDW)
    local slots, total = {}, 0
    for _, slotId in ipairs(GEAR_SLOTS) do
        local link = gear[slotId]
        if link then
            if not GetItemInfo(link) then state.missing = true end
            local raw = ScoreItem(link, slotId, weights, spec)
            if not raw then state.missing = true; raw = 0 end
            local loc = select(4, GetItemInfoInstant(link))
            slots[slotId] = { link = link, raw = raw, score = raw, twoHand = TWO_HAND[loc] or nil }
        end
    end
    -- Weapon bonuses: each hand's bonus next to the other hand (what a swap in
    -- that hand changes), and both hands together (what a two-hander replaces).
    local mh, oh = slots[16], slots[17]
    if mh then mh.score = mh.raw + WeaponBonus(mh.link, 16, weights, spec, nil, nil, oh and oh.link) end
    if oh then oh.score = oh.raw + WeaponBonus(oh.link, 17, weights, spec, nil, nil, mh and mh.link) end
    local pairBonus = (mh and WeaponBonus(mh.link, 16, weights, spec) or 0)
        + (oh and WeaponBonus(oh.link, 17, weights, spec, nil, nil, mh and mh.link) or 0)
    for _, e in pairs(slots) do total = total + e.score end
    -- Active set bonuses count toward the total, like the core's character score.
    if MSC.ItemSetMap then
        local counts = {}
        for _, e in pairs(slots) do
            local id = SetIDOf(e.link)
            if id then counts[id] = (counts[id] or 0) + 1 end
        end
        for id, n in pairs(counts) do total = total + SetValue(id, n, weights, spec) end
    end
    local stash = SnapshotStash(weights, spec, slots, stashItems or {}, state, canDW, pairBonus)
    return { pretty = PrettyName(spec), weights = CopyScalars(weights), slots = slots, total = total, stash = stash,
             pairBonus = pairBonus, talentRanks = TalentRanks() }
end

local AltCanUse, ItemInfo  -- defined in sections 4 and 5

local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetSlotLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink

-- Bank containers. Clients with character bank tabs (Forever, like Retail)
-- use Enum.BagIndex.CharacterBankTab_N; Classic uses the bank container plus
-- the bank bags after the backpack bags (never the reagent bag).
-- (Like Syndicator: Classic bank bags are NUM_BAG_SLOTS + 1..n; the enum's
-- bank bag values are wrong there. skip: a container ID to leave out.)
local function ClassicBankIds(skip)
    local ids = { BANK_CONTAINER or -1 }
    local first = (NUM_BAG_SLOTS or 4) + 1
    for b = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do
        if b ~= skip then ids[#ids + 1] = b end
    end
    return ids
end

local function BankBagIds()
    local E = Enum and Enum.BagIndex
    if E and E.CharacterBankTab_1 and GetNumSlots then
        local ids, slots = {}, 0
        for i = 1, 12 do
            local id = E["CharacterBankTab_" .. i]
            if not id then break end
            ids[#ids + 1] = id
            local ok, n = pcall(GetNumSlots, id)
            slots = slots + ((ok and tonumber(n)) or 0)
        end
        -- Tabs defined but empty (not bought, or this client still uses the
        -- old bank): read the Classic layout instead.
        if slots > 0 then return ids end
        -- this client has a reagent bag right after the backpack bags
        return ClassicBankIds(E.ReagentBag)
    end
    return ClassicBankIds()
end

local function BagLinks(ids, state)
    local links = {}
    if not (GetNumSlots and GetSlotLink) then return links end
    for _, bag in ipairs(ids) do
        local ok, n = pcall(GetNumSlots, bag)
        for slot = 1, ((ok and tonumber(n)) or 0) do
            local link = GetSlotLink(bag, slot)
            if link and IsEquippableItem(link) then
                if not GetItemInfo(link) then state.missing = true end
                links[#links + 1] = link
            end
        end
    end
    return links
end

-- Equippable attachments in this character's mailbox (only readable while
-- it's open). Second result: true when every mail was read (the inbox has
-- loaded and none are held back by the 50-mail display limit).
local function InboxLinks(state)
    local links = {}
    if not (GetInboxNumItems and GetInboxItemLink) then return links, false end
    local shown, total = GetInboxNumItems()
    shown = shown or 0
    local complete = Roster.inboxLoaded and (total == nil or shown >= total) or false
    for i = 1, shown do
        for a = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
            local link = GetInboxItemLink(i, a)
            if link and IsEquippableItem(link) then
                if not GetItemInfo(link) then state.missing = true end
                links[#links + 1] = link
            end
        end
    end
    return links, complete
end

-- Equippable bag, bank and mailbox items this character can use, now or at a
-- later level. Bank and mailbox lists are kept from the last visit.
local function CollectStash(self, prev, state)
    local bagIds = {}
    for b = 0, (NUM_BAG_SLOTS or 4) do bagIds[#bagIds + 1] = b end
    local bank = Roster.bankOpen and BagLinks(BankBagIds(), state) or (prev and prev.bankLinks) or {}
    -- The inbox only counts once it has loaded (MAIL_INBOX_UPDATE).
    local inbox, inboxComplete
    if Roster.mailOpen and Roster.inboxLoaded then
        inbox, inboxComplete = InboxLinks(state)
    else
        inbox = (prev and prev.inboxLinks) or {}
    end
    local bagLinks = BagLinks(bagIds, state)
    local items = {}
    local function Add(link, where)
        local info = ItemInfo(link)
        if info and AltCanUse(self, link, info) then
            items[#items + 1] = { link = link, loc = info.equipLoc, req = info.reqLevel, where = where }
        end
    end
    for _, link in ipairs(bagLinks) do Add(link, "bags") end
    for _, link in ipairs(bank) do Add(link, "bank") end
    for _, link in ipairs(inbox) do Add(link, "mail") end
    -- Links read live just now (for clearing mail that has arrived).
    local seen = {}
    for _, link in ipairs(bagLinks) do seen[link] = true end
    if Roster.bankOpen then for _, link in ipairs(bank) do seen[link] = true end end
    if Roster.mailOpen and Roster.inboxLoaded then for _, link in ipairs(inbox) do seen[link] = true end end
    return items, bank, inbox, seen, inboxComplete
end

-- Mail sent to this character from another of yours: drop entries that have
-- arrived (seen in the inbox, bags, bank or worn). When the whole inbox was
-- read, also drop ones past the delivery delay that aren't there any more
-- (taken and sold, returned or deleted).
local MAIL_DELAY = 3600
-- Links carry the level of whoever made them, so match on item ID,
-- enchant, gems and random suffix only.
local function ItemKey(link)
    local str = type(link) == "string" and string_match(link, "item:([%-%d:]+)")
    if not str then return link end
    local parts, n = {}, 0
    for f in string.gmatch(str .. ":", "([^:]*):") do
        n = n + 1
        if n > 7 then break end
        parts[n] = (f == "" and "0") or f
    end
    return table.concat(parts, ":")
end

local function ClearArrivedMail(key, seen, gear, inboxComplete)
    local list = DB.mailed[key]
    if not list then return end
    local have = {}
    for link in pairs(seen) do have[ItemKey(link)] = true end
    for _, link in pairs(gear) do have[ItemKey(link)] = true end
    local now = time()
    for i = #list, 1, -1 do
        local m = list[i]
        if have[ItemKey(m.link)] or (inboxComplete and now - (m.sent or 0) >= MAIL_DELAY) then table.remove(list, i) end
    end
    if #list == 0 then DB.mailed[key] = nil end
end

local function TakeSnapshot()
    if not (DB and MSC and MSC.GetCurrentWeights and MSC.CurrentClass) then return false end
    local weights, spec = MSC.GetCurrentWeights()
    if type(weights) ~= "table" or not next(weights) or not spec then return false end

    local key = PlayerKey()
    local coreKey = (MSC.GetPlayerKey and MSC:GetPlayerKey()) or key   -- core TalentProfiles/GearProfiles
    local state = {}
    local gear = {}
    for _, s in ipairs(GEAR_SLOTS) do gear[s] = GetInventoryItemLink("player", s) end

    local _, cls = UnitClass("player")
    local valid = {}
    if MSC.CurrentClass.ValidWeapons then
        for k, v in pairs(MSC.CurrentClass.ValidWeapons) do if v then valid[k] = true end end
    end
    local statsOnly = {}
    if MSC.CurrentClass.StatsOnlyWeapons then
        for k, v in pairs(MSC.CurrentClass.StatsOnlyWeapons) do if v then statsOnly[k] = true end end
    end
    local prev = DB.chars[key]
    local self = { class = cls, level = UnitLevel("player"), validWeapons = valid }
    local canDW = CanDualWieldNow()
    local stashItems, bankLinks, inboxLinks, seen, inboxComplete = CollectStash(self, prev, state)
    ClearArrivedMail(key, seen, gear, inboxComplete)

    local specs = {}
    specs[spec] = SnapshotSpec(weights, spec, gear, state, stashItems, canDW)

    -- Tracked specs (the core's multi-spec), with the talents and gear set
    -- saved for each, the same way the core's tooltip scores them.
    local tracked = SGJ_Settings and SGJ_Settings.TrackedSpecs
    if tracked and MSC.GetWeightsByName then
        for tSpec, on in pairs(tracked) do
            if on and tSpec ~= spec and not specs[tSpec] then
                local origTalents = MSC.TalentCache
                local tp = SGJ_Settings.TalentProfiles
                if tp and tp[coreKey] and tp[coreKey][tSpec] then MSC.TalentCache = tp[coreKey][tSpec] end
                local ok, tWeights = pcall(MSC.GetWeightsByName, tSpec)
                if ok and type(tWeights) == "table" and next(tWeights) then
                    local gp = SGJ_Settings.GearProfiles
                    local tGear = gp and gp[coreKey] and gp[coreKey][tSpec]
                    specs[tSpec] = SnapshotSpec(tWeights, tSpec, tGear or gear, state, stashItems, canDW)
                end
                MSC.TalentCache = origTalents
            end
        end
    end

    -- Dual Specialization: the spec you're not in, scored with its own talents,
    -- profile, Talents build and Gear for PvP, against the gear last worn in it.
    -- Its key gets "@<group>" (both specs can use the same profile); sd.spec is
    -- the real profile key used for scoring.
    if MSC.HasDualSpec and MSC.HasDualSpec() and MSC.WithSpecGroup and MSC.GetWeightsForGroup then
        local active = MSC.GetActiveSpecGroup()
        local other = (active == 1) and 2 or 1
        specs[spec].group, specs[spec].groupName = active, MSC.SpecGroupName(active)
        MSC.WithSpecGroup(other, function()
            local oWeights, oSpec = MSC:GetWeightsForGroup(other)
            if type(oWeights) ~= "table" or not next(oWeights) or not oSpec then return end
            local oGear = MSC.GetSpecGear and MSC.GetSpecGear(other)
            local entry = SnapshotSpec(oWeights, oSpec, oGear or gear, state, stashItems, canDW)
            entry.spec, entry.group, entry.groupName = oSpec, other, MSC.SpecGroupName(other)
            specs[oSpec .. "@" .. other] = entry
        end)
    end

    DB.chars[key] = {
        key = key,
        name = (MSC.GetCharacterName and MSC.GetCharacterName()) or UnitName("player"),
        realm = GetRealmName(),
        faction = UnitFactionGroup("player"),
        class = cls,
        race = UnitRace("player"),
        raceToken = select(2, UnitRace("player")),
        ap = (MSC.CtxAttackPower and MSC.CtxAttackPower()) or nil,
        statsOnly = statsOnly,
        level = UnitLevel("player"),
        updated = time(),
        canDW = canDW,
        scoring = ScoringOptions(),
        validWeapons = valid,
        active = spec,
        specs = specs,
        bankLinks = bankLinks,
        inboxLinks = inboxLinks,
        shown = prev and prev.shown and specs[prev.shown] and prev.shown or nil,
    }
    BumpRevision()
    return not state.missing
end

local snapPending, snapRetries = false, 0
local function RequestSnapshot(delay)
    if snapPending then return end
    snapPending = true
    C_Timer.After(delay or 2, function()
        snapPending = false
        if InCombatLockdown() then RequestSnapshot(5); return end
        local ok, complete = pcall(TakeSnapshot)
        if not ok then
            if MSC and MSC.Debug then print("|cff00ccffSGJ Roster|r snapshot error:", complete) end
            return
        end
        -- Some equipped items weren't cached yet: their scores read 0, so retry.
        if complete == false and snapRetries < 5 then
            snapRetries = snapRetries + 1
            RequestSnapshot(4)
        else
            snapRetries = 0
        end
        if Roster.RefreshPage then Roster.RefreshPage() end
    end)
end
-- Gear for PvP changes this character's weights: snapshot again. (Other
-- characters keep the weights from their last login until they log in.)
if MSC and MSC.PvPToggleListeners then
    table.insert(MSC.PvPToggleListeners, function() RequestSnapshot(1) end)
end

-- =========================================================================
-- 4. CAN THE ALT USE IT?
-- =========================================================================
local scanTip
local scanCache = {}  -- itemID -> { classes = "Classes: ..." or false, unique = bool }

-- What the item's tooltip says that the item API doesn't: its "Classes: ..."
-- line and whether it's unique(-equipped). nil when it can't be read yet.
local function ScanItem(link)
    local id = GetItemInfoInstant(link)
    if not id then return nil end
    if scanCache[id] then return scanCache[id] end
    scanTip = scanTip or CreateFrame("GameTooltip", "SGJ_RosterScanTip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    if not pcall(scanTip.SetHyperlink, scanTip, link) then return nil end
    local n = scanTip:NumLines() or 0
    -- An empty scan (item data not loaded) proves nothing: don't remember it.
    if n <= 1 then Roster.missing = true; return nil end
    local prefix = ITEM_CLASSES_ALLOWED and ITEM_CLASSES_ALLOWED:gsub("%%s", "")
    local res = { classes = false, unique = false }
    for i = 2, n do
        local fs = _G["SGJ_RosterScanTipTextLeft" .. i]
        local text = fs and fs:GetText()
        -- Forever can hand back protected ("secret") text that errors when compared.
        if type(text) == "string" and not (MSC_IsSecret and MSC_IsSecret(text)) then
            if prefix and not res.classes and string_find(text, prefix, 1, true) then res.classes = text end
            if (ITEM_UNIQUE and text == ITEM_UNIQUE) or (ITEM_UNIQUE_EQUIPPABLE and text == ITEM_UNIQUE_EQUIPPABLE) then
                res.unique = true
            end
        end
    end
    scanCache[id] = res
    return res
end

-- The "Classes: ..." line of an item, or false when it has none.
local function ClassRestriction(link)
    local r = ScanItem(link)
    return (r and r.classes) or false
end

local function IsUniqueItem(link)
    local r = ScanItem(link)
    return (r and r.unique) or false
end

-- Same armour rules as the core's MSC.IsItemUsable, at the level the alt
-- will be when it can wear the item.
local function MaxArmor(class, level)
    if class == "WARRIOR" or class == "PALADIN" then return (level >= 40) and 4 or 3 end
    if class == "SHAMAN" or class == "HUNTER" then return (level >= 40) and 3 or 2 end
    if class == "ROGUE" or class == "DRUID" then return 2 end
    return 1
end

function AltCanUse(alt, link, info)
    if info.classID == 2 then
        if alt.validWeapons and next(alt.validWeapons) and not alt.validWeapons[info.subClassID] then return false end
    elseif info.classID == 4 then
        local sub = info.subClassID
        if sub == 6 then
            if alt.class ~= "WARRIOR" and alt.class ~= "PALADIN" and alt.class ~= "SHAMAN" then return false end
        elseif RELIC_CLASS[sub] then
            if alt.class ~= RELIC_CLASS[sub] then return false end
        elseif sub and sub > 0 and sub <= 4 then
            if sub > MaxArmor(alt.class, math_max(alt.level or 1, info.reqLevel or 1)) then return false end
        end
    end
    local allowed = ClassRestriction(link)
    if allowed then
        local m = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[alt.class]
        local f = LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[alt.class]
        if not ((m and string_find(allowed, m, 1, true)) or (f and string_find(allowed, f, 1, true))) then return false end
    end
    return true
end

-- =========================================================================
-- 5. JUDGE AN ITEM FOR ONE ALT
-- Compares against what the alt already owns: equipped items, plus bag and
-- bank items it will be able to wear by the time it can wear this one (its
-- level or the item's required level, whichever is higher). Rings and
-- trinkets replace the weaker of the pair; one-handers try the off hand too
-- when the alt can dual wield; a two-hander replaces both hands.
-- Returns delta, slotId, delta vs equipped only, and the stashed item that
-- set the bar (nil when the item doesn't fit this alt's setup).
-- =========================================================================
-- Items sent to an alt from another of your characters, not yet seen in its
-- mailbox. Scored here with the alt's saved weights (cached on the entry).
local MAIL_DAYS = 30
local function MailedFor(alt, spec, sd)
    local list = alt.key and DB.mailed[alt.key]
    if not list then return nil end
    local out
    local now = time()
    for i = #list, 1, -1 do
        local m = list[i]
        if now - (m.sent or 0) > MAIL_DAYS * 86400 then
            table.remove(list, i)  -- returned or deleted by now
        else
            local info = ItemInfo(m.link)
            if not info then Roster.missing = true end
            local cands = info and not RelicBlocked(alt, m.link) and CandidateSlots(info.equipLoc, alt.canDW)
            if cands and AltCanUse(alt, m.link, info) then
                -- Rescore when the alt's snapshot (weights, scoring options) changed.
                local scoredFor = tostring(alt.updated) .. "|" .. ScoringSig(alt)
                if m.scoredFor ~= scoredFor then m.scores, m.scoredFor = {}, scoredFor end
                local sc = m.scores[spec]
                if not sc then
                    sc = {}
                    local twoHand = TWO_HAND[info.equipLoc]
                    for _, slotId in ipairs(cands) do
                        local other = (not twoHand) and OtherHandLink(sd.slots, slotId) or nil
                        local v = FullScore(m.link, slotId, sd.weights, sd.spec or spec, alt, sd, other)
                        if not v then Roster.missing = true end
                        sc[slotId] = v or 0
                    end
                    m.scores[spec] = sc
                end
                out = out or {}
                out[#out + 1] = { link = m.link, req = info.reqLevel, where = "mail", twoHand = TWO_HAND[info.equipLoc] or nil, scores = sc }
            end
        end
    end
    if #list == 0 then DB.mailed[alt.key] = nil end
    return out
end

-- Everything an alt owns besides what's equipped: bags, bank, mailbox and mail on the way.
local function OwnedFor(alt, spec, sd)
    local mailed = MailedFor(alt, spec, sd)
    if not mailed then return sd.stash or {} end
    local out = {}
    for _, it in ipairs(sd.stash or {}) do out[#out + 1] = it end
    for _, it in ipairs(mailed) do out[#out + 1] = it end
    return out
end

-- Where a stashed item is (literal keys so the locale audit finds them).
local function WhereText(where)
    if where == "bank" then return L["bank"] elseif where == "mail" then return L["mail"] end
    return L["bags"]
end
local function HasBetterText(where)
    if where == "bank" then return L["has better (bank)"] elseif where == "mail" then return L["has better (mail)"] end
    return L["has better (bags)"]
end

local function SpecDelta(alt, spec, sd, link, equipLoc, reqLevel)
    local w, slots, stash = sd.weights, sd.slots, OwnedFor(alt, spec, sd)
    spec = sd.spec or spec -- the other spec's entry key carries "@<group>"
    local cutoff = math_max(alt.level or 0, reqLevel or 0)
    local function Eq(s) local e = slots[s]; return e and e.score or 0 end
    local mh2H = slots[16] and slots[16].twoHand

    -- Best stashed score for a slot (twoHand: true = only 2H, false = no 2H, nil = any).
    local function Stash(slotId, twoHand)
        local best, bestIt = 0, nil
        for _, it in ipairs(stash) do
            local sc = it.scores and it.scores[slotId]
            if sc and (it.req or 0) <= cutoff and sc > best
                and (twoHand == nil or (it.twoHand and true or false) == twoHand) then
                best, bestIt = sc, it
            end
        end
        return best, bestIt
    end

    local best, bestSlot, eqBest, bar, setGain, setBreak
    -- replaced: the equipped slots the new item takes over (for set bonuses)
    local function Try(slotId, newScore, owned, equipped, stashIt, replaced)
        if not newScore then return end
        local sDelta, gained, broken = SetDelta(sd, spec, link, replaced or { slotId })
        newScore = newScore + sDelta
        local d = newScore - owned
        if not best or d > best then
            best, bestSlot, bar = d, slotId, (owned > equipped) and stashIt or nil
            setGain, setBreak = gained, broken
        end
        local de = newScore - equipped
        if not eqBest or de > eqBest then eqBest = de end
    end
    local function Other(slotId) return OtherHandLink(slots, slotId) end
    local function Score(slotId, other) return FullScore(link, slotId, w, spec, alt, sd, other) end
    -- A one-hand swap is only measured against stashed one-handers (a
    -- stashed two-hander replaces both hands, see the two-hand case).
    local function Single(slotId, n)
        local twoHand = nil
        if slotId == 16 or slotId == 17 then twoHand = false end
        local st, it = Stash(slotId, twoHand)
        Try(slotId, n, math_max(Eq(slotId), st), Eq(slotId), it)
    end

    if equipLoc == "INVTYPE_FINGER" or equipLoc == "INVTYPE_TRINKET" then
        local a = (equipLoc == "INVTYPE_FINGER") and 11 or 13
        local n = Score(a)
        -- Unique and already worn: it can only take the place of that copy.
        local wornAt
        local id = GetItemInfoInstant(link)
        if id and IsUniqueItem(link) then
            for s = a, a + 1 do
                if slots[s] and GetItemInfoInstant(slots[s].link) == id then wornAt = s; break end
            end
        end
        if wornAt then
            Try(wornAt, n, Eq(wornAt), Eq(wornAt))
        else
            -- The new item replaces the weaker of the best two owned.
            local owned = { { Eq(a) }, { Eq(a + 1) } }
            for _, it in ipairs(stash) do
                local sc = it.scores and it.scores[a]
                if sc and (it.req or 0) <= cutoff then owned[#owned + 1] = { sc, it } end
            end
            table_sort(owned, function(x, y) return x[1] > y[1] end)
            local weakSlot = (Eq(a) <= Eq(a + 1)) and a or a + 1
            Try(weakSlot, n, owned[2][1], math.min(Eq(a), Eq(a + 1)), owned[2][2])
        end
    elseif TWO_HAND[equipLoc] then
        if IsShieldTank(alt.class, spec) and not (mh2H and SGJ_Settings and SGJ_Settings.ShieldTankNo2H == false) then
            return nil
        end
        -- both hands with their combined weapon bonus (a racial counts once)
        local equipped = BothHandsScore(slots, sd.pairBonus)
        local st2H, it2H = Stash(16, true)
        -- Best owned main hand + off hand pair; one item can't fill both hands.
        local mhOpts = { { mh2H and 0 or Eq(16) } }
        local ohOpts = { { Eq(17) } }
        for _, it in ipairs(stash) do
            if (it.req or 0) <= cutoff and not it.twoHand and it.scores then
                if it.scores[16] then mhOpts[#mhOpts + 1] = { it.scores[16], it } end
                if it.scores[17] then ohOpts[#ohOpts + 1] = { it.scores[17], it } end
            end
        end
        local pair, pairIt = 0, nil
        for _, x in ipairs(mhOpts) do
            for _, y in ipairs(ohOpts) do
                if not (x[2] and x[2] == y[2]) and x[1] + y[1] > pair then
                    pair, pairIt = x[1] + y[1], x[2] or y[2]
                end
            end
        end
        local owned = math_max(equipped, st2H, pair)
        local it = (it2H and owned == st2H) and it2H or pairIt
        Try(16, Score(16), owned, equipped, it, { 16, 17 })
    elseif equipLoc == "INVTYPE_WEAPON" then
        Single(16, Score(16, Other(16)))
        if alt.canDW and not mh2H then Single(17, Score(17, Other(17))) end
    elseif equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then
        if mh2H then return nil end
        if equipLoc == "INVTYPE_WEAPONOFFHAND" and not alt.canDW then return nil end
        Single(17, Score(17, Other(17)))
    else
        local slotId = MSC.SlotMap and MSC.SlotMap[equipLoc]
        if not slotId or slotId == 4 then return nil end
        -- main-hand-only weapons: the other hand matters (a racial counts once)
        local other = (slotId == 16 or slotId == 17) and Other(slotId) or nil
        Single(slotId, Score(slotId, other))
    end
    return best, bestSlot, eqBest, bar, setGain, setBreak
end

function ItemInfo(link)
    local name, _, _, _, reqLevel, _, _, _, equipLoc, _, _, classID, subClassID, bindType = GetItemInfo(link)
    if not name then return nil end
    return { reqLevel = reqLevel or 0, equipLoc = equipLoc, classID = classID, subClassID = subClassID, bindType = bindType }
end

-- One alt, one or all of its specs. Result: { state = "cant" | "none" |
-- "stashed" (would be an upgrade, but a bag/bank item is better) | "up",
-- delta, pct, slot, spec, atLevel, stash }.
local function JudgeForAlt(alt, link, info, onlySpec)
    if not AltCanUse(alt, link, info) then return { state = "cant" } end
    local res = { state = "none" }
    -- Another class's relic on a core that can't score it for them: say nothing.
    if RelicBlocked(alt, link) then return res end
    local stashedBy
    for spec, sd in pairs(alt.specs or {}) do
        if not onlySpec or spec == onlySpec then
            local d, slotId, eqD, bar, gained, broken = SpecDelta(alt, spec, sd, link, info.equipLoc, info.reqLevel)
            if slotId then res.slot = res.slot or slotId end
            if eqD and eqD > 0.05 and (not d or d <= 0.05) and bar then stashedBy = stashedBy or bar end
            if d and d > 0.05 and (not res.delta or d > res.delta) then
                res.state, res.delta, res.slot, res.spec = "up", d, slotId, spec
                res.setGain, res.setBreak = gained, broken
                res.pct = (sd.total or 0) > 0 and (d / sd.total * 100) or nil
            end
        end
    end
    if res.state == "none" and stashedBy then res.state, res.stash = "stashed", stashedBy end
    if (info.reqLevel or 0) > (alt.level or 0) then res.atLevel = info.reqLevel end
    return res
end

local function TierText(res)
    if not res.pct then return "|cff00ff00" .. L["New"] .. "|r" end
    local color, label
    if res.pct >= BIG_PCT then color, label = "|cff00ff00", L["BIG"]
    elseif res.pct >= MID_PCT then color, label = "|cffffd100", L["mid"]
    else color, label = "|cffaaaaaa", L["small"] end
    return string_format("%s+%.0f%% %s|r", color, res.pct, label)
end

-- "(completes 3-pc set)" / "(breaks 2-pc set)" after an upgrade.
local function SetNote(res)
    if res.setGain then return " |cff00ff00" .. string_format(L["(completes %d-pc set)"], res.setGain) .. "|r" end
    if res.setBreak then return " |cffff5555" .. string_format(L["(breaks %d-pc set)"], res.setBreak) .. "|r" end
    return ""
end

local function WhenText(res)
    if res.atLevel then return "|cffff8800" .. string_format(L["at %d"], res.atLevel) .. "|r" end
    return "|cff00ff00" .. L["now"] .. "|r"
end

local function SortKey(res) return res.pct or 1e9 end

local function InScope(alt)
    if not DB.settings.SameRealm then return true end
    return alt.realm == GetRealmName() and alt.faction == UnitFactionGroup("player")
end

-- All alts (not the current character) that this item upgrades, biggest first.
local function UpgradesFor(link)
    local mscRev = MSC.ScoringRevision or 0
    local hit = Roster.cache[link]
    if hit and hit.mscRev == mscRev then return hit.list end

    local info = ItemInfo(link)
    if not info then return nil end
    local me = PlayerKey()
    local list = {}
    -- Set when some alt-side item data wasn't loaded yet: don't cache then.
    Roster.missing = false
    for key, alt in pairs(DB.chars) do
        if key ~= me and InScope(alt) and not DB.tooltipOff[key] and (DB.settings.ShowFuture or (info.reqLevel or 0) <= (alt.level or 0)) then
            local res = JudgeForAlt(alt, link, info)
            if res.state == "up" then
                res.alt = alt
                list[#list + 1] = res
            end
        end
    end
    table_sort(list, function(a, b) return SortKey(a) > SortKey(b) end)
    if Roster.missing then return list end

    if Roster.cacheSize > 400 then wipe(Roster.cache); Roster.cacheSize = 0 end
    Roster.cache[link] = { mscRev = mscRev, list = list }
    Roster.cacheSize = Roster.cacheSize + 1
    return list
end

-- =========================================================================
-- 6. TOOLTIP
-- =========================================================================
local function TooltipItemLink(tooltip)
    if MSC_GetTooltipItem then return select(2, MSC_GetTooltipItem(tooltip)) end
    if tooltip.GetItem then return select(2, tooltip:GetItem()) end
end

-- Soulbound, or binds when picked up: it can't be handed to an alt.
local function IsBound(tooltip, info)
    if info.bindType == 1 or info.bindType == 4 then return true end
    local name = tooltip:GetName()
    if not name then return false end
    for i = 2, math.min(tooltip:NumLines(), 8) do
        local fs = _G[name .. "TextLeft" .. i]
        local text = fs and fs:GetText()
        -- Forever can hand back protected ("secret") text that errors when compared.
        if type(text) == "string" and not (MSC_IsSecret and MSC_IsSecret(text))
            and (text == ITEM_SOULBOUND or text == ITEM_BIND_ON_PICKUP or text == ITEM_BIND_QUEST) then
            return true
        end
    end
    return false
end

-- Drawn right away (not deferred): some tooltips (crafting results, bag items) are
-- re-set every frame or so, which wipes lines added a frame late. Ordering under the
-- Judge's Score comes from registering after the core (see the hooks below).
local function DrawTooltip(tooltip)
    if Roster.suppressTooltip then
        -- The grid's own hover tooltips: mark them done so a deferred call skips them too.
        tooltip.sgjRosterLink = TooltipItemLink(tooltip)
        return
    end
    if not DB or not DB.settings.ShowTooltip then return end
    if not MSC or not MSC.SafeGetItemStats then return end
    local link = TooltipItemLink(tooltip)
    if not link or tooltip.sgjRosterLink == link then return end
    if not IsEquippableItem(link) then return end
    local info = ItemInfo(link)
    if not info then return end  -- the core re-sets the tooltip once the item loads
    -- Tooltips still being built: the core waits a frame too, and its timer was queued first.
    if not tooltip:IsVisible() then
        C_Timer.After(0, function() if tooltip:IsVisible() then DrawTooltip(tooltip) end end)
        return
    end
    tooltip.sgjRosterLink = link
    -- Gear you're wearing: list better items already waiting for that slot instead.
    if Roster.DrawOwnWaiting and Roster.DrawOwnWaiting(tooltip, link) then return end
    if DB.settings.BoEOnly and IsBound(tooltip, info) then return end

    local list = UpgradesFor(link)
    if not list or #list == 0 then return end

    tooltip:AddLine(" ")
    tooltip:AddLine("|cff00ccff" .. L["Roster upgrades:"] .. "|r")
    local max = DB.settings.MaxLines or DEFAULTS.MaxLines
    for i, res in ipairs(list) do
        if i > max then
            tooltip:AddLine("|cff888888" .. string_format(L["...and %d more"], #list - max) .. "|r")
            break
        end
        local alt = res.alt
        local left = "  " .. ColoredName(alt) .. " |cff888888(" .. SpecLabel(alt.specs[res.spec]) .. " " .. (alt.level or "?") .. ")|r"
        local days = DaysOld(alt)
        if days >= STALE_DAYS then left = left .. " |cff666666" .. string_format(L["%dd old"], days) .. "|r" end
        tooltip:AddDoubleLine(left .. SetNote(res), TierText(res) .. " |cff888888-|r " .. WhenText(res), 1, 1, 1, 1, 1, 1)
    end
    tooltip:Show()
end

local function HookTooltip(tt)
    if not tt or tt.sgjRosterHooked then return end
    tt.sgjRosterHooked = true
    if tt:HasScript("OnTooltipSetItem") then tt:HookScript("OnTooltipSetItem", DrawTooltip) end
    if tt:HasScript("OnTooltipCleared") then tt:HookScript("OnTooltipCleared", function(self) self.sgjRosterLink = nil end) end
end

-- Hooked at PLAYER_LOGIN, like the core's TooltipDataProcessor callback: callbacks run
-- in registration order, and this frame's PLAYER_LOGIN comes after the core's (Roster
-- loads after it), so Roster's lines always come after the Judge's Score.
do
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("PLAYER_LOGIN")
    hookFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        HookTooltip(GameTooltip)
        HookTooltip(ItemRefTooltip)
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
            TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tooltip)
                if tooltip == GameTooltip or tooltip == ItemRefTooltip then DrawTooltip(tooltip) end
            end)
        end
    end)
end

-- =========================================================================
-- 7. GRID PAGE (tab in the Gear Judge window)
-- =========================================================================
local LABEL_W, COL_W, ROW_H, HEAD_H, GRID_TOP = 100, 140, 22, 40, -116
local page, cols, rowFrames, firstCol, checkLink = nil, {}, {}, 1, nil
local extraRows = { "TOTAL", "CHECK", "UPDATED" }

local function SortedAlts()
    local me = PlayerKey()
    local list = {}
    for key, alt in pairs(DB.chars) do
        if key == me or InScope(alt) then list[#list + 1] = { key = key, alt = alt, me = (key == me) } end
    end
    table_sort(list, function(a, b)
        if a.me ~= b.me then return a.me end
        if (a.alt.level or 0) ~= (b.alt.level or 0) then return (a.alt.level or 0) > (b.alt.level or 0) end
        return (a.alt.name or "") < (b.alt.name or "")
    end)
    return list
end

local function ShownSpec(alt)
    if alt.shown and alt.specs and alt.specs[alt.shown] then return alt.shown end
    return alt.active
end

local function SpecKeys(alt)
    local keys = {}
    for k in pairs(alt.specs or {}) do keys[#keys + 1] = k end
    table_sort(keys)
    return keys
end

StaticPopupDialogs["SGJ_ROSTER_DELETE"] = {
    text = L["Remove %s from the Roster?"],
    button1 = YES, button2 = NO,
    OnAccept = function(self, data)
        if DB and data then
            DB.chars[data], DB.mailed[data], DB.tooltipOff[data] = nil, nil, nil
            BumpRevision()
            if Roster.RefreshPage then Roster.RefreshPage() end
        end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

local function SetCheckLink(link)
    checkLink = link
    if Roster.RefreshPage then Roster.RefreshPage() end
end

-- An item tooltip inside the grid: no Roster lines. The core's Judge's Score stays
-- (handy: how would this alt's item do on the character you're on?).
local function ShowGridItemTooltip(link)
    Roster.suppressTooltip = true
    pcall(GameTooltip.SetHyperlink, GameTooltip, link)
    Roster.suppressTooltip = false
end

-- True when the core added its Judge's Score block to the tooltip.
local function HasJudgeScore(tooltip)
    local label = MSC.L and MSC.L["Judge's Score:"]
    local name = tooltip:GetName()
    if not (label and name) then return false end
    for i = 2, tooltip:NumLines() do
        local fs = _G[name .. "TextLeft" .. i]
        local text = fs and fs:GetText()
        if type(text) == "string" and not (MSC_IsSecret and MSC_IsSecret(text)) and string_find(text, label, 1, true) then
            return true
        end
    end
    return false
end

local function CellOnEnter(self)
    if not self.link and not self.stashList then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.link then
        ShowGridItemTooltip(self.link)
        if self.scoreText then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("|cff00ccff" .. string_format(L["Roster score (%s):"], self.specText or "?") .. "|r", self.scoreText, 1, 1, 1, 1, 1, 1)
        end
        if HasJudgeScore(GameTooltip) then
            local me = (MSC.GetCharacterName and MSC.GetCharacterName()) or UnitName("player")
            GameTooltip:AddLine("|cff888888" .. string_format(L["Judge's Score above is for %s."], me) .. "|r", 1, 1, 1, true)
        end
    else
        GameTooltip:AddLine(L["Empty slot"], 1, 0.82, 0)
    end
    if self.stashList then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ccff" .. L["Better items waiting:"] .. "|r")
        for _, x in ipairs(self.stashList) do
            local where = WhereText(x.it.where)
            local lvl = (x.it.req or 0) > (self.altLevel or 0) and (" |cffff8800" .. string_format(L["at %d"], x.it.req) .. "|r") or ""
            GameTooltip:AddDoubleLine("  " .. x.it.link .. " |cff888888(" .. where .. ")|r", string_format("%.1f", x.score) .. lvl, 1, 1, 1, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

-- Stashed items that beat what's in this slot, best first.
local function StashFor(owned, slotId, equippedScore)
    local key = (slotId == 12 and 11) or (slotId == 14 and 13) or slotId
    local list
    for _, it in ipairs(owned) do
        local sc = it.scores and it.scores[key]
        if sc and sc > equippedScore + 0.05 then
            list = list or {}
            list[#list + 1] = { it = it, score = sc }
        end
    end
    if list then table_sort(list, function(a, b) return a.score > b.score end) end
    return list
end

-- Hovering gear the logged-in character is wearing: better items already waiting
-- for that slot (mail on the way or in the inbox, bags, bank), best first, with
-- how much each adds. Returns true for worn items (they never get alt lines).
function Roster.DrawOwnWaiting(tooltip, link)
    local slotId
    for _, s in ipairs(GEAR_SLOTS) do
        if GetInventoryItemLink("player", s) == link then slotId = s; break end
    end
    if not slotId then return false end
    local me = DB.chars[PlayerKey()]
    local sd = me and me.specs and me.specs[me.active]
    local e = sd and sd.slots and sd.slots[slotId]
    if not e then return true end
    local list = StashFor(OwnedFor(me, me.active, sd), slotId, e.score)
    if not list then return true end
    tooltip:AddLine(" ")
    tooltip:AddLine("|cff00ccff" .. L["Better items waiting:"] .. "|r")
    for i, x in ipairs(list) do
        if i > 3 then break end
        local lvl = (x.it.req or 0) > (me.level or 0) and (" |cffff8800" .. string_format(L["at %d"], x.it.req) .. "|r") or ""
        tooltip:AddDoubleLine("  " .. x.it.link .. " |cff888888(" .. WhereText(x.it.where) .. ")|r",
            "|cff00ff00+" .. string_format("%.1f", x.score - e.score) .. "|r" .. lvl, 1, 1, 1, 1, 1, 1)
    end
    tooltip:Show()
    return true
end

local function CreateColumn(parent, index)
    local col = {}
    local x = LABEL_W + (index - 1) * COL_W

    local head = CreateFrame("Button", nil, parent)
    head:SetSize(COL_W - 4, HEAD_H)
    head:SetPoint("TOPLEFT", x, GRID_TOP)
    head.bg = head:CreateTexture(nil, "BACKGROUND"); head.bg:SetAllPoints(); head.bg:SetColorTexture(1, 1, 1, 0.05)
    head.name = head:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head.name:SetPoint("TOPLEFT", 4, -4); head.name:SetPoint("TOPRIGHT", -30, -4); head.name:SetJustifyH("LEFT"); head.name:SetWordWrap(false)
    head.sub = head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    head.sub:SetPoint("TOPLEFT", head.name, "BOTTOMLEFT", 0, -3); head.sub:SetPoint("RIGHT", -4, 0); head.sub:SetJustifyH("LEFT"); head.sub:SetWordWrap(false)
    head.sub:SetTextColor(0.7, 0.7, 0.7)
    head:SetScript("OnClick", function(self)
        local alt = self.alt
        if not alt then return end
        local keys = SpecKeys(alt)
        if #keys < 2 then return end
        local cur = ShownSpec(alt)
        for i, k in ipairs(keys) do
            if k == cur then alt.shown = keys[(i % #keys) + 1]; break end
        end
        Roster.RefreshPage()
    end)
    head:SetScript("OnEnter", function(self)
        local alt = self.alt
        if not alt then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ColoredName(alt) .. " |cff888888- " .. (alt.realm or "") .. "|r")
        GameTooltip:AddLine(string_format(L["Level %d"], alt.level or 0), 1, 1, 1)
        local cur = ShownSpec(alt)
        for _, k in ipairs(SpecKeys(alt)) do
            local sd = alt.specs[k]
            local mark = (k == cur) and "|cff00ff00> |r" or "   "
            local tag = (k == alt.active) and (" |cff888888" .. L["(active)"] .. "|r") or ""
            GameTooltip:AddLine(mark .. (sd.groupName and (sd.groupName .. ": ") or "") .. (sd.pretty or k) .. tag, 0.8, 0.8, 0.8)
        end
        if #SpecKeys(alt) > 1 then GameTooltip:AddLine(L["Click to switch spec."], 0.5, 0.5, 0.5) end
        GameTooltip:AddLine(string_format(L["Updated %s"], date("%Y-%m-%d %H:%M", alt.updated or 0)), 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    head:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local del = CreateFrame("Button", nil, head)
    del:SetSize(12, 12); del:SetPoint("TOPRIGHT", -2, -3)
    del.text = del:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); del.text:SetPoint("CENTER"); del.text:SetText("x")
    del.text:SetTextColor(0.6, 0.6, 0.6)
    del:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 0.3, 0.3)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(L["Remove from the Roster"]); GameTooltip:Show()
    end)
    del:SetScript("OnLeave", function(self) self.text:SetTextColor(0.6, 0.6, 0.6); GameTooltip:Hide() end)
    del:SetScript("OnClick", function()
        local alt = head.alt
        if alt then
            StaticPopup_Show("SGJ_ROSTER_DELETE", alt.name or "?", nil, head.key)
        end
    end)
    head.del = del

    -- Show this alt on item tooltips?
    local tip = CreateFrame("CheckButton", nil, head, "UICheckButtonTemplate")
    tip:SetSize(18, 18); tip:SetPoint("RIGHT", del, "LEFT", -1, 0)
    tip:SetScript("OnClick", function(self)
        if not head.key then return end
        DB.tooltipOff[head.key] = (not self:GetChecked()) or nil
        BumpRevision()
    end)
    tip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Show on item tooltips"])
        GameTooltip:AddLine(L["Untick to leave this character out of the Roster lines on tooltips. It stays in the grid."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    head.tip = tip
    col.head = head

    col.cells = {}
    local nRows = #GEAR_SLOTS + #extraRows
    for r = 1, nRows do
        local cell = CreateFrame("Button", nil, parent)
        cell:SetSize(COL_W - 4, ROW_H - 2)
        cell:SetPoint("TOPLEFT", x, GRID_TOP - HEAD_H - 4 - (r - 1) * ROW_H)
        cell.bg = cell:CreateTexture(nil, "BACKGROUND"); cell.bg:SetAllPoints(); cell.bg:SetColorTexture(0, 0, 0, 0)
        cell.icon = cell:CreateTexture(nil, "ARTWORK"); cell.icon:SetSize(16, 16); cell.icon:SetPoint("LEFT", 3, 0)
        cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell.text:SetPoint("LEFT", 23, 0); cell.text:SetPoint("RIGHT", -3, 0); cell.text:SetJustifyH("LEFT"); cell.text:SetWordWrap(false)
        cell:SetScript("OnEnter", CellOnEnter)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        col.cells[r] = cell
    end
    return col
end

local function FillColumn(col, entry, judge)
    local head = col.head
    local alt = entry.alt
    head.alt, head.key = alt, entry.key
    head.name:SetText(ColoredName(alt) .. (entry.me and (" |cff888888" .. L["(you)"] .. "|r") or ""))
    local spec = ShownSpec(alt)
    local sd = alt.specs and alt.specs[spec]
    local nSpecs = #SpecKeys(alt)
    head.sub:SetText(string_format(L["Lv %d"], alt.level or 0) .. "  " .. SpecLabel(sd) .. (nSpecs > 1 and " |cff00ccff*|r" or ""))
    head.del:SetShown(not entry.me)
    head.tip:SetShown(not entry.me)
    head.tip:SetChecked(not DB.tooltipOff[entry.key])
    head:Show()

    local slots = sd and sd.slots or {}
    local owned = sd and OwnedFor(alt, spec, sd) or {}
    local filled, sum = 0, 0
    for _, e in pairs(slots) do filled = filled + 1; sum = sum + (e.score or 0) end
    local avg = filled > 0 and sum / filled or 0

    for r, slotId in ipairs(GEAR_SLOTS) do
        local cell = col.cells[r]
        local e = slots[slotId]
        cell.link, cell.scoreText = nil, nil
        cell.stashList = StashFor(owned, slotId, e and e.score or 0)
        cell.altLevel = alt.level
        local mark = cell.stashList and " |cff00ccff+|r" or ""
        cell.bg:SetColorTexture(0, 0, 0, 0)
        if e then
            cell.link = e.link
            cell.icon:SetTexture(select(5, GetItemInfoInstant(e.link)))
            cell.icon:Show()
            local weak = avg > 0 and e.score < avg * 0.5
            cell.text:SetText((weak and "|cffff9933" or "|cffffffff") .. string_format("%.1f", e.score) .. "|r" .. mark)
            cell.scoreText = string_format("%.1f", e.score)
            cell.specText = SpecLabel(sd)
        elseif slotId == 17 and slots[16] and slots[16].twoHand then
            cell.icon:Hide()
            cell.text:SetText("|cff666666" .. L["(two-hander)"] .. "|r")
        else
            cell.icon:Hide()
            cell.text:SetText("|cffff5555" .. L["empty"] .. "|r" .. mark)
            cell.bg:SetColorTexture(1, 0, 0, 0.06)
        end
        if judge and judge.slot == slotId then cell.bg:SetColorTexture(1, 0.82, 0, 0.18) end
        cell:Show()
    end

    local base = #GEAR_SLOTS
    local total, check, upd = col.cells[base + 1], col.cells[base + 2], col.cells[base + 3]
    for _, c in ipairs({ total, check, upd }) do c.icon:Hide(); c.link = nil; c.scoreText = nil; c.stashList = nil; c.bg:SetColorTexture(0, 0, 0, 0); c:Show() end
    total.text:SetText("|cffffd100" .. string_format("%.1f", sd and sd.total or 0) .. "|r")

    if not checkLink then
        check:Hide()
    elseif not judge then
        check.text:SetText("|cff888888" .. L["loading..."] .. "|r")
    elseif judge.state == "cant" then
        check.text:SetText("|cff888888" .. L["can't use"] .. "|r")
    elseif judge.state == "none" then
        check.text:SetText("|cffaaaaaa" .. L["no upgrade"] .. "|r")
    elseif judge.state == "stashed" then
        local where = HasBetterText(judge.stash and judge.stash.where)
        check.text:SetText("|cff00ccff" .. where .. "|r")
        check.link = judge.stash and judge.stash.link
    else
        local when = judge.atLevel and (" |cffff8800" .. string_format(L["at %d"], judge.atLevel) .. "|r") or ""
        check.text:SetText(TierText(judge) .. when)
        check.bg:SetColorTexture(0, 1, 0, 0.08)
    end

    local days = DaysOld(alt)
    local dayText = (days == 0) and L["today"] or string_format(L["%dd ago"], days)
    upd.text:SetText((days >= STALE_DAYS and "|cffff5555" or "|cff888888") .. dayText .. "|r")
end

local function RefreshPage()
    if not page or not page:IsVisible() or not DB then return end
    local list = SortedAlts()
    local visible = math_max(1, math_floor((page:GetWidth() - LABEL_W - 8) / COL_W))
    if firstCol > math_max(1, #list - visible + 1) then firstCol = math_max(1, #list - visible + 1) end

    local info = checkLink and ItemInfo(checkLink)
    page.checkIcon:SetTexture(checkLink and select(5, GetItemInfoInstant(checkLink)) or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    page.checkName:SetText(checkLink and (select(1, GetItemInfo(checkLink)) and checkLink or L["loading..."]) or ("|cff888888" .. L["Drop or shift-click an item here"] .. "|r"))

    for i = 1, math_max(visible, #cols) do
        local entry = list[firstCol + i - 1]
        if i <= visible and entry then
            cols[i] = cols[i] or CreateColumn(page.grid, i)
            local judge = info and JudgeForAlt(entry.alt, checkLink, info, ShownSpec(entry.alt)) or nil
            FillColumn(cols[i], entry, judge)
        elseif cols[i] then
            cols[i].head:Hide()
            for _, c in ipairs(cols[i].cells) do c:Hide() end
        end
    end

    rowFrames.CHECK:SetShown(checkLink ~= nil)
    page.prev:SetEnabled(firstCol > 1)
    page.next:SetEnabled(firstCol + visible - 1 < #list)
    page.pageText:SetText(#list > visible and string_format(L["%d-%d of %d"], firstCol, math.min(#list, firstCol + visible - 1), #list) or "")
    page.empty:SetShown(#list == 0)
end
Roster.RefreshPage = RefreshPage

local function Checkbox(parent, label, key, anchor, x)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("LEFT", anchor, x and "LEFT" or "RIGHT", x or 8, 0)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb.label:SetText(label)
    cb:SetScript("OnShow", function(self) self:SetChecked(DB and DB.settings[key]) end)
    cb:SetScript("OnClick", function(self)
        DB.settings[key] = self:GetChecked() and true or false
        BumpRevision(); RefreshPage()
    end)
    return cb, cb.label
end

local function BuildPage(parent)
    page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    page:Hide()

    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText(L["Roster"])
    title:SetTextColor(1, 0.82, 0)

    local sub = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetWidth(470); sub:SetJustifyH("LEFT"); sub:SetTextColor(0.7, 0.7, 0.7)
    sub:SetText(L["Every character's gear, scored for its own spec. Log in on each alt once to add it."])

    -- Item check slot (top right)
    local check = CreateFrame("Button", nil, page)
    check:SetSize(34, 34)
    check:SetPoint("TOPRIGHT", -16, -14)
    page.checkIcon = check:CreateTexture(nil, "ARTWORK"); page.checkIcon:SetAllPoints()
    local border = check:CreateTexture(nil, "OVERLAY"); border:SetAllPoints(); border:SetColorTexture(1, 0.82, 0, 0.15)
    check:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local function TakeCursor()
        local kind, _, link = GetCursorInfo()
        if kind == "item" and link then ClearCursor(); SetCheckLink(link); return true end
    end
    check:SetScript("OnReceiveDrag", TakeCursor)
    check:SetScript("OnClick", function(_, button)
        if button == "RightButton" then SetCheckLink(nil) else TakeCursor() end
    end)
    check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if checkLink then
            ShowGridItemTooltip(checkLink)
            GameTooltip:AddLine(L["Right-click to clear."], 0.5, 0.5, 0.5)
        else
            GameTooltip:SetText(L["Check an item"])
            GameTooltip:AddLine(L["Drag an item here, or shift-click one in your bags, to see how much it upgrades each character."], 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", function() GameTooltip:Hide() end)

    page.checkName = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    page.checkName:SetPoint("RIGHT", check, "LEFT", -8, 0)
    page.checkName:SetJustifyH("RIGHT"); page.checkName:SetWidth(240); page.checkName:SetWordWrap(false)

    -- Options, on two rows so translated labels fit: tooltip options, then scope
    local row1 = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row1:SetPoint("TOPLEFT", 16, -74)
    row1:SetText("")
    local row2 = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row2:SetPoint("TOPLEFT", 16, -96)
    row2:SetText("")
    local _, l1 = Checkbox(page, L["Tooltip lines"], "ShowTooltip", row1, -4)
    local _, l2 = Checkbox(page, L["Tradeable (BoE) items only"], "BoEOnly", l1)
    local _, l3 = Checkbox(page, L["This realm and faction only"], "SameRealm", row2, -4)
    Checkbox(page, L["Include higher-level items"], "ShowFuture", l3)

    local topN = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    topN:SetSize(130, 20)
    topN:SetPoint("LEFT", l2, "RIGHT", 16, 0)
    local function TopNText() topN:SetText(string_format(L["Tooltip: top %d"], DB.settings.MaxLines or DEFAULTS.MaxLines)) end
    topN:SetScript("OnShow", TopNText)
    topN:SetScript("OnClick", function()
        local cur, nextVal = DB.settings.MaxLines or DEFAULTS.MaxLines, MAX_LINE_CHOICES[1]
        for i, v in ipairs(MAX_LINE_CHOICES) do
            if v == cur then nextVal = MAX_LINE_CHOICES[i % #MAX_LINE_CHOICES + 1]; break end
        end
        DB.settings.MaxLines = nextVal
        TopNText()
    end)
    topN:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Alts per tooltip"])
        GameTooltip:AddLine(L["How many characters to list on an item's tooltip, biggest upgrades first. Click to change."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    topN:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Grid
    page.grid = CreateFrame("Frame", nil, page)
    page.grid:SetAllPoints()

    local function RowLabel(r, text)
        local f = CreateFrame("Frame", nil, page.grid)
        f:SetPoint("TOPLEFT", 8, GRID_TOP - HEAD_H - 4 - (r - 1) * ROW_H)
        f:SetPoint("RIGHT", page, "RIGHT", -8, 0)
        f:SetHeight(ROW_H - 2)
        local shade = f:CreateTexture(nil, "BACKGROUND", nil, -1); shade:SetAllPoints()
        shade:SetColorTexture(1, 1, 1, (r % 2 == 0) and 0.03 or 0)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", 4, 0); fs:SetWidth(LABEL_W - 12); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        fs:SetText(text)
        return f
    end
    for r, slotId in ipairs(GEAR_SLOTS) do RowLabel(r, SLOT_LABELS[slotId] or tostring(slotId)) end
    local base = #GEAR_SLOTS
    rowFrames.TOTAL = RowLabel(base + 1, L["Total"])
    rowFrames.CHECK = RowLabel(base + 2, L["This item"])
    rowFrames.UPDATED = RowLabel(base + 3, L["Updated"])

    -- Paging
    page.prev = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    page.prev:SetSize(24, 20); page.prev:SetText("<")
    page.prev:SetPoint("TOPLEFT", 16, GRID_TOP - 10)
    page.prev:SetScript("OnClick", function() firstCol = math_max(1, firstCol - 1); RefreshPage() end)
    page.next = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    page.next:SetSize(24, 20); page.next:SetText(">")
    page.next:SetPoint("LEFT", page.prev, "RIGHT", 4, 0)
    page.next:SetScript("OnClick", function() firstCol = firstCol + 1; RefreshPage() end)
    page.pageText = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    page.pageText:SetPoint("TOPLEFT", page.prev, "BOTTOMLEFT", 0, -2)

    page.empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    page.empty:SetPoint("CENTER")
    page.empty:SetText(L["No characters saved yet."])

    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(_, delta)
        firstCol = math_max(1, firstCol - delta); RefreshPage()
    end)
    page:SetScript("OnShow", function()
        -- Refresh this character first, so manual spec changes show up.
        pcall(TakeSnapshot)
        RefreshPage()
    end)

    MSC.ViewRoster = page
    MSC.UpdateRosterView = RefreshPage
end

local tabId
if MSC and MSC.RegisterPluginTab then
    tabId = MSC.RegisterPluginTab(L["Roster"], "Interface\\Icons\\Spell_Holy_PrayerOfFortitude", BuildPage, "ViewRoster", "UpdateRosterView")
end

-- Shift-click an item anywhere while the page is open: check it.
if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if page and page:IsVisible() and IsShiftKeyDown() and type(link) == "string" and string_find(link, "item:", 1, true) then
            if IsEquippableItem(link) then SetCheckLink(link) end
        end
    end)
end

-- =========================================================================
-- 8. MAIL SENT TO YOUR OWN CHARACTERS
-- Attachments are read when SendMail is called and committed once the send
-- succeeds (MAIL_FAILED drops them). Only recipients already in the Roster
-- are tracked; the entry lasts until that character opens its mailbox.
-- =========================================================================
local pendingMail

local function RecipientKey(name)
    if type(name) ~= "string" or name == "" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    local n, r = string_match(name, "^([^%-]+)%-(.+)$")
    n = string.lower(n or name)
    r = r and string.lower(r:gsub("%s", "")) or nil
    local myRealm = string.lower((GetRealmName() or ""):gsub("%s", ""))
    for key, alt in pairs(DB.chars) do
        local altRealm = string.lower((alt.realm or ""):gsub("%s", ""))
        if string.lower(alt.name or "") == n and altRealm == (r or myRealm) then return key end
    end
    return nil
end

if SendMail and GetSendMailItemLink then
    hooksecurefunc("SendMail", function(recipient)
        pendingMail = nil
        if not DB then return end
        local key = RecipientKey(recipient)
        if not key or key == PlayerKey() then return end
        local links = {}
        for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
            local link = GetSendMailItemLink(i)
            if link and IsEquippableItem(link) then links[#links + 1] = link end
        end
        if #links > 0 then pendingMail = { key = key, links = links } end
    end)
end

local function CommitMail()
    if not (pendingMail and DB) then return end
    local list = DB.mailed[pendingMail.key] or {}
    for _, link in ipairs(pendingMail.links) do list[#list + 1] = { link = link, sent = time() } end
    DB.mailed[pendingMail.key] = list
    pendingMail = nil
    BumpRevision()
    if Roster.RefreshPage then Roster.RefreshPage() end
end

-- =========================================================================
-- 9. SLASH COMMAND & EVENTS
-- =========================================================================
SLASH_SGJROSTER1 = "/roster"
SLASH_SGJROSTER2 = "/sgjroster"
SlashCmdList["SGJROSTER"] = function()
    if MSC and MSC.OpenMainWindow and tabId then MSC.OpenMainWindow(tabId) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("BANKFRAME_OPENED")
ev:RegisterEvent("MAIL_SHOW")
ev:RegisterEvent("MAIL_CLOSED")
ev:RegisterEvent("MAIL_INBOX_UPDATE")
ev:RegisterEvent("MAIL_SEND_SUCCESS")
ev:RegisterEvent("MAIL_FAILED")
ev:RegisterEvent("BANKFRAME_CLOSED")
ev:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
for _, e in ipairs({ "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "TRAIT_CONFIG_UPDATED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        if type(SGJ_RosterDB) ~= "table" then SGJ_RosterDB = {} end
        DB = SGJ_RosterDB
        if type(DB.chars) ~= "table" then DB.chars = {} end
        -- Entries from before GUID keys ("Name-Realm") are dropped: on WoW Forever several
        -- characters shared one first-name key. Each character is re-added at its next login.
        for _, t in ipairs({ DB.chars, type(DB.mailed) == "table" and DB.mailed or {}, type(DB.tooltipOff) == "table" and DB.tooltipOff or {} }) do
            for k in pairs(t) do
                if type(k) ~= "string" or not k:find("^Player%-") then t[k] = nil end
            end
        end
        if type(DB.settings) ~= "table" then DB.settings = {} end
        if type(DB.tooltipOff) ~= "table" then DB.tooltipOff = {} end
        if type(DB.mailed) ~= "table" then DB.mailed = {} end
        for k, v in pairs(DEFAULTS) do
            if DB.settings[k] == nil then DB.settings[k] = v end
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif not DB then
        return
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- The checked item (or an alt's gear icon) just loaded.
        if page and page:IsVisible() and not Roster.refreshQueued then
            Roster.refreshQueued = true
            C_Timer.After(0.3, function() Roster.refreshQueued = false; RefreshPage() end)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        RequestSnapshot(6)     -- talents and the core's weights settle after login
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        RequestSnapshot(2)
    elseif event == "MAIL_SEND_SUCCESS" then
        CommitMail()
    elseif event == "MAIL_FAILED" then
        pendingMail = nil
    elseif event == "MAIL_SHOW" then
        Roster.mailOpen, Roster.inboxLoaded = true, false
    elseif event == "MAIL_INBOX_UPDATE" then
        if Roster.mailOpen then
            Roster.inboxLoaded = true
            RequestSnapshot(1)
        end
    elseif event == "MAIL_CLOSED" then
        -- Same as the bank: one last read while the inbox is still loaded.
        if Roster.mailOpen and not InCombatLockdown() then pcall(TakeSnapshot) end
        Roster.mailOpen, Roster.inboxLoaded = false, false
    elseif event == "BANKFRAME_OPENED" then
        Roster.bankOpen = true
        RequestSnapshot(1)
    elseif event == "BANKFRAME_CLOSED" then
        -- Save once more while the bank is still readable (catches deposits made
        -- just before closing); later snapshots keep this bank list.
        if Roster.bankOpen and not InCombatLockdown() then pcall(TakeSnapshot) end
        Roster.bankOpen = false
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYERBANKSLOTS_CHANGED" then
        RequestSnapshot(3)
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
        -- After a gear-set swap and the core saving the new spec's gear (about 5 s).
        RequestSnapshot(7)
    else
        RequestSnapshot(3)
    end
end)
