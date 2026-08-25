import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

TibiaDialog {
  id: enterTextDialog

  caption: qsTrId("request_login_confirmation_caption")
  width: Math.ceil(Math.max(360, captionContentWidth + 2*TibiaStyle.dialogMarginBorder))

  onWidthChanged: {
    enterTextDialog.centerDialog();
  } //onWidthChanged


  property QtObject controller: null
  property alias maxInputLength: enteredTextField.maximumLength
  property alias enteredText: enteredTextField.text

  function sendEnteredText() {
    if(null != controller) {
      controller.onOkClicked(enteredTextField.text);
    }
  } //function sendEnteredText()

  function requestConfirmationCode() {
    if(null != controller) {
      controller.onSendClicked();
    }
  } //function requestConfirmationCode()


  onReturnPressedFunction: sendEnteredText
  onCancelPressedFunction: controller != null ? controller.onCancelClicked : null
  initialFocusItem: primaryEmailButton

  ColumnLayout {
    anchors { left: parent.left; right: parent.right; top: parent.top }
    spacing: TibiaStyle.marginUnrelated

      TibiaText {
        id: descriptionText
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTrId("request_login_confirmation_text")
        styleType: "Dialog"
      } //TibiaText

      ColumnLayout {
        spacing: TibiaStyle.marginUnrelated

      TibiaFrame1PixelDown {
        Layout.fillWidth: true
        Layout.preferredHeight: infoLayout2.height

        RowLayout {
          id: infoLayout2
          anchors { left: parent.left; right: parent.right; top: parent.top;
                    leftMargin: TibiaStyle.marginUnrelated; rightMargin: TibiaStyle.marginUnrelated }
          spacing: TibiaStyle.marginRelated
          
          ColumnLayout {
            spacing: TibiaStyle.marginRelated
            Layout.alignment: Qt.AlignHCenter

            TibiaText {
              text: "Primary Email"
              Layout.alignment: Qt.AlignHCenter
              Layout.topMargin: TibiaStyle.marginUnrelated
            } // TibiaText

            TibiaText {
              text: controller.availableMethods.primaryEmail != ""
                ? controller.availableMethods.primaryEmail
                : qsTrId("confirmation_method_missing")
              Layout.alignment: Qt.AlignHCenter
              Layout.bottomMargin: TibiaStyle.marginUnrelated
            } // TibiaText
          } // ColumnLayout

          TibiaButton {
            id: primaryEmailButton
            text: qsTrId("send")
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            onClicked: {
              controller.chosenMethod = "emailPrimary";
              requestConfirmationCode();
            }
          } // TibiaButton
        } // RowLayout
      } // TibiaFrame1PixelDown

      TibiaFrame1PixelDown {
        Layout.fillWidth: true
        Layout.preferredHeight: infoLayout3.height
        enabled: controller.availableMethods.secondaryEmail != ""

        RowLayout {
          id: infoLayout3
          anchors { left: parent.left; right: parent.right; top: parent.top;
                    leftMargin: TibiaStyle.marginUnrelated; rightMargin: TibiaStyle.marginUnrelated }
          spacing: TibiaStyle.marginRelated

          ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            
            TibiaText {
              text: "Secondary Email"
              Layout.alignment: Qt.AlignHCenter
              Layout.topMargin: TibiaStyle.marginUnrelated
            } // TibiaText

            TibiaText {
              text: controller.availableMethods.secondaryEmail != ""
                ? controller.availableMethods.secondaryEmail
                : qsTrId("confirmation_method_missing")
              Layout.alignment: Qt.AlignHCenter
              Layout.bottomMargin: TibiaStyle.marginUnrelated
            } // TibiaText
          } // ColumnLayout

          TibiaButton {
            text: qsTrId("send")
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            onClicked: {
              controller.chosenMethod = "emailSecondary";
              requestConfirmationCode();
            }
          } // TibiaButton
        } // RowLayout
      } // TibiaFrame1PixelDown

      TibiaFrame1PixelDown {
        Layout.fillWidth: true
        Layout.preferredHeight: infoLayout4.height
        enabled: controller.availableMethods.sms != ""

        RowLayout {
          id: infoLayout4
          anchors { left: parent.left; right: parent.right; top: parent.top;
                    leftMargin: TibiaStyle.marginUnrelated; rightMargin: TibiaStyle.marginUnrelated }
          spacing: TibiaStyle.marginRelated
          
          ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            
            TibiaText {
              text: "SMS"
              Layout.alignment: Qt.AlignHCenter
              Layout.topMargin: TibiaStyle.marginUnrelated
            } // TibiaText

            TibiaText {
              text: controller.availableMethods.sms != ""
                ? controller.availableMethods.sms
                : qsTrId("confirmation_method_missing")
              Layout.alignment: Qt.AlignHCenter
              Layout.bottomMargin: TibiaStyle.marginUnrelated
            } // TibiaText
          } // ColumnLayout
          
          TibiaButton {
            text: qsTrId("send")
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            onClicked: {
              controller.chosenMethod = "sms";
              requestConfirmationCode();
            }
          } // TibiaButton
        } // RowLayout
      } // TibiaFrame1PixelDown

      TibiaText {
        text: controller.additionalInfoText
        visible: true
        Layout.fillWidth: true
        wrapMode: Text.Wrap
      } // TibiaText
      
      TibiaText {
        // id: descriptionText
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTrId("request_confirmation_login_text")
        styleType: "Dialog"
      } //TibiaText

      TibiaTextField {
        id: enteredTextField
        enabled: controller.hasPendingCode
        Layout.fillWidth: true
        KeyNavigation.tab: enteredTextField
        focus: true
      } //TibiaTextField
    } //ColumnLayout
    
    TibiaHorizontalSeparator {
      Layout.fillWidth: true
    } //TibiaHorizontalSeparator
    
    RowLayout {
      Layout.fillWidth: true
      spacing: TibiaStyle.marginUnrelated
      
      Item {
        Layout.fillWidth: true
      } //Item
    
      TibiaButton {
        id: okButton
        text: qsTrId("ok")
        enabled: enteredText != "" && controller.hasPendingCode
        onClicked: { sendEnteredText(); } 
      } //TibiaButton
    
      TibiaButton{
        id: cancelButton
        text: qsTrId("cancel")
        onClicked: controller!=null ?  controller.onCancelClicked() : undefined 
      } //TibiaButton
    } //RowLayout
  
  }//ColumnLayout
} //TibiaDialog
