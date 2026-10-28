import 'package:directory_tree/src/filter/tree_filter.dart';
import 'package:directory_tree/src/tree/directory_tree.dart';
import 'package:meta/meta.dart';

/// A [TreeFilter] parsed from a search string, such as the text of a search
/// box above a file tree.
///
/// Use [TreeQuery.parse] to turn what a user types into a filter, pass it to
/// a view, and call [matchRanges] to highlight the matched parts of each
/// visible label. Parsing never throws: text the syntax does not recognize
/// is searched for literally.
///
/// ## Syntax
///
/// A query is a list of terms separated by whitespace. A node matches when
/// it matches every term (AND).
///
/// | Term | Matches |
/// | --- | --- |
/// | `main` | nodes whose name contains `main` |
/// | `*.dart`, `test_?.md` | nodes whose whole name matches the glob: `*` is any run of characters (including none), `?` is exactly one character |
/// | `lib/src`, `src/ut`, `a/src` | nodes whose canonical path string contains the term at an occurrence that reaches the node's own name (ends inside it or exactly where it starts): `lib/src` matches `src` in `/r/lib/src` but not `/r/lib/src/utils`, and `src/ut` matches `utils` in `/r/lib/src/utils`; `\` is read as `/` |
/// | `lib/`, `lib/src/` | the direct children of directories whose path ends with `lib` or `lib/src` (the same rule: the occurrence ends where each child's name starts), so the view keeps showing results while a path is typed |
/// | `src/*.dart`, `lib/*/*.g.dart` | nodes whose last k path components, joined with `/`, match the glob, where k is the number of `/`-separated parts of the glob; `**` is the same as `*` |
/// | `"my notes"` | nodes whose name contains `my notes`; the quoted text is literal, so `"*.g"` searches for `*.g` and `"ext:x"` for `ext:x`; a phrase with `/` (`"my dir/a b"`) matches like `lib/src` |
/// | `!term` | nodes that do not match `term`; `term` may be any other kind of term, including a quoted phrase |
/// | `ext:dart`, `ext:.dart`, `ext:dart,md` | files whose name ends with `.` plus any listed extension (`ext:tar.gz` works too); directories never match |
/// | `type:file`, `type:f` | files |
/// | `type:dir`, `type:directory`, `type:d` | directories |
/// | `path:lib/src` | nodes whose canonical path string (`TreePath.toString`) contains `lib/src`; `\` in the value is read as `/` |
///
/// Details:
///
/// * Terms without `/` or `\` look at [TreeNode.name] only. Terms with a
///   separator also look at the canonical path string
///   (`TreePath.toString`), so typing what a view shows works: a compacted
///   folder row labelled `lib/src/utils` (see `TreeRows.compactFolders`)
///   matches `lib/src/utils`, `lib/src`, and `src/ut`, and a disambiguated
///   top-level label such as `a/src` ([TreeNode.label]) matches `a/src`.
///   Only the node whose name the occurrence reaches matches, not its
///   deeper descendants, so a view shows the typed folder and its
///   ancestors. A term ending with `/` reaches the names of the folder's
///   direct children, so typing `l`, `lib`, `lib/`, `lib/s`, `lib/src`,
///   `lib/src/` keeps matching all the way. The term `/` alone reaches every
///   name after a separator. Such a term still also matches a name that
///   contains it literally, which only happens for path roots such as `/`
///   or names with a `\` under a policy where `\` is not a separator.
/// * Whitespace is any character that [String.trim] removes, including tabs
///   and line breaks.
/// * A quote starts a phrase only at the start of a term (after an optional
///   `!`) or right after a known `key:`, as in `path:"my dir"`. The phrase
///   ends at the next `"`, or at the end of the query when the quote is
///   never closed; there are no escapes. A `"` anywhere else is an ordinary
///   character. A term ends right after its closing quote, so `"a"b` is the
///   two terms `a` and `b`.
/// * A `!` negates only at the start of a term and only when something
///   follows it; a lone `!` searches for `!`. Only the first `!` negates:
///   `!!a` excludes names containing `!a`.
/// * Keys (`ext`, `type`, `path`) are case-insensitive. A term with an
///   unknown key, an empty value (`ext:`), a `type:` value that is not one of
///   the listed kinds, or an `ext:` value with no extension in it (`ext:.`)
///   is plain text, searched for literally (`foo:bar` matches names
///   containing `foo:bar`).
/// * Empty phrases (`""`, `!""`) are ignored.
///
/// ## Case sensitivity
///
/// Names, path fragments, globs, and `path:` values are compared
/// case-insensitively unless [caseSensitive] is true. `ext:` and `type:`
/// always ignore case, because extensions are conventionally
/// case-insensitive (`IMG.JPG` is a `jpg` file) and kinds are keywords.
/// Case-insensitive comparison lowercases each character on its own and
/// keeps a character unchanged when lowercasing would change its length
/// (such as `İ`), so [matchRanges] indexes line up with the original text.
/// It is not full Unicode case folding: `ß` does not match `ss`.
///
/// ## Examples
///
/// ```dart
/// final tree = DirectoryTree.fromPaths([
///   '/repo/lib/main.dart',
///   '/repo/lib/main.g.dart',
///   '/repo/README.md',
/// ]);
///
/// final query = TreeQuery.parse('ext:dart !*.g.dart');
/// tree.nodes.where(query.matches).map((n) => n.name); // (main.dart)
///
/// TreeQuery.parse('MAIN').matchRanges('main.dart'); // [(start: 0, end: 4)]
/// TreeQuery.parse('   ').matchesAll; // true
///
/// // Typing a path fragment, as shown by a compacted row.
/// final lib = TreeQuery.parse('repo/lib');
/// tree.nodes.where(lib.matches).map((n) => n.name); // (lib)
/// lib.matchRanges('repo/lib'); // [(start: 0, end: 8)]
///
/// // A trailing `/` lists the folder's contents.
/// final contents = TreeQuery.parse('repo/lib/');
/// tree.nodes.where(contents.matches).map((n) => n.name);
/// // (main.dart, main.g.dart)
///
/// final generated = TreeQuery.parse('lib/*.g.dart');
/// tree.nodes.where(generated.matches).map((n) => n.name); // (main.g.dart)
/// ```
///
/// Combine a query with other filters through [and], [or], and [negate].
/// Two queries are equal when their [source] and [caseSensitive] are equal.
@immutable
final class TreeQuery extends TreeFilter {
  TreeQuery._(this.source, this.caseSensitive, this._terms, this._highlights);

