import 'package:flutter/material.dart';

/// Barra de progresso propria: sem os atalhos internos do Slider
/// (que sequestram as setas do D-Pad). Focavel e com seek por toque/arraste.
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.onInteraction,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onInteraction;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  bool _focused = false;
  final FocusNode _node = FocusNode(debugLabel: 'seekbar');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _seekTo(double dx, double width) {
    if (widget.duration == Duration.zero) return;
    final double ratio = (dx / width).clamp(0.0, 1.0);
    widget.onSeek(widget.duration * ratio);
    widget.onInteraction?.call();
  }

  String _fmt(Duration d) {
    final int h = d.inHours;
    final String m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final String s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final double ratio = widget.duration.inMilliseconds == 0
        ? 0
        : (widget.position.inMilliseconds / widget.duration.inMilliseconds).clamp(0.0, 1.0);

    return Focus(
      focusNode: _node,
      onFocusChange: (bool v) => setState(() => _focused = v),
      child: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints c) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (TapDownDetails d) => _seekTo(d.localPosition.dx, c.maxWidth),
            onHorizontalDragUpdate: (DragUpdateDetails d) => _seekTo(d.localPosition.dx, c.maxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Stack(
                    children: <Widget>[
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: ratio,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment(ratio * 2 - 1, 0),
                        child: Container(
                          width: _focused ? 16 : 12,
                          height: _focused ? 16 : 12,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: _focused ? 3 : 2),
                            boxShadow: _focused
                                ? <BoxShadow>[
                                    BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: 14),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(_fmt(widget.position),
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      if (_focused)
                        const Text('setas = 10s',
                            style: TextStyle(color: Colors.white38, fontSize: 11)),
                      Text(_fmt(widget.duration),
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}