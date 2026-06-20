import 'dart:io';

final class Console {
  Console({bool? useAnsi}) : _useAnsi = useAnsi ?? stdout.supportsAnsiEscapes;

  final bool _useAnsi;

  void heading(String message) => stdout.writeln(_style(message, '1'));

  void info(String message) => stdout.writeln(message);

  void success(String message) => stdout.writeln(_style(message, '32'));

  void warning(String message) => stderr.writeln(_style(message, '33'));

  void error(String message) => stderr.writeln(_style(message, '31'));

  void command(String executable, List<String> arguments) {
    final rendered = <String>[executable, ...arguments.map(_shellEscape)].join(' ');
    stdout.writeln(_style(r'$ ' + rendered, '36'));
  }

  String _style(String message, String code) {
    if (!_useAnsi) return message;
    return '\x1B[${code}m$message\x1B[0m';
  }

  String _shellEscape(String value) {
    if (!value.contains(RegExp(r'''[\s'"$`\\]'''))) return value;
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}
