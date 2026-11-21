part of 'main.dart';

String _stockQuantity(double value) =>
    NumberFormat('0.####', 'en').format(value);

extension _Stock on _HomeState {
  Future<void> _medicineCabinet() => _page<void>(
    (_) => ListenableBuilder(
      listenable: widget.db,
      builder: (c, _) {
        final meds = rows(data['meds']).where((m) => m['archived'] != true);
        final doses = rows(data['doses']);
        final today = DateTime.now();
        final items = [
          for (final med in meds)
            (
              med: med,
              balance: medicationStockBalance(med, doses),
              expiry: DateAlert.read(med['expiry']),
            ),
        ];
        bool low(StockBalance? balance) =>
            balance != null && balance.remaining <= balance.stock.threshold;
        int priority(StockBalance? balance, DateAlert? expiry) {
          final days = expiry == null
              ? 999
              : calendarDaysUntil(expiry.date, today);
          if (days < 0) return 0;
          if (low(balance)) return 1;
          if (days <= 7) return 2;
          return 3;
        }

        items.sort(
          (a, b) => priority(
            a.balance,
            a.expiry,
          ).compareTo(priority(b.balance, b.expiry)),
        );
        return Scaffold(
          appBar: AppBar(title: Text(t('خزانة الأدوية', 'Medicine cabinet'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              JournalCover(
                title: t('راجع اللي عندك', 'See what’s on hand'),
                subtitle: t(
                  'الكمية بتتحدّث مع الجرعات اللي بتسجّلها. اضبط حد التنبيه وتاريخ الصلاحية لكل دواء.',
                  'Stock updates with logged doses. Set a low-stock threshold and expiry date for each medication.',
                ),
                icon: Icons.inventory_2_outlined,
                accent: mint,
              ),
              const SizedBox(height: 14),
              if (items.isEmpty)
                EmptyPanel(
                  Icons.medication_outlined,
                  t('لسه مفيش أدوية', 'No medications yet'),
                  t(
                    'ضيف دواء عشان تبدأ تتابع المخزون.',
                    'Add a medication to start tracking stock.',
                  ),
                  action: OutlinedButton(
                    onPressed: () => _medicine(),
                    child: Text(t('أضف دواء', 'Add medication')),
                  ),
                ),
              for (final (index, item) in items.indexed)
                Enter(
                  key: ValueKey(item.med['id']),
                  delay: index.clamp(0, 5) * 35,
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SectionTitle(item.med['name']),
                          if (low(item.balance))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: LinearProgressIndicator(
                                borderRadius: BorderRadius.circular(12),
                                value: item.balance!.stock.count == 0
                                    ? 0
                                    : (item.balance!.remaining /
                                              item.balance!.stock.count)
                                          .clamp(0, 1)
                                          .toDouble(),
                                semanticsLabel: t(
                                  'المخزون المتبقي',
                                  'Remaining stock',
                                ),
                              ),
                            ),
                          _stockCard(item.med, balance: item.balance),
                          const SizedBox(height: 8),
                          _expiryCard(item.med),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );

  Widget _expiryCard(JournalRow med) {
    final alert = DateAlert.read(med['expiry']);
    final days = alert == null
        ? 999
        : calendarDaysUntil(alert.date, DateTime.now());
    return ControlCard(
      title: t('صلاحية الدواء', 'Medication expiry'),
      subtitle: alert == null
          ? t(
              'أضف التاريخ المكتوب على العبوة.',
              'Add the date printed on the package.',
            )
          : [
              prettyDate(alert.date, 'd MMM yyyy'),
              _dateStatus(alert.date, expiry: true),
              if (!alert.armed) t('التنبيه مقفول', 'Alerts off'),
            ].join(' · '),
      icon: Icons.event_busy_outlined,
      tonalColor: days < 0 ? rose : honey,
      toned: days <= 7,
      onTap: () => _editMedicationExpiry(med['id']),
    );
  }

  Widget _stockCard(JournalRow med, {StockBalance? balance}) {
    balance ??= medicationStockBalance(med, rows(data['doses']));
    final low = balance != null && balance.remaining <= balance.stock.threshold;
    return ControlCard(
      title: balance == null
          ? t('فعّل متابعة المخزون', 'Track medication stock')
          : t('مخزون الدواء', 'Medication stock'),
      subtitle: balance == null
          ? t(
              'حدّد الكمية المتبقية وتنبيه إعادة الصرف.',
              'Set the remaining quantity and a refill alert.',
            )
          : [
              '${t('المتبقي', 'Remaining')} · ${_stockQuantity(balance.remaining)}',
              if (low) t('وصل لحد إعادة الصرف', 'Refill threshold reached'),
            ].join(' · '),
      icon: Icons.inventory_2_outlined,
      tonalColor: low ? honey : mint,
      toned: low,
      onTap: () => _editStock(med['id']),
    );
  }

  Future<void> _editStock(String id) async {
    final med = rows(data['meds']).where((row) => row['id'] == id).firstOrNull;
    if (med == null || med['archived'] == true) return;
    final balance = medicationStockBalance(med, rows(data['doses']));
    var count = balance == null ? '' : _stockQuantity(balance.remaining);
    var perDose = balance?.stock.perDose.toString() ?? '1';
    var threshold = balance?.stock.threshold.toString() ?? '0';
    var notify = balance?.stock.notify ?? false;
    var repeatDays = readStockInterval(balance?.stock.repeatDays);
    var repeatMinute = readAlertMinute(balance?.stock.repeatMinute);
    var busy = false;
    final form = GlobalKey<FormState>();
    final result = await _sheet<String>(
      (_) => StatefulBuilder(
        builder: (c, redraw) {
          Widget field(
            String label,
            String value,
            ValueChanged<String> changed, {
            bool positive = false,
          }) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextFormField(
              initialValue: value,
              maxLength: 12,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: label, counterText: ''),
              onChanged: changed,
              validator: (input) {
                final n = readNumber(input ?? '');
                return n == null || n < 0 || n > 100000000 || positive && n == 0
                    ? t('اكتب كمية صالحة', 'Enter a valid quantity')
                    : null;
              },
            ),
          );
          Future<void> commit({bool remove = false}) async {
            if (!remove && !form.currentState!.validate()) return;
            redraw(() => busy = true);
            final stamp = DateTime.now();
            final previous = balance?.stock;
            final quantity = readNumber(count);
            final nextThreshold = readNumber(threshold);
            final recount = previous == null || quantity != balance?.remaining;
            final newlyLow =
                balance != null &&
                balance.remaining > balance.stock.threshold &&
                balance.remaining <= (nextThreshold ?? 0);
            final next = remove
                ? null
                : MedicationStock(
                    cycle: recount ? newId() : previous.cycle,
                    countedAt: recount ? stamp : previous.countedAt,
                    count: recount ? quantity! : previous.count,
                    perDose: readNumber(perDose)!,
                    threshold: nextThreshold!,
                    notify: notify,
                    repeatDays: repeatDays,
                    repeatMinute: repeatMinute,
                    alertsEnabledAt:
                        notify && (recount || newlyLow || !previous.notify)
                        ? stamp
                        : previous?.alertsEnabledAt,
                  );
            final saved = await save((d) {
              final current = rows(
                d['meds'],
              ).where((m) => m['id'] == id).firstOrNull;
              if (current == null || current['archived'] == true) return;
              final updated = {...current};
              if (next == null) {
                updated.remove('inventory');
              } else {
                updated['inventory'] = next.toRow();
              }
              upsert(d, 'meds', updated);
            });
            if (!c.mounted) return;
            if (saved) {
              Navigator.pop(c, next?.notify == true ? 'notify' : 'saved');
            } else {
              redraw(() => busy = false);
            }
          }

          return Form(
            key: form,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                20 + MediaQuery.viewInsetsOf(c).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  JournalCover(
                    kicker: t('مخزون الدواء', 'Medication stock'),
                    title: med['name'],
                    subtitle: t(
                      'استخدم نفس الوحدة في كل الحقول، زي عدد الأقراص أو الملليلتر.',
                      'Use the same unit in every field, such as tablets or millilitres.',
                    ),
                    icon: Icons.inventory_2_outlined,
                    accent: mint,
                  ),
                  const SizedBox(height: 12),
                  field(
                    t('الكمية الموجودة دلوقتي', 'Quantity on hand'),
                    count,
                    (value) => count = value,
                  ),
                  field(
                    t(
                      'وحدات المخزون لكل جرعة مسجّلة',
                      'Stock units per logged dose',
                    ),
                    perDose,
                    (value) => perDose = value,
                    positive: true,
                  ),
                  field(
                    t('حد إعادة الصرف', 'Refill threshold'),
                    threshold,
                    (value) => threshold = value,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      t(
                        'نبّهني عند حد إعادة الصرف',
                        'Notify at the refill threshold',
                      ),
                    ),
                    value: notify,
                    onChanged: busy ? null : (on) => redraw(() => notify = on),
                  ),
                  AnimatedSize(
                    duration: motion(c, 280),
                    alignment: Alignment.topCenter,
                    child: !notify
                        ? const SizedBox(width: double.infinity)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SectionTitle(
                                t(
                                  'التكرار طالما الكمية قليلة',
                                  'Repeat while stock is low',
                                ),
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 5,
                                children: [
                                  for (final days in stockRepeatDays)
                                    ChoiceChip(
                                      selected: repeatDays == days,
                                      label: Text(switch (days) {
                                        0 => t('مرة واحدة', 'Once'),
                                        1 => t('كل يوم', 'Daily'),
                                        _ => t(
                                          'كل $days يوم',
                                          'Every $days days',
                                        ),
                                      }),
                                      onSelected: busy
                                          ? null
                                          : (_) =>
                                                redraw(() => repeatDays = days),
                                    ),
                                ],
                              ),
                              if (repeatDays > 0) ...[
                                const SizedBox(height: 8),
                                ControlCard(
                                  title: t(
                                    'وقت تكرار تنبيه النقص',
                                    'Low-stock repeat time',
                                  ),
                                  subtitle: clockText(repeatMinute),
                                  icon: Icons.access_time_rounded,
                                  onTap: busy
                                      ? null
                                      : () async {
                                          final time = await showTimePicker(
                                            context: c,
                                            initialTime: TimeOfDay(
                                              hour: repeatMinute ~/ 60,
                                              minute: repeatMinute % 60,
                                            ),
                                          );
                                          if (time != null && c.mounted)
                                            redraw(
                                              () => repeatMinute =
                                                  time.hour * 60 + time.minute,
                                            );
                                        },
                                ),
                              ],
                              const SizedBox(height: 12),
                            ],
                          ),
                  ),
                  JournalButton.icon(
                    onPressed: busy ? null : () => commit(),
                    icon: const Icon(Icons.check_rounded),
                    label: Text(t('احفظ المخزون', 'Save stock')),
                  ),
                  if (balance != null)
                    TextButton(
                      onPressed: busy ? null : () => commit(remove: true),
                      child: Text(
                        t('أوقف متابعة المخزون', 'Stop tracking stock'),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!mounted || result == null) return;
    if (result == 'notify') await _requestNotifications();
    if (mounted)
      _toast(
        t('إعدادات المخزون اتحدّثت', 'Stock settings updated'),
        sealed: true,
      );
  }
}
