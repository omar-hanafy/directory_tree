/// Enforces repository rules that neither lints nor tests can express.
///
/// Repository checks run with `dart run tool/check_repo.dart`. They are
/// deterministic and need no network:
/// - no em-dash character (U+2014) in text files Git tracks or would track
///   (tracked plus untracked files that `.gitignore` does not exclude);
/// - CHANGELOG.md has a section for the pubspec version, and its first
///   section is either that version or `Unreleased` (`## 2.0.0`,
///   `## [2.0.0] - 2026-10-29`, and `## [Unreleased]` are all recognized);
/// - nothing under `lib/` imports a platform-specific `dart:` library, so
///   the core package supports every platform, including the web and
///   WebAssembly. Only `dart:async`, `dart:collection`, `dart:convert`,
///   `dart:core`, `dart:developer`, `dart:math`, and `dart:typed_data` exist
///   everywhere; `dart:html`, `dart:js_interop`, `dart:ui_web`, and every
///   other `dart:` library do not. The optional scanner library
///   (`lib/io.dart` and `lib/src/io/`) may import `dart:io` and nothing else
///   platform-specific, and no other file under `lib/` may import, export,
///   or include as a part any of its files. A part file follows the rules of
///   the library it belongs to, not those of the directory it sits in;
/// - every `@Deprecated` under `lib/` says "removed in X.0.0" in its own
///   message, and none survives into that major version. A bare
///   `@deprecated` states no version, so it fails too.
///
/// Release checks run with `dart run tool/check_repo.dart --release`. They
/// require that the package resolves from pub.dev exactly as its users
/// resolve it:
/// - the repository root has no `pubspec_overrides.yaml`;
/// - the root `pubspec.yaml` has no `path` or `git` dependency and no
///   `dependency_overrides` section. The `benchmark/` packages are not
///   published and depend on local paths by design, so they are not checked.
///
/// Both modes check the repository that contains this script, whatever the
/// current directory is. They print every failure and exit non-zero when any
/// check fails.
library;

import 'dart:io';

/// Every failure found so far, printed together at the end.
final List<String> _errors = <String>[];

const String _usage = 'Usage: dart run tool/check_repo.dart [--release]';

/// The em-dash character (U+2014). Built from its code point so that this
/// file, which the em-dash check reads too, never contains the character.
final String _emDash = String.fromCharCode(0x2014);

/// The `dart:` libraries that the Dart VM, JavaScript, and WebAssembly all
/// support. Every other `dart:` library works on only some of them
/// (`dart:io`, `dart:ffi`, `dart:isolate`, `dart:mirrors`, `dart:cli`, and
/// `dart:concurrent` on the native VM; `dart:html`, `dart:svg`, `dart:ui_web`,
/// and every `dart:js` library on the web), so none may appear under `lib/`
/// except `dart:io` in the scanner library. An allowlist also rejects a
/// platform library that a future SDK adds.
const Set<String> _portableLibraries = <String>{
  'dart:async',
  'dart:collection',
  'dart:convert',
  'dart:core',
  'dart:developer',
  'dart:math',
  'dart:typed_data',
};

/// The optional `dart:io` scanner library and its implementation files.
const String _ioLibrary = 'lib/io.dart';
const String _ioDirectory = 'lib/src/io/';
const String _packageUriPrefix = 'package:directory_tree/';

/// The keywords that start a directive that names another file.
const Set<String> _directiveKeywords = <String>{'import', 'export', 'part'};

/// The `pubspec.yaml` sections whose entries name dependencies.
const Set<String> _dependencySections = <String>{
  'dependencies',
  'dev_dependencies',
};

