import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:glob/glob.dart';

Builder buildStylesheet(BuilderOptions options) => TailwindBuilder(options);

class TailwindBuilder implements Builder {
  final BuilderOptions options;

  TailwindBuilder(this.options);

  @override
  Future<void> build(BuildStep buildStep) async {
    var outputId = buildStep.inputId.changeExtension('').changeExtension('.css');

    final jasprTailwindUri = await Isolate.resolvePackageUri(
      Uri.parse('package:jaspr_tailwind/builder.dart'),
    );
    if (jasprTailwindUri == null) {
      log.severe("Cannot find 'jaspr_tailwind' package. Make sure it's a dependency.");
      return;
    }

    // in order to rebuild when source files change
    var assets = await buildStep.findAssets(Glob('{lib,web}/**.dart')).toList();
    await Future.wait(assets.map((a) => buildStep.canRead(a)));

    var configFile = File('tailwind.config.js');
    var hasCustomConfig = await configFile.exists();
    if (hasCustomConfig) {
      log.warning('tailwind.config.js is ignored in tailwind 4 and later. '
          'See: https://tailwindcss.com/blog/tailwindcss-v4#css-first-configuration');
    }

    var runResult = await Process.run(
      'tailwindcss',
      [
        '--input',
        buildStep.inputId.path.toPosix(),
        '--output',
        outputId.path.toPosix(),
        if (options.config.containsKey('tailwindcss')) options.config['tailwindcss'],
      ],
      runInShell: true,
      stdoutEncoding: Utf8Codec(),
      stderrEncoding: Utf8Codec(),
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
