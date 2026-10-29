import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Charge les vraies polices de l'app pour que les tests mesurent le texte
/// comme sur un téléphone (sinon chaque lettre est un carré).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  for (final (family, file) in [('Manrope', 'Manrope.ttf'), ('SpaceGrotesk', 'SpaceGrotesk.ttf')]) {
    final bytes = File('assets/fonts/$file').readAsBytesSync();
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
  await testMain();
}
