import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "WeatherData.js" as WeatherData
import "WeatherIcons.js" as WeatherIcons

// Яндекс Погода for the Omarchy bar.
//
// The bar faces the widget and also owns the panel, so the panel keeps none
// of the fetching itself: both read the same reading, and a click only
// reveals it.
//
// Data comes from bin/yandex-weather.py, which asks yandex.ru/pogoda for the
// chosen place's page and prints the current weather and a ten-day forecast
// as JSON. The script turns the page's hidden summary and its forecast cards
// into plain numbers and words; the bar only draws them.
BarWidget {
  id: root
  moduleName: "pole.yandex-weather"

  // Strings come from the plugin's own catalogs, so the bar follows the
  // desktop language like the shell's own widgets.
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // ---------------------------------------------------------------- state
  //
  // `snapshot` is the last good reading, kept while a new one is on the way
  // so the bar never flashes empty, and across a failed refresh.
  property var snapshot: null
  property string lastError: ""
  property bool loading: false
  property bool refreshPending: false
  property int clockTick: 0

  readonly property string city: String(setting("city", "elektrougli") || "elektrougli")
  readonly property string cityName: String(setting("cityName", "") || "")
  readonly property var myCities: Array.isArray(setting("cities", [])) ? setting("cities", []) : []
  readonly property int refreshMinutes: Math.max(0, Number(setting("refreshMinutes", 30)) || 0)
  readonly property bool showCondition: setting("showCondition", false) === true

  readonly property var current: snapshot && snapshot.current ? snapshot.current : null
  readonly property var placeName: snapshot && snapshot.name ? String(snapshot.name) : (cityName || city)
  readonly property var today: snapshot && snapshot.days && snapshot.days.length > 0 ? snapshot.days[0] : null
  readonly property string weatherKind: current && current.kind ? String(current.kind) : "unknown"
  readonly property bool weatherNight: current ? current.night === true : false

  // What the bar prints: the temperature now, and the words if asked for.
  readonly property string tempLabel: current ? WeatherData.formatTemp(current.temp) : ""
  readonly property string barText: {
    if (tempLabel !== "") {
      if (!showCondition || !current || !current.condition) return tempLabel
      return tempLabel + " " + String(current.condition)
    }
    return loading ? "…" : ""
  }

  readonly property string barTooltip: {
    if (!current) return lastError !== "" ? strings.t("error." + lastError) : ""
    var lines = [placeName + ": " + WeatherData.formatTemp(current.temp)]
    if (current.condition) lines.push(String(current.condition))
    if (current.feels !== null && current.feels !== undefined)
      lines.push(strings.t("panel.feels").arg(WeatherData.formatTemp(current.feels)))
    if (today) {
      var range = WeatherData.dayRange(today)
      if (range.low !== null && range.high !== null)
        lines.push(WeatherData.formatTemp(range.low) + "…" + WeatherData.formatTemp(range.high))
    }
    lines.push(strings.t("bar.tooltipHint"))
    return lines.join("\n")
  }

  // ---------------------------------------------------------------- panel

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  // The panel is built with the bar, so a click that arrives before that first
  // build is kept and handed over when the panel exists.
  property bool openWhenReady: false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) {
      openWhenReady = false
      panelLoader.item.open()
    } else {
      openWhenReady = true
    }
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (!panelLoader.item) {
      openWhenReady = true
      return
    }
    panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // The panel asks for a city and the bar writes it down, so shell.json stays
  // the single source of truth. Existing keys keep their order.
  function persistSettings(values) {
    var entry = {}
    var keys = []
    for (var existing in root.settings) if (existing !== "id") keys.push(existing)
    for (var added in values) if (keys.indexOf(added) < 0) keys.push(added)
    for (var i = 0; i < keys.length; i++) {
      var name = keys[i]
      entry[name] = values.hasOwnProperty(name) ? values[name] : root.settings[name]
    }

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setCity(slug, name) {
    var clean = String(slug || "").trim()
    if (clean === "") return
    var label = String(name || "")

    // A place picked from search joins the shortlist at the front, unless it
    // is already in it.
    var cities = []
    for (var i = 0; i < root.myCities.length; i++) {
      var item = root.myCities[i] || {}
      if (String(item.slug || "") === clean) continue
      cities.push({ slug: String(item.slug || ""), name: String(item.name || "") })
    }
    if (label !== "") cities.unshift({ slug: clean, name: label })

    persistSettings({ city: clean, cityName: label, cities: cities })

    // Nothing in the old reading belongs to the new place.
    root.snapshot = null
    root.lastError = ""
    root.refresh()
  }

  function removeCity(slug) {
    var clean = String(slug || "")
    if (clean === "" || clean === root.city) return
    var cities = []
    for (var i = 0; i < root.myCities.length; i++) {
      var item = root.myCities[i] || {}
      if (String(item.slug || "") === clean) continue
      cities.push({ slug: String(item.slug || ""), name: String(item.name || "") })
    }
    persistSettings({ cities: cities })
  }

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    // A different city has nothing in common with the reading on hand.
    if (snapshot && snapshot.slug !== city) {
      snapshot = null
      lastError = ""
      refresh()
    }
  }

  // ---------------------------------------------------------------- fetch

  readonly property string scriptPath: String(Qt.resolvedUrl("bin/yandex-weather.py")).replace(/^file:\/\//, "")

  function refresh() {
    if (fetchProcess.running) {
      refreshPending = true
      return
    }
    loading = true
    fetchProcess.command = ["python3", scriptPath, "weather", city]
    fetchProcess.running = true
  }

  // Off at refreshMinutes 0: the reading is then only taken when the panel
  // opens or the bar is clicked.
  Timer {
    interval: Math.max(1, root.refreshMinutes) * 60000
    running: root.refreshMinutes > 0
    repeat: true
    triggeredOnStart: false
    onTriggered: root.refresh()
  }

  // Keeps "updated N ago" honest without asking the site again.
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.clockTick++
  }

  Component.onCompleted: refresh()

  Process {
    id: fetchProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleOutput(text)
    }
    onExited: function(code) {
      root.loading = false
      root.clockTick++
      if (root.refreshPending) {
        root.refreshPending = false
        root.refresh()
      }
    }
  }

  function handleOutput(raw) {
    var text = String(raw || "").trim()
    var keep = function(code) { if (!root.snapshot) root.lastError = code }
    if (text === "") return keep("parse")

    var data
    try {
      data = JSON.parse(text)
    } catch (e) {
      return keep("parse")
    }
    if (!data || typeof data !== "object") return keep("parse")
    if (data.error) {
      // A failed refresh keeps the last good reading on the bar and says so
      // in the panel, rather than blanking a working forecast.
      root.lastError = String(data.error)
      return
    }
    root.snapshot = data
    root.lastError = ""
  }


  // ---------------------------------------------------------------- IPC
  //
  // A plugin widget is reached over the shell's IPC through Quickshell's own
  // handler; the shell's socket-backed ShellIpc is not available inside a
  // plugin loaded from its own folder. `omarchy-shell pole.yandex-weather
  // <method>` reaches these.
  IpcHandler {
    target: "pole.yandex-weather"

    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  // ---------------------------------------------------------------- bar

  visible: barText !== ""
  // Clear air on each side of the figure, so it stands apart from its
  // neighbours like every other label on the bar. The bar lays sections out by
  // this widget's width, so the gap is real space in the row. Set `outerGap` in
  // shell.json to change it.
  readonly property int outerGap: Math.max(0, Number(setting("outerGap", 10)) || 0)
  implicitWidth: button.implicitWidth + outerGap * 2
  implicitHeight: button.implicitHeight

  // Built with the bar so the first click opens at once; unmapped until then.
  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
      if (root.openWhenReady) {
        root.openWhenReady = false
        Qt.callLater(function() { root.open() })
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    anchors.margins: root.outerGap
    bar: root.bar
    // The figure alone: the bar gives a plugin label the width of plain text
    // and paints it from the start of that box, so a mark in front of it is
    // drawn over the widget to the left. The weather mark lives in the panel
    // and in the tooltip.
    text: root.current ? root.barText : ""
    hasVisualContent: root.current !== null
    horizontalMargin: 8.75
    verticalPadding: 8.75
    fontSize: Commons.Style.font.body
    tooltipText: root.barTooltip

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
    onWheelMoved: function(delta) {
      if (!panelLoader.item || typeof panelLoader.item.cycleCity !== "function") return
      // Wheeling up goes back in the shortlist, down forward.
      panelLoader.item.cycleCity(delta > 0 ? -1 : 1)
    }
  }

  // The mark's glyph, from WeatherIcons.js, for the label.
  readonly property string weatherMark: WeatherIcons.markFor(weatherKind, weatherNight)
}
