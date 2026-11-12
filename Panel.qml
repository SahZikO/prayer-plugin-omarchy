import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "prayer-times"
  ipcTarget: "prayer-times"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string methodSetting: String(setting("method", "Auto"))
  readonly property string asrSetting: String(setting("asr", "Standard"))
  readonly property bool use12h: setting("timeFormat", "24h") === "12h"
  readonly property bool notifyEnabled: setting("notify", true) === true
  readonly property var extraOffsets: ({
    fajr: parseInt(setting("fajrOffset", 0), 10) || 0,
    dhuhr: parseInt(setting("dhuhrOffset", 0), 10) || 0,
    asr: parseInt(setting("asrOffset", 0), 10) || 0,
    maghrib: parseInt(setting("maghribOffset", 0), 10) || 0,
    isha: parseInt(setting("ishaOffset", 0), 10) || 0
  })

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/prayer-times"
  readonly property string locatorPath: decodeURIComponent(Qt.resolvedUrl("bin/prayer-locate").toString().replace(/^file:\/\//, ""))

  property string mode: "auto"
  property var manualLocation: null
  property var detectedLocation: null
  property bool locating: false
  property bool locateFailed: false
  readonly property var location: mode === "manual" && manualLocation ? manualLocation : detectedLocation

  property real nowMs: Date.now()
  property int zoneOffset: 0
  property var cityDate: null
  property bool zoneReady: false

  readonly property string methodKey: Model.resolveMethodKey(methodSetting, location ? location.country : "")
  readonly property string methodName: Model.METHODS[methodKey] ? Model.METHODS[methodKey].name : methodKey

  readonly property var today: computeDay(0)
  readonly property var tomorrow: computeDay(1)
  readonly property var next: today.length ? Model.nextPrayer(today, tomorrow.length ? tomorrow[0] : null, nowMs) : null
  readonly property int currentIdx: today.length ? Model.currentIndex(today, nowMs) : -1

  readonly property string barLabel: next ? (Model.NAMES[next.key].en + " " + Model.formatClock(next.epoch, zoneOffset, use12h)) : ""
  readonly property string tooltip: {
    if (!location) return locating ? "Prayer times: locating…" : "Prayer times: set a city"
    if (!next) return "Prayer times — " + location.name
    return Model.NAMES[next.key].en + " at " + Model.formatClock(next.epoch, zoneOffset, use12h)
      + " (in " + Model.formatCountdown(next.epoch - nowMs) + ") — " + location.name
  }

  function computeDay(plusDays) {
    if (!location || !cityDate || !zoneReady) return []
    var d = new Date(Date.UTC(cityDate.year, cityDate.month - 1, cityDate.day + plusDays))
    return Model.schedule({
      year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate(),
      latitude: location.latitude, longitude: location.longitude, elevation: location.elevation,
      methodKey: methodKey, asr: asrSetting, extraOffsets: extraOffsets
    })
  }

  function dateLabel() {
    if (!cityDate) return ""
    var d = new Date(cityDate.year, cityDate.month - 1, cityDate.day)
    return d.toLocaleDateString(Qt.locale(Commons.I18n.formatLocale), "dddd d MMMM yyyy")
  }

  function sourceLabel() {
    if (mode === "manual") return "Manual"
    if (!location) return ""
    return location.source === "gps" ? "GPS" : "Network"
  }

  function open() { root.controller.show(); tick() }
  function openFromHotkey() { root.controller.show(); tick() }
  function close() {
    if (editing) cancelEditing()
    root.controller.hide()
  }
  function toggle() { if (root.opened) root.close(); else root.openFromHotkey() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  readonly property string wantedZone: location && location.timezone ? location.timezone : ""
  property string queriedZone: ""

  function tick() {
    nowMs = Date.now()
    if (zoneProc.running) return
    queriedZone = wantedZone
    zoneProc.environment = queriedZone !== "" ? ({ TZ: queriedZone }) : ({})
    zoneProc.running = true
  }

  onWantedZoneChanged: {
    zoneReady = false
    tick()
  }

  function relocate() {
    if (mode !== "auto") return
    if (locateProc.running) return
    locating = true
    locateProc.running = true
  }

  FileView {
    id: stateFile
    path: root.stateDir + "/location.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyState(Model.parseState(text()))
    onLoadFailed: root.applyState({ mode: "auto", location: null })
  }

  function applyState(state) {
    var newMode = state.mode === "manual" && state.location ? "manual" : "auto"
    manualLocation = state.location
    if (newMode !== mode) {
      mode = newMode
      zoneReady = false
    }
    if (mode === "auto" && !detectedLocation) relocate()
    tick()
  }

  function saveState(newMode, loc) {
    mkdirProc.running = true
    stateFile.setText(JSON.stringify({ mode: newMode, location: loc }, null, 2) + "\n")
    applyState({ mode: newMode, location: loc })
  }

  function useManual(loc) {
    if (!loc) return
    zoneReady = false
    saveState("manual", loc)
    cancelEditing()
  }

  function useAuto() {
    saveState("auto", null)
    cancelEditing()
    relocate()
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.stateDir]
  }

  Process {
    id: locateProc
    command: [root.locatorPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.locating = false
        var loc = null
        try { loc = Model.normaliseLocation(JSON.parse(String(text || "").slice(0, 4096))) } catch (e) { loc = null }
        if (loc) {
          root.locateFailed = false
          var moved = !root.detectedLocation || root.detectedLocation.timezone !== loc.timezone
          root.detectedLocation = loc
          if (moved) root.zoneReady = false
          root.tick()
        } else {
          root.locateFailed = !root.detectedLocation
        }
      }
    }
  }

  Process {
    id: zoneProc
    command: ["date", "+%Y %m %d %z"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.queriedZone !== root.wantedZone) return
        var parts = String(text || "").trim().split(" ")
        var off = Model.parseOffset(parts[3])
        if (parts.length < 4 || off === null) return
        var d = { year: parseInt(parts[0], 10), month: parseInt(parts[1], 10), day: parseInt(parts[2], 10) }
        if (!root.cityDate || root.cityDate.year !== d.year || root.cityDate.month !== d.month || root.cityDate.day !== d.day)
          root.cityDate = d
        if (root.zoneOffset !== off) root.zoneOffset = off
        root.zoneReady = true
      }
    }
    onExited: if (root.queriedZone !== root.wantedZone) Qt.callLater(root.tick)
  }

  onLocationChanged: tick()

  Timer {
    interval: 20000
    running: true
    repeat: true
    onTriggered: {
      root.tick()
      root.checkNotify()
    }
  }

  Timer {
    interval: 30 * 60 * 1000
    running: root.mode === "auto"
    repeat: true
    onTriggered: root.relocate()
  }

  property real lastNotified: 0
  function checkNotify() {
    if (!notifyEnabled || !location) return
    for (var i = 0; i < today.length; i++) {
      var p = today[i]
      if (p.key === "sunrise" || isNaN(p.epoch)) continue
      if (nowMs >= p.epoch && nowMs - p.epoch < 120000 && p.epoch > lastNotified) {
        lastNotified = p.epoch
        notifyProc.command = ["notify-send", "-a", "Prayer Times", "-i", "appointment-soon",
          "It's time for " + Model.NAMES[p.key].en + " · " + Model.NAMES[p.key].ar,
          Model.formatClock(p.epoch, zoneOffset, use12h) + " — " + location.name]
        notifyProc.running = true
      }
    }
  }
  Component.onCompleted: lastNotified = Date.now()

  Process { id: notifyProc }

  property bool editing: false
  property var suggestions: []
  property int suggestionIndex: 0
  property string geocodePending: ""
  property string geocodeActive: ""

  function searchField() { return panel.loadedContent ? panel.loadedContent.searchField : null }

  function startEditing() {
    editing = true
    suggestions = []
    suggestionIndex = 0
    Qt.callLater(function() {
      var f = root.searchField()
      if (!f) return
      f.text = ""
      f.forceActiveFocus()
    })
  }

  function cancelEditing() {
    editing = false
    suggestions = []
    geocodeDebounce.stop()
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }

  function requestGeocode() {
    var f = searchField()
    var q = f ? f.text.trim() : ""
    if (q.length < 2) { suggestions = []; return }
    geocodePending = q.slice(0, 80)
    if (!geocodeProc.running) startGeocode()
  }

  function startGeocode() {
    geocodeActive = geocodePending
    geocodeProc.command = ["curl", "-fsS", "--max-time", "6", "--max-filesize", "200000",
      "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(geocodeActive) + "&count=6&language=en&format=json"]
    geocodeProc.running = true
  }

  Process {
    id: geocodeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.suggestions = root.editing ? Model.parseGeocodingResults(String(text || "").slice(0, 200000)) : []
        root.suggestionIndex = 0
        if (root.geocodePending !== root.geocodeActive) Qt.callLater(root.startGeocode)
      }
    }
  }

  Timer {
    id: geocodeDebounce
    interval: 300
    onTriggered: root.requestGeocode()
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function relocate(): void { root.useAuto() }
    function edit(): void { root.openFromHotkey(); root.startEditing() }
    function next(): string { return root.tooltip }
  }

  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.5)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias searchField: searchField
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      blocked: root.editing
      onReturnRequested: root.startEditing()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        Item {
          width: parent.width
          height: header.implicitHeight

          Column {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(4)

            Row {
              visible: !root.editing
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: "\u{F1827}"
                color: Commons.Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Row {
                  spacing: Style.space(6)
                  TapHandler { onTapped: root.startEditing() }
                  HoverHandler { cursorShape: Qt.PointingHandCursor }

                  Text {
                    textFormat: Text.PlainText
                    text: root.location ? (root.location.name || "Current location")
                      : (root.locating ? "Locating…" : "Choose a city")
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: "\u{F03EB}"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: [root.sourceLabel(), root.dateLabel()].filter(function(s) { return s !== "" }).join(" · ")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            Row {
              visible: root.editing
              spacing: Style.space(6)

              TextField {
                id: searchField
                width: Style.space(270)
                placeholderText: "Search a city…"
                foreground: root.fg
                font.family: root.fontFamily
                onTextChanged: if (root.editing) geocodeDebounce.restart()

                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.cancelEditing(); event.accepted = true
                  } else if (event.key === Qt.Key_Down) {
                    if (root.suggestionIndex < root.suggestions.length - 1) root.suggestionIndex++
                    event.accepted = true
                  } else if (event.key === Qt.Key_Up) {
                    if (root.suggestionIndex > 0) root.suggestionIndex--
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.suggestions.length > 0) root.useManual(root.suggestions[root.suggestionIndex])
                    event.accepted = true
                  }
                }
              }

              PillButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "\u{F01A4}  Auto"
                onClicked: root.useAuto()
              }
            }
          }
        }

        Column {
          visible: root.editing && root.suggestions.length > 0
          width: parent.width

          Repeater {
            model: root.suggestions

            Rectangle {
              required property var modelData
              required property int index
              width: parent.width
              height: sugRow.implicitHeight + Style.space(12)
              radius: Style.cornerRadius
              color: index === root.suggestionIndex ? Style.hoverFillFor(root.fg, Commons.Color.accent) : "transparent"

              Row {
                id: sugRow
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)
                Text {
                  textFormat: Text.PlainText
                  text: modelData.name
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  textFormat: Text.PlainText
                  text: modelData.region
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: root.suggestionIndex = index
                onClicked: root.useManual(modelData)
              }
            }
          }
        }

        Text {
          visible: root.editing && root.suggestions.length === 0
          x: Style.space(12)
          textFormat: Text.PlainText
          text: "Type a city name, or pick Auto to use this laptop's location."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }

        Rectangle {
          visible: !root.editing && !!root.next
          width: parent.width
          height: hero.implicitHeight + Style.space(20)
          radius: Style.cornerRadius
          color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.12)

          Column {
            id: hero
            anchors.centerIn: parent
            spacing: Style.space(2)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: "NEXT PRAYER"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1.5
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: root.next ? Model.NAMES[root.next.key].en + "  ·  " + Model.NAMES[root.next.key].ar : ""
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: root.next ? Model.formatClock(root.next.epoch, root.zoneOffset, root.use12h)
                + "  —  in " + Model.formatCountdown(root.next.epoch - root.nowMs) : ""
              color: Commons.Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        Column {
          visible: !root.editing && root.today.length > 0
          width: parent.width
          spacing: Style.space(2)

          Repeater {
            model: root.today

            Rectangle {
              required property var modelData
              required property int index
              readonly property bool isNext: root.next && root.next.epoch === modelData.epoch
              readonly property bool passed: !isNaN(modelData.epoch) && modelData.epoch <= root.nowMs && !isNext
              readonly property bool isSunrise: modelData.key === "sunrise"

              width: parent.width
              height: Style.space(34)
              radius: Style.cornerRadius
              color: isNext ? Style.hoverFillFor(root.fg, Commons.Color.accent) : "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: Model.NAMES[modelData.key].en
                color: isNext ? Commons.Color.accent : (passed || isSunrise ? root.dim : root.fg)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: isNext
                font.italic: isSunrise
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: Model.NAMES[modelData.key].ar
                color: root.dim
                font.pixelSize: Style.font.body
              }

              Text {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: Model.formatClock(modelData.epoch, root.zoneOffset, root.use12h)
                color: isNext ? Commons.Color.accent : (passed || isSunrise ? root.dim : root.fg)
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: isNext
              }
            }
          }
        }

        Text {
          visible: !root.editing && root.today.length === 0
          x: Style.space(12)
          width: parent.width - Style.space(24)
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.locating ? "Finding your location…"
            : (root.locateFailed && !root.location ? "Couldn't detect your location. Click the city name above to pick one." : "Calculating…")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }

        Rectangle {
          visible: !root.editing
          width: parent.width
          height: Style.spacing.hairline
          color: root.fg
          opacity: 0.12
        }

        Item {
          visible: !root.editing
          width: parent.width
          height: footerRow.implicitHeight

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.right: footerRow.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.methodName + (root.asrSetting === "Hanafi" ? " · Hanafi Asr" : "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            id: footerRow
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(6)

            PillButton {
              visible: root.mode === "manual"
              label: "\u{F01A4}  Use my location"
              onClicked: root.useAuto()
            }
            PillButton {
              visible: root.mode === "auto"
              label: root.locating ? "\u{F0450}  Locating…" : "\u{F0450}  Refresh"
              onClicked: root.relocate()
            }
            PillButton {
              label: "\u{F0349}  City"
              onClicked: root.startEditing()
            }
          }
        }
      }
    }
  }

  component PillButton: Rectangle {
    id: pill
    property string label: ""
    signal clicked()
    implicitWidth: pillText.implicitWidth + Style.space(16)
    implicitHeight: pillText.implicitHeight + Style.space(8)
    width: implicitWidth
    height: implicitHeight
    radius: Style.cornerRadius
    color: pillArea.containsMouse ? Style.hoverFillFor(root.fg, Commons.Color.accent) : "transparent"
    border.width: 1
    border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.2)

    Text {
      id: pillText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: pill.label
      color: pillArea.containsMouse ? Style.hoverStateColor(root.fg, Commons.Color.accent) : root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      id: pillArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.clicked()
    }
  }
}
