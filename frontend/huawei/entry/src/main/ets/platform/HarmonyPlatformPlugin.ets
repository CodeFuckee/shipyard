import { FlutterEngine, MethodChannel, MethodCallHandler, MethodResult, MethodCall, BinaryMessenger } from '@ohos/flutter_ohos';
import { common, bundleManager, abilityAccessCtrl, Want, Permissions } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';
import { promptAction, router } from '@kit.ArkUI';
import window from '@ohos.window';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0001;
const PREF_NAME = 'MobilePortainerPrefs';
const CHANNEL_NAME = 'com.chenkaidi.mobileportainer/harmonyos';

// 定义支持的权限映射
const PERMISSION_MAP: Record<string, string> = {
  'storage': 'ohos.permission.READ_MEDIA',
  'manageExternalStorage': 'ohos.permission.READ_MEDIA',
  'camera': 'ohos.permission.CAMERA',
  'microphone': 'ohos.permission.MICROPHONE',
  'location': 'ohos.permission.LOCATION',
};

export class HarmonyPlatformPlugin implements MethodCallHandler {
  private channel: MethodChannel;
  private context: common.UIAbilityContext;
  // 存储 QR 扫描的结果回调
  static pendingScanResult: MethodResult | null = null;
  // 供 EntryAbility 访问分屏状态和 MethodChannel
  static channel: MethodChannel | null = null;
  static mainWindow: window.Window | null = null;
  static isInSplitScreen: boolean = false;

