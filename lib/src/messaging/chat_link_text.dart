import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Displays chat text with tappable HTTP(S) links.
/// Android/iOS decide which installed app owns a verified universal/app link;
/// if no app handles it, the operating system opens the web fallback.
class ChatLinkText extends StatefulWidget {
  const ChatLinkText(
    this.text, {
    super.key,
    required this.style,
    required this.linkColor,
  });

  final String text;
  final TextStyle style;
  final Color linkColor;

  @override
  State<ChatLinkText> createState() => _ChatLinkTextState();
}

class _ChatLinkTextState extends State<ChatLinkText> {
  final List<TapGestureRecognizer> _recognizers = [];

  static final RegExp _urlPattern = RegExp(
    r'(https?://[^\s<>()]+|www\.[^\s<>()]+)',
    caseSensitive: false,
  );

  static const String _trailingPunctuation = '.,!?;:،؛؟)]}»”’';

  @override
  void didUpdateWidget(covariant ChatLinkText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _disposeRecognizers();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _openLink(String raw) async {
    final value = raw.toLowerCase().startsWith('www.')
        ? 'https://$raw'
        : raw;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return;
    }

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('تعذّر فتح الرابط.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    var cursor = 0;

    for (final match in _urlPattern.allMatches(widget.text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }

      var url = match.group(0)!;
      var suffix = '';
      while (url.isNotEmpty && _trailingPunctuation.contains(url[url.length - 1])) {
        suffix = url[url.length - 1] + suffix;
        url = url.substring(0, url.length - 1);
      }

      if (url.isNotEmpty) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _openLink(url);
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: url,
            style: TextStyle(
              color: widget.linkColor,
              decoration: TextDecoration.underline,
              decorationColor: widget.linkColor,
              fontWeight: FontWeight.w600,
            ),
            recognizer: recognizer,
          ),
        );
      }
      if (suffix.isNotEmpty) spans.add(TextSpan(text: suffix));
      cursor = match.end;
    }

    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      textDirection: Directionality.of(context),
    );
  }
}
