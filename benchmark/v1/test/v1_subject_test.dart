import 'package:directory_tree_bench_harness/harness.dart';
import 'package:directory_tree_bench_v1/v1_subject.dart';
import 'package:test/test.dart';

void main() {
  for (final shape in WorkloadShape.values) {
    group('${shape.name} 10000', () {
      final workload = Workload.generate(shape, 10000);
      final subject = V1Subject(workload);
      for (final op in standardOperations) {
        subject.setUp(op);
      }
      final paths = workload.paths;

      test('build creates one node per file and folder', () {
        // + the hidden root and the "tree" container.
        expect(subject.run('build'), {
          'nodes': paths.length + workload.folderCount + 2,
        });
      });

      test('flatten shows every file and folder under /repo', () {
        expect(subject.run('flatten'), {
          'rows': paths.length + workload.folderCount,
        });
      });

      test('toggle hides exactly the target subtree', () {
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
        expect(subject.run('toggle'), {
          'rows': paths.length + workload.folderCount - hidden,
          'hidden_rows': hidden,
        });
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
      });

      test('diff removes the hidden rows and inserts nothing', () {
        final hidden = subject.run('toggle')['hidden_rows'];
        expect(subject.run('diff'), {'removed': hidden, 'inserted': 0});
      });
    });
  }
}
