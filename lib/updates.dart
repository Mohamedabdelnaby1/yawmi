part of 'main.dart';

const _publicReleases = 'https://github.com/Mohamedabdelnaby1/yawmi/releases';

extension _AppUpdates on _HomeState {
  Future<void> _refreshUpdateOffer() async {
    if (_syncingUpdates) return;
    _syncingUpdates = true;
    try {
      var status = await platform.invokeMapMethod<String, dynamic>(
        'openUpdates',
        ar,
      );
      for (var attempt = 0; mounted; attempt++) {
        final active = status?['enabled'] == true;
        final available = status?['version'] as String?;
        if (active != _hasUpdateChannel || available != _availableUpdate) {
          _redraw(() {
            _hasUpdateChannel = active;
            _availableUpdate = available;
          });
        }
        if (status?['checking'] != true || attempt >= 48) break;
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        status = await platform.invokeMapMethod<String, dynamic>(
          'updateStatus',
        );
      }
    } catch (_) {
      // A release check must not block the journal.
    } finally {
      _syncingUpdates = false;
    }
  }

  Future<void> _openUpdates() async {
    await _page<void>((_) => YawmiUpdateCenter(ar: ar));
    if (mounted) unawaited(_refreshUpdateOffer());
  }
}

class YawmiUpdateCenter extends StatefulWidget {
  const YawmiUpdateCenter({super.key, required this.ar});
  final bool ar;

  @override
  State<YawmiUpdateCenter> createState() => _UpdateCenterState();
}

