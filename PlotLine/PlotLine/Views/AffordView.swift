//
//  AffordView.swift
//  PlotLine
//
//  Budget → Plan → "Can I afford it?": a purchase checked against the budget and the Plan. The
//  answer says where the money would come from; if it doesn't fit, a short-term cut plan (trim fun
//  spending, pause subscriptions, a goal or extra debt payments) and "Save for it", which makes a
//  Plan goal funded by the cuts. The cuts end on their own once the goal is reached. Also: the AI's
//  estimate of what it costs to keep (a car's insurance), and a wishlist to think it over first.
//

import SwiftUI

struct AffordView: View {
    @ObservedObject var model: PlanViewModel
    /// opened from the wishlist: that item
    let wish: WishItem?

    init(model: PlanViewModel, wish: WishItem? = nil) {
        self.model = model
        self.wish = wish
        _item = State(initialValue: wish?.item ?? "")
        _price = State(initialValue: wish.map { String(Int($0.price.rounded())) } ?? "")
        // the estimate saved with the item: no new AI call
        if let wish, let costs = wish.ongoingCosts {
            _ongoing = State(initialValue: OngoingEstimate(saved: costs))
            _ongoingFor = State(initialValue: wish.item.trimmingCharacters(in: .whitespaces))
        }
    }

    @State private var item: String
    @State private var price: String
    @State private var ongoing: OngoingEstimate?
    @State private var ongoingFor = ""                // the item the estimate is for
    @State private var leftOut: Set<String> = []      // estimated costs they unticked
    @State private var estimating = false
    @State private var thinkDays = 2
    @State private var wishlisted = false
    @State private var boughtIt: BoughtResult?
    @State private var monthly = false
    @State private var wantItLater = false
    @State private var by = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var payment: AffordRequest.Payment = .cash
    @State private var apr = "24"

    @State private var result: AffordResult?
    @State private var checked: AffordRequest?        // what `result` is for
    @State private var picked: Set<String> = []       // cut ids
    @State private var checking = false
    @State private var saving = false
    @State private var saved: SaveForItResult?
    @State private var errorMessage: String?
    @FocusState private var typing: Bool

    private var priceValue: Double { Double(price.filter { $0.isNumber || $0 == "." }) ?? 0 }

    private var trimmedItem: String { item.trimmingCharacters(in: .whitespaces) }

    /// the estimated costs still ticked (only while the estimate is for this item)
    private var includedOngoing: [OngoingCost] {
        guard let ongoing, ongoingFor == trimmedItem, !monthly else { return [] }
        return ongoing.costs.filter { !leftOut.contains($0.name) }
    }

