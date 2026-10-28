import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:directory_tree/src/tree/directory_tree.dart';
import 'package:directory_tree/src/tree/tree_entry.dart';
import 'package:directory_tree/src/tree/tree_options.dart';
import 'package:meta/meta.dart';

/// Lists a directory on disk as [TreeEntry]s, ready for
/// [DirectoryTree.build].
///
/// Use a scanner when the paths come from the local file system rather than
/// from a picker, a server, or `git ls-files`. It walks the directory with an
/// explicit stack (no recursion, so very deep trees are safe), applies the
/// filters below while walking (a skipped directory is never listed), and
/// returns the entries sorted by path.
///
/// What [scan] and [scanSync] return:
///
/// * the scanned directory itself and every directory found below it, as
///   `TreeEntry.directory(path, data: Directory(path))`. Including the root
///   keeps empty directories and makes the scanned directory the single
///   top-level node of the tree that [scanTree] builds;
/// * every file as `TreeEntry.file(path, data: File(path))`. Other
///   non-directory entities (pipes, sockets, devices) are reported the same
///   way, with [File] data;
/// * every symbolic link that is not followed as
///   `TreeEntry.file(path, data: Link(path))`: all links when [followLinks]
///   is false, and with [followLinks] true the broken links and the links
///   that would close a cycle.
///
/// Paths are exactly what `dart:io` reports: the scanned path as given,
/// followed by the platform separator and each name (so a relative input
/// gives relative entries, and a symbolic link keeps its own path, not its
/// target's). Only [scanTree] rewrites its input, and only for a relative
/// path that climbs above its start (see there). Entries are sorted by [String.compareTo] on [TreeEntry.path]
/// (UTF-16 code units), so the result is the same on every run over an
/// unchanged directory.
///
/// Filters are applied in this order to each entity below the root:
/// [includeHidden], then [skip]; [maxDepth] limits which directories are
/// listed. The root itself is never filtered.
///
/// Per-directory failures (permission denied, a directory removed while the
/// walk runs) never abort the scan: the directory stays in the result as an
/// entry, its listing error goes to [onError], and the walk continues. Only
/// an invalid scan path or an invalid [maxDepth] throws.
///
/// A small `tree`-like command line tool:
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:directory_tree/directory_tree.dart';
/// import 'package:directory_tree/io.dart';
///
/// Future<void> main(List<String> args) async {
///   final scanner = DirectoryScanner(
///     maxDepth: 3,
///     skip: (entity) => entity.path.endsWith('${Platform.pathSeparator}build'),
///     onError: (error) => stderr.writeln('skipped: ${error.path}'),
///   );
///   final tree = await scanner.scanTree(args.isEmpty ? '.' : args.first);
///   for (final node in tree.nodes) {
///     stdout.writeln('${'  ' * node.depth}${node.label}');
///   }
/// }
/// ```
///
/// For guide lines like the `tree` command, render the tree that [scanTree]
/// returns with the package's text renderer instead of indenting by hand.
@immutable
final class DirectoryScanner {
  /// Creates a scanner; the scan path is given later to [scan], [scanSync],
  /// or [scanTree], so one scanner can be reused for many directories.
  ///
  /// [maxDepth] must be `null` or non-negative; a negative value is reported
  /// as an [ArgumentError] when a scan starts, not here, so the constructor
  /// can stay `const`.
  const DirectoryScanner({
    this.includeHidden = false,
    this.followLinks = false,
    this.maxDepth,
    this.skip,
    this.onError,
  });

  /// Whether entities whose name starts with `.` are included.
  ///
  /// When false (the default), hidden files are omitted and hidden
  /// directories are neither reported nor listed. The scanned directory is
  /// always included, even when its own name is hidden, such as `.git`.
  /// Only the leading dot counts; platform hidden attributes (Windows) are
  /// not consulted.
  final bool includeHidden;

