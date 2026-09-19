import SwiftUI

/// Visual state of one bookable date (one week's occurrence of a class).
/// idle: hollow circle on chip · selected: gold + check · scheduled: gold + clock ·
/// submitted: chip color + brown check, greyed date (no solid dark — that's for the button).
enum DateChipState {
    case idle, selected, scheduled, submitted, failed

    fileprivate var icon: String {
        switch self {
        case .idle: return "circle"
        case .selected, .submitted: return "checkmark"
        case .scheduled: return "clock"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    fileprivate var iconColor: Color {
        switch self {
        case .idle: return Theme.textSecondary
        case .selected: return Theme.onBrand
        case .scheduled: return Theme.onBrand
        case .submitted: return Theme.checkBrown
        case .failed: return Theme.danger
        }
    }

    fileprivate var textColor: Color {
        switch self {
        case .selected, .scheduled: return Theme.onBrand
        case .submitted: return Theme.textSecondary
        default: return Theme.ink
        }
    }

    fileprivate var fill: Color {
        switch self {
        case .idle, .submitted: return Theme.chipIdle
        case .selected, .scheduled: return Theme.brand
        case .failed: return Theme.danger.opacity(0.12)
        }
    }

    fileprivate var border: Color {
        switch self {
        case .idle, .submitted: return Theme.hairline
        case .selected, .scheduled: return .clear
        case .failed: return Theme.danger
        }
    }

    fileprivate var spokenName: String {
        switch self {
        case .idle: return "未選取"
        case .selected: return "已選取"
        case .scheduled: return "排程中"
        case .submitted: return "已送出"
        case .failed: return "送出失敗"
        }
    }
}

struct DateChip: View {
    let text: String
    let state: DateChipState
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: state.icon)
                    .font(.system(size: 18, weight: Theme.Weight.strong))
                    .foregroundStyle(state.iconColor)
                Text(text)
                    .font(.caption.weight(Theme.Weight.label).monospacedDigit())
                    .foregroundStyle(state.textColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(state.fill, in: shape)
            .overlay(shape.strokeBorder(state.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(text)，\(state.spokenName)")
    }
}

/// Round single-character weekday toggle (一…日). Same palette as `DateChip`.
struct WeekdayChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(String(label.dropFirst())) // "週一" -> "一"
                .font(.subheadline.weight(Theme.Weight.strong))
                .foregroundStyle(isOn ? Theme.onBrand : Theme.textSecondary)
                .frame(maxWidth: 44)
                .aspectRatio(1, contentMode: .fit)
                .background(Circle().fill(isOn ? Theme.brand : Theme.chipIdle))
                .overlay(Circle().strokeBorder(isOn ? Color.clear : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Filled gold circle with a dark check when on, empty ring when off.
struct CheckDot: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(Theme.brand)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.onBrand)
            } else {
                Circle().strokeBorder(Theme.textSecondary.opacity(0.5), lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
    }
}

/// Reservation status as a colored capsule label.
struct StatusPill: View {
    let status: Reservation.Status

    var body: some View {
        Text(title)
            .font(.caption.weight(Theme.Weight.strong))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(status == .submitted ? Theme.hairline : .clear, lineWidth: 1))
    }

    private var title: String {
        switch status {
        case .pending: return "排程中"
        case .submitting: return "送出中"
        case .submitted: return "已送出"
        case .failed: return "失敗"
        }
    }

    private var fill: Color {
        switch status {
        case .pending, .submitting: return Theme.brand
        case .submitted: return Theme.chipIdle
        case .failed: return Theme.danger
        }
    }

    private var foreground: Color {
        switch status {
        case .pending, .submitting: return Theme.onBrand
        case .submitted: return Theme.checkBrown
        case .failed: return Theme.onInk
        }
    }
}

/// Shared by the courses and history screens: confirm, then cancel (or clear, if failed) the
/// reservation held in `reservation`.
private struct CancelConfirmation: ViewModifier {
    @EnvironmentObject private var reservationStore: ReservationStore
    @Binding var reservation: Reservation?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "這堂課要取消預約嗎？",
            isPresented: Binding(get: { reservation != nil }, set: { if !$0 { reservation = nil } }),
            presenting: reservation
        ) { reservation in
            Button(reservation.status == .failed ? "移除" : "取消預約", role: .destructive) {
                Task { await reservationStore.cancel(reservation) }
            }
        } message: { reservation in
            Text(reservation.course.submissionText)
        }
    }
}

extension View {
    func cancelConfirmation(_ reservation: Binding<Reservation?>) -> some View {
        modifier(CancelConfirmation(reservation: reservation))
    }
}

/// Small read-only capsule, e.g. the active-filter summary row.
struct TagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(Theme.Weight.label))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.chipIdle))
            .overlay(Capsule().strokeBorder(Theme.brand, lineWidth: 1.5))
    }
}

/// 1pt divider in the theme's hairline color (system `Divider` ignores custom tints).
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }
}
