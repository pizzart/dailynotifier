import 'dart:io';
import 'dart:math';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/material.dart';
import 'notification_service.dart';
import 'package:weekday_selector/weekday_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  final locationName = await FlutterNativeTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(locationName));
  // NotificationService().periodicNotifs(DateTime.now().add(const Duration(seconds: 5)));
  runApp(const MyApp());
}

Future<void> setupPeriodicNotifs(widget) async {
  // SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  bool enabled = prefs.getBool('enabled') ?? true;
  bool sendRepeated = prefs.getBool('repeat') ?? true;
  TimeOfDay time = TimeOfDay(
      hour: prefs.getInt('hour') ?? 10, minute: prefs.getInt('minute') ?? 0);
  List<bool> weekdays = List.empty(growable: true);
  for (String day in prefs.getStringList('weekdays') ??
      ["1", "1", "1", "1", "1", "1", "1"]) {
    if (day == '0') {
      weekdays.add(false);
    } else {
      weekdays.add(true);
    }
  }

  DateTime now = DateTime.now();
  DateTime tomorrow = now.add(const Duration(days: 1));
  tz.TZDateTime specified = tz.TZDateTime.from(
      DateTime(
          tomorrow.year, tomorrow.month, tomorrow.day, time.hour, time.minute),
      tz.local);

  Map<String, dynamic> inputData = {
    // 'notifs': [Notification('hi', 0)],
    'enabled': enabled,
    'sendRepeated': sendRepeated,
    'weekdays': weekdays,
  };

  Workmanager().initialize(
    callbackDispatcher,
    // isInDebugMode: true
  );
  // Workmanager().cancelAll();
  Workmanager().registerPeriodicTask(
    'dailynotifier',
    'dailynotification',
    frequency: const Duration(days: 1),
    initialDelay: specified.difference(tz.TZDateTime.now(tz.local)),
    inputData: inputData,
  );
}

void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (inputData!['enabled'] &&
        inputData['weekdays'][DateTime.now().weekday - 1]) {
      String notifText = '';
      List<Notification> notifs = await NotifStorage().loadNotifs();
      bool hasSendable = false;
      if (inputData['sendRepeated']) {
        for (Notification notif in notifs) {
          if (notif.count < 1) {
            hasSendable = true;
          }
        }
      }
      if (!hasSendable) {
        return Future.value(false);
      }
      if (notifs.isNotEmpty) {
        Notification notif = notifs[Random().nextInt(notifs.length)];
        notifText = notif.text;
        notif.count += 1;
      } else {
        return Future.value(false);
      }
      print(notifText);
      final prefs = await SharedPreferences.getInstance();
      TimeOfDay time = TimeOfDay(
          hour: prefs.getInt('hour') ?? 10, minute: prefs.getInt('minute') ?? 0);
      DateTime now = DateTime.now();
      DateTime tomorrow = now.add(const Duration(days: 1));
      tz.TZDateTime specified = tz.TZDateTime.from(
          DateTime(
              tomorrow.year, tomorrow.month, tomorrow.day, time.hour, time.minute),
          tz.local);
      Workmanager().registerPeriodicTask(
        'dailynotifier',
        'dailynotification',
        frequency: const Duration(days: 1),
        initialDelay: specified.difference(tz.TZDateTime.now(tz.local)),
        inputData: inputData,
      );
      NotificationService().init();
      NotificationService().sendNotif(notifText);
      return Future.value(true);
    }
    return Future.value(false);
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DailyNotifier',
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
            primary: Colors.pinkAccent, secondary: Colors.pinkAccent),
        textTheme: const TextTheme(
          button: TextStyle(fontSize: 16),
        ),
      ),
      home: MainRoute(storage: NotifStorage()),
    );
  }
}

class NotifStorage {
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/notifs.txt');
  }

  Future<File> saveNotifs(List<Notification> notifs) async {
    final file = await _localFile;
    String finalStr = '';
    for (Notification notif in notifs) {
      finalStr += '${notif.text}:${notif.count}\n';
    }
    return file.writeAsString(finalStr);
  }

  Future<List<Notification>> loadNotifs() async {
    try {
      final file = await _localFile;
      final contents = await file.readAsString();
      List<Notification> notifs = List.empty(growable: true);
      for (String line in contents.split('\n')) {
        List params = line.split(':');
        if (params.length == 2) {
          notifs.add(Notification(params[0], int.parse(params[1])));
        }
      }
      return notifs;
    } catch (e) {
      return [];
    }
  }
}

class MainRoute extends StatefulWidget {
  const MainRoute({super.key, required this.storage});

  final NotifStorage storage;

  @override
  State<MainRoute> createState() => _MainRouteState();
}

class _MainRouteState extends State<MainRoute> {
  List<Notification> notifs = <Notification>[];

  @override
  void initState() {
    super.initState();
    widget.storage.loadNotifs().then((value) {
      setState(() {
        notifs = value;
      });
    });
    setupPeriodicNotifs(widget);
  }

