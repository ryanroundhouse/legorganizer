import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'export_downloader.dart';
import 'ui/app_theme.dart';
import 'ui/design_tokens.dart';
import 'ui/state_widgets.dart';

void main() {
  runApp(const LegoBinApp());
}

class LegoBinApp extends StatelessWidget {
  const LegoBinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Legorganizer',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => const AppShell(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              BrandColors.cosmic,
              BrandColors.violet,
              BrandColors.midnight,
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: 0.25,
              child: CustomPaint(painter: _SplashHorizonPainter()),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 170,
                    height: 170,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          BrandColors.sunset,
                          BrandColors.glow,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'LEGORGANIZER',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.1,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplashHorizonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x55B86CFF)
      ..strokeWidth = 1.4;
    const startYRatio = 0.58;
    final startY = size.height * startYRatio;
    for (double y = startY; y < size.height; y += 10) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  final GlobalKey<_PieceGridScreenState> _pieceGridKey =
      GlobalKey<_PieceGridScreenState>();
  final GlobalKey<_AddPieceScreenState> _addPieceKey =
      GlobalKey<_AddPieceScreenState>();

  void _openAddPageWithLegoId(String legoId) {
    setState(() => _selectedIndex = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _addPieceKey.currentState?.prefillLegoId(legoId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      PieceGridScreen(
        key: _pieceGridKey,
        onPredictedLegoIdMissing: _openAddPageWithLegoId,
      ),
      AddPieceScreen(key: _addPieceKey),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: () {
                _pieceGridKey.currentState?.captureAndSearchFromCamera();
              },
              tooltip: 'Search with camera',
              child: const Icon(Icons.camera_alt),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.add_box_outlined), label: 'Add'),
        ],
      ),
    );
  }
}

class PieceGridScreen extends StatefulWidget {
  const PieceGridScreen({
    super.key,
    this.piecesLoader,
    this.piecesSaver,
    this.onPredictedLegoIdMissing,
  });

  static const String dataPath = 'assets/data/pieces.json';
  final Future<List<LegoPiece>> Function()? piecesLoader;
  final Future<void> Function(List<LegoPiece>)? piecesSaver;
  final ValueChanged<String>? onPredictedLegoIdMissing;

  @override
  State<PieceGridScreen> createState() => _PieceGridScreenState();
}

class PieceStorage {
  static const String _piecesStorageKey = 'pieces_json';

  static Future<List<LegoPiece>> loadPieces() async {
    final prefs = await SharedPreferences.getInstance();
    final savedJsonText = prefs.getString(_piecesStorageKey);
    if (savedJsonText != null && savedJsonText.trim().isNotEmpty) {
      return _decodePieces(savedJsonText);
    }

    final bundledJsonText =
        await rootBundle.loadString(PieceGridScreen.dataPath);
    await prefs.setString(_piecesStorageKey, bundledJsonText);
    return _decodePieces(bundledJsonText);
  }

  static Future<void> savePieces(List<LegoPiece> pieces) async {
    final text = const JsonEncoder.withIndent(
      '  ',
    ).convert(pieces.map((piece) => piece.toJson()).toList());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_piecesStorageKey, '$text\n');
  }

  static Future<String> loadPiecesJsonText() async {
    final prefs = await SharedPreferences.getInstance();
    final savedJsonText = prefs.getString(_piecesStorageKey);
    if (savedJsonText != null && savedJsonText.trim().isNotEmpty) {
      return savedJsonText;
    }

    final bundledJsonText =
        await rootBundle.loadString(PieceGridScreen.dataPath);
    await prefs.setString(_piecesStorageKey, bundledJsonText);
    return bundledJsonText;
  }

  static List<LegoPiece> decodePiecesJsonText(String jsonText) =>
      _decodePieces(jsonText);

  static List<LegoPiece> _decodePieces(String jsonText) {
    final jsonList = jsonDecode(jsonText) as List<dynamic>;
    return jsonList
        .map((item) => LegoPiece.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}

class BrickognizeClient {
  static final Uri _predictUri =
      Uri.parse('https://api.brickognize.com/predict/');

  static Future<String?> predictLegoIdFromImage({
    required Uint8List imageBytes,
    required String filename,
  }) async {
    var response = await _sendPredictRequest(
      imageBytes: imageBytes,
      filename: filename,
      fieldName: 'query_image',
    );
    if (response.statusCode == 415) {
      response = await _sendPredictRequest(
        imageBytes: imageBytes,
        filename: filename,
        fieldName: 'query_image[]',
      );
    }

    if (response.statusCode != 200) {
      throw StateError(
          'Predict request failed with status ${response.statusCode}.');
    }

    final body = await response.stream.bytesToString();
    final parsed = jsonDecode(body);
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException(
          'Unexpected response format from predict API.');
    }

    final items = parsed['items'];
    if (items is! List || items.isEmpty) {
      return null;
    }
    final first = items.first;
    if (first is! Map<String, dynamic>) {
      return null;
    }
    final id = (first['id']?.toString() ?? '').trim();
    return id.isEmpty ? null : id;
  }

  static Future<http.StreamedResponse> _sendPredictRequest({
    required Uint8List imageBytes,
    required String filename,
    required String fieldName,
  }) {
    final request = http.MultipartRequest('POST', _predictUri)
      ..headers['accept'] = 'application/json'
      ..files.add(
        http.MultipartFile.fromBytes(
          fieldName,
          imageBytes,
          filename: filename,
          contentType: _imageMediaType(filename),
        ),
      );
    return request.send();
  }

  static MediaType _imageMediaType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) {
      return MediaType('image', 'png');
    }
    if (lower.endsWith('.webp')) {
      return MediaType('image', 'webp');
    }
    return MediaType('image', 'jpeg');
  }
}

