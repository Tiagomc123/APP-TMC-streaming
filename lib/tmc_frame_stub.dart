// =====================================================================
//  TMC - Stub da camada de embutir (Android / iOS / Desktop).
// =====================================================================

import 'package:flutter/material.dart';

const bool kFrameWeb = false;

class TmcFrame extends StatelessWidget {
  final String url;
  const TmcFrame({super.key, required this.url});

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
}

void abrirExterno(String url) {}