  /// Whether symbolic links are resolved.
  ///
  /// When false (the default), every link below the root is reported as a
  /// file entry with [Link] data and is never entered, so the scan never
  /// leaves the scanned directory.
  ///
  /// When true, a link to a directory is reported as a directory with
  /// [Directory] data and is entered, and a link to a file is reported as a
  /// file with [File] data; both keep the link's own path. A broken link is
  /// still reported as a file with [Link] data. Cycles are detected by
  /// resolved paths: a link whose resolved target is the directory being
  /// listed or one of its ancestors on the current branch is reported as a
  /// file with [Link] data and not entered, so every scan terminates.
  /// A directory reachable through several non-cyclic links is listed once
  /// per link, like a regular directory tree would show it. Following links
  /// costs one extra file-system call per link plus one per linked
  /// directory.
  ///
  /// A scan path that is itself a link to a directory is always scanned,
  /// whatever this setting.
  final bool followLinks;

  /// How many levels below the scanned directory are listed.
  ///
  /// The scanned directory is depth 0 and its children are depth 1, so `0`
  /// returns only the scanned directory, `1` adds its direct children, and
  /// `null` (the default) has no limit. Directories at the limit are
  /// reported but not listed. A negative value makes [scan], [scanSync],
  /// and [scanTree] throw an [ArgumentError].
  final int? maxDepth;

  /// Decides which entities to leave out; return true to omit one.
  ///
  /// Called once for every entity below the scanned directory that passes
  /// [includeHidden], with the object that would become the entry's data:
  /// a [Directory], a [File], or a [Link] (see [followLinks]). An omitted
  /// directory is not listed, so its whole subtree is pruned without any
  /// file-system work. Never called for the scanned directory itself.
  /// `null` (the default) keeps everything.
  ///
  /// The predicate runs synchronously inside the walk; an exception it
  /// throws aborts the scan and propagates to the caller.
  final bool Function(FileSystemEntity entity)? skip;

  /// Receives the failures that the walk recovers from.
  ///
  /// Called with the [FileSystemException] of a directory that could not be
  /// listed (for example a [PathAccessException] for a directory without
  /// read permission, or a [PathNotFoundException] for one deleted during
  /// the scan), and of a link to a directory whose target could not be
  /// resolved. The directory or link is still reported as an entry and the
  /// walk continues with the next directory. [scan] keeps the entities that
  /// were listed before a failure; [scanSync] cannot, because the
  /// synchronous listing fails as a whole.
  ///
  /// `null` (the default) ignores these failures. An exception thrown by
  /// the callback aborts the scan and propagates to the caller.
  final void Function(FileSystemException error)? onError;

  /// Lists the directory at [path] and everything below it, without
  /// blocking the event loop for long.
  ///
  /// Each directory is read with the asynchronous [Directory.list], so other
  /// work runs between directory reads; prefer this in servers and
  /// interactive tools, and [scanSync] in short scripts. Both return the
  /// same entries for the same directory (see [DirectoryScanner] for their
  /// shape and order).
  ///
  /// The returned future completes with a [PathNotFoundException] when
  /// nothing exists at [path] (including a broken link), with a
  /// [FileSystemException] when [path] exists but is not a directory (or a
  /// link to one), and with an [ArgumentError] when [maxDepth] is negative.
  /// Failures below the root go to [onError] instead.
  ///
  /// Takes O(n log n) time for n reported entities, plus one directory
  /// listing per listed directory.
  Future<List<TreeEntry<FileSystemEntity>>> scan(String path) async {
    _checkMaxDepth();
    final root = _root(path);
    final walk = _Walk(
      this,
      root,
      rootResolved: followLinks ? await root.resolveSymbolicLinks() : null,
    );
    while (walk.isNotDone) {
      final visit = walk.next();
      if (visit == null) continue;
      final (children, failures) = await _listAsync(visit.directory);
      failures.forEach(_reportFailure);
      for (final child in children) {
        if (walk.isHidden(child)) continue;
        if (child is Link && followLinks) {
          walk.addLink(child, visit, await _followAsync(child));
        } else {
          walk.add(child, visit);
        }
      }
    }
    return walk.sortedEntries();
  }

