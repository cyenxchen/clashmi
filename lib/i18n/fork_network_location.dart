import 'package:flutter/widgets.dart';

// Fork-only copy keeps the upstream generated translation files untouched.
class ForkNetworkLocationText {
  final List<String> _values;
  const ForkNetworkLocationText._(this._values);
  String get title => _values[0];
  String get description => _values[1];
  String get foreground => _values[2];
  String get background => _values[3];
  String get granted => _values[4];
  String get denied => _values[5];
  String get requestForeground => _values[6];
  String get requestBackground => _values[7];
  String get settings => _values[8];
  String get backgroundHelp => _values[9];
  String get error => _values[10];
  String get foregroundDeniedHelp => _values[11];

  static ForkNetworkLocationText of(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final key = locale.languageCode == 'zh'
        ? (locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
              ? 'zh-TW'
              : 'zh-CN')
        : locale.languageCode;
    return ForkNetworkLocationText._(_copy[key] ?? _copy['en']!);
  }
}

const _copy = <String, List<String>>{
  'en': [
    'Network identification',
    'Location access lets Android provide the Wi-Fi name for automatic network selection. If you decline, the VPN keeps working using other network information.',
    'Foreground location',
    'Background location',
    'Allowed',
    'Not allowed',
    'Allow foreground location',
    'Allow background location',
    'Open app settings',
    'Grant foreground location first. Then, in Android location permissions, choose Allow all the time. Location services must also be enabled to read Wi-Fi names.',
    'Unable to read or update permission. Try app settings.',
    'If Android no longer shows a permission prompt, enable location in app settings.',
  ],
  'zh-CN': [
    '网络识别权限',
    '定位授权可让 Android 提供 Wi-Fi 名称，用于自动选择网络策略。拒绝后 VPN 仍可使用，网络识别会使用其他信息。',
    '前台定位',
    '后台定位',
    '已允许',
    '未允许',
    '申请前台定位',
    '申请后台定位',
    '打开应用设置',
    '先允许前台定位，再到 Android 定位权限中选择“始终允许”。读取 Wi-Fi 名称还需要开启系统定位服务。',
    '无法读取或更新权限，请尝试打开应用设置。',
    '若系统不再弹出授权提示，请到应用设置开启定位。',
  ],
  'zh-TW': [
    '網路識別權限',
    '定位授權可讓 Android 提供 Wi-Fi 名稱，用於自動選擇網路策略。拒絕後 VPN 仍可使用，網路識別會使用其他資訊。',
    '前景定位',
    '背景定位',
    '已允許',
    '未允許',
    '申請前景定位',
    '申請背景定位',
    '開啟應用程式設定',
    '先允許前景定位，再到 Android 定位權限中選擇「一律允許」。讀取 Wi-Fi 名稱還需要開啟系統定位服務。',
    '無法讀取或更新權限，請嘗試開啟應用程式設定。',
    '若系統不再顯示授權提示，請到應用程式設定開啟定位。',
  ],
  'ja': [
    'ネットワーク識別の権限',
    '位置情報を許可すると、Android が Wi-Fi 名を提供し、ネットワーク設定を自動選択できます。拒否しても、他のネットワーク情報を使って VPN を利用できます。',
    '使用中の位置情報',
    'バックグラウンドの位置情報',
    '許可済み',
    '未許可',
    '使用中の位置情報を許可',
    'バックグラウンドの位置情報を許可',
    'アプリの設定を開く',
    'まず使用中の位置情報を許可し、次に Android の位置情報の権限で「常に許可」を選んでください。Wi-Fi 名の取得には端末の位置情報も有効にする必要があります。',
    '権限を確認または更新できません。アプリの設定を開いてください。',
    'Android に権限の確認が表示されない場合は、アプリの設定で位置情報を許可してください。',
  ],
  'ko': [
    '네트워크 식별 권한',
    '위치 접근을 허용하면 Android에서 Wi-Fi 이름을 제공하여 네트워크 정책을 자동으로 선택할 수 있습니다. 거부해도 다른 네트워크 정보를 사용하여 VPN을 계속 이용할 수 있습니다.',
    '사용 중 위치',
    '백그라운드 위치',
    '허용됨',
    '허용되지 않음',
    '사용 중 위치 허용',
    '백그라운드 위치 허용',
    '앱 설정 열기',
    '먼저 사용 중 위치를 허용한 뒤 Android 위치 권한에서 항상 허용을 선택하세요. Wi-Fi 이름을 읽으려면 기기의 위치 서비스도 켜야 합니다.',
    '권한을 확인하거나 변경할 수 없습니다. 앱 설정을 열어 주세요.',
    'Android에서 권한 요청이 더 이상 표시되지 않으면 앱 설정에서 위치 권한을 허용하세요.',
  ],
  'es': [
    'Identificación de red',
    'El acceso a la ubicación permite que Android proporcione el nombre de Wi-Fi para seleccionar la política de red. Si lo rechazas, la VPN seguirá funcionando con otros datos de red.',
    'Ubicación en primer plano',
    'Ubicación en segundo plano',
    'Permitida',
    'No permitida',
    'Permitir ubicación en primer plano',
    'Permitir ubicación en segundo plano',
    'Abrir ajustes de la aplicación',
    'Primero permite la ubicación en primer plano. Después elige Permitir siempre en los permisos de ubicación de Android. Activa también los servicios de ubicación para obtener el nombre de Wi-Fi.',
    'No se pudo consultar o cambiar el permiso. Prueba los ajustes de la aplicación.',
    'Si Android ya no muestra la solicitud de permiso, activa la ubicación en los ajustes de la aplicación.',
  ],
  'ru': [
    'Определение сети',
    'Доступ к местоположению позволяет Android передавать имя Wi-Fi для автоматического выбора сетевой политики. При отказе VPN продолжит работать, используя другие сведения о сети.',
    'Местоположение при использовании',
    'Местоположение в фоне',
    'Разрешено',
    'Не разрешено',
    'Разрешить при использовании',
    'Разрешить в фоне',
    'Открыть настройки приложения',
    'Сначала разрешите доступ при использовании. Затем выберите «Разрешать всегда» в разрешениях Android. Для получения имени Wi-Fi также включите службы геолокации.',
    'Не удалось получить или изменить разрешение. Откройте настройки приложения.',
    'Если Android больше не показывает запрос разрешения, включите доступ к местоположению в настройках приложения.',
  ],
  'ar': [
    'التعرّف على الشبكة',
    'يسمح إذن الموقع لنظام Android بتوفير اسم Wi-Fi لاختيار سياسة الشبكة تلقائيًا. إذا رفضت، تستمر شبكة VPN بالعمل باستخدام معلومات الشبكة الأخرى.',
    'الموقع أثناء الاستخدام',
    'الموقع في الخلفية',
    'مسموح',
    'غير مسموح',
    'السماح بالموقع أثناء الاستخدام',
    'السماح بالموقع في الخلفية',
    'فتح إعدادات التطبيق',
    'اسمح أولًا بالموقع أثناء الاستخدام، ثم اختر السماح طوال الوقت في أذونات الموقع في Android. يجب أيضًا تشغيل خدمات الموقع لقراءة اسم Wi-Fi.',
    'تعذّر قراءة الإذن أو تحديثه. جرّب إعدادات التطبيق.',
    'إذا لم يعد Android يعرض طلب الإذن، فعّل الموقع من إعدادات التطبيق.',
  ],
  'fa': [
    'شناسایی شبکه',
    'مجوز مکان به Android اجازه می‌دهد نام Wi-Fi را برای انتخاب خودکار سیاست شبکه ارائه کند. در صورت رد کردن، VPN با استفاده از سایر اطلاعات شبکه همچنان کار می‌کند.',
    'مکان هنگام استفاده',
    'مکان در پس‌زمینه',
    'مجاز',
    'غیرمجاز',
    'اجازهٔ مکان هنگام استفاده',
    'اجازهٔ مکان در پس‌زمینه',
    'باز کردن تنظیمات برنامه',
    'ابتدا مکان هنگام استفاده را مجاز کنید. سپس در مجوزهای مکان Android گزینهٔ همیشه مجاز را انتخاب کنید. برای خواندن نام Wi-Fi، خدمات مکان دستگاه نیز باید روشن باشد.',
    'خواندن یا تغییر مجوز ممکن نشد. تنظیمات برنامه را باز کنید.',
    'اگر Android دیگر درخواست مجوز را نشان نمی‌دهد، دسترسی به مکان را در تنظیمات برنامه فعال کنید.',
  ],
};
