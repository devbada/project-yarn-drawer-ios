import SwiftUI
import UniformTypeIdentifiers

struct PatternImportView: View {
    @EnvironmentObject private var store: PatternStore
    @Environment(\.dismiss) private var dismiss
    @State private var isFileImporterPresented = false
    @State private var selectedURL: URL?
    @State private var title = ""
    @State private var designerName = ""
    @State private var craftType: CraftType = .knitting
    @State private var tagsText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: YDSpacing.x4) {
                    fileSelection

                    if let selectedURL {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedURL.lastPathComponent)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(YDColor.yarn4)
                                Text(filePolicyDescription)
                                    .font(.system(size: 12))
                                    .foregroundStyle(YDColor.muted)
                            }
                            Spacer()
                            YDIconView(icon: .check, size: 20)
                                .foregroundStyle(YDColor.yarn4)
                        }
                        .padding(14)
                        .background(YDColor.surfaceGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(spacing: YDSpacing.x3) {
                        field(title: "도안명") {
                            TextField("필수", text: $title)
                                .textInputAutocapitalization(.never)
                        }
                        field(title: "작가명") {
                            TextField("선택", text: $designerName)
                                .textInputAutocapitalization(.never)
                        }
                        field(title: "종류") {
                            Picker("종류", selection: $craftType) {
                                ForEach(CraftType.allCases) { type in
                                    Text(type.title).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        field(title: "태그") {
                            TextField("레이스, 여름, 코튼", text: $tagsText)
                                .textInputAutocapitalization(.never)
                        }
                    }

                    if let message = store.importErrorMessage {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(YDColor.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(YDColor.danger.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    HStack(spacing: 9) {
                        Button("취소") {
                            dismiss()
                        }
                        .buttonStyle(YDSecondaryButtonStyle())

                        Button {
                            register()
                        } label: {
                            if store.isImporting {
                                ProgressView()
                                    .tint(YDColor.cream0)
                                    .accessibilityLabel("도안 변환 및 저장 중")
                            } else {
                                Text("등록 후 열기")
                            }
                        }
                        .buttonStyle(YDPrimaryButtonStyle())
                        .disabled(selectedURL == nil || store.isImporting)
                        .opacity(selectedURL == nil ? 0.48 : 1)
                    }
                }
                .padding(YDSpacing.x4)
            }
            .background(YDColor.cream0)
            .navigationTitle("도안 등록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                    .foregroundStyle(YDColor.ink)
                }
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.pdf, .jpeg, .png],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                selectedURL = url
                if title.isEmpty {
                    title = url.deletingPathExtension().lastPathComponent
                }
                store.importErrorMessage = nil
            case .failure:
                store.importErrorMessage = "파일을 선택하지 못했습니다. 다시 시도해 주세요."
            }
        }
    }

    private var fileSelection: some View {
        Button {
            isFileImporterPresented = true
        } label: {
            VStack(spacing: YDSpacing.x2) {
                YDIconView(icon: .upload, size: 34)
                    .foregroundStyle(YDColor.wood3)
                Text("PDF, JPG, JPEG, PNG 선택")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(YDColor.ink)
                Text("이미지는 비율과 방향을 유지한 작업용 PDF로 변환합니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(YDColor.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 150)
            .padding(20)
            .background(YDColor.cream2)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(YDColor.wood2, style: StrokeStyle(lineWidth: 2, dash: [7]))
            }
        }
        .buttonStyle(.plain)
    }

    private func field<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(YDColor.muted)
            content()
                .padding(.horizontal, YDSpacing.x3)
                .frame(minHeight: 46)
                .background(YDColor.cream0)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(YDColor.line, lineWidth: 1)
                }
        }
    }

    private var filePolicyDescription: String {
        guard let selectedURL else { return "" }
        if selectedURL.pathExtension.localizedLowercase == "pdf" {
            return "원본 PDF를 보존하고 작업용 문서로 연결합니다."
        }
        return "원본 이미지와 변환 PDF를 별도 파일로 저장합니다."
    }

    private func register() {
        guard let selectedURL else { return }
        let draft = PatternImportDraft(
            sourceURL: selectedURL,
            title: title,
            designerName: designerName,
            craftType: craftType,
            tagsText: tagsText
        )
        Task {
            if await store.importPattern(draft) {
                dismiss()
            }
        }
    }
}

