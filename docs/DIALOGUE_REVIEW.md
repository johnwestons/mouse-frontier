# Dialogue review and author-only policy

September 14, 2026

### September 19 correction: regular Talk restored

The user confirmed that the original `Catalog.dialogueLines` were their writing and explicitly requested their restoration. All 33 lines have been restored verbatim from R001. The earlier change incorrectly removed them and discarded the ordinary NPC/passenger Talk result, leaving Talk silent whenever no new question or task was available.

Regular Talk now shows the approved original chatter between the one-time question trees. Passengers use this same approved general chatter until passenger-specific writing is approved. The question trees retain their saved spacing, completion and single rewards. If a future approved chatter list is empty, a neutral status notice prevents Talk from silently doing nothing.

Validation for this correction includes the actual mobile touch button through the shared input router: opening/closing regular chat, completing a question tree, returning to regular chat and talking to passengers. Other archived text remains unapproved. Passenger-specific and relationship-specific lines still need your writing or confirmation.

### September 19 presentation update: no advance outcome hints

Player reply buttons now display only the supplied answer text. The cost/reward subtitles and advance XP objective have been removed. The conversation header shows the NPC name instead. Item exchanges, availability checks and XP remain functional; actual inventory/XP changes are shown after the player chooses.

Your 13 supplied conversations are implemented, preserving all 91 Q/A/R lines exactly, including spelling and punctuation. Parenthetical item instructions are implemented as mechanics and shown separately from spoken text.

## Review the old wording

The repository does not reliably identify the author of each older line. These are **legacy dialogue review candidates**, not a claim that every line was written by AI. The regular chatter approved on September 19 is now restored. Other unverified character speech remains retired pending your review; the originals remain available below.

- [Focused list of removed speech and affected contexts](dialogue-review/changed-text.md): use the R-number when supplying a rewrite. Includes the original NPC chatter arrays and the complete four retired conversation quests.
- [Broader original-text inventory](dialogue-review/legacy-text.md): 1,043 dialogue, story, and nearby UI candidates with original file/line references. This appendix deliberately includes gameplay instructions and narration for context; those are not all character dialogue.
- [Your original request and approved conversations](dialogue-review/user-conversations.txt).

Reply with a review ID and DELETE, your replacement text, or confirmation that an old line is yours and should be kept. Archived text is not approved merely because it appears in an older design document.

## Dialogue that needs your writing

| Context | Missing author-supplied speech | Current behavior |
| --- | --- | --- |
| General NPCs | Original regular chatter confirmed and restored September 19 | Approved original chatter remains available between scheduled conversations |
| Relationships | Familiar/friendly/trusted greetings; recognition of gifts and help | Relationship values and trade effects remain; no generated remarks |
| Gifts | Acceptance and rejection lines | Item-specific, neutral gift notices |
| Passengers | Job remarks, destination comments, thanks and farewell | Passenger jobs/rewards remain; approved general chatter supplies ordinary Talk |
| Mail, rides and trade | Requests, acceptance, refusal and completion lines | Neutral task cards and ACCEPT/DECLINE controls |
| Delivery quests | Requests and thanks for food, water, medicine, repair materials, ammunition and keepsake recovery | Neutral requirements, destination and reward notices |
| Item help / first aid | Requests, missing-item response, success, failure and pause response | Neutral item/treatment status; gameplay remains usable |
| Four retired dialogue quests | Missing Family Trail, Share the Water, A Trustworthy Warning, The Unfinished Promise: opening, branches and follow-up | Retired; old sessions removed on save migration, earned rewards preserved |
| Rookery Caravan | First meeting, repeat meetings and return greetings | Neutral trading notice |
| Last Stand | Scout approach, offer, refusal, pause/return, Fox/Gecko/scout replies, window handoff, intermissions, loan weapon/ammo lines and aftermath | Neutral objectives and controls preserve the complete quest |
| Family letter | The quoted letter in the bottle | Neutral westward clue; progression preserved |

Please supply rewrites for any of these contexts you want to speak. No substitute character dialogue has been invented. Event descriptions, unquoted story narration, ending narration, item descriptions and controls remain as non-dialogue text; the broader inventory includes these for optional review. Historical drafts such as `LAST_STAND_DIALOGUE_AND_BEAT_SHEET.md` remain reference material, not live or approved dialogue.

## Conversation behavior

- A random unused conversation is assigned to a randomly generated, reachable NPC. Established house residents can also be selected. The saved assignment cannot reroll through repeated interaction or reloads.
- New assignments are spaced two to four stops apart. The initial conversation can appear at stop 1; 13 assignments fit within a new 50-stop journey. Existing saves begin assigning from their current progress.
- A completed conversation never repeats during that playthrough. Unfinished conversations can be resumed with the same NPC at the same stop. Missed conversations remain assigned there; they are not reassigned elsewhere.
- Each answer selects the corresponding response. Completion awards **5 XP once**, including the free/refusal answers. Costs, rewards and the selected answer persist with the save.
- Food A1 spends 2 food from train storage. A2 spends 2 food and 1 water. An unaffordable answer is disabled and cannot deduct partial costs; A3 remains available.
- Ammo rewards are exactly 20 .22 LR, 10 9mm, or 15 mixed cartridges. Mixed rewards contain at least two supported firearm calibers, with no rocks, arrows or ball bearings.
- Wounds A2 gives a field bandage roll (5 HP when used); A3 gives a frontier medkit (12 HP when used). Neither is automatically consumed. Rewards go to the backpack, then the train mailbox, then a local supply crate if both are full.
- Numbers 1–3, mouse or touch select an answer. CONTINUE LATER or Escape/Q closes the question without completing it. Author-supplied dialogue remains open until dismissed.
- Save schema 35 preserves old progress while adding conversation assignments, discovered/completed records and spacing. It removes retired generated dialogue sessions without taking away previously earned XP or goodwill.

## Future tasks

[AGENTS.md](../AGENTS.md) now requires that all speech be supplied or explicitly approved by you. When a task needs missing dialogue, it must add the speaker, trigger and branches here and ask for your rewrite in the task report. Neutral gameplay instructions may keep mechanics usable while that text awaits you.

## Validation

- 17 focused tests passed: all 91 supplied lines, all 39 answer branches, shortages, exact costs/ammo, inventory overflow, stale requests, save serialization/reload, migration, pacing, journey integration and architecture.
- Standard in-game smoke: 88 checkpoints passed.
- Mobile-mode in-game smoke: 95 checkpoints passed.
- Full-route smoke: reached the ending at stop 50.
- Last Stand: 158 focused checks passed.
- 78 rendered dialogue layouts passed text-fit and overlap checks across desktop/mobile and all three text sizes; desktop/mobile screenshots visually inspected.

The mobile layout was tested in the shared desktop runtime; no Android device or new APK was used for this review.
