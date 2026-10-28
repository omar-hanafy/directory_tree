import 'package:directory_tree/src/path/path_policy.dart';
import 'package:directory_tree/src/tree/directory_tree.dart';
import 'package:directory_tree/src/tree/tree_options.dart';

/// Stable, deterministic node identity: the policy key of the node's
/// canonical path.
///
/// The key is the canonical path string itself, lowercased when the
/// [PathPolicy] is case insensitive. Building the same entries with the same
/// [TreeOptions] always yields the same ids, so ids survive rebuilds and can
/// key widget state, expansion sets, and selections. Two nodes in one
/// [DirectoryTree] never share an id.
///
/// Ids are human readable (for example `/users/me/repo/lib` in a case
/// insensitive tree), but treat them as opaque: derive them with
/// [PathPolicy.idOf] or [DirectoryTree.idOf] instead of formatting strings by
/// hand. Persist an id with [value] and restore it with `NodeId(saved)`.
///
/// [NodeId] is an extension type, so it costs nothing at runtime and compares
/// with string equality. It deliberately does not implement [String], so
/// string methods are not available on ids; it implements [Object], so ids
/// are non-nullable and fit anywhere an [Object] is expected.
extension type const NodeId(
  /// The policy key this id wraps; store it to persist the id.
  String value
)
    implements Object {}
