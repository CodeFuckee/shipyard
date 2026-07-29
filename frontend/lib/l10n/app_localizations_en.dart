// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Docker Monitor';

  @override
  String get titleContainers => 'Containers';

  @override
  String get titleImages => 'Images';

  @override
  String get titleSettings => 'Settings';

  @override
  String get labelDockerApiUrl => 'Docker API URL';

  @override
  String get hintIpPort => 'http://ip:port';

  @override
  String get helperDockerApiUrl => 'e.g., http://10.0.2.2:2375 for Android Emulator';

  @override
  String get buttonSave => 'Save';

  @override
  String get msgSettingsSaved => 'Settings saved';

  @override
  String get msgNoContainers => 'No containers found';

  @override
  String get msgRetry => 'Retry';

  @override
  String msgCurrentApi(Object api) {
    return 'Current API: $api';
  }

  @override
  String get buttonRefresh => 'Refresh';

  @override
  String get labelLanguage => 'Language';

  @override
  String get optionSystem => 'System Default';

  @override
  String get optionEnglish => 'English';

  @override
  String get optionChinese => 'Chinese';

  @override
  String get labelApiKey => 'API Key';

  @override
  String get hintApiKey => 'Enter your API Key (optional)';

  @override
  String get helperApiKey => 'Required for some Portainer/Docker setups';

  @override
  String get labelStack => 'Stack';

  @override
  String get labelImage => 'Image';

  @override
  String get labelPorts => 'Ports';

  @override
  String get labelSearch => 'Search';

  @override
  String get hintSearch => 'Search containers...';

  @override
  String get labelStatusAll => 'all';

  @override
  String get labelStatus => 'Status';

  @override
  String get labelFilterStatus => 'Filter by Status';

  @override
  String get labelFilterStack => 'Filter by Stack';

  @override
  String get actionStart => 'Start';

  @override
  String get actionStop => 'Stop';

  @override
  String get actionKill => 'Kill';

  @override
  String get actionRestart => 'Restart';

  @override
  String get actionPause => 'Pause';

  @override
  String get actionResume => 'Resume';

  @override
  String get actionRemove => 'Remove';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get labelTimezone => 'Timezone';

  @override
  String get optionUtc => 'UTC';

  @override
  String get optionUtcPlus8 => 'UTC+8 (China)';

  @override
  String get optionUtcPlus9 => 'UTC+9 (Japan)';

  @override
  String get optionUtcMinus5 => 'UTC-5 (Eastern US)';

  @override
  String get optionUtcPlus1 => 'UTC+1 (Central Europe)';

  @override
  String get msgOperationNotAllowed => 'Operation not allowed for this container';

  @override
  String get sectionServers => 'Servers';

  @override
  String get sectionOther => 'Other Settings';

  @override
  String get buttonAddServer => 'Add Server';

  @override
  String get hintAddServer => 'Tap to add a Docker server';

  @override
  String get labelServerName => 'Server Name';

  @override
  String get msgServerAdded => 'Server added';

  @override
  String get msgServerUpdated => 'Server updated';

  @override
  String get msgServerCopied => 'Server copied';

  @override
  String get msgServerDeleted => 'Server deleted';

  @override
  String msgServerSwitched(Object name) {
    return 'Switched to $name';
  }

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionShow => 'Show';

  @override
  String get actionHide => 'Hide';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionDeleteAll => 'Delete All';

  @override
  String get msgConfirmDeleteAllContainers => 'Are you sure you want to delete all containers in this stack? This action cannot be undone.';

  @override
  String get labelActive => 'Active';

  @override
  String get titleDashboard => 'Dashboard';

  @override
  String get labelServerInfo => 'Server Info';

  @override
  String get labelTotal => 'Total';

  @override
  String get labelRunning => 'Running';

  @override
  String get labelStopped => 'Stopped';

  @override
  String get msgWsConnected => 'WebSocket Connected';

  @override
  String get msgWsDisconnected => 'WebSocket Disconnected';

  @override
  String get titlePullImage => 'Pull Image';

  @override
  String get labelImageName => 'Image Name';

  @override
  String get hintImageName => 'e.g., docker.1ms.run/emqx/emqx';

  @override
  String get labelTag => 'Tag';

  @override
  String get hintTag => 'e.g., latest';

  @override
  String get buttonPull => 'Pull';

  @override
  String get msgImageNameRequired => 'Image name cannot be empty';

  @override
  String get msgImagePullSuccess => 'Image pulled successfully';

  @override
  String msgImagePullFailed(Object error) {
    return 'Pull failed: $error';
  }

  @override
  String get tabDetails => 'Details';

  @override
  String get tabLogs => 'Logs';

  @override
  String get msgNoLogs => 'No logs available';

  @override
  String get msgLoadingLogs => 'Loading logs...';

  @override
  String get tabOverview => 'Overview';

  @override
  String get tabNetwork => 'Network';

  @override
  String get tabStorage => 'Storage';

  @override
  String get tabEnv => 'Env';

  @override
  String get tabFiles => 'Files';

  @override
  String get titleNetworks => 'Networks';

  @override
  String get hintSearchNetworks => 'Search networks...';

  @override
  String get labelDriver => 'Driver';

  @override
  String get labelScope => 'Scope';

  @override
  String get titleStacks => 'Stacks';

  @override
  String get hintSearchStacks => 'Search stacks...';

  @override
  String get titleVolumes => 'Volumes';

  @override
  String get hintSearchVolumes => 'Search volumes...';

  @override
  String get titleResources => 'Resources';

  @override
  String get titlePorts => 'Ports';

  @override
  String msgAvailablePorts(Object count) {
    return 'Available Ports: $count';
  }

  @override
  String get msgPortRange => 'Port Range';

  @override
  String get labelMountpoint => 'Mountpoint';

  @override
  String get labelCreated => 'Created At';

  @override
  String get labelOptions => 'Options';

  @override
  String get labelLabels => 'Labels';

  @override
  String get labelIgnoreSsl => 'Ignore SSL Verification';

  @override
  String get msgErrorLoadingFiles => 'Error loading files';

  @override
  String msgFileSelected(Object name, Object size) {
    return 'Selected file: $name ($size)';
  }

  @override
  String get labelMounted => 'Mounted';

  @override
  String get msgFileSaved => 'File saved successfully';

  @override
  String msgErrorSavingFile(Object error) {
    return 'Error saving file: $error';
  }

  @override
  String get labelInUse => 'In Use';

  @override
  String get msgContainerClosed => 'Container is closed, cannot access files';

  @override
  String get labelDownload => 'Download';

  @override
  String get labelShare => 'Share';

  @override
  String get msgDownloading => 'Downloading...';

  @override
  String get titleConfirmDelete => 'Confirm Delete';

  @override
  String get msgConfirmDeleteImage => 'Are you sure you want to delete this image?';

  @override
  String get titleNewVersion => 'New Version Available';

  @override
  String get msgNoUpdate => 'Your app is up to date';

  @override
  String get errCheckUpdate => 'Failed to check for updates';

  @override
  String get msgOpeningBrowserForDownload => 'Opening browser to download update...';

  @override
  String get errOpenDownloadUrl => 'Failed to open download link';

  @override
  String get actionUpdate => 'Update';

  @override
  String get labelGithub => 'GitHub Repository';

  @override
  String get buttonScanQr => 'Scan QR Code';

  @override
  String get msgScanSuccess => 'Scanned successfully';

  @override
  String get msgInvalidQr => 'Invalid QR format';

  @override
  String get buttonManualInput => 'Manual Input';

  @override
  String get titleRunContainer => 'Run Container';

  @override
  String get labelCommand => 'Command';

  @override
  String get hintCommand => 'e.g., docker run -d -p 80:80 nginx';

  @override
  String msgContainerStarted(Object id) {
    return 'Container started successfully: $id';
  }

  @override
  String msgRunContainerFailed(Object error) {
    return 'Failed to run container: $error';
  }

  @override
  String get actionRun => 'Run';

  @override
  String get labelUsedByContainers => 'Used By Containers';

  @override
  String get filterAll => 'All';

  @override
  String get filterInUse => 'In Use';

  @override
  String get filterUnused => 'Unused';

  @override
  String get msgConfirmDeleteVolume => 'Are you sure you want to delete this volume?';

  @override
  String get msgVolumeDeleted => 'Volume deleted successfully';

  @override
  String msgDeleteVolumeFailed(Object error) {
    return 'Failed to delete volume: $error';
  }

  @override
  String get titleNetworkDetails => 'Network Details';

  @override
  String get labelSubnet => 'Subnet';

  @override
  String get labelGateway => 'Gateway';

  @override
  String get labelInternal => 'Internal';

  @override
  String get labelAttachable => 'Attachable';

  @override
  String get labelIngress => 'Ingress';

  @override
  String get labelIPAM => 'IPAM';

  @override
  String get labelEnableIPv6 => 'Enable IPv6';

  @override
  String get titleEnvVars => 'Environment Variables';

  @override
  String get tabGlobal => 'Global';

  @override
  String get tabGroups => 'Groups';

  @override
  String get labelKey => 'Key';

  @override
  String get labelValue => 'Value';

  @override
  String get labelGroupName => 'Group Name';

  @override
  String get msgVarAdded => 'Variable added';

  @override
  String get msgGroupAdded => 'Group added';

  @override
  String get msgConfirmDelete => 'Are you sure you want to delete?';

  @override
  String get actionInsertEnvVars => 'Insert Env Vars';

  @override
  String get titleSelectEnvVars => 'Select Env Vars';

  @override
  String labelSelectedCount(Object count) {
    return '$count variables selected';
  }

  @override
  String get labelMore => 'more';

  @override
  String get titleLogin => 'Login';

  @override
  String get labelUsername => 'Username';

  @override
  String get labelPassword => 'Password';

  @override
  String get hintUsername => 'Enter username';

  @override
  String get hintPassword => 'Enter password';

  @override
  String get btnLogin => 'Login';

  @override
  String get msgLoginFailed => 'Login failed, please check your credentials';

  @override
  String get msgConnecting => 'Connecting...';

  @override
  String get btnLogout => 'Logout';

  @override
  String get actionChangePassword => 'Change Password';

  @override
  String get labelCurrentPassword => 'Current Password';

  @override
  String get labelNewPassword => 'New Password';

  @override
  String get labelConfirmNewPassword => 'Confirm New Password';

  @override
  String get msgPasswordRequired => 'Please enter a password';

  @override
  String get msgPasswordMismatch => 'The passwords do not match';

  @override
  String get msgPasswordChanged => 'Password changed successfully';

  @override
  String get titleApiKeys => 'API Keys';

  @override
  String get labelApiKeyName => 'Key Name';

  @override
  String get hintApiKeyName => 'Enter a name for this key';

  @override
  String get labelApiKeyValue => 'Key Value';

  @override
  String get hintApiKeyValue => 'Leave empty for auto-generated key';

  @override
  String get msgApiKeyCreated => 'API Key created';

  @override
  String get msgApiKeyDeleted => 'API Key deleted';

  @override
  String get msgApiKeyCopied => 'API Key copied to clipboard';

  @override
  String get msgNoApiKeys => 'No API keys found';

  @override
  String get actionCreateKey => 'Create Key';

  @override
  String get labelCreatedAt => 'Created';

  @override
  String get labelExpiresAt => 'Expires';

  @override
  String get labelNever => 'Never';

  @override
  String get msgConfirmDeleteApiKey => 'Are you sure you want to delete this API key?';

  @override
  String get msgNoContainerSelected => 'Select a container to view details';

  @override
  String get titleSystemSettings => 'System Settings';

  @override
  String get titleEmailSettings => 'Email Settings';

  @override
  String get labelSmtpHost => 'SMTP Host';

  @override
  String get labelSmtpPort => 'SMTP Port';

  @override
  String get labelSmtpUsername => 'Username';

  @override
  String get labelSmtpPassword => 'Password';

  @override
  String get labelSmtpFromEmail => 'From Email';

  @override
  String get labelSmtpFromName => 'From Name';

  @override
  String get labelSmtpUseSsl => 'Use SSL';

  @override
  String get labelSmtpUseStarttls => 'Use STARTTLS';

  @override
  String get labelSmtpTimeout => 'Timeout (seconds)';

  @override
  String get hintSmtpHost => 'e.g., smtp.gmail.com';

  @override
  String get hintSmtpPort => 'e.g., 587';

  @override
  String get hintSmtpUsername => 'SMTP username';

  @override
  String get hintSmtpPasswordKeep => 'Leave empty to keep unchanged';

  @override
  String get hintSmtpFromEmail => 'e.g., noreply@example.com';

  @override
  String get hintSmtpFromName => 'Mobile Portainer';

  @override
  String get msgSmtpSaved => 'SMTP settings saved';

  @override
  String get titleProfileSettings => 'Personal Info';

  @override
  String get titlePersonalInfo => 'Personal Info';

  @override
  String get labelEmail => 'Email';

  @override
  String get hintEmail => 'Enter your email address';

  @override
  String get hintEmailBind => 'Bind your email to receive notifications and recover your account';

  @override
  String get actionBindEmail => 'Bind Email';

  @override
  String get actionChangeEmail => 'Change Email';

  @override
  String get msgEmailBound => 'Email bound successfully';

  @override
  String get msgEmailUpdated => 'Email updated successfully';

  @override
  String get msgEmailRequired => 'Please enter an email address';

  @override
  String get msgEmailInvalid => 'Please enter a valid email address';

  @override
  String get labelNotBound => 'Not bound';

  @override
  String get actionSendTestEmail => 'Send Test Email';

  @override
  String get msgTestEmailSent => 'Test email sent successfully';

  @override
  String get msgTestEmailFailed => 'Failed to send test email';

  @override
  String get msgSendingTestEmail => 'Sending test email...';

  @override
  String get msgNoEmailBound => 'Please bind an email address first';

  @override
  String get msgNoSmtpConfig => 'SMTP is not configured, please configure it in System Settings first';

  @override
  String get labelApiDocs => 'API Documentation (Swagger)';

  @override
  String get labelRedoc => 'API Documentation (ReDoc)';

  @override
  String get msgNoActiveServer => 'No active server configured';

  @override
  String get titleProjects => 'Projects';

  @override
  String get hintSearchProjects => 'Search projects...';

  @override
  String get msgNoProjects => 'No projects found';

  @override
  String get labelProjectName => 'Project Name';

  @override
  String get labelProjectDescription => 'Description';

  @override
  String get hintProjectName => 'Enter project name';

  @override
  String get hintProjectDescription => 'Optional description';

  @override
  String get actionCreateProject => 'Create Project';

  @override
  String get actionSaveFile => 'Save';

  @override
  String get actionBuildImage => 'Build Image';

  @override
  String get actionComposeUp => 'Up';

  @override
  String get actionComposeDown => 'Down';

  @override
  String get msgBuildStarted => 'Build started';

  @override
  String get msgBuildSuccess => 'Build completed successfully';

  @override
  String get msgBuildFailed => 'Build failed';

  @override
  String get msgBuildLogEmpty => 'No build logs yet';

  @override
  String get msgComposeUpSuccess => 'Containers started successfully';

  @override
  String get msgComposeDownSuccess => 'Containers stopped successfully';

  @override
  String get titleBuildLogs => 'Build Logs';

  @override
  String get labelFileDockerfile => 'Dockerfile';

  @override
  String get labelFileCompose => 'docker-compose.yaml';

  @override
  String get msgProjectCreated => 'Project created successfully';

  @override
  String get msgProjectDeleted => 'Project deleted';

  @override
  String get msgConfirmDeleteProject => 'Are you sure you want to delete this project? All associated files will also be deleted.';

  @override
  String get msgSaveBeforeBuild => 'Please save your files before building';

  @override
  String get labelBuildId => 'Build ID';

  @override
  String get labelImageId => 'Image ID';

  @override
  String get msgSaveAll => 'All files saved';
}
