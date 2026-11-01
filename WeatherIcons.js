.pragma library

// The weather shapes and how a kind of weather picks one.
//
// The fetcher prints a `kind` for every reading — clear, mostly, overcast,
// rain, showers, drizzle, snow, snowflakes, sleet, thunder, hail, fog, wind,
// unknown — and `night` when it is the dark half of the day. Each kind is drawn
// from the line-art outlines in SHAPES below: Lucide outlines (ISC), plus two
// Microsoft Fluent icons for partially cloudy weather (MIT). icons/README.md
// has the source links and the licences.
//
// The shapes are kept as text, so WeatherIcon.qml can hand one to a Text as
// RichText and any part of the shell can draw it — the bar slot gives a plugin
// widget nothing but a box, and a text entry always brings its own ink.

// The theme's light foreground, bright on any dark theme, and the same mark at
// rest in the shell's muted tone.
var INK = "#E4EDE9"
var DIM = "#6E8280"

// kind -> outline name below; night picks the moon version where the set has
// one (clear, mostly) and leaves the rest as they are
var OUTLINE = {
  clear: "sun",
  mostly: "fluent-partly-cloudy-day",
  overcast: "cloud",
  rain: "cloud-rain",
  showers: "cloud-rain-wind",
  drizzle: "cloud-drizzle",
  snow: "cloud-snow",
  snowflakes: "snowflake",
  sleet: "sun-snow",
  thunder: "cloud-lightning",
  hail: "cloud-hail",
  fog: "cloud-fog",
  wind: "wind",
  unknown: "cloud"
}

var AT_NIGHT = {
  clear: "moon",
  mostly: "fluent-partly-cloudy-night",
  sleet: "cloud-snow"
}

// The bar's mark, for the label beside the temperature. Plain Unicode rather
// than a Nerd Font glyph on purpose: a private-use character has to be found in
// a font chosen for a whole text run, and the bar's run is measured and drawn by
// the shell's own font, which carries the figure but not the glyph. These are
// in the system's symbol fonts, and the run's own fallback finds them.
//
// Every kind gets a mark that names it, and sleet (rain and snow at once) has
// a mark of its own instead of a single snowflake.
var BAR_MARK = {
  clear: "\u2600",                 // sun
  mostly: "\u26c5",                // sun behind cloud
  overcast: "\u2601",              // cloud
  rain: "\u2614",                  // umbrella with rain
  showers: "\u2614",
  drizzle: "\u2614",
  snow: "\u2744",                  // snowflake
  snowflakes: "\u2744",
  sleet: "\u2614\u2744",          // rain and snow together
  thunder: "\u26a1",               // bolt
  hail: "\u2601",                  // cloud with hail (no single symbol)
  fog: "\u2601",
  wind: "\u2634",                  // wind
  unknown: "\u2601"
}

