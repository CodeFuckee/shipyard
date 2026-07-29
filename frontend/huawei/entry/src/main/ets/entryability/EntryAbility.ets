import { ConfigurationConstant, Want } from '@kit.AbilityKit';
import { AbilityConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import window from '@ohos.window';
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '@ohos/flutter_module';
import { HarmonyPlatformPlugin } from '../platform/HarmonyPlatformPlugin';

const DOMAIN = 0x0000;

export default class EntryAbility extends FlutterAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    super.onCreate(want, launchParam);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  configureFlutterEngine(flutterEngine: FlutterEngine): void {
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);
    new HarmonyPlatformPlugin(flutterEngine, this.context);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    super.onWindowStageCreate(windowStage);
    const mainWindow = windowStage.getMainWindowSync();
    HarmonyPlatformPlugin.mainWindow = mainWindow;
    mainWindow.on('windowStatusChange', (status: window.WindowStatusType) => {
      HarmonyPlatformPlugin.isInSplitScreen =
        status === window.WindowStatusType.SPLIT_SCREEN;
      hilog.info(DOMAIN, 'testTag',
        `Window status: ${status}, isInSplitScreen: ${HarmonyPlatformPlugin.isInSplitScreen}`);
    });
    hilog.info(DOMAIN, 'testTag', 'Window status listener registered');
  }

  onBackPress(): boolean {
    hilog.info(DOMAIN, 'testTag',
      `onBackPress, isInSplitScreen=${HarmonyPlatformPlugin.isInSplitScreen}`);
    if (HarmonyPlatformPlugin.isInSplitScreen && HarmonyPlatformPlugin.mainWindow) {
      try {
        HarmonyPlatformPlugin.mainWindow.maximize();
        hilog.info(DOMAIN, 'testTag', 'maximize called to exit split screen');
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', `maximize error: ${JSON.stringify(err)}`);
      }
      return true;
    }
    return false;
  }

  onDestroy(): void {
    super.onDestroy();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onForeground(): void {
    super.onForeground();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    super.onBackground();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
