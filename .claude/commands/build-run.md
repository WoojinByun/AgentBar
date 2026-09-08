AgentBar 앱을 빌드하고 다시 실행합니다.

1. 프로젝트를 빌드합니다.

```
xcodebuild build -project AgentBar.xcodeproj -scheme AgentBar -configuration Debug -derivedDataPath build -quiet
```

2. 빌드가 성공하면 기존 프로세스를 종료하고 새 빌드를 실행합니다.

```
pkill -x AgentBar; sleep 1; open build/Build/Products/Debug/AgentBar.app
```

3. 빌드 성공 여부를 보고합니다. 실패한 경우 오류 출력을 함께 보여줍니다.