  Future<void> _navigateAndAdd(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddNotifRoute()),
    );

    if (!mounted) return;

    // ScaffoldMessenger.of(context)
    if (result != null) {
      setState(() {
        notifs.insert(0, Notification(result, 0));
      });
      widget.storage.saveNotifs(notifs);
      setupPeriodicNotifs(widget);
    }
  }

  Future<void> _navigateAndRemove(BuildContext context, notif, index) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetailScreen(notif: notif, index: index),
      ),
    );

    if (!mounted) return;

    // ScaffoldMessenger.of(context)
    if (result != null) {
      setState(() {
        notifs.removeAt(result);
      });
      widget.storage.saveNotifs(notifs);
      setupPeriodicNotifs(widget);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const SettingsRoute()),
                );
              },
              icon: const Icon(Icons.settings))
        ],
      ),
      body: Center(
        child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: notifs.length,
            itemBuilder: (BuildContext context, int index) {
              return ListTile(
                title: Text(
                  notifs[index].text,
                  style: const TextStyle(fontSize: 18),
                ),
                trailing: Text(notifs[index].count.toString(),
                    style: const TextStyle(fontSize: 16)),
                onTap: () {
                  _navigateAndRemove(context, notifs[index], index);
                },
              );
            }),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          _navigateAndAdd(context);
        },
      ),
    );
  }
}

class AddNotifRoute extends StatefulWidget {
  const AddNotifRoute({super.key});

  @override
  State<AddNotifRoute> createState() => _AddNotifRouteState();
}

class _AddNotifRouteState extends State<AddNotifRoute> {
  final textController = TextEditingController();

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Notification'),
      ),
      body: Center(
          child: Column(children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(
              // border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 4),
              hintText: 'Notification text...',
            ),
          ),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.notification_add),
          label: const Text('ADD NOTIFICATION'),
          // icon: Icon(Icons.add),
          onPressed: () {
            Navigator.pop(context, textController.text);
          },
        ),
      ])),
    );
  }
}

class SettingsRoute extends StatefulWidget {
  const SettingsRoute({super.key});

  @override
  State<SettingsRoute> createState() => _SettingsRouteState();
}

class _SettingsRouteState extends State<SettingsRoute> {
  bool _enabled = true;
  bool _sendRepeated = true;
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  List<bool> _weekdays = List.filled(7, true, growable: true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _save() async {
    List<String> wd = [];
    for (bool day in _weekdays) {
      if (day) {
        wd.add('1');
      } else {
        wd.add('0');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enabled', _enabled);
    await prefs.setBool('repeat', _sendRepeated);
    await prefs.setInt('hour', _time.hour);
    await prefs.setInt('minute', _time.minute);
    await prefs.setStringList('weekdays', wd);
    setupPeriodicNotifs(widget);
  }

  Future<void> _load() async {
    // SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _enabled = prefs.getBool('enabled') ?? true;
      _sendRepeated = prefs.getBool('repeat') ?? true;
      _time = TimeOfDay(
          hour: prefs.getInt('hour') ?? 10,
          minute: prefs.getInt('minute') ?? 0);
      _weekdays.clear();
      for (String day in prefs.getStringList('weekdays') ??
          ["1", "1", "1", "1", "1", "1", "1"]) {
        if (day == '0') {
          _weekdays.add(false);
        } else {
          _weekdays.add(true);
        }
      }
    });
  }

  _selectTime(BuildContext context) async {
    final TimeOfDay? timeOfDay = await showTimePicker(
      context: context,
      initialTime: _time,
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (timeOfDay != null && timeOfDay != _time) {
      setState(() {
        _time = timeOfDay;
        _save();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // _weekdays = List.filled(7, true, growable: true);
    // _load();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Center(
          child: ListView(
        children: [
          SwitchListTile(
              title: const Text('Enabled', style: TextStyle(fontSize: 20)),
              secondary: const Icon(Icons.check),
              value: _enabled,
              onChanged: (bool value) {
                setState(() {
                  _enabled = value;
                  _save();
                });
              }),
          SwitchListTile(
              title: const Text('Repeated Notifications',
                  style: TextStyle(fontSize: 20)),
              subtitle:
                  const Text('Send notifications that have been sent before'),
              secondary: const Icon(Icons.repeat),
              value: _sendRepeated,
              onChanged: (bool value) {
                if (_enabled) {
                  setState(() {
                    _sendRepeated = value;
                    _save();
                  });
                }
              }),
          ListTile(
              onTap: () {
                _selectTime(context);
              },
              leading: const Icon(Icons.access_time),
              title: const Text('Notification Time',
                  style: TextStyle(fontSize: 20)),
              subtitle: Text(_time.format(context)),
              trailing: const Icon(Icons.arrow_drop_up)),
          Column(children: [
            const ListTile(
                leading: Icon(Icons.calendar_month),
                title:
                    Text('Notification Days', style: TextStyle(fontSize: 20))),
            WeekdaySelector(
              onChanged: (int day) {
                setState(() {
                  final index = day % 7;
                  _weekdays[index] = !_weekdays[index];
                  _save();
                });
              },
              values: _weekdays,
            ),
          ]),
        ],
      )),
    );
  }
}

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.notif, required this.index});

  final Notification notif;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Notification Details'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
              child: Column(
            children: [
              Text(
                notif.text,
                style: const TextStyle(fontSize: 20),
              ),
              Text('Times sent: ${notif.count}',
                  style: const TextStyle(fontSize: 18)),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context, index);
                  },
                  icon: const Icon(Icons.notifications_off),
                  label: const Text('REMOVE'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    // notif.count += 1;
                    await NotificationService().sendNotif(notif.text);
                  },
                  icon: const Icon(Icons.notifications_on),
                  label: const Text('TEST'),
                ),
              ]),
            ],
          )),
        ));
  }
}

class Notification {
  final String text;
  int count;

  Notification(this.text, this.count);
}
