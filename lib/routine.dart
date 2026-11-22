part of 'main.dart';

class _QuietBand extends CustomPainter {
  const _QuietBand(this.start, this.end, this.progress);
  final int start, end;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(8);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, radius));
    canvas.drawColor(const Color(0xff4c3e64), BlendMode.src);
    final length = (end - start + 1440) % 1440;
    final stop = start + length * progress;
    final paint = Paint()..color = mint;
    canvas.drawRect(
      Rect.fromLTRB(
        size.width * start / 1440,
        0,
        size.width * math.min(stop, 1440) / 1440,
        size.height,
      ),
      paint,
    );
    if (stop > 1440) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * (stop - 1440) / 1440, size.height),
        paint,
      );
    }
    for (final tick in [360, 720, 1080]) {
      final x = size.width * tick / 1440;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()..color = night.withValues(alpha: .6),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_QuietBand old) =>
      old.start != start || old.end != end || old.progress != progress;
}

List<JournalRow> notificationRules(
  JournalRow state,
  bool ar, {
  DateTime? clock,
}) {
  final doses = (state['doses'] as List? ?? []).cast<JournalRow>();
  final meds = rows(state['meds']);
  final now = clock ?? DateTime.now();
  final rules = <JournalRow>[
    for (final med in rows(
      state['meds'],
    ).where((m) => m['notify'] == true && m['archived'] != true))
      for (final minute in ints(med['times']))
        {
          'id': [med['id'], med['revision'], minute].join(':'),
          'minute': minute,
          'days': med['days'],
          'start': med['start'],
          'end': med['end'],
          'effective': med['effective'],
          'medicine': med['id'],
          'revision': med['revision'],
          'type': 'medicine',
          'title': tr(ar, 'موعد دواء في يومي', 'Medication reminder'),
          'maxDelay': minutesUntilNextSlot(ints(med['times']), minute),
          if (med['repeat'] != null) 'repeat': med['repeat'],
        },
    for (final r in trackingSchedules(state, ar))
      {
        'id': r['id'],
        'revision': r['revision'] ?? 1,
        'minute': r['minute'],
        'days': r['days'],
        'start': r['start'],
        'end': r['end'],
        'effective': r['effective'],
        if (r['shiftMinutes'] != null) ...{
          'shiftMinutes': r['shiftMinutes'],
          'shiftStart': r['shiftStart'],
          'shiftEnd': r['shiftEnd'],
        },
        if (r['maxDelay'] != null) 'maxDelay': r['maxDelay'],
        'type': r['tracker'] == 'water' || r['tracker'] == 'sleep'
            ? 'habit'
            : 'tracking',
        'title': r['waterPlan'] == true
            ? tr(ar, 'وقت شرب المياه', 'Time for a drink of water')
            : tr(ar, 'تذكير من يومي', 'Yawmi reminder'),
        'route': r['tracker'] == null
            ? 'routine'
            : 'add/${r['tracker'] as String}',
        'tracker': r['tracker'],
        if (r['repeat'] != null) 'repeat': r['repeat'],
      },
    for (final med in meds.where((m) => m['archived'] != true)) ...[
      ..._stockReminderRules(med, doses, ar, now),
      if (DateAlert.read(med['expiry']) case final expiry?)
        ...dateAlertRules(
          expiry,
          id: "expiry:${med['id']}",
          title: tr(
            ar,
            'راجع صلاحية دوائك في يومي',
            'Check medication expiry in Yawmi',
          ),
          route: "expiry/${med['id']}",
          now: now,
        ),
      for (final pack in rows(med['packs']))
        if ((pack['count'] as num) > 0)
          if (DateAlert.read(pack['expiry']) case final expiry?)
            ...dateAlertRules(
              expiry,
              id: "expiry:${med['id']}:${pack['id']}",
              title: tr(
                ar,
                'راجع صلاحية عبوة دواء في يومي',
                'Check a package expiry in Yawmi',
              ),
              route: "packs/${med['id']}",
              now: now,
            ),
    ],
    for (final followUp in pendingFollowUps(state))
      if (DateAlert.read(followUp['alert']) case final alert?)
        ...dateAlertRules(
          alert,
          id: "follow-up:${followUp['id']}",
          title: tr(ar, 'موعد متابعة في يومي', 'Yawmi follow-up reminder'),
          route: "follow-up/${followUp['id']}",
          now: now,
        ),
    for (final e in rows(state['snoozes']))
      if (DateTime.parse(
            e['when'],
          ).isAfter(DateTime.now().subtract(const Duration(days: 1))) &&
          doseEvent(state, e['id']) == null &&
          rows(state['meds']).any(
            (m) =>
                m['id'] == e['medicine'] &&
                m['revision'] == e['revision'] &&
                m['archived'] != true &&
                m['notify'] == true,
          ))
        {
          ...e,
          'id': 'snooze:${e['id'] as String}',
          'type': 'medicine',
          'title': tr(ar, 'تذكير بجرعة في يومي', 'Yawmi dose reminder'),
          'repeat': meds
              .where((med) => med['id'] == e['medicine'])
              .firstOrNull?['repeat'],
        },
  ];
  final quiet = state['quiet'] as Map? ?? {};
  final defaults = state['repeatPreferences'] as Map? ?? {};
  return rules.map((r) {
    final repeat = readRepeat(r['repeat'] ?? defaults[r['type']]);
    return {
      ...r,
      'quiet': quiet[r['type']],
      'repeatCount': r['stableOnce'] == true ? 0 : repeat.count,
      'repeatMinutes': repeat.minutes,
    };
  }).toList();
}

Iterable<JournalRow> _stockReminderRules(
  JournalRow med,
  List<JournalRow> doses,
  bool ar,
  DateTime now,
) sync* {
  final balance = medicationStockBalance(med, doses);
  if (balance == null) return;
  final lead = med['forecastLead'];
  if (lead is int && _forecastLeadDays.contains(lead)) {
    final date = projectedRefill(med, balance, now, doses: doses);
    if (date != null) {
      final target = shiftCalendarDate(date, -lead);
      final today = DateUtils.dateOnly(now);
      final scheduled = target.isBefore(today) ? today : target;
      final at = DateTime(scheduled.year, scheduled.month, scheduled.day, 9);
      yield {
        'id': 'forecast:${med['id']}:${balance.stock.cycle}:$lead',
        'stableOnce': true,
        'type': 'tracking',
        'when': at.toUtc().toIso8601String(),
        'graceMinutes': 900,
        'route': 'stock/${med['id']}',
        'title': tr(
          ar,
          'راجع موعد نفاد مخزون الدوا',
          'Review estimated medication runout',
        ),
      };
    }
  }
  if (!balance.stock.notify || balance.lowSince == null) return;
  final lowSince = balance.lowSince!;
  final enabledAt = balance.stock.alertsEnabledAt;
  final first = enabledAt != null && enabledAt.isAfter(lowSince)
      ? enabledAt
      : lowSince;
  final id = "stock:${med['id']}:${balance.stock.cycle}";
  final base = {
    'type': 'tracking',
    'graceMinutes': 360,
    'title': tr(ar, 'مخزون دواء قرب يخلص', 'Medication stock is running low'),
    'route': "stock/${med['id']}",
    'repeat': {'count': 0},
  };
  yield {
    ...base,
    'id': id,
    'stableOnce': true,
    'when': first.add(const Duration(seconds: 1)).toUtc().toIso8601String(),
  };
  final interval = readStockInterval(balance.stock.repeatDays);
  if (interval == 0) return;
  yield {
    ...base,
    'id': '$id:repeat',
    'start': dayKey(first.toLocal()),
    'minute': readAlertMinute(balance.stock.repeatMinute),
    'days': allDays,
    'intervalDays': interval,
  };
}