  /// Lists the directory at [path] and everything below it synchronously.
  ///
  /// Returns the same entries as [scan] (see [DirectoryScanner] for their
  /// shape and order), but blocks the isolate until the whole walk is done,
  /// so prefer [scan] in servers, UIs, and other code that must stay
  /// responsive.
  ///
  /// Throws a [PathNotFoundException] when nothing exists at [path]
  /// (including a broken link), a [FileSystemException] when [path] exists
  /// but is not a directory (or a link to one), and an [ArgumentError] when
  /// [maxDepth] is negative. Failures below the root go to [onError]
  /// instead.
  ///
  /// Takes O(n log n) time for n reported entities, plus one directory
  /// listing per listed directory.
  List<TreeEntry<FileSystemEntity>> scanSync(String path) {
    _checkMaxDepth();
    final root = _root(path);
    final walk = _Walk(
      this,
      root,
      rootResolved: followLinks ? root.resolveSymbolicLinksSync() : null,
    );
    while (walk.isNotDone) {
      final visit = walk.next();
      if (visit == null) continue;
      final List<FileSystemEntity> children;
      try {
        children = visit.directory.listSync(followLinks: false);
      } on FileSystemException catch (error) {
        onError?.call(error);
        continue;
      }
      for (final child in children) {
        if (walk.isHidden(child)) continue;
        if (child is Link && followLinks) {
          walk.addLink(child, visit, _followSync(child));
        } else {
          walk.add(child, visit);
        }
      }
    }
    return walk.sortedEntries();
  }

  /// Scans [path] with [scan] and builds a [DirectoryTree] from the entries.
  ///
  /// With the default [TreeOptions] (minimal roots), the tree has a single
  /// top-level node, the scanned directory, because the scan includes it as
  /// a directory entry. Every node's `data` is the [FileSystemEntity] of its
  /// entry; no node is inferred.
  ///
  /// Node paths are parsed by [TreeOptions.paths] from the paths `dart:io`
  /// reports. A relative [path] that the policy can represent, such as
  /// `lib` or `./src`, is scanned as given, so the tree stays relative.
  /// A relative [path] that climbs above its start, such as `..` or
  /// `../project`, has no relative tree path, so this method scans
  /// `Directory(path).absolute.path` instead: the tree is then absolute, its
  /// `..` segments resolved lexically by path parsing, and each node's
  /// `data` keeps the unresolved absolute spelling that `dart:io` reports
  /// (for example `/home/me/work/../project/lib`). [scan] and [scanSync]
  /// never make this substitution; they return paths exactly as `dart:io`
  /// reports them for the path given.
  ///
  /// Completes with the same errors as [scan].
  Future<DirectoryTree<FileSystemEntity>> scanTree(
    String path, {
    TreeOptions options = const TreeOptions(),
  }) async => DirectoryTree<FileSystemEntity>.build(
    await scan(_treePath(path, options)),
    options: options,
  );

  /// The path [scanTree] scans for [path]: [path] itself when
  /// [TreeOptions.paths] can parse it, and its absolute form when only that
  /// parses (a relative path escaping its start).
  ///
  /// An empty path stays empty so [scan] still reports it as missing rather
  /// than scanning the current directory, and a path that is invalid in both
  /// forms (a NUL character) is kept so [scan] reports the caller's spelling.
  static String _treePath(String path, TreeOptions options) {
    if (path.isEmpty || options.paths.tryParse(path) != null) return path;
    final absolute = Directory(path).absolute.path;
    return options.paths.tryParse(absolute) == null ? path : absolute;
  }

  void _checkMaxDepth() {
    final depth = maxDepth;
    if (depth != null && depth < 0) {
      throw ArgumentError.value(depth, 'maxDepth', 'must be null or >= 0');
    }
  }

