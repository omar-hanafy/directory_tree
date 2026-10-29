// Reads of the 1.x members that 2.0.0 renamed without changing their type
// or meaning.
import 'package:directory_tree/directory_tree.dart';

List<int> removals(ListDiff diff) => diff.removeIndicesDesc;

int insertionCount(ListDiff diff) => diff.insertIndicesAsc.length;

void apply(ListDiff diff, void Function(int) remove, void Function(int) add) {
  for (final index in diff.removeIndicesDesc) {
    remove(index);
  }
  diff.insertIndicesAsc.forEach(add);
}

String describe(TreeEntry entry) => 'entry at ${entry.fullPath}';

String? pathOf(TreeEntry? entry) => entry?.fullPath;

List<String> paths(List<TreeEntry> entries) =>
    entries.map((entry) => entry.fullPath).toList();

// A control: members with the same names on another class stay unchanged.
class Upload {
  Upload(this.fullPath);

  final String fullPath;

  List<int> get removeIndicesDesc => const [];
}

String uploadPath(Upload upload) =>
    upload.fullPath + upload.removeIndicesDesc.length.toString();