class _UpdateCenterState extends State<YawmiUpdateCenter>
    with WidgetsBindingObserver {
  Map<String, dynamic> _status = {};
  Timer? _poll;
  bool _busy = false;
  bool _unreachable = false;
  bool _waitingForPermission = false;
  String t(String ar, String en) => tr(widget.ar, ar, en);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    _poll?.cancel();
    try {
      final status = await platform.invokeMapMethod<String, dynamic>(
        'updateStatus',
      );
      if (!mounted) return;
      setState(() {
        _status = status ?? {};
        _unreachable = false;
      });
      if (_checking || _downloading) {
        _poll = Timer(const Duration(milliseconds: 500), _refresh);
      }
    } catch (_) {
      if (mounted) setState(() => _unreachable = true);
    }
  }

  bool get _checking => _status['checking'] == true;
  bool get _downloading => (_status['progress'] as int? ?? -1) >= 0;
  bool get _ready => _status['ready'] == true;

  Future<void> _action(String method, [Object? arguments]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final outcome = await platform.invokeMethod<Object>(method, arguments);
      if (!mounted) return;
      if (method == 'installUpdate') {
        setState(() => _waitingForPermission = outcome == 'permission');
      }
      await _refresh();
    } catch (_) {
      if (mounted) setState(() => _unreachable = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = _status['version'] as String?;
    final installed = _status['installed'] as String?;
    final progress = (_status['progress'] as int? ?? -1).clamp(0, 100);
    final lastChecked = _status['checkedAt'] as int? ?? 0;
    final size = _status['size'] as int?;
    final supported = _status['enabled'] == true;
    final error = _status['error'] as String?;
    final checkFailed = _unreachable || error == 'check';
    final notes = (_status['notes'] as String? ?? '').split(
      RegExp(r'^#{1,6} English\s*$', multiLine: true),
    );
    final summary = (widget.ar ? notes.first : notes.last)
        .replaceAll(RegExp(r'[*#`]+'), '')
        .trim();
    return Scaffold(
      appBar: AppBar(title: Text(t('تحديثات يومي', 'Yawmi updates'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          JournalCover(
            title: version == null
                ? t('إصدار يومي', 'Your Yawmi version')
                : t('تحديث جديد متاح', 'A new update is available'),
            subtitle: [
              if (installed != null)
                t('المثبّت $installed', 'Installed $installed'),
              if (version != null) t('المتاح $version', 'Available $version'),
              if (size != null) '${number(size / 1048576)} ${t('م.ب', 'MB')}',
            ].join('  ·  '),
            icon: version == null
                ? Icons.system_update_rounded
                : Icons.upgrade_rounded,
            accent: mint,
          ),
          const SizedBox(height: 12),
          if (supported)
            SwitchListTile(
              title: Text(t('فحص التحديثات تلقائيًا', 'Check automatically')),
              subtitle: Text(
                t(
                  'يومي بيشوف لو فيه إصدار جديد لما تفتحه، وبيفحص من وقت للتاني.',
                  'Yawmi checks on launch and periodically in the background.',
                ),
              ),
              value: _status['automatic'] == true,
              onChanged: _busy
                  ? null
                  : (on) => _action('automaticUpdates', {
                      'enabled': on,
                      'arabic': widget.ar,
                    }),
            ),
          if (_checking || _downloading) ...[
            const SizedBox(height: 12),
            Text(
              _downloading
                  ? t(
                      'بننزّل التحديث · $progress٪',
                      'Downloading update · $progress%',
                    )
                  : t('بنفحص لو فيه تحديث…', 'Checking for updates…'),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _downloading ? progress / 100 : null,
            ),
          ],
          if (checkFailed ||
              error == 'verification' ||
              error == 'download') ...[
            const SizedBox(height: 12),
            Text(switch (error) {
              'verification' => t(
                'الملف ماعدّاش فحص التوقيع أو البصمة الرقمية. جرّب التنزيل مرة تانية.',
                'The APK did not pass signature or checksum verification. Try downloading it again.',
              ),
              'download' => t(
                'التنزيل وقف. راجع الاتصال والمساحة وجرّب تاني.',
                'The download stopped. Check your connection and storage, then retry.',
              ),
              _ => t(
                'ماقدرناش نفحص التحديثات على GitHub. راجع النت وجرّب تاني.',
                'Could not reach GitHub releases. Try again.',
              ),
            }, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (lastChecked > 0 && !_checking) ...[
            const SizedBox(height: 12),
            Text(
              version == null && !checkFailed
                  ? t('أنت على أحدث إصدار.', 'You’re up to date.')
                  : t('آخر فحص ناجح', 'Last successful check'),
            ),
            Text(
              DateFormat(
                'd MMM · HH:mm',
                widget.ar ? 'ar' : 'en',
              ).format(DateTime.fromMillisecondsSinceEpoch(lastChecked)),
            ),
          ],
          if (_waitingForPermission && _ready) ...[
            const SizedBox(height: 12),
            Text(
              t(
                'اسمح ليومي بتثبيت التحديث في إعدادات أندرويد، وارجع واضغط «ثبّت التحديث».',
                'Allow installs from Yawmi in Android settings, then return and tap “Install update”.',
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (supported && version != null)
            JournalButton.icon(
              onPressed: _busy || _downloading
                  ? null
                  : () => _action(_ready ? 'installUpdate' : 'downloadUpdate'),
              icon: Icon(
                _ready ? Icons.install_mobile_rounded : Icons.download_rounded,
              ),
              label: Text(
                _ready
                    ? t('ثبّت التحديث', 'Install update')
                    : t('نزّل التحديث', 'Download update'),
              ),
            ),
          if (supported)
            OutlinedButton.icon(
              onPressed: _busy || _checking
                  ? null
                  : () => _action('checkUpdate'),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(t('افحص دلوقتي', 'Check now')),
            ),
          if (version != null && summary.isNotEmpty) ...[
            SectionTitle(t('الجديد في الإصدار', 'What’s new')),
            Text(summary, maxLines: 12, overflow: TextOverflow.ellipsis),
          ],
          TextButton.icon(
            onPressed: _busy
                ? null
                : () => _action(
                    'openPrivacy',
                    '$_publicReleases/${version == null ? 'latest' : 'tag/v$version'}',
                  ),
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(
              t('عرض الإصدارات على GitHub', 'View releases on GitHub'),
            ),
          ),
        ],
      ),
    );
  }
}
