import SwiftUI
import UniformTypeIdentifiers

struct PatternImportView: View {
    @EnvironmentObject private var store: PatternStore
    @Environment(\.dismiss) private var dismiss
    @State private var isDocumentPickerPresented = false
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
        .sheet(isPresented: $isDocumentPickerPresented) {
            PatternDocumentPicker(
                allowedContentTypes: [.pdf, .jpeg, .png],
                onPick: selectFile,
                onFailure: {
                    store.importErrorMessage = "파일을 선택하지 못했습니다. iCloud Drive 또는 파일 앱에서 다시 선택해 주세요."
                }
            )
        }
    }

    private var fileSelection: some View {
        Button {
            isDocumentPickerPresented = true
        } label: {
            VStack(spacing: YDSpacing.x2) {
                YDIconView(icon: .upload, size: 34)
                    .foregroundStyle(YDColor.wood3)
                Text("PDF, JPG, JPEG, PNG 선택")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(YDColor.ink)
                Text("iCloud Drive, 나의 iPhone, 파일 앱 위치에서 선택할 수 있습니다.")
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

    private func selectFile(_ url: URL) {
        selectedURL = url
        if title.isEmpty {
            title = url.deletingPathExtension().lastPathComponent
        }
        store.importErrorMessage = nil
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

private struct PatternDocumentPicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let onPick: (URL) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPick: onPick,
            onFailure: onFailure
        )
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: allowedContentTypes,
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void
        private let onFailure: () -> Void

        init(
            onPick: @escaping (URL) -> Void,
            onFailure: @escaping () -> Void
        ) {
            self.onPick = onPick
            self.onFailure = onFailure
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else {
                onFailure()
                return
            }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
