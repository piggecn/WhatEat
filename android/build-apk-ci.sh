#!/usr/bin/env bash
# GitHub Actions (ubuntu) 上的 APK 构建：与本地 build-apk.sh 同一套工具链，
# 区别是版本号由环境变量注入（跟随发布 tag），签名密钥来自 GitHub Secrets。
set -e
cd "$(dirname "$0")"

SDK=${ANDROID_SDK_ROOT:-$ANDROID_HOME}
BT=$SDK/build-tools/36.0.0
PLATFORM=$SDK/platforms/android-34/android.jar
ZXING=$PWD/libs/core-3.5.3.jar
VERSION_NAME=${VERSION_NAME:-0.0.4}
VERSION_CODE=${VERSION_CODE:-1}

# 把发布版本写入源码与清单，保证壳内更新检测（CURRENT_VERSION_NAME）与本次发布一致
sed -i "s/CURRENT_VERSION_NAME = \"[^\"]*\"/CURRENT_VERSION_NAME = \"$VERSION_NAME\"/" \
  app/src/main/java/com/piggecn/whateat/MainActivity.java
sed -i "s/android:versionName=\"[^\"]*\"/android:versionName=\"$VERSION_NAME\"/" \
  app/src/main/AndroidManifest.xml
sed -i "s/android:versionCode=\"[0-9]*\"/android:versionCode=\"$VERSION_CODE\"/" \
  app/src/main/AndroidManifest.xml

echo "[1/6] 编译资源"
rm -rf build && mkdir -p build/classes
"$BT/aapt2" compile --dir app/src/main/res -o build/compiled.zip
"$BT/aapt2" link -o build/base.apk -I "$PLATFORM" \
  --min-sdk-version 24 --target-sdk-version 34 \
  --version-code "$VERSION_CODE" --version-name "$VERSION_NAME" \
  --manifest app/src/main/AndroidManifest.xml build/compiled.zip

echo "[2/6] 编译 Java"
find app/src/main/java -name '*.java' > build/sources.txt
javac -encoding UTF-8 -source 1.8 -target 1.8 -nowarn \
  -classpath "$PLATFORM:$ZXING" -d build/classes @build/sources.txt

echo "[3/6] dex"
java -cp "$BT/lib/d8.jar" com.android.tools.r8.D8 --min-api 24 \
  --lib "$PLATFORM" --output build \
  $(find build/classes -name '*.class') "$ZXING"

echo "[4/6] 打包 dex"
( cd build && jar -uf base.apk classes.dex )

echo "[5/6] 签名"
echo "$KEYSTORE_B64" | base64 -d > build/ci.keystore
"$BT/zipalign" -f 4 build/base.apk build/aligned.apk
java -jar "$BT/lib/apksigner.jar" sign \
  --ks build/ci.keystore --ks-pass pass:"$KEYSTORE_PASS" --key-pass pass:"$KEYSTORE_PASS" \
  --out whateat.apk build/aligned.apk
rm -f build/ci.keystore

echo "[6/6] 验证"
java -jar "$BT/lib/apksigner.jar" verify --print-certs whateat.apk | head -3
echo "CI 构建完成: $PWD/whateat.apk"
