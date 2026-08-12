// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Docker 监控';

  @override
  String get titleContainers => '容器';

  @override
  String get titleImages => '镜像';

  @override
  String get titleSettings => '设置';

  @override
  String get labelDockerApiUrl => 'Docker API 地址';

  @override
  String get hintIpPort => 'http://ip:port';

  @override
  String get helperDockerApiUrl => '例如：Android 模拟器使用 http://10.0.2.2:2375';

  @override
  String get buttonSave => '保存';

  @override
  String get msgSettingsSaved => '设置已保存';

  @override
  String get msgNoContainers => '暂无容器';

  @override
  String get msgRetry => '重试';

  @override
  String msgCurrentApi(Object api) {
    return '当前 API：$api';
  }

  @override
  String get buttonRefresh => '刷新';

  @override
  String get labelLanguage => '语言';

  @override
  String get optionSystem => '系统默认';

  @override
  String get optionEnglish => 'English';

  @override
  String get optionChinese => '中文';

  @override
  String get labelApiKey => 'API 密钥';

  @override
  String get hintApiKey => '输入 API 密钥（可选）';

  @override
  String get helperApiKey => '某些 Portainer/Docker 配置需要此项';

  @override
  String get labelStack => '应用栈';

  @override
  String get labelImage => '镜像';

  @override
  String get labelPorts => '端口';

  @override
  String get labelSearch => '搜索';

  @override
  String get hintSearch => '搜索容器...';

  @override
  String get labelStatusAll => '全部';

  @override
  String get labelStatus => '状态';

  @override
  String get labelFilterStatus => '按状态过滤';

  @override
  String get labelFilterStack => '按堆栈过滤';

  @override
  String get actionStart => '启动';

  @override
  String get actionStop => '停止';

  @override
  String get actionKill => '强制停止';

  @override
  String get actionRestart => '重启';

  @override
  String get actionPause => '暂停';

  @override
  String get actionResume => '恢复';

  @override
  String get actionRemove => '删除';

  @override
  String get actionUpgrade => '升级';

  @override
  String get actionCancel => '取消';

  @override
  String get labelTimezone => '时区';

  @override
  String get optionUtc => 'UTC';

  @override
  String get optionUtcPlus8 => 'UTC+8 (中国)';

  @override
  String get optionUtcPlus9 => 'UTC+9 (日本)';

  @override
  String get optionUtcMinus5 => 'UTC-5 (美东)';

  @override
  String get optionUtcPlus1 => 'UTC+1 (中欧)';

  @override
  String get msgOperationNotAllowed => '不允许对该容器进行操作';

  @override
  String get sectionServers => '服务器列表';

  @override
  String get sectionOther => '其他设置';

  @override
  String get buttonAddServer => '添加服务器';

  @override
  String get hintAddServer => '点击添加 Docker 服务器';

  @override
  String get labelServerName => '服务器名称';

  @override
  String get buttonTestConnection => '测试连接';

  @override
  String get msgConnectionSuccess => '连接成功';

  @override
  String msgConnectionFailed(Object error) {
    return '连接失败：$error';
  }

  @override
  String get msgApiKeyRequired => 'API Key 必填';

  @override
  String titleApiKeysFor(Object url) {
    return '服务器 API Key：$url';
  }

  @override
  String get msgServerAdded => '已添加服务器';

  @override
  String get msgServerUpdated => '已更新服务器';

  @override
  String get msgServerCopied => '服务器已复制';

  @override
  String get msgServerDeleted => '已删除服务器';

  @override
  String msgServerSwitched(Object name) {
    return '已切换到 $name';
  }

  @override
  String get actionEdit => '编辑';

  @override
  String get actionCopy => '复制';

  @override
  String get actionShow => '显示';

  @override
  String get actionHide => '隐藏';

  @override
  String get actionDelete => '删除';

  @override
  String get actionDeleteAll => '全部删除';

  @override
  String get msgConfirmDeleteAllContainers => '确定要删除该应用栈下的所有容器吗？此操作无法撤销。';

  @override
  String get labelActive => '当前使用';

  @override
  String get titleDashboard => '概览';

  @override
  String get labelServerInfo => '服务器信息';

  @override
  String get labelTotal => '总计';

  @override
  String get labelRunning => '运行中';

  @override
  String get labelStopped => '已停止';

  @override
  String get msgWsConnected => 'WebSocket 已连接';

  @override
  String get msgWsDisconnected => 'WebSocket 已断开';

  @override
  String get titlePullImage => '拉取镜像';

  @override
  String get labelImageName => '镜像名称';

  @override
  String get hintImageName => '例如 docker.1ms.run/emqx/emqx';

  @override
  String get labelTag => 'Tag';

  @override
  String get hintTag => '例如 latest';

  @override
  String get buttonPull => '拉取';

  @override
  String get msgImageNameRequired => '镜像名称不能为空';

  @override
  String get msgImagePullSuccess => '镜像拉取成功';

  @override
  String msgImagePullFailed(Object error) {
    return '拉取失败: $error';
  }

  @override
  String get tabDetails => '详情';

  @override
  String get tabLogs => '日志';

  @override
  String get msgNoLogs => '暂无日志';

  @override
  String get msgLoadingLogs => '加载日志中...';

  @override
  String get tabOverview => '概览';

  @override
  String get tabNetwork => '网络';

  @override
  String get tabStorage => '存储';

  @override
  String get tabEnv => '环境';

  @override
  String get tabFiles => '文件';

  @override
  String get titleNetworks => '网络';

  @override
  String get hintSearchNetworks => '搜索网络...';

  @override
  String get labelDriver => '驱动';

  @override
  String get labelScope => '范围';

  @override
  String get titleStacks => '应用栈';

  @override
  String get hintSearchStacks => '搜索应用栈...';

  @override
  String get titleVolumes => '存储卷';

  @override
  String get hintSearchVolumes => '搜索存储卷...';

  @override
  String get titleResources => '资源';

  @override
  String get titlePorts => '端口';

  @override
  String msgAvailablePorts(Object count) {
    return '可用端口数：$count';
  }

  @override
  String get msgPortRange => '端口范围';

  @override
  String get labelMountpoint => '挂载点';

  @override
  String get labelCreated => '创建时间';

  @override
  String get labelOptions => '选项';

  @override
  String get labelLabels => '标签';

  @override
  String get labelIgnoreSsl => '忽略 SSL 验证';

  @override
  String get msgErrorLoadingFiles => '加载文件失败';

  @override
  String msgFileSelected(Object name, Object size) {
    return '已选择文件: $name ($size)';
  }

  @override
  String get labelMounted => '已挂载';

  @override
  String get msgFileSaved => '文件保存成功';

  @override
  String msgErrorSavingFile(Object error) {
    return '保存文件失败: $error';
  }

  @override
  String get labelInUse => '已使用';

  @override
  String get msgContainerClosed => '容器已关闭，无法获取容器内文件';

  @override
  String get labelDownload => '下载';

  @override
  String get labelShare => '分享';

  @override
  String get msgDownloading => '下载中...';

  @override
  String get titleConfirmDelete => '确认删除';

  @override
  String get msgConfirmDeleteImage => '确定要删除此镜像吗？';

  @override
  String get titleNewVersion => '发现新版本';

  @override
  String get msgNoUpdate => '当前已是最新版本';

  @override
  String get errCheckUpdate => '检查更新失败';

  @override
  String get msgOpeningBrowserForDownload => '正在打开浏览器下载安装包...';

  @override
  String get errOpenDownloadUrl => '无法打开下载链接';

  @override
  String get actionUpdate => '立即更新';

  @override
  String get labelGithub => 'GitHub 仓库';

  @override
  String get buttonScanQr => '扫描二维码';

  @override
  String get msgScanSuccess => '扫码成功';

  @override
  String get msgInvalidQr => '二维码格式无效';

  @override
  String get buttonManualInput => '手动输入';

  @override
  String get titleRunContainer => '运行容器';

  @override
  String get labelCommand => '命令';

  @override
  String get hintCommand => '例如：docker run -d -p 80:80 nginx';

  @override
  String msgContainerStarted(Object id) {
    return '容器启动成功：$id';
  }

  @override
  String msgRunContainerFailed(Object error) {
    return '运行容器失败：$error';
  }

  @override
  String get actionRun => '运行';

  @override
  String get labelUsedByContainers => '被容器使用';

  @override
  String get filterAll => '全部';

  @override
  String get filterInUse => '使用中';

  @override
  String get filterUnused => '未使用';

  @override
  String get msgConfirmDeleteVolume => '确定要删除此存储卷吗？';

  @override
  String get msgVolumeDeleted => '存储卷删除成功';

  @override
  String msgDeleteVolumeFailed(Object error) {
    return '删除存储卷失败: $error';
  }

  @override
  String get titleNetworkDetails => '网络详情';

  @override
  String get labelSubnet => '子网';

  @override
  String get labelGateway => '网关';

  @override
  String get labelInternal => '内部';

  @override
  String get labelAttachable => '可附加';

  @override
  String get labelIngress => '入口';

  @override
  String get labelIPAM => 'IPAM';

  @override
  String get labelEnableIPv6 => '启用 IPv6';

  @override
  String get titleEnvVars => '环境变量';

  @override
  String get tabGlobal => '全局';

  @override
  String get tabGroups => '组';

  @override
  String get labelKey => '键';

  @override
  String get labelValue => '值';

  @override
  String get labelGroupName => '组名';

  @override
  String get msgVarAdded => '变量已添加';

  @override
  String get msgGroupAdded => '组已添加';

  @override
  String get msgConfirmDelete => '确定要删除吗？';

  @override
  String get actionInsertEnvVars => '插入环境变量';

  @override
  String get titleSelectEnvVars => '选择环境变量';

  @override
  String labelSelectedCount(Object count) {
    return '已选 $count 个变量';
  }

  @override
  String get labelMore => '更多';

  @override
  String get titleLogin => '登录';

  @override
  String get labelUsername => '用户名';

  @override
  String get labelPassword => '密码';

  @override
  String get hintUsername => '请输入用户名';

  @override
  String get hintPassword => '请输入密码';

  @override
  String get btnLogin => '登录';

  @override
  String get msgLoginFailed => '登录失败，请检查您的凭据';

  @override
  String get msgConnecting => '正在连接...';

  @override
  String get btnLogout => '退出登录';

  @override
  String get actionChangePassword => '修改密码';

  @override
  String get labelCurrentPassword => '当前密码';

  @override
  String get labelNewPassword => '新密码';

  @override
  String get labelConfirmNewPassword => '确认新密码';

  @override
  String get msgPasswordRequired => '请输入密码';

  @override
  String get msgPasswordMismatch => '两次输入的密码不一致';

  @override
  String get msgPasswordChanged => '密码修改成功';

  @override
  String get titleApiKeys => 'API 密钥管理';

  @override
  String get labelApiKeyName => '密钥名称';

  @override
  String get hintApiKeyName => '输入密钥名称';

  @override
  String get labelApiKeyValue => '密钥值';

  @override
  String get hintApiKeyValue => '留空则由后端自动生成';

  @override
  String get msgApiKeyCreated => 'API 密钥已创建';

  @override
  String get msgApiKeyDeleted => 'API 密钥已删除';

  @override
  String get msgApiKeyCopied => 'API 密钥已复制到剪贴板';

  @override
  String get msgCopyFailed => '复制失败，请重试';

  @override
  String get msgNoApiKeys => '暂无 API 密钥';

  @override
  String get actionCreateKey => '创建密钥';

  @override
  String get labelCreatedAt => '创建时间';

  @override
  String get labelExpiresAt => '过期时间';

  @override
  String get labelNever => '永不过期';

  @override
  String get msgConfirmDeleteApiKey => '确定要删除此 API 密钥吗？';

  @override
  String get msgNoContainerSelected => '选择一个容器查看详情';

  @override
  String get titleSystemSettings => '系统设置';

  @override
  String get titleEmailSettings => '邮件设置';

  @override
  String get labelSmtpHost => 'SMTP 服务器';

  @override
  String get labelSmtpPort => 'SMTP 端口';

  @override
  String get labelSmtpUsername => '用户名';

  @override
  String get labelSmtpPassword => '密码';

  @override
  String get labelSmtpFromEmail => '发件人邮箱';

  @override
  String get labelSmtpFromName => '发件人名称';

  @override
  String get labelSmtpUseSsl => '使用 SSL';

  @override
  String get labelSmtpUseStarttls => '使用 STARTTLS';

  @override
  String get labelSmtpTimeout => '超时时间（秒）';

  @override
  String get hintSmtpHost => '例如 smtp.gmail.com';

  @override
  String get hintSmtpPort => '例如 587';

  @override
  String get hintSmtpUsername => 'SMTP 用户名';

  @override
  String get hintSmtpPasswordKeep => '留空保持不变';

  @override
  String get hintSmtpFromEmail => '例如 noreply@example.com';

  @override
  String get hintSmtpFromName => 'Mobile Portainer';

  @override
  String get msgSmtpSaved => 'SMTP 设置已保存';

  @override
  String get titleProfileSettings => '个人信息';

  @override
  String get titlePersonalInfo => '个人信息';

  @override
  String get labelEmail => '邮箱';

  @override
  String get hintEmail => '请输入邮箱地址';

  @override
  String get hintEmailBind => '绑定邮箱后可接收通知和找回账户';

  @override
  String get actionBindEmail => '绑定邮箱';

  @override
  String get actionChangeEmail => '修改邮箱';

  @override
  String get msgEmailBound => '邮箱绑定成功';

  @override
  String get msgEmailUpdated => '邮箱更新成功';

  @override
  String get msgEmailRequired => '请输入邮箱地址';

  @override
  String get msgEmailInvalid => '请输入有效的邮箱地址';

  @override
  String get labelNotBound => '未绑定';

  @override
  String get actionSendTestEmail => '发送测试邮件';

  @override
  String get msgTestEmailSent => '测试邮件发送成功';

  @override
  String get msgTestEmailFailed => '测试邮件发送失败';

  @override
  String get msgSendingTestEmail => '正在发送测试邮件...';

  @override
  String get msgNoEmailBound => '请先绑定邮箱地址';

  @override
  String get msgNoSmtpConfig => 'SMTP 未配置，请先在系统设置中配置邮件服务';

  @override
  String get labelApiDocs => 'API 文档 (Swagger)';

  @override
  String get labelRedoc => 'API 文档 (ReDoc)';

  @override
  String get msgNoActiveServer => '未配置活跃服务器';

  @override
  String get titleProjects => '项目';

  @override
  String get hintSearchProjects => '搜索项目...';

  @override
  String get msgNoProjects => '暂无项目';

  @override
  String get labelProjectName => '项目名称';

  @override
  String get labelProjectDescription => '描述';

  @override
  String get hintProjectName => '输入项目名称';

  @override
  String get hintProjectDescription => '可选描述';

  @override
  String get labelGitUrl => 'Git 仓库 URL';

  @override
  String get hintGitUrl => '可选：从 Git 仓库克隆项目（如 https://host/user/repo.git）';

  @override
  String get actionCreateProject => '创建项目';

  @override
  String get actionSaveFile => '保存';

  @override
  String get actionBuildImage => '构建镜像';

  @override
  String get actionComposeUp => '启动';

  @override
  String get actionComposeDown => '停止';

  @override
  String get msgBuildStarted => '构建已开始';

  @override
  String get msgBuildSuccess => '构建成功';

  @override
  String get msgBuildFailed => '构建失败';

  @override
  String get msgBuildLogEmpty => '暂无构建日志';

  @override
  String get msgComposeUpSuccess => '容器启动成功';

  @override
  String get msgComposeDownSuccess => '容器已停止';

  @override
  String get titleBuildLogs => '构建日志';

  @override
  String get labelFileDockerfile => 'Dockerfile';

  @override
  String get labelFileCompose => 'docker-compose.yaml';

  @override
  String get msgProjectCreated => '项目创建成功';

  @override
  String get msgProjectDeleted => '项目已删除';

  @override
  String get msgConfirmDeleteProject => '确定要删除此项目吗？此操作将同时删除所有关联文件。';

  @override
  String get tooltipDeleteProject => '删除项目';

  @override
  String get msgSaveBeforeBuild => '请先保存文件再构建';

  @override
  String get labelBuildId => '构建 ID';

  @override
  String get labelImageId => '镜像 ID';

  @override
  String get msgSaveAll => '全部保存已保存';

  @override
  String get labelBuildTime => '构建时间';

  @override
  String get buttonConnectAdd => '网页授权添加';

  @override
  String get titleConnectAdd => '网页授权添加服务器';

  @override
  String get helperConnectAdd => '通过目标服务器的网页完成登录授权,自动获取 API 密钥并添加';

  @override
  String get errorConnectMixedContent => 'https 页面无法连接 http 目标服务器(浏览器 mixed content 限制),请将目标服务器配置为 https';

  @override
  String get msgConnectProbeFailed => '该服务器不支持网页授权添加,请手动输入';

  @override
  String get msgConnectProbing => '正在检测目标服务器是否支持网页授权…';

  @override
  String msgConnectJump(Object url) {
    return '将跳转到 $url 完成授权,登录并确认后会自动跳回并添加服务器';
  }

  @override
  String get msgConnectLaunchHint => '将打开系统浏览器完成授权,授权完成后自动返回本应用';

  @override
  String get msgConnectProcessing => '正在完成授权…';

  @override
  String msgConnectFailed(Object error) {
    return '授权添加失败:$error';
  }

  @override
  String get msgConnectDone => '授权成功,服务器已添加';

  @override
  String get actionContinue => '继续';

  @override
  String get msgConnectDupServer => '该服务器已在列表中,是否覆盖 API 密钥?';

  @override
  String get actionConfirm => '确认';

  @override
  String get buttonCreateBackup => '创建备份';

  @override
  String get hintCronExpression => '例如：0 3 * * *';

  @override
  String get hintRestoreConfirm => '输入 RESTORE 确认';

  @override
  String get labelAdvancedMode => '高级模式';

  @override
  String get labelBackupList => '备份列表';

  @override
  String get labelCronExpression => 'Cron 表达式';

  @override
  String get labelDailyTime => '每天执行时间';

  @override
  String get labelDays => '天';

  @override
  String get labelEnableSchedule => '启用定时备份';

  @override
  String get labelKeepDays => '保留天数';

  @override
  String get labelNextBackup => '下次备份';

  @override
  String get labelRestore => '恢复';

  @override
  String get labelRestoreBackup => '恢复备份';

  @override
  String get labelSchedule => '定时备份';

  @override
  String get labelSimpleMode => '简单模式';

  @override
  String get msgBackupCreated => '备份创建成功';

  @override
  String get msgBackupCreateFailed => '创建备份失败';

  @override
  String get msgBackupDeleted => '备份已删除';

  @override
  String get msgBackupDeleteFailed => '删除备份失败';

  @override
  String get msgBackupDownloaded => '备份已下载';

  @override
  String get msgDeleteBackupConfirm => '确认删除该备份？';

  @override
  String get msgDownloadFailed => '下载失败';

  @override
  String get msgNoBackups => '暂无备份';

  @override
  String get msgRestoreFailed => '恢复失败';

  @override
  String get msgRestoreStarted => '恢复已开始，服务正在重启，请稍后重新连接。';

  @override
  String get msgRestoreWarning => '恢复将覆盖当前数据库并重启服务。请输入 RESTORE 确认。';

  @override
  String get msgScheduleSaved => '定时备份配置已保存';

  @override
  String get msgScheduleSaveFailed => '保存定时配置失败';

  @override
  String get titleBackupRestore => '备份与恢复';

  @override
  String get msgUpgradeChecking => '正在检查镜像更新...';

  @override
  String get msgUpgradeUpToDate => '当前已是最新版本';

  @override
  String get msgUpgradeUnknown => '无法对比镜像摘要（容器或镜像缺少 digest 信息），是否仍要拉取最新镜像并重建容器？';

  @override
  String get msgUpgradeConfirmTitle => '确认升级';

  @override
  String get msgUpgradeConfirmBody => '将容器镜像更新到最新版本，端口、挂载、环境变量等配置保持不变，升级过程中容器会短暂停止。';

  @override
  String get msgUpgradeInProgress => '正在升级容器，请稍候...';

  @override
  String get msgUpgradeSuccess => '容器升级成功';

  @override
  String get msgUpgradeFail => '容器升级失败';

  @override
  String get msgUpgradeCurrent => '当前版本';

  @override
  String get msgUpgradeLatest => '最新版本';

  @override
  String get titleAiProviders => 'AI 供应商配置';

  @override
  String get actionAddProvider => '添加供应商';

  @override
  String get actionTestConnection => '测试连接';

  @override
  String get actionFetchModels => '获取模型列表';

  @override
  String get actionSaveProvider => '保存';

  @override
  String get msgProviderSaved => '供应商已保存';

  @override
  String get msgProviderDeleted => '供应商已删除';

  @override
  String get msgProviderDeleteConfirm => '确定删除该供应商？';

  @override
  String get msgProviderNameExists => '供应商名称已存在';

  @override
  String get msgTestConnecting => '正在测试连接...';

  @override
  String get msgFetchingModels => '正在获取模型列表...';

  @override
  String msgModelsFetchFailed(Object error) {
    return '获取模型列表失败：$error';
  }

  @override
  String get msgNoModelsFound => '未获取到模型列表，可手动输入';

  @override
  String get msgFetchModelsNeedInfo => '请先填写 Base URL 和 API Key，再获取模型列表';

  @override
  String get msgNoAiProviders => '暂无供应商，点击下方按钮添加';

  @override
  String get labelProviderName => '供应商名称';

  @override
  String get labelProviderType => '类型';

  @override
  String get labelBaseUrl => 'Base URL';

  @override
  String get labelDefaultModel => '默认模型';

  @override
  String get labelSelectModel => '选择默认模型';

  @override
  String get labelModelCurrent => '（当前）';

  @override
  String get labelEnabled => '启用';

  @override
  String get labelProviderTypeDeepseek => 'DeepSeek';

  @override
  String get labelProviderTypeOpenai => 'OpenAI';

  @override
  String get labelProviderTypeCustom => '自定义';

  @override
  String get labelKeyConfigured => '已配置';

  @override
  String get labelKeyNotConfigured => '未配置';

  @override
  String get hintBaseUrl => '例如 https://api.deepseek.com';

  @override
  String get hintApiKeyNew => '输入 API Key';

  @override
  String get hintApiKeyKeep => '留空表示不修改';

  @override
  String get msgNameRequired => '请输入供应商名称';

  @override
  String get msgBaseUrlRequired => '请输入 Base URL';

  @override
  String get msgBaseUrlInvalid => 'Base URL 必须以 http(s):// 开头';

  @override
  String get titleHermes => 'Hermes 接入';

  @override
  String get hermesSubtitle => '接入其他设备上部署的 hermes 实例（OpenAI 兼容 API）';

  @override
  String get hermesStatusEnabled => '已启用';

  @override
  String get hermesStatusDisabled => '未配置';

  @override
  String get hermesStatusDisabledHint => '请在部署环境设置 HERMES_BASE_URL / HERMES_API_KEY / HERMES_MODEL 环境变量后重启后端';

  @override
  String get hermesLabelBaseUrl => '实例地址';

  @override
  String get hermesLabelModel => '默认模型';

  @override
  String get hermesLabelApiKey => 'API Key';

  @override
  String get hermesApiKeyConfigured => '已配置';

  @override
  String get hermesApiKeyNotConfigured => '未配置';

  @override
  String get hermesTestConnection => '测试连接';

  @override
  String get hermesLabelTestResult => '测试结果';

  @override
  String get hermesTestResultOk => '连接成功';

  @override
  String get hermesTestResultFail => '连接失败';

  @override
  String get hermesRefresh => '刷新';

  @override
  String get hermesEnvVarNote => '配置来源：前端设置保存的配置优先于环境变量（HERMES_BASE_URL / HERMES_API_KEY / HERMES_MODEL），保存后立即生效无需重启';

  @override
  String get hermesEditConfig => '编辑配置';

  @override
  String get hermesSaveConfig => '保存配置';

  @override
  String get hermesCancelEdit => '取消';

  @override
  String get hermesConfigSaved => '配置已保存';

  @override
  String get hermesLabelSource => '配置来源';

  @override
  String get hermesSourceEnv => '环境变量';

  @override
  String get hermesSourceDatabase => '前端设置';

  @override
  String get hermesUrlInvalid => '请输入合法的 http(s) 地址';

  @override
  String get hintHermesBaseUrl => '例如 https://hermes.example.com/v1';

  @override
  String get hintHermesModel => '例如 hermes-chat（可留空）';

  @override
  String get agentChatTitle => 'AI 助手';

  @override
  String get agentChatInputHint => '描述需求或下达 Docker 操作指令…';

  @override
  String get agentChatSend => '发送';

  @override
  String get agentChatSkillLabel => 'Skills';

  @override
  String get agentChatToolLabel => 'Tools';

  @override
  String agentChatLoadFailed(Object error) {
    return '工具列表加载失败：$error';
  }

  @override
  String agentChatNetworkError(Object message) {
    return '请求失败：$message';
  }

  @override
  String get agentChatEmptyTools => '未选择任何工具，将使用默认 skill';

  @override
  String get agentChatSending => '思考中…';

  @override
  String get agentChatToolTip => 'AI 助手：下达 Docker 操作指令';

  @override
  String get agentChatSubtitle => '在线 · Docker 操作助手';

  @override
  String get agentChatYou => '你';

  @override
  String get agentChatClear => '清空对话';

  @override
  String get agentChatEmptyTitle => '有什么可以帮你？';

  @override
  String get agentChatEmptyDesc => '描述你的需求，AI 会选择合适的技能与工具直接操作 Docker';
}
