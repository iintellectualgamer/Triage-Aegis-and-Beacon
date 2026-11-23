# Triage - Aegis & Beacon 0.1.0

Initial public release. The updated install ZIP is Build 22.

Triage brings click casting, range alerts, group buff checks, and markers into one panel. Open the bundled **User-Manual.txt** for setup and testing. The PDF edition is a separate download.

## Install

1. Close World of Warcraft and extract the ZIP.
2. Copy the **TriageAegisBeacon** folder into the `Interface\AddOns` folder for your edition.

   - Retail uses `_retail_\Interface\AddOns`.
   - Forever uses `_forever_\Interface\AddOns`.
   - Expansion Classic and Classic Era typically use `_classic_` and `_classic_era_`.
     Use your launcher's game folder for your edition.

3. Check for `Interface\AddOns\TriageAegisBeacon\TriageAegisBeacon.toc`. Enable **Triage - Aegis & Beacon** on the character screen.
4. Log in and type `/triage version` to verify **0.1.0 / Build 22**, then type `/triage show` to open the panel. Use **Party**, **Raid**, **Markers**, or **Combined** to switch views. Use **-** to minimize, **+** to expand, and **X** to hide it. Left-click the gold minimap button to toggle the panel, right-click it for Settings, or drag it along the map rim outside combat.

For an update from an older Triage build, copy the new addon files over the existing **TriageAegisBeacon** folder with WoW closed. Character data lives in `WTF`.

## Beta game versions

| Client | Game versions |
| --- | --- |
| Midnight Retail | 12.0.0, 12.0.1, 12.0.5, 12.0.7, 12.1.0, 12.1.5, 12.1.7 |
| The War Within Retail | 11.2.0, 11.2.5, 11.2.7 |
| Dragonflight Retail | 10.2.7 |
| WoW Forever | 1.60.1 |
| Mists of Pandaria Classic | 5.5.0, 5.5.1, 5.5.2, 5.5.3, 5.5.4 |
| Cataclysm Classic | 4.4.0, 4.4.1, 4.4.2 |
| Wrath of the Lich King Classic | 3.4.3, 3.4.4, 3.4.5 |
| Wrath Titan Reforged | 3.80.0, 3.80.1, 3.80.2 |
| Burning Crusade Classic / Anniversary | 2.5.4, 2.5.5, 2.5.6 |
| WoW Classic Era / Hardcore / Season of Discovery | 1.15.3, 1.15.4, 1.15.5, 1.15.6, 1.15.7, 1.15.8, 1.15.9 |

The spell and talent picker adapts to the installed client. WoW controls the availability of world markers, Assist pings, pull countdowns, cleanse cues, Blizzard Click Casting, and group roles.

## Heal and mark

