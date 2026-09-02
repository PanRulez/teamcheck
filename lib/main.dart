import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'TeamCheck',
    // L'app e' scritta tutta in italiano: senza questo, il calendario che
    // esce quando si sposta un allenamento sarebbe in inglese e con la
    // domenica come primo giorno, anche su un telefono italiano.
    locale: const Locale('it'),
    supportedLocales: const [Locale('it')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff087448)),
    ),
    home: const CalendarPage(),
  );
}

class Kid {
  Kid(this.id, this.name, this.year, {this.classId});
  final String id, name, year;
  String? classId;
  Map<String, dynamic> json() => {
    'id': id,
    'name': name,
    'year': year,
    'classId': classId,
  };
  factory Kid.from(Map<String, dynamic> v) => Kid(
    v['id'] as String,
    v['name'] as String,
    (v['year'] ?? '') as String,
    classId: v['classId'] as String?,
  );
}

/// Giorni di una classe appena creata: lunedi' e mercoledi', gli stessi che
/// prima erano scritti nel codice come se valessero per tutti.
const defaultTrainingDays = {DateTime.monday, DateTime.wednesday};

const shortDayNames = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];

/// Elenco dei giorni in chiaro, per i sottotitoli: "Lun, Mer".
String daysLabel(Set<int> days) {
  if (days.isEmpty) return 'nessun giorno fisso';
  final sorted = days.toList()..sort();
  return sorted.map((day) => shortDayNames[day - 1]).join(', ');
}

class FootballClass {
  FootballClass(this.id, this.year, {Set<int>? days})
    : days = {...(days ?? defaultTrainingDays)};
  final String id;
  final String year;

  /// Giorni della settimana (lunedi' = 1) in cui questa classe si allena:
  /// sono suoi, un'altra classe puo' allenarsi martedi' e giovedi'.
  Set<int> days;
  Map<String, dynamic> json() => {
    'id': id,
    'year': year,
    'days': days.toList()..sort(),
  };
  factory FootballClass.from(Map<String, dynamic> value) => FootballClass(
    value['id'] as String,
    value['year'] as String,
    // Le classi salvate prima che i giorni esistessero tengono lunedi' e
    // mercoledi', cosi' sul telefono di babbo non cambia niente.
    days: (value['days'] as List?)?.map((day) => day as int).toSet(),
  );
}

enum Mark { present, absent, justified }

/// Esito del ripristino di un backup.
enum ImportResult { done, cancelled, notABackup, damaged }

class ExtraTraining {
  ExtraTraining(this.id, this.name);
  final String id;
  final String name;
  Map<String, dynamic> json() => {'id': id, 'name': name};
  factory ExtraTraining.from(Map<String, dynamic> value) =>
      ExtraTraining(value['id'] as String, value['name'] as String);
}

class TrainingOption {
  const TrainingOption({
    required this.id,
    required this.name,
    required this.canManage,
    this.managedTrainingId,
  });
  final String id;
  final String name;
  final bool canManage;
  /// Identifica l'allenamento originale quando la sessione e' stata spostata.
  final String? managedTrainingId;
}

class ReturnButton extends StatelessWidget {
  const ReturnButton({super.key, required this.destination});
  final String destination;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: TextButton.icon(
      onPressed: () => Navigator.maybePop(context),
      icon: const Icon(Icons.arrow_back, size: 25),
      label: Text(
        'TORNA A $destination',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis,
      ),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    ),
  );
}

/// La stagione va da settembre a giugno. Da agosto in poi si guarda gia' alla
/// stagione nuova, cosi' l'app non smette di funzionare a fine anno sportivo.
DateTime get seasonStart {
  final today = DateTime.now();
  return DateTime(today.month >= 8 ? today.year : today.year - 1, 9);
}

/// Primo giorno fuori stagione (escluso).
DateTime get seasonEnd => DateTime(seasonStart.year + 1, 7);

/// Ultimo mese che si puo' aprire nel calendario.
DateTime get lastSeasonMonth => DateTime(seasonStart.year + 1, 6);

/// Ultimo giorno scegliebile quando si sposta un allenamento.
DateTime get lastSeasonDay => DateTime(seasonStart.year + 1, 6, 30);

/// Mese da mostrare all'apertura, sempre dentro la stagione in corso.
DateTime currentMonthInSeason() {
  final today = DateTime.now();
  final month = DateTime(today.year, today.month);
  if (month.isBefore(seasonStart)) return seasonStart;
  if (month.isAfter(lastSeasonMonth)) return lastSeasonMonth;
  return month;
}


/// Repo GitHub da cui arrivano gli aggiornamenti: l'app guarda l'ultima
/// release pubblicata e ci cerca dentro l'APK.
const updateRepo = 'PanRulez/teamcheck';

/// Versione di questa build. Deve restare uguale a quella in pubspec.yaml:
/// c'e' un test che fallisce se le due si scollano.
const appVersion = '1.5.1';

enum UpdateStatus { upToDate, available, failed }

class UpdateResult {
  const UpdateResult(this.status, {this.version, this.url});
  final UpdateStatus status;
  final String? version;
  final String? url;
}

/// True se [candidate] e' piu' recente di [current] (es. '1.10.0' > '1.9.3').
bool isNewerVersion(String candidate, String current) {
  int part(String version, int index) {
    final pieces = version.split('.');
    if (index >= pieces.length) return 0;
    return int.tryParse(pieces[index].trim()) ?? 0;
  }

  for (var index = 0; index < 3; index++) {
    final mine = part(current, index);
    final theirs = part(candidate, index);
    if (theirs != mine) return theirs > mine;
  }
  return false;
}

