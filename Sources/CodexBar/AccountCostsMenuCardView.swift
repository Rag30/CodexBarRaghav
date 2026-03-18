import CodexBarCore
import SwiftUI

/// Menu card showing plan/tier info for every connected Codex account.
struct AccountCostsMenuCardView: View {
    let entries: [AccountCostEntry]
    let isLoading: Bool
    let width: CGFloat

    @Environment(\.menuItemHighlighted) private var isHighlighted

    static let colWidth: CGFloat = 68

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Accounts")
                    .font(.headline)
                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                Spacer()
                Text("Session")
                    .font(.caption2)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .frame(width: Self.colWidth, alignment: .trailing)
                Text("Weekly")
                    .font(.caption2)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .frame(width: Self.colWidth, alignment: .trailing)
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

    private static let colWidth: CGFloat = AccountCostsMenuCardView.colWidth

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // Left: icon + name + plan badge
            Image(systemName: self.entry.isDefault ? "person.circle.fill" : "person.circle")
                .imageScale(.small)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))

            Text(self.entry.label)
                .font(.footnote)
                .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                .lineLimit(1)
                .truncationMode(.middle)

            if self.entry.error == nil {
                if self.entry.isUnlimited {
                    self.planBadge("Unlimited")
                } else if let plan = self.entry.planType {
                    self.planBadge(plan)
                }
            }

            Spacer(minLength: 4)

            // Right columns: Session | Weekly
            if let error = self.entry.error {
                Text(self.shortError(error))
                    .font(.caption2)
                    .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
                    .frame(width: Self.colWidth * 2 + 8, alignment: .trailing)
            } else if let balance = self.entry.creditsRemaining {
                // Prepaid credits: span both columns
                Text(UsageFormatter.usdString(balance) + " left")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(balance < 5 ? Color.orange : MenuHighlightStyle.secondary(self.isHighlighted))
                    .frame(width: Self.colWidth * 2 + 8, alignment: .trailing)
            } else {
                self.percentCell(
                    usedPercent: self.entry.primaryUsedPercent,
                    resetDescription: self.entry.primaryResetDescription)
                self.percentCell(
                    usedPercent: self.entry.secondaryUsedPercent,
                    resetDescription: self.entry.secondaryResetDescription)
            }
        }
    }

    @ViewBuilder
    private func percentCell(usedPercent: Double?, resetDescription: String?) -> some View {
        if let used = usedPercent {
            let remaining = max(0, 100 - used)
            let isLow = remaining < 20
            let pctColor: Color = isLow ? .orange : MenuHighlightStyle.secondary(self.isHighlighted)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.0f%%", remaining))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(pctColor)
                if let reset = resetDescription {
                    Text(reset)
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(pctColor.opacity(0.65))
                }
            }
            .frame(width: Self.colWidth, alignment: .trailing)
        } else {
            Text("—")
                .font(.caption2)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted).opacity(0.5))
                .frame(width: Self.colWidth, alignment: .trailing)
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
