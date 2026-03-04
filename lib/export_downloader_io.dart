import 'dart:convert';

import 'package:share_plus/share_plus.dart';

Future<bool> downloadJsonFile({
  required String fileName,
  required String jsonText,
}) async {
  final result = await Share.shareXFiles(
    [
      XFile.fromData(
        utf8.encode(jsonText),
        name: fileName,
        mimeType: 'application/json',
      ),
    ],
    text: 'Legorganizer export',
    fileNameOverrides: [fileName],
  );

  return result.status == ShareResultStatus.success;
}
