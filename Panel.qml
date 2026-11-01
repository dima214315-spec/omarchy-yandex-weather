import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import qs.Commons as Commons
import "WeatherData.js" as WeatherData

// The Яндекс Погода panel: today's reading at the top, the ten days under it,
// and the city shortlist beside them.
//
// The reading itself belongs to the bar widget (BarWidget.qml), which owns
// this item; the panel reads `host` and asks it to fetch or to change city, so
// a click on the bar icon and a click inside the panel always describe the
// same numbers.
Panel {
  id: root
  moduleName: "pole.yandex-weather"
  ipcTarget: "pole.yandex-weather"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var host: hostWidget

  // Strings come from the plugin's own catalogs, following the desktop
  // language like Omarchy's own panels do.
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // Which day the detail under the list describes, and where the keyboard
  // cursor is: "days", "cities" or "search".
  property int selectedDay: 0
  property string focusSection: "days"
  property int cityCursor: 0
  property int searchCursor: 0
  property var searchResults: []
  property bool searching: false
  property string searchError: ""
  // "Определить" is asking the network where this machine is.
  property bool locating: false
  property string locateError: ""

  readonly property var snapshot: host ? host.snapshot : null
  readonly property var current: snapshot && snapshot.current ? snapshot.current : null
  readonly property var days: snapshot && snapshot.days ? snapshot.days : []
  readonly property string lastError: host ? host.lastError : ""
  readonly property bool loading: host ? host.loading : false
  readonly property int clockTick: host ? host.clockTick : 0
  readonly property var myCities: host ? host.myCities : []
  readonly property var selected: days.length > selectedDay ? days[selectedDay] : null

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color faint: Qt.darker(foreground, 2.1)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The panel's type scale: every size the shell offers, raised once here, so
  // the whole card grows together instead of a stray label staying small. The
  // day titles come from Yandex in Russian and read fine in the theme's font
  // alias, which fontconfig already resolves with Cyrillic coverage.
  function text(px, scale) {
    return Math.round(px * (scale || 1.2))
  }

  readonly property int sizeCaption: text(Style.font.caption, 1.2)
  readonly property int sizeSmall: text(Style.font.bodySmall, 1.2)
  readonly property int sizeBody: text(Style.font.body, 1.2)
  readonly property int sizeSubtitle: text(Style.font.subtitle, 1.2)
  readonly property int sizeTitle: text(Style.font.title, 1.2)
  readonly property int sizeHeading: text(Style.font.heading, 1.2)
  readonly property int sizeIcon: text(Style.font.icon, 1.2)
  readonly property int sizeIconLarge: text(Style.font.iconLarge, 1.2)
  readonly property int sizeDisplay: text(Style.font.display, 1.15)

  // Enough room for the hero, all ten days and the four-part detail without
  // spilling off a short screen.
  readonly property int availableHeight: panel.availableCardHeight > 0
    ? Math.max(Style.space(220), panel.availableCardHeight - panel.padding * 2)
    : Style.space(470)

  function errorText(code) {
    var text = strings.t("error." + String(code || ""), "")
    return text !== "" ? text : strings.t("error.generic")
  }

  function partName(key) {
    return strings.t("panel.part." + key)
  }

  // The day whose detail opens first: the nearest one carrying a daytime
  // reading, which for a fresh forecast is today.
  function findDayIndex() {
    for (var i = 0; i < days.length; i++)
      if (days[i] && days[i].parts && days[i].parts.d) return i
    return days.length > 0 ? 0 : -1
  }

  property int openAttempts: 0

  function open() {
    // A panel opened on stale numbers is worse than a second of waiting; a
    // fresh one is only asked for again when the timer is off.
    if (host && (!host.snapshot || host.refreshMinutes === 0)) host.refresh()
    // The site answers in a couple of seconds; a card that morphs while
    // nothing is in it is worse than one that appears with the numbers, so a
    // first click waits for the reading.
    if (!host || host.snapshot) root.reveal()
    else {
      openAttempts = 0
      openWhenReady.start()
    }
  }

  Timer {
    id: openWhenReady
    interval: 120
    repeat: true
    onTriggered: {
      if (root.opened || !root.host) { stop(); return }
      // Once the reading lands, or after ten seconds so a failed fetch still
      // shows the panel and its Retry button.
      if (root.host.snapshot || root.openAttempts >= 80) {
        stop()
        root.reveal()
      }
      root.openAttempts++
    }
  }

  function reveal() {
    root.visible = true
    selectedDay = Math.max(0, findDayIndex())
    root.controller.show()
    root.setCenterHoverRevealSuppressed(true)
    Qt.callLater(function() {
      if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
    })
  }

  function close() {
    root.setCenterHoverRevealSuppressed(false)
    root.controller.hide()
    resetSearch()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(root, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was holding must
  // not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (bar && typeof bar.setCenterHoverRevealSuppressed === "function")
      bar.setCenterHoverRevealSuppressed(value)
  }

  // ------------------------------------------------------------- cities

  function cycleCity(step) {
    if (!host || myCities.length < 2) return
    var index = 0
    for (var i = 0; i < myCities.length; i++)
      if (String(myCities[i].slug || "") === host.city) index = i
    var next = (index + step + myCities.length) % myCities.length
    var city = myCities[next] || {}
    chooseCity(String(city.slug || ""), String(city.name || ""))
  }

  function chooseCity(slug, name) {
    if (!host) return
    host.setCity(slug, name)
    focusSection = "days"
    selectedDay = Math.max(0, findDayIndex())
    cityCursor = 0
  }

  // ------------------------------------------------------------- search

  function resetSearch() {
    // The field is what erases itself; the rest is the panel's own state.
    var content = panel.loadedContent
    if (content && content.searchField) content.searchField.text = ""
    searchResults = []
    searchError = ""
    searching = false
    if (searchProcess.running) searchProcess.running = false
    searchTimer.stop()
  }

  function scheduleSearch() {
    searchCursor = 0
    searchError = ""
    var query = currentSearchText().trim()
    if (query.length < 2) {
      searchResults = []
      searching = false
      searchTimer.stop()
      return
    }
    searchTimer.restart()
  }

  // What the search field holds, wherever the panel's content sits.
  function currentSearchText() {
    var content = panel.loadedContent
    return content && content.searchField ? String(content.searchField.text) : ""
  }

  function focusSearch() {
    var content = panel.loadedContent
    if (!content || !content.searchField) return
    focusSection = "search"
    content.searchField.forceActiveFocus()
    content.searchField.selectAll()
  }

  function focusDays() {
    var content = panel.loadedContent
    if (content && content.keyCatcher) content.keyCatcher.forceActiveFocus()
  }

  function runSearch() {
    var query = currentSearchText().trim()
    if (query.length < 2 || !host) return
    searching = true
    searchProcess.command = ["python3", host.scriptPath, "search", query]
    searchProcess.running = true
  }

  function handleSearchOutput(raw) {
    searching = false
    var text = String(raw || "").trim()
    var data
    try {
      data = JSON.parse(text)
    } catch (e) {
      searchResults = []
      searchError = strings.t("panel.searchFailed")
      return
    }
    if (!data || data.error) {
      searchResults = []
      searchError = errorText(data ? data.error : "parse")
      return
    }
    searchResults = Array.isArray(data.results) ? data.results : []
    searchCursor = 0
    searchError = searchResults.length === 0 ? strings.t("panel.nothingFound") : ""
  }

  function activateSearch() {
    if (searchCursor < 0 || searchCursor >= searchResults.length) {
      searchTimer.stop()
      runSearch()
      return
    }
    var result = searchResults[searchCursor]
    chooseCity(String(result.slug || ""), String(result.name || ""))
    resetSearch()
    focusDays()
  }

  // ------------------------------------------------------------- location

  // The place the network says this machine is in: IP geolocation gives the
  // coordinates, Yandex's own page for them gives the city and its slug, and
  // the place joins the shortlist like one picked by hand.
  function locate() {
    if (locating || !host) return
    locating = true
    locateError = ""
    locateProcess.command = ["python3", host.scriptPath, "locate"]
    locateProcess.running = true
  }

  function handleLocateOutput(raw) {
    locating = false
    var text = String(raw || "").trim()
    var data
    try {
      data = JSON.parse(text)
    } catch (e) {
      locateError = strings.t("panel.locateFailed")
      return
    }
    if (!data || data.error || !data.slug) {
      locateError = data && data.error === "geo"
        ? strings.t("panel.locateUnknown")
        : errorText(data ? data.error : "network")
      return
    }
    root.chooseCity(String(data.slug), String(data.name || ""))
  }

  Process {
    id: locateProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleLocateOutput(text)
    }
    onExited: root.locating = false
  }

  Timer {
    id: searchTimer
    interval: 450
    repeat: false
    onTriggered: root.runSearch()
  }

  Process {
    id: searchProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleSearchOutput(text)
    }
    onExited: root.searching = false
  }

  // ================================================================= page

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Math.max(Style.space(520), root.sizeSmall * 50))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: Item {
      id: contentRoot
      // The field and the key catcher, named so the panel's own functions can
      // reach the controls inside this content:
      property alias searchField: searchField
      property alias keyCatcher: keyCatcher
      // A plain Item, not the key catcher, as the panel's content on purpose:
      // a focusable key catcher in that slot would be given focus whenever the
      // panel maps and would claim every key inside it. It sits in the content
      // below and is handed the focus explicitly, after an edit or a click on
      // an empty spot, so typing in the search field stays typing.
      implicitHeight: contentColumn.implicitHeight

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Typing in the search field is the field's business.
      blocked: contentRoot.searchField.activeFocus

      onMoveRequested: function(dx, dy) {
        if (root.focusSection === "cities") {
          if (root.myCities.length === 0) return
          root.cityCursor = Math.max(0, Math.min(root.myCities.length - 1, root.cityCursor + dy))
          return
        }
        if (dx !== 0) {
          var next = root.selectedDay + dx
          if (next >= 0 && next < root.days.length) root.selectedDay = next
          return
        }
        if (root.days.length > 0)
          root.selectedDay = Math.max(0, Math.min(root.days.length - 1, root.selectedDay + dy))
      }

      onActivateRequested: {
        if (root.focusSection === "cities") {
          var city = root.myCities[root.cityCursor] || null
          if (city) root.chooseCity(String(city.slug || ""), String(city.name || ""))
          return
        }
        if (root.focusSection === "search") return root.activateSearch()
        // Enter on a day hands the cursor to the city chips, which is the one
        // thing a keyboard user usually wants next.
        root.focusSection = "cities"
        root.cityCursor = 0
      }

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text, modifiers) {
        if (text === "/" || text === "f" || text === "F") {
          root.focusSearch()
        } else if (text === "r" || text === "R") {
          if (root.host) root.host.refresh()
        } else if (text === "n" || text === "N") {
          if (root.focusSection === "cities")
            root.cityCursor = Math.min(root.myCities.length - 1, root.cityCursor + 1)
          else root.selectedDay = Math.min(root.days.length - 1, root.selectedDay + 1)
        } else if (text === "p" || text === "P") {
          if (root.focusSection === "cities")
            root.cityCursor = Math.max(0, root.cityCursor - 1)
          else root.selectedDay = Math.max(0, root.selectedDay - 1)
        } else if (text === "j" || text === "k") {
          // vi keys stay with the day list rather than the city chips.
          root.focusSection = "days"
        }
      }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: scroller.width
          spacing: Style.space(14)

          // ------------------------------------------------------- hero
          RowLayout {
            width: parent.width
            spacing: Style.space(16)

            WeatherIcon {
              // Always built, so the hero keeps its width before the first
              // reading lands; before that the day marks are blank too.
              // Centred rather than filled: the row lays out by implicit size.
              Layout.alignment: Qt.AlignVCenter
              Layout.preferredWidth: Style.space(56)
              Layout.preferredHeight: Style.space(56)
              size: Style.space(56)
              opacity: root.current !== null ? 1 : 0
              kind: root.current && root.current.kind ? String(root.current.kind) : "transparent"
              night: root.current ? root.current.night === true : false
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: root.snapshot ? String(root.snapshot.name || "") : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.sizeSubtitle
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.current ? WeatherData.formatTemp(root.current.temp) : (root.loading ? "…" : "—")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.sizeDisplay
                  font.bold: true
                }
              }

              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: {
                  if (root.current && root.current.condition) return String(root.current.condition)
                  if (root.loading) return strings.t("panel.loading")
                  return ""
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: root.sizeBody
                elide: Text.ElideRight
              }

              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: {
                  var clock = root.clockTick // rebuilds the line as time passes
                  if (!root.current) return ""
                  var bits = []
                  if (root.current.feels !== null && root.current.feels !== undefined)
                    bits.push(strings.t("panel.feels").arg(WeatherData.formatTemp(root.current.feels)))
                  if (root.current.wind !== null && root.current.wind !== undefined) {
                    var speed = WeatherData.formatNumber(root.current.wind)
                    if (root.current.windDir) speed += " " + root.current.windDir
                    bits.push(strings.t("panel.windSpeed").arg(speed))
                  }
                  if (root.current.humidity !== null && root.current.humidity !== undefined)
                    bits.push(strings.t("panel.humidity").arg(Commons.I18n.formatNumber(root.current.humidity)))
                  if (root.current.pressure !== null && root.current.pressure !== undefined)
                    bits.push(strings.t("panel.pressure").arg(Commons.I18n.formatNumber(root.current.pressure)))
                  return bits.join(" · ")
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: root.sizeSmall
                wrapMode: Text.WordWrap
              }
            }
          }

          // A failure is worth a line of its own, but only while there is no
          // reading to look at.
          BorderSurface {
            width: parent.width
            height: errorRow.implicitHeight + Style.space(12)
            radius: Style.cornerRadius
            color: Util.alpha(root.urgent, 0.12)
            borderSpec: Border.flat(root.urgent, Style.normalBorderWidth)
            visible: root.lastError !== "" && !root.current

            RowLayout {
              id: errorRow
              anchors.fill: parent
              anchors.margins: Style.space(6)
              spacing: Style.space(8)

              Text {
                text: "󰦕"
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: root.sizeIcon
              }

              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: root.errorText(root.lastError)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.sizeSmall
                wrapMode: Text.WordWrap
              }

              Button {
                text: strings.t("panel.retry")
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: if (root.host) root.host.refresh()
              }
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Util.alpha(root.foreground, 0.12)
          }

          // ------------------------------------------------------- cities
          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.myCities

              Rectangle {
                id: cityChip
                required property var modelData
                required property int index

                readonly property bool active: root.host && String(modelData.slug || "") === String(root.host.city)
                readonly property bool hot: cityMouse.containsMouse
                readonly property bool cursor: root.focusSection === "cities" && root.cityCursor === index

                width: cityLabel.implicitWidth + Style.space(20)
                height: Math.max(Style.spacing.controlHeight - Style.space(4), root.sizeSmall + Style.space(14))
                radius: Style.cornerRadius
                color: active || cursor
                  ? Util.alpha(root.accent, active ? 0.22 : 0.12)
                  : (hot ? Util.alpha(root.foreground, 0.08) : Util.alpha(root.foreground, 0.04))
                border.width: active || cursor ? Style.normalBorderWidth : 0
                border.color: Util.alpha(root.accent, 0.55)

                Behavior on color {
                  ColorAnimation { duration: Style.duration(140) }
                }

                Text {
                  id: cityLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: String(modelData.name || modelData.slug || "")
                  color: cityChip.active ? root.accent : (cityChip.hot || cityChip.cursor ? root.foreground : root.dim)
                  font.family: root.fontFamily
                  font.pixelSize: root.sizeSmall
                }

                MouseArea {
                  id: cityMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onClicked: function(mouse) {
                    var slug = String(cityChip.modelData.slug || "")
                    // Right click drops a city from the shortlist; the current
                    // one stays until another is chosen.
                    if (mouse.button === Qt.RightButton) {
                      if (root.host) root.host.removeCity(slug)
                    } else {
                      root.chooseCity(slug, String(cityChip.modelData.name || ""))
                    }
                  }
                }
              }
            }

            // Where this machine is, according to the network, as one click:
            // IP geolocation gives the coordinates, Yandex the city.
            Rectangle {
              id: locateChip
              width: locateLabel.implicitWidth + locateIcon.width + Style.space(22)
              height: Math.max(Style.spacing.controlHeight - Style.space(4), root.sizeSmall + Style.space(14))
              radius: Style.cornerRadius
              color: locateMouse.containsMouse || root.locating
                ? Util.alpha(root.accent, 0.14)
                : Util.alpha(root.foreground, 0.04)
              border.width: Style.normalBorderWidth
              border.color: Util.alpha(root.accent, 0.4)

              Row {
                anchors.centerIn: parent
                spacing: Style.space(6)

                Text {
                  id: locateIcon
                  textFormat: Text.PlainText
                  text: "\u2316"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: root.sizeSmall
                }

                Text {
                  id: locateLabel
                  textFormat: Text.PlainText
                  text: root.locating ? strings.t("panel.locating") : strings.t("panel.locate")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.sizeSmall
                }
              }

              MouseArea {
                id: locateMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.locate()
              }
            }
          }

          // A failed lookup says so under the chips rather than swallowing it.
          Text {
            width: parent.width
            visible: root.locateError !== ""
            textFormat: Text.PlainText
            text: root.locateError
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: root.sizeCaption
            wrapMode: Text.WordWrap
          }

          // The search field doubles as "add a city": type a name, pick a
          // match, and it becomes the current place and joins the chips.
          TextField {
            id: searchField
            width: parent.width
            height: Math.max(Style.spacing.controlHeight, root.sizeBody + Style.space(14))
            placeholderText: strings.t("panel.searchPlaceholder")
            foreground: root.foreground
            font.family: root.fontFamily
            onTextChanged: {
              root.focusSection = "search"
              root.scheduleSearch()
            }
            onActiveFocusChanged: if (activeFocus) root.focusSection = "search"
            Keys.onEscapePressed: {
              root.resetSearch()
              root.focusSection = "days"
              root.focusDays()
            }
            Keys.onDownPressed: function(event) {
              if (root.searchResults.length > 0)
                root.searchCursor = Math.min(root.searchResults.length - 1, root.searchCursor + 1)
              event.accepted = true
            }
            Keys.onUpPressed: function(event) {
              root.searchCursor = Math.max(0, root.searchCursor - 1)
              event.accepted = true
            }
            Keys.onReturnPressed: root.activateSearch()
            Keys.onEnterPressed: root.activateSearch()
          }

          // ------------------------------------------------------- results
          Column {
            width: parent.width
            spacing: Style.space(2)
            visible: root.focusSection === "search"
              && (root.searchResults.length > 0 || root.searchError !== "" || root.searching)

            Text {
              visible: root.searching
              textFormat: Text.PlainText
              text: strings.t("panel.searching")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: root.sizeSmall
            }

            Text {
              visible: !root.searching && root.searchError !== ""
              textFormat: Text.PlainText
              text: root.searchError
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: root.sizeSmall
            }

            Repeater {
              model: root.searchResults

              Rectangle {
                required property var modelData
                required property int index

                width: contentColumn.width
                height: Style.spacing.popupRowHeight
                radius: Style.cornerRadius
                color: root.searchCursor === index ? Util.alpha(root.foreground, 0.1) : "transparent"

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(90)
                  textFormat: Text.PlainText
                  text: String(modelData.name || "")
                  color: root.searchCursor === index ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: root.sizeSmall
                  elide: Text.ElideRight
                }

                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: String(modelData.temp || "")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: root.sizeSmall
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.searchCursor = index
                  onClicked: {
                    root.chooseCity(String(modelData.slug || ""), String(modelData.name || ""))
                    root.resetSearch()
                    root.focusDays()
                  }
                }
              }
            }
          }

          // ------------------------------------------------------- 10 days
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: strings.t("panel.daysHeading")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: root.sizeSubtitle
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              visible: text !== ""
              text: {
                var clock = root.clockTick
                          if (root.lastError !== "" && root.current) return strings.t("panel.stale")
                return ""
              }
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: root.sizeCaption
            }

            Text {
              textFormat: Text.PlainText
              text: "󰑐"
              color: refreshMouse.containsMouse ? root.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: root.sizeIcon

              MouseArea {
                id: refreshMouse
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.host) root.host.refresh()
              }
            }

            Text {
              textFormat: Text.PlainText
              text: WeatherData.fetchedAgo(root.snapshot ? root.snapshot.fetched : 0,
                                            Math.floor(Date.now() / 1000),
                                            strings.t("panel.updatedNow"),
                                            strings.t("panel.updatedMinutes"),
                                            strings.t("panel.updatedHours"))
              color: root.faint
              font.family: root.fontFamily
              font.pixelSize: root.sizeCaption
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.days

              Rectangle {
                id: dayRow
                required property var modelData
                required property int index

                readonly property var reading: WeatherData.representativePart(modelData)
                readonly property var range: WeatherData.dayRange(modelData)
                readonly property var title: WeatherData.splitTitle(modelData.title)
                readonly property bool selected: root.selectedDay === index
                readonly property bool hot: dayMouse.containsMouse

                width: contentColumn.width
                height: Math.max(Style.space(34), root.sizeSmall + Style.space(20))
                radius: Style.cornerRadius
                color: selected
                  ? Util.alpha(root.accent, 0.18)
                  : (hot ? Util.alpha(root.foreground, 0.07) : "transparent")
                border.width: selected ? Style.normalBorderWidth : 0
                border.color: Util.alpha(root.accent, 0.5)

                Behavior on color {
                  ColorAnimation { duration: Style.duration(120) }
                }

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(10)

                  // "Сегодня, 1 ноября" — the weekday leads, the date follows.
                  Text {
                    textFormat: Text.PlainText
                    text: dayRow.title.rest !== ""
                      ? dayRow.title.lead + ", " + dayRow.title.rest
                      : dayRow.title.lead
                    color: dayRow.selected || dayRow.hot ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.sizeSmall
                    elide: Text.ElideRight
                    Layout.preferredWidth: Math.max(Style.space(150), root.sizeSmall * 16)
                  }

                  WeatherIcon {
                    size: Style.space(24)
                    // A fixed width keeps every row's text starting in the
                    // same place, icon or not.
                    Layout.preferredWidth: Style.space(24)
                    Layout.preferredHeight: Style.space(24)
                    Layout.alignment: Qt.AlignVCenter
                    opacity: dayRow.reading !== null ? 1 : 0
                    kind: dayRow.reading && dayRow.reading.kind ? String(dayRow.reading.kind) : "transparent"
                    night: dayRow.reading ? dayRow.reading.night === true : false
                    dimmed: !dayRow.selected && !dayRow.hot
                  }

                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: dayRow.reading ? String(dayRow.reading.condition || "") : ""
                    color: Qt.darker(root.foreground, 1.25)
                    font.family: root.fontFamily
                    font.pixelSize: root.sizeSmall
                    elide: Text.ElideRight
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: dayRow.range.high !== null
                      ? WeatherData.formatTemp(dayRow.range.high) + "  " + WeatherData.formatTemp(dayRow.range.low)
                      : ""
                    color: dayRow.selected ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.sizeSmall
                    Layout.preferredWidth: Math.max(Style.space(70), root.sizeSmall * 6)
                    horizontalAlignment: Text.AlignRight
                  }
                }

                MouseArea {
                  id: dayMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectedDay = dayRow.index
                }
              }
            }
          }

          // ------------------------------------------------------- detail
          Rectangle {
            width: parent.width
            height: 1
            color: Util.alpha(root.foreground, 0.12)
            visible: root.selected !== null
          }

          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.selected !== null

            Text {
              textFormat: Text.PlainText
              text: {
                var title = root.selected ? WeatherData.splitTitle(root.selected.title) : { lead: "", rest: "" }
                return title.rest !== "" ? title.lead + ", " + title.rest : title.lead
              }
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: root.sizeBody
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: ["m", "d", "e", "n"]

                ColumnLayout {
                  id: partColumn
                  required property string modelData
                  Layout.fillWidth: true
                  spacing: Style.space(3)

                  readonly property var part: root.selected && root.selected.parts
                    ? root.selected.parts[modelData] || null : null

                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: root.partName(partColumn.modelData)
                    color: root.faint
                    font.family: root.fontFamily
                    font.pixelSize: root.sizeCaption
                    horizontalAlignment: Text.AlignHCenter
                  }

                  WeatherIcon {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Style.space(34)
                    Layout.preferredHeight: Style.space(34)
                    size: Style.space(34)
                    opacity: partColumn.part !== null ? 1 : 0
                    kind: partColumn.part && partColumn.part.kind ? String(partColumn.part.kind) : "transparent"
                    night: partColumn.part ? partColumn.part.night === true : false
                  }

                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: partColumn.part ? WeatherData.formatTemp(partColumn.part.temp) : "—"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: root.sizeSubtitle
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                  }

                  // Two lines are reserved for the condition, so a long phrase
                  // does not push the wind figure off the row below it.
                  Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(conditionText.font.pixelSize * 2.4)

                    Text {
                      id: conditionText
                      anchors.fill: parent
                      textFormat: Text.PlainText
                      text: partColumn.part ? String(partColumn.part.condition || "") : ""
                      color: Qt.darker(root.foreground, 1.3)
                      font.family: root.fontFamily
                      font.pixelSize: root.sizeCaption
                      horizontalAlignment: Text.AlignHCenter
                      wrapMode: Text.WordWrap
                      maximumLineCount: 2
                      elide: Text.ElideRight
                    }
                  }

                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: {
                      var part = partColumn.part
                      if (!part) return ""
                      var bits = []
                      if (part.wind) {
                        // The page's own cell already carries the unit.
                        var wind = String(part.wind)
                        if (part.windDir) wind += " " + part.windDir
                        bits.push(wind)
                      }
                      if (part.humidity !== null && part.humidity !== undefined)
                        bits.push(Commons.I18n.formatNumber(part.humidity) + "%")
                      return bits.join("\n")
                    }
                    color: root.faint
                    font.family: root.fontFamily
                    font.pixelSize: root.sizeCaption
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                  }
                }
              }
            }
          }

          // ------------------------------------------------------- footer
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.lastError !== "" && root.current
              ? strings.t("panel.staleData").arg(root.errorText(root.lastError))
              : strings.t("panel.source")
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: root.sizeCaption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }
  }
}
