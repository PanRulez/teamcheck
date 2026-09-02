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

  group('giorni della classe', () {
    test('una classe salvata prima dei giorni tiene lunedì e mercoledì', () {
      final vecchia = FootballClass.from({'id': 'c1', 'year': '2017'});
      expect(vecchia.days, defaultTrainingDays);
    });

    test('i giorni scelti sopravvivono al salvataggio', () {
      final classe = FootballClass('c1', '2018', days: {2, 4});
      final riletta = FootballClass.from(classe.json());
      expect(riletta.days, {DateTime.tuesday, DateTime.thursday});
    });

    test('l’elenco dei giorni si legge in chiaro', () {
      expect(daysLabel({3, 1}), 'Lun, Mer');
      expect(daysLabel({2, 4}), 'Mar, Gio');
      expect(daysLabel({}), 'nessun giorno fisso');
    });
  });

  group('cambio di stagione', () {
    test('un giocatore tolto resta salvato col suo nome', () {
      final player = Kid('k1', 'Mario Rossi', '2017', classId: 'c1');
      expect(player.archived, isFalse);
      player.archived = true;
      final riletto = Kid.from(player.json());
      expect(riletto.archived, isTrue);
      expect(riletto.name, 'Mario Rossi');
    });

    test('i giocatori salvati prima restano in rosa', () {
      final vecchio = Kid.from({
        'id': 'k1',
        'name': 'Mario Rossi',
        'year': '2017',
        'classId': 'c1',
      });
      expect(vecchio.archived, isFalse);
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

    testWidgets('tutto in italiano, con la domenica in fondo', (tester) async {
      await pumpApp(tester);
      final locale = MaterialLocalizations.of(
        tester.element(find.byType(CalendarPage)),
      );
      // Il calendario che esce da "sposta allenamento" prende da qui i nomi
      // dei mesi, i tasti e da che giorno comincia la settimana.
      expect(locale.cancelButtonLabel, 'Annulla');
      expect(locale.firstDayOfWeekIndex, 1, reason: 'la settimana inizia di lunedì, quindi la domenica va in fondo');
      // narrowWeekdays parte sempre da domenica: e' firstDayOfWeekIndex a
      // dire da dove il calendario comincia a leggerla.
      final first = locale.firstDayOfWeekIndex;
      expect(locale.narrowWeekdays[first], 'L');
      expect(locale.narrowWeekdays[(first + 6) % 7], 'D');
      expect(locale.formatMonthYear(DateTime(2026, 9)), contains('settembre'));
    });

    testWidgets('senza classe il calendario non inventa allenamenti', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.byIcon(Icons.sports_soccer), findsNothing);
      expect(
        find.textContaining('Nessun allenamento sul calendario'),
        findsOneWidget,
      );

      await tester.tap(find.text('GESTISCI GIOCATORI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AGGIUNGI CLASSE'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '2017');
      await tester.tap(find.text('AGGIUNGI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TORNA A CALENDARIO'));
      await tester.pumpAndSettle();

      // Creata la classe, i suoi giorni compaiono sul calendario.
      expect(find.byIcon(Icons.sports_soccer), findsWidgets);
      expect(
        find.textContaining('Nessun allenamento sul calendario'),
        findsNothing,
      );
    });

    testWidgets('i giorni si cambiano dalla classe', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('GESTISCI GIOCATORI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AGGIUNGI CLASSE'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '2017');
      await tester.tap(find.text('AGGIUNGI'));
      await tester.pumpAndSettle();

      // La prima classe prende la stella e parte con lunedì e mercoledì.
      expect(find.text('0 giocatori • PREFERITA'), findsOneWidget);
      expect(find.text('Allena: Lun, Mer'), findsOneWidget);

      await tester.tap(find.text('Classe 2017'));
      await tester.pumpAndSettle();
      expect(find.text('Giorni di allenamento'), findsOneWidget);
      await tester.tap(find.text('Mar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TORNA A CLASSI'));
      await tester.pumpAndSettle();

      expect(find.text('Allena: Lun, Mar, Mer'), findsOneWidget);
    });

    testWidgets('togliere un giocatore lo archivia, e si rimette', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.text('GESTISCI GIOCATORI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AGGIUNGI CLASSE'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '2017');
      await tester.tap(find.text('AGGIUNGI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Classe 2017'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AGGIUNGI GIOCATORE'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Mario Rossi');
      await tester.tap(find.text('AGGIUNGI'));
      await tester.pumpAndSettle();
      expect(find.text('Mario Rossi'), findsOneWidget);

      await tester.tap(find.byTooltip('Togli dalla classe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TOGLI'));
      await tester.pumpAndSettle();

      // Non sparisce: finisce fra i tolti, col nome, e si puo' rimettere.
      expect(find.text('Giocatori tolti (1)'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Mario Rossi'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Mario Rossi'), findsOneWidget);
      await tester.tap(find.byTooltip('Rimetti in rosa'));
      await tester.pumpAndSettle();
      expect(find.text('Giocatori tolti (1)'), findsNothing);
      expect(find.byTooltip('Togli dalla classe'), findsOneWidget);
    });

    testWidgets('i giocatori aggiunti all’appello partono presenti', (
      tester,
    ) async {
      Future<void> creaClasse(String anno, String giocatore) async {
        await tester.tap(find.text('AGGIUNGI CLASSE'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), anno);
        await tester.tap(find.text('AGGIUNGI'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Classe $anno'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('AGGIUNGI GIOCATORE'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), giocatore);
        await tester.tap(find.text('AGGIUNGI'));
        await tester.pumpAndSettle();
      }

      await pumpApp(tester);
      await tester.tap(find.text('GESTISCI GIOCATORI'));
      await tester.pumpAndSettle();

      // La 2017 prende la stella perche' e' la prima.
      await creaClasse('2017', 'Marco Verdi');
      // Il test deve valere in qualsiasi giorno della settimana: si assicura
      // che la classe di casa si alleni oggi.
      final oggi = shortDayNames[DateTime.now().weekday - 1];
      final casella = find.widgetWithText(FilterChip, oggi);
      if (!tester.widget<FilterChip>(casella).selected) {
        await tester.tap(casella);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('TORNA A CLASSI'));
      await tester.pumpAndSettle();
      await creaClasse('2018', 'Luca Bianchi');
      await tester.tap(find.text('TORNA A CLASSI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TORNA A CALENDARIO'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ALLENAMENTO DI OGGI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allenamento abituale'));
      await tester.pumpAndSettle();
      // L'appello parte con la sua classe.
      expect(find.text('Marco Verdi'), findsOneWidget);

      await tester.tap(find.text('ALTRI GIOCATORI'));
      await tester.pumpAndSettle();
      // La classe con cui sta gia' lavorando non viene riproposta.
      expect(find.text('Classe 2017'), findsNothing);
      await tester.tap(find.text('Classe 2018'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Luca Bianchi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONFERMA'));
      await tester.pumpAndSettle();

      // Aggiunto significa venuto: parte gia' segnato presente.
      expect(find.text('Luca Bianchi'), findsOneWidget);
      expect(find.text('Presente'), findsOneWidget);
      expect(find.text('Aggiunto a questo appello'), findsOneWidget);

      // E se e' un errore, si toglie senza lasciare il segno in giro.
      await tester.tap(
        find.descendant(
          of: find
              .ancestor(
                of: find.text('Luca Bianchi'),
                matching: find.byType(Card),
              )
              .first,
          matching: find.byTooltip('Togli da questo appello'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Luca Bianchi'), findsNothing);
      expect(find.text('Presente'), findsNothing);
      expect(find.text('Marco Verdi'), findsOneWidget);
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

    testWidgets('un allenamento aggiunto si gestisce e si elimina', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.text('ALLENAMENTO DI OGGI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AGGIUNGI ALLENAMENTO'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Porte aperte');
      await tester.tap(find.text('AGGIUNGI'));
      await tester.pumpAndSettle();
      expect(find.text('Porte aperte'), findsOneWidget);

      // Gli allenamenti aggiunti finiscono in fondo all'elenco.
      await tester.tap(find.text('GESTISCI').last);
      await tester.pumpAndSettle();
      // Uno aggiunto a mano si sposta o si elimina: "annullare" non ha senso.
      expect(find.text('SPOSTA ALLENAMENTO'), findsOneWidget);
      expect(find.text('ELIMINA ALLENAMENTO'), findsOneWidget);
      expect(find.text('ANNULLA ALLENAMENTO'), findsNothing);

      await tester.tap(find.text('ELIMINA ALLENAMENTO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ELIMINA'));
      await tester.pumpAndSettle();

      // Tornati al giorno, l'elenco si e' riletto e la sessione non c'e' piu'.
      expect(find.text('Porte aperte'), findsNothing);
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
