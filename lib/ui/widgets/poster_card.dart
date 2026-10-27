import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';

/// Card de poster com cantos arredondados, nota e barra de progresso.
class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.autofocus = false,
    this.width = 138,
    this.progress,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final bool autofocus;
  final double width;

  /// 0..1 quando o titulo tem progresso salvo.
  final double? progress;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final double raw = widget.progress ?? 0;
    final double progress = raw.clamp(0.0, 1.0).toDouble();

    return SizedBox(
      width: widget.width,
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (bool v) => setState(() => _focused = v),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _focused ? 1.05 : 1.0,
            duration: AppTheme.fast,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: AnimatedContainer(
                          duration: AppTheme.fast,
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: AppTheme.br,
                            border: Border.all(
                              color: _focused ? AppTheme.gold : Colors.white12,
                              width: _focused ? 2.5 : 1,
                            ),
                            boxShadow: _focused
                                ? <BoxShadow>[
                                    BoxShadow(
                                      color: AppTheme.gold.withValues(alpha: .25),
                                      blurRadius: 18,
                                    ),
                                  ]
                                : null,
                          ),
                          child: ClipRRect(
                            borderRadius: AppTheme.br,
                            child: widget.item.posterUrl.isEmpty
                                ? Container(color: AppTheme.surface)
                                : CachedNetworkImage(
                                    imageUrl: widget.item.posterUrl,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, _, _) =>
                                        Container(color: AppTheme.surface),
                                  ),
                          ),
                        ),
                      ),
                      if (widget.item.rating > 0)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: _RatingBadge(value: widget.item.rating),
                        ),
                      if (progress > 0)
                        Positioned(
                          left: 6,
                          right: 6,
                          bottom: 6,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 4,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.gold),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  widget.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text(
                  widget.item.year.isEmpty
                      ? widget.item.typeLabel
                      : '${widget.item.year} - ${widget.item.typeLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.white38),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.star_rounded, size: 11, color: AppTheme.gold),
          const SizedBox(width: 3),
          Text(
            value.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}