  /// Parses [query] into a filter. Never throws.
  ///
  /// Text that is not valid syntax is searched for literally (see the
  /// [TreeQuery] class documentation for the full syntax). An empty or
  /// whitespace-only [query] yields a query that [matchesAll].
  ///
  /// [caseSensitive] makes name, glob, and `path:` terms compare case
  /// exactly; `ext:` and `type:` terms ignore case either way.
  ///
  /// Runs in O(length of [query]).
  factory TreeQuery.parse(String query, {bool caseSensitive = false}) {
    final terms = _Parser(query, caseSensitive: caseSensitive).parse();
    final highlights = <String>[
      for (final term in terms)
        if (!term.negated && term is _TextTerm) ...term.highlights,
    ];
    return TreeQuery._(
      query,
      caseSensitive,
      List<_Term>.unmodifiable(terms),
      List<String>.unmodifiable(highlights),
    );
  }

  /// The query text exactly as passed to [TreeQuery.parse].
  final String source;

  /// Whether name, glob, and `path:` terms compare case exactly.
  ///
  /// `ext:` and `type:` terms ignore case either way.
  final bool caseSensitive;

  final List<_Term> _terms;

  /// The search texts of positive plain terms, already case-folded when
  /// [caseSensitive] is false.
  final List<String> _highlights;

  /// Whether this query has no terms, so it accepts every node.
  ///
  /// True exactly when [source] is empty, contains only whitespace, or
  /// contains only empty phrases such as `""`. A query such as `*` also
  /// matches every name but still reports false, because it has a term.
  @override
  bool get matchesAll => _terms.isEmpty;

