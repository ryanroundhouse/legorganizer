import 'package:flutter/material.dart';

/// Image widget that prefers the LDraw-rendered image hosted on Rebrickable's
/// CDN, falling back to the bundled PNG and then to a placeholder widget.
class PartThumbnail extends StatelessWidget {
  const PartThumbnail({
    super.key,
    required this.assetPath,
    required this.partNum,
    required this.fit,
    required this.fallback,
  });

  final String assetPath;
  final String partNum;
  final BoxFit fit;
  final Widget fallback;

  static String? remoteUrlFor(String partNum) {
    final trimmed = partNum.trim();
    if (trimmed.isEmpty) return null;
    return 'https://cdn.rebrickable.com/media/parts/ldraw/-1/$trimmed.png';
  }

  @override
  Widget build(BuildContext context) {
    final localFallback = assetPath.isEmpty
        ? fallback
        : Image.asset(
            assetPath,
            fit: fit,
            errorBuilder: (_, __, ___) => fallback,
          );

    final remoteUrl = remoteUrlFor(partNum);
    if (remoteUrl == null) {
      return localFallback;
    }

    return Image.network(
      remoteUrl,
      fit: fit,
      errorBuilder: (_, __, ___) => localFallback,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            localFallback,
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        );
      },
    );
  }
}
