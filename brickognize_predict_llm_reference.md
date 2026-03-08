# Brickognize Predict Endpoint Reference for LLM Integration

This reference is designed for an LLM or agent that needs to call Brickognize's **predict** API and extract the predicted **item ID** from the response.

## Purpose

Send an image to Brickognize and return the most likely recognized LEGO item ID.

## Important caveat

The `/predict/` endpoint is documented under **`search (legacy)`** and is explicitly marked as **deprecated** in the OpenAPI spec. Use it as-is for now, but do not assume it is a long-term stable integration surface.

## Endpoint

- **Method:** `POST`
- **URL:** `https://api.brickognize.com/predict/`
- **Content-Type:** `multipart/form-data`
- **Field name:** `query_image`
- **Field type:** binary file upload
- **Schema:** `query_image` is an **array of binary files** in the OpenAPI spec

## What to send

Upload the target image as multipart form data using the field name `query_image`.

Example conceptual payload:

```text
POST /predict/
Content-Type: multipart/form-data

query_image = <binary image file>
```

## What comes back

The response body is JSON with this top-level structure:

```json
{
  "listing_id": "res-d492bca0",
  "bounding_box": {
    "left": 0.0,
    "upper": 0.0,
    "right": 320.0,
    "lower": 240.0,
    "image_width": 768.0,
    "image_height": 1024.0,
    "score": 0.99
  },
  "items": [
    {
      "id": "3001",
      "name": "Brick 2 x 4",
      "img_url": "https://...",
      "external_sites": [
        {
          "name": "bricklink",
          "url": "https://..."
        }
      ],
      "category": "Brick",
      "type": "part",
      "score": 0.9
    }
  ]
}
```

## How to get the predicted item ID

Use this rule:

1. Read `items`
2. If `items` is empty, return `null` or `no_match`
3. Otherwise, treat `items[0]` as the top prediction
4. Extract `items[0].id`

### Canonical extraction

```json
items[0].id
```

### Recommended returned shape for your app

```json
{
  "item_id": "3001",
  "item_name": "Brick 2 x 4",
  "item_type": "part",
  "confidence": 0.9,
  "listing_id": "res-d492bca0"
}
```

## Response field meanings

### Top level

- `listing_id`: identifier for this recognition result
- `bounding_box`: detected region in the image
- `items`: ranked candidate matches

### Candidate item fields

- `id`: the item ID you likely want
- `name`: human-readable item name
- `img_url`: thumbnail URL
- `external_sites`: related external links
- `category`: item category, may be `null`
- `type`: one of `part`, `set`, `fig`, `sticker`
- `score`: confidence from `0.0` to `1.0`

## Error handling

The spec documents:

- `200` = success
- `422` = validation error

A `422` response uses this shape:

```json
{
  "detail": [
    {
      "loc": ["body", "query_image"],
      "msg": "...",
      "type": "..."
    }
  ]
}
```

## Practical integration guidance for an LLM

Follow these rules:

1. Prefer `/predict/` when you want the API to determine the item type automatically.
2. If your workflow already knows the target is a part, set, or minifigure, consider the type-specific legacy endpoints:
   - `/predict/parts/`
   - `/predict/sets/`
   - `/predict/figs/`
3. Always check whether `items` exists and has at least one element.
4. Use the highest-ranked item only if you need a single answer.
5. Keep `listing_id` if you may later submit feedback to Brickognize.
6. Because the endpoint is legacy/deprecated, wrap it behind your own adapter so you can swap implementations later.

## Minimal pseudocode

```text
send image file to POST https://api.brickognize.com/predict/ as multipart/form-data with field query_image
parse JSON response
if items is missing or empty:
    return no_match
else:
    top = items[0]
    return {
        item_id: top.id,
        item_name: top.name,
        item_type: top.type,
        confidence: top.score,
        listing_id: listing_id
    }
```

## cURL example

```bash
curl -X POST \
  "https://api.brickognize.com/predict/" \
  -H "accept: application/json" \
  -H "Content-Type: multipart/form-data" \
  -F "query_image=@/path/to/image.jpg"
```

## Python example

```python
import requests

url = "https://api.brickognize.com/predict/"

with open("image.jpg", "rb") as f:
    response = requests.post(
        url,
        files={"query_image": f},
        headers={"accept": "application/json"},
        timeout=60,
    )

response.raise_for_status()
data = response.json()

items = data.get("items", [])
if not items:
    result = None
else:
    top = items[0]
    result = {
        "item_id": top.get("id"),
        "item_name": top.get("name"),
        "item_type": top.get("type"),
        "confidence": top.get("score"),
        "listing_id": data.get("listing_id"),
    }

print(result)
```

## JavaScript example

```javascript
import fs from "node:fs";

const form = new FormData();
form.append("query_image", new Blob([fs.readFileSync("image.jpg")]), "image.jpg");

const response = await fetch("https://api.brickognize.com/predict/", {
  method: "POST",
  headers: {
    accept: "application/json"
  },
  body: form
});

if (!response.ok) {
  throw new Error(`HTTP ${response.status}`);
}

const data = await response.json();
const top = data.items?.[0];

const result = top
  ? {
      item_id: top.id,
      item_name: top.name,
      item_type: top.type,
      confidence: top.score,
      listing_id: data.listing_id
    }
  : null;

console.log(result);
```

## Integration contract to assume

For a single-image lookup, the safest assumption is:

- input: one uploaded image file under `query_image`
- output: use `items[0].id` as the best predicted item ID
- fallback: no match if `items.length === 0`

## Known unknowns

The published OpenAPI spec does **not** clearly document, at least in the exposed schema excerpt:

- authentication requirements
- rate limits
- retry guidance
- image size limits
- SLA/versioning guarantees beyond the legacy/deprecated warning

Do not hardcode assumptions about those.