/// Runs the repository checks, or the release checks with `--release`.
void main(List<String> arguments) {
  if (arguments.contains('-h') || arguments.contains('--help')) {
    stdout.writeln(_usage);
    return;
  }
  final unknown = arguments.where((argument) => argument != '--release');
  if (unknown.isNotEmpty) {
    stderr
      ..writeln('Unknown argument: ${unknown.first}')
      ..writeln(_usage);
    exitCode = 64;
    return;
  }

  final script = Platform.script;
  if (script.isScheme('file')) {
    Directory.current = File.fromUri(script).parent.parent;
  }

  final String title;
  if (arguments.contains('--release')) {
    title = 'Release checks';
    _checkReleaseDependencies();
  } else {
    title = 'Repository checks';
    final version = _pubspecVersion();
    _checkEmDashes();
    final sources = _dartSources('lib');
    if (version != null) {
      _checkChangelog(version);
      _checkDeprecations(version, sources);
    }
    _checkPlatformImports(sources);
  }

  if (_errors.isEmpty) {
    stdout.writeln('$title passed.');
    return;
  }
  stderr.writeln('$title failed:');
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
    r'''^version:[ \t]*['"]?([^'"\s#]+)['"]?[ \t]*(?:#.*)?$''',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  if (match == null) _errors.add('pubspec.yaml has no version line.');
  return match?.group(1);
}

/// Tracked files plus untracked files that are not ignored, so a new file
/// fails locally before it is committed, exactly as it will in CI.
List<String> _repositoryFiles() {
  final ProcessResult result;
  try {
    result = Process.runSync('git', <String>[
      'ls-files',
      '-z',
      '--cached',
      '--others',
      '--exclude-standard',
    ]);
  } on ProcessException catch (error) {
    _errors.add('git is not available: ${error.message}');
    return const <String>[];
  }
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
      continue; // Unreadable, or not valid UTF-8 (a binary file).
    } on FormatException {
      continue;
    }
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains(_emDash)) {
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
  final headings = _changelogHeadings(changelog.readAsLinesSync());
  if (!headings.any((heading) => heading.version == version)) {
    _errors.add('CHANGELOG.md has no "## $version" section.');
  }
  if (headings.isNotEmpty &&
      headings.first.version != version &&
      headings.first.version != 'Unreleased') {
    _errors.add(
      'CHANGELOG.md starts with "## ${headings.first.title}"; the first '
      'section must be "## $version" or "## Unreleased".',
    );
  }
}

/// The level-2 headings of a changelog outside fenced code blocks, in
/// order, each with its full text and the version (or `Unreleased`) it
/// names: `## 2.0.0`, `## [2.0.0] - 2026-10-29`, and `## v2.0.0 (2026-10-29)`
/// all name `2.0.0`.
List<({String title, String version})> _changelogHeadings(List<String> lines) {
  final heading = RegExp(r'^##[ \t]+(.+?)[ \t]*$');
  final name = RegExp(r'^\[?v?([^\]\s]+)');
  final headings = <({String title, String version})>[];
  var inFence = false;
  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    final title = heading.firstMatch(line)?[1];
    final version = title == null ? null : name.firstMatch(title)?[1];
    if (title != null && version != null) {
      headings.add((title: title, version: version));
    }
  }
  return headings;
}

void _checkPlatformImports(List<_Source> sources) {
  final directives = <String, List<_Directive>>{
    for (final source in sources) source.path: _directivesOf(source),
  };
  for (final MapEntry(key: path, value: found) in directives.entries) {
    // A part file follows the rules of the library it belongs to, so an
    // import in a part is judged exactly as if the library had written it.
    final inIoLibrary = _isIoFile(_libraryOf(path, directives));
    for (final directive in found) {
      if (directive.keyword == 'part of') continue; // Not a dependency.
      final where = '$path:${directive.line}';
      for (final uri in directive.uris) {
        if (uri.startsWith('dart:')) {
          if (_portableLibraries.contains(uri)) continue;
          if (inIoLibrary) {
            if (uri != 'dart:io') {
              _errors.add(
                '$where: $uri is platform-specific; the scanner library '
                'may import dart:io only.',
              );
            }
          } else if (uri == 'dart:io') {
            _errors.add(
              '$where: $uri is platform-specific; only $_ioLibrary and '
              '$_ioDirectory may import dart:io.',
            );
          } else {
            _errors.add(
              '$where: $uri is platform-specific; the core library must run '
              'on every platform.',
            );
          }
        } else if (!inIoLibrary && _isIoFile(_resolveUri(path, uri))) {
          final what = directive.keyword == 'part'
              ? 'includes the dart:io scanner file ($uri) as a part'
              : 'imports or exports the dart:io scanner library ($uri)';
          _errors.add(
            '$where: $what; the core library must run on every platform.',
          );
        }
      }
    }
  }
}

