import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "prayer-times"

  readonly property var panel: panelLoader.item
  readonly property bool opened: panel ? panel.opened === true : false
  readonly property bool popoutSwitchClosing: panel ? panel.popoutSwitchClosing === true : false
  readonly property bool showNext: setting("showNextPrayer", false) === true && !vertical

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() { if (panel) panel.openFromHotkey() }
  function close() { if (panel) panel.close() }
  function togglePanel() { if (panel) panel.toggle() }
  function closeForPopoutSwitch() { if (panel) panel.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  TextMetrics {
    id: labelMetrics
    text: button.labelText
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u{F1827}"
    labelText: root.showNext && root.panel ? root.panel.barLabel : ""
    fixedWidth: root.vertical ? -1
      : (labelText !== "" ? Math.round(labelMetrics.advanceWidth + canvasSize + Style.space(4) + Style.space(14)) : slotSize)
    tooltipText: root.opened || !root.panel ? "" : root.panel.tooltip

    onPressed: function(b) {
      if (!root.panel) return
      if (b === Qt.MiddleButton) root.panel.relocate()
      else root.togglePanel()
    }
  }
}
