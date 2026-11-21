part of 'main.dart';

extension _Notifications on _HomeState {
  String _repeatLabel(ReminderRepeat repeat) => repeat.count == 0
      ? t('مرة واحدة لكل موعد', 'Once per scheduled time')
      : t(
          '${repeat.count} تكرار · كل ${repeat.minutes} دقيقة',
          '${repeat.count} repeats · every ${repeat.minutes} min',
        );

  Future<void> _openAndroidReminderSetting(
    String action, [
    String? channel,
  ]) async {
    if (!Platform.isAndroid) return;
    try {
      if (action == 'enable') {
        await _requestNotifications();
      } else {
        await platform.invokeMethod<void>(action, channel);
      }
      _changed();
    } catch (_) {
      if (mounted)
        _toast(
          t('تعذّر فتح إعدادات أندرويد.', 'Could not open Android settings.'),
        );
    }
  }

  Future<void> _notificationSettings() => _page<void>(
    (_) => ListenableBuilder(
      listenable: widget.db,
      builder: (c, _) {
        final water = data['waterReminder'] as Map? ?? {};
        final ordinary = rows(data['reminders']);
        return Scaffold(
          appBar: AppBar(
            title: Text(t('التذكيرات والتنبيهات', 'Reminders & notifications')),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              JournalCover(
                title: t('تنبيهات على وقتك', 'Reminders on your time'),
                subtitle: t(
                  'اضبط مواعيد الدوا والقياسات والمياه من مكان واحد.',
                  'Manage medication, measurement, and water reminders in one place.',
                ),
                icon: Icons.notifications_active_outlined,
                accent: mint,
              ),
              const SizedBox(height: 12),
              ControlCard(
                title: t('المياه خلال اليوم', 'Water throughout the day'),
                subtitle: water['enabled'] == true
                    ? "${clockText(water['wake'])} – ${clockText(water['sleep'])} · ${t('كل', 'Every')} ${water['interval']} ${t('دقيقة', 'min')}"
                    : t(
                        'وقت الصحو والنوم والفاصل بين التنبيهات',
                        'Wake time, bedtime, and reminder spacing',
                      ),
                icon: Icons.water_drop_outlined,
                tonalColor: ice,
                toned: true,
                onTap: _waterReminder,
              ),
              const SizedBox(height: 8),
              ControlCard(
                title: t('أضف تذكير قياس', 'Add a measurement reminder'),
                subtitle: t(
                  'اختار المتابعة، وأضف موعد واحد أو أكتر في اليوم.',
                  'Choose a tracker and one or more times per day.',
                ),
                icon: Icons.add_alarm_rounded,
                tonalColor: lavender,
                onTap: _chooseMeasurementReminder,
              ),
              const SizedBox(height: 8),
              ControlCard(
                title: t('مواعيد الأدوية', 'Medication schedules'),
                icon: Icons.medication_outlined,
                tonalColor: rose,
                onTap: () {
                  Navigator.pop(c);
                  _redraw(() => tab = 2);
                },
              ),
              const SizedBox(height: 8),
              ..._followUpShortcuts(),
              SectionTitle(
                t('تذكيراتي', 'My reminders'),
                action: TextButton(
                  onPressed: () => _reminder(),
                  child: Text(t('أضف تذكير عام', 'Add general reminder')),
                ),
              ),
              if (ordinary.isEmpty)
                Text(
                  t(
                    'أي تذكير تحفظه هيظهر هنا.',
                    'Saved reminders appear here.',
                  ),
                ),
              for (final rule in ordinary)
                Card(
                  child: ListTile(
                    leading: Icon(glyph(rule['tracker'] as String? ?? '')),
                    title: Text(rule['name']),
                    subtitle: Text(
                      reminderMinutes(rule).map(clockText).join(' · '),
                    ),
                    onTap: () => _reminder(existing: rule),
                    trailing: Switch(
                      value: rule['enabled'] == true,
                      onChanged: (on) async {
                        if (await save(
                              (d) => upsert(d, 'reminders', {
                                ...rule,
                                'enabled': on,
                              }),
                            ) &&
                            on) {
                          await _requestNotifications();
                        }
                      },
                    ),
                  ),
                ),
              SectionTitle(t('طريقة وصول التنبيه', 'How reminders arrive')),
              ControlCard(
                title: t('التكرار حسب النوع', 'Repeats by category'),
                subtitle: t(
                  'عدد التكرارات والفاصل بينها',
                  'Repeat count and spacing',
                ),
                icon: Icons.repeat_rounded,
                onTap: _repeatSettings,
              ),
              const SizedBox(height: 8),
              ControlCard(
                title: t('ساعات الهدوء', 'Quiet hours'),
                subtitle: t(
                  'كتم أو تأجيل أو تخطّي حسب نوع التذكير',
                  'Silence, defer, or skip by reminder category',
                ),
                icon: Icons.bedtime_outlined,
                onTap: _quietHours,
              ),
              if (Platform.isAndroid) ...[
                SectionTitle(
                  t('وصول الإشعارات على جهازك', 'Delivery on this device'),
                ),
                _NotificationDevicePanel(
                  ar: ar,
                  onSettings: _openAndroidReminderSetting,
                  onTest: _notificationDiagnostics,
                ),
              ],
            ],
          ),
        );
      },
    ),
  );

  Future<void> _chooseMeasurementReminder() async {
    final selected = cardPlan(data);
    final trackers = {
      ...selected.where((id) => trackerFor(data, id) != null && id != 'water'),
      ...allTrackers(data)
          .where((value) => value.kind == 'number' && value.id != 'water')
          .map((value) => value.id),
    };
    final tracker = await _sheet<String>(
      (c) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        children: [
          SectionTitle(
            t('اختار القياس أو المتابعة', 'Choose a measurement or tracker'),
          ),
          for (final id in trackers)
            ListTile(
              leading: TileIcon(id, size: 34),
              title: Text(cardName(data, id, ar)),
              onTap: () => Navigator.pop(c, id),
            ),
        ],
      ),
    );
    if (tracker != null && mounted) await _reminder(tracker: tracker);
  }

  Future<ReminderRepeat?> _repeatPicker(ReminderRepeat initial) {
    var count = initial.count, minutes = initial.minutes;
    return _sheet<ReminderRepeat>(
      (_) => StatefulBuilder(
        builder: (c, redraw) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                t('لو التنبيه لسه مفتوح', 'If the reminder is still open'),
              ),
              const SizedBox(height: 8),
              SegmentedControl(
                labels: [t('بدون', 'None'), '1', '2', '3'],
                index: count,
                onChanged: (i) => redraw(() => count = i),
              ),
              if (count > 0) ...[
                const SizedBox(height: 14),
                Text(t('الفاصل بين التكرارات', 'Time between repeats')),
                Wrap(
                  spacing: 7,
                  children: [
                    for (final value in repeatIntervals)
                      ChoiceChip(
                        label: Text('$value ${t('دقيقة', 'min')}'),
                        selected: minutes == value,
                        onSelected: (_) => redraw(() => minutes = value),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              JournalButton(
                onPressed: () =>
                    Navigator.pop(c, (count: count, minutes: minutes)),
                child: Text(t('احفظ', 'Save')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _repeatSettings() => _page<void>(
    (_) => ListenableBuilder(
      listenable: widget.db,
      builder: (c, _) {
        final prefs = data['repeatPreferences'] as Map? ?? {};
        return Scaffold(
          appBar: AppBar(title: Text(t('تكرار التنبيهات', 'Reminder repeats'))),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final (id, label, icon) in [
                (
                  'medicine',
                  t('الأدوية', 'Medication'),
                  Icons.medication_outlined,
                ),
                (
                  'tracking',
                  t(
                    'القياسات والتذكيرات العامة',
                    'Measurements and general reminders',
                  ),
                  Icons.monitor_heart_outlined,
                ),
                (
                  'habit',
                  t('المياه والعادات', 'Water and habits'),
                  Icons.water_drop_outlined,
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ControlCard(
                    title: label,
                    subtitle: _repeatLabel(readRepeat(prefs[id])),
                    icon: icon,
                    onTap: () async {
                      final chosen = await _repeatPicker(readRepeat(prefs[id]));
                      if (chosen != null && mounted) {
                        await save(
                          (d) => d['repeatPreferences'] = {
                            ...(d['repeatPreferences'] as Map? ?? {}),
                            id: {
                              'count': chosen.count,
                              'minutes': chosen.minutes,
                            },
                          },
                        );
                      }
                    },
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );

  Future<void> _waterReminder() async {
    final stored = data['waterReminder'] as Map? ?? {};
    var enabled = stored['enabled'] == true, busy = false;
    var wake = (stored['wake'] as int?) ?? 420,
        sleep = (stored['sleep'] as int?) ?? 1380;
    var interval = (stored['interval'] as int?) ?? 120,
        first = (stored['first'] as int?) ?? 30;
    final days = ints(stored['days'] ?? allDays).toSet();
    ReminderRepeat? repeat = stored['repeat'] == null
        ? null
        : readRepeat(stored['repeat']);
    await _page<void>(
      (_) => StatefulBuilder(
        builder: (c, redraw) {
          final slots = waterSlots(wake, sleep, interval, first);
          Future<void> pick(bool isWake) async {
            final current = isWake ? wake : sleep;
            final selected = await showTimePicker(
              context: c,
              initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
            );
            if (selected == null || !c.mounted) return;
            final minute = selected.hour * 60 + selected.minute;
            redraw(() {
              if (isWake) {
                wake = minute;
              } else {
                sleep = minute;
              }
            });
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(t('جدول تذكير المياه', 'Water reminder schedule')),
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: JournalButton.icon(
                  onPressed:
                      busy || (enabled && (slots.isEmpty || days.isEmpty))
                      ? null
                      : () async {
                          redraw(() => busy = true);
                          final saved = await save(
                            (d) => d['waterReminder'] = {
                              'enabled': enabled,
                              'wake': wake,
                              'sleep': sleep,
                              'interval': interval,
                              'first': first,
                              'days': days.toList()..sort(),
                              'effective': DateTime.now()
                                  .toUtc()
                                  .toIso8601String(),
                              if (repeat case final value?)
                                'repeat': {
                                  'count': value.count,
                                  'minutes': value.minutes,
                                },
                            },
                          );
                          if (!c.mounted) return;
                          if (saved) {
                            Navigator.pop(c);
                            if (enabled) await _requestNotifications();
                          } else {
                            redraw(() => busy = false);
                          }
                        },
                  icon: const Icon(Icons.check_rounded),
                  label: Text(t('احفظ جدول المياه', 'Save water schedule')),
                ),
              ),
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                JournalCover(
                  title: t(
                    'افتكر المياه وإنت صاحي',
                    'Water reminders while you’re awake',
                  ),
                  subtitle: t(
                    'اختار ساعاتك وشوف المواعيد قبل ما تحفظ.',
                    'Set your hours and preview the schedule before saving.',
                  ),
                  icon: Icons.water_drop_outlined,
                  accent: ice,
                ),
                SwitchListTile(
                  title: Text(t('فعّل جدول المياه', 'Enable water schedule')),
                  value: enabled,
                  onChanged: (on) => redraw(() => enabled = on),
                ),
                ControlCard(
                  title: t('وقت الصحو', 'Wake time'),
                  subtitle: clockText(wake),
                  icon: Icons.wb_sunny_outlined,
                  onTap: () => pick(true),
                ),
                const SizedBox(height: 8),
                ControlCard(
                  title: t('وقت النوم', 'Bedtime'),
                  subtitle: clockText(sleep),
                  icon: Icons.bedtime_outlined,
                  onTap: () => pick(false),
                ),
                SectionTitle(t('الفاصل بين التنبيهات', 'Reminder spacing')),
                Wrap(
                  spacing: 7,
                  children: [
                    for (final value in waterIntervals)
                      ChoiceChip(
                        label: Text('$value ${t('دقيقة', 'min')}'),
                        selected: value == interval,
                        onSelected: (_) => redraw(() => interval = value),
                      ),
                  ],
                ),
                SectionTitle(
                  t('أول تنبيه بعد الصحو', 'First reminder after waking'),
                ),
                Wrap(
                  spacing: 7,
                  children: [
                    for (final value in firstWaterDelays)
                      ChoiceChip(
                        label: Text(
                          value == 0
                              ? t('وقت الصحو', 'At wake time')
                              : '$value ${t('دقيقة', 'min')}',
                        ),
                        selected: value == first,
                        onSelected: (_) => redraw(() => first = value),
                      ),
                  ],
                ),
                SectionTitle(t('أيام الصحو المختارة', 'Wake-up days')),
                _weekdayChips(days, redraw),
                const SizedBox(height: 8),
                ControlCard(
                  title: t('تكرار نفس التنبيه', 'Repeat the same reminder'),
                  subtitle: repeat == null
                      ? t(
                          'يتبع إعداد المياه والعادات',
                          'Follows Water and habits',
                        )
                      : _repeatLabel(repeat!),
                  icon: Icons.repeat_rounded,
                  onTap: () async {
                    final value = await _repeatPicker(
                      repeat ??
                          readRepeat(
                            (data['repeatPreferences'] as Map?)?['habit'],
                          ),
                    );
                    if (value != null && c.mounted)
                      redraw(() => repeat = value);
                  },
                ),
                if (repeat != null)
                  TextButton(
                    onPressed: () => redraw(() => repeat = null),
                    child: Text(t('اتبع إعداد النوع', 'Use category setting')),
                  ),
                SectionTitle(t('معاينة المواعيد', 'Schedule preview')),
                if (slots.isEmpty)
                  Text(
                    t(
                      'اختار وقت نوم مختلف وخلي أول تنبيه جوّه الفترة.',
                      'Choose a different bedtime and keep the first reminder inside the window.',
                    ),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final slot in slots)
                        Chip(
                          label: Text(
                            [
                              clockText(slot.minute),
                              if (slot.shift > 0) t('تاني يوم', 'next day'),
                            ].join(' · '),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NotificationDevicePanel extends StatefulWidget {
  const _NotificationDevicePanel({
    required this.ar,
    required this.onSettings,
    required this.onTest,
  });
  final bool ar;
  final Future<void> Function(String, [String?]) onSettings;
  final VoidCallback onTest;

  @override
  State<_NotificationDevicePanel> createState() =>
      _NotificationDevicePanelState();
}

class _NotificationDevicePanelState extends State<_NotificationDevicePanel>
    with WidgetsBindingObserver {
  JournalRow? _status;
  String t(String a, String e) => tr(widget.ar, a, e);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      final status = await platform.invokeMapMethod<String, dynamic>(
        'notificationDiagnostics',
      );
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) setState(() => _status = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final channels = status?['channels'] as Map? ?? {};
    final stamp = status?['next'];
    final next = stamp is int && stamp > 0
        ? DateTime.fromMillisecondsSinceEpoch(stamp)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (next != null)
          Text(
            "${t('أقرب تنبيه على الجهاز', 'Next scheduled alert')} · ${DateFormat('EEE HH:mm', widget.ar ? 'ar' : 'en').format(next)}",
          ),
        if (status != null && status['allowed'] != true)
          TextButton.icon(
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () async {
              await widget.onSettings('enable');
              await _refresh();
            },
            label: Text(t('فعّل إذن الإشعارات', 'Allow notifications')),
          ),
        if (status != null && status['allowed'] != true)
          TextButton(
            onPressed: () => widget.onSettings('settings'),
            child: Text(
              t(
                'افتح أذونات يومي في أندرويد',
                'Open Yawmi notification permissions in Android',
              ),
            ),
          ),
        ControlCard(
          title: t('دقة المواعيد', 'Alarm precision'),
          subtitle: status?['exact'] == true
              ? t('الجدولة الدقيقة متاحة', 'Exact scheduling is available')
              : t(
                  'الجدولة تقريبية. افتح إعدادات المنبّهات.',
                  'Scheduling is approximate. Open alarm settings.',
                ),
          icon: Icons.alarm_outlined,
          onTap: () => widget.onSettings('exact'),
        ),
        const SizedBox(height: 8),
        ControlCard(
          title: t('تشغيل التطبيق في الخلفية', 'Background activity'),
          subtitle: status?['restricted'] == true
              ? t(
                  'أندرويد مقيّد تشغيل يومي في الخلفية',
                  'Android is restricting Yawmi in the background',
                )
              : t('راجع إعدادات بطارية يومي', 'Review Yawmi battery settings'),
          icon: Icons.battery_saver_outlined,
          onTap: () => widget.onSettings('battery'),
        ),
        for (final (id, label) in [
          (
            'medicine',
            t('صوت وتنبيهات الأدوية', 'Medication sound and alerts'),
          ),
          (
            'tracking',
            t('صوت وتنبيهات القياسات', 'Measurement sound and alerts'),
          ),
          (
            'habit',
            t(
              'صوت وتنبيهات المياه والعادات',
              'Water and habit sound and alerts',
            ),
          ),
        ])
          ListTile(
            title: Text(label),
            subtitle: channels[id] == false
                ? Text(
                    t(
                      'القناة مقفولة في أندرويد',
                      'Channel disabled in Android',
                    ),
                  )
                : null,
            leading: const Icon(Icons.volume_up_outlined),
            onTap: () => widget.onSettings('channel', id),
          ),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: widget.onTest,
                child: Text(t('اختبر وصول التنبيه', 'Test a notification')),
              ),
            ),
            IconButton(
              tooltip: t('حدّث الحالة', 'Refresh status'),
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ],
    );
  }
}