/// Whether [path] is the scanner library or one of its implementation files.
bool _isIoFile(String? path) =>
    path != null && (path == _ioLibrary || path.startsWith(_ioDirectory));

/// The repository-relative path that [uri], written in the file at
/// [fromPath], refers to, or null for a `dart:` library or another package.
String? _resolveUri(String fromPath, String uri) {
  if (uri.startsWith(_packageUriPrefix)) {
    return Uri.parse(
      'lib/${uri.substring(_packageUriPrefix.length)}',
    ).normalizePath().path;
  }
  if (uri.contains(':')) return null;
  return Uri.parse(fromPath).resolve(uri).path;
}

/// The library file that the file at [path] belongs to: [path] itself, or,
/// for a part file, the library its `part of` directive names, followed
/// through nested parts. A library owns a part only if it lists it in a
/// `part` directive, so a stray `part of` cannot borrow the scanner
/// library's exemption. A part that no library under `lib/` claims stands
/// for itself (or for the last library found).
String _libraryOf(String path, Map<String, List<_Directive>> directives) {
  var library = path;
  final visited = <String>{};
  while (visited.add(library)) {
    final uri = directives[library]
        ?.where((directive) => directive.keyword == 'part of')
        .expand((directive) => directive.uris)
        .firstOrNull;
    final next = uri == null ? null : _resolveUri(library, uri);
    if (next == null || !_listsPart(directives[next], next, library)) break;
    library = next;
  }
  return library;
}

/// Whether the file at [libraryPath], whose directives are [directives],
/// lists the file at [partPath] in a `part` directive.
bool _listsPart(
  List<_Directive>? directives,
  String libraryPath,
  String partPath,
) =>
    directives != null &&
    directives.any(
      (directive) =>
          directive.keyword == 'part' &&
          directive.uris.any(
            (uri) => _resolveUri(libraryPath, uri) == partPath,
          ),
    );

void _checkDeprecations(String version, List<_Source> sources) {
  final major = int.tryParse(version.split('.').first);
  final removal = RegExp(r'removed in (\d+)\.0\.0');
  for (final source in sources) {
    final tokens = source.tokens;
    for (var i = 0; i + 1 < tokens.length; i++) {
      if (!tokens[i].isSymbol('@')) continue;
      final name = tokens[i + 1];
      if (name.isWord('deprecated')) {
        _errors.add(
          '${source.where(tokens[i])}: use @Deprecated("... removed in '
          'X.0.0") instead of @deprecated, so the removal version is stated.',
        );
      } else if (name.isWord('Deprecated')) {
        final where = source.where(tokens[i]);
        // Only this annotation's own message counts, however many lines or
        // adjacent string literals it spans, and whatever follows it.
        final target = removal.firstMatch(_deprecationMessage(tokens, i + 2));
        final removedIn = int.tryParse(target?[1] ?? '');
        if (target == null) {
          _errors.add('$where: @Deprecated must say "removed in X.0.0".');
        } else if (major != null && removedIn != null && removedIn <= major) {
          _errors.add(
            '$where: deprecated for removal in ${target[1]}.0.0, but the '
            'package is at $version. Delete it and its dart fix shim test.',
          );
        }
      }
    }
  }
}

