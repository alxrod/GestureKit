---
name: verify-gestures
description: Prove the gestures of a visionOS app built on GestureKit work, in a visionOS simulator of the run's own, by driving them through gesturekit-drive, GestureKit's no-hand automation, and keeping the JSON answer, trace, screenshot, and app state as evidence. Use after changing anything an item, grid, surface, tab, grab handle, panel, or tuning on GestureKit touches, before calling the change done; or to reproduce a gesture bug without a headset.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/pinned-skill.sh *)
---

<!--
A stub. Claude Code runs the command on the line below before Claude reads
this skill, and puts what it prints in its place: dynamic context injection,
https://code.claude.com/docs/en/skills. In a plugin's skill it substitutes
the plugin's installed folder, CLAUDE_PLUGIN_ROOT, and its data folder kept
across updates, CLAUDE_PLUGIN_DATA, in the body and in allowed-tools, whose
rule lets the command run without asking (the same page's string
substitutions; https://code.claude.com/docs/en/plugins-reference has the
variables). The script prints the verify-gestures skill of the GestureKit
commit this project's Package.resolved pins, or what to run to get it, and
always exits 0, since a command that fails aborts the skill.
-->

!`${CLAUDE_PLUGIN_ROOT}/scripts/pinned-skill.sh --project "${CLAUDE_PROJECT_DIR}" --extract-into "${CLAUDE_PLUGIN_DATA}/pinned-skills"`

If no skill appears above, as when a policy turns off skills' shell commands, run `${CLAUDE_PLUGIN_ROOT}/scripts/pinned-skill.sh --project "${CLAUDE_PROJECT_DIR}"` yourself and follow what it prints.