  constructor(flutterEngine: FlutterEngine, context: common.UIAbilityContext) {
    this.context = context;
    const messenger: BinaryMessenger = flutterEngine.getDartExecutor().getBinaryMessenger();
    this.channel = new MethodChannel(messenger, CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
    HarmonyPlatformPlugin.channel = this.channel;
    hilog.info(DOMAIN, 'HarmonyPlatform', 'Platform plugin registered');
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    hilog.info(DOMAIN, 'HarmonyPlatform', `Method call: ${call.method}`);

    switch (call.method) {
      // SharedPreferences
      case 'getString':
        this.handleGetString(call, result);
        break;
      case 'setString':
        this.handleSetString(call, result);
        break;
      case 'removeString':
        this.handleRemoveString(call, result);
        break;

      // PackageInfo
      case 'getPackageInfo':
        this.handleGetPackageInfo(result);
        break;

      // UrlLauncher
      case 'launchUrl':
        this.handleLaunchUrl(call, result);
        break;

      // PathProvider
      case 'getTemporaryDirectory':
        this.handleGetTempDir(result);
        break;
      case 'getDownloadsDirectory':
        this.handleGetDownloadsDir(result);
        break;

      // Share
      case 'shareFile':
        this.handleShareFile(call, result);
        break;

      // PermissionHandler
      case 'checkPermission':
        this.handleCheckPermission(call, result);
        break;
      case 'requestPermission':
        this.handleRequestPermission(call, result);
        break;

      // DeviceInfo
      case 'getDeviceInfo':
        this.handleGetDeviceInfo(result);
        break;

      // Toast
      case 'showToast':
        this.handleShowToast(call, result);
        break;

      // Notifications
      case 'initNotifications':
        this.handleInitNotifications(result);
        break;
      case 'showNotification':
        this.handleShowNotification(call, result);
        break;

      // QR Scanner
      case 'scanQrCode':
        this.handleScanQrCode(result);
        break;

      // Split Screen
      case 'exitSplitScreen':
        this.handleExitSplitScreen(result);
        break;

      default:
        result.notImplemented();
        break;
    }
  }

  // ==================== SharedPreferences 实现 ====================

  private async handleGetString(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const key: string = (call.argument('key') as string) ?? '';
      const prefs = await preferences.getPreferences(this.context, PREF_NAME);
      const value = await prefs.get(key, '');
      await prefs.flush();
      result.success(value === '' ? null : value);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, 'Prefs', `getString error: ${e.message}`);
      result.success(null);
    }
  }

  private async handleSetString(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const key: string = (call.argument('key') as string) ?? '';
      const value: string = (call.argument('value') as string) ?? '';
      const prefs = await preferences.getPreferences(this.context, PREF_NAME);
      await prefs.put(key, value);
      await prefs.flush();
      result.success(true);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, 'Prefs', `setString error: ${e.message}`);
      result.success(false);
    }
  }

  private async handleRemoveString(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const key: string = (call.argument('key') as string) ?? '';
      const prefs = await preferences.getPreferences(this.context, PREF_NAME);
      await prefs.delete(key);
      await prefs.flush();
      result.success(true);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, 'Prefs', `remove error: ${e.message}`);
      result.success(false);
    }
  }

  // ==================== PackageInfo 实现 ====================

  private handleGetPackageInfo(result: MethodResult): void {
    try {
      const flags = bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT;
      bundleManager.getBundleInfoForSelf(flags).then((bundleInfo) => {
        const info: Record<string, string> = {
          'version': bundleInfo.versionName,
          'buildNumber': String(bundleInfo.versionCode),
          'packageName': bundleInfo.name,
        };
        result.success(info);
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, 'PackageInfo', `Error: ${err.message}`);
        const fallback: Record<string, string> = {
          'version': '1.0.0',
          'buildNumber': '1',
          'packageName': 'com.chenkaidi.mobileportainer',
        };
        result.success(fallback);
      });
    } catch (err) {
      const fallback: Record<string, string> = {
        'version': '1.0.0',
        'buildNumber': '1',
      };
      result.success(fallback);
    }
  }

  // ==================== UrlLauncher 实现 ====================

  private handleLaunchUrl(call: MethodCall, result: MethodResult): void {
    try {
      const url: string = (call.argument('url') as string) ?? '';

      // 使用 Want 打开 URL (替代不存在于该SDK的 openLink)
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url,
      };

      this.context.startAbility(want).then(() => {
        result.success(true);
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, 'UrlLauncher', `startAbility error: ${err.message}`);

        // 回退：尝试使用系统浏览器
        const browserWant: Want = {
          bundleName: 'com.huawei.hmos.browser',
          abilityName: 'com.huawei.hmos.browser.MainAbility',
          uri: url,
        };

        this.context.startAbility(browserWant).then(() => {
          result.success(true);
        }).catch(() => {
          result.success(false);
        });
      });
    } catch (err) {
      result.success(false);
    }
  }

  // ==================== PathProvider 实现 ====================

  private handleGetTempDir(result: MethodResult): void {
    try {
      result.success(this.context.tempDir);
    } catch (err) {
      result.error('TEMP_DIR_ERROR', 'Cannot get temp dir', null);
    }
  }

  private handleGetDownloadsDir(result: MethodResult): void {
    try {
      // 使用 filesDir + Download 子目录作为下载路径
      result.success(this.context.filesDir + '/Download');
    } catch (err) {
      result.error('DOWNLOADS_DIR_ERROR', 'Cannot get downloads dir', null);
    }
  }

  // ==================== Share 实现 ====================

  private async handleShareFile(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const filePath: string = (call.argument('path') as string) ?? '';

      // 构建分享 Want
      const want: Want = {
        action: 'ohos.want.action.sendData',
        uri: filePath,
        type: '*/*',
      };

      await this.context.startAbility(want);
      result.success(true);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, 'Share', `shareFile error: ${e.message}`);
      result.success(false);
    }
  }

  // ==================== PermissionHandler 实现 ====================

  private handleCheckPermission(call: MethodCall, result: MethodResult): void {
    try {
      const permission: string = (call.argument('permission') as string) ?? '';
      const ohosPermission: string | undefined = PERMISSION_MAP[permission];

      if (!ohosPermission) {
        result.success(0); // 不支持的权限返回已授权
        return;
      }

      const atManager = abilityAccessCtrl.createAtManager();
      const grantStatus = atManager.checkAccessTokenSync(
        this.context.applicationInfo.accessTokenId,
        ohosPermission as Permissions
      );

      result.success(grantStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED ? 0 : -1);
    } catch (err) {
      result.success(0);
    }
  }

  private handleRequestPermission(call: MethodCall, result: MethodResult): void {
    try {
      const permission: string = (call.argument('permission') as string) ?? '';
      const ohosPermission: string | undefined = PERMISSION_MAP[permission];

      if (!ohosPermission) {
        result.success(0);
        return;
      }

      const atManager = abilityAccessCtrl.createAtManager();
      const perm: Permissions = ohosPermission as Permissions;

      atManager.requestPermissionsFromUser(this.context, [perm]).then((permResult) => {
        if (permResult.authResults.length > 0) {
          result.success(permResult.authResults[0] === 0 ? 0 : -1);
        } else {
          result.success(-1);
        }
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, 'Permission', `request error: ${err.message}`);
        result.success(-1);
      });
    } catch (err) {
      result.success(-1);
    }
  }

  // ==================== DeviceInfo 实现 ====================

  private handleGetDeviceInfo(result: MethodResult): void {
    try {
      const info: Record<string, Object> = {
        'sdkInt': deviceInfo.sdkApiVersion,
        'manufacturer': deviceInfo.manufacture,
        'model': deviceInfo.marketName,
        'brand': deviceInfo.brand,
        'osVersion': deviceInfo.osFullName,
      };
      result.success(info);
    } catch (err) {
      const fallback: Record<string, number> = { 'sdkInt': 12 };
      result.success(fallback);
    }
  }

  // ==================== Toast 实现 ====================

  private handleShowToast(call: MethodCall, result: MethodResult): void {
    try {
      const message: string = (call.argument('message') as string) ?? '';
      promptAction.showToast({
        message: message,
        duration: 2000,
        bottom: '50%',
      });
      result.success(null);
    } catch (err) {
      result.success(null);
    }
  }

  // ==================== Notifications 实现 ====================

  private handleInitNotifications(result: MethodResult): void {
    try {
      notificationManager.isNotificationEnabled().then((enabled: boolean) => {
        if (!enabled) {
          notificationManager.requestEnableNotification().then(() => {
            result.success(true);
          }).catch(() => {
            result.success(false);
          });
        } else {
          result.success(true);
        }
      }).catch(() => {
        result.success(false);
      });
    } catch (err) {
      result.success(false);
    }
  }

  private async handleShowNotification(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const title: string = (call.argument('title') as string) ?? '';
      const body: string = (call.argument('body') as string) ?? '';

      const request: notificationManager.NotificationRequest = {
        id: 1,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: body,
          }
        }
      };

      await notificationManager.publish(request);
      result.success(null);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, 'Notification', `show error: ${e.message}`);
      result.success(null);
    }
  }

  // ==================== Split Screen 实现 ====================

  private async handleExitSplitScreen(result: MethodResult): Promise<void> {
    try {
      if (HarmonyPlatformPlugin.isInSplitScreen && HarmonyPlatformPlugin.mainWindow) {
        await HarmonyPlatformPlugin.mainWindow.maximize();
        result.success(true);
        hilog.info(DOMAIN, 'HarmonyPlatform', 'Split screen exited via maximize');
      } else {
        result.success(false);
      }
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, 'HarmonyPlatform', `exitSplitScreen error: ${e.message}`);
      result.success(false);
    }
  }

  // ==================== QR Scanner 实现 ====================

  private handleScanQrCode(result: MethodResult): void {
    try {
      // 存储回调，等扫描完成后使用
      HarmonyPlatformPlugin.pendingScanResult = result;

      // 通过 router 跳转到扫描页面
      router.pushUrl({
        url: 'pages/ScanPage'
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, 'Scan', `router.pushUrl error: ${err.message}`);
        result.success(null);
        HarmonyPlatformPlugin.pendingScanResult = null;
      });
    } catch (err) {
      result.success(null);
    }
  }

  // 供外部调用的静态方法，用于设置扫描结果
  static setScanResult(scanResult: string): void {
    if (HarmonyPlatformPlugin.pendingScanResult) {
      HarmonyPlatformPlugin.pendingScanResult.success(scanResult);
      HarmonyPlatformPlugin.pendingScanResult = null;
    }
  }

  // 取消扫描
  static cancelScan(): void {
    if (HarmonyPlatformPlugin.pendingScanResult) {
      HarmonyPlatformPlugin.pendingScanResult.success(null);
      HarmonyPlatformPlugin.pendingScanResult = null;
    }
  }
}
