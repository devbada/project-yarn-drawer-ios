# 뜨개서랍 iOS

SwiftUI 기반 iPhone/iPad MVP 프로젝트다.

## 실행

1. `YarnDrawer.xcodeproj`를 Xcode에서 연다.
2. `YarnDrawer` scheme과 iPhone 또는 iPad Simulator를 선택한다.
3. 실행한다.

`Supported Destinations`, `Development Team`, 서명 설정은 Xcode 프로젝트에서 관리한다. 설정 보존을 위해 `xcodegen`으로 프로젝트를 다시 생성하지 않는다.

앱 데이터 컨테이너 보존을 위해 Bundle Identifier는 `com.minam.YarnDrawer`로 유지한다. Bundle Identifier 변경 시 기존 설치 데이터에 접근할 수 없다.

## 형광펜 사용

1. 등록한 PDF 또는 이미지 변환 도안을 연다.
2. 하단 `형광펜`을 선택한다.
3. 기본 팔레트 또는 사용자 색상 선택기에서 색상을 고른다.
4. 자주 쓰는 사용자 색상은 `+ 즐겨찾기`로 저장한다.
5. PDF 위를 손가락 또는 Apple Pencil로 그린다.
6. PDF 이동은 두 손가락 드래그, 확대·축소는 핀치를 사용한다.

표시는 작업용 PDF 좌표로 자동 저장되며 앱을 다시 열어도 복원된다. 원본 파일은 변경하지 않는다.

## 구현 상태

상세 상태와 미구현 목록은 `../docs/10_implementation_status.md`를 기준으로 한다.

- [x] iPhone 하단 탭, iPad 사이드바
- [x] 보관함 검색·필터·즐겨찾기
- [x] PDF/JPG/JPEG/PNG 등록과 이미지 PDF 변환
- [x] 원본 파일 보호와 로컬 메타데이터 저장·백업
- [x] PDFKit 뷰어와 원본 보기
- [x] 자유 곡선 형광펜, 커스텀 팔레트, 즐겨찾기, 자동 저장·복원
- [x] 체크와 현재 줄 생성·저장·복원
- [x] 마지막 페이지 저장·복원
- [x] 게이지 계산기
- [x] 도안 상세정보·게이지·실 정보 저장
- [x] 도안 수정·삭제와 파일 재연결
- [ ] 실제 PDF annotation 또는 편집본 내보내기
- [ ] 사용자 기호 등록·편집
- [ ] 게이지 계산기 단 수/실제 길이 계산
- [ ] 로컬 백업 내보내기·가져오기
