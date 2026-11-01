import QtQuick
import qs.Commons
import "WeatherIcons.js" as WeatherIcons

// The weather mark: one outline for the kind of weather the page named, in the
// tone asked for.
//
// The outline is an SVG built by WeatherIcons.js and drawn by Qt as a vector,
// at the widget's size times the screen's pixel ratio, so the strokes stay
// crisp on a scaled display. The markup is made here, never read from the page.
//
// The outlines follow Lucide and Microsoft Fluent (ISC/MIT, see
// icons/README.md).
Item {
  id: root

  // The fetcher's `kind`: clear, mostly, overcast, rain, showers, drizzle,
  // snow, snowflakes, sleet, thunder, hail, fog, wind, unknown. A kind outside
  // that list draws the cloud rather than nothing.
  property string kind: "unknown"
  // The dark half of the day: a moon instead of the sun where there is one.
  property bool night: false
  // A quieter tone for rows that are not selected or hovered.
  property bool dimmed: false
  // The drawn size, in pixels.
  property real size: Style.font.iconLarge

  implicitWidth: size
  implicitHeight: size

  Image {
    // The outlines keep a little air inside their box, so the picture is drawn
    // a touch larger than the space it has to read level with the text beside
    // it.
    width: root.size * 1.15
    height: root.size * 1.15
    source: WeatherIcons.sourceFor(root.kind, root.night, root.dimmed ? WeatherIcons.DIM : WeatherIcons.INK)
    sourceSize.width: Math.round(root.size * 1.15 * Screen.devicePixelRatio)
    sourceSize.height: Math.round(root.size * 1.15 * Screen.devicePixelRatio)
    fillMode: Image.PreserveAspectFit
    smooth: true
  }
}
