part of 'main.dart';

enum ScanField { number, label, unit, expiry }

List<String> scanCandidates(String text, ScanField type) {
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty);
  if (type == ScanField.label)
    return lines
        .where((line) => RegExp(r'\p{L}', unicode: true).hasMatch(line))
        .map((line) => line.length > 65 ? line.substring(0, 65) : line)
        .toSet()
        .take(14)
        .toList();
  final samples = normalize(text).replaceAll('٫', '.');
  if (type == ScanField.expiry) {
    final dates = <String>{};
    for (final match in RegExp(
      r'\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b',
    ).allMatches(samples)) {
      final value =
          '${match[1]}-${match[2]!.padLeft(2, '0')}-${match[3]!.padLeft(2, '0')}';
      if (parseCalendarDate(value) != null) dates.add(value);
    }
    for (final match in RegExp(
      r'\b(1[3-9]|2\d|3[01])[/.-](\d{1,2})[/.-](20\d{2})\b',
    ).allMatches(samples)) {
      final value = '${match[3]}-${match[2]!.padLeft(2, '0')}-${match[1]}';
      if (parseCalendarDate(value) != null) dates.add(value);
    }
    return dates.take(12).toList();
  }
  final pattern = type == ScanField.unit
      ? RegExp(
          r'(?:mmol\s*/\s*l|mg\s*/\s*d[lL]|mmhg|mg\s*/\s*l|g\s*/\s*d[lL]|iu\s*/\s*l|%)',
          caseSensitive: false,
        )
      : RegExp(r'(?<![\d.])[+-]?(?:\d{1,8}(?:[.,]\d{1,6})?)(?![\d.])');
  return pattern
      .allMatches(type == ScanField.unit ? text : samples)
      .map(
        (match) => match[0]!.replaceAll(
          type == ScanField.unit ? RegExp(r'\s+') : ',',
          type == ScanField.unit ? '' : '.',
        ),
      )
      .toSet()
      .take(14)
      .toList();
}

extension _PhotoInput on _HomeState {
  Future<Map<String, String>?> _scanFields(
    Map<String, (String, ScanField)> fields,
  ) async {
    if (!Platform.isAndroid) return null;
    final method = await _sheet<String>(
      (c) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(t('اقرأ من صورة', 'Read from a photo')),
            Text(
              t(
                'اختار من اللي اتقرا وراجع الحقول قبل الحفظ.',
                'Choose the text you want to use and verify the fields before saving.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(t('صوّر دلوقتي', 'Take a photo')),
              onTap: () => Navigator.pop(c, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(t('اختار صورة', 'Choose image')),
              onTap: () => Navigator.pop(c, 'file'),
            ),
          ],
        ),
      ),
    );
    if (method == null || !mounted) return null;
    String? recognized;
    try {
      if (method == 'camera') {
        recognized = await platform.invokeMethod<String>('scanCamera');
      } else {
        final file = await FilePicker.platform.pickFiles(type: FileType.image);
        final selected = file?.files.single;
        if (selected == null || !mounted) return null;
        if (selected.path == null || selected.size > 16000000) {
          _toast(
            t(
              'اختار صورة أصغر من ١٦ ميجابايت.',
              'Choose an image under 16 MB.',
            ),
          );
          return null;
        }
        recognized = await platform.invokeMethod<String>(
          'scanImage',
          selected.path,
        );
      }
    } catch (_) {
      if (mounted)
        _toast(
          t(
            'ماقدرناش نقرا الصورة. جرّب صورة أوضح.',
            'Could not read this photo. Try a clearer image.',
          ),
        );
      return null;
    }
    if (recognized == null || !mounted) return null;
    if (recognized.trim().isEmpty) {
      _toast(t('مفيش كتابة واضحة في الصورة.', 'No clear text in this photo.'));
      return null;
    }
    final detected = recognized;
    final candidates = {
      for (final field in fields.entries)
        field.key: scanCandidates(detected, field.value.$2),
    };
    final result = <String, String>{};
    return _sheet<Map<String, String>>(
      (_) => StatefulBuilder(
        builder: (c, redraw) => _JournalPanel(
          heading: AppBar(
            title: Text(t('راجع اللي اتقرا', 'Review detected text')),
            leading: const CloseButton(),
          ),
          body: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              for (final field in fields.entries) ...[
                SectionTitle(field.value.$1),
                if (candidates[field.key]!.isEmpty)
                  Text(
                    t(
                      'مفيش اختيار واضح. ممكن تكمل الحقل يدوي.',
                      'Nothing clear to select. You can fill in the field yourself.',
                    ),
                  ),
                Wrap(
                  spacing: 7,
                  children: [
                    for (final value in candidates[field.key]!)
                      ChoiceChip(
                        label: Text(value),
                        selected: result[field.key] == value,
                        onSelected: (selected) => redraw(() {
                          if (selected) {
                            result[field.key] = value;
                          } else {
                            result.remove(field.key);
                          }
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              ExpansionTile(
                title: Text(t('كل النص اللي اتقرا', 'All detected text')),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: SelectableText(detected),
                  ),
                ],
              ),
            ],
          ),
          footer: JournalButton.icon(
            onPressed: result.isEmpty ? null : () => Navigator.pop(c, result),
            icon: const Icon(Icons.arrow_back_rounded),
            label: Text(
              t('انقل اللي اخترته للمراجعة', 'Use selection in form'),
            ),
          ),
        ),
      ),
    );
  }
}
