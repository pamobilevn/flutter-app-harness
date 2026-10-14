---
name: app-harness-design
description: Phase 3 — specify lib/core/theme/design_tokens.dart + app_theme.dart (Material 3 light and dark themes, contrast-checked), the visual concept and component inventory, one screen spec per PRD route with loading/empty/error/success states, an optional Figma/Stitch design source, and the icon/splash/illustration/font asset plan.
argument-hint: ""
allowed-tools: [Agent, Read, Write, Edit, Bash]
---

# app-harness-design

> **Plugin paths.** `docs/harness-protocol.md`, `docs/app-gotchas.md`, and `templates/` are files of this
> plugin, not of the app: read them at `${CLAUDE_PLUGIN_ROOT}/<path>` (fallback: this skill's base
> directory + `/../../<path>`). `docs/harness/` (config, state, specs, plans, logs) is the app's run
> state in the working directory.

Phase 3 of the flutter-app-harness pipeline. Reads the latest PRD and `config.md`, then produces a
design document that specifies `lib/core/theme/design_tokens.dart` and
`lib/core/theme/app_theme.dart`, the visual concept, a screen spec for every PRD route, and the
asset plan (launcher icon, splash, illustrations, fonts). Advances pipeline state to `contract`.

All file schemas (`config.md`, `state.md`, `pipeline-log.md`) and the phase transition table
are defined in `docs/harness-protocol.md` — refer to that document as the single source of
truth (§2 for `state.md` schema; §7 for the `design → contract` transition). Do not redefine
schemas here. Accessibility (R10), async states (R1), and branding/platform patterns live in
`docs/app-gotchas.md` — cite, do not restate.

---

## Input

### 1. Read `docs/harness/config.md`

Extract:

| Key | Use |
|---|---|
| `app_idea` | Informs brand personality and tone |
| `app_name` | Splash/icon glyph, app bar titles |
| `default_language` | Write every copy sample (empty/error messages, CTA labels) in it |
| `locales` | The bundled font (if any) must cover every locale's script |
| `orientation`, `device_family` | `all` → layouts survive rotation; `universal` → wide-screen layout per screen |
| `skip_monetize` | `true` → no ad slots anywhere |

If `config.md` does not exist, abort with:
`app-harness-design: docs/harness/config.md not found — run the orchestrator to bootstrap first.`

### 2. Read the latest PRD

Find the most recent file matching `docs/harness/plans/*-prd.md` (sort descending by filename,
take the first). If no PRD exists, abort with:
`app-harness-design: no PRD found in docs/harness/plans/ — run app-harness-plan first.`

Extract from the PRD (sections are found by their English heading term):

- **Product & concept** — category, target user, differentiator → brand personality and colour mood
- **Primary user flows** — F1…Fn → interactions and success feedback per screen
- **Screens & navigation** — navigation shell, onboarding yes/no, and the route table → **one
  screen spec per route name, one-to-one**
- **Settings & permissions** — permission rationale UI
- **Monetization intent** — candidate placements → reserved ad slots in the screen specs (none
  when `skip_monetize: true`)

---

## Update mode (`config.mode: update`)

For an existing app the design already exists in code — extract it, don't invent a new one:

- **Extract tokens first:** read the project's theme (`ThemeData`, `ColorScheme`, text styles, any
  colours/spacing constants) and record them in `## Design tokens` as the **current** values, with file
  paths. If the project has no token file, the generator creates `lib/core/theme/design_tokens.dart`
  holding these extracted values (no visual change) and uses it for NEW/CHANGE screens only.
- **Change visuals only on request:** palette, typography, or component restyling happens only when the
  change request asks for it. Otherwise light/dark contrast problems found here become fix items for
  CHANGE/NEW screens; KEEP screens are left untouched (note any contrast failure as a finding).
