import QtQuick
import QtQuick.Layouts

import qmlenumvalues


TibiaDialog {
  id: enterTextDialog
  property var twoFactorMethod: controller.twoFactorMethod

  caption: twoFactorMethod == TwoFactorCodeEnterText.Email
    ? qsTrId("request_two_factor_email_code_caption")
    : qsTrId("request_two_factor_token_caption")
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


  onReturnPressedFunction: sendEnteredText
  onCancelPressedFunction: controller!=null ? controller.onCancelClicked : null
  initialFocusItem: enteredTextField

  ColumnLayout {
    id: emailColumns
    anchors { left: parent.left; right: parent.right}
    spacing: TibiaStyle.marginUnrelated
    
    ColumnLayout {
      spacing: TibiaStyle.marginRelated
      Layout.fillWidth: true

      TibiaText {
        id: descriptionText
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: twoFactorMethod == TwoFactorCodeEnterText.Email
          ? qsTrId("request_two_factor_email_code_text")
          : qsTrId("request_two_factor_token_text")
        styleType: "Dialog"
      } //TibiaText
      
      TibiaTextField {
        id: enteredTextField
        Layout.fillWidth: true
        KeyNavigation.tab: enteredTextField
        focus: true
        property var numberVal: RegularExpressionValidator { regularExpression: /[0-9]{0,9}/; }
        validator: {
          if (twoFactorMethod == TwoFactorCodeEnterText.Authenticator) {
            return numberVal;
          }
          
          return null;
        }
      } //TibiaTextField

      TibiaText {
        text: controller.additionalInfoText
        visible: twoFactorMethod == TwoFactorCodeEnterText.Email && controller.additionalInfoText != ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
      } // TibiaText

      RowLayout {
        Layout.fillWidth: true

        TibiaCheckBox {
          text: qsTrId("request_two_factor_trusted_device")
          Layout.fillWidth: true
          shouldBeChecked: controller != null && controller.trustedDevice

          onClicked: {
            if (controller != null) {
              controller.trustedDevice = !controller.trustedDevice;
            }
          }
        }

        TibiaGuiHelp {
          text: qsTrId("request_two_factor_trusted_device_help")
        }
      }
    } //ColumnLayout
    
    TibiaHorizontalSeparator {
      Layout.fillWidth: true
    } //TibiaHorizontalSeparator
    
    RowLayout {
      Layout.fillWidth: true
      spacing: TibiaStyle.marginUnrelated

      TibiaButton {
        id: buttonText
        visible: twoFactorMethod == TwoFactorCodeEnterText.Email && controller.emailResendPossible
        text: qsTrId("request_two_factor_email_code_request_new_code_button_text")
        onClicked: controller!=null ?  controller.onButtonClicked() : undefined
        tooltipText: qsTrId("request_two_factor_email_code_request_new_code_button_tooltip")
      } // TibiaButton
      
      Item {
        Layout.fillWidth: true
      } //Item
    
      TibiaButton{
        id: okButton
        text: qsTrId("ok")
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
