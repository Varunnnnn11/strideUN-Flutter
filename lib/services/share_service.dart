import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Handles all social sharing for Strideun run summaries.
class ShareService {
  static const _channel = MethodChannel('com.example.aurarun_app/share');

  static Future<void> showShareSheet({
    required BuildContext context,
    required RunShareData data,
  }) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ShareBottomSheet(data: data),
    );
  }

  static Future<void> shareToInstagram({
    required BuildContext context,
    required RunShareData data,
    required GlobalKey cardKey,
  }) async {
    try {
      final imageFile = await _buildShareImage(
        context: context,
        data: data,
        cardKey: cardKey,
      );
      if (imageFile == null) return;

      final success = await _channel.invokeMethod<bool>('shareToInstagram', {
        'imagePath': imageFile.path,
      });

      if (success != true) {
        await _fallbackShare(imageFile);
      }
    } catch (e) {
      debugPrint('ShareService Instagram error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
              Text('Instagram not available — sharing via system...')),
        );
      }
    }
  }

  static Future<void> shareToSnapchat({
    required BuildContext context,
    required RunShareData data,
    required GlobalKey cardKey,
  }) async {
    try {
      final imageFile = await _buildShareImage(
        context: context,
        data: data,
        cardKey: cardKey,
      );
      if (imageFile == null) return;

      final success = await _channel.invokeMethod<bool>('shareToSnapchat', {
        'imagePath': imageFile.path,
        'attachmentUrl':
        'https://play.google.com/store/apps/details?id=com.example.aurarun_app',
      });

      if (success != true) {
        await _fallbackShare(imageFile);
      }
    } catch (e) {
      debugPrint('ShareService Snapchat error: $e');
      await _fallbackShare(null);
    }
  }

  static Future<void> shareGeneric({
    required BuildContext context,
    required RunShareData data,
    required GlobalKey cardKey,
  }) async {
    final imageFile = await _buildShareImage(
      context: context,
      data: data,
      cardKey: cardKey,
    );
    if (imageFile == null) return;
    await _fallbackShare(imageFile);
  }

  // ── Image building ──────────────────────────────────────────

  static Future<File?> _buildShareImage({
    required BuildContext context,
    required RunShareData data,
    required GlobalKey cardKey,
  }) async {
    final boundary =
    cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      debugPrint(
          'ShareService: cardKey has no render object — was Navigator.pop called too early?');
      return null;
    }

    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    final overlayBytes = byteData.buffer.asUint8List();

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);

    Uint8List? userPhotoBytes;
    if (picked != null) {
      userPhotoBytes = await picked.readAsBytes();
    }

    final finalBytes = userPhotoBytes != null
        ? await _compositeImages(userPhotoBytes, overlayBytes)
        : overlayBytes;

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/strideun_share_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(finalBytes);
    return file;
  }

  static Future<Uint8List> _compositeImages(
      Uint8List backgroundBytes,
      Uint8List overlayBytes,
      ) async {
    const w = 1080.0;
    const h = 1920.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

    final bgCodec = await ui.instantiateImageCodec(backgroundBytes);
    final bgFrame = await bgCodec.getNextFrame();
    final bgImg = bgFrame.image;

    final srcRect = Rect.fromLTWH(
        0, 0, bgImg.width.toDouble(), bgImg.height.toDouble());
    final dstRect =
    _coverRect(bgImg.width.toDouble(), bgImg.height.toDouble(), w, h);
    canvas.drawImageRect(bgImg, srcRect, dstRect, Paint());

    // Dark scrim — withValues(alpha:) ✅
    final scrimPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.85),
        ],
        stops: const [0.3, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), scrimPaint);

    final overlayCodec = await ui.instantiateImageCodec(overlayBytes);
    final overlayFrame = await overlayCodec.getNextFrame();
    final overlayImg = overlayFrame.image;

    final overlayW = overlayImg.width.toDouble();
    final overlayH = overlayImg.height.toDouble();
    final overlayX = (w - overlayW) / 2;
    final overlayY = h - overlayH - 120;

    canvas.drawImage(overlayImg, Offset(overlayX, overlayY), Paint());

    final picture = recorder.endRecording();
    final finalImg = await picture.toImage(w.toInt(), h.toInt());
    final data = await finalImg.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  static Rect _coverRect(
      double srcW, double srcH, double dstW, double dstH) {
    final scale =
    srcW / srcH > dstW / dstH ? dstH / srcH : dstW / srcW;
    final w = srcW * scale;
    final h = srcH * scale;
    return Rect.fromLTWH((dstW - w) / 2, (dstH - h) / 2, w, h);
  }

  static Future<void> _fallbackShare(File? file) async {
    if (file != null) {
      await Share.shareXFiles(
        [XFile(file.path)],
        text:
        'Just claimed territory on Strideun 🗺️ Claim Your World — strideun.app',
      );
    } else {
      await Share.share(
          'Just claimed territory on Strideun 🗺️ Claim Your World — strideun.app');
    }
  }
}

