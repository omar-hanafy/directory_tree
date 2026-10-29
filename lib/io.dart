/// Builds directory trees from the local file system.
///
/// This optional library adds [DirectoryScanner], which walks a directory
/// on disk and returns `TreeEntry`s carrying the `File`, `Directory`, or
/// `Link` of each entity, ready for `DirectoryTree.build` (or call
/// [DirectoryScanner.scanTree] to get the tree directly). The scanner
/// leaves out hidden entries by default, can prune subtrees and limit the
/// depth while it walks, and reports directories it cannot read to a
/// callback instead of failing.
///
/// It needs `dart:io`, so it is available on the Dart VM, in native
/// executables, and in Flutter apps on mobile and desktop, but not on the
/// web. It does not export the core library, so import both:
///
/// ```dart
/// import 'package:directory_tree/directory_tree.dart';
/// import 'package:directory_tree/io.dart';
///
/// Future<void> main() async {
///   final tree = await const DirectoryScanner(maxDepth: 2).scanTree('.');
///   print(tree.rootNodes.single.name); // .
///   print(tree.render());
/// }
/// ```
///
/// `package:directory_tree/directory_tree.dart` never imports this library
/// or `dart:io`, so the core stays platform independent and keeps working
/// on the web and with dart2wasm; only code that imports `io.dart` depends
/// on a native platform.
library;

// Imported only so the references in the library documentation resolve.
import 'package:directory_tree/src/io/directory_scanner.dart';

export 'package:directory_tree/src/io/directory_scanner.dart';
