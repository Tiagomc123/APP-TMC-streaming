import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';

/// Banner de destaque. [compact] e a versao baixa usada no topo das abas.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({
    super.key,
    required this.items,
    required this.onOpen,
    this.label = '',
    this.height = 300,
    this.compact = false,
    this.autofocusFirst = true,
  });

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;
  final String label;
  final double height;
  final bool compact;
  final bool autofocusFirst;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final PageController _controller = PageController(viewportFraction: 0.92);
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 8), (Timer _) {
      if (!mounted || widget.items.length < 2) return;
      final int next = (_index + 1) % widget.items.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<MediaItem> items = widget.items.take(10).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: widget.height,
      child: Column(
        children: <Widget>[
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: items.length,
              onPageChanged: (int i) => setState(() => _index = i),
              itemBuilder: (BuildContext ctx, int i) =>
                  _slide(items[i], i == 0 && widget.autofocusFirst),
            ),
          ),
          if (items.length > 1) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < items.length; i++)
                  AnimatedContainer(
                    duration: AppTheme.fast,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _index ? Colors.white : Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _slide(MediaItem item, bool autofocus) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: ClipRRect(
        borderRadius: AppTheme.brLg,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (item.backdropUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: item.backdropUrl,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Container(color: AppTheme.card),
              )
            else
              Container(color: AppTheme.card),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x11000000), Color(0xF2070A12)],
                  stops: <double>[0.1, 1],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (widget.label.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        widget.label,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                          letterSpacing: 3,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  Text(
                    item.title,
                    maxLines: widget.compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.compact ? 16 : 21,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.star_rounded, color: AppTheme.gold, size: 13),
                      const SizedBox(width: 3),
                      Text(
                        item.rating.toStringAsFixed(1),
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(width: 9),
                      Text(item.year, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(width: 9),
                      Text(
                        item.typeLabel,
                        style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  autofocus: autofocus,
                  onTap: () => widget.onOpen(item),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}