- **Dark theme:** if the app has none and the change request does not add it, record
  `dark theme: not in scope` under `## Assumptions` (R10's dark-theme item is then N/A for this run).
- **Screen specs** only for `CHANGE` and `NEW` routes from the delta PRD (KEEP screens: one line each,
  "unchanged").
- **Asset plan:** keep the existing icon, splash, and display name unless the change request rebrands;
  write `branding: unchanged` and skip the icon/splash generation specs.

---

## External design source

Optional. Look for a design the user supplied — in the harness invocation or conversation,
`app_idea`, or the PRD: a **Figma** file/frame URL (`figma.com/design/<fileKey>/…?node-id=…`) or a
**Google Stitch** project (URL or project id). Do not ask for one.

- **Supplied** → record it in the design doc under `## External design source`: the kind (Figma |
  Stitch), the link/id, and a screen map (source frame/screen → PRD route name). If Figma/Stitch MCP
  tools are available in this session, derive the token values (colours, type, radius, spacing)
  from the source's styles/variables — cheapest metadata/list calls first, smallest node scope — so
  the tokens match it. Note in the doc that **the generator implements the mapped screens from the
  source** using whatever Figma/Stitch MCP tools or skills are available in its session, while
  mapping every value onto the tokens below (no raw values — contract Hard Gate 4). Routes not in
  the source, and every loading/empty/error state the source lacks, are built from `## Screen specs`.
- **Not supplied** → write `none — the generator builds every screen from the screen specs below.`

---

## Design tokens

Write a specification for `lib/core/theme/design_tokens.dart` and `lib/core/theme/app_theme.dart`
that the generator can implement verbatim. The spec must cover every sub-section below.

### Colour roles (light + dark)

Derive a **seed colour** from the brand personality and category (finance → calm, high-trust
blues/greens; health → fresh greens/teals; productivity → focused neutrals with one accent;
education → friendly saturated hues; lifestyle → warm tones). Material 3 generates the full scheme
with `ColorScheme.fromSeed`; the design pins the text-bearing pairs as explicit overrides in **both**
themes so their contrast is known:

| Role pair | Light (bg / fg) | Ratio | Dark (bg / fg) | Ratio |
|---|---|---|---|---|
| primary / onPrimary | `#RRGGBB` / `#RRGGBB` | ≥ 4.5 | `#RRGGBB` / `#RRGGBB` | ≥ 4.5 |
| surface / onSurface | … | ≥ 4.5 | … | ≥ 4.5 |
| surface / onSurfaceVariant (secondary text) | … | ≥ 4.5 | … | ≥ 4.5 |
| error / onError | … | ≥ 4.5 | … | ≥ 4.5 |

Rules:
- Text pairs ≥ 4.5:1 in **both** themes (3:1 only for large text ≥ 24 px, icons, and component
  boundaries). Record the computed ratio in the table — compute it, don't estimate:

  ```bash
  python3 - <<'EOF'
  def lum(h):
      c = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
      c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
      return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
  def ratio(a, b):
      hi, lo = sorted((lum(a), lum(b)), reverse=True)
      return (hi + 0.05) / (lo + 0.05)
  for bg, fg in [("1E6A4F", "FFFFFF"), ("FBFDF9", "191C1A")]:  # replace with the table's pairs
      print(bg, fg, round(ratio(bg, fg), 2))
  EOF
  ```
- Light and dark use the same seed (same hue family); dark surfaces are dark tones of the seed,
  not pure `#000000`.
- Never convey meaning by colour alone (status chips also carry an icon or label).
- Need exact brand colours for more roles? Add them as further `fromSeed` overrides in the tokens —
  never a parallel palette outside `DesignTokens`.

### Typography

Map the app's text to Material 3 `TextTheme` roles. Keep the M3 default size/weight/height unless
the brand needs a change, and list only the roles that differ:

| Role | Used for | Size / weight / height (only if not M3 default) |
|---|---|---|
| headlineMedium | screen titles on large headers | — |
| titleLarge | app bar title | — |
| titleMedium | list item primary text | — |
| bodyLarge / bodyMedium | body copy | — |
| labelLarge | buttons | — |
| displaySmall | big numeric figures (totals, timers) | tabular figures |

Font: **system default** (`fontFamily: null` → Roboto on Android, SF Pro on iOS — zero assets) unless
the brand needs a custom face; then name one bundled font family (see Asset plan → Fonts). Numeric
displays use `fontFeatures: const [FontFeature.tabularFigures()]`. Sizes are logical pixels and
scale with the OS text size (`TextScaler`) — never pinned (`docs/app-gotchas.md`, *Accessibility*).

### Spacing, radius, elevation, motion, tap target

```
Spacing  xs 4 · sm 8 · md 16 · lg 24 · xl 32 · xxl 48          (screen margin = md)
Radius   xs 4 · sm 8 · md 12 · lg 16 · xl 28 · full = StadiumBorder   (M3 shape scale)
Elevation 0 · 1 · 3 · 6                                          (M3 levels 0–3)
Motion   short 150 ms · medium 300 ms · long 500 ms · curve easeInOutCubicEmphasized
minTapTarget 48 dp
```

All layout values in UI code come from these named tokens — no raw numbers. Every interactive
control is at least `minTapTarget` (gate R10). When Reduce Motion is on
(`MediaQuery.disableAnimations`), non-essential motion uses `Duration.zero`. For
`device_family: universal` also define `maxContentWidth` (e.g. 600) for wide screens.

### `design_tokens.dart` file template

The generator must emit a file with this exact structure:

```dart
// lib/core/theme/design_tokens.dart
// Generated by app-harness-design — values come from docs/harness/plans/<date>-design.md.
// Change the design doc first, then this file. No other file defines colours, spacing, or type.

import 'package:flutter/material.dart';

abstract final class DesignTokens {
  // --- Colour: seed + explicit text-pair overrides (scheme built in app_theme.dart) ---
  static const Color seed = Color(0xFF______);

  static const Color lightPrimary = Color(0xFF______);
  static const Color lightOnPrimary = Color(0xFF______);
  static const Color lightSurface = Color(0xFF______);
  static const Color lightOnSurface = Color(0xFF______);
  static const Color lightOnSurfaceVariant = Color(0xFF______);
  static const Color lightError = Color(0xFF______);
  static const Color lightOnError = Color(0xFF______);

  static const Color darkPrimary = Color(0xFF______);
  static const Color darkOnPrimary = Color(0xFF______);
  static const Color darkSurface = Color(0xFF______);
  static const Color darkOnSurface = Color(0xFF______);
  static const Color darkOnSurfaceVariant = Color(0xFF______);
  static const Color darkError = Color(0xFF______);
  static const Color darkOnError = Color(0xFF______);

  // --- Typography ---
  static const String? fontFamily = ______; // null = platform default, or 'FamilyName' (bundled)

  // --- Spacing ---
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;
  static const double spaceXxl = 48;

  // --- Radius (M3 shape scale; full = StadiumBorder) ---
  static const double radiusXs = 4;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 28;

  // --- Elevation (M3 levels) ---
  static const double elevation0 = 0;
  static const double elevation1 = 1;
  static const double elevation2 = 3;
  static const double elevation3 = 6;

  // --- Motion ---
  static const Duration motionShort = Duration(milliseconds: 150);
  static const Duration motionMedium = Duration(milliseconds: 300);
  static const Duration motionLong = Duration(milliseconds: 500);
  static const Curve motionCurve = Curves.easeInOutCubicEmphasized;

  // --- Accessibility ---
  static const double minTapTarget = 48;

  // --- Layout (device_family: universal only — delete otherwise) ---
  static const double maxContentWidth = 600;
}
```

Fill every `______` from the colour table and typography decision above.

### `app_theme.dart` file template

`ColorScheme.fromSeed` is not `const`, so the scheme is built here, not in the tokens:

```dart
// lib/core/theme/app_theme.dart
// Generated by app-harness-design. Builds ThemeData from DesignTokens only.

import 'package:flutter/material.dart';

import 'design_tokens.dart';

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: DesignTokens.seed,
      brightness: brightness,
      primary: isDark ? DesignTokens.darkPrimary : DesignTokens.lightPrimary,
      onPrimary: isDark ? DesignTokens.darkOnPrimary : DesignTokens.lightOnPrimary,
      surface: isDark ? DesignTokens.darkSurface : DesignTokens.lightSurface,
      onSurface: isDark ? DesignTokens.darkOnSurface : DesignTokens.lightOnSurface,
      onSurfaceVariant:
          isDark ? DesignTokens.darkOnSurfaceVariant : DesignTokens.lightOnSurfaceVariant,
      error: isDark ? DesignTokens.darkError : DesignTokens.lightError,
      onError: isDark ? DesignTokens.darkOnError : DesignTokens.lightOnError,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: DesignTokens.fontFamily,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: base.textTheme.copyWith(
        // only the roles listed in the typography table, e.g.:
        // displaySmall: base.textTheme.displaySmall?.copyWith(
        //     fontFeatures: const [FontFeature.tabularFigures()]),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: DesignTokens.elevation0,
        scrolledUnderElevation: DesignTokens.elevation2,
      ),
      cardTheme: CardThemeData(
        elevation: DesignTokens.elevation1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(DesignTokens.minTapTarget, DesignTokens.minTapTarget),
          shape: const StadiumBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      // + one component theme per remaining component in the inventory
      //   (navigationBarTheme, dialogTheme: DialogThemeData(...), listTileTheme, …)
    );
  }
}
```

`lib/app/app.dart` wires `theme: AppTheme.light`, `darkTheme: AppTheme.dark`,
`themeMode: ThemeMode.system` (or the theme setting from PRD §6, if one exists).

---

## Visual concept

### Brand personality

Three adjectives (e.g. *calm, precise, encouraging*) and, for each, what it means visually
(colour saturation, corner radius, density, motion amount, illustration tone, copy voice). The
description must be concrete enough that another designer would make the same choices.

### Iconography

Material Symbols design language. Default implementation: Flutter's built-in `Icons.*` (Material
Icons font, bundled via `uses-material-design: true` — **no package**); use the `*_outlined`
variant for unselected states and the filled one for selected (navigation bar). Only if the concept
needs Symbols' variable axes (weight/fill/grade) add `material_symbols_icons` and record it in the
Asset plan. List the icon for every navigation destination and primary action. Icon-only buttons
always carry a `tooltip` (gate R10).

