#!/usr/bin/env bash
# Run once after `flutter create --org com.spider --project-name spider_mind --platforms=android,ios .`
# Patches the generated Android project for reminders. Safe to run again.
set -euo pipefail
cd "$(dirname "$0")/.."
MANIFEST=android/app/src/main/AndroidManifest.xml
[ -f "$MANIFEST" ] || { echo "Run 'flutter create' first (no $MANIFEST)"; exit 1; }
python3 - "$MANIFEST" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
perms = ['android.permission.INTERNET', 'android.permission.POST_NOTIFICATIONS', 'android.permission.SCHEDULE_EXACT_ALARM',
         'android.permission.RECEIVE_BOOT_COMPLETED', 'android.permission.VIBRATE', 'android.permission.WAKE_LOCK']
for perm in perms:
    if perm not in s:
        s = s.replace('<application', f'<uses-permission android:name="{perm}"/>\n    <application', 1)
if 'usesCleartextTraffic' not in s:
    s = s.replace('<application', '<application\n        android:usesCleartextTraffic="true"', 1)  # dev http; remove for production HTTPS-only builds
if 'ScheduledNotificationReceiver' not in s:
    recv = '''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
'''
    s = s.replace('</application>', recv + '    </application>', 1)
open(p, 'w').write(s)
PY
# flutter_local_notifications needs core library desugaring and minSdk 21+.
for G in android/app/build.gradle android/app/build.gradle.kts; do
  [ -f "$G" ] || continue
  python3 - "$G" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read(); kts = p.endswith('.kts')
if 'isCoreLibraryDesugaringEnabled' not in s and 'coreLibraryDesugaringEnabled' not in s:
    flag = 'isCoreLibraryDesugaringEnabled = true' if kts else 'coreLibraryDesugaringEnabled true'
    s = re.sub(r'(compileOptions\s*\{)', r'\1\n        ' + flag, s, 1)
if 'desugar_jdk_libs' not in s:
    dep = 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")' if kts else "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4'"
    if re.search(r'^dependencies\s*\{', s, re.M):
        s = re.sub(r'^(dependencies\s*\{)', r'\1\n    ' + dep, s, 1, flags=re.M)
    else:
        s += '\ndependencies {\n    ' + dep + '\n}\n'
s = re.sub(r'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion', 'minSdk = 23' if kts else 'minSdkVersion 23', s)
open(p, 'w').write(s)
PY
done
echo "Android configured. Build: flutter build apk --release --dart-define=API_URL=https://your-api"
