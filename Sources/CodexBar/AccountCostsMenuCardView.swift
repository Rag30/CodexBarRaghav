import CodexBarCore
import SwiftUI

/// Menu card showing plan/tier info for every connected Codex account.
struct AccountCostsMenuCardView: View {
    let entries: [AccountCostEntry]
    let isLoading: Bool
    let width: CGFloat

    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Accounts")
                    .font(.headline)
                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()
                .padding(.horizontal, 16)

            if self.isLoading && self.entries.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading…")
                        .font(.footnote)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else if self.entries.isEmpty {
                Text("No accounts connected.")
                    .font(.footnote)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(self.entries) { entry in
                        AccountCostRow(entry: entry, isHighlighted: self.isHighlighted)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
        }
        .frame(width: self.width, alignment: .leading)
    }
}

private struct AccountCostRow: View {
    let entry: AccountCostEntry
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: self.entry.isDefault ? "person.circle.fill" : "person.circle")
                .imageScale(.small)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))

            Text(self.entry.label)
                .font(.footnote)
                .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            self.trailingContent
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        if let error = self.entry.error {
            Text(self.shortError(error))
                .font(.footnote)
                .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
                .lineLimit(1)
        } else if self.entry.isUnlimited {
            self.planBadge("Unlimited")
        } else if let balance = self.entry.creditsRemaining {
            // Prepaid credits — the one case where a dollar amount is meaningful.
            HStack(spacing: 4) {
                if let plan = self.entry.planType { self.planBadge(plan) }
                Text(UsageFormatter.usdString(balance) + " left")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(balance < 5 ? Color.orange : MenuHighlightStyle.primary(self.isHighlighted))
            }
        } else if let plan = self.entry.planType {
            self.planBadge(plan)
        } else {
            Text("—")
                .font(.footnote)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        }
    }

    private func planBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(MenuHighlightStyle.secondary(self.isHighlighted).opacity(0.12)))
    }

    private func shortError(_ error: String) -> String {
        if error.contains("not found") || error.contains("notFound") { return "Not signed in" }
        if error.contains("unauthorized") || error.contains("401") { return "Token expired" }
        return "Error"
    }
}
