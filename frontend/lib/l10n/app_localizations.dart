import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Docker Monitor'**
  String get appTitle;

  /// No description provided for @titleContainers.
  ///
  /// In en, this message translates to:
  /// **'Containers'**
  String get titleContainers;

  /// No description provided for @titleImages.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get titleImages;

  /// No description provided for @titleSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get titleSettings;

  /// No description provided for @labelDockerApiUrl.
  ///
  /// In en, this message translates to:
  /// **'Docker API URL'**
  String get labelDockerApiUrl;

  /// No description provided for @hintIpPort.
  ///
  /// In en, this message translates to:
  /// **'http://ip:port'**
  String get hintIpPort;

  /// No description provided for @helperDockerApiUrl.
  ///
  /// In en, this message translates to:
  /// **'e.g., http://10.0.2.2:2375 for Android Emulator'**
  String get helperDockerApiUrl;

  /// No description provided for @buttonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get buttonSave;

  /// No description provided for @msgSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get msgSettingsSaved;

  /// No description provided for @msgNoContainers.
  ///
  /// In en, this message translates to:
  /// **'No containers found'**
  String get msgNoContainers;

  /// No description provided for @msgRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get msgRetry;

  /// No description provided for @msgCurrentApi.
  ///
  /// In en, this message translates to:
  /// **'Current API: {api}'**
  String msgCurrentApi(Object api);

  /// No description provided for @buttonRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get buttonRefresh;

  /// No description provided for @labelLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get labelLanguage;

  /// No description provided for @optionSystem.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get optionSystem;

  /// No description provided for @optionEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get optionEnglish;

  /// No description provided for @optionChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get optionChinese;

  /// No description provided for @labelApiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get labelApiKey;

  /// No description provided for @hintApiKey.
  ///
  /// In en, this message translates to:
  /// **'Enter your API Key (optional)'**
  String get hintApiKey;

  /// No description provided for @helperApiKey.
  ///
  /// In en, this message translates to:
  /// **'Required for some Portainer/Docker setups'**
  String get helperApiKey;

  /// No description provided for @labelStack.
  ///
  /// In en, this message translates to:
  /// **'Stack'**
  String get labelStack;

  /// No description provided for @labelImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get labelImage;

  /// No description provided for @labelPorts.
  ///
  /// In en, this message translates to:
  /// **'Ports'**
  String get labelPorts;

  /// No description provided for @labelSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get labelSearch;

  /// No description provided for @hintSearch.
  ///
  /// In en, this message translates to:
  /// **'Search containers...'**
  String get hintSearch;

  /// No description provided for @labelStatusAll.
  ///
  /// In en, this message translates to:
  /// **'all'**
  String get labelStatusAll;

  /// No description provided for @labelStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get labelStatus;

  /// No description provided for @labelFilterStatus.
  ///
  /// In en, this message translates to:
  /// **'Filter by Status'**
  String get labelFilterStatus;

  /// No description provided for @labelFilterStack.
  ///
  /// In en, this message translates to:
  /// **'Filter by Stack'**
  String get labelFilterStack;

  /// No description provided for @actionStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get actionStart;

  /// No description provided for @actionStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get actionStop;

  /// No description provided for @actionKill.
  ///
  /// In en, this message translates to:
  /// **'Kill'**
  String get actionKill;

  /// No description provided for @actionRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get actionRestart;

  /// No description provided for @actionPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get actionPause;

  /// No description provided for @actionResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get actionResume;

  /// No description provided for @actionRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get actionRemove;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @labelTimezone.
  ///
  /// In en, this message translates to:
  /// **'Timezone'**
  String get labelTimezone;

  /// No description provided for @optionUtc.
  ///
  /// In en, this message translates to:
  /// **'UTC'**
  String get optionUtc;

  /// No description provided for @optionUtcPlus8.
  ///
  /// In en, this message translates to:
  /// **'UTC+8 (China)'**
  String get optionUtcPlus8;

  /// No description provided for @optionUtcPlus9.
  ///
  /// In en, this message translates to:
  /// **'UTC+9 (Japan)'**
  String get optionUtcPlus9;

  /// No description provided for @optionUtcMinus5.
  ///
  /// In en, this message translates to:
  /// **'UTC-5 (Eastern US)'**
  String get optionUtcMinus5;

  /// No description provided for @optionUtcPlus1.
  ///
  /// In en, this message translates to:
  /// **'UTC+1 (Central Europe)'**
  String get optionUtcPlus1;

  /// No description provided for @msgOperationNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Operation not allowed for this container'**
  String get msgOperationNotAllowed;

  /// No description provided for @sectionServers.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get sectionServers;

  /// No description provided for @sectionOther.
  ///
  /// In en, this message translates to:
  /// **'Other Settings'**
  String get sectionOther;

  /// No description provided for @buttonAddServer.
  ///
  /// In en, this message translates to:
  /// **'Add Server'**
  String get buttonAddServer;

  /// No description provided for @hintAddServer.
  ///
  /// In en, this message translates to:
  /// **'Tap to add a Docker server'**
  String get hintAddServer;

  /// No description provided for @labelServerName.
  ///
  /// In en, this message translates to:
  /// **'Server Name'**
  String get labelServerName;

  /// No description provided for @msgServerAdded.
  ///
  /// In en, this message translates to:
  /// **'Server added'**
  String get msgServerAdded;

  /// No description provided for @msgServerUpdated.
  ///
  /// In en, this message translates to:
  /// **'Server updated'**
  String get msgServerUpdated;

  /// No description provided for @msgServerCopied.
  ///
  /// In en, this message translates to:
  /// **'Server copied'**
  String get msgServerCopied;

  /// No description provided for @msgServerDeleted.
  ///
  /// In en, this message translates to:
  /// **'Server deleted'**
  String get msgServerDeleted;

  /// No description provided for @msgServerSwitched.
  ///
  /// In en, this message translates to:
  /// **'Switched to {name}'**
  String msgServerSwitched(Object name);

  /// No description provided for @actionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @actionShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get actionShow;

  /// No description provided for @actionHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get actionHide;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionDeleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete All'**
  String get actionDeleteAll;

  /// No description provided for @msgConfirmDeleteAllContainers.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete all containers in this stack? This action cannot be undone.'**
  String get msgConfirmDeleteAllContainers;

  /// No description provided for @labelActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get labelActive;

  /// No description provided for @titleDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get titleDashboard;

  /// No description provided for @labelServerInfo.
  ///
  /// In en, this message translates to:
  /// **'Server Info'**
  String get labelServerInfo;

  /// No description provided for @labelTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get labelTotal;

  /// No description provided for @labelRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get labelRunning;

  /// No description provided for @labelStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get labelStopped;

  /// No description provided for @msgWsConnected.
  ///
  /// In en, this message translates to:
  /// **'WebSocket Connected'**
  String get msgWsConnected;

  /// No description provided for @msgWsDisconnected.
  ///
  /// In en, this message translates to:
  /// **'WebSocket Disconnected'**
  String get msgWsDisconnected;

  /// No description provided for @titlePullImage.
  ///
  /// In en, this message translates to:
  /// **'Pull Image'**
  String get titlePullImage;

  /// No description provided for @labelImageName.
  ///
  /// In en, this message translates to:
  /// **'Image Name'**
  String get labelImageName;

  /// No description provided for @hintImageName.
  ///
  /// In en, this message translates to:
  /// **'e.g., docker.1ms.run/emqx/emqx'**
  String get hintImageName;

  /// No description provided for @labelTag.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get labelTag;

  /// No description provided for @hintTag.
  ///
  /// In en, this message translates to:
  /// **'e.g., latest'**
  String get hintTag;

  /// No description provided for @buttonPull.
  ///
  /// In en, this message translates to:
  /// **'Pull'**
  String get buttonPull;

  /// No description provided for @msgImageNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Image name cannot be empty'**
  String get msgImageNameRequired;

  /// No description provided for @msgImagePullSuccess.
  ///
  /// In en, this message translates to:
  /// **'Image pulled successfully'**
  String get msgImagePullSuccess;

  /// No description provided for @msgImagePullFailed.
  ///
  /// In en, this message translates to:
  /// **'Pull failed: {error}'**
  String msgImagePullFailed(Object error);

  /// No description provided for @tabDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get tabDetails;

  /// No description provided for @tabLogs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get tabLogs;

  /// No description provided for @msgNoLogs.
  ///
  /// In en, this message translates to:
  /// **'No logs available'**
  String get msgNoLogs;

  /// No description provided for @msgLoadingLogs.
  ///
  /// In en, this message translates to:
  /// **'Loading logs...'**
  String get msgLoadingLogs;

  /// No description provided for @tabOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get tabOverview;

  /// No description provided for @tabNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get tabNetwork;

  /// No description provided for @tabStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get tabStorage;

  /// No description provided for @tabEnv.
  ///
  /// In en, this message translates to:
  /// **'Env'**
  String get tabEnv;

  /// No description provided for @tabFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get tabFiles;

  /// No description provided for @titleNetworks.
  ///
  /// In en, this message translates to:
  /// **'Networks'**
  String get titleNetworks;

  /// No description provided for @hintSearchNetworks.
  ///
  /// In en, this message translates to:
  /// **'Search networks...'**
  String get hintSearchNetworks;

  /// No description provided for @labelDriver.
  ///
  /// In en, this message translates to:
  /// **'Driver'**
  String get labelDriver;

  /// No description provided for @labelScope.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get labelScope;

  /// No description provided for @titleStacks.
  ///
  /// In en, this message translates to:
  /// **'Stacks'**
  String get titleStacks;

  /// No description provided for @hintSearchStacks.
  ///
  /// In en, this message translates to:
  /// **'Search stacks...'**
  String get hintSearchStacks;

  /// No description provided for @titleVolumes.
  ///
  /// In en, this message translates to:
  /// **'Volumes'**
  String get titleVolumes;

  /// No description provided for @hintSearchVolumes.
  ///
  /// In en, this message translates to:
  /// **'Search volumes...'**
  String get hintSearchVolumes;

  /// No description provided for @titleResources.
  ///
  /// In en, this message translates to:
  /// **'Resources'**
  String get titleResources;

  /// No description provided for @titlePorts.
  ///
  /// In en, this message translates to:
  /// **'Ports'**
  String get titlePorts;

  /// No description provided for @msgAvailablePorts.
  ///
  /// In en, this message translates to:
  /// **'Available Ports: {count}'**
  String msgAvailablePorts(Object count);

  /// No description provided for @msgPortRange.
  ///
  /// In en, this message translates to:
  /// **'Port Range'**
  String get msgPortRange;

  /// No description provided for @labelMountpoint.
  ///
  /// In en, this message translates to:
  /// **'Mountpoint'**
  String get labelMountpoint;

  /// No description provided for @labelCreated.
  ///
  /// In en, this message translates to:
  /// **'Created At'**
  String get labelCreated;

  /// No description provided for @labelOptions.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get labelOptions;

  /// No description provided for @labelLabels.
  ///
  /// In en, this message translates to:
  /// **'Labels'**
  String get labelLabels;

  /// No description provided for @labelIgnoreSsl.
  ///
  /// In en, this message translates to:
  /// **'Ignore SSL Verification'**
  String get labelIgnoreSsl;

  /// No description provided for @msgErrorLoadingFiles.
  ///
  /// In en, this message translates to:
  /// **'Error loading files'**
  String get msgErrorLoadingFiles;

  /// No description provided for @msgFileSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected file: {name} ({size})'**
  String msgFileSelected(Object name, Object size);

  /// No description provided for @labelMounted.
  ///
  /// In en, this message translates to:
  /// **'Mounted'**
  String get labelMounted;

  /// No description provided for @msgFileSaved.
  ///
  /// In en, this message translates to:
  /// **'File saved successfully'**
  String get msgFileSaved;

  /// No description provided for @msgErrorSavingFile.
  ///
  /// In en, this message translates to:
  /// **'Error saving file: {error}'**
  String msgErrorSavingFile(Object error);

  /// No description provided for @labelInUse.
  ///
  /// In en, this message translates to:
  /// **'In Use'**
  String get labelInUse;

  /// No description provided for @msgContainerClosed.
  ///
  /// In en, this message translates to:
  /// **'Container is closed, cannot access files'**
  String get msgContainerClosed;

  /// No description provided for @labelDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get labelDownload;

  /// No description provided for @labelShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get labelShare;

  /// No description provided for @msgDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading...'**
  String get msgDownloading;

  /// No description provided for @titleConfirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Confirm Delete'**
  String get titleConfirmDelete;

  /// No description provided for @msgConfirmDeleteImage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this image?'**
  String get msgConfirmDeleteImage;

  /// No description provided for @titleNewVersion.
  ///
  /// In en, this message translates to:
  /// **'New Version Available'**
  String get titleNewVersion;

  /// No description provided for @msgNoUpdate.
  ///
  /// In en, this message translates to:
  /// **'Your app is up to date'**
  String get msgNoUpdate;

  /// No description provided for @errCheckUpdate.
  ///
  /// In en, this message translates to:
  /// **'Failed to check for updates'**
  String get errCheckUpdate;

  /// No description provided for @msgOpeningBrowserForDownload.
  ///
  /// In en, this message translates to:
  /// **'Opening browser to download update...'**
  String get msgOpeningBrowserForDownload;

  /// No description provided for @errOpenDownloadUrl.
  ///
  /// In en, this message translates to:
  /// **'Failed to open download link'**
  String get errOpenDownloadUrl;

  /// No description provided for @actionUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get actionUpdate;

  /// No description provided for @labelGithub.
  ///
  /// In en, this message translates to:
  /// **'GitHub Repository'**
  String get labelGithub;

  /// No description provided for @buttonScanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get buttonScanQr;

  /// No description provided for @msgScanSuccess.
  ///
  /// In en, this message translates to:
  /// **'Scanned successfully'**
  String get msgScanSuccess;

  /// No description provided for @msgInvalidQr.
  ///
  /// In en, this message translates to:
  /// **'Invalid QR format'**
  String get msgInvalidQr;

  /// No description provided for @buttonManualInput.
  ///
  /// In en, this message translates to:
  /// **'Manual Input'**
  String get buttonManualInput;

  /// No description provided for @titleRunContainer.
  ///
  /// In en, this message translates to:
  /// **'Run Container'**
  String get titleRunContainer;

  /// No description provided for @labelCommand.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get labelCommand;

  /// No description provided for @hintCommand.
  ///
  /// In en, this message translates to:
  /// **'e.g., docker run -d -p 80:80 nginx'**
  String get hintCommand;

  /// No description provided for @msgContainerStarted.
  ///
  /// In en, this message translates to:
  /// **'Container started successfully: {id}'**
  String msgContainerStarted(Object id);

  /// No description provided for @msgRunContainerFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to run container: {error}'**
  String msgRunContainerFailed(Object error);

  /// No description provided for @actionRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get actionRun;

  /// No description provided for @labelUsedByContainers.
  ///
  /// In en, this message translates to:
  /// **'Used By Containers'**
  String get labelUsedByContainers;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterInUse.
  ///
  /// In en, this message translates to:
  /// **'In Use'**
  String get filterInUse;

  /// No description provided for @filterUnused.
  ///
  /// In en, this message translates to:
  /// **'Unused'**
  String get filterUnused;

  /// No description provided for @msgConfirmDeleteVolume.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this volume?'**
  String get msgConfirmDeleteVolume;

  /// No description provided for @msgVolumeDeleted.
  ///
  /// In en, this message translates to:
  /// **'Volume deleted successfully'**
  String get msgVolumeDeleted;

  /// No description provided for @msgDeleteVolumeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete volume: {error}'**
  String msgDeleteVolumeFailed(Object error);

  /// No description provided for @titleNetworkDetails.
  ///
  /// In en, this message translates to:
  /// **'Network Details'**
  String get titleNetworkDetails;

  /// No description provided for @labelSubnet.
  ///
  /// In en, this message translates to:
  /// **'Subnet'**
  String get labelSubnet;

  /// No description provided for @labelGateway.
  ///
  /// In en, this message translates to:
  /// **'Gateway'**
  String get labelGateway;

  /// No description provided for @labelInternal.
  ///
  /// In en, this message translates to:
  /// **'Internal'**
  String get labelInternal;

  /// No description provided for @labelAttachable.
  ///
  /// In en, this message translates to:
  /// **'Attachable'**
  String get labelAttachable;

  /// No description provided for @labelIngress.
  ///
  /// In en, this message translates to:
  /// **'Ingress'**
  String get labelIngress;

  /// No description provided for @labelIPAM.
  ///
  /// In en, this message translates to:
  /// **'IPAM'**
  String get labelIPAM;

  /// No description provided for @labelEnableIPv6.
  ///
  /// In en, this message translates to:
  /// **'Enable IPv6'**
  String get labelEnableIPv6;

  /// No description provided for @titleEnvVars.
  ///
  /// In en, this message translates to:
  /// **'Environment Variables'**
  String get titleEnvVars;

  /// No description provided for @tabGlobal.
  ///
  /// In en, this message translates to:
  /// **'Global'**
  String get tabGlobal;

  /// No description provided for @tabGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get tabGroups;

  /// No description provided for @labelKey.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get labelKey;

  /// No description provided for @labelValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get labelValue;

  /// No description provided for @labelGroupName.
  ///
  /// In en, this message translates to:
  /// **'Group Name'**
  String get labelGroupName;

  /// No description provided for @msgVarAdded.
  ///
  /// In en, this message translates to:
  /// **'Variable added'**
  String get msgVarAdded;

  /// No description provided for @msgGroupAdded.
  ///
  /// In en, this message translates to:
  /// **'Group added'**
  String get msgGroupAdded;

  /// No description provided for @msgConfirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete?'**
  String get msgConfirmDelete;

  /// No description provided for @actionInsertEnvVars.
  ///
  /// In en, this message translates to:
  /// **'Insert Env Vars'**
  String get actionInsertEnvVars;

  /// No description provided for @titleSelectEnvVars.
  ///
  /// In en, this message translates to:
  /// **'Select Env Vars'**
  String get titleSelectEnvVars;

  /// No description provided for @labelSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} variables selected'**
  String labelSelectedCount(Object count);

  /// No description provided for @labelMore.
  ///
  /// In en, this message translates to:
  /// **'more'**
  String get labelMore;

  /// No description provided for @titleLogin.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get titleLogin;

  /// No description provided for @labelUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get labelUsername;

  /// No description provided for @labelPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get labelPassword;

  /// No description provided for @hintUsername.
  ///
  /// In en, this message translates to:
  /// **'Enter username'**
  String get hintUsername;

  /// No description provided for @hintPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter password'**
  String get hintPassword;

  /// No description provided for @btnLogin.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get btnLogin;

  /// No description provided for @msgLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed, please check your credentials'**
  String get msgLoginFailed;

  /// No description provided for @msgConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get msgConnecting;

  /// No description provided for @btnLogout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get btnLogout;

  /// No description provided for @actionChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get actionChangePassword;

  /// No description provided for @labelCurrentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get labelCurrentPassword;

  /// No description provided for @labelNewPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get labelNewPassword;

  /// No description provided for @labelConfirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get labelConfirmNewPassword;

  /// No description provided for @msgPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a password'**
  String get msgPasswordRequired;

  /// No description provided for @msgPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'The passwords do not match'**
  String get msgPasswordMismatch;

  /// No description provided for @msgPasswordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed successfully'**
  String get msgPasswordChanged;

  /// No description provided for @titleApiKeys.
  ///
  /// In en, this message translates to:
  /// **'API Keys'**
  String get titleApiKeys;

  /// No description provided for @labelApiKeyName.
  ///
  /// In en, this message translates to:
  /// **'Key Name'**
  String get labelApiKeyName;

  /// No description provided for @hintApiKeyName.
  ///
  /// In en, this message translates to:
  /// **'Enter a name for this key'**
  String get hintApiKeyName;

  /// No description provided for @labelApiKeyValue.
  ///
  /// In en, this message translates to:
  /// **'Key Value'**
  String get labelApiKeyValue;

  /// No description provided for @hintApiKeyValue.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for auto-generated key'**
  String get hintApiKeyValue;

  /// No description provided for @msgApiKeyCreated.
  ///
  /// In en, this message translates to:
  /// **'API Key created'**
  String get msgApiKeyCreated;

  /// No description provided for @msgApiKeyDeleted.
  ///
  /// In en, this message translates to:
  /// **'API Key deleted'**
  String get msgApiKeyDeleted;

  /// No description provided for @msgApiKeyCopied.
  ///
  /// In en, this message translates to:
  /// **'API Key copied to clipboard'**
  String get msgApiKeyCopied;

  /// No description provided for @msgNoApiKeys.
  ///
  /// In en, this message translates to:
  /// **'No API keys found'**
  String get msgNoApiKeys;

  /// No description provided for @actionCreateKey.
  ///
  /// In en, this message translates to:
  /// **'Create Key'**
  String get actionCreateKey;

  /// No description provided for @labelCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get labelCreatedAt;

  /// No description provided for @labelExpiresAt.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get labelExpiresAt;

  /// No description provided for @labelNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get labelNever;

  /// No description provided for @msgConfirmDeleteApiKey.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this API key?'**
  String get msgConfirmDeleteApiKey;

  /// No description provided for @msgNoContainerSelected.
  ///
  /// In en, this message translates to:
  /// **'Select a container to view details'**
  String get msgNoContainerSelected;

  /// No description provided for @titleSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'System Settings'**
  String get titleSystemSettings;

  /// No description provided for @titleEmailSettings.
  ///
  /// In en, this message translates to:
  /// **'Email Settings'**
  String get titleEmailSettings;

  /// No description provided for @labelSmtpHost.
  ///
  /// In en, this message translates to:
  /// **'SMTP Host'**
  String get labelSmtpHost;

  /// No description provided for @labelSmtpPort.
  ///
  /// In en, this message translates to:
  /// **'SMTP Port'**
  String get labelSmtpPort;

  /// No description provided for @labelSmtpUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get labelSmtpUsername;

  /// No description provided for @labelSmtpPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get labelSmtpPassword;

  /// No description provided for @labelSmtpFromEmail.
  ///
  /// In en, this message translates to:
  /// **'From Email'**
  String get labelSmtpFromEmail;

  /// No description provided for @labelSmtpFromName.
  ///
  /// In en, this message translates to:
  /// **'From Name'**
  String get labelSmtpFromName;

  /// No description provided for @labelSmtpUseSsl.
  ///
  /// In en, this message translates to:
  /// **'Use SSL'**
  String get labelSmtpUseSsl;

  /// No description provided for @labelSmtpUseStarttls.
  ///
  /// In en, this message translates to:
  /// **'Use STARTTLS'**
  String get labelSmtpUseStarttls;

  /// No description provided for @labelSmtpTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timeout (seconds)'**
  String get labelSmtpTimeout;

  /// No description provided for @hintSmtpHost.
  ///
  /// In en, this message translates to:
  /// **'e.g., smtp.gmail.com'**
  String get hintSmtpHost;

  /// No description provided for @hintSmtpPort.
  ///
  /// In en, this message translates to:
  /// **'e.g., 587'**
  String get hintSmtpPort;

  /// No description provided for @hintSmtpUsername.
  ///
  /// In en, this message translates to:
  /// **'SMTP username'**
  String get hintSmtpUsername;

  /// No description provided for @hintSmtpPasswordKeep.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to keep unchanged'**
  String get hintSmtpPasswordKeep;

  /// No description provided for @hintSmtpFromEmail.
  ///
  /// In en, this message translates to:
  /// **'e.g., noreply@example.com'**
  String get hintSmtpFromEmail;

  /// No description provided for @hintSmtpFromName.
  ///
  /// In en, this message translates to:
  /// **'Mobile Portainer'**
  String get hintSmtpFromName;

  /// No description provided for @msgSmtpSaved.
  ///
  /// In en, this message translates to:
  /// **'SMTP settings saved'**
  String get msgSmtpSaved;

  /// No description provided for @titleProfileSettings.
  ///
  /// In en, this message translates to:
  /// **'Personal Info'**
  String get titleProfileSettings;

  /// No description provided for @titlePersonalInfo.
  ///
  /// In en, this message translates to:
  /// **'Personal Info'**
  String get titlePersonalInfo;

  /// No description provided for @labelEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get labelEmail;

  /// No description provided for @hintEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter your email address'**
  String get hintEmail;

  /// No description provided for @hintEmailBind.
  ///
  /// In en, this message translates to:
  /// **'Bind your email to receive notifications and recover your account'**
  String get hintEmailBind;

  /// No description provided for @actionBindEmail.
  ///
  /// In en, this message translates to:
  /// **'Bind Email'**
  String get actionBindEmail;

  /// No description provided for @actionChangeEmail.
  ///
  /// In en, this message translates to:
  /// **'Change Email'**
  String get actionChangeEmail;

  /// No description provided for @msgEmailBound.
  ///
  /// In en, this message translates to:
  /// **'Email bound successfully'**
  String get msgEmailBound;

  /// No description provided for @msgEmailUpdated.
  ///
  /// In en, this message translates to:
  /// **'Email updated successfully'**
  String get msgEmailUpdated;

  /// No description provided for @msgEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter an email address'**
  String get msgEmailRequired;

  /// No description provided for @msgEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get msgEmailInvalid;

  /// No description provided for @labelNotBound.
  ///
  /// In en, this message translates to:
  /// **'Not bound'**
  String get labelNotBound;

  /// No description provided for @actionSendTestEmail.
  ///
  /// In en, this message translates to:
  /// **'Send Test Email'**
  String get actionSendTestEmail;

  /// No description provided for @msgTestEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Test email sent successfully'**
  String get msgTestEmailSent;

  /// No description provided for @msgTestEmailFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send test email'**
  String get msgTestEmailFailed;

  /// No description provided for @msgSendingTestEmail.
  ///
  /// In en, this message translates to:
  /// **'Sending test email...'**
  String get msgSendingTestEmail;

  /// No description provided for @msgNoEmailBound.
  ///
  /// In en, this message translates to:
  /// **'Please bind an email address first'**
  String get msgNoEmailBound;

  /// No description provided for @msgNoSmtpConfig.
  ///
  /// In en, this message translates to:
  /// **'SMTP is not configured, please configure it in System Settings first'**
  String get msgNoSmtpConfig;

  /// No description provided for @labelApiDocs.
  ///
  /// In en, this message translates to:
  /// **'API Documentation (Swagger)'**
  String get labelApiDocs;

  /// No description provided for @labelRedoc.
  ///
  /// In en, this message translates to:
  /// **'API Documentation (ReDoc)'**
  String get labelRedoc;

  /// No description provided for @msgNoActiveServer.
  ///
  /// In en, this message translates to:
  /// **'No active server configured'**
  String get msgNoActiveServer;

  /// No description provided for @titleProjects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get titleProjects;

  /// No description provided for @hintSearchProjects.
  ///
  /// In en, this message translates to:
  /// **'Search projects...'**
  String get hintSearchProjects;

  /// No description provided for @msgNoProjects.
  ///
  /// In en, this message translates to:
  /// **'No projects found'**
  String get msgNoProjects;

  /// No description provided for @labelProjectName.
  ///
  /// In en, this message translates to:
  /// **'Project Name'**
  String get labelProjectName;

  /// No description provided for @labelProjectDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get labelProjectDescription;

  /// No description provided for @hintProjectName.
  ///
  /// In en, this message translates to:
  /// **'Enter project name'**
  String get hintProjectName;

  /// No description provided for @hintProjectDescription.
  ///
  /// In en, this message translates to:
  /// **'Optional description'**
  String get hintProjectDescription;

  /// No description provided for @actionCreateProject.
  ///
  /// In en, this message translates to:
  /// **'Create Project'**
  String get actionCreateProject;

  /// No description provided for @actionSaveFile.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSaveFile;

  /// No description provided for @actionBuildImage.
  ///
  /// In en, this message translates to:
  /// **'Build Image'**
  String get actionBuildImage;

  /// No description provided for @actionComposeUp.
  ///
  /// In en, this message translates to:
  /// **'Up'**
  String get actionComposeUp;

  /// No description provided for @actionComposeDown.
  ///
  /// In en, this message translates to:
  /// **'Down'**
  String get actionComposeDown;

  /// No description provided for @msgBuildStarted.
  ///
  /// In en, this message translates to:
  /// **'Build started'**
  String get msgBuildStarted;

  /// No description provided for @msgBuildSuccess.
  ///
  /// In en, this message translates to:
  /// **'Build completed successfully'**
  String get msgBuildSuccess;

  /// No description provided for @msgBuildFailed.
  ///
  /// In en, this message translates to:
  /// **'Build failed'**
  String get msgBuildFailed;

  /// No description provided for @msgBuildLogEmpty.
  ///
  /// In en, this message translates to:
  /// **'No build logs yet'**
  String get msgBuildLogEmpty;

  /// No description provided for @msgComposeUpSuccess.
  ///
  /// In en, this message translates to:
  /// **'Containers started successfully'**
  String get msgComposeUpSuccess;

  /// No description provided for @msgComposeDownSuccess.
  ///
  /// In en, this message translates to:
  /// **'Containers stopped successfully'**
  String get msgComposeDownSuccess;

  /// No description provided for @titleBuildLogs.
  ///
  /// In en, this message translates to:
  /// **'Build Logs'**
  String get titleBuildLogs;

  /// No description provided for @labelFileDockerfile.
  ///
  /// In en, this message translates to:
  /// **'Dockerfile'**
  String get labelFileDockerfile;

  /// No description provided for @labelFileCompose.
  ///
  /// In en, this message translates to:
  /// **'docker-compose.yaml'**
  String get labelFileCompose;

  /// No description provided for @msgProjectCreated.
  ///
  /// In en, this message translates to:
  /// **'Project created successfully'**
  String get msgProjectCreated;

  /// No description provided for @msgProjectDeleted.
  ///
  /// In en, this message translates to:
  /// **'Project deleted'**
  String get msgProjectDeleted;

  /// No description provided for @msgConfirmDeleteProject.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this project? All associated files will also be deleted.'**
  String get msgConfirmDeleteProject;

  /// No description provided for @msgSaveBeforeBuild.
  ///
  /// In en, this message translates to:
  /// **'Please save your files before building'**
  String get msgSaveBeforeBuild;

  /// No description provided for @labelBuildId.
  ///
  /// In en, this message translates to:
  /// **'Build ID'**
  String get labelBuildId;

  /// No description provided for @labelImageId.
  ///
  /// In en, this message translates to:
  /// **'Image ID'**
  String get labelImageId;

  /// No description provided for @msgSaveAll.
  ///
  /// In en, this message translates to:
  /// **'All files saved'**
  String get msgSaveAll;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'zh': return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
