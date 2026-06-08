import SwiftUI

struct StatusItemLabelView: View {
    nonisolated static let defaultFallbackText = "AIPace"

    let claudeText: String?
    let codexText: String?
    let claudeStyle: StatusPillStyle
    let codexStyle: StatusPillStyle
    let fallbackStyle: StatusPillStyle

    var body: some View {
        let visibleClaudeText = Self.visibleText(claudeText)
        let visibleCodexText = Self.visibleText(codexText)

        VStack(alignment: .leading, spacing: 1) {
            if let claudeText = visibleClaudeText {
                pill(text: claudeText, style: claudeStyle)
            }
            if let codexText = visibleCodexText {
                pill(text: codexText, style: codexStyle)
            }
            if let fallbackText = Self.resolvedFallbackText(
                claudeText: visibleClaudeText,
                codexText: visibleCodexText
            ) {
                pill(text: fallbackText, style: fallbackStyle)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
        .allowsHitTesting(false)
    }

    nonisolated static func resolvedFallbackText(claudeText: String?, codexText: String?) -> String? {
        guard visibleText(claudeText) == nil, visibleText(codexText) == nil else {
            return nil
        }
        return defaultFallbackText
    }

    private nonisolated static func visibleText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func pill(text: String, style: StatusPillStyle) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(style.foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 0.5)
            .background(
                Capsule(style: .continuous)
                    .fill(style.background)
            )
    }
}