### Illustration style (empty states, onboarding)

Default: **code-drawn** `CustomPainter` widgets in `lib/core/widgets/` — simple geometric shapes
built from `Theme.of(context).colorScheme`, so they adapt to dark mode and need no assets. Use SVG
(`flutter_svg`) only for art sourced with a recorded licence (URL + licence in the Asset plan).
Illustrations are decorative — wrap them in `ExcludeSemantics`; the message text carries meaning.

| Illustration | Used on (route names) | Description | Implementation |
|---|---|---|---|
| <empty_items> | <routeName> | <what it depicts, colour roles used> | `<EmptyItemsPainter>` / SVG path + licence |

### Component inventory

Every shared widget the screens use, with its token mapping. Minimum set:

| Component | Location | Spec |
|---|---|---|
| `AsyncValueView` / `EmptyView` / `ErrorView` | `lib/core/widgets/` | loading / empty (illustration + message + CTA) / error (message + Retry) — gate R1 |
| Primary button | theme (`FilledButton`) | stadium, ≥ `minTapTarget` |
| List row | <ListTile / custom> | paddings from spacing tokens; `MergeSemantics` for custom rows |
| Confirm dialog / bottom sheet | <…> | destructive actions confirm, or offer Undo via SnackBar |
| Form field | theme (`InputDecorationTheme`) | label, helper, inline error text |
| Ad slot position (only when PRD §7 lists placements and `skip_monetize: false`) | screen spec | where the monetize phase inserts the ad widget; the generator renders nothing there (no empty box), and the layout must let an ad sit there without covering content or FABs |

