// lib/src/state/selection_state.dart

/// Defines how many items can be selected at once.
enum SelectionMode {
  /// Only one item can be selected at a time.
  single,

  /// Multiple items can be selected (e.g., via Shift/Ctrl clicks).
  multi,
}

/// Tracks selected items and enforces selection modes.
///
/// ### Behavior
/// *   **Single Mode:** [toggle] replaces the current selection.
/// *   **Multi Mode:** [toggle] adds/removes individual items.
/// *   **Range:** [selectRange] fills the gap between two anchors (Shift+Click behavior).
class SelectionSet {
  /// Creates a new [SelectionSet].
  SelectionSet({this.mode = SelectionMode.single});

  /// The current selection mode (single or multi).
  SelectionMode mode;
  final Set<String> _selected = <String>{};

  /// Returns true if [id] is selected.
  bool isSelected(String id) => _selected.contains(id);

  /// Returns a read-only view of the selected IDs.
  Set<String> get selectedIds => Set.unmodifiable(_selected);

  /// Exclusive selection: selects [id] and deselects everything else.
  ///
  /// Use this for standard click behavior in single-select lists.
  /// Returns `true` if the selection set changed.
  bool selectOnly(String id) {
    if (_selected.length == 1 && _selected.contains(id)) {
      return false;
    }
    _selected
      ..clear()
      ..add(id);
    return true;
  }

  /// Toggles [id] depending on [mode].
  ///
  /// *   **Single Mode:** Replaces the current selection with [id].
  /// *   **Multi Mode:** Adds [id] if missing, or removes it if present.
  ///
  /// Returns `true` if the selection changed.
  bool toggle(String id) {
    if (mode == SelectionMode.single) {
      return selectOnly(id);
    }
    if (_selected.contains(id)) {
      _selected.remove(id);
      return true;
    }
    _selected.add(id);
    return true;
  }

  /// Clears all selections. Returns true if anything was cleared.
  bool clear() {
    if (_selected.isEmpty) return false;
    _selected.clear();
    return true;
  }

  /// Selects a contiguous range of items between [anchorId] and [toId].
  ///
  /// [orderedVisibleIds] must be the current flat list of items shown in the UI.
  /// This mimics standard "Shift+Click" behavior in file explorers.
  ///
  /// Returns `true` if the selection changed.
  bool selectRange(
    List<String> orderedVisibleIds,
    String anchorId,
    String toId,
  ) {
    if (mode == SelectionMode.single) {
      return selectOnly(toId);
    }
    final anchorIndex = orderedVisibleIds.indexOf(anchorId);
    final targetIndex = orderedVisibleIds.indexOf(toId);
    if (anchorIndex == -1 || targetIndex == -1) {
      return false;
    }
    final start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final end = anchorIndex < targetIndex ? targetIndex : anchorIndex;
    final next = orderedVisibleIds.sublist(start, end + 1);
    if (_selected.length == next.length && _selected.containsAll(next)) {
      return false;
    }
    _selected
      ..clear()
      ..addAll(next);
    return true;
  }

  /// Adds [ids] to the selection. Returns true if any id was newly added.
  bool addAll(Iterable<String> ids) {
    var changed = false;
    for (final id in ids) {
      if (_selected.add(id)) {
        changed = true;
      }
    }
    return changed;
  }

  /// Removes [ids] from the selection. Returns true if any id was removed.
  bool removeAll(Iterable<String> ids) {
    var changed = false;
    for (final id in ids) {
      if (_selected.remove(id)) {
        changed = true;
      }
    }
    return changed;
  }

  /// Keeps only ids that satisfy [test]. Returns true if the set changed.
  bool retainWhere(bool Function(String id) test) {
    final before = _selected.length;
    _selected.removeWhere((element) => !test(element));
    return before != _selected.length;
  }
}
