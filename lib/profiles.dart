part of 'main.dart';

String profileRuleId(String id, String profile) =>
    profile == ProfileJournal.personal ? id : 'p$profile:$id';

List<JournalRow> rulesForProfile(JournalRow state, bool ar, String id) => [
  for (final row in notificationRules(state, ar))
    {
      ...row,
      'owner': id,
      if (row['medicine'] == null) ...{
        'origin': row['id'],
        'id': profileRuleId(row['id'], id),
      },
    },
];

extension _ProfileControls on _HomeState {
  String? get _profileName => widget.db is ProfileJournal
      ? (widget.db as ProfileJournal).activeName
      : null;

  JournalRow get _widgetState {
    final profiles = widget.db;
    if (profiles is! ProfileJournal) return data;
    return {
      ...data,
      'widgetOwner': profiles.activeId,
      if (profiles.activeName case final name?) 'widgetOwnerName': name,
    };
  }

  Widget _profileCard() => ControlCard(
    title: t('ملفات العيلة', 'Family profiles'),
    subtitle: _profileName ?? t('ملفي الشخصي', 'My journal'),
    icon: Icons.switch_account_outlined,
    tonalColor: lavender,
    onTap: _showProfiles,
  );

  Future<void> _showProfiles() async {
    final journal = widget.db;
    if (journal is! ProfileJournal) return;
    final choice = await _sheet<String>(
      (_) => ListenableBuilder(
        listenable: journal,
        builder: (c, _) => _JournalPanel(
          heading: AppBar(
            title: Text(t('ملفات العيلة', 'Family profiles')),
            leading: const CloseButton(),
          ),
          body: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                t(
                  'كل ملف له تسجيلاته وأدويته. التذكيرات بتشتغل لكل الملفات، ونسخ البيانات والويدجت بيعرضوا الملف المفتوح.',
                  'Every profile has its own entries and medications. Reminders run for all profiles. Backup and widgets use the active profile.',
                ),
              ),
              const SizedBox(height: 12),
              for (final p in journal.profiles)
                ListTile(
                  leading: Icon(
                    p.id == journal.activeId
                        ? Icons.check_circle_rounded
                        : Icons.person_outline,
                  ),
                  title: Text(p.name ?? t('ملفي الشخصي', 'My journal')),
                  subtitle: p.id == journal.activeId
                      ? Text(t('الملف المفتوح', 'Active profile'))
                      : null,
                  onTap: () => Navigator.pop(c, p.id),
                  trailing: PopupMenuButton<String>(
                    tooltip: t('إعدادات الملف', 'Profile settings'),
                    onSelected: (action) async {
                      if (action == 'rename') {
                        final name = await _textPrompt(
                          t('اسم الملف', 'Profile name'),
                          t('الاسم الظاهر', 'Display name'),
                          initial: p.name ?? '',
                        );
                        if (name != null && mounted)
                          await _profileAction(
                            () => journal.rename(p.id, name),
                          );
                      }
                      if (action == 'delete') {
                        final confirmed = await _confirm(
                          t(
                            'تمسح ملف ${p.name}؟',
                            'Delete ${p.name}’s profile?',
                          ),
                          t(
                            'تسجيلاته وتذكيراته هتتمسح من الجهاز.',
                            'Its records and reminders will be removed from this device.',
                          ),
                          t('امسح الملف', 'Delete profile'),
                        );
                        if (confirmed && c.mounted)
                          Navigator.pop(c, 'delete/${p.id}');
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text(t('غيّر الاسم', 'Rename')),
                      ),
                      if (p.id != ProfileJournal.personal)
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(t('امسح الملف', 'Delete profile')),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          footer: JournalButton.icon(
            onPressed: journal.profiles.length >= 9
                ? null
                : () => Navigator.pop(c, 'new'),
            label: Text(t('ضيف فرد من العيلة', 'Add a family member')),
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'new') {
      final name = await _textPrompt(
        t('ملف جديد', 'New profile'),
        t('اسم مختصر لتمييز الملف', 'Short display name'),
      );
      if (name == null || !mounted) return;
      if (name.trim().isEmpty || name.trim().length > 40) {
        _toast(t('اكتب اسم لحد ٤٠ حرف.', 'Enter a name up to 40 characters.'));
        return;
      }
      await _profileAction(() => journal.addProfile(name));
    } else if (choice.startsWith('delete/')) {
      await _profileAction(() => journal.remove(choice.substring(7)));
    } else if (choice != journal.activeId) {
      await _profileAction(() => journal.switchTo(choice));
    }
  }

  Future<void> _profileAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted)
        _toast(t('التغيير ما اتحفظش.', 'Could not save the profile change.'));
    }
  }
}
