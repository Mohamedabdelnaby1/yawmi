part of 'main.dart';

Widget _careTextField(
  String label,
  String initial,
  ValueChanged<String> change, {
  bool numeric = false,
  int lines = 1,
  Key? fieldKey,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: TextFormField(
    key: fieldKey,
    initialValue: initial,
    maxLength: numeric
        ? 18
        : lines > 1
        ? 700
        : 140,
    minLines: lines,
    maxLines: lines + (lines > 1 ? 2 : 0),
    keyboardType: numeric
        ? const TextInputType.numberWithOptions(decimal: true, signed: true)
        : TextInputType.text,
    decoration: InputDecoration(labelText: label, counterText: ''),
    onChanged: change,
  ),
);

class _PressureWait extends StatefulWidget {
  const _PressureWait(this.from);
  final DateTime from;

  @override
  State<_PressureWait> createState() => _PressureWaitState();
}

class _PressureWaitState extends State<_PressureWait> {
  late final Timer timer;
  int get remaining =>
      (60 - DateTime.now().difference(widget.from).inSeconds).clamp(0, 60);

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (tick) {
      setState(() {});
      if (remaining == 0) tick.cancel();
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final seconds = remaining;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            seconds == 0
                ? tr(ar, 'سجّل القراءة التانية', 'Record the second reading')
                : tr(ar, 'فاضل $seconds ثانية', '$seconds seconds remaining'),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: (60 - seconds) / 60),
        ],
      ),
    );
  }
}