// ─── Data model ───────────────────────────────────────────────

class RunShareData {
  final String username;
  final String activityType;
  final double distanceKm;
  final int durationSeconds;
  final int zonesCaptured;
  final double avgPaceMinPerKm;
  final int calories;
  final int xpEarned;
  final Color trailColor;

  const RunShareData({
    required this.username,
    required this.activityType,
    required this.distanceKm,
    required this.durationSeconds,
    required this.zonesCaptured,
    required this.avgPaceMinPerKm,
    required this.calories,
    required this.xpEarned,
    required this.trailColor,
  });

  String get formattedDuration {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  String get formattedPace {
    if (avgPaceMinPerKm <= 0) return '--\'--"';
    final mins = avgPaceMinPerKm.floor();
    final secs = ((avgPaceMinPerKm - mins) * 60).round();
    return "$mins'${secs.toString().padLeft(2, '00')}\"";
  }

  String get activityEmoji {
    switch (activityType) {
      case 'RUN':   return '🏃';
      case 'WALK':  return '🚶';
      case 'CYCLE': return '🚴';
      case 'HIKE':  return '🥾';
      default:      return '🏃';
    }
  }
}

// ─── Share Bottom Sheet ───────────────────────────────────────

class _ShareBottomSheet extends StatefulWidget {
  final RunShareData data;
  const _ShareBottomSheet({required this.data});