/// The string literals in the arguments of the `@Deprecated` annotation
/// whose name ends just before `tokens[index]`, concatenated, from its
/// opening parenthesis to the matching closing one. A named constructor,
/// as in `@Deprecated.extend('...')`, comes first. Parentheses inside string
/// literals are not tokens, so they never end the arguments.
String _deprecationMessage(List<_Token> tokens, int index) {
  var open = index;
  if (open + 1 < tokens.length &&
      tokens[open].isSymbol('.') &&
      tokens[open + 1].kind == _TokenKind.word) {
    open += 2;
  }
  if (open >= tokens.length || !tokens[open].isSymbol('(')) return '';
  final message = StringBuffer();
  var depth = 0;
  for (var i = open; i < tokens.length; i++) {
    final token = tokens[i];
    if (token.isSymbol('(')) {
      depth++;
    } else if (token.isSymbol(')')) {
      depth--;
      if (depth == 0) break;
    } else if (token.isString) {
      message.write(token.text);
    }
  }
  return message.toString();
}

void _checkReleaseDependencies() {
  // Only the root package is published. The benchmark packages depend on
  // local paths by design and are not checked.
  if (FileSystemEntity.typeSync('pubspec_overrides.yaml', followLinks: false) !=
      FileSystemEntityType.notFound) {
    _errors.add(
      'pubspec_overrides.yaml: development override; delete it before '
      'releasing, so dependencies resolve from pub.dev.',
    );
  }

  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    _errors.add('pubspec.yaml is missing.');
    return;
  }
  final lines = pubspec.readAsLinesSync();
  final reported = <String>{};
  String? section;
  String? dependency;
  int? entryIndent;
  for (var i = 0; i < lines.length; i++) {
    final line = _withoutYamlComment(lines[i]);
    if (line.trim().isEmpty) continue;
    final where = 'pubspec.yaml:${i + 1}';
    final indent = line.length - line.trimLeft().length;
    if (indent == 0) {
      section = _yamlKey(line);
      dependency = null;
      entryIndent = null;
      if (section == 'dependency_overrides') {
        _errors.add(
          '$where: dependency_overrides; remove them before releasing, so '
          'tests run against the versions users resolve.',
        );
      }
      continue;
    }
    if (!_dependencySections.contains(section)) continue;
    entryIndent ??= indent;
    final String? source;
    if (indent <= entryIndent) {
      // A dependency entry; its source may be an inline map:
      // `name: {path: ../name}`.
      dependency = _yamlKey(line);
      source = RegExp(r'[{,][ \t]*(path|git)[ \t]*:').firstMatch(line)?[1];
    } else {
      source = RegExp(r'^[ \t]*(path|git)[ \t]*:').firstMatch(line)?[1];
    }
    if (source != null && dependency != null && reported.add(dependency)) {
      _errors.add(
        '$where: $dependency is a $source dependency in $section; depend on '
        'a pub.dev version before releasing.',
      );
    }
  }
}

/// The key of a YAML mapping line (`name` for `  name: value`), or null.
String? _yamlKey(String line) =>
    RegExp(r'^[ \t]*([^\s:#{}\[\],]+)[ \t]*:').firstMatch(line)?[1];

/// [line] without its YAML comment: a `#` that starts the line or follows
/// whitespace starts a comment.
String _withoutYamlComment(String line) {
  final match = RegExp(r'(?:^|[ \t])#').firstMatch(line);
  return match == null ? line : line.substring(0, match.start);
}

/// The Dart files under [directory], with their tokens, sorted by path. A
/// file that is not valid UTF-8 text is reported instead of read.
List<_Source> _dartSources(String directory) {
  final root = Directory(directory);
  if (!root.existsSync()) return const <_Source>[];
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final sources = <_Source>[];
  for (final file in files) {
    final path = _posix(file.path);
    final String text;
    try {
      text = file.readAsStringSync();
    } on Exception {
      _errors.add('$path: cannot be read as UTF-8 text.');
      continue;
    }
    sources.add(_Source(path, text));
  }
  return sources;
}

