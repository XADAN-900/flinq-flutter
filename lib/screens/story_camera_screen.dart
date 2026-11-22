import 'dart:async';
import 'package:flinq/core/i18n.dart';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Hikaye kamerası (Instagram gibi): dokun = fotoğraf, basılı tut = video (en fazla 30 sn).
/// Sonuç: (dosya, video mu?)
class StoryCameraScreen extends StatefulWidget {
  const StoryCameraScreen({super.key});

  static const Duration maxVideo = Duration(seconds: 30);

  @override
  State<StoryCameraScreen> createState() => _StoryCameraScreenState();
}

class _StoryCameraScreenState extends State<StoryCameraScreen> with WidgetsBindingObserver {
  List<CameraDescription> _cams = const [];
  CameraController? _c;
  int _camIndex = 0;
  String? _error;
  bool _busy = false;
  bool _recording = false;
  FlashMode _flash = FlashMode.off;
  final _elapsed = ValueNotifier<double>(0); // 0..1
  Timer? _recTimer;
  DateTime? _recStart;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recTimer?.cancel();
    _c?.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      if (_recording) _stopVideo();
      _c = null;
      c.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _open(_camIndex);
    }
  }

  Future<void> _setup() async {
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) {
        setState(() => _error = 'Kamera bulunamadı.');
        return;
      }
      final back = _cams.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      await _open(back < 0 ? 0 : back);
    } catch (e) {
      if (mounted) setState(() => _error = 'Kamera açılamadı.');
    }
  }

  Future<void> _open(int index) async {
    final old = _c;
    _c = null;
    if (mounted) setState(() {});
    await old?.dispose();
    _camIndex = index;
    final c = CameraController(
      _cams[index],
      ResolutionPreset.high,
      enableAudio: true,
      // Hikaye videoları veritabanında saklanıyor: makul boyut için bit hızı sınırlı.
      videoBitrate: 2500000,
      audioBitrate: 96000,
    );
    try {
      await c.initialize();
      await c.setFlashMode(_flash).catchError((_) {});
    } on CameraException catch (e) {
      await c.dispose();
      if (!mounted) return;
      setState(() => _error = e.code.contains('Access') || e.code.contains('ermission')
          ? 'Kamera / mikrofon izni verilmedi. Ayarlardan FlinQ\'ya izin ver.'
          : 'Kamera açılamadı.');
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() {
      _c = c;
      _error = null;
    });
  }

  Future<void> _takePhoto() async {
    final c = _c;
    if (c == null || _busy || _recording) return;
    _busy = true;
    try {
      final f = await c.takePicture();
      if (mounted) Navigator.pop(context, (f, false));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: T('Fotoğraf çekilemedi.')));
    } finally {
      _busy = false;
    }
  }

  Future<void> _startVideo() async {
    final c = _c;
    if (c == null || _busy || _recording) return;
    _busy = true;
    try {
      await c.startVideoRecording();
      _recStart = DateTime.now();
      setState(() => _recording = true);
      _recTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        final ms = DateTime.now().difference(_recStart!).inMilliseconds;
        _elapsed.value = math.min(1, ms / StoryCameraScreen.maxVideo.inMilliseconds);
        if (ms >= StoryCameraScreen.maxVideo.inMilliseconds) _stopVideo();
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: T('Video başlatılamadı.')));
    } finally {
      _busy = false;
    }
  }

  Future<void> _stopVideo() async {
    final c = _c;
    if (c == null || !_recording) return;
    _recTimer?.cancel();
    _recording = false;
    _elapsed.value = 0;
    final tooShort = _recStart != null && DateTime.now().difference(_recStart!).inMilliseconds < 700;
    try {
      final f = await c.stopVideoRecording();
      if (!mounted) return;
      if (tooShort) {
        // Çok kısa basış: fotoğraf çek.
        setState(() {});
        await _takePhoto();
        return;
      }
      Navigator.pop(context, (f, true));
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _systemCamera() async {
    final f = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1080, imageQuality: 80);
    if (f != null && mounted) Navigator.pop(context, (f, false));
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (c != null && c.value.isInitialized)
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.previewSize?.height ?? 1080,
                  height: c.value.previewSize?.width ?? 1920,
                  child: CameraPreview(c),
                ),
              ),
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.no_photography_outlined, color: Colors.white54, size: 56),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _systemCamera, child: const T('Telefonun kamerasıyla çek')),
                ]),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    if (c != null && !_recording)
                      IconButton(
                        icon: Icon(
                          _flash == FlashMode.off
                              ? Icons.flash_off_rounded
                              : _flash == FlashMode.torch
                                  ? Icons.flashlight_on_rounded
                                  : Icons.flash_on_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () async {
                          final next = _flash == FlashMode.off
                              ? FlashMode.always
                              : _flash == FlashMode.always
                                  ? FlashMode.torch
                                  : FlashMode.off;
                          await c.setFlashMode(next).catchError((_) {});
                          setState(() => _flash = next);
                        },
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  _recording ? 'Kaydediliyor… bırakınca biter' : 'Fotoğraf için dokun · Video için basılı tut',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, shadows: [
                    Shadow(blurRadius: 6, color: Colors.black54),
                  ]),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const SizedBox(width: 48),
                      GestureDetector(
                        onTap: _takePhoto,
                        onLongPressStart: (_) => _startVideo(),
                        onLongPressEnd: (_) => _stopVideo(),
                        child: ValueListenableBuilder<double>(
                          valueListenable: _elapsed,
                          builder: (_, v, __) => SizedBox(
                            width: 86,
                            height: 86,
                            child: Stack(alignment: Alignment.center, children: [
                              SizedBox(
                                width: 86,
                                height: 86,
                                child: CircularProgressIndicator(
                                  value: _recording ? v : 0,
                                  strokeWidth: 5,
                                  color: const Color(0xFFFF3D71),
                                  backgroundColor: Colors.white70,
                                ),
                              ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: _recording ? 40 : 66,
                                height: _recording ? 40 : 66,
                                decoration: BoxDecoration(
                                  color: _recording ? const Color(0xFFFF3D71) : Colors.white,
                                  borderRadius: BorderRadius.circular(_recording ? 10 : 40),
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: (_cams.length > 1 && !_recording)
                            ? IconButton(
                                icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white, size: 30),
                                onPressed: () => _open((_camIndex + 1) % _cams.length),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
