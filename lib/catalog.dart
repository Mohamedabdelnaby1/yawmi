import 'domain.dart';

class CatalogEntry {
  final String id, ar, en, category;
  final List<String> suggested, aliases;
  const CatalogEntry(
    this.id,
    this.ar,
    this.en,
    this.category,
    this.suggested,
    this.aliases,
  );
  String name(bool arabic) => tr(arabic, ar, en);
  bool matches(String query) =>
      normalize([ar, en, ...aliases].join(' ')).contains(normalize(query));
}

const categories = <String, (String, String)>{
  'metabolic': ('الأيض والغدد', 'Metabolic & endocrine'),
  'heart': ('القلب والدورة الدموية', 'Heart & circulation'),
  'air': ('التنفس والحساسية', 'Respiratory & allergy'),
  'brain': ('الأعصاب والصداع', 'Neurology'),
  'gut': ('الجهاز الهضمي', 'Digestive'),
  'kidney': ('الكلى والمسالك', 'Kidney & urinary'),
  'skin': ('الجلد', 'Skin'),
  'joint': ('العضلات والمفاصل', 'Muscles & joints'),
  'sleep': ('النوم والصحة النفسية', 'Sleep & mental health'),
  'blood': ('الدم', 'Blood'),
  'eye': ('العين', 'Eye'),
  'reproductive': ('صحة المرأة والإنجاب', 'Reproductive health'),
  'immune': ('المناعة', 'Immune health'),
  'oncology': ('الأورام والمتابعة بعد العلاج', 'Oncology & follow-up'),
};

final _historicalCatalog = _catalog
    .trim()
    .split('\n')
    .map((line) {
      final p = line.split('|');
      return CatalogEntry(
        p[0],
        p[2],
        p[3],
        p[1],
        p.length > 4 && p[4].isNotEmpty ? p[4].split(',') : [],
        p.length > 5 ? p[5].split(',') : [],
      );
    })
    .toList(growable: false);

const conditionFamilies = <String, List<String>>{
  'diabetes2': ['diabetes1', 'gestational-diabetes', 'prediabetes'],
  'hypothyroid': ['hyperthyroid', 'hashimoto', 'graves'],
  'hypertension': ['hypotension'],
  'arrhythmia': ['afib'],
  'coronary': ['heart-failure'],
  'allergic-rhinitis': ['food-allergy', 'drug-allergy', 'urticaria'],
  'migraine': ['cluster'],
  'colitis': ['crohn'],
  'gerd': ['gastritis'],
  'arthritis': ['rheumatoid', 'ankylosing'],
  'insomnia': ['apnea', 'restless-legs', 'narcolepsy'],
  'anemia': ['iron', 'sickle', 'thalassemia'],
  'eczema': ['psoriasis', 'rosacea', 'acne'],
  'endometriosis': ['fibroids'],
  'recovery': [
    'breast-cancer',
    'colorectal-cancer',
    'prostate-cancer',
    'lymphoma',
  ],
};

const _familyNames = <String, (String, String)>{
  'diabetes2': ('السكري', 'Diabetes'),
  'hypothyroid': ('الغدة الدرقية', 'Thyroid conditions'),
  'hypertension': ('مشاكل ضغط الدم', 'Blood pressure conditions'),
  'arrhythmia': ('اضطراب ضربات القلب', 'Heart rhythm conditions'),
  'coronary': ('أمراض القلب', 'Heart conditions'),
  'allergic-rhinitis': ('الحساسية', 'Allergies'),
  'migraine': ('الصداع والشقيقة', 'Headaches & migraine'),
  'colitis': ('التهاب الأمعاء المزمن', 'Inflammatory bowel conditions'),
  'gerd': ('مشاكل المعدة والارتجاع', 'Stomach symptoms & reflux'),
  'arthritis': ('التهاب وآلام المفاصل', 'Arthritis & joint pain'),
  'insomnia': ('اضطرابات النوم', 'Sleep conditions'),
  'anemia': ('فقر الدم', 'Anemia'),
  'eczema': ('مشاكل الجلد', 'Skin conditions'),
  'endometriosis': ('أعراض وآلام الحوض', 'Pelvic symptoms & pain'),
  'recovery': ('المتابعة مع الأورام', 'Oncology follow-up'),
};

