import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:build_modules/build_modules.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

Builder buildStylesheet(BuilderOptions options) => TailwindBuilder(options);

class TailwindBuilder implements Builder {
  final BuilderOptions options;

  TailwindBuilder(this.options);

  @override
  Future<void> build(BuildStep buildStep) async {
    var scratchSpace = await buildStep.fetchResource(scratchSpaceResource);

    await scratchSpace.ensureAssets({buildStep.inputId}, buildStep);

    var outputId =
        buildStep.inputId.changeExtension('').changeExtension('.css');

    final jasprTailwindUri = await Isolate.resolvePackageUri(
      Uri.parse('package:jaspr_tailwind/builder.dart'),
    );
    if (jasprTailwindUri == null) {
      log.severe(
          "Cannot find 'jaspr_tailwind' package. Make sure it's a dependency.");
      return;
    }

    // in order to rebuild when source files change
    var assets = await buildStep.findAssets(Glob('{lib,web}/**.dart')).toList();
    await Future.wait(assets.map((a) => buildStep.canRead(a)));

    var configFile = File('tailwind.config.js');
    var hasCustomConfig = await configFile.exists();

    await Process.run(
      'tailwindcss',
      [
        '--input',
        scratchSpace.fileFor(buildStep.inputId).path,
        '--output',
        scratchSpace.fileFor(outputId).path.toPosix(),
        if (options.config.containsKey('tailwindcss'))
          options.config['tailwindcss'],
        if (hasCustomConfig) ...[
          '--config',
          p.join(Directory.current.path, 'tailwind.config.js').toPosix(),
        ] else ...[
          '--content',
          p
              .join(Directory.current.path, '{lib,web}', '**', '*.dart')
              .toPosix(true),
        ],
      ],
      runInShell: true,
    );

    await scratchSpace.copyOutput(outputId, buildStep);
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
