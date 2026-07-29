# AI 학습 스케줄러

책의 목차 사진 또는 직접 입력한 장·절 목록을 바탕으로, 마감일과 학습 습관에 맞는 일별 학습 계획을 만드는 Flutter + FastAPI 앱입니다.

## 구성

- `app/`: Android/iOS Flutter 클라이언트. OpenAI 키를 포함하지 않습니다.
- `backend/`: 목차 추출과 일정 생성을 위해 OpenAI Responses API를 호출하는 FastAPI 서버.

## 실행

### 1. 백엔드

```powershell
Copy-Item backend/.env.example backend/.env
# backend/.env의 OPENAI_API_KEY를 실제 키로 교체
python -m venv backend/.venv
backend/.venv/Scripts/Activate.ps1
pip install -r backend/requirements.txt
uvicorn app.main:app --app-dir backend --reload --port 8000
```

### 2. Flutter 앱

Flutter SDK를 설치한 뒤 다음을 실행합니다.

```powershell
cd app
flutter create --platforms=android,ios .
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Android 에뮬레이터는 `10.0.2.2`, 실제 기기는 개발 PC의 LAN IP를 `API_BASE_URL`로 사용합니다. iOS 시뮬레이터에서는 `http://127.0.0.1:8000`을 사용할 수 있습니다.
카메라·사진 및 개발 HTTP 설정은 [모바일 권한 설정](app/PLATFORM_SETUP.md)을 적용하세요.

## 보안

실제 API 키는 `backend/.env`에만 저장합니다. `.env`는 Git에서 제외되어 있고, Flutter 빌드나 앱 저장소에 키를 넣지 않습니다.