---

## Screen specs

Screen inventory: one entry per route in the PRD's **Screens & navigation** table, keyed by the
exact route name, in table order — no extras, none missing. Add onboarding pages and permission
rationale UI as their own entries when the PRD has them.

```markdown
### <routeName> — `<path>`

- **Purpose / flows:** <one line> · F1, F2
- **Layout (top → bottom):** <AppBar(title) · sections · FAB / bottom action>
- **Components:** <names from the component inventory>
- **States:**
  - Loading: <skeleton or spinner>
  - Empty: <illustration> + "<message in default_language>" + [<CTA label>] → <action / route>
  - Error: "<message in default_language>" + [<Retry label>] → re-fetch via the provider
  - Success: <what is shown; confirmation feedback after a save (SnackBar / inline)>
  (A screen with no async data writes `States: static — no async data`.)
- **Interactions:** <gesture → result / route>; destructive actions confirm or offer Undo
- **Ad slot:** <banner below content, above the nav bar | native after item N | none> (position only — filled by the monetize phase)
- **Accessibility:** <tooltips/semantic labels for icon-only controls; reading order; behaviour at
  200 % text scale (wraps, no clipped text); colour-independent status>
- **Wide layout:** <universal only: max content width / two-pane — otherwise omit>
```

The empty/error/CTA strings are the real copy (in `default_language`); the generator turns them
into ARB keys.

