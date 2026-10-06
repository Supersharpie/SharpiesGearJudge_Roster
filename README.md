# Sharpie's Gear Judge - Roster (Alt Upgrades)

A plugin for **Sharpie's Gear Judge (SGJ)** for altoholics: see at a glance which of your other characters a BoE item would upgrade, and by how much.

## 🌟 Features

### 🧾 Alt Upgrades on Tooltips
- Hover any tradeable item and a **Roster upgrades** section lists every alt it upgrades, biggest first.
- Each line shows the alt's spec and level, the size of the upgrade (**BIG**, **mid** or **small**, as a percent of that alt's total gear score), and whether they can use it **now** or only **at level X**.
- Each alt's own spec, talents and level are taken into account: the item is scored with the same Gear Judge weights that alt uses on their own tooltips. Multi-spec (tracked specs) is included, and the best spec is shown.
- Soulbound and bind-on-pickup items are skipped by default, since they can't be sent to an alt.
- Only the **top 3** alts are listed by default (change it on the Roster tab), and any alt can be left off tooltips with the checkbox on its column.

### 🎒 Bags, Bank and Mail Count Too
- Gear an alt is holding for later counts as theirs. If they'll already have something better by the time they can wear the new item, it isn't shown as an upgrade.
- The bank is saved each time that character visits it, and the mailbox each time they open it.
- Items you mail to one of your own characters count for them straight away, before they log in. (Mail older than 30 days is dropped, since it will have been returned.)

### 📊 The Roster Grid
- A new **Roster** tab in the Gear Judge window: one column per character, one row per slot, with each item's icon and score.
- Empty slots and slots scoring well below the rest of that character's gear stand out, so you can see who needs gear most.
- **Check an item**: drag an item onto the check slot (or shift-click one in your bags while the tab is open) to see each character's upgrade, with the slot it would replace highlighted.
- A blue **+** on a cell means a better item for that slot is waiting in that character's bags, bank or mail (hover to see it).
- Click a character's name to switch between their saved specs. Remove old characters with the **x**.

## ⚙️ How It Works
- Each character saves a snapshot when they log in, level up, change talents or change gear. **Log in on each alt once** after installing to add them.
- Items are saved and scored by their full item link, so random-suffix items ("of the Bear" vs "of the Tiger") are always scored correctly.
- Data is shared across your account. By default only characters on the same realm and faction are shown.

## 💬 Chat Commands
- `/roster` or `/sgjroster` - open the Roster tab.

## 📝 Notes
- A snapshot is only as fresh as that character's last login. Characters not seen for a week are marked.
- Class weapon bonuses (such as racial weapon skills) and set bonuses aren't counted for alts.