  /// Whether [node] matches every term of this query.
  ///
  /// Always true when [matchesAll]. Terms are tested in query order and
  /// testing stops at the first failing term. Runs in
  /// O(terms x (name length + path length)) for plain, key, and quoted terms
  /// (times the term length in the worst case of a highly repetitive
  /// substring search); a glob term costs O(name length x glob length), or
  /// O(path length x glob length) when it contains `/`, in the worst case
  /// and never backtracks exponentially.
  @override
  bool matches(TreeNode<Object?> node) {
    if (_terms.isEmpty) return true;
    final subject = _Subject(node, caseSensitive: caseSensitive);
    for (final term in _terms) {
      if (term.test(subject) == term.negated) return false;
    }
    return true;
  }

  /// The ranges of [text] to highlight: every occurrence of every positive
  /// plain-text term, sorted and merged.
  ///
  /// Plain terms and quoted phrases contribute, including terms with `/`
  /// (so `lib/src` highlights `(start: 0, end: 7)` in a compacted label
  /// `lib/src/utils`; a `\` in such a term is looked for both as typed and
  /// as `/`); globs, `key:value` terms, and negated terms do not. Pass the
  /// text a view displays, such as `TreeRow.label`. Occurrences are found
  /// case-insensitively unless [caseSensitive] is true. Overlapping and
  /// adjacent occurrences merge into one range, so the result is sorted by
  /// `start`, ranges never overlap or touch, and every range is non-empty.
  /// Each range covers `text.substring(start, end)` in UTF-16 code units of
  /// [text] as given.
  ///
  /// Returns an empty list when no term occurs in [text], when [text] is
  /// empty, and when the query has no positive plain terms. For a node that
  /// [matches], the result for its name is non-empty whenever the query has
  /// a positive plain term without `/` or `\`; a term with a separator
  /// usually highlights only in a label that shows the parent folders too.
  /// The returned list is unmodifiable. Runs in O(terms x text length x term
  /// length) in the worst case.
  List<({int start, int end})> matchRanges(String text) {
    if (_highlights.isEmpty || text.isEmpty) {
      return const <({int start, int end})>[];
    }
    final haystack = caseSensitive ? text : _fold(text);
    final found = <({int start, int end})>[];
    for (final needle in _highlights) {
      var index = haystack.indexOf(needle);
      while (index >= 0) {
        found.add((start: index, end: index + needle.length));
        index = haystack.indexOf(needle, index + 1);
      }
    }
    if (found.isEmpty) return const <({int start, int end})>[];
    found.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.end.compareTo(b.end);
    });
    final merged = <({int start, int end})>[];
    var start = found.first.start;
    var end = found.first.end;
    for (var i = 1; i < found.length; i++) {
      final range = found[i];
      if (range.start <= end) {
        if (range.end > end) end = range.end;
      } else {
        merged.add((start: start, end: end));
        start = range.start;
        end = range.end;
      }
    }
    merged.add((start: start, end: end));
    return List<({int start, int end})>.unmodifiable(merged);
  }

  /// Whether [other] is a [TreeQuery] with the same [source] and
  /// [caseSensitive].
  ///
  /// Queries that differ only in spelling, such as `a  b` and `a b`, are not
  /// equal even though they match the same nodes.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TreeQuery &&
          other.source == source &&
          other.caseSensitive == caseSensitive;

  @override
  int get hashCode => Object.hash(TreeQuery, source, caseSensitive);

  /// The [source] in quotes, plus `caseSensitive` when it is set, such as
  /// `TreeQuery('ext:dart main')`.
  @override
  String toString() => caseSensitive
      ? "TreeQuery('$source', caseSensitive)"
      : "TreeQuery('$source')";
}

// ---------------------------------------------------------------------------
// Terms
// ---------------------------------------------------------------------------

/// The parts of a node that terms look at, computed lazily once per
/// [TreeQuery.matches] call so several terms share the work.
final class _Subject {
  _Subject(this.node, {required this.caseSensitive});

  final TreeNode<Object?> node;
  final bool caseSensitive;

  /// The name, folded unless [caseSensitive].
  late final String name = caseSensitive ? node.name : _fold(node.name);

  /// [name] as runes, for globs, where `?` stands for one character.
  late final List<int> nameRunes = name.runes.toList(growable: false);

  /// The name, always folded, for `ext:` terms.
  late final String foldedName = caseSensitive ? _fold(node.name) : name;

  /// The canonical path string, folded unless [caseSensitive].
  late final String path = caseSensitive
      ? node.path.toString()
      : _fold(node.path.toString());