---

## Asset plan

> **Defaults the generator can always satisfy with no sourcing:** icon, splash, and Play store
> graphics drawn by the shared code painter (`templates/gen_icon.dart.template` → `tool/gen_icon.dart`,
> token colours); illustrations code-drawn; system font; **no audio**. Specify sourced art or a custom
> font below only if the concept needs it, with source URL + licence. The harness never depends on
> assets that aren't sourced.

### Launcher icon — flutter_launcher_icons

> Branding art source: by default the generator draws the icon/splash from the shared code painter
> using design-token colours; choose **AI-generated or sourced art** here instead if the concept
> warrants it. Either way the generator runs `flutter_launcher_icons` / `flutter_native_splash` and
> sets the localized app display name — design only specifies intent.

Painter inputs (`tool/gen_icon.dart` constants), each a token value:

```
kBg      <hex>  icon background = adaptive_icon_background
kPrimary <hex>  motif base   (≥ 3:1 against kBg and against BOTH splash colours)
kAccent  <hex>  motif accent
kGlyph   <first letter of app_name, or a motif note>
```

The splash logo is the same motif on a transparent canvas, composited on the light and the dark
splash colour — so the motif must stay visible on both.

Specify the icon intent so the generator can configure `flutter_launcher_icons`:

```yaml
# pubspec.yaml excerpt (dev_dependencies)
flutter_launcher_icons:
  android: true
  ios: true
  remove_alpha_ios: true
  image_path: "assets/icons/icon.png"                    # 1024×1024, no alpha (iOS + legacy)
  adaptive_icon_background: "<kBg hex>"                  # solid, opaque
  adaptive_icon_foreground: "assets/icons/icon-fg.png"   # safe-zone padded (NOT full-bleed)
  adaptive_icon_monochrome: "assets/icons/icon-mono.png" # Android 13+ themed icon
  min_sdk_android: 23
  web:
    generate: false
```

The icon must:
- Be 1024×1024 pixels, PNG format; iOS `icon.png` is **opaque** (no alpha).
- Follow the brand personality (a simple, recognisable motif or glyph on the icon background — no
  text other than a single glyph, no screenshots).
- **Android adaptive foreground** (`icon-fg.png`): the motif must sit inside the **safe zone** — the
  108dp canvas is masked to ≤72dp and only the centre ~66dp is guaranteed unclipped, so keep ~25%
  padding on every side. Reusing the full-bleed `icon.png` here makes the icon look cropped/"zoomed"
  on Android. Background is a solid colour (`kBg`), not an image.
- **Android themed icon** (`icon-mono.png`): a single-colour (white-on-transparent) silhouette in the
  same safe zone; Android 13+ tints it to the user's theme. Without it the icon looks out of place
  among themed icons (Google Play increasingly expects one).

The same painter emits the Play hi-res icon (512×512) and feature graphic (1024×500), both opaque
(gate R8).

### Splash — flutter_native_splash

Specify the splash screen intent for `flutter_native_splash`:

```yaml
# pubspec.yaml excerpt
flutter_native_splash:
  color: "<light surface hex>"          # == DesignTokens.lightSurface (light scaffold background)
  color_dark: "<dark surface hex>"      # == DesignTokens.darkSurface (dark scaffold background)
  image: assets/images/splash.png       # 512×512 transparent motif (from gen_icon.dart)
  android_12:
    color: "<light surface hex>"
    color_dark: "<dark surface hex>"
    image: assets/images/splash.png
    icon_background_color: "<kBg hex>"
    icon_background_color_dark: "<kBg hex or a dark variant>"
  ios: true
  android: true
  web: false
```

The splash must:
- Use `color` / `color_dark` equal to the first Flutter frame's background in each theme, or the
  launch blinks (`docs/app-gotchas.md`, *Build / platform*).
