/// One source of truth for PROP INTELLIGENCE responsive layout selection.
///
/// Flutter web, installed PWAs, Android, iOS, Windows, macOS and Linux all
/// report their usable logical width to the widget tree. These helpers choose
/// the correct presentation from that width; no browser sniffing is required.
abstract final class ResponsiveBreakpoints {
  static const double phone = 600;
  static const double desktop = 1000;

  static bool isPhone(double width) => width < phone;

  static bool isTablet(double width) => width >= phone && width < desktop;

  static bool isDesktop(double width) => width >= desktop;
}
