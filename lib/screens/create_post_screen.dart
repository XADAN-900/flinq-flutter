import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import '../widgets/preview_video.dart';
import 'story_viewer.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  static const int maxVideoBytes = 7 * 1024 * 1024;

  int _mode = 0; // 0 fotoğraf, 1 video, 2 metin
  Uint8List? _image;
  String? _videoData;
  int _videoSize = 0;
  String? _videoPath;
  final _caption = TextEditingController();
  final _text = TextEditingController();
  bool _busy = false;

  Future<void> _pickImage(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1440, maxHeight: 1800, imageQuality: 85);
    if (x == null) return;
    final b = await x.readAsBytes();
    setState(() => _image = b);
  }

  Future<void> _pickVideo(ImageSource src) async {
    final x = await ImagePicker().pickVideo(source: src, maxDuration: const Duration(seconds: 90));
    if (x == null) return;
    final len = await x.length();
    if (len > maxVideoBytes) {
      if (mounted) {
        showSnack(context, 'Video çok büyük: ${formatFileSize(len)}. En fazla 7 MB olabilir.', error: true);
      }
      return;
    }
    final b = await x.readAsBytes();
    setState(() {
      _videoData = toDataUrl(b, mimeFromName(x.name).startsWith('video/') ? mimeFromName(x.name) : 'video/mp4');
      _videoSize = len;
      _videoPath = x.path;
    });
  }

  bool get _canShare {
    switch (_mode) {
      case 0:
        return _image != null;
      case 1:
        return _videoData != null;
      default:
        return _text.text.trim().isNotEmpty;
    }
  }

  Future<void> _share() async {
    if (!_canShare || _busy) return;
    setState(() => _busy = true);
    final app = context.read<AppState>();
    try {
      if (_mode == 0) {
        await app.createPost(url: toDataUrl(_image!, 'image/jpeg'), caption: _caption.text.trim(), type: 'image');
      } else if (_mode == 1) {
        await app.createPost(url: _videoData!, caption: _caption.text.trim(), type: 'video');
      } else {
        await app.createPost(url: '', caption: _text.text.trim(), type: 'text');
      }
      if (!mounted) return;
      showSnack(context, 'Paylaşıldı 🎉');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, 'Paylaşılamadı: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        title: const Text('Yeni gönderi'),
        actions: [
          TextButton(
            onPressed: _canShare && !_busy ? _share : null,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Paylaş', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, icon: Icon(Icons.photo_outlined), label: Text('Fotoğraf')),
                ButtonSegment(value: 1, icon: Icon(Icons.videocam_outlined), label: Text('Video')),
                ButtonSegment(value: 2, icon: Icon(Icons.text_fields_rounded), label: Text('Fly')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
          ),
          if (_mode == 0) ...[
            if (_image != null)
              Stack(
                children: [
                  Image.memory(_image!, width: double.infinity, fit: BoxFit.cover),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filledTonal(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _image = null),
                    ),
                  ),
                ],
              )
            else
              _Picker(
                icon: Icons.add_photo_alternate_outlined,
                text: 'Bir fotoğraf seç',
                onGallery: () => _pickImage(ImageSource.gallery),
                onCamera: () => _pickImage(ImageSource.camera),
              ),
          ],
          if (_mode == 1) ...[
            if (_videoData != null)
              Column(
                children: [
                  SizedBox(height: 380, child: ClipRRect(borderRadius: BorderRadius.circular(16), child: PreviewVideo(key: ValueKey(_videoPath), path: _videoPath!))),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Text(formatFileSize(_videoSize), style: TextStyle(color: theme.hintColor)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => setState(() => _videoData = null),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Kaldır'),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else
              _Picker(
                icon: Icons.video_call_outlined,
                text: 'Bir video seç (en fazla 7 MB)',
                onGallery: () => _pickVideo(ImageSource.gallery),
                onCamera: () => _pickVideo(ImageSource.camera),
              ),
          ],
          if (_mode == 2)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: TextPostCard(
                        text: _text.text.isEmpty ? 'Aklından ne geçiyor?' : _text.text,
                        seed: 'preview_${_text.text.length % 6}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _text,
                    maxLines: 6,
                    minLines: 3,
                    maxLength: 500,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: 'Yaz… #etiket ve @kullanıcı kullanabilirsin'),
                  ),
                ],
              ),
            ),
          if (_mode != 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: TextField(
                controller: _caption,
                maxLines: 5,
                minLines: 2,
                maxLength: 2200,
                decoration: const InputDecoration(hintText: 'Açıklama yaz… #etiket @kullanıcı'),
              ),
            ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined, color: FColors.accent),
            title: const Text('Bunun yerine hikaye paylaş'),
            subtitle: const Text('24 saat sonra kaybolur'),
            onTap: () async {
              await addStoryFlow(context);
              if (context.mounted) Navigator.pop(context, false);
            },
          ),
        ],
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onGallery;
  final VoidCallback onCamera;
  const _Picker({required this.icon, required this.text, required this.onGallery, required this.onCamera});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      height: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor, width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: theme.hintColor),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(onPressed: onGallery, icon: const Icon(Icons.photo_library_outlined), label: const Text('Galeri')),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onCamera,
                style: OutlinedButton.styleFrom(minimumSize: const Size(64, 46)),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Kamera'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