const _common = {
  'diabetes2',
  'hypothyroid',
  'pcos',
  'gout',
  'hypertension',
  'arrhythmia',
  'coronary',
  'high-cholesterol',
  'asthma',
  'allergic-rhinitis',
  'copd',
  'migraine',
  'epilepsy',
  'ms',
  'gerd',
  'ibs',
  'colitis',
  'celiac',
  'fatty-liver',
  'ckd',
  'kidney-stones',
  'eczema',
  'arthritis',
  'fibromyalgia',
  'osteoporosis',
  'insomnia',
  'anxiety',
  'depression',
  'anemia',
  'glaucoma',
  'endometriosis',
  'menopause',
  'postpartum',
  'post-transplant',
  'recovery',
};

CatalogEntry? _historical(String id) =>
    _historicalCatalog.where((entry) => entry.id == id).firstOrNull;

final catalog = [
  for (final entry in _historicalCatalog)
    if (_common.contains(entry.id))
      CatalogEntry(
        entry.id,
        _familyNames[entry.id]?.$1 ?? entry.ar,
        _familyNames[entry.id]?.$2 ?? entry.en,
        entry.category,
        entry.suggested,
        [
          entry.ar,
          entry.en,
          ...entry.aliases,
          for (final id in conditionFamilies[entry.id] ?? const [])
            if (_historical(id) case final CatalogEntry subtype) ...[
              subtype.ar,
              subtype.en,
              ...subtype.aliases,
            ],
        ],
      ),
];

CatalogEntry? catalogCondition(Object? id) => id is String
    ? catalog.where((entry) => entry.id == id).firstOrNull ?? _historical(id)
    : null;

String conditionFamilyId(String id) =>
    conditionFamilies.entries
        .where((entry) => entry.value.contains(id))
        .firstOrNull
        ?.key ??
    id;

List<CatalogEntry> conditionVariants(String id) => [
  if (conditionFamilies.containsKey(id))
    for (final choice in [id, ...conditionFamilies[id]!])
      if (_historical(choice) case final CatalogEntry entry) entry,
];

final catalogOverview = () {
  final groups = [
    for (final category in categories.keys)
      catalog.where((entry) => entry.category == category).toList(),
  ];
  final depth = groups.fold(
    0,
    (n, group) => n < group.length ? group.length : n,
  );
  return [
    for (var i = 0; i < depth; i++)
      for (final group in groups)
        if (i < group.length) group[i],
  ];
}();

String conditionName(JournalRow condition, bool ar) =>
    ((condition['label'] as String?)?.trim().isNotEmpty == true
        ? condition['label'] as String
        : catalogCondition(condition['id'])?.name(ar)) ??
    condition['name'];

List<String> suggestedFor(CatalogEntry? condition) {
  if (condition == null) return const ['symptom', 'note'];
  final category = switch (condition.category) {
    'sleep' => const ['sleep', 'mood'],
    'air' => const ['symptom'],
    'gut' => const ['symptom', 'meal'],
    'joint' => const ['pain', 'activity'],
    'eye' || 'skin' => const ['symptom', 'note'],
    'blood' => const ['symptom', 'lab'],
    'reproductive' => const ['symptom', 'visit'],
    'immune' => const ['symptom', 'lab', 'visit'],
    'oncology' => const ['symptom', 'lab', 'visit', 'question'],
    _ => const ['symptom', 'note'],
  };
  final specific = switch (condition.id) {
    'asthma' => const ['peak_flow'],
    'pcos' => const ['cycle'],
    'endometriosis' || 'fibroids' => const ['cycle', 'pain'],
    'migraine' || 'cluster' => const ['pain'],
    'diabetes1' ||
    'diabetes2' ||
    'gestational-diabetes' ||
    'prediabetes' => const ['meal', 'a1c'],
    _ => const <String>[],
  };
  return {...condition.suggested, ...specific, ...category}.toList();
}

Map<String, List<String>> recommendations(JournalRow state, bool ar) {
  final result = <String, List<String>>{};
  for (final condition in rows(state['conditions'])) {
    if (condition['archived'] == true) continue;
    final match = catalogCondition(condition['id']);
    final ids = condition['links'] is List
        ? strings(condition['links'])
        : suggestedFor(match);
    for (final id in ids) {
      if (trackerFor(state, id) != null) {
        (result[id] ??= []).add(conditionName(condition, ar));
      }
    }
  }
  return result;
}

