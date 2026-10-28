import 'dart:io';

/// The machine, OS, and SDK the benchmarks run on.
class BenchEnvironment {
  /// Creates an environment description.
  const BenchEnvironment({
    required this.machine,
    required this.os,
    required this.dart,
  });

  /// CPU model and architecture, for example `Apple M2 Pro (arm64)`.
  final String machine;

  /// Operating system name and version.
  final String os;

  /// The `dart --version` line of the SDK that compiled the executables.
  final String dart;

  /// Detects the environment, using [dartExecutable] for `dart --version`.
  static Future<BenchEnvironment> detect(String dartExecutable) async {
    Future<String?> run(String exe, List<String> args) async {
      try {
        final r = await Process.run(exe, args);
        if (r.exitCode != 0) return null;
        final out = '${r.stdout}${r.stderr}'.trim();
        return out.isEmpty ? null : out;
      } on ProcessException {
        return null;
      }
    }

    String? cpu;
    if (Platform.isMacOS) {
      cpu = await run('sysctl', ['-n', 'machdep.cpu.brand_string']);
    } else if (Platform.isLinux) {
      final info = File('/proc/cpuinfo');
      if (info.existsSync()) {
        final line = info
            .readAsLinesSync()
            .where((l) => l.startsWith('model name'))
            .firstOrNull;
        cpu = line?.split(':').skip(1).join(':').trim();
      }
    }
    final arch = await run('uname', ['-m']);
    final cores = Platform.numberOfProcessors;
    final machine = [
      cpu ?? 'unknown CPU',
      if (arch != null) '($arch)',
      '$cores logical cores',
    ].join(' ');

    var os = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    if (Platform.isMacOS) {
      final version = await run('sw_vers', ['-productVersion']);
      final build = await run('sw_vers', ['-buildVersion']);
      if (version != null) {
        os = 'macOS $version${build == null ? '' : ' ($build)'}';
      }
    }

    final dart = await run(dartExecutable, ['--version']) ?? 'unknown Dart SDK';
    return BenchEnvironment(
      machine: machine,
      os: os,
      dart: dart.split('\n').first,
    );
  }

  /// The fields added to every stored record.
  Map<String, String> toJson() => {'machine': machine, 'os': os, 'dart': dart};
}
