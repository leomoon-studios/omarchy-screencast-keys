import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  required property var entries
  property string position: "bottom-right"
  property real scaleFactor: 1.0
  property double nowMs: Date.now()

  readonly property bool topPlacement: position.indexOf("top-") === 0
  readonly property bool leftPlacement: position.indexOf("-left") !== -1
  readonly property real stackSpacing: Style.spaceReal(8) * scaleFactor
  readonly property real chordSpacing: Style.spaceReal(7) * scaleFactor
  readonly property real keycapPadding: Style.spaceReal(22) * scaleFactor
  readonly property real labelWidthCap: Style.spaceReal(240) * scaleFactor
  readonly property real fadeDuration: 350
  clip: true

  ListView {
    id: stack
    anchors.fill: parent
    spacing: root.stackSpacing
    interactive: false
    clip: true
    model: root.entries
    verticalLayoutDirection: root.topPlacement ? ListView.TopToBottom : ListView.BottomToTop

    add: Transition {
      NumberAnimation { properties: "opacity"; from: 0; to: 1; duration: 150; easing.type: Easing.OutCubic }
    }
    remove: Transition {
      NumberAnimation { properties: "opacity"; to: 0; duration: 160; easing.type: Easing.OutCubic }
    }
    displaced: Transition {
      NumberAnimation { properties: "y"; duration: 150; easing.type: Easing.OutCubic }
    }

    delegate: Item {
      id: keyRowSlot
      required property string keyText
      required property double expiresAt
      readonly property var labels: keyText.split("\u001f")
      readonly property real fittedLabelWidth: Math.max(
        Style.spaceReal(24) * root.scaleFactor,
        (stack.width - labels.length * root.keycapPadding
          - Math.max(0, labels.length - 1)
            * (root.chordSpacing * 2 + Style.font.subtitle * root.scaleFactor))
          / Math.max(1, labels.length))
      readonly property real maximumLabelWidth: Math.min(
        root.labelWidthCap, fittedLabelWidth)

      width: stack.width
      height: keyRow.implicitHeight
      readonly property real remaining: Math.max(0, expiresAt - root.nowMs)
      opacity: remaining >= root.fadeDuration ? 1 : remaining / root.fadeDuration

      Row {
        id: keyRow
        anchors.left: root.leftPlacement ? parent.left : undefined
        anchors.right: root.leftPlacement ? undefined : parent.right
        spacing: root.chordSpacing

        Repeater {
          model: keyRowSlot.labels

          Row {
            required property int index
            required property string modelData
            spacing: root.chordSpacing

            BorderSurface {
              id: keycap
              width: keyLabel.width + root.keycapPadding
              height: keyLabel.implicitHeight + Style.spaceReal(14) * root.scaleFactor
              radius: Math.max(3, Style.cornerRadius * root.scaleFactor)
              color: Util.alpha(Color.popups.background, 0.96)
              borderSpec: Border.flat(Color.popups.border, Math.max(1, Style.spaceReal(1) * root.scaleFactor))

              Text {
                id: keyLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: modelData
                width: Math.min(implicitWidth, keyRowSlot.maximumLabelWidth)
                elide: Text.ElideRight
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle * root.scaleFactor
                font.bold: true
                renderType: Text.NativeRendering
              }
            }

            Text {
              visible: index < keyRowSlot.labels.length - 1
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "+"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle * root.scaleFactor
              font.bold: true
            }
          }
        }
      }
    }
  }
}
