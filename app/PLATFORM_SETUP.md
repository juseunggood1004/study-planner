# 모바일 권한 설정

`flutter create --platforms=android,ios .`를 한 번 실행한 뒤 다음 설정을 확인하세요.

## iOS

`ios/Runner/Info.plist`의 `<dict>` 안에 추가합니다.

```xml
<key>NSCameraUsageDescription</key>
<string>책 목차를 촬영하여 학습 계획을 만들기 위해 카메라를 사용합니다.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>책 목차 사진을 선택하여 학습 계획을 만들기 위해 사진 보관함에 접근합니다.</string>
```

## Android

`android/app/src/main/AndroidManifest.xml`에 네트워크 권한이 있는지 확인합니다.

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

개발 서버가 HTTP라면 Android 9 이상에서 개발 빌드에 `android:usesCleartextTraffic="true"`를 설정해야 할 수 있습니다. 배포 환경에서는 HTTPS 백엔드 주소를 사용하세요.