/// Chiede a GitHub qual e' l'ultima versione pubblicata.
Future<UpdateResult> checkForUpdate() async {
  try {
    final response = await http
        .get(
          Uri.https('api.github.com', '/repos/$updateRepo/releases/latest'),
          headers: const {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      return const UpdateResult(UpdateStatus.failed);
    }
    final release = jsonDecode(response.body) as Map<String, dynamic>;
    // I tag delle release si scrivono di solito con la v davanti: v1.3.0.
    final version = (release['tag_name'] as String? ?? '').replaceFirst(
      RegExp('^v', caseSensitive: false),
      '',
    );
    String? apk;
    for (final asset in (release['assets'] as List? ?? const [])) {
      final file = asset as Map<String, dynamic>;
      if ((file['name'] as String? ?? '').toLowerCase().endsWith('.apk')) {
        apk = file['browser_download_url'] as String?;
        break;
      }
    }
    if (version.isEmpty || apk == null) {
      return const UpdateResult(UpdateStatus.failed);
    }
    if (!isNewerVersion(version, appVersion)) {
      return const UpdateResult(UpdateStatus.upToDate);
    }
    return UpdateResult(UpdateStatus.available, version: version, url: apk);
  } catch (_) {
    return const UpdateResult(UpdateStatus.failed);
  }
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime month = currentMonthInSeason();
  List<Kid> kids = [];
  List<FootballClass> classes = [];
  Map<String, Map<String, Mark>> attendance = {};
  Map<String, bool> trainingChanges = {};
  Map<String, String> movedTraining = {};
  Map<String, List<ExtraTraining>> extraTrainings = {};
  Map<String, List<String>> selectedPlayers = {};
  String? favoriteClassId;
  String coachName = '';
  bool loading = true;
  String key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    var migratedLegacyMoves = false;
    var migratedExistingClasses = false;
    kids = [];
    classes = [];
    attendance = {};
    trainingChanges = {};
    movedTraining = {};
    extraTrainings = {};
    selectedPlayers = {};
    favoriteClassId = null;
    coachName = '';
    final text = await SharedPreferencesAsync().getString('sanfrediano');
    if (text != null) {
      final root = jsonDecode(text) as Map<String, dynamic>;
      kids = (root['kids'] as List)
          .map((e) => Kid.from(e as Map<String, dynamic>))
          .toList();
      final savedClasses = root['classes'] as List<dynamic>?;
      if (savedClasses != null) {
        classes = savedClasses
            .map((value) => FootballClass.from(value as Map<String, dynamic>))
            .toList();
      } else {
        _createClassesForExistingPlayers();
        migratedExistingClasses = true;
      }
      (root['attendance'] as Map<String, dynamic>).forEach((day, values) {
        attendance[day] = (values as Map<String, dynamic>).map(
          (id, value) => MapEntry(id, Mark.values.byName(value as String)),
        );
      });
      final savedTraining = root['trainingChanges'] as Map<String, dynamic>?;
      if (savedTraining != null) {
        trainingChanges = savedTraining.map(
          (day, value) => MapEntry(day, value as bool),
        );
      }
      final savedMoves = root['movedTraining'] as Map<String, dynamic>?;
      if (savedMoves != null) {
        movedTraining = savedMoves.map(
          (from, to) => MapEntry(from, to as String),
        );
      } else {
        _migrateLegacyMoves();
        migratedLegacyMoves = true;
      }
      final savedExtras = root['extraTrainings'] as Map<String, dynamic>?;
      if (savedExtras != null) {
        extraTrainings = savedExtras.map(
          (day, values) => MapEntry(
            day,
            (values as List)
                .map(
                  (value) => ExtraTraining.from(value as Map<String, dynamic>),
                )
                .toList(),
          ),
        );
      }
      final savedSelected = root['selectedPlayers'] as Map<String, dynamic>?;
      if (savedSelected != null) {
        selectedPlayers = savedSelected.map(
          (session, players) =>
              MapEntry(session, List<String>.from(players as List)),
        );
      }
      favoriteClassId = root['favoriteClassId'] as String?;
      coachName = (root['coachName'] as String?) ?? '';
    }
    if (const bool.fromEnvironment('LOAD_TEST_DATA')) {
      await addTestData();
    }
    if (migratedLegacyMoves || migratedExistingClasses) await save();
    if (mounted) setState(() => loading = false);
  }

  Future<void> addTestData() async {
    for (final year in ['2017', '2018', '2019']) {
      final footballClass = classes.firstWhere(
        (group) => group.year == year,
        orElse: () {
          final group = FootballClass('test-class-$year', year);
          classes.add(group);
          return group;
        },
      );
      for (var number = 1; number <= 5; number++) {
        final id = 'test-$year-$number';
        if (kids.any((player) => player.id == id)) continue;
        kids.add(
          Kid(
            id,
            'Giocatore $year $number',
            year,
            classId: footballClass.id,
          ),
        );
      }
    }
    await save();
  }

  Map<String, dynamic> data() {
    return {
      'kids': kids.map((e) => e.json()).toList(),
      'classes': classes.map((value) => value.json()).toList(),
      'attendance': attendance.map(
        (d, values) =>
            MapEntry(d, values.map((id, mark) => MapEntry(id, mark.name))),
      ),
      'trainingChanges': trainingChanges,
      'movedTraining': movedTraining,
      'extraTrainings': extraTrainings.map(
        (day, sessions) =>
            MapEntry(day, sessions.map((session) => session.json()).toList()),
      ),
      'selectedPlayers': selectedPlayers,
      'favoriteClassId': favoriteClassId,
      'coachName': coachName,
    };
  }

  Future<void> save() =>
      SharedPreferencesAsync().setString('sanfrediano', jsonEncode(data()));

  /// Manda il backup completo (WhatsApp, Drive, mail...) come file JSON.
  Future<void> exportBackup() async {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            utf8.encode(jsonEncode(data())),
            mimeType: 'application/json',
          ),
        ],
        fileNameOverrides: ['teamcheck-presenze-${key(DateTime.now())}.json'],
        title: 'Backup presenze',
        subject: 'Backup presenze TeamCheck',
      ),
    );
  }

  /// Rimpiazza tutti i dati con quelli di un backup scelto dal telefono.
  Future<ImportResult> importBackup() async {
    final choice = await FilePicker.pickFiles(
      dialogTitle: 'Scegli il file di backup',
    );
    if (choice.isEmpty) return ImportResult.cancelled;
    final String text;
    try {
      text = utf8.decode(await choice.first.readAsBytes());
      final root = jsonDecode(text) as Map<String, dynamic>;
      if (root['kids'] is! List || root['attendance'] is! Map) {
        return ImportResult.notABackup;
      }
    } catch (_) {
      return ImportResult.notABackup;
    }
    // Si tiene da parte il contenuto attuale: se il backup e' rovinato a meta'
    // lettura si rimette tutto com'era invece di restare senza dati.
    final store = SharedPreferencesAsync();
    final previous = await store.getString('sanfrediano');
    await store.setString('sanfrediano', text);
    setState(() => loading = true);
    try {
      await load();
    } catch (_) {
      if (previous == null) {
        await store.remove('sanfrediano');
      } else {
        await store.setString('sanfrediano', previous);
      }
      await load();
      return ImportResult.damaged;
    }
    return ImportResult.done;
  }

  int present(DateTime d) {
    var total = (attendance[key(d)] ?? {}).values
        .where((m) => m == Mark.present)
        .length;
    for (final session in extraTrainings[key(d)] ?? const <ExtraTraining>[]) {
      total += (attendance[session.id] ?? {}).values
          .where((m) => m == Mark.present)
          .length;
    }
    return total;
  }

  void _createClassesForExistingPlayers() {
    for (final player in kids) {
      final year = player.year.isEmpty ? 'Classe principale' : player.year;
      FootballClass? existing;
      for (final group in classes) {
        if (group.year == year) {
          existing = group;
          break;
        }
      }
      final footballClass =
          existing ??
          FootballClass(
            'class-${DateTime.now().microsecondsSinceEpoch}-${classes.length}',
            year,
          );
      if (existing == null) classes.add(footballClass);
      player.classId = footballClass.id;
    }
  }

  DateTime? attendanceDate(String attendanceId) {
    final normalDate = DateTime.tryParse(attendanceId);
    if (normalDate != null) return normalDate;
    for (final entry in extraTrainings.entries) {
      if (entry.value.any((session) => session.id == attendanceId)) {
        return DateTime.parse(entry.key);
      }
    }
    return null;
  }

  void _migrateLegacyMoves() {
    final usedDestinations = <String>{};
    final addedDays = trainingChanges.entries
        .where(
          (entry) => entry.value && !defaultTraining(DateTime.parse(entry.key)),
        )
        .map((entry) => entry.key)
        .toList();
    for (final entry in List.of(trainingChanges.entries)) {
      final oldDay = DateTime.tryParse(entry.key);
      if (entry.value || oldDay == null || !defaultTraining(oldDay)) continue;
      String? destination;
      var shortestDistance = 8;
      for (final addedDay in addedDays) {
        if (usedDestinations.contains(addedDay)) continue;
        final distance = DateTime.parse(addedDay)
            .difference(oldDay)
            .inDays
            .abs();
        if (distance < shortestDistance) {
          shortestDistance = distance;
          destination = addedDay;
        }
      }
      if (destination != null) {
        movedTraining[entry.key] = destination;
        trainingChanges.remove(entry.key);
        trainingChanges.remove(destination);
        usedDestinations.add(destination);
      }
    }
  }

  String dateLabel(String dateKey) {
    final date = DateTime.parse(dateKey);
    return '${date.day} ${months[date.month - 1]}';
  }

  String monthlyReport() {
    final report = StringBuffer()
      ..writeln('SCUOLA CALCIO SAN FREDIANO')
      ..writeln('Riepilogo presenze - ${months[month.month - 1]} ${month.year}');
    if (coachName.trim().isNotEmpty) {
      report.writeln('Allenatore: ${coachName.trim()}');
    }
    report
      ..writeln()
      ..writeln('GIOCATORE | PRES. | ASS. | GIUST.')
      ..writeln('--------------------------------');

    if (kids.isEmpty) {
      report.writeln('Nessun giocatore inserito.');
    }

    for (final player in kids) {
      var presences = 0;
      var absences = 0;
      var justified = 0;
      for (final entry in attendance.entries) {
        final date = attendanceDate(entry.key);
        if (date == null ||
            date.year != month.year ||
            date.month != month.month) {
          continue;
        }
        switch (entry.value[player.id]) {
          case Mark.present:
            presences++;
          case Mark.absent:
            absences++;
          case Mark.justified:
            justified++;
          case null:
            break;
        }
      }
      report.writeln('${player.name} | $presences | $absences | $justified');
    }

    report
      ..writeln()
      ..writeln('VARIAZIONI ALLENAMENTI')
      ..writeln('--------------------------------');
    var hasVariations = false;
    for (final entry in movedTraining.entries) {
      final oldDate = DateTime.parse(entry.key);
      final newDate = DateTime.parse(entry.value);
      if ((oldDate.year == month.year && oldDate.month == month.month) ||
          (newDate.year == month.year && newDate.month == month.month)) {
        report.writeln(
          '- Allenamento del ${dateLabel(entry.key)} spostato al ${dateLabel(entry.value)}.',
        );
        hasVariations = true;
      }
    }
    for (final entry in trainingChanges.entries) {
      final date = DateTime.parse(entry.key);
      if (!entry.value &&
          date.year == month.year &&
          date.month == month.month) {
        report.writeln('- Allenamento del ${dateLabel(entry.key)} annullato.');
        hasVariations = true;
      }
    }
    if (!hasVariations) report.writeln('Nessuna variazione agli allenamenti.');

    report
      ..writeln()
      ..writeln('Report creato con TeamCheck.');
    return report.toString();
  }

  Future<void> shareMonthlyReport() => SharePlus.instance.share(
    ShareParams(
      text: monthlyReport(),
      title: 'Report ${months[month.month - 1]} ${month.year}',
      subject: 'Riepilogo presenze ${months[month.month - 1]} ${month.year}',
    ),
  );
  bool inSeason(DateTime day) =>
      !day.isBefore(seasonStart) && day.isBefore(seasonEnd);

  /// La classe che babbo allena, quella con la stella.
  FootballClass? get favoriteClass {
    for (final group in classes) {
      if (group.id == favoriteClassId) return group;
    }
    return null;
  }

  /// I giorni fissi del calendario sono quelli della classe preferita: se un
  /// domani babbo prende una classe che si allena martedi' e giovedi', basta
  /// cambiarli li'. Senza classe scelta non c'e' nessun giorno: segnare
  /// allenamenti che nessuno ha mai inserito sarebbe una bugia.
  Set<int> get trainingDays => favoriteClass?.days ?? const {};
  bool defaultTraining(DateTime day) =>
      inSeason(day) && trainingDays.contains(day.weekday);
  bool isMoved(DateTime day) => movedTraining.containsKey(key(day));
  bool isTraining(DateTime day) =>
      inSeason(day) &&
      !isMoved(day) &&
      trainingChanges[key(day)] != false &&
      (defaultTraining(day) ||
          trainingChanges[key(day)] == true ||
          movedTraining.containsValue(key(day)));
  bool canManageTraining(DateTime day) =>
      defaultTraining(day) ||
      trainingChanges.containsKey(key(day)) ||
      isMoved(day) ||
      movedTraining.containsValue(key(day));

  /// L'allenamento aggiunto a mano con quell'id, se esiste.
  ExtraTraining? extraSession(String id) {
    for (final sessions in extraTrainings.values) {
      for (final session in sessions) {
        if (session.id == id) return session;
      }
    }
    return null;
  }

  /// Sposta un allenamento aggiunto a mano: cambia solo la lista del giorno
  /// in cui sta, l'id non cambia e quindi le presenze lo seguono.
  Future<void> moveExtraTraining(String id, DateTime from, DateTime to) async {
    final source = extraTrainings[key(from)];
    if (source == null) return;
    final index = source.indexWhere((session) => session.id == id);
    if (index < 0) return;
    final session = source.removeAt(index);
    setState(() {
      if (source.isEmpty) extraTrainings.remove(key(from));
      extraTrainings.putIfAbsent(key(to), () => []).add(session);
    });
    await save();
  }

  Future<void> deleteExtraTraining(String id, DateTime from) async {
    setState(() {
      final source = extraTrainings[key(from)];
      source?.removeWhere((session) => session.id == id);
      if (source != null && source.isEmpty) extraTrainings.remove(key(from));
      attendance.remove(id);
      selectedPlayers.remove(id);
    });
    await save();
  }

  Future<void> manageTraining(DateTime date, {String? trainingId}) async {
    final id = trainingId ?? key(date);
    final extra = extraSession(id);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrainingPage(
          date: date,
          trainingId: id,
          extraName: extra?.name,
          changes: Map.of(trainingChanges),
          moves: Map.of(movedTraining),
          onChanged: (changes, moves) async {
            setState(() {
              trainingChanges = changes;
              movedTraining = moves;
            });
            await save();
          },
          onMoveExtra: extra == null
              ? null
              : (newDate) => moveExtraTraining(id, date, newDate),
          onDeleteExtra: extra == null
              ? null
              : () => deleteExtraTraining(id, date),
        ),
      ),
    );
  }

  Future<void> editKids() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClassesPage(
          classes: classes,
          kids: kids,
          favoriteClassId: favoriteClassId,
          onSave: (newClasses, newKids, newFavoriteClassId) async {
            setState(() {
              classes = newClasses;
              kids = newKids;
              favoriteClassId = newFavoriteClassId;
              forgetRemovedPlayers();
            });
            await save();
          },
        ),
      ),
    );
  }

  /// Toglie presenze e convocazioni dei giocatori che non ci sono piu',
  /// altrimenti restano nel salvataggio per sempre.
  void forgetRemovedPlayers() {
    final ids = kids.map((player) => player.id).toSet();
    for (final marks in attendance.values) {
      marks.removeWhere((id, _) => !ids.contains(id));
    }
    for (final players in selectedPlayers.values) {
      players.removeWhere((id) => !ids.contains(id));
    }
  }

  Future<void> openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          coachName: coachName,
          onCoachNameChanged: (name) async {
            setState(() => coachName = name);
            await save();
          },
          onExport: exportBackup,
          onImport: importBackup,
        ),
      ),
    );
  }

  List<TrainingOption> sessionsFor(DateTime date) {
    final sessions = <TrainingOption>[];
    if (trainingChanges[key(date)] == false) {
      sessions.add(
        TrainingOption(
          id: key(date),
          name: 'Allenamento annullato',
          canManage: true,
          managedTrainingId: key(date),
        ),
      );
    } else if (
        inSeason(date) &&
        !isMoved(date) &&
        trainingChanges[key(date)] != false &&
        (defaultTraining(date) || trainingChanges[key(date)] == true)) {
      sessions.add(
        TrainingOption(
          id: key(date),
          name: 'Allenamento abituale',
          canManage: canManageTraining(date),
          managedTrainingId: key(date),
        ),
      );
    }
    // Ogni allenamento spostato resta una sessione distinta: piu' allenamenti
    // possono quindi svolgersi nello stesso giorno.
    for (final entry in movedTraining.entries) {
      if (entry.value == key(date)) {
        sessions.add(
          TrainingOption(
            id: entry.key,
            name: 'Allenamento spostato dal ${dateLabel(entry.key)}',
            canManage: true,
            managedTrainingId: entry.key,
          ),
        );
      }
    }
    for (final extra in extraTrainings[key(date)] ?? const <ExtraTraining>[]) {
      sessions.add(
        TrainingOption(
          id: extra.id,
          name: extra.name,
          canManage: true,
          managedTrainingId: extra.id,
        ),
      );
    }
    return sessions;
  }

  Future<TrainingOption> addExtraTraining(DateTime date, String name) async {
    final session = ExtraTraining(
      'extra-${DateTime.now().microsecondsSinceEpoch}',
      name.trim().isEmpty ? 'Allenamento aggiuntivo' : name.trim(),
    );
    setState(
      () => extraTrainings.putIfAbsent(key(date), () => []).add(session),
    );
    await save();
    return TrainingOption(
      id: session.id,
      name: session.name,
      canManage: true,
      managedTrainingId: session.id,
    );
  }

  Future<Kid> addPlayerForRollCall(String name, String classId) async {
    final footballClass = classes.firstWhere((group) => group.id == classId);
    final player = Kid(
      DateTime.now().microsecondsSinceEpoch.toString(),
      name.trim(),
      footballClass.year,
      classId: footballClass.id,
    );
    setState(() => kids.add(player));
    await save();
    return player;
  }

  Future<void> openRollCall(DateTime date, TrainingOption session) async {
    // Nei giorni della sua classe l'appello si apre gia' con i suoi giocatori.
    final useFavoriteTeam =
        session.id == key(date) &&
        favoriteClassId != null &&
        trainingDays.contains(date.weekday);
    final defaultPlayerIds = useFavoriteTeam
        ? kids
              .where((player) => player.classId == favoriteClassId)
              .map((player) => player.id)
        : kids.map((player) => player.id);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DayPage(
          date: date,
          sessionName: session.name,
          kids: kids,
          classes: classes,
          initialPlayerIds: List.of(
            useFavoriteTeam
                ? defaultPlayerIds
                : selectedPlayers[session.id] ?? defaultPlayerIds,
          ),
          marks: Map.of(attendance[session.id] ?? {}),
          onChanged: (values) async {
            setState(() => attendance[session.id] = values);
            await save();
          },
          onPlayersChanged: (ids) async {
            setState(() => selectedPlayers[session.id] = ids);
            await save();
          },
          onRegisterPlayer: addPlayerForRollCall,
        ),
      ),
    );
  }

  Future<void> openDay(DateTime date) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => DaySchedulePage(
        date: date,
        sessions: sessionsFor(date),
        onAdd: (name) => addExtraTraining(date, name),
        onOpen: (session) => openRollCall(date, session),
        onManage: (session) => manageTraining(
          date,
          trainingId: session.managedTrainingId,
        ),
        onRefresh: () => sessionsFor(date),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final first = DateTime(month.year, month.month).weekday - 1,
        count = DateUtils.getDaysInMonth(month.year, month.month);
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 7),
          child: Image.asset(
            'assets/san_frediano_logo.png',
            fit: BoxFit.contain,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TeamCheck'),
            Text(
              // Finche' il nome non e' stato scritto in Impostazioni resta
              // la societa', cosi' l'intestazione non e' mai monca.
              coachName.trim().isEmpty
                  ? 'Presenze San Frediano'
                  : 'Allenatore ${coachName.trim()}',
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: loading ? null : openSettings,
            tooltip: 'Impostazioni e backup',
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: month.isAfter(seasonStart)
                          ? () => setState(
                              () =>
                                  month = DateTime(month.year, month.month - 1),
                            )
                          : null,
                      tooltip: 'Mese precedente',
                      iconSize: 38,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(64, 64),
                      ),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          '${months[month.month - 1]} ${month.year}',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 21,
                              ),
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: month.isBefore(lastSeasonMonth)
                          ? () => setState(
                              () =>
                                  month = DateTime(month.year, month.month + 1),
                            )
                          : null,
                      tooltip: 'Mese successivo',
                      iconSize: 38,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(64, 64),
                      ),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
            ),
            // Senza classe scelta il calendario non ha giorni fissi, e un
            // calendario vuoto sembra rotto: qui c'e' scritto cosa manca.
            if (favoriteClass == null) ...[
              const SizedBox(height: 12),
              Card(
                color: const Color(0xfffff0cc),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          classes.isEmpty
                              ? 'Nessun allenamento sul calendario: tocca '
                                    'GESTISCI GIOCATORI e crea la tua classe '
                                    'con i suoi giorni.'
                              : 'Tocca la stella accanto alla classe che '
                                    'alleni: il calendario seguirà i suoi '
                                    'giorni.',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                for (final label in ['L', 'M', 'M', 'G', 'V', 'S', 'D'])
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.builder(
                itemCount: first + count,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: .82,
                ),
                itemBuilder: (_, index) {
                  if (index < first) return const SizedBox();
                  final day = DateTime(
                        month.year,
                        month.month,
                        index - first + 1,
                      ),
                      total = present(
                        DateTime(month.year, month.month, index - first + 1),
                      );
                  final isToday = DateUtils.isSameDay(day, DateTime.now());
                  final training = isTraining(day);
                  final cancelled = trainingChanges[key(day)] == false;
                  final moved = isMoved(day);
                  return InkWell(
                    onTap: () => openDay(day),
                    borderRadius: BorderRadius.circular(14),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: cancelled
                            ? const Color(0xffffe2e2)
                            : moved
                            ? const Color(0xfffff0cc)
                            : isToday
                            ? Theme.of(context).colorScheme.primaryContainer
                            : training
                            ? const Color(0xffd9f3df)
                            : Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                        border: training || cancelled || moved
                            ? Border.all(
                                color: cancelled
                                    ? Colors.red
                                    : moved
                                    ? const Color(0xffb86e00)
                                    : const Color(0xff087448),
                                width: 2,
                              )
                            : null,
                      ),
                      // Stack e non Column: nelle celle piccole i riquadri
                      // andavano in overflow (righe gialle e nere), qui invece
                      // ogni segno sta nel suo angolo.
                      child: Stack(
                        children: [
                          Positioned(
                            top: 3,
                            left: 5,
                            child: Text(
                              '${day.day}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          // Il pallone sta in basso: in alto a destra si
                          // appiccicava ai giorni a due cifre.
                          if (training)
                            const Positioned(
                              bottom: 4,
                              left: 4,
                              child: Icon(
                                Icons.sports_soccer,
                                size: 16,
                                color: Color(0xff087448),
                              ),
                            ),
                          if (cancelled)
                            const Positioned(
                              bottom: 4,
                              left: 4,
                              child: Text(
                                'ANNULL.',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else if (moved)
                            const Positioned(
                              bottom: 4,
                              left: 4,
                              child: Text(
                                'SPOST.',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Color(0xff9a5900),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else if (total > 0)
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: CircleAvatar(
                                radius: 9,
                                child: Text(
                                  '$total',
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 70,
              child: FilledButton.icon(
                onPressed: () => openDay(DateTime.now()),
                icon: const Icon(Icons.how_to_reg, size: 31),
                label: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'ALLENAMENTO DI OGGI',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text('Apri l’appello', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: FilledButton.icon(
                onPressed: editKids,
                icon: const Icon(Icons.groups, size: 28),
                label: const Text(
                  'GESTISCI GIOCATORI',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: OutlinedButton.icon(
                onPressed: shareMonthlyReport,
                icon: const Icon(Icons.ios_share, size: 28),
                label: Text(
                  'INVIA REPORT DI ${months[month.month - 1].toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TrainingPage extends StatefulWidget {
  const TrainingPage({
    super.key,
    required this.date,
    required this.trainingId,
    required this.changes,
    required this.moves,
    required this.onChanged,
    this.extraName,
    this.onMoveExtra,
    this.onDeleteExtra,
  });
  final DateTime date;
  final String trainingId;
  final Map<String, bool> changes;
  final Map<String, String> moves;
  final Future<void> Function(Map<String, bool>, Map<String, String>) onChanged;

  /// Valorizzato solo per gli allenamenti aggiunti a mano: quelli si
  /// spostano cambiando giorno e si eliminano, non si "annullano".
  final String? extraName;
  final Future<void> Function(DateTime newDate)? onMoveExtra;
  final Future<void> Function()? onDeleteExtra;
  bool get isExtra => extraName != null;

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  late Map<String, bool> changes = Map.of(widget.changes);
  late Map<String, String> moves = Map.of(widget.moves);
  String key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Future<DateTime?> pick(String title) {
    final today = DateUtils.dateOnly(DateTime.now());
    final initialDate = widget.date.isBefore(today) ? today : widget.date;
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: lastSeasonDay,
      helpText: title,
    );
  }
  Future<void> save() => widget.onChanged(changes, moves);
  String label(DateTime d) => '${d.day}/${d.month}/${d.year}';

  String eventKey() => widget.trainingId;

  bool get isMovedTraining => moves.containsKey(eventKey());
  bool get isCancelledTraining => changes[eventKey()] == false;

  Future<void> cancelTraining() async {
    setState(() {
      final original = eventKey();
      moves.remove(original);
      changes[original] = false;
    });
    await save();
  }

  Future<void> restoreTraining() async {
    final original = eventKey();
    setState(() {
      moves.remove(original);
      changes.remove(original);
    });
    await save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Allenamento ripristinato.')),
      );
    }
  }

  /// Sposta un allenamento aggiunto a mano e torna al giorno: da qui in poi
  /// quella sessione non sta piu' su questa data.
  Future<void> moveExtra() async {
    final newDate = await pick('Scegli la nuova data');
    if (newDate == null) return;
    await widget.onMoveExtra!(newDate);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Allenamento spostato dal ${label(widget.date)} al ${label(newDate)}',
        ),
      ),
    );
    Navigator.pop(context);
  }

  Future<void> deleteExtra() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminare questo allenamento?'),
        content: Text(
          'Sparisce dal ${label(widget.date)} insieme all\'appello che hai '
          'già fatto per lui. Gli altri allenamenti del giorno restano.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ANNULLA'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ELIMINA'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.onDeleteExtra!();
    if (mounted) Navigator.pop(context);
  }

  Future<void> moveTraining() async {
    final newDate = await pick('Scegli la nuova data');
    if (newDate == null) return;
    setState(() {
      final original = eventKey();
      moves[original] = key(newDate);
      changes.remove(original);
      changes.remove(key(newDate));
    });
    await save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Allenamento spostato dal ${label(widget.date)} al ${label(newDate)}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 70,
      automaticallyImplyLeading: false,
      leadingWidth: 190,
      leading: const ReturnButton(destination: 'GIORNO'),
      title: const Text('Gestisci allenamento'),
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              color: const Color(0xffd9f3df),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.sports_soccer, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.extraName ??
                            'Allenamento del ${label(widget.date)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                widget.isExtra
                    ? 'Allenamento aggiunto da te il ${label(widget.date)}.'
                    : 'Qui modifichi solo questo allenamento.',
                textAlign: TextAlign.center,
              ),
            ),
            if (widget.isExtra) ...[
              _actionButton(
                context,
                Icons.swap_horiz,
                'SPOSTA ALLENAMENTO',
                'Scegli la nuova data',
                moveExtra,
              ),
              const SizedBox(height: 12),
              _actionButton(
                context,
                Icons.delete_outline,
                'ELIMINA ALLENAMENTO',
                'Lo toglie dal giorno, con il suo appello',
                deleteExtra,
                danger: true,
              ),
            ] else ...[
              if (isMovedTraining || isCancelledTraining) ...[
                _actionButton(
                  context,
                  Icons.restore,
                  'RIPRISTINA ALLENAMENTO',
                  isMovedTraining
                      ? 'Tornerà alla data originale'
                      : 'Tornerà nel calendario',
                  restoreTraining,
                ),
                const SizedBox(height: 12),
              ],
              _actionButton(
                context,
                Icons.swap_horiz,
                'SPOSTA ALLENAMENTO',
                'Scegli la nuova data',
                moveTraining,
              ),
              const SizedBox(height: 12),
              _actionButton(
                context,
                Icons.cancel_outlined,
                'ANNULLA ALLENAMENTO',
                'Sarà segnato in rosso sul calendario',
                cancelTraining,
                danger: true,
              ),
            ],
            const Spacer(),
            Text(
              'Le modifiche vengono salvate automaticamente.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _actionButton(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Future<void> Function() action, {
    bool danger = false,
  }) => SizedBox(
    width: double.infinity,
    height: 76,
    child: OutlinedButton.icon(
      onPressed: action,
      icon: Icon(icon, size: 30, color: danger ? Colors.red : null),
      label: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: danger ? Colors.red : null,
            ),
          ),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 18),
      ),
    ),
  );
}

class DaySchedulePage extends StatefulWidget {
  const DaySchedulePage({
    super.key,
    required this.date,
    required this.sessions,
    required this.onAdd,
    required this.onOpen,
    required this.onManage,
    required this.onRefresh,
  });
  final DateTime date;
  final List<TrainingOption> sessions;
  final Future<TrainingOption> Function(String name) onAdd;
  final Future<void> Function(TrainingOption session) onOpen;
  final Future<void> Function(TrainingOption session) onManage;

  /// Rilegge gli allenamenti del giorno: dopo uno spostamento o una
  /// cancellazione l'elenco qui sotto sarebbe rimasto quello di prima.
  final List<TrainingOption> Function() onRefresh;

  @override
  State<DaySchedulePage> createState() => _DaySchedulePageState();
}

class _DaySchedulePageState extends State<DaySchedulePage> {
  late List<TrainingOption> sessions = List.of(widget.sessions);

  Future<void> manage(TrainingOption session) async {
    await widget.onManage(session);
    if (mounted) setState(() => sessions = widget.onRefresh());
  }

  /// L'appello si fa il giorno stesso o piu' tardi: se babbo se ne dimentica
  /// deve poterlo recuperare. Sui giorni futuri invece non ha senso.
  bool get canTakeRollCall => !DateUtils.dateOnly(
    widget.date,
  ).isAfter(DateUtils.dateOnly(DateTime.now()));
  bool get isToday => DateUtils.isSameDay(widget.date, DateTime.now());

  Future<void> addTraining() async {
    final name = TextEditingController();
    final add = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Aggiungi allenamento'),
        content: TextField(
          controller: name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Gruppo o descrizione (facoltativo)',
            hintText: 'Es. Classe 2017',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ANNULLA'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('AGGIUNGI'),
          ),
        ],
      ),
    );
    if (add != true) return;
    final session = await widget.onAdd(name.text);
    if (mounted) setState(() => sessions.add(session));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 70,
      automaticallyImplyLeading: false,
      leadingWidth: 220,
      leading: const ReturnButton(destination: 'CALENDARIO'),
      title: Text('${widget.date.day} ${months[widget.date.month - 1]}'),
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              isToday ? 'Allenamenti di oggi' : 'Allenamenti del giorno',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              canTakeRollCall
                  ? 'Puoi fare o correggere l\'appello anche nei giorni passati.'
                  : 'L\'appello si potrà fare dal giorno dell\'allenamento.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: sessions.isEmpty
                  ? const Center(
                      child: Text(
                        'Nessun allenamento programmato.\nPuoi aggiungerne uno qui sotto.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: sessions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (_, index) {
                        final session = sessions[index];
                        // Appello e gestione affiancati: ogni allenamento si
                        // porta accanto il suo tasto, cosi' non c'e' dubbio su
                        // quale allenamento si sta gestendo.
                        return SizedBox(
                          height: 88,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: canTakeRollCall
                                      ? () => widget.onOpen(session)
                                      : null,
                                  icon: const Icon(Icons.how_to_reg, size: 29),
                                  label: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        session.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        canTakeRollCall
                                            ? 'APRI APPELLO'
                                            : 'NON ANCORA DISPONIBILE',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ],
                                  ),
                                  style: FilledButton.styleFrom(
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                  ),
                                ),
                              ),
                              if (session.canManage) ...[
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 108,
                                  child: OutlinedButton(
                                    onPressed: () => manage(session),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                    ),
                                    child: const Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.settings, size: 28),
                                        SizedBox(height: 4),
                                        Text(
                                          'GESTISCI',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
            SizedBox(
              width: double.infinity,
              height: 66,
              child: OutlinedButton.icon(
                onPressed: addTraining,
                icon: const Icon(Icons.add_circle_outline, size: 31),
                label: const Text(
                  'AGGIUNGI ALLENAMENTO',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class DayPage extends StatefulWidget {
  const DayPage({
    super.key,
    required this.date,
    required this.sessionName,
    required this.kids,
    required this.classes,
    required this.initialPlayerIds,
    required this.marks,
    required this.onChanged,
    required this.onPlayersChanged,
    required this.onRegisterPlayer,
  });
  final DateTime date;
  final String sessionName;
  final List<Kid> kids;
  final List<FootballClass> classes;
  final List<String> initialPlayerIds;
  final Map<String, Mark> marks;
  final Future<void> Function(Map<String, Mark>) onChanged;
  final Future<void> Function(List<String>) onPlayersChanged;
  final Future<Kid> Function(String name, String classId) onRegisterPlayer;
  @override
  State<DayPage> createState() => _DayPageState();
}

class _DayPageState extends State<DayPage> {
  late Map<String, Mark> marks = widget.marks;
  late List<Kid> allPlayers = List.of(widget.kids);
  late Set<String> playerIds = Set.of(widget.initialPlayerIds);

  Future<void> chooseOtherPlayers() async {
    final classId = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Scegli la classe'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: widget.classes
                .map(
                  (group) => ListTile(
                    leading: const Icon(Icons.groups),
                    title: Text('Classe ${group.year}'),
                    onTap: () => Navigator.pop(context, group.id),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ANNULLA'),
          ),
        ],
      ),
    );
    if (classId == null || !mounted) return;

    final group = widget.classes.firstWhere((item) => item.id == classId);
    final classPlayers = allPlayers
        .where((player) => player.classId == classId)
        .toList();
    final chosen = Set<String>.of(playerIds);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Altri giocatori · Classe ${group.year}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: classPlayers
                  .map(
                    (player) => CheckboxListTile(
                      value: chosen.contains(player.id),
                      onChanged: (value) => setDialogState(() {
                        if (value == true) {
                          chosen.add(player.id);
                        } else {
                          chosen.remove(player.id);
                        }
                      }),
                      title: Text(player.name),
                      subtitle: const Text('Aggiungi all’appello'),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ANNULLA'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('CONFERMA'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    setState(() => playerIds = chosen);
    await widget.onPlayersChanged(playerIds.toList());
  }

  Future<void> registerPlayer() async {
    final name = TextEditingController();
    String? classId = widget.classes.isEmpty ? null : widget.classes.first.id;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Registra nuovo giocatore'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(labelText: 'Nome e cognome'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: classId,
                decoration: const InputDecoration(labelText: 'Classe'),
                items: widget.classes
                    .map(
                      (group) => DropdownMenuItem(
                        value: group.id,
                        child: Text('Classe ${group.year}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => classId = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ANNULLA'),
            ),
            FilledButton(
              onPressed: classId == null || name.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('REGISTRA'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || classId == null || name.text.trim().isEmpty) return;
    final player = await widget.onRegisterPlayer(name.text, classId!);
    setState(() {
      allPlayers.add(player);
      playerIds.add(player.id);
    });
    await widget.onPlayersChanged(playerIds.toList());
  }

  List<Kid> get visiblePlayers =>
      allPlayers.where((player) => playerIds.contains(player.id)).toList();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 70,
      automaticallyImplyLeading: false,
      leadingWidth: 220,
      leading: const ReturnButton(destination: 'GIORNO'),
      title: Text(widget.sessionName),
    ),
    body: Column(
      children: [
        Expanded(
          child: visiblePlayers.isEmpty
              ? const Center(
                  child: Text(
                    'Aggiungi altri giocatori o registrane uno nuovo.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: visiblePlayers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final kid = visiblePlayers[i];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(kid.name[0].toUpperCase()),
                        ),
                        title: Text(kid.name),
                        subtitle: kid.year.isEmpty
                            ? null
                            : Text('Nato nel ${kid.year}'),
                        trailing: PopupMenuButton<Mark>(
                          onSelected: (m) async {
                            setState(() => marks[kid.id] = m);
                            await widget.onChanged(marks);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: Mark.present,
                              child: Text('✓ Presente'),
                            ),
                            PopupMenuItem(
                              value: Mark.absent,
                              child: Text('✕ Assente'),
                            ),
                            PopupMenuItem(
                              value: Mark.justified,
                              child: Text('G Giustificato'),
                            ),
                          ],
                          child: Status(marks[kid.id]),
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: widget.classes.isEmpty
                        ? null
                        : chooseOtherPlayers,
                    icon: const Icon(Icons.group_add, size: 27),
                    label: const Text(
                      'ALTRI GIOCATORI',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: widget.classes.isEmpty ? null : registerPlayer,
                    icon: const Icon(Icons.person_add_alt_1, size: 27),
                    label: const Text(
                      'REGISTRA NUOVO GIOCATORE',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class Status extends StatelessWidget {
  const Status(this.mark, {super.key});
  final Mark? mark;
  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (mark) {
      Mark.present => ('Presente', Colors.green),
      Mark.absent => ('Assente', Colors.red),
      Mark.justified => ('Giustificato', Colors.orange),
      null => ('Segna', Colors.grey),
    };
    return Chip(
      avatar: Icon(Icons.circle, color: color, size: 12),
      label: Text(text),
    );
  }
}

class ClassesPage extends StatefulWidget {
  const ClassesPage({
    super.key,
    required this.classes,
    required this.kids,
    required this.favoriteClassId,
    required this.onSave,
  });
  final List<FootballClass> classes;
  final List<Kid> kids;
  final String? favoriteClassId;
  final Future<void> Function(List<FootballClass>, List<Kid>, String?) onSave;

  @override
  State<ClassesPage> createState() => _ClassesPageState();
}

class _ClassesPageState extends State<ClassesPage> {
  late List<FootballClass> groups = List.of(widget.classes);
  late List<Kid> players = List.of(widget.kids);
  late String? favoriteClassId = widget.favoriteClassId;
  Future<void> persist() => widget.onSave(groups, players, favoriteClassId);

  Future<void> setFavorite(FootballClass footballClass) async {
    setState(() => favoriteClassId = footballClass.id);
    await persist();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Classe ${footballClass.year} scelta come squadra preferita.'),
        ),
      );
    }
  }

  Future<void> addClass() async {
    final year = TextEditingController();
    final add = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Aggiungi classe'),
        content: TextField(
          controller: year,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Anno di nascita',
            hintText: 'Es. 2017',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ANNULLA'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('AGGIUNGI'),
          ),
        ],
      ),
    );
    final value = year.text.trim();
    if (add != true ||
        value.isEmpty ||
        groups.any((group) => group.year == value)) {
      return;
    }
    setState(
      () {
        final footballClass = FootballClass(
          'class-${DateTime.now().microsecondsSinceEpoch}',
          value,
        );
        groups.add(footballClass);
        // La prima classe diventa quella di babbo: e' la sua a dettare i
        // giorni del calendario, e senza stella non ne detterebbe nessuna.
        favoriteClassId ??= footballClass.id;
      },
    );
    await persist();
  }

  Future<void> openClass(FootballClass footballClass) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ClassPlayersPage(
        footballClass: footballClass,
        isFavorite: favoriteClassId == footballClass.id,
        players: players
            .where((player) => player.classId == footballClass.id)
            .toList(),
        onDaysChanged: (days) async {
          setState(() => footballClass.days = days);
          await persist();
        },
        onSave: (classPlayers) async {
          setState(() {
            players.removeWhere((player) => player.classId == footballClass.id);
            players.addAll(classPlayers);
          });
          await persist();
        },
        onDelete: () async {
          setState(() {
            groups.removeWhere((group) => group.id == footballClass.id);
            players.removeWhere(
              (player) => player.classId == footballClass.id,
            );
            if (favoriteClassId == footballClass.id) favoriteClassId = null;
          });
          await persist();
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 70,
      automaticallyImplyLeading: false,
      leadingWidth: 220,
      leading: const ReturnButton(destination: 'CALENDARIO'),
      title: const Text('Gestisci classi'),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: groups.isEmpty
                ? const Center(
                    child: Text(
                      'Aggiungi la prima classe.',
                      style: TextStyle(fontSize: 18),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: groups.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final group = groups[index];
                      final count = players
                          .where((player) => player.classId == group.id)
                          .length;
                      final isFavorite = favoriteClassId == group.id;
                      return SizedBox(
                        height: 96,
                        child: Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => openClass(group),
                                icon: Icon(
                                  isFavorite ? Icons.star : Icons.groups,
                                  size: 30,
                                ),
                                label: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Classe ${group.year}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      isFavorite
                                          ? '$count giocatori • PREFERITA'
                                          : '$count giocatori',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'Allena: ${daysLabel(group.days)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              onPressed: isFavorite
                                  ? null
                                  : () => setFavorite(group),
                              tooltip: isFavorite
                                  ? 'Squadra preferita'
                                  : 'Imposta come squadra preferita',
                              icon: Icon(
                                isFavorite ? Icons.star : Icons.star_border,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 62,
              child: OutlinedButton.icon(
                onPressed: addClass,
                icon: const Icon(Icons.add_circle_outline, size: 29),
                label: const Text(
                  'AGGIUNGI CLASSE',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class ClassPlayersPage extends StatefulWidget {
  const ClassPlayersPage({
    super.key,
    required this.footballClass,
    required this.isFavorite,
    required this.players,
    required this.onSave,
    required this.onDaysChanged,
    required this.onDelete,
  });
  final FootballClass footballClass;
  final bool isFavorite;
  final List<Kid> players;
  final Future<void> Function(List<Kid>) onSave;
  final Future<void> Function(Set<int>) onDaysChanged;
  final Future<void> Function() onDelete;

  @override
  State<ClassPlayersPage> createState() => _ClassPlayersPageState();
}

class _ClassPlayersPageState extends State<ClassPlayersPage> {
  late List<Kid> list = List.of(widget.players);
  late Set<int> days = Set.of(widget.footballClass.days);
  Future<void> persist() => widget.onSave(list);

  Future<void> toggleDay(int day, bool selected) async {
    setState(() {
      if (selected) {
        days.add(day);
      } else {
        days.remove(day);
      }
    });
    await widget.onDaysChanged(Set.of(days));
  }

  Widget daysPicker(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Giorni di allenamento',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var day = DateTime.monday; day <= DateTime.sunday; day++)
              FilterChip(
                label: Text(
                  shortDayNames[day - 1],
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                showCheckmark: false,
                selected: days.contains(day),
                onSelected: (selected) => toggleDay(day, selected),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          widget.isFavorite
              ? 'Il calendario segue questi giorni, perché è la classe scelta '
                    'come preferita.'
              : 'Il calendario segue i giorni della classe con la stella, non '
                    'questi.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const Divider(height: 26),
      ],
    ),
  );

  Future<void> deleteClass() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Eliminare la classe ${widget.footballClass.year}?'),
        content: Text(
          list.isEmpty
              ? 'La classe verrà tolta dall\'elenco.'
              : 'Verranno eliminati anche i ${list.length} giocatori della '
                    'classe e tutte le loro presenze.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ANNULLA'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ELIMINA'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.onDelete();
    if (mounted) Navigator.pop(context);
  }

  Future<void> addPlayer() async {
    final name = TextEditingController();
    final add = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Aggiungi giocatore'),
        content: TextField(
          controller: name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nome e cognome'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ANNULLA'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('AGGIUNGI'),
          ),
        ],
      ),
    );
    if (add != true || name.text.trim().isEmpty) return;
    setState(
      () => list.add(
        Kid(
          DateTime.now().microsecondsSinceEpoch.toString(),
          name.text.trim(),
          widget.footballClass.year,
          classId: widget.footballClass.id,
        ),
      ),
    );
    await persist();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 70,
      automaticallyImplyLeading: false,
      leadingWidth: 190,
      leading: const ReturnButton(destination: 'CLASSI'),
      title: Text('Classe ${widget.footballClass.year}'),
    ),
    body: SafeArea(
      child: Column(
        children: [
          daysPicker(context),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text(
                      'Nessun giocatore in questa classe.',
                      style: TextStyle(fontSize: 17),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (_, index) => Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        leading: CircleAvatar(
                          radius: 23,
                          child: Text(list[index].name[0].toUpperCase()),
                        ),
                        title: Text(
                          list[index].name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 27),
                          tooltip: 'Elimina giocatore',
                          onPressed: () async {
                            setState(() => list.removeAt(index));
                            await persist();
                          },
                        ),
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: FilledButton.icon(
                onPressed: addPlayer,
                icon: const Icon(Icons.person_add_alt_1, size: 28),
                label: const Text(
                  'AGGIUNGI GIOCATORE',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: deleteClass,
                icon: const Icon(
                  Icons.delete_outline,
                  size: 26,
                  color: Colors.red,
                ),
                label: const Text(
                  'ELIMINA CLASSE',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.coachName,
    required this.onCoachNameChanged,
    required this.onExport,
    required this.onImport,
  });
  final String coachName;
  final Future<void> Function(String name) onCoachNameChanged;
  final Future<void> Function() onExport;
  final Future<ImportResult> Function() onImport;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final coachName = TextEditingController(text: widget.coachName);
  bool busy = false;

  @override
  void dispose() {
    coachName.dispose();
    super.dispose();
  }

  Future<void> exportBackup() async {
    setState(() => busy = true);
    await widget.onExport();
    if (mounted) setState(() => busy = false);
  }

  Future<void> lookForUpdate() async {
    setState(() => busy = true);
    final result = await checkForUpdate();
    if (!mounted) return;
    setState(() => busy = false);
    switch (result.status) {
      case UpdateStatus.upToDate:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('TeamCheck è già aggiornato (versione $appVersion).'),
          ),
        );
      case UpdateStatus.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Non riesco a controllare adesso: serve una connessione a '
              'internet. Riprova più tardi.',
            ),
          ),
        );
      case UpdateStatus.available:
        final download = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('C\'è la versione ${result.version}'),
            content: const Text(
              'Tocca SCARICA: quando il telefono ha finito, apri il file '
              'scaricato e tocca AGGIORNA.\n\n'
              'Le presenze già inserite restano tutte al loro posto.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('PIÙ TARDI'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('SCARICA'),
              ),
            ],
          ),
        );
        if (download != true) return;
        final opened = await launchUrl(
          Uri.parse(result.url!),
          mode: LaunchMode.externalApplication,
        );
        if (!mounted || opened) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Non riesco ad aprire il download.')),
        );
    }
  }

  Future<void> importBackup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ripristinare un backup?'),
        content: const Text(
          'Le presenze che ci sono adesso nell\'app verranno sostituite con '
          'quelle del file che sceglierai.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ANNULLA'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CONTINUA'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => busy = true);
    final result = await widget.onImport();
    if (!mounted) return;
    setState(() => busy = false);
    if (result == ImportResult.cancelled) return;
    final message = switch (result) {
      ImportResult.done => 'Backup ripristinato.',
      ImportResult.notABackup =>
        'Il file scelto non è un backup delle presenze.',
      ImportResult.damaged => 'Backup danneggiato: i dati non sono cambiati.',
      ImportResult.cancelled => '',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    if (result == ImportResult.done) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 70,
      automaticallyImplyLeading: false,
      leadingWidth: 220,
      leading: const ReturnButton(destination: 'CALENDARIO'),
      title: const Text('Impostazioni e backup'),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Nome dell\'allenatore',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Compare in alto nella schermata principale e in cima al report '
            'che mandi ogni mese.',
          ),
          const SizedBox(height: 10),
          TextField(
            controller: coachName,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(
              labelText: 'Nome e cognome',
              hintText: 'Es. Mario Rossi',
              border: OutlineInputBorder(),
            ),
            onChanged: widget.onCoachNameChanged,
          ),
          const SizedBox(height: 8),
          Text(
            'Il nome si salva da solo.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const Divider(height: 40),
          Text(
            'Backup delle presenze',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Le presenze sono salvate solo dentro questo telefono. Ogni tanto '
            'salva una copia: ti serve se cambi telefono o se l\'app viene '
            'disinstallata.',
          ),
          const SizedBox(height: 14),
          if (busy)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ))
          else ...[
            SizedBox(
              width: double.infinity,
              height: 66,
              child: FilledButton.icon(
                onPressed: exportBackup,
                icon: const Icon(Icons.save_alt, size: 28),
                label: const Text(
                  'SALVA UNA COPIA',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Manda il file a te stesso su WhatsApp, mail o Drive.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 66,
              child: OutlinedButton.icon(
                onPressed: importBackup,
                icon: const Icon(Icons.restore_page, size: 28),
                label: const Text(
                  'RIPRISTINA UNA COPIA',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sostituisce tutte le presenze con quelle del file scelto.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 40),
            Text(
              'Aggiornamento dell\'app',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Versione installata: $appVersion',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 66,
              child: OutlinedButton.icon(
                onPressed: lookForUpdate,
                icon: const Icon(Icons.system_update, size: 28),
                label: const Text(
                  'CONTROLLA AGGIORNAMENTI',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Se c\'è una versione nuova, l\'app te la fa scaricare.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

const months = [
  'Gennaio',
  'Febbraio',
  'Marzo',
  'Aprile',
  'Maggio',
  'Giugno',
  'Luglio',
  'Agosto',
  'Settembre',
  'Ottobre',
  'Novembre',
  'Dicembre',
];
