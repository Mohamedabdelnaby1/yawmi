import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show compute;

import 'care_data.dart';
import 'domain.dart';

const excelMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

Future<Uint8List> makeExcel(
  JournalRow state,
  List<JournalRow> rows,
  bool ar,
  String period, {
  required bool notes,
}) => compute(_workbook, (state, rows, ar, period, notes));

const _sheetNs = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _docRel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pkgRel = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _xmlHeader = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

String _xml(Object text) => const HtmlEscape(HtmlEscapeMode.element).convert(
  text.toString().replaceAll(
    RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\ufffe\uffff]'),
    '',
  ),
);

String _column(int index) {
  var name = '';
  for (var n = index + 1; n > 0; n = (n - 1) ~/ 26) {
    name = String.fromCharCode(65 + (n - 1) % 26) + name;
  }
  return name;
}

double _excelDate(DateTime at) {
  final wall = DateTime.utc(
    at.year,
    at.month,
    at.day,
    at.hour,
    at.minute,
    at.second,
  );
  final serial = wall.difference(DateTime.utc(1899, 12, 31)).inSeconds / 86400;
  return serial >= 60 ? serial + 1 : serial;
}

String _cell(Object? value, String ref, bool header, bool even) {
  if (value == null) return '';
  final prefix = '<c r="$ref"';
  final stripe = even ? 3 : 0;
  if (value is DateTime) {
    return '$prefix s="${even ? 4 : 2}"><v>${_excelDate(value)}</v></c>';
  }
  if (value is num && value.isFinite)
    return '$prefix s="$stripe"><v>$value</v></c>';
  if (value is bool)
    return '$prefix s="$stripe" t="b"><v>${value ? 1 : 0}</v></c>';
  final style = header ? 1 : stripe;
  return '$prefix s="$style" t="inlineStr"><is><t xml:space="preserve">${_xml(value)}</t></is></c>';
}

typedef _Sheet = ({
  String name,
  List<String> headers,
  List<List<Object?>> values,
  List<int> widths,
});

String _worksheet(_Sheet sheet, bool ar) {
  final end = '${_column(sheet.headers.length - 1)}${sheet.values.length + 1}';
  final data = StringBuffer('$_xmlHeader<worksheet xmlns="$_sheetNs">')
    ..write(
      '<dimension ref="A1:$end"/><sheetViews><sheetView workbookViewId="0" showGridLines="0" rightToLeft="${ar ? 1 : 0}">',
    )
    ..write(
      '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>',
    )
    ..write('<sheetFormatPr defaultRowHeight="19"/><cols>');
  for (final (index, width) in sheet.widths.indexed) {
    data.write(
      '<col min="${index + 1}" max="${index + 1}" width="$width" customWidth="1"/>',
    );
  }
  data.write('</cols><sheetData>');
  void writeRow(int index, List<Object?> row) {
    data.write(
      index == 1 ? '<row r="1" ht="25" customHeight="1">' : '<row r="$index">',
    );
    for (final (column, value) in row.indexed) {
      data.write(
        _cell(value, '${_column(column)}$index', index == 1, index.isEven),
      );
    }
    data.write('</row>');
  }

  writeRow(1, sheet.headers);
  for (final (index, row) in sheet.values.indexed) {
    writeRow(index + 2, row);
  }
  data.write('</sheetData><autoFilter ref="A1:$end"/></worksheet>');
  return data.toString();
}

