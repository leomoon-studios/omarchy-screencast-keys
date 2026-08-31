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
  readonly property real outerMargin: Style.spaceReal(42) * scaleFactor
  readonly property real stackSpacing: Style.spaceReal(8) * scaleFactor
  readonly property real fadeDuration: 350

  ListView {
    id: stack
    width: parent.width
    height: Math.min(contentHeight, Math.max(0, parent.height - root.outerMargin * 2))
    anchors.top: root.topPlacement ? parent.top : undefined
    anchors.bottom: root.topPlacement ? undefined : parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: root.topPlacement ? root.outerMargin : 0
    anchors.bottomMargin: root.topPlacement ? 0 : root.outerMargin
    spacing: root.stackSpacing
    interactive: false
    clip: false
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
      required property var keys
      required property double expiresAt

      width: stack.width
      height: keyRow.implicitHeight
      readonly property real remaining: Math.max(0, expiresAt - root.nowMs)
      opacity: remaining >= root.fadeDuration ? 1 : remaining / root.fadeDuration

      Row {
        id: keyRow
        anchors.left: root.leftPlacement ? parent.left : undefined
        anchors.right: root.leftPlacement ? undefined : parent.right
        anchors.leftMargin: root.leftPlacement ? root.outerMargin : 0
        anchors.rightMargin: root.leftPlacement ? 0 : root.outerMargin
        spacing: Style.spaceReal(7) * root.scaleFactor

        Repeater {
          model: keyRowSlot.keys

          Row {
            required property int index
            required property string modelData
            spacing: Style.spaceReal(7) * root.scaleFactor

            BorderSurface {
              id: keycap
              width: keyLabel.implicitWidth + Style.spaceReal(22) * root.scaleFactor
              height: keyLabel.implicitHeight + Style.spaceReal(14) * root.scaleFactor
              radius: Math.max(3, Style.cornerRadius * root.scaleFactor)
              color: Util.alpha(Color.popups.background, 0.96)
              borderSpec: Border.flat(Color.popups.border, Math.max(1, Style.spaceReal(1) * root.scaleFactor))

              Text {
                id: keyLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: modelData
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle * root.scaleFactor
                font.bold: true
                renderType: Text.NativeRendering
              }
            }

            Text {
              visible: index < keyRowSlot.keys.length - 1
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
