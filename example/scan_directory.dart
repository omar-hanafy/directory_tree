// A small `tree` command: scans a directory and prints it.
//
//   dart run example/scan_directory.dart [directory]
//
// The directory defaults to the current one. Hidden entries (names starting
// with `.`) are left out. Needs dart:io, so it runs on the Dart VM and in
// native executables, not on the web.
import 'dart:io';

import 'package:directory_tree/directory_tree.dart';
import 'package:directory_tree/io.dart';

/// How many levels below the scanned directory are printed.
const int printedDepth = 2;

Future<void> main(List<String> args) async {
  final path = args.isEmpty ? '.' : args.first;
  final skipped = <String>[];
  final scanner = DirectoryScanner(
    onError: (error) => skipped.add('${error.path}: ${error.message}'),
  );

  // Only the scanned path itself can fail the scan; unreadable directories
  // below it go to onError and the walk continues.
  final DirectoryTree<FileSystemEntity> tree;
  try {
    tree = await scanner.scanTree(path);
  } on FileSystemException catch (error) {
    stderr.writeln('Cannot scan $path: ${error.message}');
    exitCode = 1;
    return;
  }

  print(tree.render(maxDepth: printedDepth));
  print('');
  print('${tree.directoryCount} directories, ${tree.fileCount} files');
  for (final issue in tree.issues) {
    print('issue: $issue');
  }
  for (final failure in skipped) {
    print('skipped $failure');
  }
}
