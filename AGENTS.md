# Global working preferences

## Game saves across all projects

- The user's game saves are normally disposable test saves. Prefer wiping/resetting the relevant game's saves over spending time preserving or backing them up, unless the user says they need them.
- At the very beginning of any task that might touch existing game saves (including installs, updates, testing, migration or resets), ask once whether to wipe the test saves (the default choice) or keep them. Resolve this early, before touching saves; continue independent work while awaiting the answer.
- Do not automatically back up saves. Ask before doing backup work, and only preserve/back up saves when the user requests it or chooses that option.
- An explicit save-handling decision in the current task already answers the question. Honor it without repeatedly asking.
- Limit any wipe to the relevant game's saves in the agreed task. This preference does not authorize deleting unrelated files, other games' data or existing backups, and does not request an immediate wipe merely because these instructions were read.

--- project-doc ---

# Dialogue ownership

- All character dialogue, player spoken answers, barks, letters and quoted character speech must be supplied or explicitly approved by the user.
- Do not invent, paraphrase, polish, or correct dialogue without the user's request. Preserve supplied wording, capitalization, spelling and punctuation.
- Approved conversation content is in `game/authored_dialogue.lua`; its source is `docs/dialogue-review/user-conversations.txt`.
- On September 19, 2026, the user confirmed the original regular talk lines in `Catalog.dialogueLines` were theirs and explicitly requested their restoration. These lines are approved; preserve them verbatim. This approval does not extend to all other archived text. Regular chatter remains available alongside the one-time conversation trees.
- When a task needs dialogue the user has not supplied, implement the necessary mechanics with neutral UI instructions where possible. Add the missing speaker, trigger, context and required branches to `docs/DIALOGUE_REVIEW.md`, and request the user's rewrite in the task report. Do not ship invented placeholder speech.
- Legacy text is archived for review in `docs/dialogue-review/legacy-text.md`; presence there is not approval. Prior dialogue design documents are historical drafts, not authorization.
- Conversation assignments, completion and rewards must persist across saves; completed conversations must never repeat in the same playthrough.
- Player reply choices show only the supplied dialogue. Do not show advance reward, cost, XP, or outcome hints below choices or elsewhere in the conversation prompt. Apply mechanics normally and report actual changes only after the choice is made.
