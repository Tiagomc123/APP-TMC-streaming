import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/focus/dpad.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';

/// Banner de destaque com auto-avanco, indicador de pagina e CTA.
/// [compact] deixa a versao baixa usada no topo das abas Filmes/Series.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({
    super.key,
    required this.items,
    required this.onOpen,
    this.label = 'DESTAQUE',
    this.height = 306,
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
  final PageController _controller = PageController(viewportFraction: 0.9);
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 7), (Timer _) {
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
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (int i = 0; i < items.length; i++)
                AnimatedContainer(
                  duration: AppTheme.fast,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _index ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _index ? AppTheme.gold : Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _slide(MediaItem item, bool autofocus) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
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
                  colors: <Color>[Color(0x22000000), Color(0xF2070A12)],
                  stops: <double>[0.15, 1],
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
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: AppTheme.gold.withValues(alpha: .95),
                      fontSize: 10,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.title,
                    maxLines: widget.compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.compact ? 16 : 20,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.star_rounded, color: AppTheme.gold, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        item.rating.toStringAsFixed(1),
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(width: 10),
                      Text(item.year,
                          style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(width: 10),
                      Text(
                        item.typeLabel,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  if (!widget.compact) ...<Widget>[
                    const SizedBox(height: 12),
                    TvButton(
                      label: 'DETALHES',
                      icon: Icons.play_circle_outline,
                      primary: true,
                      autofocus: autofocus,
                      onPressed: () => widget.onOpen(item),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.compact)
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