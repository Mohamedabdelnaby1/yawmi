part of 'main.dart';

extension _Sharing on _HomeState {
  Future<void> _privacy() => _page<void>(
    (c) => Scaffold(
      appBar: AppBar(title: Text(t('الخصوصية', 'Privacy'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          JournalCover(
            title: t('سجلّك على جهازك', 'Your journal stays on your device'),
            subtitle: t(
              'يومي يعمل من غير حساب أو تحليلات استخدام.',
              'Yawmi works without an account or usage analytics.',
            ),
            icon: Icons.privacy_tip_outlined,
            accent: mint,
          ),
          SectionTitle(t('التنبيهات والويدجت', 'Reminders and widgets')),
          Text(
            t(
              'التنبيهات تُجدول على جهازك. الويدجت قد يعرض معلومات على الشاشة الرئيسية، وتقدر تخفي القيم من إعدادات كل بطاقة.',
              'Reminders are scheduled on your device. Widgets may show information on the home screen. Hide values from each card’s options.',
            ),
          ),
          SectionTitle(t('النسخ والمشاركة', 'Backups and sharing')),
          Text(
            t(
              'إنت بتختار الملف اللي تحفظه أو تشاركه. النسخة الاحتياطية بتتشفّر بكلمة مرور. ملفات PDF وExcel تتفتح عادي.',
              'You choose which files to save or share. Yawmi backups are encrypted with a password. PDF and Excel reports are readable files.',
            ),
          ),
          SectionTitle(t('الحذف', 'Deletion')),
          Text(
            t(
              'احذف السجل والإعدادات من «المزيد»، وتولَّ حذف أي ملفات سبق حفظها أو مشاركتها.',
              'Delete your journal and settings from More. Manage any files you previously saved or shared separately.',
            ),
          ),
          SectionTitle(t('الاستخدام الصحي والتواصل', 'Health use and contact')),
          Text(
            t(
              'يومي دفتر للمتابعة. استشر مختصًا للرعاية الطبية أو لتغيير الجرعات. للتواصل افتح «عن التطبيق».',
              'Yawmi is a journal. Consult a healthcare professional for medical care or dosage changes. See About Yawmi for contact details.',
            ),
          ),
          if (const String.fromEnvironment('YAWMI_PRIVACY_URL') != '')
            TextButton.icon(
              onPressed: () async {
                try {
                  await platform.invokeMethod<void>(
                    'openPrivacy',
                    const String.fromEnvironment('YAWMI_PRIVACY_URL'),
                  );
                } catch (_) {
                  if (c.mounted)
                    _toast(
                      t(
                        'الرابط ما فتحش. جرّب تاني.',
                        'Could not open the link',
                      ),
                    );
                }
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(
                t('سياسة الخصوصية على الويب', 'Privacy policy on the web'),
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _dataCenter() => _page<void>(
    (c) => Scaffold(
      appBar: AppBar(title: Text(t('الاستيراد والتصدير', 'Import & export'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _FieldBanner(
            title: t('سجلك معاك', 'Take your journal with you'),
            detail: t('نقل البيانات والنسخ الاحتياطي', 'Transfer & backup'),
            accent: mint,
          ),
          SectionTitle(t('استيراد', 'Import')),
          ControlCard(
            emphasized: true,
            title: t('استورد قياسات من CSV', 'Import readings from CSV'),
            subtitle: t(
              'ضيف قراءات من ملف CSV متوافق مع يومي.',
              'Use the Yawmi export columns to add readings to your journal.',
            ),
            icon: Icons.move_to_inbox_outlined,
            onTap: () => _transferFromDataCenter(c, _importCsv),
          ),
          if (Platform.isAndroid && data['stage'] == 3) ...[
            const SizedBox(height: 8),
            ControlCard(
              title: t(
                'استورد من Health Connect',
                'Import from Health Connect',
              ),
              subtitle: t(
                'السكر والضغط · آخر ٧ أيام · أندرويد ١٤+',
                'Glucose and pressure · Last 7 days · Android 14+',
              ),
              icon: Icons.sync_alt_rounded,
              tonalColor: mint,
              onTap: _healthConnect,
            ),
          ],
          const SizedBox(height: 8),
          ControlCard(
            title: t('استعادة نسخة يومي', 'Restore a Yawmi backup'),
            subtitle: t(
              'شوف إيه اللي في النسخة قبل ما تستبدل سجلك.',
              'Review the backup before replacing your journal.',
            ),
            icon: Icons.restore_page_outlined,
            tonalColor: ice,
            onTap: () => _transferFromDataCenter(c, _restore),
          ),
          if (data['stage'] == 3) ...[
            SectionTitle(t('تصدير', 'Export')),
            ControlCard(
              title: t('احفظ نسخة مشفّرة', 'Save an encrypted backup'),
              subtitle: t(
                'خد نسخة من سجلك وإعداداتك وتصميمات الويدجت',
                'Journal, preferences and widget designs',
              ),
              icon: Icons.lock_outline_rounded,
              onTap: _backup,
              trailing: IconButton(
                tooltip: t('شارك نسخة مشفّرة', 'Share encrypted backup'),
                icon: const Icon(Icons.ios_share),
                onPressed: () => _backup(share: true),
              ),
            ),
            const SizedBox(height: 8),
            ControlCard(
              title: t('تقرير PDF أو Excel', 'PDF or Excel report'),
              subtitle: t(
                'اختار الفترة والبيانات اللي هتشاركها.',
                'Choose the date range and data to share.',
              ),
              icon: Icons.article_outlined,
              tonalColor: honey,
              onTap: _report,
            ),
          ],
        ],
      ),
    ),
  );

  Future<void> _transferFromDataCenter(
    BuildContext context,
    Future<void> Function() transfer,
  ) async {
    final fromWelcome = data['stage'] == 0;
    await transfer();
    if (fromWelcome && context.mounted && mounted && data['stage'] == 1) {
      Navigator.pop(context);
    }
  }

  Future<void> _importCsv() async {
    try {
      final pick = (await FilePicker.platform.pickFiles())?.files.singleOrNull;
      if (pick?.path == null || !mounted) return;
      final file = File(pick!.path!);
      if (pick.size > csvMaxBytes || await file.length() > csvMaxBytes) {
        _toast(
          t('حدّ حجم CSV هو ١٦ ميجابايت.', 'The CSV size limit is 16 MB.'),
        );
        return;
      }
      final incoming = await readJournalCsv(data, await file.readAsBytes());
      if (!mounted) return;
      final pending = newCsvEntries(data, incoming.entries);
      final duplicates = incoming.entries.length - pending.length;
      final accepted = await _page<bool>(
        (c) => Scaffold(
          appBar: AppBar(title: Text(t('معاينة الاستيراد', 'Import preview'))),
          body: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              JournalCover(
                title: t('راجع القراءات الجديدة', 'Review new readings'),
                subtitle: t(
                  'تُضاف القراءات الجديدة إلى السجل. استخدم النسخة المشفّرة لنقل الأدوية والإعدادات.',
                  'New readings are added to your journal. Use an encrypted backup to transfer medications and settings.',
                ),
                icon: Icons.playlist_add_check_rounded,
                accent: ice,
              ),
              SectionTitle(
                '${t('القراءات الجديدة', 'New readings')} · ${pending.length}',
              ),
              Text('${t('المكرّر', 'Duplicates')} · $duplicates'),
              Text(
                '${t('غير المدعوم أو غير الصالح', 'Unsupported or invalid')} · ${incoming.skipped}',
              ),
              for (final row in pending.take(5))
                ListTile(
                  leading: TileIcon(row['tracker'], size: 34),
                  title: Text(cardName(data, row['tracker'], ar)),
                  subtitle: Text(dayKey(eventTime(row))),
                  trailing: Text(reportValue(row, ar)),
                ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: JournalButton.icon(
                onPressed: pending.isEmpty
                    ? null
                    : () => Navigator.pop(c, true),
                icon: const Icon(Icons.playlist_add_rounded),
                label: Text(t('أضف للسجل', 'Add to journal')),
              ),
            ),
          ),
        ),
      );
      if (accepted != true || !mounted) return;
      final saved = await save((d) {
        final added = newCsvEntries(d, pending);
        d['entries'] = [...rows(d['entries']), ...added];
        if (d['stage'] != 3 && added.isNotEmpty) {
          d['enabled'] = {
            ...strings(d['enabled']),
            ...added.map((row) => row['tracker'] as String),
          }.toList();
          if (d['stage'] == 0) d['stage'] = 1;
        }
      });
      if (saved && mounted)
        _toast(
          t('القراءات اتضافت للسجل', 'Readings added to your journal'),
          sealed: true,
        );
    } catch (_) {
      if (mounted) {
        _toast(
          t(
            'الملف ما اتقراش. راجع ترتيب أعمدة CSV بتنسيق يومي.',
            'Could not read the file. Check the Yawmi CSV columns.',
          ),
        );
      }
    }
  }

  Future<void> _report({
    bool fromHistory = false,
    DateTimeRange? presetRange,
    List<JournalRow>? sourceOverride,
    bool onePage = false,
  }) async {
    final today = DateTime.now();
    var range =
        presetRange ??
        DateTimeRange(
          start: DateTime(today.year, today.month, today.day - 6),
          end: today,
        );
    final source =
        sourceOverride ??
        (fromHistory
            ? _historySelection().visible
            : <JournalRow>[
                ...rows(data['entries']),
                for (final d in rows(data['doses']))
                  {...d, 'tracker': medicineCard},
              ]);
    final newest = source
        .map((e) => DateUtils.dateOnly(eventTime(e)))
        .fold(
          DateUtils.dateOnly(today),
          (latest, day) => day.isAfter(latest) ? day : latest,
        );
    if (fromHistory) {
      if (dates != null) {
        range = dates!;
      } else if (period > 0) {
        range = DateTimeRange(
          start: DateTime(today.year, today.month, today.day - period + 1),
          end: today,
        );
      } else if (source.isNotEmpty) {
        final sorted = (source.map(eventTime).toList()..sort());
        final first = DateUtils.dateOnly(sorted.first);
        range = DateTimeRange(start: first, end: newest);
      }
    }
    final types = source.map((e) => e['tracker'] as String).toSet();
    final selected = fromHistory && filter != null
        ? types.where((id) => id == filter).toSet()
        : types.toSet();
    if (!fromHistory &&
        sourceOverride == null &&
        rows(
          data['meds'],
        ).any((m) => m['archived'] != true && ints(m['times']).isNotEmpty)) {
      types.add(medicineCard);
      selected.add(medicineCard);
    }
    var notes = false, busy = false, summary = onePage, appendix = false;
    await _page<void>(
      (_) => StatefulBuilder(
        builder: (c, redraw) {
          final first = DateTime(
            range.start.year,
            range.start.month,
            range.start.day,
          );
          final end = DateTime(
            range.end.year,
            range.end.month,
            range.end.day + 1,
          );
          final filtered =
              source
                  .where(
                    (e) =>
                        selected.contains(e['tracker']) &&
                        (!isPlannedEntry(e) || e['planCompletedAt'] != null) &&
                        !eventTime(e).isBefore(first) &&
                        eventTime(e).isBefore(end),
                  )
                  .toList()
                ..sort((a, b) => eventTime(b).compareTo(eventTime(a)));
          final label = '${dayKey(range.start)} – ${dayKey(range.end)}';
          final includeCoverage =
              !fromHistory &&
              sourceOverride == null &&
              selected.contains(medicineCard);
          final canSharePdf =
              filtered.isNotEmpty ||
              summary &&
                  includeCoverage &&
                  calendarSpan(first, range.end) <= 366 &&
                  doseCoverage(data, first, range.end).scheduled > 0;
          Future<void> share(bool pdf) async {
            redraw(() => busy = true);
            try {
              if (pdf) {
                final bytes = summary
                    ? await makeVisitSummaryPdf(
                        data,
                        filtered,
                        ar,
                        label,
                        start: first,
                        through: range.end,
                        notes: notes,
                        includeDoseCoverage: includeCoverage,
                        appendDetails: appendix,
                      )
                    : await makePdf(data, filtered, ar, label, notes: notes);
                await shareBytes(
                  bytes,
                  summary ? 'Yawmi-visit-summary.pdf' : 'Yawmi-report.pdf',
                  'application/pdf',
                );
              } else {
                await shareBytes(
                  await makeExcel(data, filtered, ar, label, notes: notes),
                  'Yawmi-report.xlsx',
                  excelMime,
                );
              }
            } catch (_) {
              _toast(
                t(
                  'ماقدرناش نجهّز التقرير أو نشاركه. جرّب تاني.',
                  'Could not create or share the report.',
                ),
              );
            } finally {
              if (c.mounted) redraw(() => busy = false);
            }
          }

          return Scaffold(
            appBar: AppBar(title: Text(t('معاينة التقرير', 'Report preview'))),
            body: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              itemCount: summary ? 1 : filtered.length + 1,
              itemBuilder: (_, i) {
                if (i > 0) {
                  final row = filtered[i - 1];
                  final at = eventTime(row);
                  return Card(
                    child: ListTile(
                      leading: TileIcon(row['tracker'], size: 35),
                      title: Text(
                        row['tracker'] == medicineCard
                            ? row['name']
                            : cardName(data, row['tracker'], ar),
                      ),
                      subtitle: Text(
                        [
                          '${dayKey(at)} · ${clockText(at.hour * 60 + at.minute)}',
                          if (entryContext(row['context'], ar).isNotEmpty)
                            entryContext(row['context'], ar),
                          if (notes &&
                              row['note'] is String &&
                              (row['note'] as String).isNotEmpty)
                            row['note'] as String,
                        ].join('\n'),
                      ),
                      trailing: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 107),
                        child: Text(
                          reportValue(row, ar),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    JournalCover(
                      title: t('تقرير من سجلك', 'A report from your journal'),
                      subtitle: t(
                        fromHistory
                            ? 'التقرير يبدأ من نتيجة السجل الحالية.'
                            : 'اختار المدة والبيانات اللي تحب تشاركها.',
                        fromHistory
                            ? 'This report starts from the current history results.'
                            : 'Choose which dates and data to include.',
                      ),
                      icon: Icons.article_outlined,
                      accent: honey,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.date_range),
                      label: Text(label),
                      onPressed: busy
                          ? null
                          : () async {
                              final dates = await showDateRangePicker(
                                context: c,
                                firstDate: range.start.isBefore(DateTime(1900))
                                    ? range.start
                                    : DateTime(1900),
                                lastDate: range.end.isAfter(newest)
                                    ? range.end
                                    : newest,
                                initialDateRange: range,
                              );
                              if (dates != null && c.mounted) {
                                redraw(() => range = dates);
                              }
                            },
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final id in types)
                          FilterChip(
                            label: Text(cardName(data, id, ar)),
                            selected: selected.contains(id),
                            onSelected: busy
                                ? null
                                : (on) => redraw(
                                    () => on
                                        ? selected.add(id)
                                        : selected.remove(id),
                                  ),
                          ),
                      ],
                    ),
                    SwitchListTile(
                      title: Text(
                        t(
                          'ملخّص زيارة في صفحة واحدة',
                          'One-page visit summary',
                        ),
                      ),
                      subtitle: Text(
                        t(
                          'اتجاه القياسات وتغطية التسجيل وأهم نقاط الزيارة',
                          'Reading trends, recording coverage, and visit highlights',
                        ),
                      ),
                      value: summary,
                      onChanged: busy
                          ? null
                          : (on) => redraw(() => summary = on),
                    ),
                    if (summary)
                      for (final group in visitSummary(data, filtered, ar))
                        ListTile(
                          leading: TileIcon(group.id, size: 34),
                          title: Text(group.title),
                          subtitle: Text(group.detail),
                          trailing: Text(group.count.toString()),
                        ),
                    if (summary)
                      SwitchListTile(
                        title: Text(
                          t(
                            'أضف تفاصيل السجل بعد الملخص',
                            'Append journal details',
                          ),
                        ),
                        value: appendix,
                        onChanged: busy
                            ? null
                            : (on) => redraw(() => appendix = on),
                      ),
                    SwitchListTile(
                      title: Text(
                        summary
                            ? t(
                                'ضمّ الملاحظات والحساسية المسجّلة',
                                'Include notes and recorded allergies',
                              )
                            : t('ضمّ الملاحظات', 'Include notes'),
                      ),
                      value: notes,
                      onChanged: busy ? null : (on) => redraw(() => notes = on),
                    ),
                    if (busy) const LinearProgressIndicator(),
                    SectionTitle(
                      '${t('التسجيلات اللي اخترتها', 'Selected entries')} · ${filtered.length}',
                    ),
                    if (filtered.isEmpty)
                      EmptyPanel(
                        Icons.article_outlined,
                        t('مفيش تسجيلات في الاختيار ده', 'No entries selected'),
                        t(
                          'وسّع الفترة أو اختار نوعًا آخر.',
                          'Choose a wider date range or another type.',
                        ),
                      ),
                  ],
                );
              },
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: Row(
                  children: [
                    Expanded(
                      child: JournalButton(
                        onPressed: busy || !canSharePdf
                            ? null
                            : () => share(true),
                        child: Text(
                          summary
                              ? t('شارك الملخّص', 'Share summary')
                              : t('شارك PDF', 'Share PDF'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy || filtered.isEmpty
                            ? null
                            : () => share(false),
                        child: Text(t('شارك Excel', 'Share Excel')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _backup({bool share = false}) async {
    final password = await _textPrompt(
      t('كلمة مرور النسخة الاحتياطية', 'Backup password'),
      t(
        '٨ أحرف على الأقل. هتحتاجها للاستعادة.',
        'At least 8 characters. Keep it to restore the backup.',
      ),
      secret: true,
    );
    if (password == null || !mounted) return false;
    if (password.runes.length < 8) {
      _toast(t('استخدم ٨ أحرف على الأقل', 'Use at least 8 characters'));
      return false;
    }
    final confirmation = await _textPrompt(
      t('أكد كلمة المرور', 'Confirm the password'),
      t('اكتبها مرة تانية', 'Enter it again'),
      secret: true,
    );
    if (confirmation != password || !mounted) {
      if (confirmation != null) {
        _toast(t('كلمتا المرور مختلفتان', 'Passwords do not match'));
      }
      return false;
    }
    _toast(t('جاري تشفير النسخة…', 'Encrypting backup…'));
    try {
      final bytes = await makeBackup(data, password);
      if (!mounted) return false;
      final name = 'Yawmi-${dayKey(DateTime.now())}.yawmi';
      if (share) {
        await shareBytes(bytes, name, 'application/octet-stream');
      } else {
        final destination = await FilePicker.platform.saveFile(
          dialogTitle: t('احفظ النسخة المشفّرة', 'Save encrypted backup'),
          fileName: name,
          bytes: bytes,
        );
        if (destination == null) return false;
        _toast(t('اتحفظت النسخة المشفّرة', 'Encrypted backup saved'));
      }
      return true;
    } catch (_) {
      _toast(
        t('ماقدرناش نجهّز النسخة الاحتياطية.', 'Could not create backup.'),
      );
      return false;
    }
  }

  Future<void> _restore() async {
    try {
      final file = (await FilePicker.platform.pickFiles())?.files.singleOrNull;
      if (file == null || file.path == null || !mounted) return;
      final input = File(file.path!);
      if (file.size > maxBackupBytes || await input.length() > maxBackupBytes) {
        _toast(
          t(
            'حجم الملف أكبر من الحد المدعوم.',
            'This file is larger than the supported limit.',
          ),
        );
        return;
      }
      final pass = await _textPrompt(
        t('فك تشفير نسخة يومي', 'Unlock Yawmi backup'),
        t('كلمة المرور', 'Password'),
        secret: true,
      );
      if (pass == null || !mounted) return;
      _toast(t('جاري فحص النسخة…', 'Checking backup…'));
      final next = await openBackup(await input.readAsBytes(), pass);
      if (!mounted) return;
      final hasData = [
        'entries',
        'conditions',
        'meds',
        'doses',
        'reminders',
        'widgets',
        'custom',
      ].any((key) => rows(data[key]).isNotEmpty);
      final entries = rows(next['entries'])
        ..sort((a, b) => eventTime(a).compareTo(eventTime(b)));
      final details = [
        t('التسجيلات ', 'Entries ') + entries.length.toString(),
        t('الحالات ', 'Conditions ') +
            rows(next['conditions']).length.toString(),
        t('الأدوية ', 'Medications ') + rows(next['meds']).length.toString(),
        if (entries.isNotEmpty)
          '${dayKey(eventTime(entries.first))} – ${dayKey(eventTime(entries.last))}',
        t(
          'التذكيرات المستعادة تبدأ متوقفة. تصميمات الويدجت تُستعاد وتقدر تثبّتها من الاستوديو.',
          'Restored reminders start paused. Pin your restored widget designs from Studio.',
        ),
        if (hasData)
          t(
            'الاستعادة تستبدل البيانات الحالية.',
            'Restoring replaces the current journal.',
          ),
      ].join('\n');
      if (hasData) {
        final backup = await _sheet<bool>(
          (c) => Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t('البيانات الحالية', 'Current data'),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                JournalButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: Text(t('أنشئ نسخة منها', 'Create a safety backup')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: Text(
                    t('انتقل لمعاينة الاستعادة', 'Continue to restore preview'),
                  ),
                ),
              ],
            ),
          ),
        );
        if (backup == null) return;
        if (backup && !await _backup()) return;
      }
      if (!mounted ||
          !await _confirm(
            t('معاينة الاستعادة', 'Restore preview'),
            details,
            t('استعد النسخة', 'Restore backup'),
          )) {
        return;
      }
      if (await save((d) {
            final started = d['stage'] == 3;
            d.clear();
            d.addAll(next);
            if (!started) d['stage'] = 1;
          }) &&
          mounted) {
        _entryDrafts.clear();
        _search.clear();
        _redraw(() {
          tab = 0;
          _dashboardSection = next['startSection'] == 'doses' ? 1 : 0;
          filter = null;
          conditionFilter = null;
          dates = null;
          period = 0;
        });
        _toast(t('النسخة اتستعادت', 'Backup restored'));
      }
    } catch (_) {
      _toast(
        t(
          'النسخة ما فتحتش. راجع كلمة المرور وإصدار الملف.',
          'Could not open backup. Check the password and file version.',
        ),
      );
    }
  }
}