extension _Routine on _HomeState {
  Widget routine() {
    final meds = rows(data['meds']);
    final doses = dosesOn(data, now);
    final reminders = rows(data['reminders']);
    final doseHistory = rows(data['doses']);
    final pending = doses
        .where((dose) => doseEvent(data, dose.id) == null)
        .length;
    final logged = doses.length - pending;
    final visibleDoses = doses.where((dose) {
      final event = doseEvent(data, dose.id);
      return switch (_doseFilter) {
        1 => event == null,
        2 => event != null,
        _ => true,
      };
    }).toList();
    String permissionText() => !_notifying
        ? t('الإشعارات مقفولة', 'Notifications are off')
        : _exact
        ? t('التوقيت الدقيق متاح', 'Exact reminders available')
        : t(
            'الإشعارات شغالة · التوقيت تقريبي',
            'Notifications on · approximate timing',
          );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 7, 18, 35),
      children: [
        Enter(
          child: _FieldBanner(
            title: t('مواعيدك', 'Your routine'),
            detail: prettyDate(now, 'EEEE، d MMMM'),
            accent: honey,
            action: IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: honey,
                foregroundColor: ink,
              ),
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _medicine(),
              tooltip: t('أضف دواء', 'Add medication'),
            ),
            bottom: Row(
              children: [
                Expanded(
                  child: _FieldMetric(
                    value: '$logged/${doses.length}',
                    label: t('جرعات مسجّلة', 'Doses logged'),
                    icon: Icons.task_alt_rounded,
                    accent: leaf,
                    onTap: () => _redraw(() => _doseFilter = 2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FieldMetric(
                    value: '$pending',
                    label: t('جرعات منتظرة', 'Doses pending'),
                    icon: Icons.schedule_rounded,
                    accent: honey,
                    onTap: () => _redraw(() => _doseFilter = 1),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 11),
        ControlCard(
          icon: _notifying
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          title: permissionText(),
          tonalColor: honey,
          onTap: _notificationSettings,
        ),
        const SizedBox(height: 8),
        ..._followUpShortcuts(),
        SectionTitle(t('مواعيد اليوم', 'Today’s schedule')),
        if (doses.isNotEmpty) ...[
          SegmentedControl(
            labels: [
              t('الكل', 'All'),
              t('منتظرة', 'Pending'),
              t('مسجّلة', 'Logged'),
            ],
            index: _doseFilter,
            onChanged: (value) => _redraw(() => _doseFilter = value),
          ),
          const SizedBox(height: 9),
          if (visibleDoses.isEmpty)
            EmptyPanel(
              Icons.event_available_outlined,
              _doseFilter == 1
                  ? t('مفيش جرعات منتظرة', 'No pending doses')
                  : t('لسه مفيش جرعات مسجّلة', 'No doses logged yet'),
              '',
            ),
        ],
        if (doses.isEmpty)
          EmptyPanel(
            Icons.event_available,
            t('يومك من غير جرعات مجدولة', 'No scheduled doses today'),
            t(
              'أضف دواء وحدّد المواعيد اللي كتبتها لنفسك.',
              'Add a medication and enter your schedule.',
            ),
            action: OutlinedButton(
              onPressed: () => _medicine(),
              child: Text(t('أضف دواء', 'Add medication')),
            ),
          ),
        for (final (index, dose) in visibleDoses.indexed)
          Enter(
            key: ValueKey(dose.id),
            delay: index.clamp(0, 6) * 35,
            child: _doseTile(dose),
          ),
        SectionTitle(
          t('أدويتي', 'My medications'),
          action: IconButton(
            onPressed: () => _medicine(),
            icon: const Icon(Icons.add_circle_outline),
            tooltip: t('دواء جديد', 'New medication'),
          ),
        ),
        for (final med in meds)
          _routineMedicine(med, medicationStockBalance(med, doseHistory)),
        Card(
          child: ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: Text(t('التكيّف مع روتينك', 'Adaptive routine')),
            subtitle: Text(
              t(
                'اقتراحات التذكير وسجل تغييراتها',
                'Reminder suggestions and adjustment history',
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _adaptiveSettings,
          ),
        ),
        SectionTitle(
          t('تذكيراتي', 'My reminders'),
          action: IconButton(
            onPressed: () => _reminder(),
            icon: const Icon(Icons.add_alarm),
            tooltip: t('تذكير جديد', 'New reminder'),
          ),
        ),
        if (reminders.isEmpty)
          EmptyPanel(
            Icons.alarm,
            t('اضبط تذكير على يومك', 'Set a reminder for your day'),
            t(
              'أضف تذكيرًا لمتابعة أو مهمة من اختيارك.',
              'Choose a tracker or a task to remind yourself about.',
            ),
          ),
        for (final r in reminders) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.alarm),
              title: Text(r['name']),
              subtitle: Text(
                reminderMinutes(r).map(clockText).join(' · ') +
                    (r['flexible'] == true
                        ? t(' · وقت مرن', ' · flexible')
                        : ''),
              ),
              onTap: () => _reminder(existing: r),
              trailing: Switch(
                value: r['enabled'] == true,
                onChanged: (on) async {
                  if (await save(
                        (d) => upsert(d, 'reminders', {...r, 'enabled': on}),
                      ) &&
                      on) {
                    await _requestNotifications();
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 5),
          if (_suggestion(r) case (final int minute, final int count))
            _learningCard(r, minute, count),
          if (r['previousMinute'] is int)
            TextButton.icon(
              onPressed: () => _undoAdjustment(r['id'], r['revision']),
              icon: const Icon(Icons.undo),
              label: Text(t('تراجع عن آخر ضبط', 'Undo last adjustment')),
            ),
        ],
        if (reminders.any((r) => r['learn'] != 'off') ||
            data['layoutLearning'] != null ||
            rows(data['widgets']).any((w) => w['layoutLearning'] != null))
          TextButton(
            onPressed: _clearLearning,
            child: Text(t('امسح سجل التعلّم', 'Clear learning history')),
          ),
      ],
    );
  }

  Widget _routineMedicine(JournalRow med, StockBalance? balance) {
    final schedule = med['archived'] == true
        ? t('مؤرشف', 'Archived')
        : _legacyScheduleNeedsReview(med)
        ? t('جدول مستورد يحتاج مراجعة', 'Imported schedule needs review')
        : ints(med['times']).isEmpty
        ? t('عند الحاجة', 'As needed')
        : ints(med['times']).map(clockText).join(' · ');
    final low =
        med['archived'] != true &&
        balance != null &&
        balance.remaining <= balance.stock.threshold;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Card(
        child: ListTile(
          leading: const TileIcon('medicine'),
          title: Text(med['name']),
          subtitle: Text(
            low
                ? '$schedule · ${t('راجع المخزون', 'Check stock')} (${number(balance.remaining)})'
                : schedule,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _medDetails(med['id']),
        ),
      ),
    );
  }

  Widget _doseTile(Dose dose) {
    final event = doseEvent(data, dose.id);
    final status = event?['status'];
    final meal = doseMealLabel(
      event == null ? dose.mealSlot : event['mealSlot'],
      ar,
    );
    final recorded = status == 'taken';
    final scheduled = status == null && dose.time.isAfter(now);
    final panel = recorded
        ? mint
        : status == 'skipped'
        ? rose
        : scheduled
        ? ice
        : honey;
    final text = recorded
        ? t('اتسجّل', 'Taken')
        : status == 'skipped'
        ? t('متخطّية', 'Skipped')
        : dose.time.isAfter(now)
        ? t('قادمة', 'Upcoming')
        : t('فات الموعد ولسه ما اتسجّلش', 'Time passed · awaiting entry');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 53,
            child: Column(
              children: [
                Text(
                  clockText(dose.minute),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  width: 1,
                  height: 26,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Pressable(
              onTap: () => _actDose(dose),
              radius: 18,
              child: UpdateFlash(
                value: status,
                color: Colors.white,
                child: AnimatedContainer(
                  duration: motion(context, 460),
                  curve: motionArrival,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dose.medicine['name'],
                              style: const TextStyle(
                                color: ink,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              [text, ?meal].join(' · '),
                              style: const TextStyle(color: ink, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: motion(context, 290),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                              scale: CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutBack,
                              ),
                              child: child,
                            ),
                        child: recorded
                            ? const SaveSeal(
                                key: ValueKey('taken'),
                                color: honey,
                              )
                            : CircleAvatar(
                                key: ValueKey(status),
                                radius: 17,
                                backgroundColor: night,
                                foregroundColor: panel,
                                child: Icon(
                                  status == 'skipped'
                                      ? Icons.skip_next
                                      : scheduled
                                      ? Icons.schedule
                                      : Icons.add,
                                  size: 17,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestNotifications() async {
    if (!Platform.isAndroid || _notifying) return;
    try {
      await platform.invokeMethod<void>('permission');
      _changed();
    } catch (_) {
      _toast(
        t(
          'افتح إعدادات أندرويد لتفعيل الإشعارات.',
          'Open Android settings to enable notifications.',
        ),
      );
    }
  }

  Future<void> _notificationDiagnostics() async {
    var channel = 'tracking';
    Future<JournalRow?> status({bool test = false, bool locked = false}) async {
      try {
        return await platform.invokeMapMethod<String, dynamic>(
          test ? 'testNotification' : 'notificationDiagnostics',
          test ? {'arabic': ar, 'channel': channel, 'locked': locked} : null,
        );
      } catch (_) {
        return null;
      }
    }

    var reading = await status();
    if (!mounted) return;
    Timer? updates;
    var busy = false;
    String stamp(Object? milliseconds) =>
        milliseconds is int && milliseconds > 0
        ? prettyDate(
            DateTime.fromMillisecondsSinceEpoch(milliseconds),
            'd MMM · HH:mm',
          )
        : t('لسه مفيش', 'None yet');
    try {
      await _sheet<void>(
        (_) => StatefulBuilder(
          builder: (c, redraw) {
            Future<void> refresh({
              bool test = false,
              bool locked = false,
            }) async {
              if (busy) return;
              redraw(() => busy = true);
              final next = await status(test: test, locked: locked);
              if (!c.mounted) return;
              redraw(() {
                reading = next;
                busy = false;
              });
            }

            updates ??= Timer.periodic(const Duration(seconds: 3), (_) {
              if (c.mounted &&
                  (reading?['state'] as String?)?.startsWith('queued') ==
                      true) {
                unawaited(refresh());
              }
            });
            final result = switch (reading?['state']) {
              'queuedExact' => t(
                'متجدول للوقت الموضّح',
                'Scheduled for the time shown',
              ),
              'queuedApproximate' => t(
                'متجدول · أندرويد ممكن يأخّره',
                'Scheduled · Android may delay it',
              ),
              'posted' => t(
                'أندرويد استلم طلب عرض التنبيه',
                'Android accepted the notification',
              ),
              'blocked' => t(
                'إذن الإشعارات مقفول',
                'Notification permission is off',
              ),
              'channelBlocked' => t(
                'القناة المختارة مقفولة في أندرويد',
                'The selected channel is disabled in Android',
              ),
              'interrupted' => t(
                'أُعيد تشغيل الجهاز. جرّب تاني.',
                'Device restarted. Run another test.',
              ),
              _ => t('جاهز للاختبار', 'Ready to test'),
            };
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  JournalCover(
                    title: t('فحص التنبيهات', 'Notification check'),
                    subtitle: t(
                      'ابعث تنبيهًا تجريبيًا على جهازك.',
                      'Send a test notification to this device.',
                    ),
                    icon: Icons.notifications_active_outlined,
                    accent: honey,
                  ),
                  const SizedBox(height: 12),
                  if (reading == null)
                    Text(
                      t(
                        'ماقدرناش نعرض حالة التنبيهات. جرّب تاني.',
                        'Could not read notification status.',
                      ),
                    )
                  else ...[
                    Text(
                      reading!['allowed'] == true
                          ? t(
                              'إذن الإشعارات مفعّل',
                              'Notification permission is on',
                            )
                          : t(
                              'إذن الإشعارات مقفول',
                              'Notification permission is off',
                            ),
                    ),
                    Text(
                      reading!['exact'] == true
                          ? t(
                              'الجدولة على وقت محدد متاحة',
                              'Exact scheduling is available',
                            )
                          : t('الجدولة تقريبية', 'Scheduling is approximate'),
                    ),
                    Text(
                      '${t('قواعد متجدولة', 'Scheduled rules')} · ${reading!['scheduled']}',
                    ),
                    Text(
                      '${t('آخر تذكير أُرسل', 'Last reminder posted')} · ${stamp(reading!['lastReminder'])}',
                    ),
                    if ((reading!['lastReminder'] as int? ?? 0) > 0)
                      Text(
                        "${t('التأخير قبل طلب العرض', 'Delay before posting')} · ${((reading!['delay'] as int? ?? 0) / 1000).round()} ${t('ثانية', 'sec')}",
                      ),
                    const SizedBox(height: 8),
                    Semantics(
                      liveRegion: true,
                      child: Text('$result · ${stamp(reading!['at'])}'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    children: [
                      for (final (id, name) in [
                        ('medicine', t('الأدوية', 'Medication')),
                        ('tracking', t('القياسات', 'Measurements')),
                        ('habit', t('المياه والعادات', 'Water and habits')),
                      ])
                        ChoiceChip(
                          label: Text(name),
                          selected: id == channel,
                          onSelected: busy
                              ? null
                              : (_) => redraw(() => channel = id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  JournalButton.icon(
                    onPressed: busy ? null : () => refresh(test: true),
                    icon: const Icon(Icons.alarm_add_rounded),
                    label: Text(
                      t('جدول تنبيه تجريبي', 'Schedule a test notification'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            await refresh(test: true, locked: true);
                            if (c.mounted)
                              _toast(
                                t(
                                  'اقفل الشاشة دلوقتي وراجع بعد دقيقة.',
                                  'Lock the screen now and check after a minute.',
                                ),
                              );
                          },
                    icon: const Icon(Icons.lock_clock_outlined),
                    label: Text(
                      t(
                        'اختبار والشاشة مقفولة · بعد دقيقة',
                        'Lock-screen test · in one minute',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => refresh(),
                    child: Text(t('حدّث الحالة', 'Refresh status')),
                  ),
                  SectionTitle(
                    t('آخر طلبات عرض التنبيه', 'Recent notification requests'),
                  ),
                  if ((reading?['audit'] as List? ?? []).isEmpty)
                    Text(
                      t(
                        'لسه مفيش طلبات في السجل.',
                        'There are no requests in the log yet.',
                      ),
                    ),
                  for (final item in (reading?['audit'] as List? ?? []).take(
                    15,
                  ))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        item['state'] == 'posted'
                            ? Icons.check_circle_outline
                            : Icons.schedule_outlined,
                      ),
                      title: Text(switch (item['kind']) {
                        'test' => t('اختبار', 'Test'),
                        'medicine' => t('دوا', 'Medication'),
                        'habit' => t('مياه وعادات', 'Water and habits'),
                        _ => t('متابعة', 'Tracking'),
                      }),
                      subtitle: Text(
                        [
                          '${t('الموعد', 'Scheduled')} · ${stamp(item['due'])}',
                          if (item['state'] == 'posted')
                            '${t('طلب العرض', 'Posted to Android')} · ${stamp(item['actual'])} · ${math.max(0, ((item['actual'] as int) - (item['due'] as int)) ~/ 1000)} ${t('ث', 'sec')}',
                          if (item['state'] == 'blocked')
                            t('الإذن مقفول', 'Permission blocked'),
                          if (item['state'] == 'channelBlocked')
                            t('القناة مقفولة', 'Channel blocked'),
                          if ((item['state'] as String).startsWith('queued'))
                            t('اتجدول', 'Queued'),
                        ].join('\n'),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      );
    } finally {
      updates?.cancel();
    }
  }

  Future<void> _quietHours() async {
    final stored = data['quiet'] as Map? ?? {};
    final settings = <String, JournalRow>{
      for (final category in ['medicine', 'tracking', 'habit'])
        category: {
          'mode': 'off',
          'start': 1320,
          'end': 420,
          ...?(stored[category] as Map?),
        },
    };
    final labels = [
      t('الأدوية', 'Medication'),
      t('القياسات', 'Tracking'),
      t('العادات', 'Habits'),
    ];
    var selected = 0;
    await _page<void>(
      (_) => StatefulBuilder(
        builder: (c, redraw) {
          final colors = Theme.of(c).colorScheme;
          final category = settings.keys.elementAt(selected);
          final setting = settings[category]!;
          final active = setting['mode'] != 'off';
          final start = setting['start'] as int, end = setting['end'] as int;
          final modes = [
            ('off', t('إيقاف فترة الهدوء', 'Quiet period off')),
            ('silent', t('إشعار صامت', 'Silent notification')),
            ('defer', t('نبّه بعد انتهاء الهدوء', 'Notify after quiet hours')),
            ('skip', t('داخل التطبيق فقط', 'In-app only')),
          ];
          Future<void> choose(String key, int old) async {
            final next = await showTimePicker(
              context: c,
              initialTime: TimeOfDay(hour: old ~/ 60, minute: old % 60),
            );
            if (c.mounted && next != null)
              redraw(() => setting[key] = next.hour * 60 + next.minute);
          }

          return Scaffold(
            appBar: AppBar(title: Text(t('ساعات الهدوء', 'Quiet hours'))),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: [
                JournalCover(
                  title: t('اختار وقت هدوئك', 'Choose your quiet time'),
                  subtitle: t(
                    'الموعد الأصلي يظل ظاهر في روتيني.',
                    'The original time stays visible in Routine.',
                  ),
                  icon: Icons.bedtime_outlined,
                  accent: lavender,
                ),
                const SizedBox(height: 14),
                SegmentedControl(
                  labels: labels,
                  index: selected,
                  onChanged: (i) => redraw(() => selected = i),
                ),
                const SizedBox(height: 12),
                _choiceSetting(
                  c,
                  t('أثناء الهدوء', 'During quiet hours'),
                  setting['mode'],
                  modes,
                  (mode) => redraw(() => setting['mode'] = mode),
                  icon: Icons.notifications_off_outlined,
                ),
                AnimatedSize(
                  duration: motion(c, 250),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: active
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 12),
                            Semantics(
                              label: [
                                t('فترة الهدوء', 'Quiet window'),
                                clockText(start),
                                clockText(end),
                              ].join(' '),
                              child: ExcludeSemantics(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: night,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        textDirection: TextDirection.ltr,
                                        children: [
                                          for (final hour in [
                                            '00:00',
                                            '06:00',
                                            '12:00',
                                            '18:00',
                                            '00:00',
                                          ])
                                            Flexible(
                                              child: Text(
                                                hour,
                                                style: const TextStyle(
                                                  color: lavender,
                                                  fontFamily: 'Manrope',
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 9),
                                      RepaintBoundary(
                                        child: TweenAnimationBuilder<double>(
                                          key: ValueKey([start, end].join('/')),
                                          tween: Tween(begin: 0, end: 1),
                                          duration: motion(c, 340),
                                          curve: Curves.easeOutCubic,
                                          builder: (_, progress, _) => SizedBox(
                                            height: 13,
                                            width: double.infinity,
                                            child: CustomPaint(
                                              painter: _QuietBand(
                                                start,
                                                end,
                                                progress,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ControlCard(
                              title: t('البداية', 'Starts'),
                              subtitle: clockText(start),
                              icon: Icons.bedtime_outlined,
                              onTap: () => choose('start', start),
                            ),
                            const SizedBox(height: 8),
                            ControlCard(
                              title: t('النهاية', 'Ends'),
                              subtitle: clockText(end),
                              icon: Icons.wb_sunny_outlined,
                              tonalColor: honey,
                              onTap: () => choose('end', end),
                            ),
                            if (start == end)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  t(
                                    'اختار وقتين مختلفين للفترة.',
                                    'Choose two different times for the quiet window.',
                                  ),
                                  style: TextStyle(color: colors.error),
                                ),
                              ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: JournalButton(
                  onPressed:
                      settings.values.any(
                        (s) => s['mode'] != 'off' && s['start'] == s['end'],
                      )
                      ? null
                      : () async {
                          if (await save((d) => d['quiet'] = settings) &&
                              c.mounted)
                            Navigator.pop(c);
                        },
                  child: Text(t('احفظ', 'Save')),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _medicine({JournalRow? existing}) async {
    var name = existing?['name'] as String? ?? '';
    var scanRevision = 0;
    var directions = existing?['directions'] as String? ?? '';
    var amount = existing?['amount'] as String? ?? '';
    var strength = existing?['strength'] as String? ?? '';
    var administration = existing?['administration'] as String? ?? '';
    final times = ints(existing?['times']).toSet();
    final meals = readDoseMeals(existing?['mealSlots'], times);
    final days = ints(existing?['days'] ?? allDays).toSet();
    var asNeeded = existing != null && times.isEmpty;
    var notify = existing?['notify'] == true, busy = false;
    ReminderRepeat? repeat = existing?['repeat'] == null
        ? null
        : readRepeat(existing?['repeat']);
    var start = DateTime.tryParse(existing?['start'] ?? '') ?? DateTime.now();
    var end = DateTime.tryParse(existing?['end'] ?? '');
    final links = strings(existing?['links']).toSet();
    final id = existing?['id'] as String? ?? newId();
    final form = GlobalKey<FormState>();
    await _page<void>(
      (_) => StatefulBuilder(
        builder: (c, redraw) => Scaffold(
          appBar: AppBar(
            title: Text(
              existing == null
                  ? t('أضف دواء', 'Add medication')
                  : t('تعديل الدواء', 'Edit medication'),
            ),
          ),
          body: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
              children: [
                JournalCover(
                  title: existing == null
                      ? t('جدول دواء', 'Medication schedule')
                      : existing['name'],
                  subtitle: t(
                    'اكتب الاسم وحدّد طريقة التسجيل.',
                    'Name the medication and set how you log it.',
                  ),
                  icon: Icons.medication_outlined,
                  accent: mint,
                ),
                const SizedBox(height: 16),
                if (Platform.isAndroid)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              final scan = await _scanFields({
                                'name': (
                                  t('اسم الدوا', 'Medication name'),
                                  ScanField.label,
                                ),
                              });
                              if (!c.mounted || scan?['name'] == null) return;
                              redraw(() {
                                name = scan!['name']!;
                                scanRevision++;
                              });
                            },
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: Text(
                        t('اقرأ الاسم من العبوة', 'Read name from package'),
                      ),
                    ),
                  ),
                TextFormField(
                  key: ValueKey(('medicine-name', scanRevision)),
                  initialValue: name,
                  maxLength: 100,
                  onChanged: (v) => name = v,
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? t('اكتب اسم الدواء', 'Enter a medication name')
                      : null,
                  decoration: InputDecoration(
                    labelText: t('اسم الدواء', 'Medication name'),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 9),
                TextFormField(
                  initialValue: amount,
                  maxLength: 80,
                  onChanged: (v) => amount = v,
                  decoration: InputDecoration(
                    labelText: t(
                      'الجرعة كما كتبتها (اختياري)',
                      'Your dose text (optional)',
                    ),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 9),
                _careTextField(
                  t(
                    'تركيز الدواء حسب العبوة',
                    'Strength as written on the package',
                  ),
                  strength,
                  (value) => strength = value,
                ),
                _careTextField(
                  t('طريقة الاستخدام', 'Route of administration'),
                  administration,
                  (value) => administration = value,
                ),
                TextFormField(
                  initialValue: directions,
                  maxLength: 600,
                  maxLines: 2,
                  onChanged: (v) => directions = v,
                  decoration: InputDecoration(
                    labelText: t(
                      'تعليماتك (اختياري)',
                      'Your instructions (optional)',
                    ),
                    counterText: '',
                  ),
                ),
                SectionTitle(t('طريقة التسجيل', 'Logging schedule')),
                SegmentedControl(
                  labels: [
                    t('مواعيد ثابتة', 'Scheduled'),
                    t('عند الحاجة', 'As needed'),
                  ],
                  index: asNeeded ? 1 : 0,
                  onChanged: (i) => redraw(() => asNeeded = i == 1),
                ),
                if (!asNeeded) ...[
                  SectionTitle(
                    t('أوقات الجرعات', 'Dose times'),
                    action: TextButton.icon(
                      icon: const Icon(Icons.add, size: 17),
                      label: Text(t('أضف وقت', 'Add time')),
                      onPressed: () async {
                        final result = await showTimePicker(
                          context: c,
                          initialTime: const TimeOfDay(hour: 8, minute: 0),
                        );
                        if (result != null && c.mounted) {
                          redraw(
                            () => times.add(result.hour * 60 + result.minute),
                          );
                        }
                      },
                    ),
                  ),
                  if (times.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${t('عدد المواعيد في يوم الجدول', 'Doses per scheduled day')} · ${times.length}',
                        style: Theme.of(c).textTheme.bodyMedium,
                      ),
                    ),
                  for (final minute in (times.toList()..sort()))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ControlCard(
                        title: clockText(minute),
                        subtitle:
                            doseMealLabel(meals['$minute'], ar) ??
                            t(
                              'اربط الموعد بوجبة (اختياري)',
                              'Link time to a meal (optional)',
                            ),
                        icon: Icons.schedule_rounded,
                        trailing: IconButton(
                          tooltip: t('احذف الموعد', 'Remove time'),
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => redraw(() {
                            times.remove(minute);
                            meals.remove('$minute');
                          }),
                        ),
                        onTap: () async {
                          final rule = await _chooseDoseMeal(
                            minute,
                            meals['$minute'],
                          );
                          if (rule == null || !c.mounted) return;
                          redraw(() {
                            if (rule.isEmpty) {
                              meals.remove('$minute');
                            } else {
                              meals['$minute'] = rule;
                            }
                          });
                        },
                      ),
                    ),
                  SectionTitle(t('الأيام', 'Days')),
                  _weekdayChips(days, redraw),
                  ListTile(
                    leading: const Icon(Icons.date_range),
                    title: Text(t('بداية الجدول', 'Schedule starts')),
                    trailing: Text(dayKey(start)),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: c,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2100),
                        initialDate: start,
                      );
                      if (date != null && c.mounted) {
                        redraw(() {
                          start = date;
                          if (end != null && end!.isBefore(start)) end = null;
                        });
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.event),
                    title: Text(t('نهاية الجدول', 'Schedule ends')),
                    trailing: end == null
                        ? Text(t('بدون نهاية', 'No end'))
                        : TextButton(
                            onPressed: () => redraw(() => end = null),
                            child: Text('${dayKey(end!)} ×'),
                          ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: c,
                        firstDate: DateTime(start.year, start.month, start.day),
                        lastDate: DateTime(2100),
                        initialDate: end ?? start,
                      );
                      if (date != null && c.mounted) redraw(() => end = date);
                    },
                  ),
                  SwitchListTile(
                    title: Text(
                      t('فعّل تذكير الدواء', 'Enable medication reminder'),
                    ),
                    value: notify,
                    onChanged: (on) => redraw(() => notify = on),
                  ),
                  if (notify) ...[
                    ControlCard(
                      title: t(
                        'تكرار تنبيه الدواء',
                        'Repeat medication reminder',
                      ),
                      subtitle: repeat == null
                          ? t(
                              'يتبع إعداد الأدوية',
                              'Follows Medication settings',
                            )
                          : _repeatLabel(repeat!),
                      icon: Icons.repeat_rounded,
                      onTap: () async {
                        final next = await _repeatPicker(
                          repeat ??
                              readRepeat(
                                (data['repeatPreferences']
                                    as Map?)?['medicine'],
                              ),
                        );
                        if (next != null && c.mounted)
                          redraw(() => repeat = next);
                      },
                    ),
                    if (repeat != null)
                      TextButton(
                        onPressed: () => redraw(() => repeat = null),
                        child: Text(
                          t('اتبع إعداد النوع', 'Use category setting'),
                        ),
                      ),
                  ],
                ],
                if (rows(
                  data['conditions'],
                ).any((e) => e['archived'] != true)) ...[
                  SectionTitle(t('ربط بحالات', 'Link conditions')),
                  Wrap(
                    spacing: 5,
                    children: [
                      for (final e in rows(
                        data['conditions'],
                      ).where((e) => e['archived'] != true))
                        FilterChip(
                          label: Text(conditionName(e, ar)),
                          selected: links.contains(e['id']),
                          onSelected: (on) => redraw(
                            () =>
                                on ? links.add(e['id']) : links.remove(e['id']),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 15),
                JournalButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (!form.currentState!.validate()) return;
                          if (!asNeeded && (times.isEmpty || days.isEmpty)) {
                            _toast(
                              t(
                                'اختار وقتًا ويومًا واحدًا على الأقل.',
                                'Choose at least one time and day.',
                              ),
                            );
                            return;
                          }
                          redraw(() => busy = true);
                          final scheduleTimes = asNeeded
                              ? <int>[]
                              : (times.toList()..sort());
                          final scheduleDays = days.toList()..sort();
                          final changed =
                              existing == null ||
                              !_sameInts(
                                scheduleTimes,
                                ints(existing['times']),
                              ) ||
                              !_sameInts(
                                scheduleDays,
                                ints(existing['days']),
                              ) ||
                              existing['start'] != dayKey(start) ||
                              existing['end'] !=
                                  (end == null ? null : dayKey(end!));
                          final medicationChanged =
                              existing != null &&
                              (existing['amount'] != amount.trim() ||
                                  (existing['strength'] ?? '') !=
                                      strength.trim() ||
                                  (existing['administration'] ?? '') !=
                                      administration.trim());
                          final saved = await save((d) {
                            final changedAt = DateTime.now()
                                .toUtc()
                                .toIso8601String();
                            upsert(d, 'meds', {
                              ...?existing,
                              'id': id,
                              'name': name.trim(),
                              'directions': directions.trim(),
                              'amount': amount.trim(),
                              'strength': strength.trim(),
                              'administration': administration.trim(),
                              if (medicationChanged)
                                'changes': [
                                  {
                                    'at': changedAt,
                                    'previous':
                                        (existing['amount'] as String?) ?? '',
                                    'dose': amount.trim(),
                                    'strength': strength.trim(),
                                    'administration': administration.trim(),
                                  },
                                  ...rows(existing['changes']).take(49),
                                ],
                              'links': links.toList(),
                              'times': scheduleTimes,
                              'mealSlots': readDoseMeals(meals, scheduleTimes),
                              'days': scheduleDays,
                              'start': dayKey(start),
                              'end': end == null ? null : dayKey(end!),
                              'revision':
                                  (existing?['revision'] as int? ?? 0) +
                                  (changed ? 1 : 0),
                              'effective': existing != null && changed
                                  ? DateTime.now().toUtc().toIso8601String()
                                  : existing?['effective'],
                              'notify': !asNeeded && notify,
                              'repeat': repeat == null
                                  ? null
                                  : {
                                      'count': repeat!.count,
                                      'minutes': repeat!.minutes,
                                    },
                              'archived': existing?['archived'] ?? false,
                            });
                          });
                          if (!c.mounted) return;
                          if (saved) {
                            Navigator.pop(c);
                            if (notify && !asNeeded) {
                              await _requestNotifications();
                            }
                          } else {
                            redraw(() => busy = false);
                          }
                        },
                  child: Text(t('احفظ الدواء', 'Save medication')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<Map<String, String>?> _chooseDoseMeal(
    int minute,
    Map<String, String>? current,
  ) {
    var meal = current?['meal'] ?? '';
    var relation = current?['relation'] ?? '';
    return _sheet<Map<String, String>>(
      (_) => StatefulBuilder(
        builder: (c, redraw) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              JournalCover(
                title: t('الجرعة والوجبة', 'Dose and meal'),
                subtitle:
                    '${t('الميعاد اللي حددته', 'Your reminder time')} · ${clockText(minute)}',
                icon: Icons.restaurant_outlined,
                accent: honey,
              ),
              SectionTitle(t('اختار الوجبة', 'Choose the meal')),
              Wrap(
                spacing: 7,
                children: [
                  ChoiceChip(
                    label: Text(t('من غير ربط', 'No meal')),
                    selected: meal.isEmpty,
                    onSelected: (_) => redraw(() => meal = ''),
                  ),
                  for (final option in doseMeals.entries)
                    ChoiceChip(
                      label: Text(t(option.value.$1, option.value.$2)),
                      selected: meal == option.key,
                      onSelected: (_) => redraw(() => meal = option.key),
                    ),
                ],
              ),
              if (meal.isNotEmpty) ...[
                SectionTitle(
                  t('التوقيت بالنسبة للوجبة', 'Timing around the meal'),
                ),
                Wrap(
                  spacing: 7,
                  children: [
                    for (final option in doseMealRelations.entries)
                      ChoiceChip(
                        label: Text(t(option.value.$1, option.value.$2)),
                        selected: relation == option.key,
                        onSelected: (_) => redraw(() => relation = option.key),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              JournalButton(
                onPressed: meal.isNotEmpty && relation.isEmpty
                    ? null
                    : () => Navigator.pop(
                        c,
                        meal.isEmpty
                            ? <String, String>{}
                            : {'meal': meal, 'relation': relation},
                      ),
                child: Text(t('احفظ اختيار الوجبة', 'Save meal selection')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _legacyScheduleNeedsReview(JournalRow med) =>
      (med['legacySchedule'] as Map?)?['review'] == true &&
      ints(med['times']).isEmpty;

  Widget _legacyScheduleCard(JournalRow med, Map schedule) {
    final interval = schedule['mode'] == 'interval';
    final meal = switch (schedule['meal']) {
      'breakfast' => t('الفطار', 'Breakfast'),
      'lunch' => t('الغدا', 'Lunch'),
      'dinner' => t('العشا', 'Dinner'),
      _ => t('وجبة', 'Meal'),
    };
    final relation = switch (schedule['relation']) {
      'before' => t('قبل الوجبة', 'Before meal'),
      'after' => t('بعد الوجبة', 'After meal'),
      _ => t('مع الوجبة', 'With meal'),
    };
    final detail = switch (schedule['mode']) {
      'interval' => [
        t('كل', 'Every'),
        schedule['intervalHours'],
        t('ساعة', 'hours'),
      ].join(' '),
      'meal' => [
        meal,
        relation,
        if (schedule['offsetMinutes'] is int && schedule['offsetMinutes'] != 0)
          [schedule['offsetMinutes'], t('دقيقة', 'min')].join(' '),
        if (schedule['plannedTime'] is String) schedule['plannedTime'],
      ].join(' · '),
      _ => strings(schedule['times']).join(' · '),
    };
    return Card(
      child: ListTile(
        leading: const Icon(Icons.history),
        title: Text(t('تفاصيل الجدول المحفوظ', 'Saved schedule details')),
        subtitle: Text(
          [
            if (detail.isNotEmpty) detail,
            if (interval && schedule['anchor'] is int)
              prettyDate(
                DateTime.fromMillisecondsSinceEpoch(schedule['anchor'] as int),
              ),
            if (_legacyScheduleNeedsReview(med))
              t(
                'راجع الجدول القديم واضبط الأوقات في تعديل الدواء قبل تشغيل التنبيهات.',
                'Review the imported schedule and set times in Edit medication before enabling alerts.',
              ),
          ].join('\n'),
        ),
      ),
    );
  }

  bool _sameInts(List<int> a, List<int> b) =>
      a.length == b.length && a.toSet().containsAll(b);

  Widget _weekdayChips(Set<int> selected, StateSetter change) => Wrap(
    spacing: 6,
    children: [
      for (final day in [6, 7, 1, 2, 3, 4, 5])
        FilterChip(
          label: Text(prettyDate(DateTime(2024, 1, day), 'EEE')),
          selected: selected.contains(day),
          onSelected: (on) =>
              change(() => on ? selected.add(day) : selected.remove(day)),
        ),
    ],
  );

  Future<void> _medDetails(String id) => _page<void>(
    (_) => ListenableBuilder(
      listenable: widget.db,
      builder: (c, _) {
        final med = rows(data['meds']).where((m) => m['id'] == id).firstOrNull;
        if (med == null)
          return Scaffold(
            appBar: AppBar(
              title: Text(t('تفاصيل الدواء', 'Medication details')),
            ),
            body: Center(
              child: Text(t('الدواء مش موجود', 'Medication unavailable')),
            ),
          );
        final history =
            rows(data['doses']).where((e) => e['medicine'] == id).toList()
              ..sort((a, b) => eventTime(b).compareTo(eventTime(a)));
        return Scaffold(
          appBar: AppBar(
            title: Text(t('تفاصيل الدواء', 'Medication details')),
            actions: [
              IconButton(
                onPressed: () => _medicine(existing: med),
                icon: const Icon(Icons.edit_outlined),
                tooltip: t('تعديل', 'Edit'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              JournalCover(
                title: med['name'],
                subtitle: (med['amount'] as String?) ?? '',
                icon: Icons.medication_outlined,
                accent: mint,
              ),
              const SizedBox(height: 10),
              for (final detail in [
                med['directions'],
              ].whereType<String>().where((x) => x.isNotEmpty))
                Text(detail),
              if (med['archived'] != true) ...[
                _stockCard(med),
                const SizedBox(height: 8),
                _expiryCard(med),
                const SizedBox(height: 8),
                _packsCard(med),
                const SizedBox(height: 10),
              ],
              if (med['legacySchedule'] case final Map schedule)
                _legacyScheduleCard(med, schedule),
              for (final dose in dosesOn(
                data,
                now,
              ).where((d) => d.medicine['id'] == id))
                _doseTile(dose),
              if (med['archived'] != true)
                FilledButton.tonal(
                  onPressed: () async {
                    if (await _confirm(
                      t('تسجيل جرعة يدوية', 'Log a manual dose'),
                      med['name'],
                      t('سجّل', 'Log'),
                    )) {
                      final key = newId();
                      final token = newId();
                      var added = false;
                      final saved = await save((d) {
                        final current = rows(
                          d['meds'],
                        ).where((m) => m['id'] == id).firstOrNull;
                        if (current == null || current['archived'] == true)
                          return;
                        upsert(
                          d,
                          'doses',
                          _doseRow(d, current, key, 'taken', token: token),
                        );
                        added = true;
                      });
                      if (saved && added && mounted)
                        _doseSaved(key, token, taken: true);
                    }
                  },
                  child: Text(
                    t('سجّل جرعة خارج الجدول', 'Log an unscheduled dose'),
                  ),
                ),
              OutlinedButton(
                onPressed: () async {
                  final archive = med['archived'] != true;
                  if (!archive ||
                      await _confirm(
                        t('أرشفة الدواء؟', 'Archive medication?'),
                        t(
                          'هتتوقف المواعيد المستقبلية، وسجل الجرعات يفضل متاح.',
                          'Future reminders will stop. Your dose history stays available.',
                        ),
                        t('أرشف', 'Archive'),
                      )) {
                    await save(
                      (d) => upsert(d, 'meds', {...med, 'archived': archive}),
                    );
                  }
                },
                child: Text(
                  med['archived'] == true
                      ? t('أعد التفعيل', 'Reactivate')
                      : t('أرشف الدواء', 'Archive medication'),
                ),
              ),
              SectionTitle(t('سجل الإجراءات', 'Dose history')),
              for (final row in history)
                _logTile({...row, 'tracker': medicineCard}),
            ],
          ),
        );
      },
    ),
  );

  JournalRow _doseRow(
    JournalRow state,
    JournalRow med,
    String id,
    String status, {
    required String token,
    Dose? dose,
  }) {
    final stamp = DateTime.now();
    return doseWithInventory(
      {
        'id': id,
        'medicine': med['id'],
        'name': med['name'],
        'amount': med['amount'],
        'strength': med['strength'],
        'administration': med['administration'],
        'status': status,
        'at': stamp.toUtc().toIso8601String(),
        'editToken': token,
        'scheduled': dose?.time.toUtc().toIso8601String(),
        if (dose?.mealSlot case final meal?) 'mealSlot': meal,
        'revision': med['revision'],
        'directions': med['directions'],
        'conditions': [
          for (final c in rows(
            state['conditions'],
          ).where((c) => strings(med['links']).contains(c['id'])))
            {'id': c['id'], 'name': conditionName(c, ar)},
        ],
      },
      med,
      stamp,
    );
  }

  Future<void> _doseHistory(JournalRow row) async {
    var at = eventTime(row);
    final planned = DateTime.tryParse(row['scheduled'] ?? '')?.toLocal();
    var taken = row['status'] == 'taken';
    final result = await _sheet<String>(
      (_) => StatefulBuilder(
        builder: (c, redraw) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              JournalCover(
                kicker: t('تصحيح تسجيل الجرعة', 'Correct a dose record'),
                title: _doseName(row),
                subtitle: [
                  if (planned != null)
                    "${t('الموعد المخطط', 'Scheduled')} · ${prettyDate(planned)} · ${clockText(planned.hour * 60 + planned.minute)}",
                  ?doseMealLabel(row['mealSlot'], ar),
                  if (row['amount'] case final String amount
                      when amount.isNotEmpty)
                    amount,
                  if (row['note'] case final String note when note.isNotEmpty)
                    note,
                ].join('\n'),
                icon: Icons.medication_outlined,
                accent: mint,
              ),
              const SizedBox(height: 12),
              SegmentedControl(
                labels: [t('أُخذت', 'Taken'), t('متخطّية', 'Skipped')],
                index: taken ? 0 : 1,
                onChanged: (index) => redraw(() => taken = index == 0),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  "${t('تاريخ التسجيل', 'Entry date')} · ${prettyDate(at)}",
                ),
                onPressed: () async {
                  final today = DateTime.now();
                  final date = await showDatePicker(
                    context: c,
                    initialDate: at.isAfter(today) ? today : at,
                    firstDate: at.isBefore(DateTime(1900))
                        ? at
                        : DateTime(1900),
                    lastDate: today,
                  );
                  if (date != null && c.mounted) {
                    redraw(
                      () => at = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        at.hour,
                        at.minute,
                      ),
                    );
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule_rounded),
                label: Text(
                  "${t('وقت التسجيل', 'Entry time')} · ${clockText(at.hour * 60 + at.minute)}",
                ),
                onPressed: () async {
                  final time = await showTimePicker(
                    context: c,
                    initialTime: TimeOfDay.fromDateTime(at),
                  );
                  if (time != null && c.mounted) {
                    redraw(
                      () => at = DateTime(
                        at.year,
                        at.month,
                        at.day,
                        time.hour,
                        time.minute,
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
              JournalButton(
                onPressed: () {
                  if (at.isAfter(DateTime.now())) {
                    _toast(
                      t('اختار وقت حصل بالفعل', 'Choose a time in the past'),
                    );
                  } else {
                    Navigator.pop(c, 'save');
                  }
                },
                child: Text(t('احفظ التصحيح', 'Save correction')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, 'remove'),
                child: Text(t('امسح تسجيل الجرعة', 'Remove dose record')),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result == 'remove' &&
        !await _confirm(
          t('تمسح تسجيل الجرعة؟', 'Remove this dose record?'),
          t(
            'الجرعة هترجع لجدولها لو موعدها لسه موجود.',
            'The dose will return to its schedule if the slot still exists.',
          ),
          t('امسح التسجيل', 'Remove record'),
        ))
      return;
    final status = taken ? 'taken' : 'skipped';
    var changed = false;
    if (await save((d) {
          final latest = doseEvent(d, row['id']);
          if (latest == null ||
              latest['editToken'] != row['editToken'] ||
              latest['at'] != row['at'] ||
              latest['status'] != row['status'])
            return;
          if (result == 'remove') {
            removeRow(d, 'doses', latest['id']);
          } else {
            upsert(d, 'doses', {
              ...latest,
              'status': status,
              'at': at.toUtc().toIso8601String(),
              'editToken': newId(),
              if (latest['stockCycle'] != null && latest['status'] != status)
                'stockChangedAt': DateTime.now().toUtc().toIso8601String(),
            });
          }
          changed = true;
        }) &&
        changed &&
        mounted) {
      _toast(
        result == 'remove'
            ? t('اتمسح تسجيل الجرعة', 'Dose record removed')
            : t('اتحفظ التصحيح', 'Dose correction saved'),
        sealed: true,
      );
    }
  }

  String _doseName(JournalRow row) {
    final name = (row['name'] as String?)?.trim() ?? '';
    return name.isEmpty ? t('جرعة مسجّلة', 'Logged dose') : name;
  }

  void _doseSaved(String id, String token, {required bool taken}) {
    if (taken && mounted) _redraw(() => _recentDoseId = id);
    unawaited(HapticFeedback.lightImpact());
    _toast(
      t('اتحفظ إجراء الجرعة', 'Dose action saved'),
      sealed: taken,
      action: SnackBarAction(
        label: t('تراجع', 'Undo'),
        onPressed: () async {
          var removed = false;
          if (await save((d) {
                final record = doseEvent(d, id);
                if (record != null && record['editToken'] == token) {
                  removeRow(d, 'doses', id);
                  removed = true;
                }
              }) &&
              removed &&
              mounted) {
            _toast(t('اتلغى آخر تسجيل للجرعة', 'Dose entry undone'));
          }
        },
      ),
    );
  }

  Future<void> _actDose(Dose dose) async {
    final recorded = doseEvent(data, dose.id);
    if (recorded != null) return _doseHistory(recorded);
    final glucose = trackerFor(data, 'glucose')!;
    final glucoseSummary =
        cardPlan(data).contains(glucose.id) &&
            trackerView(data, glucose).doseSummary
        ? summaryFor(data, glucose.id, ar, DateTime.now())
        : null;
    final choice = await _sheet<String>(
      (c) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(17, 0, 17, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            JournalCover(
              kicker: t('تسجيل الجرعة', 'Log a dose'),
              title: dose.medicine['name'],
              subtitle: [
                t('موعد الجرعة', 'Scheduled dose'),
                clockText(dose.minute),
                ?_profileName,
                ?doseMealLabel(dose.mealSlot, ar),
              ].join(' · '),
              icon: Icons.medication_outlined,
              accent: mint,
            ),
            if (glucoseSummary != null && glucoseSummary.value != '—')
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Card(
                  child: ListTile(
                    leading: const TileIcon('glucose', size: 35),
                    title: Text(glucose.name(ar)),
                    subtitle: Text(glucoseSummary.context),
                    trailing: Text(
                      [glucoseSummary.value, glucoseSummary.unit].join(' '),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 11),
            JournalButton.icon(
              onPressed: () => Navigator.pop(c, 'taken'),
              icon: const Icon(Icons.check),
              label: Text(t('سجّل كأُخذت', 'Mark taken')),
            ),
            if (dose.medicine['notify'] == true)
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(c, 'snooze'),
                icon: const Icon(Icons.snooze),
                label: Text(t('ذكّرني بعد ١٠ دقائق', 'Snooze 10 minutes')),
              ),
            TextButton(
              onPressed: () => Navigator.pop(c, 'skipped'),
              child: Text(t('تخطّي الجرعة', 'Skip this dose')),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final token = newId();
    var changed = false;
    if (await save((d) {
          final latest = dosesOn(
            d,
            dose.time,
          ).where((e) => e.id == dose.id).firstOrNull;
          if (doseEvent(d, dose.id) != null || latest == null) {
            return;
          }
          if (choice == 'snooze') {
            upsert(d, 'snoozes', {
              'id': dose.id,
              'medicine': dose.medicine['id'],
              'revision': dose.medicine['revision'],
              'when': DateTime.now()
                  .add(const Duration(minutes: 10))
                  .toUtc()
                  .toIso8601String(),
              'route': 'dose/${dose.id}',
            });
          } else {
            upsert(
              d,
              'doses',
              _doseRow(
                d,
                latest.medicine,
                dose.id,
                choice,
                dose: latest,
                token: token,
              ),
            );
            removeRow(d, 'snoozes', dose.id);
          }
          changed = true;
        }) &&
        changed &&
        mounted) {
      if (choice == 'snooze') {
        _toast(t('اتضبطت الغفوة', 'Reminder snoozed'));
      } else {
        _doseSaved(dose.id, token, taken: choice == 'taken');
      }
    }
  }

  Future<void> _reminder({
    String? tracker,
    JournalRow? existing,
    int? suggestedMinute,
  }) async {
    var linked = existing?['tracker'] as String? ?? tracker;
    var name =
        existing?['name'] as String? ??
        (tracker == null ? '' : cardName(data, tracker, ar));
    var minute = existing?['minute'] as int? ?? suggestedMinute ?? 1200;
    final times = existing == null
        ? <int>{minute}
        : {...reminderMinutes(existing)};
    ReminderRepeat? repeat = existing?['repeat'] == null
        ? null
        : readRepeat(existing?['repeat']);
    var low = existing?['low'] as int? ?? 1080,
        high = existing?['high'] as int? ?? 1380;
    var learn = existing?['learn'] as String? ?? 'off';
    var flexible = existing?['flexible'] == true,
        enabled = existing?['enabled'] != false,
        once = existing?['end'] != null;
    final days = ints(existing?['days'] ?? allDays).toSet();
    var date = DateTime.tryParse(existing?['start'] ?? '') ?? DateTime.now();
    final id = existing?['id'] as String? ?? newId();
    Future<int?> pick(BuildContext c, int current) async {
      final time = await showTimePicker(
        context: c,
        initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      );
      return time == null ? null : time.hour * 60 + time.minute;
    }

    var busy = false;
    await _page<void>(
      (_) => StatefulBuilder(
        builder: (c, redraw) => Scaffold(
          appBar: AppBar(
            title: Text(
              existing == null
                  ? t('تذكير جديد', 'New reminder')
                  : t('تعديل التذكير', 'Edit reminder'),
            ),
            actions: [
              if (existing != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: t('حذف', 'Delete'),
                  onPressed: () async {
                    if (await _confirm(
                          t('حذف التذكير؟', 'Delete the reminder?'),
                          t('هيتوقف من دلوقتي.', 'It will stop immediately.'),
                          t('احذف', 'Delete'),
                        ) &&
                        await save((d) => removeRow(d, 'reminders', id)) &&
                        c.mounted) {
                      Navigator.pop(c);
                    }
                  },
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
            children: [
              JournalCover(
                title: t('افتكر في وقتك', 'A reminder on your time'),
                subtitle: t(
                  'اختار الميعاد والمتابعة المرتبطة به.',
                  'Choose a time and the tracker it opens.',
                ),
                icon: Icons.notifications_none_rounded,
                accent: honey,
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: name,
                maxLength: 80,
                onChanged: (x) => name = x,
                decoration: InputDecoration(
                  labelText: t('اسم التذكير', 'Reminder name'),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              _choiceSetting(
                c,
                t('المتابعة', 'Tracker'),
                linked ?? '',
                [
                  ('', t('تذكير عام', 'General reminder')),
                  for (final t in allTrackers(data)) (t.id, t.name(ar)),
                ],
                (v) => redraw(() {
                  linked = v == '' ? null : v;
                  if (linked == null) flexible = false;
                }),
                icon: Icons.link_rounded,
              ),
              const SizedBox(height: 8),
              ControlCard(
                title: t('ميعاد التذكير الأول', 'First reminder time'),
                subtitle: clockText(minute),
                icon: Icons.schedule_rounded,
                tonalColor: honey,
                onTap: () async {
                  final n = await pick(c, minute);
                  if (n != null && c.mounted)
                    redraw(() {
                      times.remove(minute);
                      minute = n;
                      times.add(n);
                    });
                },
              ),
              const SizedBox(height: 8),
              for (final extra
                  in times.where((value) => value != minute).toList()..sort())
                InputChip(
                  label: Text(clockText(extra)),
                  onDeleted: () => redraw(() => times.remove(extra)),
                ),
              if (times.length < 12)
                TextButton.icon(
                  icon: const Icon(Icons.add_alarm_outlined),
                  label: Text(t('أضف موعد تاني', 'Add another time')),
                  onPressed: () async {
                    final value = await pick(c, (minute + 240) % 1440);
                    if (value != null && c.mounted) {
                      redraw(() {
                        times.add(value);
                        if (times.length > 1) flexible = false;
                      });
                    }
                  },
                ),
              SwitchListTile(
                title: Text(t('مرة واحدة', 'One time')),
                value: once,
                onChanged: (on) => redraw(() {
                  once = on;
                  if (on) flexible = false;
                }),
              ),
              if (once)
                ListTile(
                  title: Text(t('التاريخ', 'Date')),
                  trailing: Text(dayKey(date)),
                  onTap: () async {
                    final today = DateTime.now();
                    final value = await showDatePicker(
                      context: c,
                      firstDate: today,
                      lastDate: DateTime(2100),
                      initialDate: date.isBefore(today) ? today : date,
                    );
                    if (value != null && c.mounted) redraw(() => date = value);
                  },
                )
              else
                _weekdayChips(days, redraw),
              if (linked != null && !once && times.length == 1)
                SwitchListTile(
                  title: Text(t('اسمح بوقت مرن', 'Allow flexible time')),
                  value: flexible,
                  onChanged: (v) => redraw(() => flexible = v),
                ),
              if (flexible) ...[
                ListTile(
                  title: Text(t('بداية النافذة', 'Window starts')),
                  trailing: Text(clockText(low)),
                  onTap: () async {
                    final n = await pick(c, low);
                    if (n != null && c.mounted) redraw(() => low = n);
                  },
                ),
                ListTile(
                  title: Text(t('نهاية النافذة', 'Window ends')),
                  trailing: Text(clockText(high)),
                  onTap: () async {
                    final n = await pick(c, high);
                    if (n != null && c.mounted) redraw(() => high = n);
                  },
                ),
                DropdownButton<String>(
                  isExpanded: true,
                  value: learn,
                  items: [
                    DropdownMenuItem(
                      value: 'off',
                      child: Text(t('التعلّم متوقف', 'Learning off')),
                    ),
                    DropdownMenuItem(
                      value: 'suggest',
                      child: Text(t('اقترح فقط', 'Suggestions only')),
                    ),
                    DropdownMenuItem(
                      value: 'auto',
                      child: Text(
                        t(
                          'اضبط التذكير داخل نافذتي',
                          'Adjust within my window',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => redraw(() => learn = v ?? 'off'),
                ),
              ],
              ControlCard(
                title: t('تكرار نفس التنبيه', 'Repeat the same reminder'),
                subtitle: repeat == null
                    ? t('يتبع إعداد النوع', 'Follows category setting')
                    : _repeatLabel(repeat!),
                icon: Icons.repeat_rounded,
                onTap: () async {
                  final type = linked == 'water' || linked == 'sleep'
                      ? 'habit'
                      : 'tracking';
                  final next = await _repeatPicker(
                    repeat ??
                        readRepeat((data['repeatPreferences'] as Map?)?[type]),
                  );
                  if (next != null && c.mounted) redraw(() => repeat = next);
                },
              ),
              if (repeat != null)
                TextButton(
                  onPressed: () => redraw(() => repeat = null),
                  child: Text(t('اتبع إعداد النوع', 'Use category setting')),
                ),
              SwitchListTile(
                title: Text(t('التذكير فعّال', 'Reminder enabled')),
                value: enabled,
                onChanged: (v) => redraw(() => enabled = v),
              ),
              JournalButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (name.trim().isEmpty ||
                            (!once && days.isEmpty) ||
                            (flexible &&
                                !(low <= high
                                    ? minute >= low && minute <= high
                                    : minute >= low || minute <= high))) {
                          _toast(
                            t(
                              'راجع الاسم والأيام والنافذة.',
                              'Check the name, days and time window.',
                            ),
                          );
                          return;
                        }
                        if (once &&
                            times.any(
                              (slot) => !DateTime(
                                date.year,
                                date.month,
                                date.day,
                                slot ~/ 60,
                                slot % 60,
                              ).isAfter(DateTime.now()),
                            )) {
                          _toast(
                            t(
                              'اختار موعدًا في المستقبل.',
                              'Choose a future time.',
                            ),
                          );
                          return;
                        }
                        redraw(() => busy = true);
                        final added = await save(
                          (d) => upsert(d, 'reminders', {
                            ...?existing,
                            'id': id,
                            'name': name.trim(),
                            'tracker': linked,
                            'minute': minute,
                            'times': times.length > 1
                                ? (times.toList()..sort())
                                : null,
                            'repeat': repeat == null
                                ? null
                                : {
                                    'count': repeat!.count,
                                    'minutes': repeat!.minutes,
                                  },
                            'effective': DateTime.now()
                                .toUtc()
                                .toIso8601String(),
                            'manualMinute': minute,
                            'revision':
                                (existing?['revision'] as int? ?? 0) + 1,
                            'previousMinute': null,
                            'low': low,
                            'high': high,
                            'learn': flexible ? learn : 'off',
                            'flexible': flexible,
                            'enabled': enabled,
                            'start': dayKey(once ? date : DateTime.now()),
                            'end': once ? dayKey(date) : null,
                            'days': once ? [date.weekday] : days.toList(),
                          }),
                        );
                        if (!c.mounted) return;
                        if (added) {
                          Navigator.pop(c);
                          if (enabled) await _requestNotifications();
                        } else {
                          redraw(() => busy = false);
                        }
                      },
                child: Text(t('احفظ التذكير', 'Save reminder')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (int, int)? _suggestion(JournalRow r, {JournalRow? state, DateTime? at}) {
    final stamp = at ?? now;
    final source = state ?? data;
    if (r['learn'] == 'off' ||
        r['flexible'] != true ||
        r['tracker'] == null ||
        r['enabled'] != true) {
      return null;
    }
    final rejected = DateTime.tryParse(r['rejectedAt'] ?? '');
    if (rejected != null &&
        stamp.difference(rejected) < const Duration(days: 14)) {
      return null;
    }
    return proposeTime(
      entriesFor(source, r['tracker']),
      stamp,
      r['minute'],
      r['low'],
      r['high'],
      since: DateTime.tryParse(source['learningReset'] ?? ''),
    );
  }

  Future<void> _applyAutomatic() async {
    final stamp = DateTime.now();
    final rules = rows(data['reminders']);
    if (!rules.any((rule) {
      if (rule['learn'] != 'auto') return false;
      final suggestion = _suggestion(rule, state: data, at: stamp);
      return suggestion != null &&
          automaticReminderMinute(rule, suggestion.$1, stamp) != null;
    }))
      return;
    await save((draft) {
      for (final reminder in rows(
        draft['reminders'],
      ).where((r) => r['learn'] == 'auto')) {
        final suggestion = _suggestion(reminder, state: draft, at: stamp);
        if (suggestion == null) continue;
        final minute = automaticReminderMinute(reminder, suggestion.$1, stamp);
        if (minute == null) continue;
        final adjusted = _adjusted(reminder, minute, at: stamp);
        upsert(draft, 'reminders', adjusted);
        final event = <String, dynamic>{
          'id': newId(),
          'at': stamp.toUtc().toIso8601String(),
          'reminder': reminder['id'],
          'tracker': reminder['tracker'],
          'name': reminder['name'],
          'old': reminder['minute'],
          'next': minute,
          'pattern': suggestion.$1,
          'days': suggestion.$2,
          'revision': adjusted['revision'],
        };
        draft['adaptiveHistory'] = [
          event,
          ...rows(draft['adaptiveHistory']),
        ].take(20).toList();
      }
    });
  }

  JournalRow _adjusted(JournalRow r, int minute, {DateTime? at}) => {
    ...r,
    'minute': minute,
    'previousMinute': r['minute'],
    'revision': (r['revision'] as int) + 1,
    'changedAt': (at ?? DateTime.now()).toIso8601String(),
  };
  Widget _learningCard(JournalRow r, int minute, int count) => Enter(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('اقتراح من استخدامك', 'Suggestion from your use'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            Text(
              t('سجّلت المتابعة قرب ', 'You logged close to ') +
                  clockText(minute) +
                  t(' في ', ' on ') +
                  count.toString() +
                  t(' أيام.', ' days.'),
            ),
            Wrap(
              spacing: 6,
              children: [
                FilledButton.tonal(
                  onPressed: () =>
                      save((d) => upsert(d, 'reminders', _adjusted(r, minute))),
                  child: Text(t('اعتمد الموعد', 'Use this time')),
                ),
                TextButton(
                  onPressed: () => save(
                    (d) => upsert(d, 'reminders', {
                      ...r,
                      'rejectedAt': now.toIso8601String(),
                    }),
                  ),
                  child: Text(t('تجاهل', 'Dismiss')),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _clearLearning() async {
    if (!await _confirm(
      t('مسح سجل التعلّم؟', 'Clear learning history?'),
      t(
        'ترجع التذكيرات لأوقاتها اليدوية ويتوقف التعلّم. قياساتك محفوظة.',
        'Reminders return to your manual times and learning turns off. Your readings are kept.',
      ),
      t('امسح التعلّم', 'Clear learning'),
    )) {
      return;
    }
    await save((d) {
      d['learningReset'] = DateTime.now().toUtc().toIso8601String();
      d['discoverReminders'] = false;
      d.remove('adaptiveHistory');
      d.remove('discoveryDismissed');
      void clearLayout(JournalRow prefs) {
        final saved = prefs.remove('layoutManual');
        if (saved != null) prefs['order'] = saved;
        for (final key in [
          'layoutLearning',
          'layoutUndo',
          'layoutAppliedDay',
          'layoutChanged',
          'layoutDecision',
        ]) {
          prefs.remove(key);
        }
      }

      clearLayout(d);
      final layouts = rows(d['widgets']);
      layouts.forEach(clearLayout);
      d['widgets'] = layouts;
      d['reminders'] = [
        for (final r in rows(d['reminders']))
          {
            ...r,
            'learn': 'off',
            'minute': r['manualMinute'] ?? r['minute'],
            'revision': (r['revision'] as int) + 1,
            'previousMinute': null,
            'rejectedAt': null,
            'changedAt': null,
          },
      ];
    });
  }
}
