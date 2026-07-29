import { router, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HarmonyPlatformPlugin } from '../platform/HarmonyPlatformPlugin';

const DOMAIN = 0x0002;

@Entry
@Component
struct ScanPage {
  @State scanValue: string = '';

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Button('Cancel')
          .fontColor('#FFFFFF')
          .backgroundColor('#00000000')
          .onClick(() => {
            HarmonyPlatformPlugin.cancelScan();
            router.back();
          })

        Blank()

        Text('Scan QR Code')
          .fontSize(18)
          .fontColor('#FFFFFF')

        Blank()

        // 占位
        Row().width(60)
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })
      .backgroundColor('#000000')

      // 说明区域
      Column() {
        Text('QR Scanner')
          .fontSize(24)
          .fontColor('#333333')
          .margin({ bottom: 16 })

        Text('Camera-based scanning is not available in this version.')
          .fontSize(14)
          .fontColor('#666666')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 24 })

        Text('Please enter the QR code content manually below.')
          .fontSize(14)
          .fontColor('#666666')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 32 })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .padding(24)
      .backgroundColor('#F5F5F5')

      // 手动输入区域
      Column() {
        TextInput({ placeholder: 'Paste or type QR code content', text: this.scanValue })
          .width('100%')
          .height(48)
          .onChange((value: string) => {
            this.scanValue = value;
          })

        Row() {
          Button('Submit')
            .width('45%')
            .onClick(() => {
              const trimmedValue = this.scanValue.trim();
              if (trimmedValue.length > 0) {
                HarmonyPlatformPlugin.setScanResult(trimmedValue);
                router.back();
              } else {
                promptAction.showToast({
                  message: 'Please enter QR code content',
                  duration: 2000,
                });
              }
            })

          Blank()

          Button('Paste')
            .width('45%')
            .backgroundColor('#666666')
            .onClick(() => {
              promptAction.showToast({
                message: 'Long press to paste from clipboard',
                duration: 2000,
              });
            })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 40, top: 24 })
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
  }
}
