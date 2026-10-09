"""在 `flutter create` 生成平台目录之后运行，写入本应用需要的原生配置。

用法: python tool/patch_platforms.py android|windows
"""
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PKG = "com.shen.jinrishi"


def must_replace(text: str, old: str, new: str, what: str) -> str:
    if old not in text:
        sys.exit(f"[patch] 找不到要修改的位置：{what}")
    return text.replace(old, new, 1)


def patch_android() -> None:
    app = ROOT / "android" / "app"
    src = ROOT / "platform" / "android"

    # 1. 原生文件
    kdir = app / "src" / "main" / "kotlin" / PKG.replace(".", "/")
    kdir.mkdir(parents=True, exist_ok=True)
    shutil.copy(src / "kotlin" / "TodayWidgetProvider.kt", kdir / "TodayWidgetProvider.kt")
    for sub in ("layout", "xml", "drawable"):
        dst = app / "src" / "main" / "res" / sub
        dst.mkdir(parents=True, exist_ok=True)
        for f in (src / "res" / sub).iterdir():
            shutil.copy(f, dst / f.name)
    shutil.copy(src / "proguard-rules.pro", app / "proguard-rules.pro")
    # 固定签名，保证每次打出的新版本都能直接覆盖安装
    if (src / "release.jks").exists():
        shutil.copy(src / "release.jks", app / "release.jks")

    # 2. AndroidManifest.xml
    mf = app / "src" / "main" / "AndroidManifest.xml"
    m = mf.read_text(encoding="utf-8")
    perms = "\n".join(
        f'    <uses-permission android:name="{p}" />'
        for p in [
            "android.permission.INTERNET",
            "android.permission.POST_NOTIFICATIONS",
            "android.permission.SCHEDULE_EXACT_ALARM",
            "android.permission.RECEIVE_BOOT_COMPLETED",
            "android.permission.VIBRATE",
            "android.permission.WAKE_LOCK",
            "android.permission.USE_FULL_SCREEN_INTENT",
            "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
        ]
    )
    m = re.sub(r"(<manifest[^>]*>)", r"\1\n" + perms.replace("\\", "\\\\"), m, count=1)
    m = re.sub(r'android:label="[^"]*"', 'android:label="今日事"', m, count=1)
    # 锁屏时允许全屏弹出提醒
    m = must_replace(
        m,
        'android:name=".MainActivity"',
        'android:name=".MainActivity"\n            android:showWhenLocked="true"\n            android:turnScreenOn="true"',
        "MainActivity",
    )
    receivers = """
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
        <receiver android:name=".TodayWidgetProvider" android:exported="true">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/today_widget_info" />
        </receiver>
    </application>"""
    m = must_replace(m, "</application>", receivers, "</application>")
    mf.write_text(m, encoding="utf-8")

    # 3. build.gradle(.kts)：脱糖、混淆规则、固定签名
    kts = app / "build.gradle.kts"
    if kts.exists():
        g = kts.read_text(encoding="utf-8")
        g = must_replace(
            g,
            "compileOptions {",
            "compileOptions {\n        isCoreLibraryDesugaringEnabled = true",
            "compileOptions",
        )
        g = re.sub(r"minSdk = [^\n]+", "minSdk = 23", g, count=1)
        signing = """
    signingConfigs {
        create("release") {
            val ks = file("release.jks")
            if (ks.exists()) {
                storeFile = ks
                storePassword = System.getenv("JRS_KEY_PASSWORD") ?: "jinrishi"
                keyAlias = "jinrishi"
                keyPassword = System.getenv("JRS_KEY_PASSWORD") ?: "jinrishi"
            }
        }
    }

    buildTypes {"""
        g = must_replace(g, "\n    buildTypes {", signing, "buildTypes")
        g = must_replace(
            g,
            'signingConfig = signingConfigs.getByName("debug")',
            'signingConfig = if (file("release.jks").exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")\n'
            '            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")',
            "release signingConfig",
        )
        if "dependencies {" in g:
            g = g.replace(
                "dependencies {",
                'dependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")',
                1,
            )
        else:
            g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
        kts.write_text(g, encoding="utf-8")
    else:
        sys.exit("[patch] 只支持 build.gradle.kts（Flutter 3.29 及以上）")

    print("[patch] android ok")


def patch_windows() -> None:
    fw = ROOT / "windows" / "runner" / "flutter_window.cpp"
    t = fw.read_text(encoding="utf-8")
    # 由 Dart 端决定是否显示窗口（开机自启时只进托盘）
    t = must_replace(t, "this->Show();", "// this->Show();  // 由 window_manager 控制", "Show()")
    fw.write_text(t, encoding="utf-8")

    main = ROOT / "windows" / "runner" / "main.cpp"
    t = main.read_text(encoding="utf-8")
    t = re.sub(r'window\.Create\(L"[^"]*"', 'window.Create(L"\\\\u4ECA\\\\u65E5\\\\u4E8B"', t, count=1)
    main.write_text(t, encoding="utf-8")

    rc = ROOT / "windows" / "runner" / "Runner.rc"
    t = rc.read_text(encoding="utf-8")
    t = re.sub(r'VALUE "ProductName", "[^"]*"', 'VALUE "ProductName", "jinrishi"', t)
    t = re.sub(r'VALUE "FileDescription", "[^"]*"', 'VALUE "FileDescription", "Jinrishi Reminder"', t)
    rc.write_text(t, encoding="utf-8")
    print("[patch] windows ok")


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else ""
    if target == "android":
        patch_android()
    elif target == "windows":
        patch_windows()
    else:
        sys.exit("usage: patch_platforms.py android|windows")