    private var request: AffordRequest {
        AffordRequest(item: trimmedItem, price: priceValue,
                      by: !monthly && wantItLater ? Plan.dayKey(by) : nil, payment: monthly ? .cash : payment,
                      apr: payment == .cardBalance ? (Double(apr) ?? 24) : 0, monthly: monthly,
                      ongoingCosts: includedOngoing)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PLSpacing.lg) {
                form
                if let result, let checked {
                    if checked != request {
                        Text("You changed something: check again to update the answer.")
                            .font(.footnote).foregroundColor(PLColor.warning)
                    }
                    answer(result, for: checked)
                }
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Can I afford it?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { typing = false }
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - The purchase

    private var form: some View {
        VStack(alignment: .leading, spacing: PLSpacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What is it?").font(.headline)
                TextField("e.g. New laptop", text: $item)
                    .textFieldStyle(.roundedBorder)
                    .focused($typing)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(monthly ? "How much a month?" : "How much?").font(.headline)
                TextField("$0", text: $price)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($typing)
                Toggle("It's a monthly cost (a gym, a car payment)", isOn: $monthly)
                    .font(.subheadline)
            }
            if !monthly { ongoingSection }
            if !monthly {
                VStack(alignment: .leading, spacing: 6) {
                    Text("When do you want it?").font(.headline)
                    Picker("", selection: $wantItLater) {
                        Text("Now").tag(false)
                        Text("By a date").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if wantItLater {
                        DatePicker("By", selection: $by, in: Date()..., displayedComponents: .date)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("How would you pay?").font(.headline)
                    Picker("Pay with", selection: $payment) {
                        ForEach(AffordRequest.Payment.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    if payment == .cardBalance {
                        HStack {
                            Text("Card's interest rate (APR)")
                            Spacer()
                            TextField("24", text: $apr)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                                .focused($typing)
                            Text("%")
                        }
                        .font(.subheadline)
                    }
                }
            }
            Button {
                Task { await check() }
            } label: {
                if checking { ProgressView().frame(maxWidth: .infinity) } else { Text("Check").frame(maxWidth: .infinity) }
            }
            .buttonStyle(PrimaryButton())
            .disabled(priceValue <= 0 || checking)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .plCard()
    }

    /// what it costs to keep each month, from the AI (they can untick any)
    @ViewBuilder private var ongoingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let ongoing, ongoingFor == trimmedItem {
                Text("What it costs to keep").font(.headline)
                if ongoing.costs.isEmpty {
                    Text(ongoing.note.isEmpty ? "Nothing much: no real monthly costs." : ongoing.note)
                        .font(.subheadline).foregroundColor(PLColor.textSecondary)
                } else {
                    ForEach(ongoing.costs) { cost in
                        Toggle(isOn: Binding(get: { !leftOut.contains(cost.name) },
                                             set: { on in if on { leftOut.remove(cost.name) } else { leftOut.insert(cost.name) } })) {
                            HStack {
                                Text(cost.name)
                                Spacer()
                                Text("\(cost.monthly.dollars())/mo").monospacedDigit().foregroundColor(PLColor.textSecondary)
                            }
                        }
                        .font(.subheadline)
                    }
                    Text("About \(includedOngoing.reduce(0) { $0 + $1.monthly }.dollars()) a month, an AI estimate. \(ongoing.note)")
                        .font(.caption).foregroundColor(PLColor.textSecondary)
                }
            } else {
                Button {
                    Task { await estimateOngoing() }
                } label: {
                    if estimating {
                        ProgressView()
                    } else {
                        Label("Estimate what it costs to keep (insurance, upkeep…)", systemImage: "sparkles")
                            .font(.subheadline)
                    }
                }
                .disabled(trimmedItem.isEmpty || estimating)
            }
        }
    }

    // MARK: - The answer

    @ViewBuilder
    private func answer(_ r: AffordResult, for purchase: AffordRequest) -> some View {
        // the verdict
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            Label(r.headline, systemImage: icon(r.tone))
                .font(.title3.bold())
                .foregroundColor(color(r.tone))
            Text(r.detail).font(.subheadline)
            if let ready = r.readyBy, r.verdict != "notYet", r.perMonth > 0 {
                Label("Or wait: at \(r.perMonth.dollars()) a month, you'll have it around \(AffordResult.monthName(ready)).",
                      systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
            }
            if r.hoursOfWork > 0 {
                Label("About \(r.hoursOfWork.formatted(.number.precision(.fractionLength(0...1)))) hours of work\(purchase.monthly ? " a month" : "")",
                      systemImage: "clock")
                    .font(.footnote).foregroundColor(PLColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .plCard()

        // where the money comes from
        if !r.sources.isEmpty {
            VStack(alignment: .leading, spacing: PLSpacing.sm) {
                Text("Where the money comes from").font(.headline)
                ForEach(Array(r.sources.enumerated()), id: \.offset) { _, source in
                    HStack(alignment: .top) {
                        Image(systemName: sourceIcon(source.kind)).foregroundColor(source.kind == "emergency" ? PLColor.danger : PLColor.tint)
                            .frame(width: 22)
                        Text(source.label).font(.subheadline)
                        Spacer()
                        Text(source.amount.dollars()).font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .plCard()
        }

        // paying for it
        if !r.warnings.isEmpty || r.payIn4 != nil {
            VStack(alignment: .leading, spacing: PLSpacing.sm) {
                if let payments = r.payIn4 {
                    Text("Your 4 payments").font(.headline)
                    ForEach(Array(payments.enumerated()), id: \.offset) { _, p in
                        HStack {
                            Text(Plan.day(p.date)?.formatted(.dateTime.month(.abbreviated).day()) ?? p.date)
                            Spacer()
                            Text(p.amount.dollars(cents: true)).monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
                ForEach(r.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline).foregroundColor(PLColor.warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .plCard()
        }

        if let plan = r.cutPlan, !plan.cuts.isEmpty, saved == nil, boughtIt == nil {
            cutPlan(plan, r, purchase)
        }
        if let saved {
            savedCard(saved)
        }
        if !purchase.monthly, saved == nil {
            decideCard(purchase)
        }
    }

    /// not sure yet: the wishlist; from the wishlist: "I bought it"
    @ViewBuilder private func decideCard(_ purchase: AffordRequest) -> some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            if let boughtIt {
                Label("Logged \(boughtIt.logged.dollars()) to \(boughtIt.category)", systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundColor(PLColor.success)
                Text("It's in today's spending, and \(boughtIt.item) is off your wishlist.")
                    .font(.subheadline)
            } else if let wish {
                Text("Decided?").font(.headline)
                Button {
                    Task { await markBought(wish) }
                } label: {
                    Label("I Bought It", systemImage: "bag.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButton())
                Button("Let It Go") {
                    model.removeFromWishlist(wish.id)
                    wishlisted = true
                }
                .frame(maxWidth: .infinity)
                .disabled(wishlisted)
                if wishlisted {
                    Text("Off your wishlist.").font(.caption).foregroundColor(PLColor.textSecondary)
                }
            } else if wishlisted {
                Label("On your wishlist", systemImage: "heart.fill")
                    .font(.headline).foregroundColor(PLColor.success)
                Text("We'll remind you in \(thinkDays == 2 ? "2 days" : "30 days") to decide. It's in your Plan tab.")
                    .font(.subheadline)
            } else {
                Text("Not sure yet?").font(.headline)
                Text("Put it on your wishlist and decide after a cooling-off period. Most impulse buys don't survive it.")
                    .font(.subheadline).foregroundColor(PLColor.textSecondary)
                Picker("Think it over for", selection: $thinkDays) {
                    Text("2 days").tag(2)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)
                Button {
                    // only an estimate for this item is kept (the ones they left ticked)
                    let estimated = ongoing != nil && ongoingFor == purchase.item
                    model.addToWishlist(item: purchase.item, price: purchase.price, days: thinkDays,
                                        ongoingCosts: estimated ? purchase.ongoingCosts : nil)
                    wishlisted = true
                } label: {
                    Label("Add to Wishlist", systemImage: "heart").frame(maxWidth: .infinity)
                }
                .buttonStyle(OutlineButton(tint: PLColor.tint))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .plCard()
    }

    private func cutPlan(_ plan: AffordResult.CutPlan, _ r: AffordResult, _ purchase: AffordRequest) -> some View {
        let selected = plan.cuts.filter { picked.contains($0.id) }
        let perMonth = selected.reduce(0) { $0 + $1.amount }
        let ready = r.readyBy(price: purchase.price, cutsPerMonth: perMonth)
        return VStack(alignment: .leading, spacing: PLSpacing.sm) {
            Text(plan.monthlyNeeded > 0 ? "Make room for it" : "Get it sooner").font(.headline)
            Text(plan.monthlyNeeded > 0
                 ? "You'd need about \(plan.monthlyNeeded.dollars()) more a month\(purchase.monthly ? "" : " for \(plan.months) month\(plan.months == 1 ? "" : "s")"). Pick what to cut for now:"
                 : "Your budget gets there on its own. These would get you there faster:")
                .font(.subheadline).foregroundColor(PLColor.textSecondary)

            VStack(spacing: 0) {
                ForEach(Array(plan.cuts.enumerated()), id: \.element.id) { index, cut in
                    if index > 0 { Divider() }
                    Button {
                        if picked.contains(cut.id) { picked.remove(cut.id) } else { picked.insert(cut.id) }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: picked.contains(cut.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(picked.contains(cut.id) ? PLColor.tint : PLColor.textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cut.label).foregroundColor(.primary)
                                if let note = cut.note {
                                    Text(note).font(.caption).foregroundColor(PLColor.textSecondary)
                                }
                                if !cut.applies {
                                    Text(cut.kind == "subscription"
                                         ? "Your budget's Subscriptions line doesn't cover it, so only Track Subscriptions changes."
                                         : "Not in your budget as its own line: do this one yourself.")
                                        .font(.caption).foregroundColor(PLColor.textSecondary)
                                }
                            }
                            Spacer()
                            Text("\(cut.amount.dollars())/mo").font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if perMonth > 0, let ready {
                Text("With these, \(perMonth.dollars()) more a month: about \(AffordResult.monthName(ready)).")
                    .font(.subheadline.weight(.semibold))
            }

            if !purchase.monthly {
                Button {
                    // a subscription is paused even without its own budget line; the rest only if they apply
                    Task { await saveForIt(purchase, cuts: selected.filter { $0.applies || $0.kind == "subscription" }.map(\.pick)) }
                } label: {
                    if saving { ProgressView().frame(maxWidth: .infinity) }
                    else { Label("Save for It", systemImage: "target").frame(maxWidth: .infinity) }
                }
                .buttonStyle(PrimaryButton(color: PLColor.success))
                .disabled(saving)
                Text("Adds \(purchase.item.isEmpty ? "it" : "“\(purchase.item)”") to your Plan's savings goals and makes these cuts in your budget. They end on their own once you reach it.")
                    .font(.caption).foregroundColor(PLColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .plCard()
    }

    private func savedCard(_ s: SaveForItResult) -> some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            Label("Saving for \(s.goal.name)", systemImage: "checkmark.seal.fill")
                .font(.headline).foregroundColor(PLColor.success)
            Text("\(s.monthly.dollars()) a month goes to it, so you'll have \(s.goal.target.dollars()) around \(AffordResult.monthName(s.readyBy)). It's in your Plan's savings goals, and the cuts end on their own once you reach it.")
                .font(.subheadline)
            if let paused = s.pausedSubscriptions, !paused.isEmpty {
                Label("Paused in Track Subscriptions: \(paused.joined(separator: ", ")). Cancel or pause \(paused.count == 1 ? "it" : "them") in the app you pay through; \(paused.count == 1 ? "it resumes" : "they resume") here when you reach your goal.",
                      systemImage: "pause.circle")
                    .font(.footnote).foregroundColor(PLColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .plCard()
    }

    // MARK: - Actions

    private func check() async {
        typing = false
        checking = true
        defer { checking = false }
        let purchase = request
        do {
            let r = try await PlanAPI.checkAfford(purchase)
            result = r
            checked = purchase
            saved = nil
            picked = Set((r.cutPlan?.cuts ?? []).filter { $0.suggested && $0.applies }.map(\.id))
        } catch {
            errorMessage = (error as? AffordError)?.message ?? "Couldn't check that right now. Try again in a moment."
        }
    }

    private func saveForIt(_ purchase: AffordRequest, cuts: [String]) async {
        saving = true
        defer { saving = false }
        do {
            await model.flushSave()
            saved = try await PlanAPI.saveForIt(purchase, cuts: cuts, wishlistId: wish?.id)
            await model.load(reportErrors: false)
        } catch {
            errorMessage = (error as? AffordError)?.message ?? "Couldn't save for it right now. Try again in a moment."
        }
    }

    private func estimateOngoing() async {
        typing = false
        estimating = true
        defer { estimating = false }
        do {
            ongoing = try await PlanAPI.estimateOngoingCosts(item: trimmedItem, price: priceValue)
            ongoingFor = trimmedItem
            leftOut = []
        } catch {
            errorMessage = (error as? AffordError)?.message ?? "Couldn't estimate that right now. Try again in a moment."
        }
    }

    private func markBought(_ wish: WishItem) async {
        do {
            boughtIt = try await model.bought(goalId: wish.goalId, wishlistId: wish.id)
        } catch {
            errorMessage = (error as? AffordError)?.message ?? "Couldn't log it right now. Try again in a moment."
        }
    }

    // MARK: - Look

    private func icon(_ tone: AffordResult.Tone) -> String {
        switch tone {
        case .good: return "checkmark.circle.fill"
        case .okay: return "calendar.badge.clock"
        case .caution: return "hourglass"
        case .bad: return "exclamationmark.octagon.fill"
        }
    }

    private func color(_ tone: AffordResult.Tone) -> Color {
        switch tone {
        case .good: return PLColor.success
        case .okay: return PLColor.tint
        case .caution: return PLColor.warning
        case .bad: return PLColor.danger
        }
    }

    private func sourceIcon(_ kind: String) -> String {
        switch kind {
        case "unassigned": return "tray"
        case "savings": return "banknote"
        case "wants": return "fork.knife"
        case "goal": return "target"
        case "emergency": return "cross.case"
        default: return "calendar"
        }
    }
}

#Preview {
    NavigationStack { AffordView(model: PlanViewModel(preview: Plan())) }
}
