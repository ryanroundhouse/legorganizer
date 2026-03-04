# Legorganizer

Legorganizer is a Flutter app for tracking LEGO parts and their storage bins.
It includes:

- A searchable/filterable grid of parts with images
- Quick bin editing and piece deletion
- A part lookup screen to add new pieces from a CSV catalog
- Local persistence using `shared_preferences`
- JSON export support on web builds

## Project structure

- `lib/main.dart`: app UI, storage logic, search/filter, add/edit/delete flows
- `lib/export_downloader.dart`: platform wrapper for exports
- `assets/data/pieces.json`: starter piece list bundled with the app
- `assets/data/parts.csv`: part lookup source used by the Add screen
- `assets/pieces/`: piece images (`<legoId>.png`)
- `test/widget_test.dart`: widget tests for core flows

## Prerequisites

- Flutter SDK (Dart 3.6+ compatible)
- A target device/emulator, or Chrome for web

## Setup

```bash
flutter pub get
```

## Run the app

```bash
flutter run
```

Run on web:

```bash
flutter run -d chrome
```

## How to use

### Home tab

- Browse parts in a grid.
- Use the search bar to find by name or `legoId`.
- Tap the filter icon to filter by category or box.
- Tap a part to see its current bin in a snackbar.
- Long-press (or right-click) a part to:
  - Edit bin
  - Delete the part

### Add tab

- Enter a `legoId`.
- Optionally enter a bin location.
- If the part is found, review the card and image preview.
- Tap **Add** to append it to saved pieces.

Notes:

- Duplicate `legoId`s are blocked.
- Lookup data comes from `assets/data/parts.csv`.
- Images are loaded from `assets/pieces/<legoId>.png`.

### Menu actions (Home tab top-right)

- **Export**: downloads current saved pieces as JSON (`web` builds only).
- **About**: credits Rebrickable for piece images.

## Data and persistence

- Pieces are persisted in local app storage under key `pieces_json`.
- On first launch, bundled `assets/data/pieces.json` is copied into local storage.
- Later edits/additions/deletions update local storage only.

Piece JSON shape:

```json
{
  "name": "Brick 1x2",
  "bin": "Bin 7",
  "legoId": "3004",
  "present": true,
  "imageAsset": "assets/pieces/3004.png",
  "part_cat_id": "11"
}
```

## Tests

Run tests:

```bash
flutter test
```

Current tests cover:

- Loading and rendering pieces
- Search behavior
- Category and box filters
- Editing bin values
- Deleting pieces
- Bin-number badge behavior