// The shapes, each with its own view box and painting style. The stroke colour
// is set when the picture is built, not here.
var SHAPES = {
  "sun": '<circle cx="12" cy="12" r="4" /> <path d="M12 2v2" /> <path d="M12 20v2" /> <path d="m4.93 4.93 1.41 1.41" /> <path d="m17.66 17.66 1.41 1.41" /> <path d="M2 12h2" /> <path d="M20 12h2" /> <path d="m6.34 17.66-1.41 1.41" /> <path d="m19.07 4.93-1.41 1.41" />',
  "moon": '<path d="M20.985 12.486a9 9 0 1 1-9.473-9.472c.405-.022.617.46.402.803a6 6 0 0 0 8.268 8.268c.344-.215.825-.004.803.401" />',
  "cloud": '<path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z" />',
  "cloud-rain": '<path d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242" /> <path d="M16 14v6" /> <path d="M8 14v6" /> <path d="M12 16v6" />',
  "cloud-rain-wind": '<path d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242" /> <path d="m9.2 22 3-7" /> <path d="m9 13-3 7" /> <path d="m17 13-3 7" />',
  "cloud-drizzle": '<path d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242" /> <path d="M8 19v1" /> <path d="M8 14v1" /> <path d="M16 19v1" /> <path d="M16 14v1" /> <path d="M12 21v1" /> <path d="M12 16v1" />',
  "cloud-snow": '<path d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242" /> <path d="M8 15h.01" /> <path d="M8 19h.01" /> <path d="M12 17h.01" /> <path d="M12 21h.01" /> <path d="M16 15h.01" /> <path d="M16 19h.01" />',
  "snowflake": '<path d="m10 20-1.25-2.5L6 18" /> <path d="M10 4 8.75 6.5 6 6" /> <path d="m14 20 1.25-2.5L18 18" /> <path d="m14 4 1.25 2.5L18 6" /> <path d="m17 21-3-6h-4" /> <path d="m17 3-3 6 1.5 3" /> <path d="M2 12h6.5L10 9" /> <path d="m20 10-1.5 2 1.5 2" /> <path d="M22 12h-6.5L14 15" /> <path d="m4 10 1.5 2L4 14" /> <path d="m7 21 3-6-1.5-3" /> <path d="m7 3 3 6h4" />',
  "sun-snow": '<path d="M10 21v-1" /> <path d="M10 4V3" /> <path d="M10 9a3 3 0 0 0 0 6" /> <path d="m14 20 1.25-2.5L18 18" /> <path d="m14 4 1.25 2.5L18 6" /> <path d="m17 21-3-6 1.5-3H22" /> <path d="m17 3-3 6 1.5 3" /> <path d="M2 12h1" /> <path d="m20 10-1.5 2 1.5 2" /> <path d="m3.64 18.36.7-.7" /> <path d="m4.34 6.34-.7-.7" />',
  "cloud-lightning": '<path d="M6 16.326A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 .5 8.973" /> <path d="m13 12-3 5h4l-3 5" />',
  "cloud-hail": '<path d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242" /> <path d="M16 14v2" /> <path d="M8 14v2" /> <path d="M16 20h.01" /> <path d="M8 20h.01" /> <path d="M12 16v2" /> <path d="M12 22h.01" />',
  "cloud-fog": '<path d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242" /> <path d="M16 17H7" /> <path d="M17 21H9" />',
  "wind": '<path d="M12.8 19.6A2 2 0 1 0 14 16H2" /> <path d="M17.5 8a2.5 2.5 0 1 1 2 4H2" /> <path d="M9.8 4.4A2 2 0 1 1 11 8H2" />',
  "fluent-partly-cloudy-day": '<path d="M25.9956 15.9975C32.3326 15.9975 35.9275 20.1921 36.4504 25.2577L36.6103 25.2577C40.6884 25.2577 43.9944 28.5552 43.9944 32.6228C43.9944 36.6904 40.6884 39.9878 36.6103 39.9878H15.3808C11.3027 39.9878 7.99666 36.6904 7.99666 32.6228C7.99666 28.5552 11.3027 25.2577 15.3809 25.2577L15.5408 25.2577C16.0666 20.1588 19.6585 15.9975 25.9956 15.9975ZM7.56878 24.19C8.0236 24.9778 7.79632 25.9722 7.07019 26.4894L6.92824 26.5806L5.6292 27.3306C4.79219 27.8138 3.7219 27.527 3.23865 26.69C2.78383 25.9023 3.01111 24.9078 3.73725 24.3907L3.8792 24.2995L5.17824 23.5495C6.01525 23.0662 7.08553 23.353 7.56878 24.19ZM21.705 14.6499C17.9036 15.8696 15.1962 18.7411 14.0845 22.5718L13.9906 22.9123L13.8752 23.3879L13.463 23.4649C12.2458 23.7206 11.1148 24.2144 10.1213 24.8959C9.94463 24.5931 9.78662 24.2748 9.64877 23.942C7.98267 19.9197 9.89276 15.3083 13.9151 13.6422C16.5996 12.5303 19.5464 13.0112 21.705 14.6499ZM5.50487 13.9785L5.6374 14.0339L6.99686 14.6678C7.87281 15.0762 8.25178 16.1175 7.84332 16.9934C7.45528 17.8256 6.49618 18.2092 5.65023 17.8953L5.5177 17.8399L4.15824 17.2059C3.28229 16.7975 2.90332 15.7563 3.31178 14.8803C3.69982 14.0482 4.65891 13.6645 5.50487 13.9785ZM24.6155 8.21643C25.3677 8.74307 25.5789 9.75422 25.1229 10.5328L25.0453 10.6537L24.1849 11.8824C23.6306 12.6741 22.5394 12.8666 21.7477 12.3122C20.9955 11.7855 20.7843 10.7744 21.2403 9.99581L21.3179 9.87492L22.1783 8.64619C22.7326 7.85448 23.8238 7.66207 24.6155 8.21643ZM14.3237 7.79709L14.3888 7.95272L14.9019 9.36226C15.2324 10.2705 14.7641 11.2747 13.8559 11.6053C13.0011 11.9164 12.0613 11.5199 11.6781 10.715L11.6129 10.5593L11.0999 9.14979C10.7693 8.24158 11.2376 7.23736 12.1458 6.9068C13.0006 6.59568 13.9405 6.99218 14.3237 7.79709Z" fill="{c}"/>',
  "fluent-partly-cloudy-night": '<path d="M25.9956 15.9975C32.3326 15.9975 35.9275 20.1921 36.4504 25.2577L36.6103 25.2577C40.6884 25.2577 43.9944 28.5552 43.9944 32.6228C43.9944 36.6904 40.6884 39.9878 36.6103 39.9878H15.3808C11.3027 39.9878 7.99666 36.6904 7.99666 32.6228C7.99666 28.5552 11.3027 25.2577 15.3809 25.2577L15.5408 25.2577C16.0666 20.1588 19.6585 15.9975 25.9956 15.9975ZM26 13.995C24.3226 8.488 19.7333 5 14.5 5 7.939 5 3 10.672 3 18.5S7.939 32 14.5 32c3.316 0 6.271-1.448 8.217-3.694a8.5 8.5 0 0 1-.717-9.306A9.99 9.99 0 0 1 26 13.995Z" fill="{c}"/>'
}

