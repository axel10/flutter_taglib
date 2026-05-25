import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageName = input.packageName;

    final sources = <String>[
      'src/flutter_taglib.cpp',
    ];

    final includes = <String>[
      'src',
      'taglib',
      'taglib/taglib',
      'taglib/3rdparty/utfcpp/source',
    ];

    // Find all .cpp files in taglib/taglib recursively and add to sources
    // Also find all subdirectories in taglib/taglib and add to includes
    final taglibDir = Directory('taglib/taglib');
    if (taglibDir.existsSync()) {
      for (final entity in taglibDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.cpp')) {
          sources.add(entity.path);
        } else if (entity is Directory) {
          includes.add(entity.path);
        }
      }
    }

    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: '${packageName}_bindings_generated.dart',
      sources: sources,
      includes: includes,
      defines: {
        'HAVE_CONFIG_H': '1',
        'TAGLIB_STATIC': '1',
      },
      std: 'c++17',
      language: Language.cpp,
      cppLinkStdLib: input.config.code.targetOS.toString().contains('android') ? 'c++_static' : null,
    );

    await cbuilder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.ALL
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}
