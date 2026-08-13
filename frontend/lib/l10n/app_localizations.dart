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

  /// No description provided for @actionUpgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get actionUpgrade;

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

  /// No description provided for @buttonTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get buttonTestConnection;

  /// No description provided for @msgConnectionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connection successful'**
  String get msgConnectionSuccess;

  /// No description provided for @msgConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}'**
  String msgConnectionFailed(Object error);

  /// No description provided for @msgApiKeyRequired.
  ///
  /// In en, this message translates to:
  /// **'API Key is required'**
  String get msgApiKeyRequired;

  /// No description provided for @titleApiKeysFor.
  ///
  /// In en, this message translates to:
  /// **'API Keys for: {url}'**
  String titleApiKeysFor(Object url);

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

  /// No description provided for @msgCopyFailed.
  ///
  /// In en, this message translates to:
  /// **'Copy failed, please try again'**
  String get msgCopyFailed;

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

  /// No description provided for @labelGitUrl.
  ///
  /// In en, this message translates to:
  /// **'Git Repository URL'**
  String get labelGitUrl;

  /// No description provided for @hintGitUrl.
  ///
  /// In en, this message translates to:
  /// **'Optional: clone project from a git repository (e.g. https://host/user/repo.git)'**
  String get hintGitUrl;

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

  /// No description provided for @tooltipDeleteProject.
  ///
  /// In en, this message translates to:
  /// **'Delete project'**
  String get tooltipDeleteProject;

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

  /// No description provided for @labelBuildTime.
  ///
  /// In en, this message translates to:
  /// **'Build Time'**
  String get labelBuildTime;

  /// No description provided for @buttonConnectAdd.
  ///
  /// In en, this message translates to:
  /// **'Authorize Add'**
  String get buttonConnectAdd;

  /// No description provided for @titleConnectAdd.
  ///
  /// In en, this message translates to:
  /// **'Add Server via Authorization'**
  String get titleConnectAdd;

  /// No description provided for @helperConnectAdd.
  ///
  /// In en, this message translates to:
  /// **'Authorize on the target server\'s web page, then the API key is added automatically'**
  String get helperConnectAdd;

  /// No description provided for @errorConnectMixedContent.
  ///
  /// In en, this message translates to:
  /// **'Cannot connect to an http target from an https page (blocked as mixed content by the browser). Configure the target server with https'**
  String get errorConnectMixedContent;

  /// No description provided for @msgConnectProbeFailed.
  ///
  /// In en, this message translates to:
  /// **'This server does not support authorized adding, please add manually'**
  String get msgConnectProbeFailed;

  /// No description provided for @msgConnectProbing.
  ///
  /// In en, this message translates to:
  /// **'Checking whether the target server supports web authorization...'**
  String get msgConnectProbing;

  /// No description provided for @msgConnectJump.
  ///
  /// In en, this message translates to:
  /// **'You will be redirected to {url} to authorize. After login and confirmation you will be brought back with the server added'**
  String msgConnectJump(Object url);

  /// No description provided for @msgConnectLaunchHint.
  ///
  /// In en, this message translates to:
  /// **'The system browser will open for authorization, and the app will resume automatically when done'**
  String get msgConnectLaunchHint;

  /// No description provided for @msgConnectProcessing.
  ///
  /// In en, this message translates to:
  /// **'Completing authorization...'**
  String get msgConnectProcessing;

  /// No description provided for @msgConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Authorized add failed: {error}'**
  String msgConnectFailed(Object error);

  /// No description provided for @msgConnectDone.
  ///
  /// In en, this message translates to:
  /// **'Authorized, server added'**
  String get msgConnectDone;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @msgConnectDupServer.
  ///
  /// In en, this message translates to:
  /// **'This server is already in the list. Overwrite its API key?'**
  String get msgConnectDupServer;

  /// No description provided for @actionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get actionConfirm;

  /// No description provided for @buttonCreateBackup.
  ///
  /// In en, this message translates to:
  /// **'Create backup'**
  String get buttonCreateBackup;

  /// No description provided for @hintCronExpression.
  ///
  /// In en, this message translates to:
  /// **'e.g. 0 3 * * *'**
  String get hintCronExpression;

  /// No description provided for @hintRestoreConfirm.
  ///
  /// In en, this message translates to:
  /// **'Type RESTORE to confirm'**
  String get hintRestoreConfirm;

  /// No description provided for @labelAdvancedMode.
  ///
  /// In en, this message translates to:
  /// **'Advanced mode'**
  String get labelAdvancedMode;

  /// No description provided for @labelBackupList.
  ///
  /// In en, this message translates to:
  /// **'Backups'**
  String get labelBackupList;

  /// No description provided for @labelCronExpression.
  ///
  /// In en, this message translates to:
  /// **'Cron expression'**
  String get labelCronExpression;

  /// No description provided for @labelDailyTime.
  ///
  /// In en, this message translates to:
  /// **'Daily time'**
  String get labelDailyTime;

  /// No description provided for @labelDays.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get labelDays;

  /// No description provided for @labelEnableSchedule.
  ///
  /// In en, this message translates to:
  /// **'Enable scheduled backup'**
  String get labelEnableSchedule;

  /// No description provided for @labelKeepDays.
  ///
  /// In en, this message translates to:
  /// **'Keep days'**
  String get labelKeepDays;

  /// No description provided for @labelNextBackup.
  ///
  /// In en, this message translates to:
  /// **'Next backup'**
  String get labelNextBackup;

  /// No description provided for @labelRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get labelRestore;

  /// No description provided for @labelRestoreBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore backup'**
  String get labelRestoreBackup;

  /// No description provided for @labelSchedule.
  ///
  /// In en, this message translates to:
  /// **'Scheduled backup'**
  String get labelSchedule;

  /// No description provided for @labelSimpleMode.
  ///
  /// In en, this message translates to:
  /// **'Simple mode'**
  String get labelSimpleMode;

  /// No description provided for @msgBackupCreated.
  ///
  /// In en, this message translates to:
  /// **'Backup created'**
  String get msgBackupCreated;

  /// No description provided for @msgBackupCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create backup'**
  String get msgBackupCreateFailed;

  /// No description provided for @msgBackupDeleted.
  ///
  /// In en, this message translates to:
  /// **'Backup deleted'**
  String get msgBackupDeleted;

  /// No description provided for @msgBackupDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete backup'**
  String get msgBackupDeleteFailed;

  /// No description provided for @msgBackupDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Backup downloaded'**
  String get msgBackupDownloaded;

  /// No description provided for @msgDeleteBackupConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this backup?'**
  String get msgDeleteBackupConfirm;

  /// No description provided for @msgDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get msgDownloadFailed;

  /// No description provided for @msgNoBackups.
  ///
  /// In en, this message translates to:
  /// **'No backups yet'**
  String get msgNoBackups;

  /// No description provided for @msgRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed'**
  String get msgRestoreFailed;

  /// No description provided for @msgRestoreStarted.
  ///
  /// In en, this message translates to:
  /// **'Restore started. Service is restarting, please reconnect shortly.'**
  String get msgRestoreStarted;

  /// No description provided for @msgRestoreWarning.
  ///
  /// In en, this message translates to:
  /// **'This will overwrite the current database and restart the service. Type RESTORE to confirm.'**
  String get msgRestoreWarning;

  /// No description provided for @msgScheduleSaved.
  ///
  /// In en, this message translates to:
  /// **'Schedule saved'**
  String get msgScheduleSaved;

  /// No description provided for @msgScheduleSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save schedule'**
  String get msgScheduleSaveFailed;

  /// No description provided for @titleBackupRestore.
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore'**
  String get titleBackupRestore;

  /// No description provided for @msgUpgradeChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for image updates...'**
  String get msgUpgradeChecking;

  /// No description provided for @msgUpgradeUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Already up to date'**
  String get msgUpgradeUpToDate;

  /// No description provided for @msgUpgradeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Cannot compare image digests (no digest info available). Pull the latest image and recreate the container anyway?'**
  String get msgUpgradeUnknown;

  /// No description provided for @msgUpgradeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Upgrade'**
  String get msgUpgradeConfirmTitle;

  /// No description provided for @msgUpgradeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The container image will be updated to the latest version. Ports, mounts, environment variables will be preserved. The container will be briefly stopped during upgrade.'**
  String get msgUpgradeConfirmBody;

  /// No description provided for @msgUpgradeInProgress.
  ///
  /// In en, this message translates to:
  /// **'Upgrading container, please wait...'**
  String get msgUpgradeInProgress;

  /// No description provided for @msgUpgradeSuccess.
  ///
  /// In en, this message translates to:
  /// **'Container upgraded successfully'**
  String get msgUpgradeSuccess;

  /// No description provided for @msgUpgradeFail.
  ///
  /// In en, this message translates to:
  /// **'Container upgrade failed'**
  String get msgUpgradeFail;

  /// No description provided for @msgUpgradeCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get msgUpgradeCurrent;

  /// No description provided for @msgUpgradeLatest.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get msgUpgradeLatest;

  /// No description provided for @titleAiProviders.
  ///
  /// In en, this message translates to:
  /// **'AI Providers'**
  String get titleAiProviders;

  /// No description provided for @actionAddProvider.
  ///
  /// In en, this message translates to:
  /// **'Add Provider'**
  String get actionAddProvider;

  /// No description provided for @actionTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get actionTestConnection;

  /// No description provided for @actionFetchModels.
  ///
  /// In en, this message translates to:
  /// **'Fetch Models'**
  String get actionFetchModels;

  /// No description provided for @actionSaveProvider.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSaveProvider;

  /// No description provided for @msgProviderSaved.
  ///
  /// In en, this message translates to:
  /// **'Provider saved'**
  String get msgProviderSaved;

  /// No description provided for @msgProviderDeleted.
  ///
  /// In en, this message translates to:
  /// **'Provider deleted'**
  String get msgProviderDeleted;

  /// No description provided for @msgProviderDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this provider?'**
  String get msgProviderDeleteConfirm;

  /// No description provided for @msgProviderNameExists.
  ///
  /// In en, this message translates to:
  /// **'Provider name already exists'**
  String get msgProviderNameExists;

  /// No description provided for @msgTestConnecting.
  ///
  /// In en, this message translates to:
  /// **'Testing connection...'**
  String get msgTestConnecting;

  /// No description provided for @msgFetchingModels.
  ///
  /// In en, this message translates to:
  /// **'Fetching model list...'**
  String get msgFetchingModels;

  /// No description provided for @msgModelsFetchFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch models: {error}'**
  String msgModelsFetchFailed(Object error);

  /// No description provided for @msgNoModelsFound.
  ///
  /// In en, this message translates to:
  /// **'No models found. You can type manually.'**
  String get msgNoModelsFound;

  /// No description provided for @msgFetchModelsNeedInfo.
  ///
  /// In en, this message translates to:
  /// **'Fill in Base URL and API Key first, then fetch models.'**
  String get msgFetchModelsNeedInfo;

  /// No description provided for @msgNoAiProviders.
  ///
  /// In en, this message translates to:
  /// **'No providers yet. Tap the button below to add one.'**
  String get msgNoAiProviders;

  /// No description provided for @labelProviderName.
  ///
  /// In en, this message translates to:
  /// **'Provider Name'**
  String get labelProviderName;

  /// No description provided for @labelProviderType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get labelProviderType;

  /// No description provided for @labelBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get labelBaseUrl;

  /// No description provided for @labelDefaultModel.
  ///
  /// In en, this message translates to:
  /// **'Default Model'**
  String get labelDefaultModel;

  /// No description provided for @labelSelectModel.
  ///
  /// In en, this message translates to:
  /// **'Select Default Model'**
  String get labelSelectModel;

  /// No description provided for @labelModelCurrent.
  ///
  /// In en, this message translates to:
  /// **'(Current)'**
  String get labelModelCurrent;

  /// No description provided for @labelEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get labelEnabled;

  /// No description provided for @labelProviderTypeDeepseek.
  ///
  /// In en, this message translates to:
  /// **'DeepSeek'**
  String get labelProviderTypeDeepseek;

  /// No description provided for @labelProviderTypeOpenai.
  ///
  /// In en, this message translates to:
  /// **'OpenAI'**
  String get labelProviderTypeOpenai;

  /// No description provided for @labelProviderTypeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get labelProviderTypeCustom;

  /// No description provided for @labelKeyConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get labelKeyConfigured;

  /// No description provided for @labelKeyNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get labelKeyNotConfigured;

  /// No description provided for @hintBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'e.g. https://api.deepseek.com'**
  String get hintBaseUrl;

  /// No description provided for @hintApiKeyNew.
  ///
  /// In en, this message translates to:
  /// **'Enter API Key'**
  String get hintApiKeyNew;

  /// No description provided for @hintApiKeyKeep.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to keep unchanged'**
  String get hintApiKeyKeep;

  /// No description provided for @msgNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Provider name is required'**
  String get msgNameRequired;

  /// No description provided for @msgBaseUrlRequired.
  ///
  /// In en, this message translates to:
  /// **'Base URL is required'**
  String get msgBaseUrlRequired;

  /// No description provided for @msgBaseUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'Base URL must start with http(s)://'**
  String get msgBaseUrlInvalid;

  /// No description provided for @titleHermes.
  ///
  /// In en, this message translates to:
  /// **'Hermes Integration'**
  String get titleHermes;

  /// No description provided for @hermesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to hermes instances deployed on other devices (OpenAI-compatible API)'**
  String get hermesSubtitle;

  /// No description provided for @hermesStatusEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get hermesStatusEnabled;

  /// No description provided for @hermesStatusDisabled.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get hermesStatusDisabled;

  /// No description provided for @hermesStatusDisabledHint.
  ///
  /// In en, this message translates to:
  /// **'Set HERMES_BASE_URL / HERMES_API_KEY / HERMES_MODEL environment variables on the deployment, then restart the backend'**
  String get hermesStatusDisabledHint;

  /// No description provided for @hermesLabelBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Instance URL'**
  String get hermesLabelBaseUrl;

  /// No description provided for @hermesLabelModel.
  ///
  /// In en, this message translates to:
  /// **'Default model'**
  String get hermesLabelModel;

  /// No description provided for @hermesLabelApiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get hermesLabelApiKey;

  /// No description provided for @hermesApiKeyConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get hermesApiKeyConfigured;

  /// No description provided for @hermesApiKeyNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get hermesApiKeyNotConfigured;

  /// No description provided for @hermesTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get hermesTestConnection;

  /// No description provided for @hermesLabelTestResult.
  ///
  /// In en, this message translates to:
  /// **'Test result'**
  String get hermesLabelTestResult;

  /// No description provided for @hermesTestResultOk.
  ///
  /// In en, this message translates to:
  /// **'Connection successful'**
  String get hermesTestResultOk;

  /// No description provided for @hermesTestResultFail.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get hermesTestResultFail;

  /// No description provided for @hermesRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get hermesRefresh;

  /// No description provided for @hermesEnvVarNote.
  ///
  /// In en, this message translates to:
  /// **'Configuration precedence: settings saved in-app override environment variables (HERMES_BASE_URL / HERMES_API_KEY / HERMES_MODEL). Changes take effect immediately without a restart.'**
  String get hermesEnvVarNote;

  /// No description provided for @hermesEditConfig.
  ///
  /// In en, this message translates to:
  /// **'Edit config'**
  String get hermesEditConfig;

  /// No description provided for @hermesSaveConfig.
  ///
  /// In en, this message translates to:
  /// **'Save config'**
  String get hermesSaveConfig;

  /// No description provided for @hermesCancelEdit.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get hermesCancelEdit;

  /// No description provided for @hermesConfigSaved.
  ///
  /// In en, this message translates to:
  /// **'Config saved'**
  String get hermesConfigSaved;

  /// No description provided for @hermesLabelSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get hermesLabelSource;

  /// No description provided for @hermesSourceEnv.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get hermesSourceEnv;

  /// No description provided for @hermesSourceDatabase.
  ///
  /// In en, this message translates to:
  /// **'In-app settings'**
  String get hermesSourceDatabase;

  /// No description provided for @hermesUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid http(s) URL'**
  String get hermesUrlInvalid;

  /// No description provided for @hintHermesBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'e.g. https://hermes.example.com/v1'**
  String get hintHermesBaseUrl;

  /// No description provided for @hintHermesModel.
  ///
  /// In en, this message translates to:
  /// **'e.g. hermes-chat (optional)'**
  String get hintHermesModel;

  /// No description provided for @agentChatTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get agentChatTitle;

  /// No description provided for @agentChatInputHint.
  ///
  /// In en, this message translates to:
  /// **'Describe your request or give Docker commands…'**
  String get agentChatInputHint;

  /// No description provided for @agentChatSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get agentChatSend;

  /// No description provided for @agentChatSkillLabel.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get agentChatSkillLabel;

  /// No description provided for @agentChatToolLabel.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get agentChatToolLabel;

  /// No description provided for @agentChatLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load tools: {error}'**
  String agentChatLoadFailed(Object error);

  /// No description provided for @agentChatNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Request failed: {message}'**
  String agentChatNetworkError(Object message);

  /// No description provided for @agentChatEmptyTools.
  ///
  /// In en, this message translates to:
  /// **'No tools selected; default skills will be used'**
  String get agentChatEmptyTools;

  /// No description provided for @agentChatSending.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get agentChatSending;

  /// No description provided for @agentChatToolTip.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant: give Docker commands'**
  String get agentChatToolTip;

  /// No description provided for @agentChatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Online · Docker operations assistant'**
  String get agentChatSubtitle;

  /// No description provided for @agentChatYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get agentChatYou;

  /// No description provided for @agentChatClear.
  ///
  /// In en, this message translates to:
  /// **'Clear conversation'**
  String get agentChatClear;

  /// No description provided for @agentChatEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'How can I help you?'**
  String get agentChatEmptyTitle;

  /// No description provided for @agentChatEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'Describe what you need; AI will pick the right skills and tools to operate Docker'**
  String get agentChatEmptyDesc;

  /// No description provided for @agentChatLlmNotConfiguredTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant Not Configured'**
  String get agentChatLlmNotConfiguredTitle;

  /// No description provided for @agentChatLlmNotConfiguredBody.
  ///
  /// In en, this message translates to:
  /// **'The backend LLM is not configured. Configure the Hermes integration, or add an AI provider with an API Key (the default provider is preferred).'**
  String get agentChatLlmNotConfiguredBody;

  /// No description provided for @agentChatGoConfigureHermes.
  ///
  /// In en, this message translates to:
  /// **'Configure Hermes'**
  String get agentChatGoConfigureHermes;

  /// No description provided for @agentChatGoConfigureProvider.
  ///
  /// In en, this message translates to:
  /// **'Configure AI Provider'**
  String get agentChatGoConfigureProvider;

  /// No description provided for @labelDefaultProvider.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get labelDefaultProvider;

  /// No description provided for @actionSetDefaultProvider.
  ///
  /// In en, this message translates to:
  /// **'Set as default'**
  String get actionSetDefaultProvider;

  /// No description provided for @actionUnsetDefaultProvider.
  ///
  /// In en, this message translates to:
  /// **'Unset as default'**
  String get actionUnsetDefaultProvider;

  /// No description provided for @msgProviderDefaultSet.
  ///
  /// In en, this message translates to:
  /// **'Default provider updated'**
  String get msgProviderDefaultSet;

  /// No description provided for @msgProviderDefaultUnset.
  ///
  /// In en, this message translates to:
  /// **'Default provider cleared'**
  String get msgProviderDefaultUnset;

  /// No description provided for @agentDebugTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Debug Logs'**
  String get agentDebugTitle;

  /// No description provided for @agentDebugClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get agentDebugClear;

  /// No description provided for @agentDebugClearConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear debug logs?'**
  String get agentDebugClearConfirmTitle;

  /// No description provided for @agentDebugClearConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'All debug records will be deleted. This cannot be undone.'**
  String get agentDebugClearConfirmBody;

  /// No description provided for @agentDebugCleared.
  ///
  /// In en, this message translates to:
  /// **'Debug logs cleared'**
  String get agentDebugCleared;

  /// No description provided for @agentDebugClearFailed.
  ///
  /// In en, this message translates to:
  /// **'Clear failed'**
  String get agentDebugClearFailed;

  /// No description provided for @agentDebugLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load debug logs'**
  String get agentDebugLoadFailed;

  /// No description provided for @agentDebugEmpty.
  ///
  /// In en, this message translates to:
  /// **'No debug records yet'**
  String get agentDebugEmpty;

  /// No description provided for @agentDebugRetry.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get agentDebugRetry;

  /// No description provided for @agentDebugDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Debug Detail'**
  String get agentDebugDetailTitle;

  /// No description provided for @agentDebugStatusSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get agentDebugStatusSuccess;

  /// No description provided for @agentDebugStatusError.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get agentDebugStatusError;

  /// No description provided for @agentDebugSource.
  ///
  /// In en, this message translates to:
  /// **'LLM source'**
  String get agentDebugSource;

  /// No description provided for @agentDebugSourceProvider.
  ///
  /// In en, this message translates to:
  /// **'AI provider'**
  String get agentDebugSourceProvider;

  /// No description provided for @agentDebugModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get agentDebugModel;

  /// No description provided for @agentDebugTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get agentDebugTools;

  /// No description provided for @agentDebugTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get agentDebugTime;

  /// No description provided for @agentDebugError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get agentDebugError;

  /// No description provided for @agentDebugSteps.
  ///
  /// In en, this message translates to:
  /// **'Execution steps'**
  String get agentDebugSteps;

  /// No description provided for @agentDebugConversation.
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get agentDebugConversation;

  /// No description provided for @agentDebugReply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get agentDebugReply;

  /// No description provided for @agentDebugAssistant.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get agentDebugAssistant;

  /// No description provided for @agentDebugToolRole.
  ///
  /// In en, this message translates to:
  /// **'Tool'**
  String get agentDebugToolRole;

  /// No description provided for @agentDebugSystemRole.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get agentDebugSystemRole;

  /// No description provided for @agentDebugAgentStep.
  ///
  /// In en, this message translates to:
  /// **'AI step'**
  String get agentDebugAgentStep;

  /// No description provided for @agentDebugToolStep.
  ///
  /// In en, this message translates to:
  /// **'Tool result'**
  String get agentDebugToolStep;

  /// No description provided for @agentDebugToolCallName.
  ///
  /// In en, this message translates to:
  /// **'Tool call: {name}'**
  String agentDebugToolCallName(Object name);

  /// No description provided for @agentDebugToolResultName.
  ///
  /// In en, this message translates to:
  /// **'Tool result: {name}'**
  String agentDebugToolResultName(Object name);
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
