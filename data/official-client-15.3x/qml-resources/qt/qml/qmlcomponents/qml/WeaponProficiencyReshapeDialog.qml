import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

import qmlcomponents

TibiaDialog {
  id: root

  caption: qsTrId("weapon_proficiency_reshape_dialog_caption")
  width: 874

  initialFocusItem: root
  KeyNavigation.tab: root
  KeyNavigation.backtab: root

  required property var controller

  readonly property int perkCardWidth: 200

  ColumnLayout {
    id: mainLayout
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: TibiaStyle.marginUnrelated

    RowLayout {
      id: cardRowLayout
      spacing: TibiaStyle.marginUnrelated

      ColumnLayout {
        spacing: TibiaStyle.marginRelated

        TibiaFrame2PixelUpFilled {
          Layout.fillWidth: true
          Layout.preferredHeight: selectInfoText.height + 2*marginsToContent

          TibiaText {
            anchors { left: parent.left; top: parent.top; right: parent.right }
            anchors.margins: parent.marginsToContent

            horizontalAlignment: Text.AlignHCenter
            text: qsTrId("weapon_proficiency_reshape_current_perk")
          } //TibiaText
        } //TibiaFrame2PixelUpFilled


        WeaponProficiencyPerkCard {
          Layout.preferredWidth: root.perkCardWidth
          isActive: true
          perkName: controller.currentPerk.perkName
          perkDescription: controller.currentPerk.perkDescription
          isShaped: true
          imageSource: controller.currentPerk.imageSource
          hasAugmentEffect: controller.currentPerk.hasAugmentEffect
          perkRank: controller.currentPerk.perkRank
          augmentEffectImageSource: controller.currentPerk.augmentEffectImageSource
        } //WeaponProficiencyPerkCard
        TibiaButton {
          Layout.preferredWidth: root.perkCardWidth / 2
          Layout.preferredHeight: TibiaStyle.buttonHeightHigh
          Layout.alignment: Qt.AlignHCenter

          text: qsTrId("weapon_proficiency_reshape_keep_button")
          textFont: TibiaStyle.defaultTextFont
          onClicked: controller.requestCancel()
        } //TibiaButton
      } //ColumnLayout

      TibiaVerticalSeparator {
        Layout.fillHeight: true
      } // TibiaHorizontalSeparator

      ColumnLayout {
        id: newPerksLayout
        spacing: TibiaStyle.marginRelated

        TibiaFrame2PixelUpFilled {
          Layout.fillWidth: true
          Layout.preferredHeight: selectInfoText.height + 2*marginsToContent

          TibiaText {
            id: selectInfoText
            anchors { left: parent.left; top: parent.top; right: parent.right }
            anchors.margins: parent.marginsToContent

            horizontalAlignment: Text.AlignHCenter
            text: qsTrId("weapon_proficiency_reshape_dialog_hint")
          } //TibiaText
        } //TibiaFrame2PixelUpFilled

        RowLayout {
          spacing: TibiaStyle.marginUnrelated

          Repeater {
            model: root.controller.perkOffersModel
            ColumnLayout {
              WeaponProficiencyPerkCard {
                id: weaponProficiencyCard
                Layout.preferredWidth: root.perkCardWidth
                isActive: true
                perkName: modelData.perkName
                perkDescription: modelData.perkDescription
                isShaped: true
                imageSource: modelData.imageSource
                hasAugmentEffect: modelData.hasAugmentEffect
                perkRank: modelData.perkRank
                augmentEffectImageSource: modelData.augmentEffectImageSource
              } //WeaponProficiencyPerkCard

              TibiaButton {
                Layout.preferredWidth: root.perkCardWidth / 2
                Layout.preferredHeight: TibiaStyle.buttonHeightHigh
                Layout.alignment: Qt.AlignHCenter

                text: qsTrId("weapon_proficiency_reshape_replace_button")
                textFont: TibiaStyle.defaultTextFont
                onClicked: {
                  controller.replacePerkSelected(index);
                } //onClicked

                TibiaRectangleHighlight {}
              } //TibiaButton
            } //ColumnLayout
          } //Repeater
        } //RowLayout
      } //ColumnLayout
    } //RowLayout

    Item {
      id: highlightVisibleEnabler
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      Layout.topMargin: -2*parent.spacing
    } //Item
  } // ColumnLayout
} // TibiaDialog
