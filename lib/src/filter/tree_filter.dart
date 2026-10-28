import 'package:directory_tree/src/tree/directory_tree.dart';
import 'package:meta/meta.dart';

/// A predicate over tree nodes, used to filter views of a [DirectoryTree].
///
/// A filter decides per node with [matches]; views then keep matching nodes
/// together with the ancestors that lead to them. Build filters from a
/// function with [TreeFilter.where], combine them with [and], [or], and
/// [negate], or extend this class (as `TreeQuery` does for search strings).
///
/// [matchesAll] tells views that a filter accepts every node, so they can
/// skip filtering entirely; an empty search box is the typical case.
///
/// ```dart
/// final dartFiles = TreeFilter.where<Object?>(
///   (node) => node.isFile && node.path.extension == '.dart',
/// );
/// final notGenerated = TreeFilter.where<Object?>(
///   (node) => !node.name.endsWith('.g.dart'),
/// );
/// final filter = dartFiles.and(notGenerated);
/// ```
///
/// Implementations must be pure: [matches] must return the same answer for
/// the same node every time, because views cache results.
abstract class TreeFilter {
  /// Creates a filter. Subclasses implement [matches].
  const TreeFilter();

  /// A filter that matches every node and reports [matchesAll].
  ///
  /// Use it as a neutral value instead of `null`.
  static const TreeFilter all = _AllFilter();

  /// Creates a filter that matches nodes for which [test] returns true.
  ///
  /// [test] is only called with `TreeNode<T>` nodes; any other node never
  /// matches, so a `TreeFilter.where<int>` never matches nodes of a
  /// `DirectoryTree<String>`. Use `TreeFilter.where<Object?>` to accept
  /// every tree. The filter never reports [matchesAll], even if [test]
  /// accepts everything.
  static TreeFilter where<T>(bool Function(TreeNode<T> node) test) =>
      _WhereFilter<T>(test);

  /// Whether [node] passes this filter.
  bool matches(TreeNode<Object?> node);

  /// Whether this filter accepts every node, so views can treat it as no
  /// filter at all.
  ///
  /// Defaults to false. Override it only when [matches] is true for every
  /// possible node.
  bool get matchesAll => false;

  /// Returns a filter that matches nodes matched by both this filter and
  /// [other].
  ///
  /// [other] is only consulted for nodes this filter matches. The result
  /// reports [matchesAll] when both filters do.
  @useResult
  TreeFilter and(TreeFilter other) => _AndFilter(this, other);

  /// Returns a filter that matches nodes matched by this filter or [other].
  ///
  /// [other] is only consulted for nodes this filter rejects. The result
  /// reports [matchesAll] when either filter does.
  @useResult
  TreeFilter or(TreeFilter other) => _OrFilter(this, other);

  /// Returns a filter that matches exactly the nodes this filter rejects.
  ///
  /// The result never reports [matchesAll]; negating [all] yields a filter
  /// that matches nothing. Negating a negation returns the original filter.
  @useResult
  TreeFilter negate() => _NotFilter(this);
}

@immutable
final class _AllFilter extends TreeFilter {
  const _AllFilter();

  @override
  bool matches(TreeNode<Object?> node) => true;

  @override
  bool get matchesAll => true;

  @override
  String toString() => 'TreeFilter.all';
}

@immutable
final class _WhereFilter<T> extends TreeFilter {
  const _WhereFilter(this.test);

  final bool Function(TreeNode<T> node) test;

  @override
  bool matches(TreeNode<Object?> node) => node is TreeNode<T> && test(node);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _WhereFilter<T> && other.test == test;

  @override
  int get hashCode => test.hashCode;

  @override
  String toString() => 'TreeFilter.where(...)';
}

@immutable
final class _AndFilter extends TreeFilter {
  const _AndFilter(this.first, this.second);

  final TreeFilter first;
  final TreeFilter second;

  @override
  bool matches(TreeNode<Object?> node) =>
      first.matches(node) && second.matches(node);

  @override
  bool get matchesAll => first.matchesAll && second.matchesAll;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _AndFilter && other.first == first && other.second == second;

  @override
  int get hashCode => Object.hash(_AndFilter, first, second);

  @override
  String toString() => '($first and $second)';
}

@immutable
final class _OrFilter extends TreeFilter {
  const _OrFilter(this.first, this.second);

  final TreeFilter first;
  final TreeFilter second;

  @override
  bool matches(TreeNode<Object?> node) =>
      first.matches(node) || second.matches(node);

  @override
  bool get matchesAll => first.matchesAll || second.matchesAll;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _OrFilter && other.first == first && other.second == second;

  @override
  int get hashCode => Object.hash(_OrFilter, first, second);

  @override
  String toString() => '($first or $second)';
}

@immutable
final class _NotFilter extends TreeFilter {
  const _NotFilter(this.inner);

  final TreeFilter inner;

  @override
  bool matches(TreeNode<Object?> node) => !inner.matches(node);

  @override
  TreeFilter negate() => inner;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _NotFilter && other.inner == inner;

  @override
  int get hashCode => Object.hash(_NotFilter, inner);

  @override
  String toString() => 'not $inner';
}