String _posix(String path) => path.replaceAll(r'\', '/');

/// A Dart file split into [tokens].
class _Source {
  _Source(this.path, this.text) : tokens = _Lexer(text).tokenize();

  /// The repository-relative path, with `/` separators.
  final String path;
  final String text;
  final List<_Token> tokens;

  /// The 1-based line that contains the character at [offset].
  int lineAt(int offset) =>
      '\n'.allMatches(text.substring(0, offset)).length + 1;

  /// `path:line` of [token], the way failures name a location.
  String where(_Token token) => '$path:${lineAt(token.offset)}';
}

/// An `import`, `export`, `part`, or `part of` directive.
class _Directive {
  const _Directive(this.keyword, this.line, this.uris);

  /// `import`, `export`, `part`, or `part of`.
  final String keyword;

  /// The 1-based line of the keyword.
  final int line;

  /// The URIs the directive names. A conditional directive names several:
  /// `import 'a.dart' if (dart.library.io) 'b.dart';` names both files. The
  /// older `part of library.name;` names its library without a URI.
  final List<String> uris;
}

/// The directives of [source] that name another file.
List<_Directive> _directivesOf(_Source source) {
  final tokens = source.tokens;
  final directives = <_Directive>[];
  for (var i = 0; i < tokens.length; i++) {
    final keyword = tokens[i];
    if (keyword.kind != _TokenKind.word ||
        !_directiveKeywords.contains(keyword.text)) {
      continue;
    }
    var next = i + 1;
    if (keyword.text == 'part' &&
        next < tokens.length &&
        tokens[next].isWord('of')) {
      next++;
      directives.add(
        _Directive('part of', source.lineAt(keyword.offset), <String>[
          if (next < tokens.length && tokens[next].isString) tokens[next].text,
        ]),
      );
      continue;
    }
    if (next < tokens.length && tokens[next].isWord('augment')) next++;
    // A directive names its file by a string literal. An identifier called
    // `part` or `import` followed by anything else is ordinary code.
    if (next >= tokens.length || !tokens[next].isString) continue;
    final uris = <String>[];
    var depth = 0;
    for (var j = next; j < tokens.length && !tokens[j].isSymbol(';'); j++) {
      final token = tokens[j];
      if (token.isSymbol('(')) depth++;
      if (token.isSymbol(')')) depth--;
      // Strings inside an `if (...)` condition are not URIs.
      if (token.isString && depth == 0) uris.add(token.text);
    }
    directives.add(
      _Directive(keyword.text, source.lineAt(keyword.offset), uris),
    );
  }
  return directives;
}

/// What a [_Token] is.
enum _TokenKind { word, string, symbol }

/// A word, a string literal, or a punctuation character of Dart source.
class _Token {
  const _Token(this.kind, this.text, this.offset);

  final _TokenKind kind;

  /// The word, the content of the string literal without its quotes (escapes
  /// and interpolations stay as written), or the punctuation character.
  final String text;

  /// The offset of the token's first character in the source.
  final int offset;

  bool get isString => kind == _TokenKind.string;

  bool isWord(String word) => kind == _TokenKind.word && text == word;

  bool isSymbol(String symbol) => kind == _TokenKind.symbol && text == symbol;
}

final RegExp _wordCharacter = RegExp(r'[A-Za-z0-9_$]');

/// A minimal Dart lexer: enough to read directives and annotations without
/// mistaking look-alikes inside comments and strings for code.
///
/// Whitespace and comments (block comments nest, as in Dart) produce no
/// tokens. A string literal of any form (single, double, or triple quoted;
/// raw; with `${...}` interpolations) is one token, and adjacent literals,
/// which Dart joins, are one token too. So quotes, parentheses, and
/// semicolons inside a string or a comment never look like code.
class _Lexer {
  _Lexer(this._source);

  final String _source;
  int _position = 0;

  List<_Token> tokenize() {
    final tokens = <_Token>[];
    _scan(tokens);
    return tokens;
  }

  /// Scans to the end of the source or, with [inInterpolation], past the `}`
  /// that closes a `${...}` interpolation. Adds the tokens to [out] when it
  /// is not null; the tokens of an interpolation are discarded.
  void _scan(List<_Token>? out, {bool inInterpolation = false}) {
    var braces = 0;
    while (_position < _source.length) {
      final start = _position;
      final char = _source[start];
      if (char.trim().isEmpty) {
        _position++;
      } else if (_source.startsWith('//', start)) {
        _skipLineComment();
      } else if (_source.startsWith('/*', start)) {
        _skipBlockComment();
      } else if (char == "'" || char == '"') {
        _addString(out, _readString(raw: false), start);
      } else if (_wordCharacter.hasMatch(char)) {
        final word = _readWord();
        if (word == 'r' && _atQuote) {
          _addString(out, _readString(raw: true), start);
        } else {
          out?.add(_Token(_TokenKind.word, word, start));
        }
      } else {
        _position++;
        if (inInterpolation && char == '{') braces++;
        if (inInterpolation && char == '}') {
          if (braces == 0) return;
          braces--;
        }
        out?.add(_Token(_TokenKind.symbol, char, start));
      }
    }
  }

  bool get _atQuote =>
      _position < _source.length &&
      (_source[_position] == "'" || _source[_position] == '"');

  String _readWord() {
    final start = _position;
    while (_position < _source.length &&
        _wordCharacter.hasMatch(_source[_position])) {
      _position++;
    }
    return _source.substring(start, _position);
  }

  void _skipLineComment() {
    while (_position < _source.length &&
        _source[_position] != '\n' &&
        _source[_position] != '\r') {
      _position++;
    }
  }

  void _skipBlockComment() {
    var depth = 0;
    while (_position < _source.length) {
      if (_source.startsWith('/*', _position)) {
        depth++;
        _position += 2;
      } else if (_source.startsWith('*/', _position)) {
        depth--;
        _position += 2;
        if (depth == 0) return;
      } else {
        _position++;
      }
    }
  }

  /// Reads the string literal that starts at the current quote and returns
  /// its content. An unterminated literal ends at its line (or, if it is
  /// triple quoted, at the end of the file).
  String _readString({required bool raw}) {
    final quote = _source[_position];
    final triple = _source.startsWith(quote * 3, _position);
    final closing = triple ? quote * 3 : quote;
    _position += closing.length;
    final content = StringBuffer();
    while (_position < _source.length) {
      final char = _source[_position];
      if (_source.startsWith(closing, _position)) {
        _position += closing.length;
        break;
      }
      if (!triple && (char == '\n' || char == '\r')) break;
      if (!raw && char == r'\') {
        // An escape: keep it as written and never let it end the string.
        final end = _position + 2 < _source.length
            ? _position + 2
            : _source.length;
        content.write(_source.substring(_position, end));
        _position = end;
      } else if (!raw &&
          char == r'$' &&
          _source.startsWith('{', _position + 1)) {
        // An interpolation can hold quotes and braces of its own.
        final start = _position;
        _position += 2;
        _scan(null, inInterpolation: true);
        content.write(_source.substring(start, _position));
      } else {
        content.write(char);
        _position++;
      }
    }
    return content.toString();
  }

  void _addString(List<_Token>? out, String content, int start) {
    if (out == null) return;
    if (out.isNotEmpty && out.last.isString) {
      final previous = out.removeLast();
      out.add(
        _Token(_TokenKind.string, previous.text + content, previous.offset),
      );
    } else {
      out.add(_Token(_TokenKind.string, content, start));
    }
  }
}
