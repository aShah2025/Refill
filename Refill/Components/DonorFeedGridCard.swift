import SwiftUI

struct DonorFeedGridCard: View {
    let need: ClassroomNeed
    @EnvironmentObject private var state: AppState
    @State private var expanded = false

    private var currentNeed: ClassroomNeed {
        state.allNeeds.first(where: { $0.id == need.id }) ?? need
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerTags
            teacherLine
            if !currentNeed.aiSummary.isEmpty {
                summary
            }
            progressSection
            supportAction
            NavigationLink {
                NeedDetailView(need: currentNeed)
            } label: {
                Label("View story and item list", systemImage: "arrow.right.circle.fill")
                    .font(SchoolTheme.headlineFont(size: 13))
                    .foregroundStyle(SchoolTheme.denim)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .accessibilityElement(children: .contain)
    }

    private var headerTags: some View {
        HStack(spacing: 8) {
            SchoolTag(text: currentNeed.category.rawValue, color: currentNeed.category.tint, system: currentNeed.category.symbol)
            SchoolTag(text: currentNeed.urgency.rawValue, color: currentNeed.urgency.tint, system: "clock.fill")
            Spacer()
            if currentNeed.status == .funded {
                SchoolTag(text: "Funded", color: SchoolTheme.crayonTeal, system: "checkmark.seal.fill")
            } else if currentNeed.fundingProgress > 0.75 {
                SchoolTag(text: "Almost there", color: SchoolTheme.apple, system: "heart.fill")
            }
        }
    }

    private var teacherLine: some View {
        HStack(spacing: 10) {
            AsyncImage(url: currentNeed.teacherPhotoURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        Circle().fill(SchoolTheme.denim.opacity(0.18))
                        Text(initials)
                            .font(SchoolTheme.headlineFont(size: 14))
                            .foregroundStyle(SchoolTheme.denim)
                    }
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(currentNeed.title)
                    .font(SchoolTheme.headlineFont(size: 15))
                    .foregroundStyle(SchoolTheme.ink)
                    .lineLimit(2)
                Text("\(currentNeed.teacherName) · \(currentNeed.schoolName)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(SchoolTheme.mutedText)
                    .lineLimit(2)
                Label(currentNeed.resolvedOrigin.displayName, systemImage: originSymbol)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(originColor)
            }

            Spacer(minLength: 4)
            Button {
                state.toggleFavorite(currentNeed)
            } label: {
                Image(systemName: state.isFavorite(currentNeed) ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(SchoolTheme.apple)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.isFavorite(currentNeed) ? "Remove from favorites" : "Add to favorites")
        }
    }

    private var initials: String {
        let parts = currentNeed.teacherName.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private var originSymbol: String {
        switch currentNeed.resolvedOrigin {
        case .local: return "doc.text.fill"
        case .donorsChoose: return "checkmark.shield.fill"
        case .sample: return "shippingbox.fill"
        }
    }

    private var originColor: Color {
        switch currentNeed.resolvedOrigin {
        case .local: return SchoolTheme.denim
        case .donorsChoose: return SchoolTheme.crayonTeal
        case .sample: return SchoolTheme.crayonOrange
        }
    }

    private var summary: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Refill summary", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(SchoolTheme.crayonPurple)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(currentNeed.aiSummary)
                    .font(SchoolTheme.bodyFont(size: 12))
                    .foregroundStyle(SchoolTheme.mutedText)
                    .lineLimit(expanded ? nil : 2)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(SchoolTheme.crayonPurple.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(SchoolTheme.crayonPurple.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Collapse request summary" : "Expand request summary")
    }

    private var progressSection: some View {
        VStack(spacing: 5) {
            ChalkProgress(progress: currentNeed.fundingProgress, height: 12)
                .accessibilityLabel("Funding progress")
                .accessibilityValue("\(Int(currentNeed.fundingProgress * 100)) percent")
            HStack {
                Text("\(currentNeed.raised.formatted(.currency(code: "USD").precision(.fractionLength(0)))) raised")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(SchoolTheme.ink)
                Spacer()
                Text("\(currentNeed.donorCount) supporters · \(currentNeed.amountRemaining.formatted(.currency(code: "USD").precision(.fractionLength(0)))) left")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(SchoolTheme.mutedText)
            }
        }
    }

    @ViewBuilder
    private var supportAction: some View {
        if !currentNeed.isAcceptingSupport {
            Label(currentNeed.status == .funded ? "This request is fully funded" : "This request is not accepting support", systemImage: "checkmark.seal.fill")
                .font(SchoolTheme.headlineFont(size: 13))
                .foregroundStyle(SchoolTheme.crayonTeal)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            switch currentNeed.resolvedOrigin {
            case .local:
                DonationCheckoutView(need: currentNeed, compact: true)
            case .donorsChoose:
                if let url = currentNeed.sourceURL {
                    Link(destination: url) {
                        Label("Donate securely on DonorsChoose", systemImage: "arrow.up.right.square.fill")
                            .font(SchoolTheme.headlineFont(size: 14))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(SchoolTheme.apple)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityHint("Opens the official project in your browser")
                } else {
                    Label("Official donation link unavailable", systemImage: "exclamationmark.triangle.fill")
                        .font(SchoolTheme.bodyFont(size: 13))
                        .foregroundStyle(SchoolTheme.apple)
                }
            case .sample:
                DonationCheckoutView(need: currentNeed, compact: true)
            }
        }
    }
}

struct DonationCheckoutView: View {
    let need: ClassroomNeed
    var compact = false

    @EnvironmentObject private var state: AppState
    @State private var selectedAmount: Double
    @State private var message = ""
    @State private var isProcessing = false
    @State private var paymentError: String?
    @State private var receipt: Receipt?

    private let presets: [Double] = [5, 10, 25, 50, 100]

    init(need: ClassroomNeed, compact: Bool = false) {
        self.need = need
        self.compact = compact
        _selectedAmount = State(initialValue: min(10, max(need.amountRemaining, 1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if need.resolvedOrigin == .sample {
                Label("Sample request · test card checkout", systemImage: "creditcard.fill")
                    .font(SchoolTheme.headlineFont(size: compact ? 13 : 16))
                    .foregroundStyle(SchoolTheme.crayonOrange)
                Text("Use Stripe test card details to try the full payment flow. No real card is charged and this sample does not fund a classroom.")
                    .font(SchoolTheme.bodyFont(size: 12))
                    .foregroundStyle(SchoolTheme.mutedText)
            }

            if !compact {
                if need.resolvedOrigin != .sample {
                    Label("Secure Refill checkout", systemImage: "lock.shield.fill")
                        .font(SchoolTheme.headlineFont(size: 16))
                        .foregroundStyle(SchoolTheme.ink)
                }
                Text("Stripe hosts the payment form. Refill records a contribution only after the server verifies it was paid.")
                    .font(SchoolTheme.bodyFont(size: 12))
                    .foregroundStyle(SchoolTheme.mutedText)
                if need.resolvedOrigin != .sample {
                    Text("Payment goes to the Stripe account configured by this Refill deployment. Review its disbursement, refund, and receipt terms before paying.")
                        .font(SchoolTheme.bodyFont(size: 11))
                        .foregroundStyle(SchoolTheme.crayonOrange)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(presets, id: \.self) { amount in
                        Button {
                            selectedAmount = min(amount, need.amountRemaining)
                        } label: {
                            Text(amount.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(selectedAmount == amount ? .white : SchoolTheme.apple)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(selectedAmount == amount ? SchoolTheme.apple : SchoolTheme.apple.opacity(0.1)))
                                .overlay(Capsule().stroke(SchoolTheme.apple.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(amount > need.amountRemaining)
                        .opacity(amount > need.amountRemaining ? 0.35 : 1)
                        .accessibilityValue(selectedAmount == amount ? "Selected" : "Not selected")
                    }
                }
            }

            if !compact {
                HStack {
                    Text("Custom amount")
                        .font(SchoolTheme.bodyFont(size: 13))
                    Spacer()
                    TextField("Amount", value: $selectedAmount, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
                        .accessibilityLabel("Custom donation amount")
                }

                TextField("Add a kind note (optional)", text: $message, axis: .vertical)
                    .lineLimit(1...3)
                    .font(SchoolTheme.bodyFont(size: 14))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
                    .onChange(of: message) { _, value in
                        if value.count > 240 { message = String(value.prefix(240)) }
                    }
            }

            if !AppConfig.BackendConfig.current.isCheckoutConfigured {
                Label(
                    need.resolvedOrigin == .sample
                        ? "Test card checkout is not configured in this build."
                        : "Live checkout is not configured in this build.",
                    systemImage: "wrench.and.screwdriver.fill"
                )
                    .font(SchoolTheme.bodyFont(size: 12))
                    .foregroundStyle(SchoolTheme.crayonOrange)
            }

            Button {
                startCheckout()
            } label: {
                HStack(spacing: 8) {
                    if isProcessing { ProgressView().tint(.white) }
                    Image(systemName: "lock.fill")
                    Text(buttonTitle)
                }
                .font(SchoolTheme.headlineFont(size: 14))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(canCheckout ? SchoolTheme.apple : SchoolTheme.mutedText)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!canCheckout || isProcessing)
            .accessibilityHint("Opens Stripe's secure hosted payment form")
        }
        .padding(compact ? 0 : 14)
        .background {
            if !compact {
                RoundedRectangle(cornerRadius: 18).fill(Color.white)
            }
        }
        .overlay {
            if !compact {
                RoundedRectangle(cornerRadius: 18).stroke(SchoolTheme.subtleBorder, lineWidth: 1)
            }
        }
        .alert("Donation not completed", isPresented: Binding(
            get: { paymentError != nil },
            set: { if !$0 { paymentError = nil } }
        )) {
            Button("OK") { paymentError = nil }
        } message: {
            Text(paymentError ?? "Please try again.")
        }
        .sheet(item: $receipt) { ReceiptView(receipt: $0) }
    }

    private var canCheckout: Bool {
        need.isAcceptingSupport
            && AppConfig.BackendConfig.current.isCheckoutConfigured
            && selectedAmount >= 1
            && selectedAmount <= 1_000
            && selectedAmount <= need.amountRemaining
    }

    private var buttonTitle: String {
        if isProcessing { return "Opening secure checkout…" }
        let amount = selectedAmount.formatted(.currency(code: "USD").precision(.fractionLength(0)))
        return need.resolvedOrigin == .sample ? "Try card payment · \(amount)" : "Donate \(amount)"
    }

    private func startCheckout() {
        guard canCheckout else { return }
        isProcessing = true
        paymentError = nil
        let donorName = state.profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = donorName.isEmpty ? "A Refill supporter" : donorName
        let email = state.profile.email.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let verifiedReceipt = try await DonationCheckoutService.shared.checkout(
                    amount: selectedAmount,
                    to: need,
                    from: displayName,
                    donorEmail: email.isEmpty ? nil : email,
                    message: message
                )
                state.addDonation(
                    Donation(
                        needId: verifiedReceipt.needId,
                        needTitle: verifiedReceipt.needTitle,
                        donorName: verifiedReceipt.donorName,
                        amount: verifiedReceipt.amount,
                        source: .parents,
                        message: verifiedReceipt.message,
                        createdAt: verifiedReceipt.createdAt,
                        transactionId: verifiedReceipt.transactionId,
                        isVerified: true,
                        isTest: verifiedReceipt.isTest
                    ),
                    to: verifiedReceipt.needId
                )
                receipt = verifiedReceipt
                message = ""
                selectedAmount = min(10, max(need.amountRemaining - verifiedReceipt.amount, 1))
            } catch {
                paymentError = error.localizedDescription
            }
            isProcessing = false
        }
    }
}

struct ReceiptView: View {
    let receipt: Receipt
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(SchoolTheme.crayonTeal)
                        .padding(.top, 20)
                    Text(receipt.isTest ? "Test payment complete" : "Thank you!")
                        .font(SchoolTheme.displayFont(size: 28))
                    Text(receipt.isTest
                         ? "Stripe verified the \(receipt.formattedAmount) test checkout for \(receipt.needTitle)."
                         : "Stripe verified your \(receipt.formattedAmount) contribution for \(receipt.needTitle).")
                        .font(SchoolTheme.bodyFont(size: 15))
                        .foregroundStyle(SchoolTheme.mutedText)
                        .multilineTextAlignment(.center)
                    Text(receipt.isTest
                         ? "This used Stripe test mode. No real card was charged and no classroom received funds."
                         : "This receipt confirms payment to the configured Refill Stripe account; it does not by itself confirm classroom disbursement or a tax deduction.")
                        .font(SchoolTheme.bodyFont(size: 12))
                        .foregroundStyle(SchoolTheme.crayonOrange)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 12) {
                        ReceiptRow(label: "Transaction", value: receipt.transactionId)
                        ReceiptRow(label: "Amount", value: receipt.formattedAmount)
                        ReceiptRow(label: "Method", value: receipt.method)
                        ReceiptRow(label: "Date", value: receipt.formattedDate)
                        ReceiptRow(label: "Classroom", value: receipt.needTitle)
                        if !receipt.message.isEmpty { ReceiptRow(label: "Note", value: receipt.message) }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(SchoolTheme.subtleBorder, lineWidth: 1))

                    if !receipt.isTest {
                        ShareLink(item: "I supported \(receipt.needTitle) with Refill.") {
                            Label("Share your impact", systemImage: "square.and.arrow.up")
                                .font(SchoolTheme.headlineFont(size: 15))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(SchoolTheme.denim)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding(16)
            }
            .background(LinedPaperBackground())
            .navigationTitle("Verified receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

private struct ReceiptRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(SchoolTheme.mutedText)
            Spacer()
            Text(value)
                .font(SchoolTheme.monoFont(size: 12))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(SchoolTheme.bodyFont(size: 13))
    }
}