extension _Care on _HomeState {
  Future<void> _healthConnect() async {
    var busy = false;
    final selected = {'glucose', 'pressure'};
    await _page<void>(
      (_) => StatefulBuilder(
        builder: (c, redraw) {
          Future<void> access({required bool import}) async {
            redraw(() => busy = true);
            try {
              final status = await platform.invokeMapMethod<String, dynamic>(
                'healthStatus',
              );
              if (!c.mounted) return;
              if (status?['available'] != true) {
                _toast(
                  t(
                    'الاستيراد يتطلب Health Connect على أندرويد ١٤ أو أحدث.',
                    'Import requires Health Connect on Android 14 or later.',
                  ),
                );
                return;
              }
              if (!import) {
                await platform.invokeMethod<void>('healthSettings');
                return;
              }
              final allowed = (status?['granted'] as List? ?? [])
                  .whereType<String>()
                  .toSet();
              if (!allowed.containsAll(selected)) {
                _toast(
                  t(
                    'اسمح للأنواع المختارة من «أذونات أندرويد».',
                    'Allow the selected types in Android permissions.',
                  ),
                );
                return;
              }
              final raw =
                  await platform.invokeListMethod<Object?>(
                    'healthRead',
                    selected.toList(),
                  ) ??
                  [];
              if (!c.mounted) return;
              final candidates = healthImportRows(data, raw, DateTime.now());
              if (candidates.isEmpty) {
                _toast(
                  t(
                    'مفيش قراءات جديدة في آخر ٧ أيام.',
                    'No new readings in the last seven days.',
                  ),
                );
                return;
              }
              final confirmed = await _confirm(
                t(
                  'أضف ${candidates.length} قراءة؟',
                  'Add ${candidates.length} readings?',
                ),
                t(
                  'هتتحفظ مع وقت القياس ووحدته ومصدره.',
                  'Readings will retain their time, unit, and source.',
                ),
                t('أضف للسجل', 'Add to journal'),
              );
              if (!confirmed || !c.mounted) return;
              var count = 0;
              final saved = await save((d) {
                final latest = healthImportRows(d, raw, DateTime.now());
                count = latest.length;
                d['entries'] = [...rows(d['entries']), ...latest];
              });
              if (saved && c.mounted)
                _toast(
                  t('اتضاف $count قراءة.', 'Added $count readings.'),
                  sealed: true,
                );
            } catch (_) {
              if (c.mounted)
                _toast(
                  t(
                    'ماقدرناش نوصل لـ Health Connect. راجع أذونات أندرويد.',
                    'Could not open or read Health Connect.',
                  ),
                );
            } finally {
              if (c.mounted) redraw(() => busy = false);
            }
          }

          return Scaffold(
            appBar: AppBar(title: const Text('Health Connect')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                JournalCover(
                  title: t('القياسات من جهازك', 'Readings from your devices'),
                  subtitle: t(
                    'اختار أنواع القياس، واسمح بيها في أندرويد قبل استيراد آخر ٧ أيام.',
                    'Choose measurement types and allow them in Android before importing the last seven days.',
                  ),
                  icon: Icons.sync_alt_rounded,
                  accent: mint,
                ),
                for (final id in ['glucose', 'pressure'])
                  CheckboxListTile(
                    title: Text(cardName(data, id, ar)),
                    value: selected.contains(id),
                    onChanged: busy
                        ? null
                        : (on) => redraw(() {
                            if (on == true) {
                              selected.add(id);
                            } else {
                              selected.remove(id);
                            }
                          }),
                  ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => access(import: false),
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(t('أذونات أندرويد', 'Android permissions')),
                ),
                JournalButton.icon(
                  onPressed: busy || selected.isEmpty
                      ? null
                      : () => access(import: true),
                  icon: const Icon(Icons.download_rounded),
                  label: Text(
                    t('راجع القياسات الجديدة', 'Review new readings'),
                  ),
                ),
                if (busy) const LinearProgressIndicator(),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<JournalRow?> _pickLabAttachment() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      );
      final file = picked?.files.singleOrNull;
      if (file == null) return null;
      final path = file.path;
      if (path == null || file.size > maxLabAttachmentBytes)
        throw const FormatException();
      final handle = File(path);
      if (await handle.length() > maxLabAttachmentBytes)
        throw const FormatException();
      final bytes = await handle.readAsBytes();
      final format = labAttachmentFormat(bytes);
      if (format == null || bytes.length > maxLabAttachmentBytes)
        throw const FormatException();
      return {'name': file.name, 'format': format, 'data': base64Encode(bytes)};
    } catch (_) {
      if (mounted)
        _toast(
          t(
            'اختار صورة أو PDF بحجم أقل من ٢ ميجابايت.',
            'Choose an image or PDF up to 2 MB.',
          ),
        );
      return null;
    }
  }

  Future<void> _careCenter() => _page<void>(
    (_) => ListenableBuilder(
      listenable: widget.db,
      builder: (c, _) {
        final end = DateTime.now();
        final start = DateTime(end.year, end.month, end.day - 6);
        final previousStart = DateTime(end.year, end.month, end.day - 13);
        final available = rows(data['entries'])
            .where(
              (row) =>
                  row['legacyUndated'] != true &&
                  !eventTime(row).isBefore(previousStart) &&
                  !eventTime(row).isAfter(end) &&
                  (!isPlannedEntry(row) || row['planCompletedAt'] != null),
            )
            .toList();
        final entries = available
            .where((row) => !eventTime(row).isBefore(start))
            .toList();
        final previous = available
            .where((row) => eventTime(row).isBefore(start))
            .toList();
        final coverage = doseCoverage(
          data,
          start,
          end,
          fromHour: 18,
          clock: end,
        );
        final tracked = <String, Set<String>>{};
        for (final row in entries) {
          (tracked.putIfAbsent(
            row['tracker'],
            () => <String>{},
          )).add(dayKey(eventTime(row)));
        }
        final ranked = tracked.entries.toList()
          ..sort((a, b) => b.value.length.compareTo(a.value.length));
        final conditions = rows(
          data['conditions'],
        ).where((row) => row['archived'] != true);
        return Scaffold(
          appBar: AppBar(title: Text(t('متابعتي', 'My care'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 25),
            children: [
              JournalCover(
                title: t('روتينك في آخر ٧ أيام', 'Your last seven days'),
                subtitle: t(
                  'الملخص بيتغيّر مع تسجيلاتك، وبيتحسب على جهازك.',
                  'Insights update on this device as entries are logged.',
                ),
                icon: Icons.insights_rounded,
                accent: mint,
              ),
              const SizedBox(height: 12),
              if (entries.isEmpty && coverage.scheduled == 0)
                EmptyPanel(
                  Icons.insights_outlined,
                  t('أول تسجيل هيبدأ الملخّص', 'Log an entry to get started'),
                  t(
                    'الملاحظات هتظهر مع القياسات والجرعات المسجّلة.',
                    'Readings and logged doses will appear here.',
                  ),
                ),
              if (coverage.scheduled > 0)
                ControlCard(
                  title: t('الجرعات المسائية', 'Evening doses'),
                  subtitle: t(
                    '${coverage.unlogged} من ${coverage.scheduled} موعد مفيش تسجيل ليه · حسب الجدول الحالي',
                    '${coverage.unlogged} of ${coverage.scheduled} scheduled times have no entry · current schedule',
                  ),
                  icon: Icons.medication_outlined,
                  tonalColor: honey,
                  onTap: () {
                    Navigator.pop(c);
                    _redraw(() => tab = 2);
                  },
                ),
              for (final item in ranked.take(4))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ControlCard(
                    title: cardName(data, item.key, ar),
                    subtitle: _careInsight(
                      item.key,
                      entries,
                      previous,
                      item.value.length,
                    ),
                    icon: glyph(item.key),
                    tonalColor: lavender,
                    onTap: () {
                      final tracker = trackerFor(data, item.key);
                      if (tracker != null) _details(tracker);
                    },
                  ),
                ),
              SectionTitle(t('تخصيص الروتين', 'Routine personalization')),
              SwitchListTile(
                title: Text(
                  t('رتّب بطاقاتي تلقائيًا', 'Arrange my cards automatically'),
                ),
                subtitle: Text(
                  t(
                    'ترتيب حسب أيام التسجيل مع احترام البطاقات المثبّتة.',
                    'Uses days with entries and respects pinned cards.',
                  ),
                ),
                value: data['layoutLearning'] == 'auto',
                onChanged: (on) async {
                  if (await save(
                        (d) => d['layoutLearning'] = on ? 'auto' : 'off',
                      ) &&
                      mounted &&
                      on)
                    await _autoArrange(end);
                },
              ),
              ControlCard(
                title: t(
                  'اقتراحات التذكيرات المرنة',
                  'Flexible reminder suggestions',
                ),
                icon: Icons.auto_awesome_outlined,
                onTap: _adaptiveSettings,
              ),
              SectionTitle(t('خطة الطبيب', 'Care plan')),
              for (final condition in [null, ...conditions])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ControlCard(
                    title: condition == null
                        ? t('خطة عامة', 'General care plan')
                        : conditionName(condition, ar),
                    subtitle: _planLabel(condition?['id'] ?? 'general'),
                    icon: Icons.assignment_outlined,
                    tonalColor: mint,
                    onTap: () => _editCarePlan(condition?['id'] ?? 'general'),
                  ),
                ),
              ControlCard(
                title: t('الحساسية وردود الفعل', 'Allergies and reactions'),
                subtitle:
                    (data['allergyNotes'] as String?)?.trim().isNotEmpty == true
                    ? t(
                        'راجع أو عدّل اللي كتبته',
                        'Review your recorded information',
                      )
                    : t(
                        'احفظ الحساسية ودوّن رد الفعل للزيارة.',
                        'Record allergies and reactions for your visit.',
                      ),
                icon: Icons.fact_check_outlined,
                onTap: () async {
                  final result = await _textPrompt(
                    t('الحساسية وردود الفعل', 'Allergies and reactions'),
                    t('اسم المادة ورد الفعل', 'Substance and reaction'),
                    initial: data['allergyNotes'] as String? ?? '',
                  );
                  if (result != null && mounted)
                    await save((d) => d['allergyNotes'] = result.trim());
                },
              ),
              const SizedBox(height: 10),
              JournalButton.icon(
                onPressed: () => _report(
                  presetRange: DateTimeRange(start: start, end: end),
                  onePage: true,
                ),
                icon: const Icon(Icons.description_outlined),
                label: Text(t('جهّز ملخص الزيارة', 'Prepare visit summary')),
              ),
              ControlCard(
                title: t('خط المتابعة', 'Care timeline'),
                subtitle: t(
                  'راجع القياسات والتغييرات بالترتيب.',
                  'Review readings and care changes in order.',
                ),
                icon: Icons.timeline_rounded,
                onTap: _timeline,
              ),
              ControlCard(
                title: t('زياراتي', 'Visits'),
                subtitle: t(
                  'الأسئلة والنتايج والمتابعة لكل زيارة.',
                  'Questions, results, and follow-up for each visit.',
                ),
                icon: Icons.event_note_outlined,
                onTap: _visits,
              ),
            ],
          ),
        );
      },
    ),
  );

  String _careInsight(
    String id,
    List<JournalRow> entries,
    List<JournalRow> previous,
    int days,
  ) {
    final trend = careTrend(data, id, entries);
    if (trend == null)
      return t('سجّلت في $days أيام من ٧', 'Logged on $days of 7 days');
    final unit = trend.unit;
    final second = trend.secondaryMean;
    final mean = second == null
        ? number(trend.mean)
        : '${number(trend.mean)}/${number(second)}';
    final basic = t(
      'متوسط $mean $unit · ${trend.count} قراءة في $days أيام',
      'Mean $mean $unit · ${trend.count} readings across $days days',
    );
    if (id != 'glucose' || trend.days < 3) return basic;
    for (final (context, caption) in [
      ('fasting', t('صايم', 'Fasting')),
      ('after meal', t('بعد الأكل', 'After meals')),
    ]) {
      final group = entries.where((r) => r['context'] == context);
      final earlier = previous.where((r) => r['context'] == context);
      final newTrend = careTrend(data, id, group);
      final oldTrend = careTrend(data, id, earlier);
      if (newTrend == null ||
          oldTrend == null ||
          newTrend.days < 3 ||
          oldTrend.days < 3)
        continue;
      final recentValue = number(newTrend.mean);
      final oldValue = number(oldTrend.mean);
      return t(
        '$caption · متوسط $recentValue $unit (${newTrend.count} قراءة) · الأسبوع السابق $oldValue (${oldTrend.count} قراءة)',
        '$caption · Mean $recentValue $unit (${newTrend.count} readings) · Previous week $oldValue (${oldTrend.count} readings)',
      );
    }
    return basic;
  }

  String _planLabel(String id) {
    final raw = (data['carePlans'] as Map?)?[id];
    if (raw is Map) {
      final at = parseCalendarDate(raw['review']);
      if (at != null)
        return t('مراجعة ${prettyDate(at)}', 'Review ${prettyDate(at)}');
      return t('راجع أو عدّل الخطة', 'Review or edit plan');
    }
    return t(
      'إيه اللي تقيسه وإمتى وتاريخ المراجعة',
      'What to measure, when, and review date',
    );
  }

  Future<void> _editCarePlan(String id) async {
    final raw = (data['carePlans'] as Map?)?[id] as Map?;
    var measure = raw?['measure'] as String? ?? '';
    var timing = raw?['timing'] as String? ?? '';
    var target = raw?['target'] as String? ?? '';
    var review = parseCalendarDate(raw?['review']);
    var busy = false;
    await _sheet<void>(
      (_) => StatefulBuilder(
        builder: (c, refresh) => _JournalPanel(
          heading: AppBar(
            title: Text(t('خطة الطبيب', 'Care plan')),
            leading: const CloseButton(),
          ),
          footer: JournalButton.icon(
            label: Text(t('احفظ الخطة', 'Save plan')),
            icon: const Icon(Icons.check_rounded),
            onPressed: busy
                ? null
                : () async {
                    refresh(() => busy = true);
                    final saved = await save((d) {
                      final plans = Map<String, dynamic>.from(
                        d['carePlans'] as Map? ?? {},
                      );
                      if ([
                            measure,
                            timing,
                            target,
                          ].every((s) => s.trim().isEmpty) &&
                          review == null) {
                        plans.remove(id);
                      } else {
                        plans[id] = {
                          'measure': measure.trim(),
                          'timing': timing.trim(),
                          'target': target.trim(),
                          'updatedAt': DateTime.now().toUtc().toIso8601String(),
                          if (review != null) 'review': dayKey(review!),
                        };
                      }
                      d['carePlans'] = plans;
                    });
                    if (!c.mounted) return;
                    if (saved) {
                      Navigator.pop(c);
                    } else {
                      refresh(() => busy = false);
                    }
                  },
          ),
          body: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              _careTextField(
                t('إيه اللي هتقيسه؟', 'What to measure'),
                measure,
                (v) => measure = v,
              ),
              _careTextField(
                t('مواعيد القياس المتفق عليها', 'Agreed measurement schedule'),
                timing,
                (v) => timing = v,
              ),
              _careTextField(
                t(
                  'الهدف المتفق عليه مع الطبيب',
                  'Target agreed with your clinician',
                ),
                target,
                (v) => target = v,
              ),
              ControlCard(
                title: t('تاريخ المراجعة', 'Review date'),
                icon: Icons.event_outlined,
                subtitle: review == null
                    ? t('اختار التاريخ', 'Choose a date')
                    : prettyDate(review!),
                onTap: busy
                    ? null
                    : () async {
                        final date = await showDatePicker(
                          context: c,
                          initialDate: review ?? DateTime.now(),
                          firstDate: DateTime(1900),
                          lastDate: DateTime(2200),
                        );
                        if (c.mounted && date != null)
                          refresh(() => review = date);
                      },
              ),
              if (review != null)
                TextButton(
                  onPressed: () => refresh(() => review = null),
                  child: Text(t('امسح تاريخ المراجعة', 'Remove review date')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