  /// Where the node's own name starts in [path]: the canonical string ends
  /// with the last segment, and a path root is all name. Folding keeps the
  /// length, so this indexes the folded [path] too.
  late final int nameStart = node.path.segments.isEmpty
      ? 0
      : path.length - node.path.segments.last.length;

  /// The last [count] `/`-separated components of [path] as runes, or all of
  /// [path] when it has fewer components. Runs in O(path length).
  List<int> tailRunes(int count) {
    var start = 0;
    var seen = 0;
    for (var i = path.length - 1; i >= 0; i--) {
      if (path.codeUnitAt(i) == _slash && ++seen == count) {
        start = i + 1;
        break;
      }
    }
    return path.substring(start).runes.toList(growable: false);
  }
}

sealed class _Term {
  _Term({required this.negated});

  /// Whether the term was written with a leading `!`. [TreeQuery.matches]
  /// inverts [test] for negated terms.
  final bool negated;

  /// Whether the node matches the term, ignoring [negated].
  bool test(_Subject subject);
}

/// A plain term or quoted phrase: the name contains [text], or, for a term
/// with a separator, the path contains [segmentText] at an occurrence that
/// reaches the node's own name (ends inside it or exactly where it starts).
final class _TextTerm extends _Term {
  _TextTerm(this.text, this.segmentText, {required super.negated});

  /// The search text, folded when the query is case-insensitive. Never empty.
  final String text;

  /// [text] with `\` replaced by `/` when [text] contains `/` or `\`;
  /// otherwise `null`.
  final String? segmentText;

  /// The texts [TreeQuery.matchRanges] looks for.
  List<String> get highlights {
    final segment = segmentText;
    return segment == null || segment == text ? [text] : [text, segment];
  }

  @override
  bool test(_Subject subject) {
    if (subject.name.contains(text)) return true;
    final segment = segmentText;
    if (segment == null) return false;
    // The last occurrence ends furthest right, so it is the only one that
    // needs checking: it reaches the name if any occurrence does.
    final index = subject.path.lastIndexOf(segment);
    return index >= 0 && index + segment.length >= subject.nameStart;
  }
}

/// A plain term containing `*` or `?`: the whole name matches the glob, or,
/// for a glob with a separator, the last [segmentCount] path components
/// match [segmentPattern].
final class _GlobTerm extends _Term {
  _GlobTerm(
    this.pattern,
    this.segmentPattern,
    this.segmentCount, {
    required super.negated,
  });

  /// The pattern as runes (folded when case-insensitive), with runs of `*`
  /// collapsed to one.
  final List<int> pattern;

  /// [pattern] with `\` read as `/`, when the term contains `/` or `\`;
  /// otherwise `null`.
  final List<int>? segmentPattern;

  /// The number of `/`-separated parts of [segmentPattern] (0 without one).
  final int segmentCount;

  @override
  bool test(_Subject subject) {
    if (_globMatches(pattern, subject.nameRunes)) return true;
    final segments = segmentPattern;
    return segments != null &&
        _globMatches(segments, subject.tailRunes(segmentCount));
  }
}

/// `ext:a,b`: a file whose folded name ends with one of [suffixes] and has
/// at least one character before it.
final class _ExtTerm extends _Term {
  _ExtTerm(this.suffixes, {required super.negated});

  /// Folded suffixes including their leading dot, such as `.dart`.
  final List<String> suffixes;

  @override
  bool test(_Subject subject) {
    if (!subject.node.isFile) return false;
    final name = subject.foldedName;
    for (final suffix in suffixes) {
      if (name.length > suffix.length && name.endsWith(suffix)) return true;
    }
    return false;
  }
}

/// `type:file` or `type:dir`.
final class _TypeTerm extends _Term {
  _TypeTerm({required super.negated, required this.directory});

  final bool directory;

  @override
  bool test(_Subject subject) => subject.node.isDirectory == directory;
}

/// `path:value`: the canonical path string contains [text].
final class _PathTerm extends _Term {
  _PathTerm(this.text, {required super.negated});

  /// The value with `\` replaced by `/`, folded when case-insensitive.
  final String text;

