import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';

class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.autofocus = false,
    this.width = 132,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final bool autofocus;
  final double width;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (bool v) => setState(() => _focused = v),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _focused ? 1.06 : 1.0,
            duration: const Duration(milliseconds: 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _focused ? AppTheme.gold : Colors.white12,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: widget.item.posterUrl.isEmpty
                          ? Container(color: AppTheme.surface)
                          : CachedNetworkImage(
                              imageUrl: widget.item.posterUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => Container(color: AppTheme.surface),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
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