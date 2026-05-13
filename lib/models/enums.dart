/// Shared enumerations used across the Hex Grid Mapmaker application.
///
/// These replace the stringly-typed constants that previously caused
/// silent runtime failures when typos were introduced (e.g. `'selcet'`
/// instead of `'select'`). With enums, the Dart compiler catches all
/// invalid values at compile time.
library;

/// The hex grid layout orientation.
///
/// - [pointyTopped]: Hexes have a pointed vertex at the top. Rows are
///   offset horizontally. This is the default.
/// - [flatTopped]: Hexes have a flat edge at the top. Columns are offset
///   vertically.
enum MapOrientation { pointyTopped, flatTopped }

/// The currently active editor tool, controlling how mouse clicks on the
/// canvas are interpreted.
///
/// - [select]: Clicking a tile highlights the region it belongs to.
/// - [draw]: Clicking adds the tile to the active region.
/// - [erase]: Clicking removes the tile from whichever region owns it.
enum Tool { select, draw, erase }

/// Controls what text label is displayed inside each region on the canvas.
///
/// - [none]: No labels are drawn.
/// - [id]: Shows the region's unique numeric ID.
/// - [name]: Shows the region's human-readable name.
enum LabelDisplay { none, id, name }
