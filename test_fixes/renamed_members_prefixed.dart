// The same reads through a prefixed import.
import 'package:directory_tree/directory_tree.dart' as dt;

List<int> removals(dt.ListDiff diff) => diff.removeIndicesDesc;

List<int> insertions(dt.ListDiff diff) => diff.insertIndicesAsc;

String pathOf(dt.TreeEntry entry) => entry.fullPath;