  // `typeSync` follows links, so a link to a directory is accepted as the
  // root and a broken link counts as missing. It is used by [scan] too: it
  // is one stat call, cheaper than the asynchronous round trip.
  Directory _root(String path) {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      // ENOENT on POSIX and ERROR_FILE_NOT_FOUND on Windows are both 2.
      throw PathNotFoundException(
        path,
        const OSError('No such file or directory', 2),
        'Cannot scan a directory that does not exist',
      );
    }
    if (type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Cannot scan a path that is not a directory',
        path,
      );
    }
    return Directory(path);
  }

  void _reportFailure(FileSystemException error) => onError?.call(error);

  /// Collects one directory's children and listing failures, keeping
  /// whatever was listed before a failure.
  ///
  /// Failures are returned rather than passed to [onError] here, so that
  /// an exception thrown by [onError] propagates from [scan] instead of
  /// escaping into the stream's zone. Errors that are not
  /// [FileSystemException]s are unexpected and complete the future with
  /// the error.
  Future<(List<FileSystemEntity>, List<FileSystemException>)> _listAsync(
    Directory directory,
  ) {
    final children = <FileSystemEntity>[];
    final failures = <FileSystemException>[];
    final done =
        Completer<(List<FileSystemEntity>, List<FileSystemException>)>();
    directory
        .list(followLinks: false)
        .listen(
          children.add,
          onError: (Object error, StackTrace stackTrace) {
            if (error is FileSystemException) {
              failures.add(error);
            } else if (!done.isCompleted) {
              done.completeError(error, stackTrace);
            }
          },
          onDone: () {
            if (!done.isCompleted) done.complete((children, failures));
          },
        );
    return done.future;
  }

  // `typeSync` is a single stat call; the asynchronous variant costs a
  // round trip to the IO thread pool for the same work.
  Future<_LinkTarget> _followAsync(Link link) async {
    final type = FileSystemEntity.typeSync(link.path);
    if (type != FileSystemEntityType.directory) return _LinkTarget(type);
    try {
      return _LinkTarget(type, await link.resolveSymbolicLinks());
    } on FileSystemException catch (error) {
      onError?.call(error);
      return const _LinkTarget(FileSystemEntityType.notFound);
    }
  }

  _LinkTarget _followSync(Link link) {
    final type = FileSystemEntity.typeSync(link.path);
    if (type != FileSystemEntityType.directory) return _LinkTarget(type);
    try {
      return _LinkTarget(type, link.resolveSymbolicLinksSync());
    } on FileSystemException catch (error) {
      onError?.call(error);
      return const _LinkTarget(FileSystemEntityType.notFound);
    }
  }

  /// Whether [other] is a [DirectoryScanner] with equal settings.
  ///
  /// [skip] and [onError] are compared with `==`, so two scanners built
  /// with separate closures are not equal even when the closures behave the
  /// same; pass the same function (or a tear-off) to make them equal.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectoryScanner &&
          other.includeHidden == includeHidden &&
          other.followLinks == followLinks &&
          other.maxDepth == maxDepth &&
          other.skip == skip &&
          other.onError == onError;

  @override
  int get hashCode =>
      Object.hash(includeHidden, followLinks, maxDepth, skip, onError);

  @override
  String toString() =>
      'DirectoryScanner(includeHidden: $includeHidden, '
      'followLinks: $followLinks, maxDepth: $maxDepth, '
      'skip: ${skip == null ? 'none' : 'set'}, '
      'onError: ${onError == null ? 'none' : 'set'})';
}

/// The followed target of a link: its type and, for a directory, its fully
/// resolved path. A directory without a resolved path (resolution failed) is
/// stored as [FileSystemEntityType.notFound] so the link is reported as is.
final class _LinkTarget {
  const _LinkTarget(this.type, [this.resolved]);

  final FileSystemEntityType type;
  final String? resolved;
}

/// One step of the explicit walk stack.
sealed class _Step {
  const _Step();
}

/// A directory to list. [resolved] is its real path, tracked only when
/// links are followed.
final class _Visit extends _Step {
  const _Visit(this.directory, this.depth, this.resolved);

  final Directory directory;
  final int depth;
  final String? resolved;
}

/// Marks that the walk has finished the subtree of a directory, so its real
/// path leaves the active branch.
final class _Leave extends _Step {
  const _Leave(this.resolved);

  final String resolved;
}

