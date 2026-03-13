import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'export_downloader.dart';

void main() {
  runApp(const LegoBinApp());
}

class LegoBinApp extends StatelessWidget {
  const LegoBinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Legorganizer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
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
    Future<void>.delayed(const Duration(seconds: 2), () {
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
    return const Scaffold(
      body: Center(
        child: Image(
          image: AssetImage('legorganizer logo.png'),
          width: 240,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
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
  static final Uri _predictUri = Uri.parse('https://api.brickognize.com/predict/');

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
      throw StateError('Predict request failed with status ${response.statusCode}.');
    }

    final body = await response.stream.bytesToString();
    final parsed = jsonDecode(body);
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('Unexpected response format from predict API.');
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
              didExport
                  ? 'Exported $fileName.'
                  : 'Export canceled.',
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
          content: const Text(
            'The piece images in this app come from Rebrickable.\n\n'
            'Camera ID functionality uses the API hosted by brickognize.com.',
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
            content: Text('Camera search is currently supported on Android only.'),
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
    const crossAxisCount = 2;
    const crossAxisSpacing = 12.0;
    const mainAxisSpacing = 12.0;
    const childAspectRatio = 0.85;
    final width = _lastGridWidth > 0 ? _lastGridWidth : 320.0;
    final tileWidth = (width - crossAxisSpacing) / crossAxisCount;
    final tileHeight = tileWidth / childAspectRatio;
    final row = index ~/ crossAxisCount;
    return row * (tileHeight + mainAxisSpacing);
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
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
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
        body: FutureBuilder<List<LegoPiece>>(
          future: _piecesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Failed to load pieces: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              );
            }

            final pieces = snapshot.data ?? const <LegoPiece>[];
            _latestPieces = pieces;
            if (pieces.isEmpty) {
              return const Center(child: Text('No lego pieces found in JSON.'));
            }

            final normalizedQuery = _searchQuery.trim().toLowerCase();
            final categoryOptions = _categoryOptions(pieces);
            final boxOptions = _boxOptions(pieces);
            final activeCategory = categoryOptions.contains(_selectedPartCatId)
                ? _selectedPartCatId
                : null;
            final activeBox =
                boxOptions.contains(_selectedBox) ? _selectedBox : null;
            final hasSearch = normalizedQuery.isNotEmpty;
            final hasCategoryFilter =
                activeCategory != null && activeCategory.isNotEmpty;
            final hasBoxFilter = activeBox != null && activeBox.isNotEmpty;
            final filteredPieces = pieces.where((piece) {
              final matchesSearch =
                  !hasSearch ||
                  piece.name.toLowerCase().contains(normalizedQuery) ||
                      piece.legoId.toLowerCase().contains(normalizedQuery);
              final matchesCategory =
                  !hasCategoryFilter || piece.partCatId.trim() == activeCategory;
              final matchesBox = !hasBoxFilter || piece.bin.trim() == activeBox;
              return matchesSearch && matchesCategory && matchesBox;
            }).toList();
            final hasAnyFilter = hasCategoryFilter || hasBoxFilter;

            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      labelText: 'Search pieces',
                      hintText: 'Type part name or legoId',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Material(
                          color: hasAnyFilter
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surface,
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: IconButton(
                            tooltip: 'Filter category',
                            onPressed: () => _showFilterDialog(
                              categoryOptions: categoryOptions,
                              boxOptions: boxOptions,
                            ),
                            icon: Icon(
                              Icons.filter_list,
                              color: hasAnyFilter
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filteredPieces.isEmpty
                        ? const Center(
                            child: Text('No pieces match your search.'),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              _lastGridWidth = constraints.maxWidth;
                              return GridView.builder(
                                controller: _gridScrollController,
                                itemCount: filteredPieces.length,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.85,
                                ),
                                itemBuilder: (context, index) {
                                  final piece = filteredPieces[index];
                                  return PieceTile(
                                    piece: piece,
                                    onSaveBin: (updatedBin) => _updatePieceBin(
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
    );
  }
}

class _PieceFilterSelection {
  const _PieceFilterSelection({required this.categoryId, required this.box});

  final String? categoryId;
  final String? box;
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
                onDelete();
              },
              child: const Text('Delete'),
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

  @override
  Widget build(BuildContext context) {
    final binNumber = _binNumberOrNull(piece.bin);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black12),
          color: Colors.white,
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
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          piece.imageAsset,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const DecoratedBox(
                            decoration: BoxDecoration(color: Color(0xFFE6E6E6)),
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              size: 42,
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
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                binNumber,
                                style: const TextStyle(
                                  color: Colors.white,
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
  String? _statusText;

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
        _statusText = 'Failed to load part data: $error';
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
        _statusText = 'Part data is not loaded yet.';
      });
      return;
    }

    if (legoId.isEmpty) {
      setState(() {
        _foundPart = null;
        _statusText = null;
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
        _statusText =
            'Part $legoId is already in pieces.json and cannot be added.';
      });
      return;
    }

    final found = _findPartByLegoId(legoId);
    setState(() {
      _foundPart = found;
      _statusText =
          found == null ? 'No part found for legoId "$legoId".' : null;
    });
  }

  Future<void> _addPart() async {
    final part = _foundPart;
    if (part == null) {
      return;
    }

    if (_pieceNamesById.containsKey(part.partNum)) {
      setState(() {
        _statusText =
            'Part ${part.partNum} already exists in pieces.json and cannot be added.';
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
        _statusText = 'Added ${part.partNum} to saved pieces.';
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
        _statusText = 'Could not save piece changes: $error';
      });
    }
  }

  Future<void> _captureAndPredictPart() async {
    if (_loading || _cameraLookupLoading) {
      return;
    }

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      setState(() {
        _statusText = 'Camera lookup is currently supported on Android only.';
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
      _statusText = 'Analyzing photo...';
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
          _statusText = 'No LEGO match found from the captured photo.';
        });
        return;
      }

      prefillLegoId(predictedId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'Camera lookup failed: $error';
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

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(title: const Text('Add Lego Piece')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Instructions:\n'
                      '1. Enter a legoId to look up a part.\n'
                      '2. Enter a bin location (optional).\n'
                      '3. Review the part card and tap Add.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        labelText: 'legoId',
                        hintText: 'Type a legoId (example: 3001)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _lookup(),
                      onSubmitted: (_) => _lookup(),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed:
                          _cameraLookupLoading ? null : _captureAndPredictPart,
                      icon: _cameraLookupLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_alt),
                      label: Text(
                        _cameraLookupLoading
                            ? 'Searching from camera...'
                            : 'Find legoId with camera',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _binController,
                      decoration: const InputDecoration(
                        labelText: 'Bin',
                        hintText: 'Type bin location (example: Bin 12)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_statusText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _statusText!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (foundPart != null)
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        foundPart.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 8),
                                      Text('legoId: ${foundPart.partNum}'),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        height: 200,
                                        child: Center(
                                          child: Image.asset(
                                            imageAsset,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) =>
                                                const DecoratedBox(
                                              decoration: BoxDecoration(
                                                  color: Color(0xFFE6E6E6)),
                                              child: SizedBox(
                                                width: double.infinity,
                                                child: Center(
                                                  child: Text(
                                                      'Image not found for this legoId.'),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: canAdd ? _addPart : null,
                                icon: const Icon(Icons.add),
                                label: const Text('Add'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
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
