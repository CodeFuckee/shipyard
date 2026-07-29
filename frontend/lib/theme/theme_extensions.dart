import 'package:flutter/material.dart';

class DockerColors extends ThemeExtension<DockerColors> {
  final Color statusRunning;
  final Color statusExited;
  final Color statusCreated;
  final Color statusRestarting;
  final Color statusPaused;
  final Color sectionTitle;
  final Color labelText;
  final Color valueText;
  final Color copyButton;
  final Color inUseBorder;
  final Color inUseBackground;
  final Color mountedBorder;
  final Color mountedBackground;
  final Color fileIcon;
  final Color dirIcon;

  const DockerColors({
    required this.statusRunning,
    required this.statusExited,
    required this.statusCreated,
    required this.statusRestarting,
    required this.statusPaused,
    required this.sectionTitle,
    required this.labelText,
    required this.valueText,
    required this.copyButton,
    required this.inUseBorder,
    required this.inUseBackground,
    required this.mountedBorder,
    required this.mountedBackground,
    required this.fileIcon,
    required this.dirIcon,
  });

  // Arco Design aligned colors
  static const light = DockerColors(
    statusRunning: Color(0xFF00B42A),
    statusExited: Color(0xFFF53F3F),
    statusCreated: Color(0xFF165DFF),
    statusRestarting: Color(0xFFFF7D00),
    statusPaused: Color(0xFF86909C),
    sectionTitle: Color(0xFF165DFF),
    labelText: Color(0xFF4E5969),
    valueText: Color(0xFF1D2129),
    copyButton: Color(0xFF86909C),
    inUseBorder: Color(0xFF00B42A),
    inUseBackground: Color(0xFFE8FFEA),
    mountedBorder: Color(0xFF00B42A),
    mountedBackground: Color(0xFFE8FFEA),
    fileIcon: Color(0xFF86909C),
    dirIcon: Color(0xFF165DFF),
  );

  static const dark = DockerColors(
    statusRunning: Color(0xFF52CC6D),
    statusExited: Color(0xFFF76560),
    statusCreated: Color(0xFF4080FF),
    statusRestarting: Color(0xFFFF9933),
    statusPaused: Color(0xFF86909C),
    sectionTitle: Color(0xFF4080FF),
    labelText: Color(0xFF86909C),
    valueText: Color(0xFFE5E6EB),
    copyButton: Color(0xFF86909C),
    inUseBorder: Color(0xFF52CC6D),
    inUseBackground: Color(0xFF1A4A1A),
    mountedBorder: Color(0xFF52CC6D),
    mountedBackground: Color(0xFF1A4A1A),
    fileIcon: Color(0xFF86909C),
    dirIcon: Color(0xFF4080FF),
  );

  @override
  DockerColors copyWith({
    Color? statusRunning,
    Color? statusExited,
    Color? statusCreated,
    Color? statusRestarting,
    Color? statusPaused,
    Color? sectionTitle,
    Color? labelText,
    Color? valueText,
    Color? copyButton,
    Color? inUseBorder,
    Color? inUseBackground,
    Color? mountedBorder,
    Color? mountedBackground,
    Color? fileIcon,
    Color? dirIcon,
  }) {
    return DockerColors(
      statusRunning: statusRunning ?? this.statusRunning,
      statusExited: statusExited ?? this.statusExited,
      statusCreated: statusCreated ?? this.statusCreated,
      statusRestarting: statusRestarting ?? this.statusRestarting,
      statusPaused: statusPaused ?? this.statusPaused,
      sectionTitle: sectionTitle ?? this.sectionTitle,
      labelText: labelText ?? this.labelText,
      valueText: valueText ?? this.valueText,
      copyButton: copyButton ?? this.copyButton,
      inUseBorder: inUseBorder ?? this.inUseBorder,
      inUseBackground: inUseBackground ?? this.inUseBackground,
      mountedBorder: mountedBorder ?? this.mountedBorder,
      mountedBackground: mountedBackground ?? this.mountedBackground,
      fileIcon: fileIcon ?? this.fileIcon,
      dirIcon: dirIcon ?? this.dirIcon,
    );
  }

  @override
  DockerColors lerp(ThemeExtension<DockerColors>? other, double t) {
    if (other is! DockerColors) return this;
    return DockerColors(
      statusRunning: Color.lerp(statusRunning, other.statusRunning, t)!,
      statusExited: Color.lerp(statusExited, other.statusExited, t)!,
      statusCreated: Color.lerp(statusCreated, other.statusCreated, t)!,
      statusRestarting: Color.lerp(statusRestarting, other.statusRestarting, t)!,
      statusPaused: Color.lerp(statusPaused, other.statusPaused, t)!,
      sectionTitle: Color.lerp(sectionTitle, other.sectionTitle, t)!,
      labelText: Color.lerp(labelText, other.labelText, t)!,
      valueText: Color.lerp(valueText, other.valueText, t)!,
      copyButton: Color.lerp(copyButton, other.copyButton, t)!,
      inUseBorder: Color.lerp(inUseBorder, other.inUseBorder, t)!,
      inUseBackground: Color.lerp(inUseBackground, other.inUseBackground, t)!,
      mountedBorder: Color.lerp(mountedBorder, other.mountedBorder, t)!,
      mountedBackground: Color.lerp(mountedBackground, other.mountedBackground, t)!,
      fileIcon: Color.lerp(fileIcon, other.fileIcon, t)!,
      dirIcon: Color.lerp(dirIcon, other.dirIcon, t)!,
    );
  }
}

class DockerResourceIconColor {
  static const images = Color(0xFF00B42A);
  static const networks = Color(0xFFFF7D00);
  static const stacks = Color(0xFF165DFF);
  static const volumes = Color(0xFF4E5969);
  static const envVars = Color(0xFFF53F3F);
  static const ports = Color(0xFF722ED1);

  const DockerResourceIconColor._();
}