class _PieceGridScreenState extends State<PieceGridScreen> {
  String _searchQuery = '';
  String? _selectedPartCatId;
  String? _selectedBox;
  late Future<List<LegoPiece>> _piecesFuture;
  final ImagePicker _imagePicker = ImagePicker();
  final ScrollController _gridScrollController = ScrollController();
  bool _cameraLookupLoading = false;
  List<LegoPiece> _latestPieces = const [];
  double _lastGridWidth = 0;

  static const _importMenuAction = 'import';
  static const _exportMenuAction = 'export';
  static const _aboutMenuAction = 'about';
  static const Map<String, String> _customCategoryNames = {
    '1': 'Baseplates',
    '11': 'brick',
    '13': 'Minifigs',
    '14': 'plate',
    '16': 'Windows and Doors',
    '17': 'Gear Parts',
    '19': 'tile',
    '22': 'Pneumatics',
    '23': 'Panels',
    '24': 'Other',
    '26': 'Technic Special',
    '28': 'Animals / Creatures',
    '29': 'Wheels and Tyres',
    '30': 'Tubes and Hoses',
    '31': 'String, Bands and Reels',
    '33': 'Rock',
    '34': 'Supports, Girders and Cranes',
    '35': 'Transportation - Sea and Air',
    '38': 'Flags, Banners and Signs',
    '39': 'Magnets and Holders',
    '40': 'Technic Panels',
    '41': 'Large Buildable Figures',
    '42': 'Belville, Scala and Fabuland',
    '43': 'Znap',
    '44': 'Mechanical',
    '45': 'Electronics',
    '47': 'Windscreens and Fuselage',
    '48': 'Clikits',
    '49': 'Plates Angled',
    '50': 'HO Scale',
    '51': 'Technic Beams',
    '52': 'Technic Gears',
    '55': 'Technic Beams Special',
    '56': 'Tools',
    '57': 'Non-Buildable Figures (Duplo, Fabuland, etc)',
    '58': 'Stickers',
    '59': 'Minifig Heads',
    '60': 'Minifig Upper Body',
    '61': 'Minifig Lower Body',
    '62': 'Minidoll Heads',
    '63': 'Minidoll Upper Body',
    '64': 'Minidoll Lower Body',
    '65': 'Minifig Headwear',
    '66': 'Modulex',
    '69': 'Energy Effects',
    '70': 'Minifig Hipwear',
    '71': 'Minifig Neckwear',
    '72': 'Minifig Headwear Accessories',
    '74': 'Animal / Creature Accessories',
    '75': 'Animal / Creature Body Parts',
    '76': 'Plants & Trees',
    '77': 'Non-System Parts',
    '78': 'Pen & Watch',
    '3': 'slope',
    '4': 'Duplo, Quatro and Primo',
    '8': 'technic brick',
    '5': 'stud brick',
    '7': 'Containers',
    '9': 'jumper plate',
    '6': 'Bricks Wedged',
    '12': 'Technic Connectors',
    '15': 'Tiles Special',
    '18': 'Hinges, Arms and Turntables',
    '20': 'Bricks Round and Cones',
    '21': 'Plates Round Curved and Dishes',
    '25': 'Technic Steering, Suspension and Engine',
    '27': 'Minifig Accessories',
    '32': 'Bars, Ladders and Fences',
    '36': 'Transportation - Land',
    '37': 'Bricks Curved',
    '46': 'Technic Axles',
    '53': 'Technic Pins',
    '54': 'Technic Bushes',
    '67': 'Tiles Round and Curved',
    '68': 'Projectiles / Launchers',
    '73': 'Minifig Shields, Weapons, & Tools',
  };

  String _categoryLabel(String partCatId) =>
      _customCategoryNames[partCatId] ?? partCatId;

  List<String> _categoryOptions(List<LegoPiece> pieces) {
    final categories = pieces
        .map((piece) => piece.partCatId.trim())
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList();
    categories.sort((a, b) {
      final aNumber = int.tryParse(a);
      final bNumber = int.tryParse(b);
      if (aNumber != null && bNumber != null) {
        return aNumber.compareTo(bNumber);
      }
      return a.compareTo(b);
    });
    return categories;
  }