- Use only `assets/images/splash.png` — no `image_dark`, since the painter emits a single splash
  image (a missing asset fails gate R7).
- Show the app motif only — no text, no loading indicator.

### Illustrations

Repeat the illustration table from the Visual concept with the implementation decided: code-drawn
painter class names, or for sourced SVGs the file path under `assets/illustrations/`, source URL, and
licence.

### Fonts

- Default: system font — no font assets.
- Custom font (only if the brand needs it): bundle the TTF/OTF files for the weights actually used
  in `assets/fonts/`, declare them under `flutter: fonts:` in `pubspec.yaml`, and ship the licence
  (`assets/fonts/OFL.txt` registered with `LicenseRegistry.addLicense` in `bootstrap.dart`). Never
  fetch fonts at runtime (`google_fonts` runtime fetching fails offline and delays the first frame).
  The font must cover every script in `locales` (e.g. Vietnamese diacritics, Hangul, Kana/Kanji);
  otherwise use the system font for those locales.

### Audio

None by default. Only if a PRD flow needs a sound (e.g. a timer alert), list the file, source URL,
and licence; bundle WAV/M4A/MP3 (iOS does not reliably play OGG) under `assets/audio/`.

### pubspec assets

Declare asset **directories** with a trailing slash (e.g. `assets/icons/`, `assets/images/`),
lowercase names only. Every declared or referenced asset must exist (gate R7).

---

## Output

### 1. Write the design document

Create `docs/harness/plans/<YYYY-MM-DD>-design.md` (use today's UTC date).

If `docs/harness/plans/` does not exist, create it before writing.

The document must include all of the following sections, with these exact English headings
(downstream phases grep for them; prose may be in `default_language`):

- `## External design source` — the Figma/Stitch link and screen map, or `none`
- `## Design tokens` — colour-role table (light + dark, computed ratios), typography table,
  spacing/radius/elevation/motion, and the filled `design_tokens.dart` + `app_theme.dart` templates
- `## Visual concept` — brand personality, iconography, illustration style, component inventory
- `## Screen specs` — one `### <routeName>` entry per PRD route (states, interactions, ad slot,
  accessibility)
- `## Asset plan` — painter inputs, `flutter_launcher_icons` config, `flutter_native_splash` config
  (with `color_dark`), illustrations, fonts, audio (`none`)

Fill every section from the PRD and `config.md`; do not leave placeholder text.

### 2. Update `state.md`

Update `docs/harness/state.md` per `docs/harness-protocol.md` §2 and the transition rule
in §7 (`design` → `contract`). Per §7 rule 2, a skill that completes successfully and
advances the pipeline sets `status: running` together with `current_phase` and `next_role`
in the same atomic write:

```yaml
status: running
current_phase: design
next_role: contract
updated_at: "<ISO-8601 UTC now>"
```

Leave all other keys unchanged. Use `Edit` for a targeted update.

### 3. Append to `pipeline-log.md`

Append one row to `docs/harness/pipeline-log.md` per `docs/harness-protocol.md` §6:

```
| <ISO-8601 UTC now> | complete | design | design_tokens + app_theme spec written; <N> screen specs; source: <none | Figma | Stitch>; next: contract |
```

---

## Error handling

- Every pause appends `| <ISO-8601 UTC now> | pause | design | manual_action: <what is missing> |` to
  `pipeline-log.md` (protocol §7 rule 12), and leaves `next_role` on the phase that must produce the
  missing input (`plan` for a missing PRD, `design` for a missing design doc).
- If the PRD is missing or empty, abort with a clear message and set `state.md` to
  `status: paused`, `pause_reason: manual_action`.
- If `config.md` cannot be read, abort immediately (do not write partial output).
- If the PRD's route table is missing, abort the same way — screen specs cannot be keyed without it.
- If the brand mood cannot be determined from the PRD, choose a neutral seed (`#3F6FB5`, a calm
  blue), keep the M3 defaults, and note the assumption in the design document under an
  `## Assumptions` heading.
- If an external design source is supplied but cannot be read in this session, record the link
  anyway, derive the tokens as above, and note it under `## Assumptions`.
