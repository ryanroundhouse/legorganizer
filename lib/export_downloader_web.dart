// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

Future<bool> downloadJsonFile({
  required String fileName,
  required String jsonText,
}) async {
  final bytes = html.Blob(
    [jsonText],
    'application/json;charset=utf-8',
  );
  final url = html.Url.createObjectUrlFromBlob(bytes);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
  return true;
}
