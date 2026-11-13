import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/messaging/chat_link_text.dart';

void main() {
  testWidgets('renders HTTP, HTTPS and www links without swallowing punctuation',
      (tester) async {
    const message = 'شاهد https://youtube.com/watch?v=abc، ثم www.example.com!';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatLinkText(
            message,
            style: TextStyle(fontSize: 16),
            linkColor: Colors.blue,
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(find.byType(RichText));
    final spans = richText.text as TextSpan;
    final links = <TextSpan>[];
    void collect(InlineSpan span) {
      if (span is TextSpan) {
        if (span.recognizer != null) links.add(span);
        for (final child in span.children ?? const <InlineSpan>[]) {
          collect(child);
        }
      }
    }

    collect(spans);
    expect(links.map((span) => span.text).toList(), [
      'https://youtube.com/watch?v=abc',
      'www.example.com',
    ]);
    expect(spans.toPlainText(), message);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replaces recognizers safely when text or inherited theme changes',
      (tester) async {
    Widget build(String message, ThemeMode mode) => MaterialApp(
          themeMode: mode,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          home: Scaffold(
            body: ChatLinkText(
              message,
              style: const TextStyle(fontSize: 16),
              linkColor: Colors.blue,
            ),
          ),
        );

    await tester.pumpWidget(build('https://one.example', ThemeMode.light));
    await tester.pumpWidget(build('https://two.example', ThemeMode.dark));
    await tester.pumpWidget(build('بدون رابط', ThemeMode.dark));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps malformed HTTP-looking text plain and links valid HTTP URLs',
      (tester) async {
    const message =
        'HTTP http://example.org/path; invalid https://?x=1 and www.example.net.';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatLinkText(
            message,
            style: TextStyle(fontSize: 16),
            linkColor: Colors.blue,
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(find.byType(RichText));
    final spans = richText.text as TextSpan;
    final links = <TextSpan>[];
    void collect(InlineSpan span) {
      if (span is TextSpan) {
        if (span.recognizer != null) links.add(span);
        for (final child in span.children ?? const <InlineSpan>[]) {
          collect(child);
        }
      }
    }

    collect(spans);
    expect(links.map((span) => span.text).toList(), [
      'http://example.org/path',
      'www.example.net',
    ]);
    expect(spans.toPlainText(), message);
    expect(tester.takeException(), isNull);
  });

}
