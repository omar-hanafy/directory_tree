# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-01-02

### Initial Release
- Core `TreeBuilder` for normalizing paths and generating deterministic tree structures.
- `TreeData` and `TreeNode` immutable models.
- `FlattenStrategy` (DFS) and `SortedFlattenStrategy` for linearizing trees.
- `diffVisibleNodes` using Longest Increasing Subsequence (LIS) for efficient list updates.
- `ExpansionSet` and `SelectionSet` state helpers.
- `compileFilter` for flexible text and extension searching.
- Cross-platform path normalization (Windows/POSIX).
