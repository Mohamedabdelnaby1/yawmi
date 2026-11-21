part of 'transfer.dart';

final _reportInk = PdfColor.fromHex('#162C24');
final _reportGreen = PdfColor.fromHex('#205747');
final _reportMint = PdfColor.fromHex('#DAEADA');
final _reportPaper = PdfColor.fromHex('#F3F5EE');
final _reportMuted = PdfColor.fromHex('#416355');

Future<pw.Document> _journalDocument() async => pw.Document(
  theme: pw.ThemeData.withFont(
    base: pw.Font.ttf(await rootBundle.load('assets/Tajawal-Regular.ttf')),
    bold: pw.Font.ttf(await rootBundle.load('assets/Tajawal-Bold.ttf')),
  ),
);

pw.TextStyle _type(double size, {PdfColor? color, bool bold = false}) =>
    pw.TextStyle(
      fontSize: size,
      color: color ?? _reportInk,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );

pw.Widget _reportHero(
  String label,
  String title,
  String range, {
  bool compact = false,
}) => pw.Container(
  padding: pw.EdgeInsets.fromLTRB(16, compact ? 10 : 17, 16, compact ? 8 : 13),
  decoration: pw.BoxDecoration(
    color: _reportGreen,
    borderRadius: pw.BorderRadius.circular(13),
  ),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Text(label, style: _type(10, color: _reportMint, bold: true)),
      pw.SizedBox(height: 4),
      pw.Text(
        title,
        style: _type(compact ? 18 : 27, color: PdfColors.white, bold: true),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        range,
        textDirection: pw.TextDirection.ltr,
        style: _type(10, color: _reportMint),
      ),
    ],
  ),
);

pw.Widget _reportFooter(pw.Context c, bool ar) => pw.Container(
  margin: const pw.EdgeInsets.only(top: 8),
  padding: const pw.EdgeInsets.only(top: 6),
  decoration: pw.BoxDecoration(
    border: pw.Border(top: pw.BorderSide(color: _reportMint)),
  ),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        tr(
          ar,
          'يومي · من التسجيلات اللي اخترتها',
          'Yawmi · Selected journal entries',
        ),
        style: _type(9, color: _reportMuted),
      ),
      pw.Text(
        '${c.pageNumber} / ${c.pagesCount}',
        textDirection: pw.TextDirection.ltr,
        style: _type(9),
      ),
    ],
  ),
);

pw.Widget _reportMetrics(List<(String, String)> entries) => pw.Row(
  children: [
    for (final (index, (label, value)) in entries.indexed) ...[
      if (index > 0) pw.SizedBox(width: 7),
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 6),
          decoration: pw.BoxDecoration(
            color: index == 0 ? _reportMint : _reportPaper,
            borderRadius: pw.BorderRadius.circular(9),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(value, style: _type(19, bold: true), maxLines: 1),
              pw.Text(label, style: _type(9, color: _reportMuted), maxLines: 1),
            ],
          ),
        ),
      ),
    ],
  ],
);

String _shortText(Object? value, int length) {
  final text =
      value?.toString().replaceAll(RegExp(r'[\r\n]+'), ' ').trim() ?? '';
  final printable = text.replaceAllMapped(
    RegExp('[¼½¾⅓⅔⅛⅜⅝⅞]'),
    (match) => const {
      '¼': '1/4',
      '½': '1/2',
      '¾': '3/4',
      '⅓': '1/3',
      '⅔': '2/3',
      '⅛': '1/8',
      '⅜': '3/8',
      '⅝': '5/8',
      '⅞': '7/8',
    }[match[0]]!,
  );
  if (printable.length <= length) return printable;
  return '${String.fromCharCodes(printable.runes.take(length))}…';
}

pw.Widget _reportField(
  String text, {
  double size = 9,
  PdfColor? color,
  int maxLines = 1,
}) => pw.Text(
  text,
  textDirection: RegExp(r'[\u0620-\u064A]').hasMatch(text)
      ? pw.TextDirection.rtl
      : pw.TextDirection.ltr,
  style: _type(size, color: color),
  maxLines: maxLines,
);

int _recordedDays(List<JournalRow> entries) => entries
    .where((e) => e['legacyUndated'] != true)
    .map((e) => dayKey(eventTime(e)))
    .toSet()
    .length;

