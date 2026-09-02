import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:san_frediano_presenze/main.dart';

void main() {
  setUp(() {
    // Ogni test parte con un telefono "vuoto", senza dati salvati.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('stagione', () {
    test('parte sempre a settembre e dura un anno sportivo', () {
      expect(seasonStart.month, 9);
      expect(seasonEnd.year, seasonStart.year + 1);
      expect(seasonEnd.month, 7);
      expect(lastSeasonMonth, DateTime(seasonStart.year + 1, 6));
      expect(lastSeasonDay, DateTime(seasonStart.year + 1, 6, 30));
    });

    test('il mese di apertura sta dentro la stagione', () {
      final month = currentMonthInSeason();
      expect(month.isBefore(seasonStart), isFalse);
      expect(month.isAfter(lastSeasonMonth), isFalse);
    });
  });

  group('versione', () {
    test('quella nel codice combacia con pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final declared = RegExp(
        r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+',
        multiLine: true,
      ).firstMatch(pubspec);
      expect(declared, isNotNull, reason: 'version: mancante in pubspec.yaml');
      expect(
        appVersion,
        declared!.group(1),
        reason: 'appVersion in main.dart va tenuto uguale a pubspec.yaml, '
            'altrimenti il controllo aggiornamenti sbaglia il confronto',
      );
    });

    test('il confronto fra versioni', () {
      expect(isNewerVersion('1.3.0', '1.2.1'), isTrue);
      expect(isNewerVersion('1.10.0', '1.9.9'), isTrue);
      expect(isNewerVersion('2.0.0', '1.99.99'), isTrue);
      expect(isNewerVersion('1.2.1', '1.2.1'), isFalse);
      expect(isNewerVersion('1.2.0', '1.2.1'), isFalse);
      expect(isNewerVersion('', '1.2.1'), isFalse);
      expect(isNewerVersion('robaccia', '1.2.1'), isFalse);
    });
  });

  group('app', () {
    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();
    }

    testWidgets('si apre sul calendario', (tester) async {
      await pumpApp(tester);
      expect(find.text('TeamCheck'), findsOneWidget);
      expect(find.text('ALLENAMENTO DI OGGI'), findsOneWidget);
      expect(find.text('GESTISCI GIOCATORI'), findsOneWidget);
    });

    testWidgets('apre la gestione delle classi', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('GESTISCI GIOCATORI'));
      await tester.pumpAndSettle();
      expect(find.text('Gestisci classi'), findsOneWidget);
      expect(find.text('Aggiungi la prima classe.'), findsOneWidget);
    });

    testWidgets('apre impostazioni e backup', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Impostazioni e backup'));
      await tester.pumpAndSettle();
      expect(find.text('Impostazioni e backup'), findsOneWidget);
      expect(find.text('SALVA UNA COPIA'), findsOneWidget);
      expect(find.text('RIPRISTINA UNA COPIA'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('CONTROLLA AGGIORNAMENTI'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('CONTROLLA AGGIORNAMENTI'), findsOneWidget);
      expect(find.text('Versione installata: $appVersion'), findsOneWidget);
    });

    testWidgets('il nome allenatore finisce in intestazione', (tester) async {
      await pumpApp(tester);
      // Appena installata non c'e' nessun nome: resta la societa'.
      expect(find.text('Presenze San Frediano'), findsOneWidget);

      await tester.tap(find.byTooltip('Impostazioni e backup'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Mario Rossi');
      await tester.pumpAndSettle();
      await tester.tap(find.text('TORNA A CALENDARIO'));
      await tester.pumpAndSettle();

      expect(find.text('Allenatore Mario Rossi'), findsOneWidget);
      expect(find.text('Presenze San Frediano'), findsNothing);
    });

    testWidgets('l’appello di oggi è disponibile', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('ALLENAMENTO DI OGGI'));
      await tester.pumpAndSettle();
      expect(
        find.text('Puoi fare o correggere l\'appello anche nei giorni passati.'),
        findsOneWidget,
      );
      expect(find.text('AGGIUNGI ALLENAMENTO'), findsOneWidget);
    });

    testWidgets('l’appello non ripete il tasto gestisci', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('ALLENAMENTO DI OGGI'));
      await tester.pumpAndSettle();

      // Un allenamento aggiunto a mano esiste in qualsiasi giorno della
      // settimana, cosi' il test non dipende da quando viene eseguito.
      await tester.tap(find.text('AGGIUNGI ALLENAMENTO'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Allenamento di prova');
      await tester.tap(find.text('AGGIUNGI'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Allenamento di prova'));
      await tester.pumpAndSettle();
      expect(find.text('REGISTRA NUOVO GIOCATORE'), findsOneWidget);
      expect(find.text('GESTISCI ALLENAMENTO'), findsNothing);
    });
  });
}
