/// Generates `lib/src/path/case_folding_table.dart`, the package's Unicode
/// simple case folding table, from the Unicode Character Database.
///
/// Run it from any directory:
///
/// ```text
/// dart run tool/generate_case_folding.dart [path/to/CaseFolding.txt]
/// ```
///
/// Without an argument it downloads [_sourceUrl]. The table is pinned to
/// [_unicodeVersion]: the script refuses a file of any other version, so a
/// Unicode upgrade is a deliberate change to both constants and to the
/// documentation that names the version (`PathPolicy.caseSensitive`,
/// `TreeOrder.compareNames`, and `TreeQuery`).
///
/// Only the mappings with status C (common) and S (simple) are used; F
/// (full) and T (Turkic) are not. The script checks that the result is
/// idempotent (no target is itself folded again) and that every mapping
/// keeps its UTF-16 length, except the ones listed in
/// [_knownLengthChanges]. `TreeQuery` translates folded indexes back for
/// those, so a new length-changing mapping fails the script until it is
/// reviewed and added there. It then writes the table and formats it with
/// `dart format`.
///
/// Not part of the published package (`tool/` is not in the pub archive).
library;

import 'dart:convert';
import 'dart:io';

/// The Unicode version the table is pinned to.
const String _unicodeVersion = '18.0.0';

/// Where the pinned CaseFolding.txt is published.
const String _sourceUrl =
    'https://www.unicode.org/Public/$_unicodeVersion/ucd/CaseFolding.txt';

/// Code points whose C or S folding changes their UTF-16 length, mapped to
/// the length change (folded length minus original length).
///
/// U+1DF95 LATIN SMALL LIGATURE LONG S WITH DESCENDER S folds to U+00DF
/// (`ß`), from two code units to one.
const Map<int, int> _knownLengthChanges = <int, int>{0x1DF95: -1};

/// The generated file, relative to the repository root.
const String _output = 'lib/src/path/case_folding_table.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length > 1) {
    stderr.writeln(
      'Usage: dart run tool/generate_case_folding.dart [CaseFolding.txt]',
    );
    exitCode = 64;
    return;
  }
  final source = arguments.isEmpty
      ? await _download(Uri.parse(_sourceUrl))
      : File(arguments.single).readAsStringSync();

  final errors = <String>[];
  final mappings = _parse(source, errors);
  _check(mappings, errors);
  if (errors.isNotEmpty) {
    stderr.writeln('CaseFolding.txt was rejected:');
    for (final error in errors) {
      stderr.writeln('  - $error');
    }
    exitCode = 1;
    return;
  }

  final ranges = _compress(mappings);
  final root = File.fromUri(Platform.script).parent.parent;
  final file = File('${root.path}/$_output')
    ..writeAsStringSync(_render(ranges, mappings.length));
  final format = Process.runSync('dart', <String>['format', file.path]);
  if (format.exitCode != 0) {
    stderr.write(format.stderr);
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Wrote $_output: ${mappings.length} mappings in ${ranges.length} '
    'ranges (Unicode $_unicodeVersion).',
  );
}