var FLUENT = { "fluent-partly-cloudy-day": true, "fluent-partly-cloudy-night": true }

// The shape a kind is drawn with.
function shapeName(kind, night) {
  var key = String(kind || "unknown")
  if (!OUTLINE.hasOwnProperty(key)) key = "unknown"
  if (night && AT_NIGHT.hasOwnProperty(key)) return AT_NIGHT[key]
  return OUTLINE[key]
}

// The mark the bar's label shows for a kind.
function markFor(kind, night) {
  var key = String(kind || "unknown")
  if (!BAR_MARK.hasOwnProperty(key)) key = "unknown"
  return BAR_MARK[key]
}

// The outline as an SVG document, painted in `tone`.
function svgFor(kind, night, tone) {
  var shape = shapeName(kind, night)
  var body = SHAPES[shape]
  if (!body) return ""
  var ink = tone || INK
  var fluent = FLUENT.hasOwnProperty(shape)
  var viewBox = fluent ? "0 0 48 48" : "0 0 24 24"
  var style = fluent
    ? 'fill="' + ink + '" stroke="none"'
    : 'fill="none" stroke="' + ink + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"'
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="' + viewBox + '" ' + style + '>' + body.replace(/\{c\}/g, ink) + '</svg>'
}

// For an Image: the picture as a source. Qt draws it as a vector, at the size
// and the screen's ratio the Image asks for, so the lines stay crisp.
function sourceFor(kind, night, tone) {
  var svg = svgFor(kind, night, tone)
  return svg === "" ? "" : "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg)
}

// For a Text in RichText mode: the same picture as markup.
function htmlFor(kind, night, tone, px) {
  var source = sourceFor(kind, night, tone)
  if (source === "") return ""
  return '<img width="' + Math.round(px) + '" height="' + Math.round(px) + '" src="' + source + '">'
}
