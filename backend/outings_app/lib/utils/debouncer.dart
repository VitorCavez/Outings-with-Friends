import 'dart:async';

class Debouncer {
  Debouncer({this.ms = 400});
  final int ms;
  Timer? _t;
  void run(void Function() action) {
    _t?.cancel();
    _t = Timer(Duration(milliseconds: ms), action);
  }
  void dispose() => _t?.cancel();
}