String _entryExtra(JournalRow e, bool ar) => [
  if (e['tracker'] == medicineCard) ...[
    _shortText(e['amount'], 70),
    _shortText(e['strength'], 45),
    _shortText(e['administration'], 45),
  ],
  entryContext(e['context'], ar),
  if (e['pressureSession'] case final List session when session.length == 2)
    [
      tr(ar, 'متوسط قراءتين', 'Mean of two readings'),
      for (final (index, reading) in session.indexed)
        if (reading is Map)
          '${index + 1}. ${reading['systolic']}/${reading['diastolic']}',
    ].join(' · '),
  if (e['mealMinutes'] case final int mins)
    tr(ar, 'بعد الوجبة بـ $mins د', '$mins min after meal'),
  if (e['readingSource'] != null) readingSourceLabel(e['readingSource'], ar),
  if (readLabDetails(e['labDetails']) case final lab?) ...[
    _shortText(lab['laboratory'], 55),
    if (_shortText(lab['reference'], 51).isNotEmpty)
      '${tr(ar, 'المدى المرجعي للمعمل', 'Lab range')} ${_shortText(lab['reference'], 51)}',
  ],
].where((value) => value.isNotEmpty).join(' · ');

Future<Uint8List> makePdf(
  JournalRow state,
  List<JournalRow> entries,
  bool ar,
  String range, {
  required bool notes,
}) async {
  final doc = await _journalDocument();
  _addJournalPages(doc, state, entries, ar, range, notes: notes);
  return doc.save();
}

