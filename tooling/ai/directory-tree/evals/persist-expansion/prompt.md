---
description: Saving a tree view's expansion must persist requestedExpansion, not the search-revealed state.
tags: [use, rows, expansion]
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

My Flutter file explorer depends on directory_tree ^2.0.0. Write a Dart function `String saveExpansion(TreeRows<Object?> rows)` that returns a JSON string of the folders the user expanded, so the view can be restored after a restart. Folders that only the current search opened must not be saved. Reply with only the code.