const _catalog = '''
diabetes2|metabolic|السكري من النوع الثاني|Type 2 diabetes|glucose|سكر النوع التاني,سكر النوع الثاني,سكري 2
diabetes1|metabolic|السكري من النوع الأول|Type 1 diabetes|glucose|سكر النوع الاول,سكري 1
gestational-diabetes|metabolic|سكري الحمل|Gestational diabetes|glucose|سكر الحمل
prediabetes|metabolic|مقدمات السكري|Prediabetes|glucose|ما قبل السكري
hypothyroid|metabolic|قصور الغدة الدرقية|Hypothyroidism|symptom|خمول الغدة
hyperthyroid|metabolic|فرط نشاط الغدة الدرقية|Hyperthyroidism|symptom|نشاط الغدة
hashimoto|metabolic|التهاب الغدة الدرقية لهاشيموتو|Hashimoto thyroiditis
graves|metabolic|داء غريفز|Graves disease
pcos|metabolic|متلازمة تكيس المبايض|Polycystic ovary syndrome|symptom|تكيس المبيض,PCOS
gout|metabolic|النقرس|Gout
hypertension|heart|ارتفاع ضغط الدم|High blood pressure|pressure|ضغط عالي,فرط الضغط,hypertension
hypotension|heart|انخفاض ضغط الدم|Low blood pressure|pressure|ضغط واطي,hypotension
heart-failure|heart|قصور القلب|Heart failure|pressure,pulse,weight|فشل القلب
coronary|heart|مرض الشريان التاجي|Coronary artery disease|pressure,pulse
afib|heart|الرجفان الأذيني|Atrial fibrillation|pulse,symptom
arrhythmia|heart|اضطراب نظم القلب|Arrhythmia|pulse,symptom
high-cholesterol|heart|ارتفاع الكوليسترول|High cholesterol
venous|heart|القصور الوريدي المزمن|Chronic venous insufficiency
asthma|air|الربو|Asthma|symptom|ازمة تنفس
allergic-rhinitis|air|الحساسية الموسمية|Seasonal allergies|symptom|حساسية الانف,حمى القش
copd|air|الانسداد الرئوي المزمن|Chronic obstructive pulmonary disease|symptom|COPD
food-allergy|air|حساسية الطعام|Food allergy|symptom
sinusitis|air|التهاب الجيوب الأنفية المزمن|Chronic sinusitis|symptom
bronchiectasis|air|توسع القصبات|Bronchiectasis
drug-allergy|air|حساسية الأدوية|Drug allergy
migraine|brain|الصداع النصفي|Migraine|symptom|شقيقة
epilepsy|brain|الصرع|Epilepsy|symptom
ms|brain|التصلب المتعدد|Multiple sclerosis|symptom
parkinsons|brain|داء باركنسون|Parkinson disease|symptom|شلل رعاش
neuropathy|brain|اعتلال الأعصاب الطرفية|Peripheral neuropathy
trigeminal|brain|ألم العصب الثلاثي التوائم|Trigeminal neuralgia
cluster|brain|الصداع العنقودي|Cluster headache|symptom
vertigo|brain|الدوار الوضعي الحميد|Benign positional vertigo
gerd|gut|الارتجاع المعدي المريئي|Acid reflux|symptom|ارتجاع المريء,GERD
ibs|gut|متلازمة القولون العصبي|Irritable bowel syndrome|symptom|IBS
celiac|gut|الداء البطني|Celiac disease|symptom|سيلياك,حساسية الغلوتين
crohn|gut|داء كرون|Crohn disease|symptom
colitis|gut|التهاب القولون التقرحي|Ulcerative colitis|symptom
lactose|gut|عدم تحمل اللاكتوز|Lactose intolerance
gallstones|gut|حصوات المرارة|Gallstones
fatty-liver|gut|مرض الكبد الدهني|Fatty liver disease
gastritis|gut|التهاب المعدة|Gastritis
ckd|kidney|مرض الكلى المزمن|Chronic kidney disease|pressure
kidney-stones|kidney|حصوات الكلى|Kidney stones
overactive-bladder|kidney|فرط نشاط المثانة|Overactive bladder
interstitial-cystitis|kidney|التهاب المثانة الخلالي|Interstitial cystitis
polycystic-kidney|kidney|داء الكلى متعددة الكيسات|Polycystic kidney disease
prostate|kidney|تضخم البروستاتا الحميد|Benign prostate enlargement
eczema|skin|الإكزيما|Eczema|symptom|اكزيما,التهاب الجلد التاتبي
psoriasis|skin|الصدفية|Psoriasis|symptom
rosacea|skin|الوردية|Rosacea
acne|skin|حب الشباب|Acne
vitiligo|skin|البهاق|Vitiligo
urticaria|skin|الشرى المزمن|Chronic urticaria
alopecia|skin|الثعلبة البقعية|Alopecia areata
arthritis|joint|الفصال العظمي|Osteoarthritis|symptom|خشونة المفاصل
rheumatoid|joint|التهاب المفاصل الروماتويدي|Rheumatoid arthritis|symptom|روماتويد
ankylosing|joint|التهاب الفقار المقسط|Ankylosing spondylitis
osteoporosis|joint|هشاشة العظام|Osteoporosis
fibromyalgia|joint|الألم العضلي الليفي|Fibromyalgia|symptom,sleep
lupus|joint|الذئبة الحمامية الجهازية|Systemic lupus erythematosus
scoliosis|joint|الجنف|Scoliosis
carpal|joint|متلازمة النفق الرسغي|Carpal tunnel syndrome
insomnia|sleep|الأرق|Insomnia|sleep|قلة النوم
apnea|sleep|انقطاع النفس النومي|Sleep apnea|sleep
restless-legs|sleep|متلازمة تململ الساقين|Restless legs syndrome
depression|sleep|الاكتئاب|Depression|sleep,symptom
anxiety|sleep|اضطراب القلق العام|Generalized anxiety disorder|symptom
adhd|sleep|اضطراب فرط الحركة وتشتت الانتباه|ADHD
ocd|sleep|اضطراب الوسواس القهري|Obsessive-compulsive disorder||OCD
narcolepsy|sleep|النوم القهري|Narcolepsy|sleep
anemia|blood|فقر الدم|Anemia|symptom|انيميا
iron|blood|فقر الدم بنقص الحديد|Iron deficiency anemia|symptom|نقص الحديد
sickle|blood|فقر الدم المنجلي|Sickle cell disease
thalassemia|blood|الثلاسيميا|Thalassemia
hemophilia|blood|الناعور|Hemophilia
itp|blood|قلة الصفيحات المناعية|Immune thrombocytopenia
glaucoma|eye|الزرق|Glaucoma||المياه الزرقاء
cataract|eye|الساد|Cataract||المياه البيضاء
dry-eye|eye|جفاف العين|Dry eye disease|symptom
myopia|eye|قصر النظر|Myopia
hyperopia|eye|طول النظر|Hyperopia
diabetic-retinopathy|eye|اعتلال الشبكية السكري|Diabetic retinopathy
macular|eye|التنكس البقعي|Macular degeneration
endometriosis|reproductive|بطانة الرحم المهاجرة|Endometriosis|pain|الانتباذ البطاني الرحمي
fibroids|reproductive|الأورام الليفية بالرحم|Uterine fibroids|cycle
menopause|reproductive|مرحلة انقطاع الطمث|Menopause|sleep,mood|انقطاع الدورة,سن اليأس
postpartum|reproductive|متابعة ما بعد الولادة|Postpartum follow-up|mood,sleep|النفاس
infertility-followup|reproductive|متابعة تأخر الحمل|Fertility follow-up|cycle
sjogrens|immune|متلازمة شوغرن|Sjögren disease|symptom|جفاف الفم,شوغرن
immune-deficiency|immune|نقص المناعة الأولي|Primary immunodeficiency|symptom
vasculitis|immune|التهاب الأوعية الدموية|Vasculitis|symptom
post-transplant|immune|متابعة ما بعد زراعة الأعضاء|Post-transplant follow-up|lab
breast-cancer|oncology|متابعة سرطان الثدي|Breast cancer follow-up|pain
colorectal-cancer|oncology|متابعة سرطان القولون والمستقيم|Colorectal cancer follow-up|meal
prostate-cancer|oncology|متابعة سرطان البروستاتا|Prostate cancer follow-up
lymphoma|oncology|متابعة اللمفوما|Lymphoma follow-up||الورم اللمفاوي
recovery|oncology|المتابعة بعد علاج الأورام|Cancer survivorship follow-up|activity
''';
