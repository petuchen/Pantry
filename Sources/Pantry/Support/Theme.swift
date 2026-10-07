import AppKit
import PantryCore
import SwiftUI

extension ModelService {
    /// Used for the usage bar and badges. Never the only signal: the service name and
    /// symbol always appear next to it.
    var tint: Color {
        switch self {
        case .ollama: return .indigo
        case .llamaCpp: return .orange
        case .mlx: return .teal
        case .huggingFace: return .pink
        }
    }
}

enum Spacing {
    static let page: CGFloat = 28
    static let section: CGFloat = 24
    static let card: CGFloat = 16
}

/// Service name + icon on a soft tinted pill. Text stays in the primary colour for contrast.
struct ServiceBadge: View {
    let service: ModelService

    var body: some View {
        Label {
            Text(service.displayName)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: service.symbolName)
                .foregroundStyle(service.tint)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(service.tint.opacity(0.14), in: Capsule())
        .fixedSize()
    }
}

struct CategoryLabel: View {
    let category: ModelCategory
    var short = true

    var body: some View {
        Label(short ? category.shortName : category.displayName, systemImage: category.symbolName)
            .labelStyle(.titleAndIcon)
    }
}

/// A grouped surface. One level of grouping only; cards are never nested.
struct Card<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.headline)
            }
            content
        }
        .padding(Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct UsageSegment: Identifiable {
    let id: String
    let label: String
    let color: Color
    let value: Double
}

/// Proportional bar. Segments are listed with names and sizes right below it, so the colours
/// are a reinforcement, not the only way to read it.
struct StackedUsageBar: View {
    let segments: [UsageSegment]

    var body: some View {
        let total = max(segments.reduce(0.0) { $0 + $1.value }, 1.0)
        GeometryReader { proxy in
            let gaps = CGFloat(max(segments.count - 1, 0)) * 2
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(segment.color)
                        .frame(width: max(4, (proxy.size.width - gaps) * CGFloat(segment.value / total)))
                }
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Storage by service")
        .accessibilityValue(segments.map { "\($0.label) \(Int(($0.value / total * 100).rounded())) percent" }.joined(separator: ", "))
    }
}

/// "12.3K" style compact numbers for download counts.
func compactNumber(_ value: Int) -> String {
    value.formatted(.number.notation(.compactName))
}

enum Finder {
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func openTrash() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
    }
}