  @override
  State<_ShareBottomSheet> createState() => _ShareBottomSheetState();
}

class _ShareBottomSheetState extends State<_ShareBottomSheet> {
  final GlobalKey _cardKey = GlobalKey();
  int _selectedCard = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0d1120),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0xFF1A2030), width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(
        0,
        16,
        0,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Share Activity',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Swipeable card previews
            SizedBox(
              height: 380,
              child: PageView(
                controller: PageController(
                  viewportFraction: 0.78,
                  initialPage: 0,
                ),
                onPageChanged: (i) => setState(() => _selectedCard = i),
                children: [
                  _CardPreviewWrapper(
                    label: 'Dark',
                    isSelected: _selectedCard == 0,
                    child: RepaintBoundary(
                      key: _selectedCard == 0 ? _cardKey : null,
                      child: RunShareCard(
                          data: widget.data,
                          variant: ShareCardVariant.dark),
                    ),
                  ),
                  _CardPreviewWrapper(
                    label: 'Transparent',
                    isSelected: _selectedCard == 1,
                    child: RepaintBoundary(
                      key: _selectedCard == 1 ? _cardKey : null,
                      child: RunShareCard(
                          data: widget.data,
                          variant: ShareCardVariant.transparent),
                    ),
                  ),
                  _CardPreviewWrapper(
                    label: 'Neon',
                    isSelected: _selectedCard == 2,
                    child: RepaintBoundary(
                      key: _selectedCard == 2 ? _cardKey : null,
                      child: RunShareCard(
                          data: widget.data,
                          variant: ShareCardVariant.neon),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            // Page dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _selectedCard == i ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _selectedCard == i
                        ? const Color(0xFFFF2D78)
                        : Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),

            const SizedBox(height: 20),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Share to',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  _BigShareButton(
                    label: 'Instagram\nStory',
                    gradient: const [Color(0xFFE1306C), Color(0xFFF77737)],
                    iconWidget: const Icon(Icons.camera_alt_rounded,
                        color: Colors.white, size: 28),
                    onTap: () => _handleShare('instagram'),
                  ),
                  const SizedBox(width: 12),
                  _BigShareButton(
                    label: 'Snapchat',
                    gradient: const [Color(0xFFFFFC00), Color(0xFFFFD700)],
                    iconWidget: const Icon(Icons.bolt_rounded,
                        color: Colors.black, size: 28),
                    labelColor: Colors.black,
                    onTap: () => _handleShare('snapchat'),
                  ),
                  const SizedBox(width: 12),
                  _BigShareButton(
                    label: 'Save\nImage',
                    gradient: const [Color(0xFF1A2030), Color(0xFF0d1120)],
                    borderColor: const Color(0xFF2D3748),
                    iconWidget: const Icon(Icons.download_rounded,
                        color: Colors.white, size: 28),
                    onTap: () => _handleShare('save'),
                  ),
                  const SizedBox(width: 12),
                  _BigShareButton(
                    label: 'More',
                    gradient: const [Color(0xFF1A2030), Color(0xFF0d1120)],
                    borderColor: const Color(0xFF2D3748),
                    iconWidget: const Icon(Icons.ios_share_rounded,
                        color: Colors.white, size: 28),
                    onTap: () => _handleShare('other'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleShare(String target) async {
    if (!mounted) return;

    final boundary =
    _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;

    final uiImage = await boundary.toImage(pixelRatio: 3.0);
    final byteData =
    await uiImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final overlayBytes = byteData.buffer.asUint8List();

    Uint8List? userPhotoBytes;
    if (target == 'instagram' || target == 'snapchat') {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) userPhotoBytes = await picked.readAsBytes();
    }

    if (mounted) Navigator.pop(context);

    final finalBytes = userPhotoBytes != null
        ? await ShareService._compositeImages(userPhotoBytes, overlayBytes)
        : overlayBytes;

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/strideun_share_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(finalBytes);

    switch (target) {
      case 'instagram':
        try {
          final success = await ShareService._channel
              .invokeMethod<bool>('shareToInstagram', {'imagePath': file.path});
          if (success != true) await ShareService._fallbackShare(file);
        } catch (_) {
          await ShareService._fallbackShare(file);
        }
        break;
      case 'snapchat':
        try {
          final success = await ShareService._channel
              .invokeMethod<bool>('shareToSnapchat', {
            'imagePath': file.path,
            'attachmentUrl':
            'https://play.google.com/store/apps/details?id=com.example.aurarun_app',
          });
          if (success != true) await ShareService._fallbackShare(file);
        } catch (_) {
          await ShareService._fallbackShare(file);
        }
        break;
      default:
        await ShareService._fallbackShare(file);
    }
  }
}

// ─── Card preview wrapper ─────────────────────────────────────

class _CardPreviewWrapper extends StatelessWidget {
  final Widget child;
  final String label;
  final bool isSelected;

  const _CardPreviewWrapper({
    required this.child,
    required this.label,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isSelected ? 1.0 : 0.92,
      duration: const Duration(milliseconds: 250),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          children: [
            Expanded(child: child),
            const SizedBox(height: 8),
            AnimatedOpacity(
              opacity: isSelected ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFFFF2D78)
                      : Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Big Share Button ─────────────────────────────────────────

class _BigShareButton extends StatelessWidget {
  final String label;
  final List<Color> gradient;
  final Widget iconWidget;
  final Color labelColor;
  final Color? borderColor;
  final VoidCallback onTap;

  const _BigShareButton({
    required this.label,
    required this.gradient,
    required this.iconWidget,
    required this.onTap,
    this.labelColor = Colors.white,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: borderColor != null
                    ? Border.all(color: borderColor!, width: 1)
                    : null,
              ),
              child: Center(child: iconWidget),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                // withValues(alpha:) ✅
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 10,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Share Card Variants ──────────────────────────────────────

enum ShareCardVariant { dark, transparent, neon }

class RunShareCard extends StatelessWidget {
  final RunShareData data;
  final ShareCardVariant variant;

  const RunShareCard({
    super.key,
    required this.data,
    this.variant = ShareCardVariant.dark,
  });

  @override
  Widget build(BuildContext context) {
    switch (variant) {
      case ShareCardVariant.transparent:
        return _buildTransparentCard();
      case ShareCardVariant.neon:
        return _buildNeonCard();
      case ShareCardVariant.dark:
        return _buildDarkCard();
    }
  }

  // ── Dark card ─────────────────────────────────────────────
  Widget _buildDarkCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0d1120), Color(0xFF080c14)],
        ),
        border: Border.all(color: const Color(0xFF1A2030), width: 1),
        boxShadow: [
          BoxShadow(
            // withValues(alpha:) ✅
            color: const Color(0xFFFF2D78).withValues(alpha: 0.15),
            blurRadius: 30,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
              gradient: LinearGradient(
                colors: [data.trailColor, const Color(0xFFFF2D78)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: _cardContent(
              logoStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5),
              distanceStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -1),
              subtextColor: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  // ── Transparent card ──────────────────────────────────────
  Widget _buildTransparentCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        // withValues(alpha:) ✅
        color: Colors.black.withValues(alpha: 0.55),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.15), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    // withValues(alpha:) ✅
                    Colors.white.withValues(alpha: 0.05),
                    Colors.white.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: _cardContent(
                logoStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5),
                distanceStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    letterSpacing: -1),
                subtextColor: Colors.white70,
                showTopBar: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Neon card ─────────────────────────────────────────────
  Widget _buildNeonCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF080c14),
        // withValues(alpha:) ✅
        border: Border.all(
            color: data.trailColor.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: data.trailColor.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: -2,
          ),
          BoxShadow(
            color: const Color(0xFFFF2D78).withValues(alpha: 0.2),
            blurRadius: 40,
            spreadRadius: -10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF2D78),
                  data.trailColor,
                  const Color(0xFF2D8BFF),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: _cardContent(
              logoStyle: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  shadows: [
                    Shadow(
                      // withValues(alpha:) ✅
                        color: data.trailColor.withValues(alpha: 0.8),
                        blurRadius: 12),
                  ]),
              distanceStyle: TextStyle(
                  color: data.trailColor,
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -1,
                  shadows: [
                    Shadow(
                        color: data.trailColor.withValues(alpha: 0.6),
                        blurRadius: 20),
                  ]),
              subtextColor: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared card content ───────────────────────────────────
  Widget _cardContent({
    required TextStyle logoStyle,
    required TextStyle distanceStyle,
    required Color subtextColor,
    bool showTopBar = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: 'stride', style: logoStyle),
                  TextSpan(
                    text: 'UN',
                    style: logoStyle.copyWith(
                      color: const Color(0xFFFF2D78),
                      shadows: [
                        Shadow(
                          // withValues(alpha:) ✅
                          color: const Color(0xFFFF2D78).withValues(alpha: 0.8),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),
                ])),
                Text(
                  'CLAIM YOUR WORLD',
                  style: TextStyle(
                    // withValues(alpha:) ✅
                    color: subtextColor.withValues(alpha: 0.6),
                    fontSize: 8,
                    letterSpacing: 2.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                // withValues(alpha:) ✅
                color: data.trailColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: data.trailColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(data.activityEmoji,
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 5),
                  Text(
                    data.activityType,
                    style: TextStyle(
                      color: data.trailColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        Text(
          '@${data.username}',
          style: TextStyle(color: subtextColor, fontSize: 11),
        ),

        const SizedBox(height: 12),

        // Distance
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(data.distanceKm.toStringAsFixed(2),
                style: distanceStyle),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text('km',
                  style: TextStyle(
                      color: subtextColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),

        const SizedBox(height: 16),
        // withValues(alpha:) ✅
        Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
        const SizedBox(height: 16),

        // Stats row
        Row(
          children: [
            _StatCell(
                label: 'DURATION',
                value: data.formattedDuration,
                subtextColor: subtextColor),
            _StatDivider(),
            _StatCell(
                label: 'PACE',
                value: data.formattedPace,
                unit: '/km',
                subtextColor: subtextColor),
            _StatDivider(),
            _StatCell(
                label: 'CALORIES',
                value: '${data.calories}',
                unit: 'kcal',
                subtextColor: subtextColor),
          ],
        ),

        const SizedBox(height: 16),

        // Territory box
        Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                // withValues(alpha:) ✅
                const Color(0xFFFF2D78).withValues(alpha: 0.1),
                data.trailColor.withValues(alpha: 0.07),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFFF2D78).withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: Color(0xFFFF2D78), width: 1.5),
                  // withValues(alpha:) ✅
                  color: const Color(0xFFFF2D78).withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${data.zonesCaptured} zones captured',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'territory claimed on the map',
                      style:
                      TextStyle(color: subtextColor, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Text(
                '+${data.xpEarned} XP',
                style: TextStyle(
                  color: data.trailColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color subtextColor;

  const _StatCell({
    required this.label,
    required this.value,
    required this.subtextColor,
    this.unit = '',
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                // withValues(alpha:) ✅
                  color: subtextColor.withValues(alpha: 0.6),
                  fontSize: 8,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(children: [
              TextSpan(
                  text: value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              if (unit.isNotEmpty)
                TextSpan(
                    text: ' $unit',
                    style: TextStyle(color: subtextColor, fontSize: 9)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 28, color: const Color(0xFF1A2030));
}