void _addJournalPages(
  pw.Document doc,
  JournalRow state,
  List<JournalRow> entries,
  bool ar,
  String range, {
  required bool notes,
}) {
  String t(String a, String e) => tr(ar, a, e);
  final header = [
    t('التاريخ والوقت', 'Date and time'),
    t('المتابعة', 'Tracker'),
    t('النتيجة', 'Result'),
    t('السياق', 'Context'),
  ];
  pw.Widget cell(String text, {bool bold = false, bool heading = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 5),
        child: pw.Text(
          text,
          style: _type(
            heading ? 9 : 10,
            bold: bold,
            color: heading ? PdfColors.white : null,
          ),
        ),
      );
  List<pw.Widget> cells(List<pw.Widget> values) =>
      ar ? values.reversed.toList() : values;
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      margin: const pw.EdgeInsets.all(34),
      maxPages: 1000,
      header: (c) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 11),
        child: _reportHero(
          t('يومي · دفتر المتابعة', 'YAWMI · HEALTH JOURNAL'),
          t('تقرير السجل', 'Journal report'),
          range,
          compact: c.pageNumber > 1,
        ),
      ),
      footer: (c) => _reportFooter(c, ar),
      build: (_) => [
        _reportMetrics([
          (t('إدخال', 'Entries'), entries.length.toString()),
          (
            t('أيام التسجيل', 'Days recorded'),
            _recordedDays(entries).toString(),
          ),
          (
            t('متابعات', 'Trackers'),
            entries.map((e) => e['tracker']).toSet().length.toString(),
          ),
        ]),
        pw.SizedBox(height: 14),
        pw.Table(
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            pw.TableRow(
              repeat: true,
              decoration: pw.BoxDecoration(color: _reportGreen),
              children: cells([
                for (final title in header)
                  cell(title, bold: true, heading: true),
              ]),
            ),
            for (final (i, e) in entries.indexed)
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: i.isEven ? _reportPaper : PdfColors.white,
                ),
                children: cells([
                  cell(
                    e['legacyUndated'] == true
                        ? t('بدون تاريخ', 'Undated')
                        : '${dayKey(eventTime(e))}\n${clockText(eventTime(e).hour * 60 + eventTime(e).minute)}',
                  ),
                  cell(
                    _shortText(
                      e['tracker'] == medicineCard
                          ? e['name']
                          : cardName(state, e['tracker'], ar),
                      75,
                    ),
                    bold: true,
                  ),
                  cell(_shortText(reportValue(e, ar), 340)),
                  cell(
                    [
                      _entryExtra(e, ar),
                      if (notes) _shortText(e['note'], 450),
                    ].where((s) => s.isNotEmpty).join('\n'),
                  ),
                ]),
              ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _sparkline(List<double> values) {
  final pts = values.length <= 24
      ? values
      : List.generate(
          24,
          (i) => values[(i * (values.length - 1) / 23).round()],
        );
  final min = pts.reduce((a, b) => a < b ? a : b);
  final max = pts.reduce((a, b) => a > b ? a : b);
  return pw.CustomPaint(
    size: const PdfPoint(86, 21),
    painter: (canvas, size) {
      canvas.setStrokeColor(_reportGreen);
      canvas.setLineWidth(1.2);
      double y(double n) =>
          max == min ? size.y / 2 : 2 + (n - min) / (max - min) * (size.y - 4);
      for (var i = 1; i < pts.length; i++) {
        canvas.drawLine(
          (i - 1) * size.x / (pts.length - 1),
          y(pts[i - 1]),
          i * size.x / (pts.length - 1),
          y(pts[i]),
        );
        canvas.strokePath();
      }
    },
  );
}

Future<Uint8List> makeVisitSummaryPdf(
  JournalRow state,
  List<JournalRow> entries,
  bool ar,
  String range, {
  DateTime? start,
  DateTime? through,
  bool notes = false,
  bool includeDoseCoverage = false,
  bool appendDetails = false,
}) async {
  final doc = await _journalDocument();
  String t(String a, String e) => tr(ar, a, e);
  final trends = [
    for (final id in [
      'glucose',
      'pressure',
      'a1c',
      'weight',
      'pulse',
      'oxygen',
      'temperature',
      'peak_flow',
    ])
      if (careTrend(state, id, entries) case final trend?) (id, trend),
  ];
  final highlights =
      entries
          .where(
            (e) =>
                ['symptom', 'question', 'lab', 'visit'].contains(e['tracker']),
          )
          .toList()
        ..sort((a, b) => eventTime(b).compareTo(eventTime(a)));
  final coverage =
      includeDoseCoverage &&
          start != null &&
          through != null &&
          calendarSpan(start, through) <= 366
      ? doseCoverage(state, start, through)
      : null;
  final groups = visitSummary(state, entries, ar);
  bool inPeriod(DateTime at) =>
      (start == null || !at.isBefore(start)) &&
      (through == null || dayKey(at.toLocal()).compareTo(dayKey(through)) <= 0);
  final selectedMedicines = entries
      .where((e) => e['tracker'] == medicineCard)
      .map((e) => e['medicine'])
      .toSet();
  final changes = <(JournalRow, JournalRow, DateTime)>[
    for (final med in rows(
      state['meds'],
    ).where((m) => selectedMedicines.contains(m['id'])))
      for (final change in rows(med['changes']))
        if (DateTime.tryParse(change['at'] as String? ?? '') case final at?)
          if (inPeriod(at)) (med, change, at),
  ]..sort((a, b) => b.$3.compareTo(a.$3));
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(34),
      textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      build: (c) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _reportHero(
            t('يومي · قبل الزيارة', 'YAWMI · BEFORE THE VISIT'),
            t('ملخّص المتابعة', 'Visit summary'),
            range,
          ),
          pw.SizedBox(height: 10),
          _reportMetrics([
            (t('إدخال', 'Entries'), entries.length.toString()),
            (
              t('أيام فيها تسجيل', 'Days recorded'),
              _recordedDays(entries).toString(),
            ),
            (
              t('أيام الفترة', 'Days in period'),
              start == null || through == null
                  ? '—'
                  : calendarSpan(start, through).toString(),
            ),
          ]),
          pw.SizedBox(height: 12),
          pw.Text(
            t('اتجاه القياسات', 'Measurement trends'),
            style: _type(16, bold: true),
          ),
          if (trends.isEmpty)
            pw.Text(
              t(
                'مفيش اتجاه رقمي في الفترة المختارة.',
                'No numeric trends in the selected period.',
              ),
              style: _type(10),
            ),
          for (final (i, (id, trend)) in trends.take(4).indexed)
            pw.Container(
              height: 59,
              color: i.isEven ? _reportPaper : PdfColors.white,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 7,
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Text(
                          cardName(state, id, ar),
                          style: _type(13, bold: true),
                        ),
                        pw.Wrap(
                          spacing: 5,
                          crossAxisAlignment: pw.WrapCrossAlignment.center,
                          children: [
                            _reportField(t('المتوسط', 'Mean'), size: 10),
                            _reportField(
                              '${number(trend.mean)}${trend.secondaryMean == null ? '' : '/${number(trend.secondaryMean!)}'} ${trend.unit}',
                              size: 10,
                              color: _reportMuted,
                            ),
                            _reportField(
                              t(
                                '· ${trend.count} قراءة في ${trend.days} يوم',
                                '· ${trend.count} readings over ${trend.days} days',
                              ),
                              size: 10,
                              color: _reportMuted,
                            ),
                          ],
                        ),
                        pw.Wrap(
                          spacing: 5,
                          crossAxisAlignment: pw.WrapCrossAlignment.center,
                          children: [
                            _reportField(t('آخر قراءة', 'Latest')),
                            _reportField(
                              '${number(trend.last)}${trend.secondaryLast == null ? '' : '/${number(trend.secondaryLast!)}'} ${trend.unit}',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (trend.count > 1)
                    pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        _sparkline(trend.points),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          id == 'pressure'
                              ? t('الانقباضي', 'Systolic')
                              : '${number(trend.low)} – ${number(trend.high)} ${trend.unit}',
                          textDirection: id == 'pressure'
                              ? null
                              : pw.TextDirection.ltr,
                          style: _type(8, color: _reportMuted),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          pw.SizedBox(height: 12),
          if (coverage != null && coverage.scheduled > 0) ...[
            pw.Text(
              t(
                'الجرعات حسب الجدول الحالي',
                'Doses under the current schedule',
              ),
              style: _type(14, bold: true),
            ),
            pw.SizedBox(height: 5),
            _reportMetrics([
              (t('اتاخدت', 'Taken'), '${coverage.taken}'),
              (t('اتخطّت', 'Skipped'), '${coverage.skipped}'),
              (t('مفيش تسجيل', 'Unlogged'), '${coverage.unlogged}'),
            ]),
          ] else if (groups.where((g) => g.id == medicineCard).firstOrNull
              case final dose?)
            pw.Text(
              '${dose.title} · ${dose.detail}',
              style: _type(11, bold: true),
            ),
          for (final med
              in rows(state['meds'])
                  .where((med) {
                    if (!entries.any(
                      (e) =>
                          e['tracker'] == medicineCard &&
                          e['medicine'] == med['id'],
                    ))
                      return false;
                    final at = DateTime.tryParse(
                      med['effective'] as String? ?? '',
                    );
                    return at != null &&
                        (start == null || !at.isBefore(start)) &&
                        (through == null ||
                            dayKey(at.toLocal()).compareTo(dayKey(through)) <=
                                0);
                  })
                  .take(2))
            pw.Text(
              "${t('تعديل جدول', 'Schedule changed')} · ${_shortText(med['name'], 40)} · ${dayKey(DateTime.parse(med['effective']).toLocal())}",
              style: _type(9),
              maxLines: 1,
            ),
          for (final (med, change, at) in changes.take(2)) ...[
            pw.SizedBox(height: 5),
            pw.Wrap(
              spacing: 5,
              crossAxisAlignment: pw.WrapCrossAlignment.center,
              children: [
                _reportField(t('تغيير جرعة مسجّل', 'Recorded dose change')),
                _reportField(_shortText(med['name'], 32), color: _reportMuted),
                _reportField(dayKey(at.toLocal()), color: _reportMuted),
                _reportField(t('من', 'from'), color: _reportMuted),
                _reportField(_shortText(change['previous'], 26)),
                _reportField(t('إلى', 'to'), color: _reportMuted),
                _reportField(_shortText(change['dose'], 26)),
              ],
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Text(
            t('نقاط للمراجعة', 'Discuss at the visit'),
            style: _type(16, bold: true),
          ),
          if (highlights.isEmpty)
            pw.Text(
              t(
                'مفيش أعراض أو أسئلة أو تحاليل ضمن الاختيار.',
                'No symptoms, questions, or labs in this selection.',
              ),
              style: _type(10),
            ),
          if (notes && _shortText(state['allergyNotes'], 140).isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Text(
                '${t('الحساسية المسجّلة', 'Recorded allergies')} · ${_shortText(state['allergyNotes'], 140)}',
                style: _type(10, bold: true),
                maxLines: 2,
              ),
            ),
          for (final item in highlights.take(4))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                [
                  cardName(state, item['tracker'], ar),
                  _shortText(reportValue(item, ar), 96),
                  if (notes) _shortText(item['note'], 54),
                ].where((s) => s.isNotEmpty).join(' · '),
                style: _type(10),
                maxLines: 2,
              ),
            ),
          pw.Spacer(),
          _reportFooter(c, ar),
        ],
      ),
    ),
  );
  if (appendDetails && entries.isNotEmpty) {
    _addJournalPages(doc, state, entries, ar, range, notes: notes);
  }
  return doc.save();
}
