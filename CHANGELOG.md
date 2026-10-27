# Sharpie's Gear Judge [Roster] - Version History

## 🚀 v1.0.4

### 🎨 New Look
- Matches Gear Judge's new window: colored section titles, slimmer bars and your class color as the accent.

### 🔀 Off-Specs for Alts
- Each alt's off-specs (ticked in the Gear Judge's Off-Specs settings on that alt) are judged against the best gear it owns for them, bags and bank included, so a healing drop shows for a Feral Druid alt's healing set.
- Dual Specialization alts on Season of Discovery and TBC Anniversary now save both specs.

## 🚀 v1.0.3

### 🔄 Out-of-Date Characters Flagged
- Each character is scored with the weights saved the last time you logged into it. After a Gear Judge update changes the weights, characters you haven't logged into since still use the old ones, so their upgrade percentages can differ from what they'd show logged in. Those characters now say **needs login** next to their name in tooltips and the BoE Finder, and in place of the "updated" date on the Roster grid. Logging into the character once refreshes it.

### 🙋 You in the List
- When an item upgrades one of your other characters, the tooltip's Roster list now includes the character you're on too, marked **(you)** and measured against what you're wearing, so you can see who gains most in one ranked list. It isn't shown when no other character is listed, since the Gear Judge Upgrade line above already covers that.

## 🚀 v1.0.2

### 🔎 BoE Finder
- **New: BoE Finder**: A button on the Roster tab switches the grid to a list of every tradeable item your characters are holding (bags, plus bank and mailbox from their last visit) that upgrades another of your characters, biggest upgrade first. Each row shows the item, who holds it and where, the best character to send it to, and how many others it also upgrades.
- **Who Can Get It**: Only characters on the same realm and faction as the holder are suggested, since only they can be mailed it. Each is scored the same way as the tooltip lines: their own spec, talents and level, items they already own or have on the way, and set bonuses. Items above a character's level show **at X**, and are left out when Include higher-level items is off.
- **Soulbound Items Skipped**: Items already bound to the character holding them, and bind-on-pickup items, are never listed.
- Hover a row to see the item and every character it upgrades; shift-click it to link the item in chat. Bags update when you log in on a character, and the bank and mailbox when you open them.

## 🚀 v1.0.1

### ⚔️ PvP
- **Gear for PvP**: Turning Gear for PvP on or off updates this character's Roster entry right away. Your other characters pick it up the next time you log into them.

### 🔀 Dual Specialization
- **Both Specs Per Character**: WoW Forever unlocks a second spec at level 40. Roster now saves both specs of each character: the one you're in, and the other scored with its own talents, profile, Talents build and Gear for PvP setting against the gear you last wore in it. Tooltips can say "upgrade for <alt> (Secondary: Protection)", and clicking a character's name in the grid switches between its specs.
- Characters update when you log into them; a spec switch is saved a few seconds later, once a gear-set swap has finished.
- Nothing changes for characters with one spec. Dual Specialization can't be reached in the beta yet (level cap 30), so this has only been tested with simulated specs.

---

## 🚀 v1.0.0

### 🎉 First Release
Roster is for altoholics: it shows which of your other characters an item upgrades, and how much, so you know who should get that Bind on Equip drop.

### 🧾 Alt Upgrades on Tooltips
- **Roster Upgrades**: Tradeable items list which of your other characters they upgrade, biggest first, with the size of the upgrade (BIG, mid or small, as a share of that character's gear score) and whether it's usable now or only at a later level.
- **Short Tooltips**: Only the top 3 characters are listed by default (1, 2, 3, 5 or 10 on the Roster tab), and each character has a checkbox to leave it off tooltips entirely.
- **Upgrades Waiting for You**: Hovering gear you're wearing lists better items already waiting for that slot, in your mail (including items your other characters sent), bags or bank, with how much each adds and the level it needs.
- **Tradeable Items Only**: Bind on Pickup and soulbound items show no Roster lines, since they can't be sent to another character.

### 📊 The Roster Grid
- **Every Character at a Glance**: A new Roster tab in the Gear Judge window shows every character's gear and slot scores side by side, with empty and weak slots highlighted.
- **Check an Item**: Drag or shift-click an item onto the grid to see each character's upgrade and the slot it would replace.
- **Your Verdict Too**: Hovering an item in the grid also shows Gear Judge's score for the character you're logged in on, with a note saying whose verdict it is.
- **Options**: Tooltip lines on or off, tradeable (BoE) items only, this realm and faction only, and whether to include items above a character's level.

### 🎒 Bags, Bank and Mail
- **Gear Held for Later Counts**: Items a character is already holding count as theirs. If they'll have something better by the time they can wear the new item, it isn't shown as an upgrade, and the grid says "has better (bags)", "(bank)" or "(mail)".
- **Better Items Waiting**: Grid cells with a better item waiting are marked with a blue **+**; hover it to see the item.
- **Mail**: Items you mail to one of your own characters count for them as soon as the mail is sent. The bank and mailbox are saved each time that character opens them.

### ⚖️ Scored for Each Character
- **Their Own Weights**: Each character's spec, talents, level and tracked specs are saved when they log in, level up, change talents or change gear, and items are scored with those.
- **Set Bonuses**: An item that completes a set bonus for a character says so on the tooltip ("completes 2-pc set") and gets the bonus's value; one that breaks a set bonus loses it, and isn't shown unless it's still an upgrade.
- **Weapon Bonuses**: Class and racial weapon bonuses (Sword Specialization, Weaponmaster, Hack and Slash and so on) are scored with each character's own race, talents and level. Needs Sharpie's Gear Judge 3.2.1.
- **Relics**: Librams, idols and totems are scored with that character's own class data, even when you're logged in on another class. Needs Sharpie's Gear Judge 3.2.1.
- **Thrown Weapons (Forever)**: A thrown weapon judged for a Hunter scores on its stats only (Hunters can't attack with it), and for other classes includes its damage, whichever character you're logged in on.
- **Unique Items**: A second copy of a unique ring or trinket a character already wears isn't shown as an upgrade for it.
- **Scoring Options per Character**: Each character's gear is scored with the Enchant, Gem and Camping Buffs options that were set when it last logged in, so changing them on one character doesn't throw off the others.
- **Two-Part Names (Forever)**: Characters are told apart by their unique character ID, so names that share a first word ("Sharpie Hustlegear", "Sharpie Windfield") never mix.

### 🌍 Translations
- **Translated**: Roster is translated into every language WoW Forever launches with: German, Spanish (Spain and Latin America), French, Brazilian Portuguese, Russian, Korean and Traditional Chinese.