- Choose **All heals** or type `/triage heals` to see the learned healing spells, health-bar clicks, and keyboard shortcuts for your build. Select **Show all clicks** to search every active or disabled assignment by spell name, ID, or gesture. Select a row to edit its click. Auto clicks and Auto keys refresh as you learn abilities or change your build. Saved clicks and existing WoW keybinds take priority.
- **Emergency** on the healing panel and **Alt + right-click** on a health bar use the same spec-appropriate emergency spell. The icon shows the cooldown where the client supports it. The first keyboard choice is **Alt + E** when available. In combat, click the bar directly, select a living ally before clicking Emergency, or hover their bar and press the emergency shortcut.
- **Auto target** starts on. A friendly mouseover takes priority. Outside combat, pressing Emergency can then choose the lowest-health eligible group member in confirmed range. **Healing loadout** has separate switches for **Auto clicks**, **Auto keys**, and **Auto target**.
- **Assign spells** starts with plain Left-click, Middle-click, and Right-click. Toggle **Alt**, **Ctrl**, and **Shift** to edit any combination. Page through **Button 31** with the arrows. Pick a learned spell, type its name or ID, or drag it from the spellbook or action bar onto the field or **Pick**. Return the cursor icon or cancel the drag, then save.
- **Settings > Custom spells > Saved clicks** lists your active profile's saved gestures and their availability. Select a row to open its assignment field.
- **Pick → Browse spells and talents** searches the current character's healing, damage, tank, utility, racial, and pet abilities. View active or passive talents and inactive choices. Select an **Assignable** result, then save the original field. Availability follows WoW's active specialization and talent build.
- Type `/target` in any health-bar click field to select that unit. Use `None` to disable a click, including the default **Left-click** and **Alt + middle-click** selection. Try any gesture in **Settings > Practice**.
- Supported friendly spells on health bars select the clicked unit by default. To keep your current target while healing, clear **Target player on healing clicks** in **Mouse buttons**. The checkbox saves right away.
- **Settings > Spell icons** controls ten tiles across **Party**, **Raid**, and **Combined**. Plain Left, Middle, and Right are separate from modifier clicks. Tiles show the name, spell ID, gesture, and any assigned Triage keyboard shortcut. Hover for the full text.
- The **Target (/target)** tile shows which gesture selects a unit. **None** removes that gesture's tile and the row closes the gap. The two extra spell tiles and **Emergency** stay in the Extras row.
- **Combined** follows WoW's party or full raid roster and shows markers below it. Raid bars populate when Triage opens in an existing raid, including after a UI reload. **Party** displays your subgroup and shows a hint to reach the full raid.
- Use the view tabs, title controls, and gold minimap button during combat. **Settings** stays separate from the combat panel. Spell reassignments, scale, and protected layout changes apply after combat.
- **Appearance** has independent current health and percentage switches, panel opacity, priority players, party roles, combat tooltips, a thin hover outline, and a cleanse cue for readable dispel data.
- A red underline shows critical health. Blue, amber, and green strips show damage absorption, healing absorption, and incoming heals when the game supplies them. Offline, Dead, and Ghost labels appear when WoW exposes the state.
- Classic and Forever can show personal mana and threat plus colored threat edges on group bars. Forever and older Classic clients can also show the approximate five-second regeneration window. **Appearance** offers a game-managed Private Aura slot on supported Midnight and Forever clients.
- **Practice > Sample cues** lets you preview health and shield displays while checking your clicks.
- Hover over a healing bar to see the player's name when available and up to three plain mouse assignments. Open **Saved clicks** for all assignments.
- **Alert settings > Channels** displays separate automatic and manual buttons for **Current group**, **Whisper**, **Raid**, **Party**, **Instance**, **Say**, and **Battleground**. Enable the alerts you want and choose **Save alerts**. Automatic **Say** prepares a draft. Battleground uses instance chat. Optional native minimap pings, timing, and ping audio are in **Behavior**.
- Use a party member's **Notify** or a raid teammate's **!** for a manual alert. Right-click or middle-click it to choose a channel, including **Whisper this player**. The raid **!** brightens gently on hover. **Ping target** is the separate WoW Assist action.
- **Buff coverage** can announce every verified missing buff count once when a group or instance starts. Healer reminders and buff summaries begin with **[Triage - Aegis & Beacon]**. **Profiles** saves Dungeon and Raid presets and transfers your spell, mouse, and icon choices.
- **Quiet Group** in **All heals** pauses automatic chat, whispers, pings, and buff notices while keeping manual controls available. Automatic range and buff group chat share a 30-second delay.
- **Markers** places unit icons or aims ground markers with your click or keypress. The marker section fits in 24 fewer UI pixels of height. Right-click a world marker to clear it. Ready check and 10s pull follow WoW's group permissions.

## Quick commands

`/triage help` lists the slash commands. Use `/triage icons` for spell icons, `/triage practice` for click previews, and `/triage reset` to restore the initial panel position.

## Credits

Created by **iintellectualgamer**. Contact **iintellectualgamer@gmail.com**. The creator uses **iintellectualgamer** on Twitch and YouTube.

- **Wissegmini-Kil'jaeden** — Human Paladin, Alliance, Midnight Season 2 Retail
- **Wissegmini-Kil'jaeden** — Draenei Paladin, Alliance, Midnight Season 2 Retail (no footage used)
- **Wiisggemini-Kel'thuzad** — Goblin Shaman, Horde, Midnight Season 2 Retail
- **Wiiseegemini-Wiiseegemini** — Troll Priest, Horde, WoW Forever
- **Wwiisegemini-Wwiisegemini** — Horde, WoW Forever

Use `/triage credits` to copy credit details or turn the local login message off for this character.