  List<String> _boxOptions(List<LegoPiece> pieces) {
    final boxes = pieces
        .map((piece) => piece.bin.trim())
        .where((box) => box.isNotEmpty)
        .toSet()
        .toList();
    boxes.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return boxes;
  }

  Future<void> _showFilterDialog({
    required List<String> categoryOptions,
    required List<String> boxOptions,
  }) async {
    final result = await showDialog<_PieceFilterSelection>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Filter pieces'),
          content: SizedBox(
            width: 360,
            child: categoryOptions.isEmpty && boxOptions.isEmpty
                ? const Text('No filters available.')
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (categoryOptions.isNotEmpty) ...[
                          const Text('Category'),
                          const SizedBox(height: 6),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.clear),
                            title: const Text('Clear category'),
                            onTap: () => Navigator.of(context).pop(
                              _PieceFilterSelection(
                                categoryId: null,
                                box: _selectedBox,
                              ),
                            ),
                          ),
                          ...categoryOptions.map(
                            (partCatId) => RadioListTile<String>(
                              value: partCatId,
                              groupValue: _selectedPartCatId,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(_categoryLabel(partCatId)),
                              onChanged: (value) => Navigator.of(context).pop(
                                _PieceFilterSelection(
                                  categoryId: value,
                                  box: _selectedBox,
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (categoryOptions.isNotEmpty && boxOptions.isNotEmpty)
                          const SizedBox(height: 10),
                        if (boxOptions.isNotEmpty) ...[
                          const Text('Box'),
                          const SizedBox(height: 6),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.clear),
                            title: const Text('Clear box'),
                            onTap: () => Navigator.of(context).pop(
                              _PieceFilterSelection(
                                categoryId: _selectedPartCatId,
                                box: null,
                              ),
                            ),
                          ),
                          ...boxOptions.map(
                            (box) => RadioListTile<String>(
                              value: box,
                              groupValue: _selectedBox,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(box),
                              onChanged: (value) => Navigator.of(context).pop(
                                _PieceFilterSelection(
                                  categoryId: _selectedPartCatId,
                                  box: value,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }
    setState(() {
      _selectedPartCatId = result.categoryId;
      _selectedBox = result.box;
    });
  }

  Future<List<LegoPiece>> _loadPieces() => PieceStorage.loadPieces();

  Future<void> _savePieces(List<LegoPiece> pieces) =>
      PieceStorage.savePieces(pieces);

  Future<void> _exportPiecesJson() async {
    try {
      final jsonText = await PieceStorage.loadPiecesJsonText();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final fileName = 'lego_pieces_$timestamp.json';
      final didExport =
          await downloadJsonFile(fileName: fileName, jsonText: jsonText);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              didExport ? 'Exported $fileName.' : 'Export canceled.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not export pieces JSON: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _importPiecesJson() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Import is currently supported on Android only.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (!mounted || result == null) {
        return;
      }

      final selectedFile = result.files.single;
      final rawBytes = selectedFile.bytes;
      if (rawBytes == null) {
        throw FormatException('Could not read selected file bytes.');
      }

      final jsonText = utf8.decode(rawBytes);
      final importedPieces = PieceStorage.decodePiecesJsonText(jsonText);
      final fileName = selectedFile.name;

      final shouldReplace = await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Import pieces'),
                content: Text(
                  'Replace your current pieces with ${importedPieces.length} '
                  'pieces from "$fileName"?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Replace'),
                  ),
                ],
              );
            },
          ) ??
          false;

      if (!mounted || !shouldReplace) {
        return;
      }

      await PieceStorage.savePieces(importedPieces);
      if (!mounted) {
        return;
      }

      setState(() {
        _piecesFuture = Future.value(importedPieces);
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Imported ${importedPieces.length} pieces.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not import pieces JSON: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _showAboutDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('About Legorganizer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The piece images in this app come from'),
              _AboutLink(
                label: 'Rebrickable',
                url: 'https://rebrickable.com/home/',
                onOpen: _openAboutLink,
              ),
              const SizedBox(height: 16),
              const Text('Camera ID functionality uses the API hosted by'),
              _AboutLink(
                label: 'brickognize.com',
                url: 'https://brickognize.com/',
                onOpen: _openAboutLink,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openAboutLink(String url) async {
    final uri = Uri.parse(url);
    final didLaunch =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (didLaunch || !mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Could not open $url'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _updatePieceBin(
    List<LegoPiece> currentPieces,
    LegoPiece piece,
    String updatedBin,
  ) async {
    if (updatedBin == piece.bin) {
      return;
    }

    final updatedPieces = currentPieces
        .map(
          (currentPiece) => currentPiece.legoId == piece.legoId
              ? currentPiece.copyWith(bin: updatedBin)
              : currentPiece,
        )
        .toList();

    setState(() {
      _piecesFuture = Future.value(updatedPieces);
    });

    try {
      await (widget.piecesSaver ?? _savePieces).call(updatedPieces);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Saved ${piece.name} bin to "$updatedBin".'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _piecesFuture = Future.value(currentPieces);
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not save piece changes: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _deletePiece(
    List<LegoPiece> currentPieces,
    LegoPiece piece,
  ) async {
    final pieceIndex = currentPieces.indexWhere(
      (currentPiece) => currentPiece.legoId == piece.legoId,
    );
    if (pieceIndex == -1) {
      return;
    }

    final updatedPieces = List<LegoPiece>.from(currentPieces)
      ..removeAt(pieceIndex);

    setState(() {
      _piecesFuture = Future.value(updatedPieces);
    });

    try {
      await (widget.piecesSaver ?? _savePieces).call(updatedPieces);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Deleted ${piece.name}.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _piecesFuture = Future.value(currentPieces);
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not delete piece: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  void initState() {
    super.initState();
    _piecesFuture = widget.piecesLoader?.call() ?? _loadPieces();
  }

  @override
  void dispose() {
    _gridScrollController.dispose();
    super.dispose();
  }

  Future<void> captureAndSearchFromCamera() async {
    if (_cameraLookupLoading) {
      return;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content:
                Text('Camera search is currently supported on Android only.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    final image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (image == null) {
      return;
    }

    setState(() {
      _cameraLookupLoading = true;
    });

    try {
      final imageBytes = await image.readAsBytes();
      final uploadName = image.name.isEmpty ? 'lego_piece.jpg' : image.name;
      final predictedId = await BrickognizeClient.predictLegoIdFromImage(
        imageBytes: imageBytes,
        filename: uploadName,
      );

      if (!mounted) {
        return;
      }

      if (predictedId == null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('No LEGO match found from the captured photo.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }

      final matchedPiece = _findPieceByLegoId(predictedId);
      if (matchedPiece != null) {
        await _scrollToPiece(matchedPiece.legoId);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Found in inventory: ${matchedPiece.name} (${matchedPiece.legoId}).',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
      } else {
        widget.onPredictedLegoIdMissing?.call(predictedId);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Camera search failed: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _cameraLookupLoading = false;
        });
      }
    }
  }

  LegoPiece? _findPieceByLegoId(String legoId) {
    final normalizedLegoId = _normalizeLegoId(legoId);
    for (final piece in _latestPieces) {
      if (_normalizeLegoId(piece.legoId) == normalizedLegoId) {
        return piece;
      }
    }
    return null;
  }

  Future<void> _scrollToPiece(String legoId) async {
    final targetIndex = _latestPieces.indexWhere(
      (piece) => _normalizeLegoId(piece.legoId) == _normalizeLegoId(legoId),
    );
    if (targetIndex == -1) {
      return;
    }

    setState(() {
      _searchQuery = '';
      _selectedPartCatId = null;
      _selectedBox = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_gridScrollController.hasClients) {
        return;
      }
      final targetOffset = _gridOffsetForIndex(targetIndex);
      final maxOffset = _gridScrollController.position.maxScrollExtent;
      await _gridScrollController.animateTo(
        targetOffset.clamp(0.0, maxOffset),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  double _gridOffsetForIndex(int index) {
    final crossAxisCount = _gridCrossAxisCountForWidth(_lastGridWidth);
    const crossAxisSpacing = AppGrid.spacing;
    const mainAxisSpacing = AppGrid.spacing;
    const childAspectRatio = AppGrid.childAspectRatio;
    final width = _lastGridWidth > 0 ? _lastGridWidth : 320.0;
    final tileWidth =
        (width - crossAxisSpacing * (crossAxisCount - 1)) / crossAxisCount;
    final tileHeight = tileWidth / childAspectRatio;
    final row = index ~/ crossAxisCount;
    return row * (tileHeight + mainAxisSpacing);
  }

  int _gridCrossAxisCountForWidth(double width) {
    final effectiveWidth = width > 0 ? width : 320;
    final count = ((effectiveWidth + AppGrid.spacing) /
            (AppGrid.maxCrossAxisExtent + AppGrid.spacing))
        .floor();
    return math.max(1, count);
  }

  String _normalizeLegoId(String value) {
    final lower = value.trim().toLowerCase();
    final chars = lower.runes.where((r) {
      final isDigit = r >= 48 && r <= 57;
      final isLower = r >= 97 && r <= 122;
      return isDigit || isLower;
    });
    return String.fromCharCodes(chars);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColor = colorScheme.surface;

    return SafeArea(
      child: Scaffold(
        backgroundColor: surfaceColor,
        appBar: AppBar(
          backgroundColor: surfaceColor,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          title: const Text('Legorganizer'),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.menu),
              tooltip: 'Menu',
              onSelected: (value) {
                if (value == _importMenuAction) {
                  _importPiecesJson();
                } else if (value == _exportMenuAction) {
                  _exportPiecesJson();
                } else if (value == _aboutMenuAction) {
                  _showAboutDialog();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem<String>(
                  value: _importMenuAction,
                  child: Text('Import'),
                ),
                PopupMenuItem<String>(
                  value: _exportMenuAction,
                  child: Text('Export'),
                ),
                PopupMenuItem<String>(
                  value: _aboutMenuAction,
                  child: Text('About'),
                ),
              ],
            ),
          ],
        ),
        body: ColoredBox(
          color: surfaceColor,
          child: FutureBuilder<List<LegoPiece>>(
            future: _piecesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const AppLoadingState(message: 'Loading pieces...');
              }

              if (snapshot.hasError) {
                return AppErrorState(
                  message: 'Failed to load pieces: ${snapshot.error}',
                  onRetry: () {
                    setState(() {
                      _piecesFuture = widget.piecesLoader?.call() ?? _loadPieces();
                    });
                  },
                );
              }

              final pieces = snapshot.data ?? const <LegoPiece>[];
              _latestPieces = pieces;
              if (pieces.isEmpty) {
                return AppEmptyState(
                  title: 'No pieces yet',
                  message: 'Add a piece from the Add tab or import a JSON backup.',
                  actionLabel: 'Retry',
                  onActionPressed: () {
                    setState(() {
                      _piecesFuture = widget.piecesLoader?.call() ?? _loadPieces();
                    });
                  },
                );
              }

              final normalizedQuery = _searchQuery.trim().toLowerCase();
              final categoryOptions = _categoryOptions(pieces);
              final boxOptions = _boxOptions(pieces);
              final activeCategory =
                  categoryOptions.contains(_selectedPartCatId)
                      ? _selectedPartCatId
                      : null;
              final activeBox =
                  boxOptions.contains(_selectedBox) ? _selectedBox : null;
              final hasSearch = normalizedQuery.isNotEmpty;
              final hasCategoryFilter =
                  activeCategory != null && activeCategory.isNotEmpty;
              final hasBoxFilter = activeBox != null && activeBox.isNotEmpty;
              final filteredPieces = pieces.where((piece) {
                final matchesSearch = !hasSearch ||
                    piece.name.toLowerCase().contains(normalizedQuery) ||
                    piece.legoId.toLowerCase().contains(normalizedQuery);
                final matchesCategory = !hasCategoryFilter ||
                    piece.partCatId.trim() == activeCategory;
                final matchesBox =
                    !hasBoxFilter || piece.bin.trim() == activeBox;
                return matchesSearch && matchesCategory && matchesBox;
              }).toList();
              final hasAnyFilter = hasCategoryFilter || hasBoxFilter;

              return Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  children: [
                    Material(
                      color: surfaceColor,
                      child: TextField(
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                        decoration: InputDecoration(
                          labelText: 'Search pieces',
                          hintText: 'Type part name or LEGO ID',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest,
                          border: const OutlineInputBorder(),
                          suffixIcon: Padding(
                            padding: const EdgeInsets.only(right: AppSpacing.xxs),
                            child: Material(
                              color: hasAnyFilter
                                  ? colorScheme.primaryContainer
                                  : colorScheme.surface,
                              shape: const CircleBorder(),
                              elevation: 2,
                              child: IconButton(
                                tooltip: 'Filter pieces',
                                onPressed: () => _showFilterDialog(
                                  categoryOptions: categoryOptions,
                                  boxOptions: boxOptions,
                                ),
                                icon: Icon(
                                  Icons.filter_list,
                                  color:
                                      hasAnyFilter ? colorScheme.primary : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (hasSearch || hasAnyFilter) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Wrap(
                                spacing: AppSpacing.xs,
                                children: [
                                  if (hasSearch)
                                    InputChip(
                                      label: Text('Search: ${_searchQuery.trim()}'),
                                      onDeleted: () => setState(
                                        () => _searchQuery = '',
                                      ),
                                    ),
                                  if (hasCategoryFilter)
                                    InputChip(
                                      label: Text(
                                        'Category: ${_categoryLabel(activeCategory)}',
                                      ),
                                      onDeleted: () => setState(
                                        () => _selectedPartCatId = null,
                                      ),
                                    ),
                                  if (hasBoxFilter)
                                    InputChip(
                                      label: Text('Box: $activeBox'),
                                      onDeleted: () => setState(
                                        () => _selectedBox = null,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (hasSearch || hasAnyFilter)
                            TextButton(
                              onPressed: () => setState(() {
                                _searchQuery = '';
                                _selectedPartCatId = null;
                                _selectedBox = null;
                              }),
                              child: const Text('Clear all'),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Expanded(
                      child: filteredPieces.isEmpty
                          ? AppEmptyState(
                              title: 'No matching pieces',
                              message:
                                  'Try a different search, remove filters, or clear all criteria.',
                              actionLabel: 'Clear filters',
                              onActionPressed: () => setState(() {
                                _searchQuery = '';
                                _selectedPartCatId = null;
                                _selectedBox = null;
                              }),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                _lastGridWidth = constraints.maxWidth;
                                return GridView.builder(
                                  controller: _gridScrollController,
                                  itemCount: filteredPieces.length,
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: AppGrid.maxCrossAxisExtent,
                                    crossAxisSpacing: AppGrid.spacing,
                                    mainAxisSpacing: AppGrid.spacing,
                                    childAspectRatio: AppGrid.childAspectRatio,
                                  ),
                                  itemBuilder: (context, index) {
                                    final piece = filteredPieces[index];
                                    return PieceTile(
                                      piece: piece,
                                      onSaveBin: (updatedBin) =>
                                          _updatePieceBin(
                                        pieces,
                                        piece,
                                        updatedBin,
                                      ),
                                      onDelete: () => _deletePiece(
                                        pieces,
                                        piece,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AboutLink extends StatelessWidget {
  const _AboutLink({
    required this.label,
    required this.url,
    required this.onOpen,
  });

  final String label;
  final String url;
  final Future<void> Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextButton(
      onPressed: () => onOpen(url),
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        alignment: Alignment.centerLeft,
      ),
      child: Text(
        label,
        textAlign: TextAlign.left,
        style: TextStyle(
          color: colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}

class _PieceFilterSelection {
  const _PieceFilterSelection({required this.categoryId, required this.box});

  final String? categoryId;
  final String? box;
}

class _InlineStatusData {
  const _InlineStatusData({required this.message, required this.tone});

  final String message;
  final StatusTone tone;
}

class PieceTile extends StatelessWidget {
  const PieceTile({
    super.key,
    required this.piece,
    required this.onSaveBin,
    required this.onDelete,
  });

  final LegoPiece piece;
  final ValueChanged<String> onSaveBin;
  final VoidCallback onDelete;

  String? _binNumberOrNull(String rawBin) {
    final match = RegExp(r'\d+').firstMatch(rawBin);
    return match?.group(0);
  }

  Future<void> _showEditDialog(BuildContext context) async {
    final controller = TextEditingController(text: piece.bin);
    final updatedBin = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Bin: ${piece.name}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Bin',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showDeleteDialog(context);
              },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete piece'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (updatedBin != null) {
      onSaveBin(updatedBin);
    }
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete piece?'),
            content: Text('Delete ${piece.name} from your inventory?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (shouldDelete) {
      onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final binNumber = _binNumberOrNull(piece.bin);
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: AppRadius.card,
      onTap: () {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('${piece.name} is in ${piece.bin}'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
      },
      onLongPress: () => _showEditDialog(context),
      onSecondaryTap: () => _showEditDialog(context),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: AppRadius.card,
          border: Border.all(color: colorScheme.outlineVariant),
          color: colorScheme.surface,
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: AppRadius.image,
                        child: Image.asset(
                          piece.imageAsset,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => DecoratedBox(
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                            ),
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              size: 42,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (binNumber != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                binNumber,
                                style: TextStyle(
                                  color: colorScheme.onError,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  height: 1,
                                ),
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (!piece.present)
                      const Positioned(
                        top: 8,
                        left: 8,
                        child: Chip(label: Text('Missing')),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          piece.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ID: ${piece.legoId}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Piece actions',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showEditDialog(context);
                      } else if (value == 'delete') {
                        _showDeleteDialog(context);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Text('Edit bin'),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Delete piece'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddPieceScreen extends StatefulWidget {
  const AddPieceScreen({super.key});

  @override
  State<AddPieceScreen> createState() => _AddPieceScreenState();
}

class _AddPieceScreenState extends State<AddPieceScreen> {
  static const String _partsPath = 'assets/data/parts.csv';

  final TextEditingController _controller = TextEditingController();
  final TextEditingController _binController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _loading = true;
  bool _cameraLookupLoading = false;
  List<LegoPiece> _pieces = const [];
  List<PartRecord> _parts = const [];
  Map<String, PartRecord> _partsByLookupKey = const {};
  Map<String, String> _pieceNamesById = const {};
  PartRecord? _foundPart;
  _InlineStatusData? _status;

  void _setStatus(String message, StatusTone tone) {
    _status = _InlineStatusData(message: message, tone: tone);
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void prefillLegoId(String legoId) {
    final value = legoId.trim();
    if (value.isEmpty) {
      return;
    }
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _lookup();
  }

  @override
  void dispose() {
    _controller.dispose();
    _binController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final csvText = await rootBundle.loadString(_partsPath);
      final pieces = await PieceStorage.loadPieces();
      final pieceNames = _buildPieceNameMap(pieces);

      if (!mounted) {
        return;
      }
      setState(() {
        _pieces = pieces;
        _parts = _parsePartsCsv(csvText);
        _partsByLookupKey = _buildPartLookup(_parts);
        _pieceNamesById = pieceNames;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _setStatus('Failed to load part data: $error', StatusTone.error);
      });
    }
  }

  void _lookup() {
    final legoId = _controller.text.trim();
    if (_loading) {
      return;
    }

    if (_parts.isEmpty && _pieceNamesById.isEmpty) {
      setState(() {
        _foundPart = null;
        _setStatus('Part data is not loaded yet.', StatusTone.error);
      });
      return;
    }

    if (legoId.isEmpty) {
      setState(() {
        _foundPart = null;
        _status = null;
      });
      return;
    }

    final existingPieceName = _pieceNamesById[legoId];
    if (existingPieceName != null) {
      setState(() {
        _foundPart = PartRecord(
          partNum: legoId,
          name: existingPieceName,
          partCatId: '',
          partMaterial: '',
        );
        _setStatus(
          'Part $legoId is already in your inventory and cannot be added.',
          StatusTone.warning,
        );
      });
      return;
    }

    final found = _findPartByLegoId(legoId);
    setState(() {
      _foundPart = found;
      if (found == null) {
        _setStatus('No part found for LEGO ID "$legoId".', StatusTone.warning);
      } else {
        _status = null;
      }
    });
  }

  Future<void> _addPart() async {
    final part = _foundPart;
    if (part == null) {
      return;
    }

    if (_pieceNamesById.containsKey(part.partNum)) {
      setState(() {
        _setStatus(
          'Part ${part.partNum} already exists in your inventory.',
          StatusTone.warning,
        );
      });
      return;
    }

    final enteredBin = _binController.text.trim();
    final bin = enteredBin;

    final newPiece = LegoPiece(
      name: part.name,
      bin: bin,
      legoId: part.partNum,
      present: true,
      imageAsset: 'assets/pieces/${part.partNum}.png',
      partCatId: part.partCatId,
    );
    final updatedPieces = [..._pieces, newPiece];

    try {
      await PieceStorage.savePieces(updatedPieces);

      if (!mounted) {
        return;
      }
      setState(() {
        _pieces = updatedPieces;
        _pieceNamesById = _buildPieceNameMap(updatedPieces);
        _setStatus('Added ${part.partNum} to your inventory.', StatusTone.success);
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Added ${part.partNum} to pieces'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _setStatus('Could not save piece changes: $error', StatusTone.error);
      });
    }
  }

  Future<void> _captureAndPredictPart() async {
    if (_loading || _cameraLookupLoading) {
      return;
    }

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      setState(() {
        _setStatus(
          'Camera lookup is currently supported on Android only.',
          StatusTone.info,
        );
      });
      return;
    }

    final image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (image == null) {
      return;
    }

    setState(() {
      _cameraLookupLoading = true;
      _setStatus('Analyzing photo...', StatusTone.info);
    });

    try {
      final imageBytes = await image.readAsBytes();
      final uploadName = image.name.isEmpty ? 'lego_piece.jpg' : image.name;
      final predictedId = await BrickognizeClient.predictLegoIdFromImage(
        imageBytes: imageBytes,
        filename: uploadName,
      );
      if (predictedId == null) {
        if (!mounted) {
          return;
        }
        setState(() {
          _setStatus(
            'No LEGO match found from the captured photo.',
            StatusTone.warning,
          );
        });
        return;
      }

      prefillLegoId(predictedId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _setStatus('Camera lookup failed: $error', StatusTone.error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _cameraLookupLoading = false;
        });
      }
    }
  }

  List<PartRecord> _parsePartsCsv(String csvText) {
    final lines = const LineSplitter()
        .convert(csvText)
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return const [];
    }

    final result = <PartRecord>[];
    for (var i = 1; i < lines.length; i++) {
      final columns = _splitCsvLine(lines[i]);
      if (columns.length < 4) {
        continue;
      }
      result.add(
        PartRecord(
          partNum: columns[0],
          name: columns[1],
          partCatId: columns[2],
          partMaterial: columns[3],
        ),
      );
    }
    return result;
  }

  List<String> _splitCsvLine(String line) {
    final values = <String>[];
    final current = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }

      if (char == ',' && !inQuotes) {
        values.add(current.toString());
        current.clear();
        continue;
      }

      current.write(char);
    }

    values.add(current.toString());
    return values;
  }

  Map<String, String> _buildPieceNameMap(List<LegoPiece> pieces) {
    final namesById = <String, String>{};
    for (final piece in pieces) {
      if (piece.legoId.isNotEmpty && piece.name.isNotEmpty) {
        namesById[piece.legoId] = piece.name;
      }
    }
    return namesById;
  }

  Map<String, PartRecord> _buildPartLookup(List<PartRecord> parts) {
    final lookup = <String, PartRecord>{};
    for (final part in parts) {
      final rawKey = part.partNum.trim().toLowerCase();
      final normalizedKey = _normalizeLegoId(part.partNum);
      if (rawKey.isNotEmpty && !lookup.containsKey(rawKey)) {
        lookup[rawKey] = part;
      }
      if (normalizedKey.isNotEmpty && !lookup.containsKey(normalizedKey)) {
        lookup[normalizedKey] = part;
      }
    }
    return lookup;
  }

  PartRecord? _findPartByLegoId(String legoId) {
    final raw = legoId.trim().toLowerCase();
    final normalized = _normalizeLegoId(legoId);
    return _partsByLookupKey[raw] ?? _partsByLookupKey[normalized];
  }

  String _normalizeLegoId(String value) {
    final lower = value.trim().toLowerCase();
    final chars = lower.runes.where((r) {
      final isDigit = r >= 48 && r <= 57;
      final isLower = r >= 97 && r <= 122;
      return isDigit || isLower;
    });
    return String.fromCharCodes(chars);
  }

  @override
  Widget build(BuildContext context) {
    final foundPart = _foundPart;
    final enteredLegoId = _controller.text.trim();
    final imageAsset =
        enteredLegoId.isEmpty ? '' : 'assets/pieces/$enteredLegoId.png';
    final canAdd =
        foundPart != null && !_pieceNamesById.containsKey(foundPart.partNum);

    return Scaffold(
      appBar: AppBar(title: const Text('Add LEGO Piece')),
      body: SafeArea(
        child: _loading
            ? const AppLoadingState(message: 'Loading part catalog...')
            : Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Enter a LEGO ID to preview the part, optionally add a bin location, then add it to your inventory.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextField(
                            controller: _controller,
                            decoration: const InputDecoration(
                              labelText: 'LEGO ID',
                              hintText: 'Example: 3001',
                            ),
                            textInputAction: TextInputAction.search,
                            onChanged: (_) => _lookup(),
                            onSubmitted: (_) => _lookup(),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          FilledButton.icon(
                            onPressed: _cameraLookupLoading
                                ? null
                                : _captureAndPredictPart,
                            icon: _cameraLookupLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.camera_alt),
                            label: Text(
                              _cameraLookupLoading
                                  ? 'Searching camera...'
                                  : 'Find LEGO ID with camera',
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextField(
                            controller: _binController,
                            decoration: const InputDecoration(
                              labelText: 'Bin',
                              hintText: 'Example: Bin 12',
                            ),
                          ),
                          if (_status != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            InlineStatusBanner(
                              message: _status!.message,
                              tone: _status!.tone,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          if (foundPart != null)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      foundPart.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text('LEGO ID: ${foundPart.partNum}'),
                                    const SizedBox(height: AppSpacing.sm),
                                    SizedBox(
                                      height: 200,
                                      child: Center(
                                        child: Image.asset(
                                          imageAsset,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) =>
                                              DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                              borderRadius: AppRadius.image,
                                            ),
                                            child: const SizedBox(
                                              width: double.infinity,
                                              child: Center(
                                                child: Text(
                                                  'Image not found for this LEGO ID.',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            const AppEmptyState(
                              title: 'No part selected',
                              message:
                                  'Search by LEGO ID or use the camera to find a matching part.',
                              icon: Icons.search,
                            ),
                          SizedBox(
                            height: AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.xs,
                        AppSpacing.md,
                        AppSpacing.md,
                      ),
                      child: FilledButton.icon(
                        onPressed: canAdd ? _addPart : null,
                        icon: const Icon(Icons.add),
                        label: const Text('Add to inventory'),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class LegoPiece {
  const LegoPiece({
    required this.name,
    required this.bin,
    required this.legoId,
    required this.present,
    required this.imageAsset,
    this.partCatId = '',
  });

  factory LegoPiece.fromJson(Map<String, dynamic> json) {
    return LegoPiece(
      name: json['name'] as String? ?? 'Unknown',
      bin: json['bin'] as String? ?? 'Unknown Bin',
      legoId: json['legoId']?.toString() ?? 'Unknown',
      present: json['present'] as bool? ?? false,
      imageAsset: json['imageAsset'] as String? ?? '',
      partCatId: json['part_cat_id']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'bin': bin,
      'legoId': legoId,
      'present': present,
      'imageAsset': imageAsset,
      'part_cat_id': partCatId,
    };
  }

  LegoPiece copyWith({
    String? name,
    String? bin,
    String? legoId,
    bool? present,
    String? imageAsset,
    String? partCatId,
  }) {
    return LegoPiece(
      name: name ?? this.name,
      bin: bin ?? this.bin,
      legoId: legoId ?? this.legoId,
      present: present ?? this.present,
      imageAsset: imageAsset ?? this.imageAsset,
      partCatId: partCatId ?? this.partCatId,
    );
  }

  final String name;
  final String bin;
  final String legoId;
  final bool present;
  final String imageAsset;
  final String partCatId;
}

class PartRecord {
  const PartRecord({
    required this.partNum,
    required this.name,
    required this.partCatId,
    required this.partMaterial,
  });

  static const PartRecord empty = PartRecord(
    partNum: '',
    name: '',
    partCatId: '',
    partMaterial: '',
  );

  final String partNum;
  final String name;
  final String partCatId;
  final String partMaterial;

  bool get isEmpty => partNum.isEmpty;
}
