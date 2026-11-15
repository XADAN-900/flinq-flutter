import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';

enum StoryRing { none, unseen, seen }

class FAvatar extends StatelessWidget {
  final String? photo;
  final String name;
  final double size;
  final StoryRing ring;

  const FAvatar({super.key, required this.name, this.photo, this.size = 40, this.ring = StoryRing.none});

  @override
  Widget build(BuildContext context) {
    final bytes = (photo == null || photo!.isEmpty) ? null : MediaCache.bytes(photo);
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget inner = bytes != null
        ? ClipOval(
            child: Image.memory(bytes,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: (size * 3).round(),
                errorBuilder: (_, __, ___) => _initials(dark)),
          )
        : _initials(dark);
    if (ring == StoryRing.none) return inner;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: ring == StoryRing.unseen ? FColors.brand : null,
        color: ring == StoryRing.seen ? (dark ? Colors.white24 : Colors.black26) : null,
      ),
      child: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).scaffoldBackgroundColor),
        child: inner,
      ),
    );
  }

  Widget _initials(bool dark) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dark ? const Color(0xFF262A33) : const Color(0xFFE8ECED),
        ),
        child: Text(
          name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
          style: TextStyle(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w700,
            color: dark ? Colors.white70 : const Color(0xFF555B66),
          ),
        ),
      );
}

class VerifiedBadge extends StatelessWidget {
  final double size;
  const VerifiedBadge({super.key, this.size = 15});

  @override
  Widget build(BuildContext context) =>
      Padding(
        padding: const EdgeInsets.only(left: 3),
        child: Icon(Icons.verified_rounded, size: size, color: FColors.verified),
      );
}

class UserName extends StatelessWidget {
  final String name;
  final bool verified;
  final double fontSize;
  final FontWeight weight;
  const UserName(this.name,
      {super.key, this.verified = false, this.fontSize = 14, this.weight = FontWeight.w700});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: weight, fontSize: fontSize)),
          ),
          if (verified) VerifiedBadge(size: fontSize + 1),
        ],
      );
}

/// #etiket ve @kullanıcı bağlantılı metin; uzunsa "devamı" ile açılır.
class RichCaption extends StatefulWidget {
  final String? prefix;
  final String text;
  final void Function(String tag)? onHashtag;
  final void Function(String username)? onMention;
  final VoidCallback? onPrefix;
  final int trimAt;
  final TextStyle? style;

  const RichCaption({
    super.key,
    required this.text,
    this.prefix,
    this.onHashtag,
    this.onMention,
    this.onPrefix,
    this.trimAt = 140,
    this.style,
  });

  @override
  State<RichCaption> createState() => _RichCaptionState();
}

class _RichCaptionState extends State<RichCaption> {
  bool _expanded = false;
  static final RegExp _token = RegExp(r'(#[\wığüşöçİĞÜŞÖÇ]+)|(@[\wığüşöçİĞÜŞÖÇ]+)|((https?:\/\/|www\.)[^\s]+)');

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? DefaultTextStyle.of(context).style.copyWith(fontSize: 14, height: 1.35);
    final link = base.copyWith(color: FColors.verified, fontWeight: FontWeight.w500);
    var text = widget.text;
    final long = text.length > widget.trimAt && !_expanded;
    if (long) text = '${text.substring(0, widget.trimAt).trimRight()}…';
    final spans = <InlineSpan>[];
    if (widget.prefix != null) {
      spans.add(TextSpan(
        text: '${widget.prefix} ',
        style: base.copyWith(fontWeight: FontWeight.w700),
        recognizer: widget.onPrefix == null ? null : (TapGestureRecognizer()..onTap = widget.onPrefix),
      ));
    }
    var last = 0;
    for (final m in _token.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final t = m.group(0)!;
      GestureRecognizer? r;
      if (t.startsWith('#') && widget.onHashtag != null) {
        r = TapGestureRecognizer()..onTap = () => widget.onHashtag!(t.substring(1));
      } else if (t.startsWith('@') && widget.onMention != null) {
        r = TapGestureRecognizer()..onTap = () => widget.onMention!(t.substring(1));
      }
      spans.add(TextSpan(text: t, style: link, recognizer: r));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    if (long) {
      spans.add(TextSpan(
        text: ' devamı',
        style: base.copyWith(color: Theme.of(context).hintColor),
        recognizer: TapGestureRecognizer()..onTap = () => setState(() => _expanded = true),
      ));
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

/// "<strong>x</strong> gönderini beğendi" biçimindeki bildirim metnini kalın yazıyla gösterir.
class HtmlLite extends StatelessWidget {
  final String html;
  final TextStyle? style;
  final int? maxLines;
  const HtmlLite(this.html, {super.key, this.style, this.maxLines});

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final spans = <TextSpan>[];
    final re = RegExp(r'<strong>(.*?)</strong>', dotAll: true);
    var last = 0;
    for (final m in re.allMatches(html)) {
      if (m.start > last) spans.add(TextSpan(text: stripHtml(html.substring(last, m.start))));
      spans.add(TextSpan(text: stripHtml(m.group(1) ?? ''), style: const TextStyle(fontWeight: FontWeight.w700)));
      last = m.end;
    }
    if (last < html.length) spans.add(TextSpan(text: stripHtml(html.substring(last))));
    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const GradientText(this.text, {super.key, required this.style});

  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (r) => FColors.brand.createShader(r),
        blendMode: BlendMode.srcIn,
        child: Text(text, style: style),
      );
}

/// Metin gönderisi için kare gradyan kart.
class TextPostCard extends StatelessWidget {
  final String text;
  final String seed;
  final bool small;
  const TextPostCard({super.key, required this.text, required this.seed, this.small = false});

  @override
  Widget build(BuildContext context) {
    final g = FColors.textPostGradients[seed.hashCode.abs() % FColors.textPostGradients.length];
    final len = text.length;
    final fs = small ? 11.0 : (len < 60 ? 26.0 : len < 160 ? 20.0 : 16.0);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      alignment: Alignment.center,
      padding: EdgeInsets.all(small ? 8 : 28),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: small ? 6 : 14,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.white, fontSize: fs, fontWeight: FontWeight.w700, height: 1.3),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).hintColor, width: 2),
                ),
                child: Icon(icon, size: 40, color: Theme.of(context).hintColor),
              ),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
              ],
            ],
          ),
        ),
      );
}
