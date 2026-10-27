import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ------------------------------- Intents --------------------------------------

class SeekIntent extends Intent {
  const SeekIntent(this.delta);
  final Duration delta;
}

class TogglePlayIntent extends Intent {
  const TogglePlayIntent();
}

class ShowOverlayIntent extends Intent {
  const ShowOverlayIntent();
}

class ExitPlayerIntent extends Intent {
  const ExitPlayerIntent();
}

/// Atalhos de controle remoto do player.
const Map<ShortcutActivator, Intent> kPlayerShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.select): TogglePlayIntent(),
  SingleActivator(LogicalKeyboardKey.enter): TogglePlayIntent(),
  SingleActivator(LogicalKeyboardKey.space): TogglePlayIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonA): TogglePlayIntent(),
  SingleActivator(LogicalKeyboardKey.mediaPlayPause): TogglePlayIntent(),
  SingleActivator(LogicalKeyboardKey.mediaPlay): TogglePlayIntent(),
  SingleActivator(LogicalKeyboardKey.mediaPause): TogglePlayIntent(),
  SingleActivator(LogicalKeyboardKey.mediaStop): ExitPlayerIntent(),
  SingleActivator(LogicalKeyboardKey.arrowLeft): SeekIntent(Duration(seconds: -10)),
  SingleActivator(LogicalKeyboardKey.mediaRewind): SeekIntent(Duration(seconds: -10)),
  SingleActivator(LogicalKeyboardKey.arrowRight): SeekIntent(Duration(seconds: 10)),
  SingleActivator(LogicalKeyboardKey.mediaFastForward): SeekIntent(Duration(seconds: 10)),
  SingleActivator(LogicalKeyboardKey.arrowUp): ShowOverlayIntent(),
  SingleActivator(LogicalKeyboardKey.arrowDown): ShowOverlayIntent(),
  SingleActivator(LogicalKeyboardKey.escape): ExitPlayerIntent(),
  SingleActivator(LogicalKeyboardKey.goBack): ExitPlayerIntent(),
};

// ------------------------- Botao focavel por D-Pad ----------------------------

class TvButton extends StatefulWidget {
  const TvButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.focusNode,
    this.autofocus = false,
    this.primary = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool primary;

  @override
  State<TvButton> createState() => _TvButtonState();
}

class _TvButtonState extends State<TvButton> {
  bool _focused = false;
  late final FocusNode _node = widget.focusNode ?? FocusNode(debugLabel: widget.label);

  @override
  void dispose() {
    if (widget.focusNode == null) _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final bool invert = widget.primary || _focused;

    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onFocusChange: (bool v) => setState(() => _focused = v),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _focused ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            decoration: BoxDecoration(
              color: widget.primary
                  ? (_focused ? Colors.white : accent)
                  : (_focused ? Colors.white : Colors.white10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _focused ? accent : Colors.white24,
                width: _focused ? 3 : 1,
              ),
              boxShadow: _focused
                  ? <BoxShadow>[
                      BoxShadow(color: accent.withValues(alpha: 0.55), blurRadius: 18, spreadRadius: 2),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (widget.icon != null) ...<Widget>[
                  Icon(widget.icon, size: 18, color: invert ? Colors.black : Colors.white),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    fontSize: 13,
                    color: invert ? Colors.black : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}