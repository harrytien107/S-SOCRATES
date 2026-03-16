// Stub file for non-web platforms to avoid compilation errors
// This file simulates the JS-interop parts of dart:html/dart:js_interop

class JSObject {}

class JS {
  final String name;
  const JS(this.name);
}

class JSString {}

extension JSStringExtension on String {
  JSString get toJS => JSString();
}

class JSAny {}

class JSFunction {}

extension JSFunctionExtension on Function {
  JSFunction get toJS => JSFunction();
}

class JSPromise<T> {}

class JSNumber {}

extension JSNumberExtension on num {
  JSNumber get toJS => JSNumber();
}

class _Audio {
  _Audio();
  JSPromise<JSAny?> play() => JSPromise();
  void pause() {}
  set currentTime(JSNumber value) {}
  set onended(JSFunction? handler) {}
  set onerror(JSFunction? handler) {}
}