  @override
  bool test(_Subject subject) => subject.path.contains(text);
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

const int _quote = 0x22; // "
const int _bang = 0x21; // !
const int _colon = 0x3A; // :
const int _star = 0x2A; // *
const int _question = 0x3F; // ?
const int _slash = 0x2F; // /

/// A single left-to-right pass over the query. Every index is checked
/// against the length before use, so no input can make it throw.
final class _Parser {
  _Parser(this.source, {required this.caseSensitive});

  final String source;
  final bool caseSensitive;
  final List<_Term> terms = <_Term>[];
  int index = 0;

  List<_Term> parse() {
    final length = source.length;
    while (true) {
      while (index < length && _isWhitespace(source.codeUnitAt(index))) {
        index++;
      }
      if (index >= length) break;
      _parseTerm();
    }
    return terms;
  }

  void _parseTerm() {
    final length = source.length;
    var negated = false;
    if (source.codeUnitAt(index) == _bang &&
        index + 1 < length &&
        !_isWhitespace(source.codeUnitAt(index + 1))) {
      negated = true;
      index++;
    }
    if (source.codeUnitAt(index) == _quote) {
      final phrase = _readQuoted();
      if (phrase.isNotEmpty) terms.add(_textTerm(phrase, negated: negated));
      return;
    }
    // A bare word runs to the next whitespace. Quotes inside it are literal,
    // except right after a known key. Only the first colon can end a key.
    final start = index;
    var sawColon = false;
    while (index < length && !_isWhitespace(source.codeUnitAt(index))) {
      if (!sawColon && source.codeUnitAt(index) == _colon) {
        sawColon = true;
        final key = _keyOf(source.substring(start, index));
        if (key != null) {
          index++;
          _parseKeyValue(key, start, negated: negated);
          return;
        }
      }
      index++;
    }
    _addPlain(source.substring(start, index), negated: negated);
  }

  /// Parses the value of a known key; [index] is just past the colon and
  /// [start] is where the word began, for the plain-text fallback.
  void _parseKeyValue(String key, int start, {required bool negated}) {
    final length = source.length;
    String value;
    if (index < length && source.codeUnitAt(index) == _quote) {
      value = _readQuoted();
    } else {
      final valueStart = index;
      while (index < length && !_isWhitespace(source.codeUnitAt(index))) {
        index++;
      }
      value = source.substring(valueStart, index);
    }
    final term = _keyTerm(key, value, negated: negated);
    if (term != null) {
      terms.add(term);
    } else {
      // Not a usable key term: the whole spelling, quotes included, is
      // searched for literally.
      _addPlain(source.substring(start, index), negated: negated);
    }
  }

  /// Reads a phrase starting at the opening quote at [index] and leaves
  /// [index] just past the closing quote (or at the end of the source).
  String _readQuoted() {
    final contentStart = index + 1;
    final close = source.indexOf('"', contentStart);
    if (close < 0) {
      index = source.length;
      return source.substring(contentStart);
    }
    index = close + 1;
    return source.substring(contentStart, close);
  }

