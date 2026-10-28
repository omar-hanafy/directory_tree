import 'package:directory_tree_bench_harness/harness.dart';
import 'package:directory_tree_bench_v2/v2_subject.dart';
import 'package:test/test.dart';

void main() {
  for (final shape in WorkloadShape.values) {
    group('${shape.name} 10000', () {
      final workload = Workload.generate(shape, 10000);
      final subject = V2Subject(workload);
      for (final op in standardOperations) {
        subject.setUp(op);
      }
      final paths = workload.paths;

      test('build creates one node per file and folder, /repo on top', () {
        expect(subject.run('build'), {
          'nodes': paths.length + workload.folderCount,
        });
        expect(subject.tree.issues, isEmpty);
        expect(subject.tree.rootNodes.single.id, subject.tree.idOf('/repo'));
      });

      test('flatten shows every file and folder under /repo', () {
        expect(subject.run('flatten'), {
          'rows': paths.length + workload.folderCount,
        });
      });

      test('toggle and toggle_full hide exactly the target subtree', () {
        final prefix = '${workload.toggleTarget}/';
        final hiddenFolders = {
          for (final p in paths.where((p) => p.startsWith(prefix)))
            for (
              var i = p.indexOf('/', prefix.length);
              i != -1;
              i = p.indexOf('/', i + 1)
            )
              p.substring(0, i),
        };
        final hidden = workload.toggleTargetFileCount + hiddenFolders.length;
        final expected = {
          'rows': paths.length + workload.folderCount - hidden,
          'hidden_rows': hidden,
        };
        expect(subject.run('toggle'), expected);
        expect(subject.run('toggle_full'), expected);
        // The incremental and the full collapse produce the same rows.
        final full = subject.tree.flatten(
          expansion: subject.collapsedExpansion,
        );
        expect(
          [for (final row in subject.collapsedRows) row.id],
          [for (final row in full) row.id],
        );
        expect(
          subject.collapsedRows.rowOf(subject.toggleId)!.isExpanded,
          isFalse,
        );
      });

      test('filter keeps matches and their ancestors', () {
        final ancestors = <String>{};
        for (final p in paths) {
          if (!p.split('/').last.contains(workload.filterQuery)) continue;
          for (var i = p.indexOf('/', 1); i != -1; i = p.indexOf('/', i + 1)) {
            ancestors.add(p.substring(0, i));
          }
        }
        expect(subject.run('filter'), {
          'rows': workload.filterMatchCount + ancestors.length,
        });
        final rows = subject.tree.flatten(filter: subject.query);
        expect(rows.where((r) => r.isMatch).length, workload.filterMatchCount);
      });

      test('diff removes the hidden rows and inserts nothing', () {
        final hidden = subject.run('toggle')['hidden_rows'];
        expect(subject.run('diff'), {'removed': hidden, 'inserted': 0});
      });
    });
  }
}
