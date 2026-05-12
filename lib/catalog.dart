import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

class PartsCatalog {
  PartsCatalog._({
    required this.categoryNames,
    required this.designToVariants,
    required this.partAliases,
  });

  final Map<String, String> categoryNames;
  final Map<String, List<String>> designToVariants;
  final Map<String, PartAliases> partAliases;

  static Future<PartsCatalog>? _cached;

  static Future<PartsCatalog> load() {
    return _cached ??= _loadFromAssets();
  }

  static Future<PartsCatalog> _loadFromAssets() async {
    final results = await Future.wait([
      rootBundle.loadString('assets/data/part_categories.json'),
      rootBundle.loadString('assets/data/design_to_variants.json'),
      rootBundle.loadString('assets/data/part_aliases.json'),
    ]);

    final categoriesRaw = jsonDecode(results[0]) as Map<String, dynamic>;
    final variantsRaw = jsonDecode(results[1]) as Map<String, dynamic>;
    final aliasesRaw = jsonDecode(results[2]) as Map<String, dynamic>;

    final categoryNames = <String, String>{};
    categoriesRaw.forEach((id, name) {
      if (name is String && name.isNotEmpty) {
        categoryNames[id] = name;
      }
    });

    final designToVariants = <String, List<String>>{};
    variantsRaw.forEach((designId, variants) {
      if (variants is List) {
        final values = variants
            .map((v) => v?.toString() ?? '')
            .where((v) => v.isNotEmpty)
            .toList(growable: false);
        if (values.isNotEmpty) {
          designToVariants[designId] = values;
        }
      }
    });

    final partAliases = <String, PartAliases>{};
    aliasesRaw.forEach((partNum, raw) {
      if (raw is! Map) return;
      final mold = (raw['mold'] as List?)
              ?.map((v) => v?.toString() ?? '')
              .where((v) => v.isNotEmpty)
              .toList(growable: false) ??
          const <String>[];
      final alternate = (raw['alternate'] as List?)
              ?.map((v) => v?.toString() ?? '')
              .where((v) => v.isNotEmpty)
              .toList(growable: false) ??
          const <String>[];
      if (mold.isEmpty && alternate.isEmpty) return;
      partAliases[partNum] = PartAliases(mold: mold, alternate: alternate);
    });

    return PartsCatalog._(
      categoryNames: categoryNames,
      designToVariants: designToVariants,
      partAliases: partAliases,
    );
  }

  List<String> variantsFor(String designId) {
    return designToVariants[designId.trim()] ?? const <String>[];
  }

  PartAliases? aliasesFor(String partNum) => partAliases[partNum.trim()];
}

class PartAliases {
  const PartAliases({required this.mold, required this.alternate});

  final List<String> mold;
  final List<String> alternate;
}
