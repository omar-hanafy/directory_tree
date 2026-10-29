---
description: Checkbox trees use SelectionState in multiple mode with toggleCheck and checkStateOf.
tags: [use, selection, checkboxes]
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

Using directory_tree 2.0.0, I am building a file picker with a tri-state checkbox on every row. Given `DirectoryTree<Object?> tree`, write the initial selection value, a function `SelectionState onCheckboxTap(SelectionState selection, NodeId id)` for a checkbox click, and a function that returns the checkbox state of any node. Reply with only the Dart code.