/// The I/O-free part of a scan, shared by the synchronous and asynchronous
/// walks: the explicit stack, the filters, cycle tracking, and the result.
///
/// The walk is depth first. When links are followed, [_active] holds the
/// real paths of the directory being listed and all of its ancestors: a
/// [_Visit] adds its path and pushes a [_Leave] below its children, which
/// removes the path once the whole subtree has been processed. A directory
/// whose real path is already active would repeat an ancestor, so it is not
/// entered. Membership is a hash lookup, so cycle checks stay O(1) however
/// deep the tree is.
final class _Walk {
  _Walk(this._scanner, Directory root, {required String? rootResolved}) {
    _entries.add(TreeEntry<FileSystemEntity>.directory(root.path, data: root));
    if (_scanner.maxDepth != 0) _stack.add(_Visit(root, 0, rootResolved));
  }

  final DirectoryScanner _scanner;
  final List<TreeEntry<FileSystemEntity>> _entries =
      <TreeEntry<FileSystemEntity>>[];
  final List<_Step> _stack = <_Step>[];
  final Set<String> _active = HashSet<String>();

  bool get isNotDone => _stack.isNotEmpty;

  /// Pops the next step; returns the directory to list, or `null` when the
  /// step only closed a subtree.
  _Visit? next() {
    final step = _stack.removeLast();
    switch (step) {
      case _Leave(:final resolved):
        _active.remove(resolved);
        return null;
      case _Visit(:final resolved):
        if (resolved != null) {
          _active.add(resolved);
          _stack.add(_Leave(resolved));
        }
        return step;
    }
  }

  bool isHidden(FileSystemEntity entity) =>
      !_scanner.includeHidden && _nameOf(entity.path).startsWith('.');

  /// Adds a child that needs no link resolution: a directory, a file, or a
  /// link that is not followed.
  void add(FileSystemEntity entity, _Visit parent) {
    if (entity is Directory) {
      final parentResolved = parent.resolved;
      final resolved = parentResolved == null
          ? null
          : _join(parentResolved, _nameOf(entity.path));
      _addDirectory(entity, parent, resolved);
    } else {
      _addFile(entity);
    }
  }

  /// Adds a link that is followed, given its resolved [target].
  void addLink(Link link, _Visit parent, _LinkTarget target) {
    final resolved = target.resolved;
    switch (target.type) {
      case FileSystemEntityType.directory when resolved != null:
        if (_active.contains(resolved)) {
          _addFile(link); // A cycle: report the link itself, never enter it.
        } else {
          _addDirectory(Directory(link.path), parent, resolved);
        }
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.directory:
        _addFile(link);
      default:
        _addFile(File(link.path));
    }
  }

  void _addDirectory(Directory directory, _Visit parent, String? resolved) {
    if (_scanner.skip?.call(directory) ?? false) return;
    _entries.add(
      TreeEntry<FileSystemEntity>.directory(directory.path, data: directory),
    );
    final depth = parent.depth + 1;
    final maxDepth = _scanner.maxDepth;
    if (maxDepth != null && depth >= maxDepth) return;
    // A real directory that is already on the active branch can only be
    // reached again through a followed link above the scan root; listing it
    // would repeat the branch, so it is reported but not entered.
    if (resolved != null && _active.contains(resolved)) return;
    _stack.add(_Visit(directory, depth, resolved));
  }

  void _addFile(FileSystemEntity entity) {
    if (_scanner.skip?.call(entity) ?? false) return;
    _entries.add(TreeEntry<FileSystemEntity>.file(entity.path, data: entity));
  }

  List<TreeEntry<FileSystemEntity>> sortedEntries() =>
      _entries..sort((a, b) => a.path.compareTo(b.path));
}

/// The last path segment as `dart:io` reports it (children never end with a
/// separator).
String _nameOf(String path) {
  var end = path.lastIndexOf('/');
  if (Platform.isWindows) {
    final backslash = path.lastIndexOf(r'\');
    if (backslash > end) end = backslash;
  }
  return path.substring(end + 1);
}

String _join(String directory, String name) {
  final separator = Platform.pathSeparator;
  return directory.endsWith(separator) || directory.endsWith('/')
      ? '$directory$name'
      : '$directory$separator$name';
}
