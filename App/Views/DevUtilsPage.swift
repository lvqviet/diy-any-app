import AppKit
import DevCore
import SwiftUI

/// Main window page: text conversions (JSON, Base64, URL, JWT, timestamps, hashes, UUIDs).
/// Output updates as you type.
struct DevUtilsPage: View {
    @AppStorage("devUtils.tool") private var tool: DevTool = .json
    @State private var inputs: [DevTool: String] = [:]
    @State private var modes: [DevTool: Int] = [:]
    /// Bumped by "Generate" so UUID output is recomputed.
    @State private var generation = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Tool", selection: $tool) {
                    ForEach(DevTool.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                if !tool.modes.isEmpty {
                    Picker("Mode", selection: mode) {
                        ForEach(tool.modes.indices, id: \.self) { Text(tool.modes[$0]).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            if tool != .uuid {
                Text("Input").font(.subheadline.weight(.medium))
                TextEditor(text: input)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                    .overlay(alignment: .topLeading) {
                        if input.wrappedValue.isEmpty {
                            Text(placeholder)
                                .font(.body.monospaced())
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 80, maxHeight: .infinity)
            }

            let result = output
            HStack {
                Text("Output").font(.subheadline.weight(.medium))
                Spacer()
                if tool == .uuid {
                    Button("Generate") { generation += 1 }
                }
                if tool.modes.count == 2, tool != .json, case .success(let text) = result, !text.isEmpty {
                    Button("Use as Input") {
                        inputs[tool] = text
                        modes[tool] = 1 - mode.wrappedValue
                    }
                    .help("Move the output to the input and switch direction")
                }
                Button("Copy") { PortActions.copy(resultText(result)) }
                    .disabled(resultText(result).isEmpty)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            ScrollView {
                Group {
                    switch result {
                    case .success(let text):
                        Text(text.isEmpty ? " " : text)
                    case .failure(let error):
                        Text(error.localizedDescription).foregroundStyle(.red)
                    }
                }
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(8)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .frame(minHeight: 80, maxHeight: .infinity)
        }
        .padding(20)
        .navigationTitle("Dev Utils")
    }

    private var input: Binding<String> {
        Binding(get: { inputs[tool] ?? "" }, set: { inputs[tool] = $0 })
    }

    private var mode: Binding<Int> {
        Binding(get: { modes[tool] ?? 0 }, set: { modes[tool] = $0 })
    }

    private var output: Result<String, Error> {
        _ = generation
        return Result { try tool.run(inputs[tool] ?? "", mode: modes[tool] ?? 0) }
    }

    private func resultText(_ result: Result<String, Error>) -> String {
        (try? result.get()) ?? ""
    }

    private var placeholder: String {
        switch tool {
        case .json: return #"{"paste": "JSON here"}"#
        case .base64: return mode.wrappedValue == 0 ? "Text to encode" : "Base64 to decode"
        case .url: return mode.wrappedValue == 0 ? "Text to percent-encode" : "Percent-encoded text"
        case .jwt: return "eyJhbGciOi…"
        case .timestamp: return "1700000000, 1700000000000 or 2023-11-14T22:13:20Z (empty shows now)"
        case .hash: return "Text to hash (UTF-8)"
        case .uuid: return ""
        }
    }
}
