import 'package:flutter/material.dart';
import 'theme_extensions.dart';

class AppTheme {
  AppTheme._();

  static const double fabBottomInset = 88;

  // Arco Design light color scheme
  static const _lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF165DFF),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE8F0FF),
    onPrimaryContainer: Color(0xFF001A52),
    secondary: Color(0xFF86909C),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF2F3F5),
    onSecondaryContainer: Color(0xFF1D2129),
    tertiary: Color(0xFFFF7D00),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFFF2E5),
    onTertiaryContainer: Color(0xFF4D1B00),
    error: Color(0xFFF53F3F),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFF0F0),
    onErrorContainer: Color(0xFF5C0000),
    surface: Color(0xFFF2F3F5),
    onSurface: Color(0xFF1D2129),
    surfaceContainerHighest: Color(0xFFE5E6EB),
    surfaceContainerHigh: Color(0xFFF2F3F5),
    surfaceContainer: Color(0xFFF7F8FA),
    surfaceContainerLow: Color(0xFFFAFAFB),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    onSurfaceVariant: Color(0xFF4E5969),
    outline: Color(0xFFE5E6EB),
    outlineVariant: Color(0xFFF2F3F5),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF2F3034),
    onInverseSurface: Color(0xFFF1F1F5),
    inversePrimary: Color(0xFFA2CCFF),
  );

  // Arco Design dark color scheme
  static const _darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF4080FF),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF002B73),
    onPrimaryContainer: Color(0xFFD6E4FF),
    secondary: Color(0xFF86909C),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFF3A3A3D),
    onSecondaryContainer: Color(0xFFE5E6EB),
    tertiary: Color(0xFFFF9933),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFF5C2D00),
    onTertiaryContainer: Color(0xFFFFE4CC),
    error: Color(0xFFF76560),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFF4D0000),
    onErrorContainer: Color(0xFFFFCCCC),
    surface: Color(0xFF17171A),
    onSurface: Color(0xFFE5E6EB),
    surfaceContainerHighest: Color(0xFF3A3A3D),
    surfaceContainerHigh: Color(0xFF2E2E30),
    surfaceContainer: Color(0xFF232324),
    surfaceContainerLow: Color(0xFF1A1A1D),
    surfaceContainerLowest: Color(0xFF0D0D0F),
    onSurfaceVariant: Color(0xFF86909C),
    outline: Color(0xFF484849),
    outlineVariant: Color(0xFF2E2E30),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE5E6EB),
    onInverseSurface: Color(0xFF2F3034),
    inversePrimary: Color(0xFF165DFF),
  );

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required DockerColors dockerColors,
  }) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final textTheme = isDark
        ? Typography.material2021().white
        : Typography.material2021().black;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: 'Roboto',

      scaffoldBackgroundColor: colorScheme.surface,

      textTheme: textTheme.copyWith(
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
        bodyLarge: textTheme.bodyLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
        bodyMedium: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
        bodySmall: textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
        labelLarge: textTheme.labelLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
        labelMedium: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        labelSmall: textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLowest,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: colorScheme.outline,
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        prefixIconColor: colorScheme.onSurfaceVariant,
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        floatingLabelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withAlpha(140)),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 80,
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        selectedIconTheme: IconThemeData(
          color: colorScheme.onPrimaryContainer,
          size: 22,
        ),
        unselectedIconTheme: IconThemeData(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
          size: 22,
        ),
        selectedLabelTextStyle: TextStyle(
          color: colorScheme.onPrimaryContainer,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
          fontSize: 12,
        ),
        groupAlignment: -0.3,
        minWidth: 80,
      ),

      tabBarTheme: TabBarThemeData(
        tabAlignment: TabAlignment.start,
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorColor: colorScheme.primary,
      ),

      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 0.5,
        color: colorScheme.outlineVariant,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      listTileTheme: ListTileThemeData(
        textColor: colorScheme.onSurface,
        iconColor: colorScheme.onSurfaceVariant,
      ),

      iconTheme: IconThemeData(
        color: colorScheme.onSurfaceVariant,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        labelStyle: TextStyle(color: colorScheme.onSurface),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }
          return colorScheme.surfaceContainerLowest;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.onSurfaceVariant.withValues(alpha: 0.3);
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      extensions: [dockerColors],
    );
  }

  static ThemeData light() => _buildTheme(
        colorScheme: _lightColorScheme,
        dockerColors: DockerColors.light,
      );

  static ThemeData dark() => _buildTheme(
        colorScheme: _darkColorScheme,
        dockerColors: DockerColors.dark,
      );
}
