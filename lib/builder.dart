import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';

Builder buildStylesheet(BuilderOptions options) => TailwindBuilder(options);

class TailwindBuilder implements Builder {
  final BuilderOptions options;

  TailwindBuilder(this.options);

  Future<ProcessResult> _runTailwind(List<String> args) => Process.run(
        'tailwindcss',
        args,
        runInShell: true,
        stdoutEncoding: Utf8Codec(),
        stderrEncoding: Utf8Codec(),
      );

  @override
  Future<void> build(BuildStep buildStep) async {
    final jasprTailwindUri = await Isolate.resolvePackageUri(
      Uri.parse('package:jaspr_tailwind/builder.dart'),
    );
    if (jasprTailwindUri == null) {
      throw Exception("Cannot find 'jaspr_tailwind' package. Make sure it's a dependency.");
    }

    // Check that tailwindcss CLI is available, and get the help output
    var helpResult = await _runTailwind(['--help']);
    if (helpResult.exitCode != 0) {
      throw Exception('tailwindcss cli not found in \$PATH. Please follow the instructions here: '
          'https://docs.jaspr.site/eco/tailwind');
    }

    // Extract the major version number between 'v' and '.' from the help output
    // (the first line looks like: "≈ tailwindcss vX.Y.Z")
    var versionMatch = RegExp(r'v(\d+)\.').firstMatch(helpResult.stdout);
    if (versionMatch == null) {
      throw Exception('Could not determine tailwindcss version from --help output.');
    }
    var majorVersion = int.parse(versionMatch.group(1)!);

    // If there is a legacy config file with majorVersion >= 4, warn that it is ignored
    if (majorVersion >= 4) {
      var configFile = File('tailwind.config.js');
      var hasCustomConfig = await configFile.exists();
      if (hasCustomConfig) {
        log.warning('tailwind.config.js is ignored in tailwind 4 and later. '
            'See: https://tailwindcss.com/blog/tailwindcss-v4#css-first-configuration');
      }
    }

    // Run tailwindcss to produce <filename>.css from <filename>.tw.css
    var inputPath = buildStep.inputId.path.toPosix();
    var outputPath = buildStep.inputId.changeExtension('').changeExtension('.css').path.toPosix();
    var runResult = await _runTailwind(
      [
        '--input',
        inputPath,
        '--output',
        outputPath,
        if (options.config.containsKey('tailwindcss')) options.config['tailwindcss'],
      ],
    );

    // Log output lines, and detect error messages
    var stdout = runResult.stdout.toString();
    var stderr = runResult.stderr.toString();
    var lines = [
      if (stdout.isNotEmpty) ...stdout.split('\n'),
      if (stderr.isNotEmpty) ...stderr.split('\n'),
    ].toList();
    var nonErrorLines = lines.where((line) => !line.startsWith('Error:')).toList();
    if (nonErrorLines.isNotEmpty) {
      log.info(nonErrorLines.join('\n'));
    }
    var errorLines = lines.where((line) => line.startsWith('Error:')).toList();
    if (errorLines.isNotEmpty) {
      log.severe(errorLines.join('\n'));
    }

    // Throw an exception if the tailwindcss process failed
    if (runResult.exitCode != 0) {
      throw Exception('tailwindcss build failed with exit code ${runResult.exitCode}');
    }
  }

  @override
  Map<String, List<String>> get buildExtensions => {
        'web/{{file}}.tw.css': ['web/{{file}}.css']
      };
}

extension POSIXPath on String {
  String toPosix([bool quoted = false]) {
    if (Platform.isWindows) {
      final result = replaceAll('\\', '/');
      return quoted ? "'$result'" : result;
    }
    return this;
  }
}
