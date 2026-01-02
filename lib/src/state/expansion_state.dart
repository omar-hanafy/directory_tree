// lib/src/state/expansion_state.dart

/// Tracks which folders are currently open.
///
/// Designed to be framework-agnostic so it can be used in ViewModels or BLoCs.
///
/// ### Behavior
/// *   **Persistence:** IDs are strings, so they survive tree rebuilds if the node IDs are stable.
class ExpansionSet {
  /// Creates a new [ExpansionSet], optionally with initial IDs.
  ExpansionSet({Set<String>? initiallyExpanded})
    : _expanded = {...?initiallyExpanded};

  final Set<String> _expanded;

  /// Returns true if [id] is currently expanded.
  bool isExpanded(String id) => _expanded.contains(id);

  /// Adds or removes [id] from the expanded set.
  ///
  /// Returns `true` if the state actually changed (e.g., [id] was not already in the target state).
  bool setExpanded(String id, bool expanded) {
    return expanded ? _expanded.add(id) : _expanded.remove(id);
  }

  /// Toggles the expanded state of [id].
  ///
  /// If [id] is present, it is removed. If absent, it is added.
  /// Returns `true` if the set changed.
  bool toggle(String id) => setExpanded(id, !isExpanded(id));

  /// Expands every id in [ids].
  ///
  /// Useful for "Expand All" or restoring a saved session state.
  /// Returns `true` if any new ID was added to the set.
  bool expandAll(Iterable<String> ids) {
    var changed = false;
    for (final id in ids) {
      if (_expanded.add(id)) {
        changed = true;
      }
    }
    return changed;
  }

  /// Collapses all ids. Returns true if any id was previously expanded.
  bool collapseAll() {
    if (_expanded.isEmpty) return false;
    _expanded.clear();
    return true;
  }

  /// Keeps only ids that satisfy [test]. Returns true if the set changed.
  bool retainWhere(bool Function(String id) test) {
    final before = _expanded.length;
    _expanded.removeWhere((element) => !test(element));
    return before != _expanded.length;
  }

  /// Returns a read-only view of the expanded IDs.
  Set<String> get expandedIds => Set.unmodifiable(_expanded);
}
