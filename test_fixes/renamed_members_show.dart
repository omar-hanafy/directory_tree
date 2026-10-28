// The same reads through an import with a show combinator.
import 'package:directory_tree/directory_tree.dart' show ListDiff, TreeEntry;

List<int> removals(ListDiff diff) => diff.removeIndicesDesc;

List<int> insertions(ListDiff diff) => diff.insertIndicesAsc;

String pathOf(TreeEntry entry) => entry.fullPath;
