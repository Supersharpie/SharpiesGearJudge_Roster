# Sharpie's Gear Judge [Roster] - Version History

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