Future<String> _download(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

/// The C and S mappings of [source], sorted by code point.
List<(int, int)> _parse(String source, List<String> errors) {
  final lines = const LineSplitter().convert(source);
  final expectedHeader = '# CaseFolding-$_unicodeVersion.txt';
  if (lines.isEmpty || lines.first.trim() != expectedHeader) {
    errors.add(
      'The first line is "${lines.isEmpty ? '' : lines.first}", '
      'not "$expectedHeader".',
    );
    return const [];
  }
  final mappings = <(int, int)>[];
  final seen = <int>{};
  for (final line in lines) {
    final data = line.split('#').first.trim();
    if (data.isEmpty) continue;
    final fields = data.split(';').map((field) => field.trim()).toList();
    if (fields.length < 3) {
      errors.add('Unreadable line: $line');
      continue;
    }
    final status = fields[1];
    if (status != 'C' && status != 'S') continue;
    final targets = fields[2].split(' ');
    if (targets.length != 1) {
      errors.add('A $status mapping with several code points: $line');
      continue;
    }
    final from = int.parse(fields[0], radix: 16);
    final to = int.parse(targets.single, radix: 16);
    if (!seen.add(from)) errors.add('Two C or S mappings for $from: $line');
    mappings.add((from, to));
  }
  mappings.sort((a, b) => a.$1.compareTo(b.$1));
  return mappings;
}

void _check(List<(int, int)> mappings, List<String> errors) {
  final sources = {for (final (from, _) in mappings) from};
  final lengthChanges = <int, int>{};
  for (final (from, to) in mappings) {
    if (sources.contains(to)) {
      errors.add('${_hex(from)} folds to ${_hex(to)}, which folds again.');
    }
    final change = _utf16Length(to) - _utf16Length(from);
    if (change != 0) lengthChanges[from] = change;
    if (to >= 0x30 && to <= 0x39) {
      // TreeOrder.compareNames relies on no letter folding into a digit.
      errors.add('${_hex(from)} folds to the digit ${_hex(to)}.');
    }
    if (to == 0x2F || from == 0x2F) {
      // Ids and the builder's trie fold segments and whole paths alike.
      errors.add('${_hex(from)} folds to or from "/".');
    }
  }
  for (final MapEntry(key: from, value: change) in lengthChanges.entries) {
    if (_knownLengthChanges[from] != change) {
      errors.add(
        '${_hex(from)} changes the UTF-16 length by $change. Review '
        'TreeQuery.matchRanges and add it to _knownLengthChanges.',
      );
    }
    if (change > 0) {
      errors.add('${_hex(from)} grows when folded; foldCase cannot.');
    }
  }
  for (final from in _knownLengthChanges.keys) {
    if (!lengthChanges.containsKey(from)) {
      errors.add('${_hex(from)} no longer changes length; update the list.');
    }
  }
}

/// One run of mappings: code points `start`, `start + stride`, ..., `end`,
/// each folding to itself plus `delta`.
typedef _Range = ({int start, int end, int stride, int delta});

/// Merges consecutive mappings with the same delta and a stride of 1 or 2
/// (the alternating upper and lower case pairs of many scripts).
///
/// The ranges are disjoint and sorted: a code point between two members of
/// a stride-2 range is never a source, since it would have broken the run.
List<_Range> _compress(List<(int, int)> mappings) {
  final ranges = <_Range>[];
  for (final (from, to) in mappings) {
    final delta = to - from;
    if (ranges.isNotEmpty) {
      final last = ranges.last;
      final gap = from - last.end;
      final stride = last.start == last.end ? gap : last.stride;
      if (last.delta == delta && (gap == 1 || gap == 2) && gap == stride) {
        ranges.last = (
          start: last.start,
          end: from,
          stride: stride,
          delta: delta,
        );
        continue;
      }
    }
    ranges.add((start: from, end: from, stride: 1, delta: delta));
  }
  return ranges;
}

String _render(List<_Range> ranges, int count) {
  final rows = [
    for (final range in ranges)
      '  ${_hex(range.start)}, ${_hex(range.end)}, ${range.stride}, '
          '${range.delta},\n',
  ].join();
  final firstNonAscii = ranges.firstWhere((range) => range.start >= 0x80).start;
  return '''
// GENERATED by tool/generate_case_folding.dart. Do not edit by hand.
//
// Unicode simple case folding: the $count mappings with status C or S of
// CaseFolding.txt, Unicode $_unicodeVersion, as ${ranges.length} ranges.
// Source: $_sourceUrl
// Regenerate: dart run tool/generate_case_folding.dart

part of 'case_folding.dart';

/// The Unicode version of this table.
const String _unicodeVersion = '$_unicodeVersion';

/// The smallest non-ASCII code point that has a folding.
const int _firstNonAscii = ${_hex(firstNonAscii)};

/// The largest code point that has a folding.
const int _lastSource = ${_hex(ranges.last.end)};

/// The number of ints per range in [_ranges].
const int _rangeWidth = 4;

/// The folding ranges, ascending and disjoint, [_rangeWidth] ints each:
/// the first code point, the last code point (inclusive), the stride
/// between the code points of the range (1 or 2), and the delta that
/// folds each of them.
// dart format off
const List<int> _ranges = <int>[
$rows];
// dart format on
''';
}

int _utf16Length(int codePoint) => codePoint > 0xFFFF ? 2 : 1;

String _hex(int value) =>
    '0x${value.toRadixString(16).toUpperCase().padLeft(4, '0')}';