Uint8List _workbook((JournalRow, List<JournalRow>, bool, String, bool) input) {
  final (state, entries, ar, period, notes) = input;
  String t(String a, String e) => tr(ar, a, e);
  final readings = <List<Object?>>[],
      doses = <List<Object?>>[],
      labs = <List<Object?>>[];
  for (final entry in entries) {
    final id = entry['tracker'] as String;
    final stamp = entry['legacyUndated'] == true ? null : eventTime(entry);
    if (id == medicineCard) {
      doses.add([
        stamp,
        entry['name'],
        entry['amount'],
        entry['strength'],
        entry['administration'],
        if (entry['scheduled'] is String)
          DateTime.tryParse(entry['scheduled'])?.toLocal()
        else
          null,
        entry['status'] == 'taken'
            ? t('اتاخدت', 'Taken')
            : t('اتخطّت', 'Skipped'),
        if (notes) entry['note'],
      ]);
      continue;
    }
    final lab = id == 'lab' ? readLabDetails(entry['labDetails']) : null;
    if (lab != null) {
      labs.add([
        stamp,
        entry['values']['value'],
        lab['result'],
        lab['unit'],
        lab['laboratory'],
        lab['reference'],
        if (notes) entry['note'],
      ]);
      continue;
    }
    final tracker = trackerFor(state, id);
    if (tracker == null || entry['values'] is! Map) continue;
    for (final value in (entry['values'] as Map).entries) {
      readings.add([
        stamp,
        tracker.name(ar),
        tracker.fields.where((f) => f.id == value.key).firstOrNull?.name(ar) ??
            value.key,
        value.value,
        entry['unit'],
        entryContext(entry['context'], ar),
        entry['mealMinutes'],
        readingSourceLabel(entry['readingSource'], ar),
        if (notes) entry['note'],
      ]);
    }
    final readingsInSession = entry['pressureSession'];
    if (id == 'pressure' && readingsInSession is List) {
      for (final (index, sample) in readingsInSession.indexed) {
        if (sample is! Map) continue;
        for (final field in tracker.fields.where(
          (field) => sample[field.id] is num,
        )) {
          readings.add([
            stamp,
            tracker.name(ar),
            '${field.name(ar)} · ${index + 1}',
            sample[field.id],
            entry['unit'],
            t('جلسة الضغط', 'Blood pressure session'),
            null,
            t('جهاز قياس', 'Meter'),
            if (notes) null,
          ]);
        }
      }
    }
  }
  final sheets = <_Sheet>[
    (
      name: t('ملخص', 'Summary'),
      headers: [t('يومي', 'Yawmi'), t('التقرير', 'Report')],
      values: [
        [t('الفترة', 'Period'), period],
        [t('عدد التسجيلات', 'Journal entries'), entries.length],
        [
          t('أيام فيها تسجيل', 'Days with entries'),
          entries
              .where((row) => row['legacyUndated'] != true)
              .map((row) => dayKey(eventTime(row)))
              .toSet()
              .length,
        ],
      ],
      widths: [28, 42],
    ),
    (
      name: t('القياسات', 'Readings'),
      headers: [
        t('وقت القياس', 'Recorded time'),
        t('المتابعة', 'Tracker'),
        t('الحقل', 'Field'),
        t('القيمة', 'Value'),
        t('الوحدة', 'Unit'),
        t('السياق', 'Context'),
        t('دقائق من الوجبة', 'Minutes since meal'),
        t('المصدر', 'Source'),
        if (notes) t('ملاحظات', 'Notes'),
      ],
      values: readings,
      widths: [23, 25, 20, 19, 14, 20, 24, 19, if (notes) 40],
    ),
    (
      name: t('الجرعات', 'Doses'),
      headers: [
        t('وقت التسجيل', 'Logged time'),
        t('الدواء', 'Medicine'),
        t('الجرعة', 'Dose'),
        t('التركيز', 'Strength'),
        t('طريقة الاستخدام', 'Route'),
        t('وقت الموعد', 'Scheduled time'),
        t('الحالة', 'Status'),
        if (notes) t('ملاحظات', 'Notes'),
      ],
      values: doses,
      widths: [23, 28, 20, 19, 24, 23, 18, if (notes) 40],
    ),
    (
      name: t('التحاليل', 'Lab results'),
      headers: [
        t('وقت العينة', 'Sample time'),
        t('التحليل', 'Test'),
        t('النتيجة', 'Result'),
        t('الوحدة', 'Unit'),
        t('المعمل', 'Laboratory'),
        t('المدى المرجعي للمعمل', 'Lab reference range'),
        if (notes) t('ملاحظات', 'Notes'),
      ],
      values: labs,
      widths: [23, 29, 16, 15, 29, 27, if (notes) 40],
    ),
  ];
  final zip = Archive();
  void add(String path, String body) {
    final bytes = utf8.encode(body);
    zip.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  String types(String path, String type) =>
      '<Override PartName="/$path" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.$type+xml"/>';
  String rel(String id, String kind, String target) =>
      '<Relationship Id="$id" Type="$_docRel/$kind" Target="$target"/>';
  add(
    '[Content_Types].xml',
    '$_xmlHeader<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
        '${types('xl/workbook.xml', 'sheet.main')}${types('xl/styles.xml', 'styles')}'
        '${[for (var i = 1; i <= sheets.length; i++) types('xl/worksheets/sheet$i.xml', 'worksheet')].join()}</Types>',
  );
  add(
    '_rels/.rels',
    '$_xmlHeader<Relationships xmlns="$_pkgRel">${rel('rId1', 'officeDocument', 'xl/workbook.xml')}</Relationships>',
  );
  add(
    'xl/workbook.xml',
    '$_xmlHeader<workbook xmlns="$_sheetNs" xmlns:r="$_docRel"><sheets>'
        '${[for (final (i, sheet) in sheets.indexed) '<sheet name="${_xml(sheet.name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}</sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '$_xmlHeader<Relationships xmlns="$_pkgRel">'
        '${[for (var i = 1; i <= sheets.length; i++) rel('rId$i', 'worksheet', 'worksheets/sheet$i.xml')].join()}'
        '${rel('rIdStyles', 'styles', 'styles.xml')}</Relationships>',
  );
  add('xl/styles.xml', _styles);
  for (final (index, sheet) in sheets.indexed) {
    add('xl/worksheets/sheet${index + 1}.xml', _worksheet(sheet, ar));
  }
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

const _styles = '''$_xmlHeader<styleSheet xmlns="$_sheetNs">
<numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy-mm-dd hh:mm"/></numFmts>
<fonts count="2">
<font><sz val="11"/><color rgb="FF192D27"/><name val="Calibri"/></font>
<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
</fonts><fills count="4">
<fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF205747"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFEAF2E8"/><bgColor indexed="64"/></patternFill></fill>
</fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="5"><xf xfId="0" numFmtId="0" fontId="0" fillId="0" borderId="0"/>
<xf xfId="0" numFmtId="0" fontId="1" fillId="2" borderId="0" applyFont="1" applyFill="1"/>
<xf xfId="0" numFmtId="164" fontId="0" fillId="0" borderId="0" applyNumberFormat="1"/>
<xf xfId="0" numFmtId="0" fontId="0" fillId="3" borderId="0" applyFill="1"/>
<xf xfId="0" numFmtId="164" fontId="0" fillId="3" borderId="0" applyNumberFormat="1" applyFill="1"/>
</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>''';
