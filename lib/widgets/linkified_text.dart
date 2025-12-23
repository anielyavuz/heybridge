import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A widget that displays text with clickable URLs
class LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final TextAlign textAlign;

  const LinkifiedText({
    super.key,
    required this.text,
    this.style,
    this.linkStyle,
    this.textAlign = TextAlign.start,
  });

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  // URL regex pattern
  static final RegExp _urlRegex = RegExp(
    r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
    caseSensitive: false,
  );

  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Clear old recognizers
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final defaultStyle = widget.style ?? const TextStyle(color: Colors.white, fontSize: 15);
    final defaultLinkStyle = widget.linkStyle ?? defaultStyle.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.bold,
      decoration: TextDecoration.underline,
      decorationColor: Colors.white,
      decorationThickness: 1.5,
    );

    final spans = _buildTextSpans(widget.text, defaultStyle, defaultLinkStyle);

    return RichText(
      textAlign: widget.textAlign,
      text: TextSpan(children: spans),
    );
  }

  List<TextSpan> _buildTextSpans(String text, TextStyle normalStyle, TextStyle linkStyle) {
    final List<TextSpan> spans = [];
    final matches = _urlRegex.allMatches(text);

    if (matches.isEmpty) {
      return [TextSpan(text: text, style: normalStyle)];
    }

    int lastEnd = 0;

    for (final match in matches) {
      // Add text before the URL
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: normalStyle,
        ));
      }

      // Add the URL as a clickable link
      final url = match.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _launchUrl(url);
      _recognizers.add(recognizer);

      spans.add(TextSpan(
        text: url,
        style: linkStyle,
        recognizer: recognizer,
      ));

      lastEnd = match.end;
    }

    // Add remaining text after the last URL
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: normalStyle,
      ));
    }

    return spans;
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      // Don't use canLaunchUrl - it has issues on Android 11+
      // Just try to launch directly
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }
}
