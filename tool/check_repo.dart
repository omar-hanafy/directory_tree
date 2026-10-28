/// Enforces repository rules that neither lints nor tests can express.
///
/// Checks (deterministic, no network):
/// - no em-dash character (U+2014) in text files Git tracks or would track
///   (tracked plus untracked files that `.gitignore` does not exclude);
/// - CHANGELOG.md has a `## <version>` section for the pubspec version, and
///   its first section is either that version or `## Unreleased`;
/// - nothing under `lib/` imports a platform-specific `dart:` library, so
///   the core package supports every platform, including the web. The
///   optional scanner library (`lib/io.dart` and `lib/src/io/`) may import
///   `dart:io`, and no other file under `lib/` may import or export it;
/// - every `@Deprecated` under `lib/` names its removal version as
///   "removed in X.0.0", and none survives into that major version.
///
/// Run with `dart run tool/check_repo.dart`; it checks the repository that
/// contains this script, whatever the current directory is.
/// Exits non-zero when any check fails; prints every failure.
library;

import 'dart:io';

final List<String> _errors = <String>[];

/// Libraries that are unavailable on at least one platform the package
/// supports.
const Set<String> _platformOnly = <String>{
  'dart:io',
  'dart:ffi',
  'dart:html',
  'dart:isolate',
  'dart:js',
  'dart:js_interop',
  'dart:js_interop_unsafe',
  'dart:js_util',
  'dart:mirrors',
};

/// The optional `dart:io` scanner library and its implementation files.
const String _ioLibrary = 'lib/io.dart';
const String _ioDirectory = 'lib/src/io/';
const String _packageUriPrefix = 'package:directory_tree/';

void main() {
  Directory.current = File.fromUri(Platform.script).parent.parent;

  final version = _pubspecVersion();
  _checkEmDashes();
  if (version != null) {
    _checkChangelog(version);
    _checkDeprecations(version);
  }
  _checkPlatformImports();

  if (_errors.isEmpty) {
    stdout.writeln('Repository checks passed.');
    return;
  }
  stderr.writeln('Repository checks failed:');
  for (final error in _errors) {
    stderr.writeln('  - $error');
  }
  exitCode = 1;
}

String? _pubspecVersion() {
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    _errors.add('pubspec.yaml is missing.');
    return null;
  }
  final match = RegExp(
    r'''^version:\s*['"]?([^'"\s]+)['"]?\s*$''',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  if (match == null) _errors.add('pubspec.yaml has no version line.');
  return match?.group(1);
}

/// Tracked files plus untracked files that are not ignored, so a new file
/// fails locally before it is committed, exactly as it will in CI.
List<String> _repositoryFiles() {
  final result = Process.runSync('git', <String>[
    'ls-files',
    '-z',
    '--cached',
    '--others',
    '--exclude-standard',
  ]);
  if (result.exitCode != 0) {
    _errors.add('git ls-files failed: ${result.stderr}');
    return const <String>[];
  }
  final output = result.stdout;
  if (output is! String) return const <String>[];
  return output
      .split('\u0000')
      .where((path) => path.isNotEmpty && File(path).existsSync())
      .toSet()
      .toList();
}

void _checkEmDashes() {
  for (final path in _repositoryFiles()) {
    final String text;
    try {
      text = File(path).readAsStringSync();
    } on FileSystemException {
      continue; // Binary or not valid UTF-8.
    } on FormatException {
      continue;
    }
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains('\u2014')) {
        _errors.add("$path:${i + 1}: em-dash character; use '-' instead.");
      }
    }
  }
}

