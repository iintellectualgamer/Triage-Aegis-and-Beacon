# Triage - Aegis & Beacon 0.1.1 / Test 17

Triage brings click casting, range alerts, group buff checks, and markers into one panel. Open the bundled **User-Manual.txt** for setup and testing. The PDF edition is a separate download.

## Install

1. Close World of Warcraft and extract the ZIP.
2. Copy the **TriageAegisBeacon** folder into the `Interface\AddOns` folder for your edition.

   - Retail uses `_retail_\Interface\AddOns`.
   - Forever uses `_forever_\Interface\AddOns`.
   - Expansion Classic and Classic Era typically use `_classic_` and `_classic_era_`.
     Use your launcher's game folder for your edition.

3. Check for `Interface\AddOns\TriageAegisBeacon\TriageAegisBeacon.toc`. Enable **Triage - Aegis & Beacon** on the character screen.
4. Log in and type `/triage version` to verify **0.1.1 / Test 17**, then type `/triage show` to open the panel. Use **Party**, **Raid**, **Markers**, or **Combined** to switch views. Use **-** to minimize, **+** to expand, and **X** to hide it. Left-click the gold minimap button to toggle the panel, right-click it for Settings, or drag it along the map rim outside combat.

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

## Bring settings forward from VigilSigil

Close WoW and move the old `VigilSigil` addon folder out of `Interface\AddOns`. Install the new folder. Existing keyboard assignments use the same binding IDs.

For each character, look in the same edition's `WTF\Account\<account>\<realm>\<character>\SavedVariables` folder. If `VigilSigil.lua` exists and `TriageAegisBeacon.lua` is absent, copy `VigilSigil.lua` there as `TriageAegisBeacon.lua`. Triage imports those character settings at login.


## Heal and mark

- **Assign spells** starts with plain Left-click, Right-click, and Middle-click. Toggle **Alt**, **Ctrl**, and **Shift** to edit any combination. Page through **Button 31** with the arrows. Pick a learned spell, type its name or ID, or drag it from the spellbook or action bar onto the field or **Pick**. Return the cursor icon or cancel the drag, then save.
- **Settings > Custom spells > Saved clicks** lists your active profile's saved gestures and their availability. Select a row to open its assignment field.
- **Pick → Browse spells and talents** searches the current character's healing, damage, tank, utility, racial, and pet abilities. View active or passive talents and inactive choices. Select an **Assignable** result, then save the original field. Availability follows WoW's active specialization and talent build.
- Type `/target` in any health-bar click field to select that unit. Use `None` to disable a click, including the default **Left-click** and **Alt + middle-click** selection. Try any gesture in **Settings > Practice**.
- Supported friendly spells on health bars select the clicked unit by default. To keep your current target while healing, clear **Target player on healing clicks** in **Mouse buttons**. The checkbox saves right away.
- **Settings > Spell icons** lets you show any of the eight slots in **Party**, **Raid**, and **Combined**. Select zero through eight or use individual checkboxes. Assign either extra slot any learned eligible spell, such as Cleanse, Blessing of Freedom, or a Beacon. Choose **Save spell icons** to apply the selection.
- The first spell tile shows Left-click when assigned and Shift + left-click otherwise. The second tile shows Right-click.
- **Combined** follows WoW's party or full raid roster and shows markers below it. Raid bars populate when Triage opens in an existing raid, including after a UI reload. **Party** displays your subgroup and shows a hint to reach the full raid.
- Use the view tabs, title controls, and gold minimap button during combat. **Settings** stays separate from the combat panel. Spell reassignments, scale, and protected layout changes apply after combat.
- **Appearance** has independent current health and percentage switches, panel opacity, priority players, party roles, combat tooltips, a thin hover edge, and a cleanse cue for readable dispel data.
- Hover over a healing bar to see the player's name when available and up to three plain mouse assignments. Open **Saved clicks** for all assignments.
- **Alert settings > Channels** displays separate automatic and manual buttons for **Current group**, **Whisper**, **Raid**, **Party**, **Instance**, **Say**, and **Battleground**. Enable the alerts you want and choose **Save alerts**. Automatic **Say** prepares a draft. Battleground uses instance chat. Optional native minimap pings, timing, and ping audio are in **Behavior**.
- Use a party member's **Notify** or a raid teammate's **!** for a manual alert. Right-click or middle-click it to choose a channel, including **Whisper this player**. The raid **!** brightens gently on hover. **Ping target** is the separate WoW Assist action.
- **Buff coverage** can announce every verified missing buff count once when a group or instance starts. Healer reminders and buff summaries begin with **[Triage - Aegis & Beacon]**. **Profiles** saves Dungeon and Raid presets and transfers your spell, mouse, and icon choices.
- **Markers** places unit icons or aims ground markers with your click or keypress. The marker section fits in 24 fewer UI pixels of height. Right-click a world marker to clear it. Ready check and 10s pull follow WoW's group permissions.

## Quick commands

`/triage help` lists the slash commands. Use `/triage icons` for spell icons, `/triage practice` for click previews, and `/triage reset` to restore the initial panel position.

## Credits

Created by **iintellectualgamer**. Contact **iintellectualgamer@gmail.com**. The creator uses **iintellectualgamer** on Twitch and YouTube and plays as **Wissegmini-Kil'jaeden** and **Wwiisseegemi-Tichondrius**.

Use `/triage credits` to copy credit details or turn the local login message off for this character.