  void _addPlain(String text, {required bool negated}) {
    // Callers only pass non-empty words, but stay defensive.
    if (text.isEmpty) return;
    if (!text.contains('*') && !text.contains('?')) {
      terms.add(_textTerm(text, negated: negated));
      return;
    }
    final folded = _caseFold(text);
    List<int>? segmentPattern;
    var segmentCount = 0;
    if (_hasSeparator(folded)) {
      final normalized = folded.replaceAll(r'\', '/');
      segmentPattern = _compileGlob(normalized);
      segmentCount = '/'.allMatches(normalized).length + 1;
    }
    terms.add(
      _GlobTerm(
        _compileGlob(folded),
        segmentPattern,
        segmentCount,
        negated: negated,
      ),
    );
  }

  _TextTerm _textTerm(String text, {required bool negated}) {
    final folded = _caseFold(text);
    return _TextTerm(
      folded,
      _hasSeparator(folded) ? folded.replaceAll(r'\', '/') : null,
      negated: negated,
    );
  }

  static bool _hasSeparator(String text) =>
      text.contains('/') || text.contains(r'\');

  _Term? _keyTerm(String key, String value, {required bool negated}) {
    if (value.isEmpty) return null;
    switch (key) {
      case 'ext':
        final suffixes = <String>[];
        for (var part in value.split(',')) {
          if (part.startsWith('.')) part = part.substring(1);
          if (part.isEmpty) continue;
          final suffix = '.${_fold(part)}';
          if (!suffixes.contains(suffix)) suffixes.add(suffix);
        }
        if (suffixes.isEmpty) return null;
        return _ExtTerm(List<String>.unmodifiable(suffixes), negated: negated);
      case 'type':
        switch (_fold(value)) {
          case 'file':
          case 'f':
            return _TypeTerm(negated: negated, directory: false);
          case 'dir':
          case 'directory':
          case 'd':
            return _TypeTerm(negated: negated, directory: true);
        }
        return null;
      case 'path':
        return _PathTerm(
          _caseFold(value.replaceAll(r'\', '/')),
          negated: negated,
        );
    }
    return null;
  }

  String _caseFold(String text) => caseSensitive ? text : _fold(text);

  static String? _keyOf(String word) {
    if (word.length > 4) return null;
    switch (_fold(word)) {
      case 'ext':
        return 'ext';
      case 'type':
        return 'type';
      case 'path':
        return 'path';
    }
    return null;
  }
}

/// Converts a folded glob to runes and collapses runs of `*`, which match
/// the same names as a single `*`.
List<int> _compileGlob(String glob) {
  final pattern = <int>[];
  for (final rune in glob.runes) {
    if (rune == _star && pattern.isNotEmpty && pattern.last == _star) continue;
    pattern.add(rune);
  }
  return List<int>.unmodifiable(pattern);
}

/// Whether [name] matches the whole [pattern] (`*` any run, `?` one rune).
///
/// The classic two-pointer wildcard match: on a mismatch it only retries the
/// most recent `*` with one more character, which is enough because an
/// earlier `*` can always absorb what a later one would. That bounds the work
/// by O(name x pattern) with no exponential backtracking, even for patterns
/// like `*a*a*a*b`.
bool _globMatches(List<int> pattern, List<int> name) {
  var p = 0;
  var n = 0;
  var star = -1;
  var resume = 0;
  while (n < name.length) {
    if (p < pattern.length &&
        pattern[p] != _star &&
        (pattern[p] == _question || pattern[p] == name[n])) {
      p++;
      n++;
    } else if (p < pattern.length && pattern[p] == _star) {
      star = p;
      p++;
      resume = n;
    } else if (star >= 0) {
      p = star + 1;
      resume++;
      n = resume;
    } else {
      return false;
    }
  }
  while (p < pattern.length && pattern[p] == _star) {
    p++;
  }
  return p == pattern.length;
}

/// Lowercases [text] one character at a time without changing its length.
///
/// Per-character lowercasing (instead of one `toLowerCase` call on the whole
/// string) keeps results identical on every platform: JavaScript applies the
/// context-dependent final-sigma rule, the VM does not. A character whose
/// lowercase form has a different length (such as `İ`) is kept unchanged, so
/// indexes into the folded string are indexes into [text]. Final sigma `ς`
/// folds to `σ` so both spellings match each other.
String _fold(String text) {
  var ascii = true;
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) > 0x7F) {
      ascii = false;
      break;
    }
  }
  if (ascii) return text.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (rune < 0x80) {
      buffer.writeCharCode(rune >= 0x41 && rune <= 0x5A ? rune + 0x20 : rune);
      continue;
    }
    if (rune == 0x3C2) {
      buffer.writeCharCode(0x3C3);
      continue;
    }
    final char = String.fromCharCode(rune);
    final lower = char.toLowerCase();
    buffer.write(lower.length == char.length ? lower : char);
  }
  return buffer.toString();
}

/// Whether [unit] is whitespace by the definition of [String.trim].
bool _isWhitespace(int unit) {
  if (unit <= 0x20) {
    return unit == 0x20 || (unit >= 0x09 && unit <= 0x0D);
  }
  if (unit < 0x85) return false;
  return unit == 0x85 ||
      unit == 0xA0 ||
      unit == 0x1680 ||
      (unit >= 0x2000 && unit <= 0x200A) ||
      unit == 0x2028 ||
      unit == 0x2029 ||
      unit == 0x202F ||
      unit == 0x205F ||
      unit == 0x3000 ||
      unit == 0xFEFF;
}