void _checkChangelog(String version) {
  final changelog = File('CHANGELOG.md');
  if (!changelog.existsSync()) {
    _errors.add('CHANGELOG.md is missing.');
    return;
  }
  final headings = RegExp(r'^## (.+?)\s*$', multiLine: true)
      .allMatches(changelog.readAsStringSync())
      .map((match) => match.group(1)!)
      .toList();
  if (!headings.contains(version)) {
    _errors.add('CHANGELOG.md has no "## $version" section.');
  }
  if (headings.isNotEmpty &&
      headings.first != version &&
      headings.first != 'Unreleased') {
    _errors.add(
      'CHANGELOG.md starts with "## ${headings.first}"; the first section '
      'must be "## $version" or "## Unreleased".',
    );
  }
}

void _checkPlatformImports() {
  // One directive, possibly spread over several lines, up to its `;`.
  // Conditional imports carry extra URIs after `if (...)`.
  final directive = RegExp(
    r'^[ \t]*(?:import|export)\b[^;]*;',
    multiLine: true,
  );
  final quotedUri = RegExp('''['"]([^'"]+)['"]''');
  for (final file in _dartFilesUnder('lib')) {
    final path = _posix(file.path);
    final inIoLibrary = path == _ioLibrary || path.startsWith(_ioDirectory);
    final text = file.readAsStringSync();
    for (final match in directive.allMatches(text)) {
      final line = '\n'.allMatches(text.substring(0, match.start)).length + 1;
      final where = '$path:$line';
      for (final uriMatch in quotedUri.allMatches(match.group(0)!)) {
        final uri = uriMatch.group(1)!;
        if (_platformOnly.contains(uri)) {
          if (inIoLibrary && uri == 'dart:io') continue;
          _errors.add(
            inIoLibrary
                ? '$where: $uri is platform-specific; the scanner library '
                      'may import dart:io only.'
                : '$where: $uri is platform-specific; only $_ioLibrary and '
                      '$_ioDirectory may import dart:io.',
          );
        } else if (!inIoLibrary && _isIoLibraryFile(path, uri)) {
          _errors.add(
            '$where: imports or exports the dart:io scanner library ($uri); '
            'the core library must run on every platform.',
          );
        }
      }
    }
  }
}

/// Whether [uri], written in the file at [fromPath], refers to the scanner
/// library or one of its implementation files.
bool _isIoLibraryFile(String fromPath, String uri) {
  final String target;
  if (uri.startsWith(_packageUriPrefix)) {
    target = 'lib/${uri.substring(_packageUriPrefix.length)}';
  } else if (uri.contains(':')) {
    return false; // Another package or a dart: library.
  } else {
    target = Uri.parse(fromPath).resolve(uri).path;
  }
  return target == _ioLibrary || target.startsWith(_ioDirectory);
}

void _checkDeprecations(String version) {
  final major = int.tryParse(version.split('.').first);
  final annotation = RegExp(r'@Deprecated\(');
  final bareAnnotation = RegExp(r'@deprecated\b');
  final removal = RegExp(r'removed in (\d+)\.0\.0');
  for (final file in _dartFilesUnder('lib')) {
    final path = _posix(file.path);
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final where = '$path:${i + 1}';
      if (bareAnnotation.hasMatch(lines[i])) {
        _errors.add(
          '$where: use @Deprecated("... removed in X.0.0") instead of '
          '@deprecated, so the removal version is stated.',
        );
        continue;
      }
      if (!annotation.hasMatch(lines[i])) continue;
      // The message may wrap onto the next lines of the annotation.
      final text = lines.skip(i).take(4).join(' ');
      final target = removal.firstMatch(text);
      if (target == null) {
        _errors.add('$where: @Deprecated must say "removed in X.0.0".');
      } else if (major != null && int.parse(target.group(1)!) <= major) {
        _errors.add(
          '$where: deprecated for removal in ${target.group(1)}.0.0, but '
          'the package is at $version. Delete it and its dart fix shim test.',
        );
      }
    }
  }
}

Iterable<File> _dartFilesUnder(String directory) {
  final root = Directory(directory);
  if (!root.existsSync()) return const <File>[];
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

String _posix(String path) => path.replaceAll(r'\', '/');
