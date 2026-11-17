//
//  BudgetQuizModel.swift
//  PlotLine
//
//  Everything the budget quiz asks, what it loads (last answers, bank spending, subscriptions,
//  savings from the Plan tab), the answers kept on the phone while it's unfinished, and the request
//  that builds the budget. Saving also puts bills on the calendar and schedules a one-month check-in.
//  The quiz screens (BudgetQuizView) show one step at a time; the review screen (BudgetReviewView)
//  checks the result before it's saved.
//

import SwiftUI
import UserNotifications

/// the quiz's steps, in order
enum QuizStep: Int, CaseIterable, Identifiable {
    case bank, location, pay, home, gettingAround, otherCosts, subscriptions, debt, goals, categories
    var id: Int { rawValue }
    /// a stable name (the order can change; an unfinished quiz is saved by name)
    var key: String { String(describing: self) }
    static func named(_ key: String) -> QuizStep? { allCases.first { $0.key == key } }

    var title: String {
        switch self {
        case .bank: return "Link a bank or card"
        case .location: return "Where you live"
        case .pay: return "Your pay"
        case .home: return "Home"
        case .gettingAround: return "Getting around"
        case .subscriptions: return "Subscriptions & yearly costs"
        case .otherCosts: return "Other regular costs"
        case .debt: return "Debt"
        case .goals: return "Goals & budgeting style"
        case .categories: return "Categories"
        }
    }

    var why: String {
        switch self {
        case .bank: return "starting from what you really spend beats guessing. It's optional."
        case .location: return "prices, taxes and rent depend on where you live."
        case .pay: return "your budget starts from what actually lands in your account."
        case .home: return "rent is usually the biggest line, and your share of it shapes everything else."
        case .gettingAround: return "so your Transportation budget is real, not a guess."
        case .subscriptions: return "small monthly charges and once-a-year bills are easy to forget; each yearly one becomes a little to set aside every month."
        case .otherCosts: return "these are regular costs a budget often misses."
        case .debt: return "minimum payments come first, and a loan that hasn't started yet isn't budgeted until it does."
        case .goals: return "extra money goes toward what matters most to you, the way you like to budget."
        case .categories: return "costs you already know stay exactly as you enter them."
        }
    }

    /// for someone updating one part of an earlier quiz
    var shortcut: String? {
        switch self {
        case .pay: return "I got a raise"
        case .location: return "I moved"
        case .home: return "Rent changed"
        case .gettingAround: return "New job or commute"
        case .subscriptions: return "Subscriptions"
        case .debt: return "Debt changed"
        default: return nil
        }
    }
}

enum BudgetingStyleChoice: String, CaseIterable, Identifiable {
    case fiftyThirtyTwenty, payYourselfFirst, everyDollar, flexible
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fiftyThirtyTwenty: return "50/30/20"
        case .payYourselfFirst: return "Pay yourself first"
        case .everyDollar: return "Every dollar assigned"
        case .flexible: return "Flexible"
        }
    }
    var detail: String {
        switch self {
        case .fiftyThirtyTwenty: return "Half on needs, 30% on wants, 20% to savings and debt."
        case .payYourselfFirst: return "Savings come out first; spend the rest."
        case .everyDollar: return "Every dollar of your take-home gets a job."
        case .flexible: return "Plan most of it and leave some breathing room."
        }
    }
}

struct QuizSubscription: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var cost: Double
    var dueDate: Date
    var fromBank = false
}

struct YearlyCost: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var amount: Double?          // blank: estimated
    var timesPerYear: Int = 1
    var monthly: Double { (amount ?? 0) * Double(timesPerYear) / 12 }

    // insurance isn't here: it's asked with the car (and through work)
    static let suggestions = ["Car registration", "Car maintenance", "Holidays & gifts", "Trips", "Amazon Prime"]
}

/// one bank transaction counted in "what you usually spend", and how it was sorted
struct BankTransaction: Identifiable, Equatable {
    let id = UUID()
    /// the bank's id: what the quiz's Remove / Move edits refer to
    var txnId: String = ""
    let date: Date
    let name: String
    let amount: Double
    var category: String
    let how: String           // yours, store, bank, ai, none
    /// narrower categories it would move to if switched on (Alcohol & Bars out of Eating Out), best first
    var niches: [String] = []

    /// why it's in that category, in plain words
    var howText: String {
        switch how {
        case "yours": return "Your rule for this place"
        case "store": return "A business PlotLine knows"
        case "bank": return "Your bank or card's label"
        case "ai": return "Sorted by AI from the name"
        default: return "Couldn't tell what it was"
        }
    }
}

/// a charge the bank counts as a subscription, even one that hasn't repeated enough to be detected
struct BankCharge: Identifiable, Equatable {
    let name: String
    let amount: Double        // the latest charge
    let dayOfMonth: Int
    let lastDate: Date
    let times: Int            // in the last ~3 months
    var id: String { name.lowercased() }
}

/// a recurring charge the bank shows that isn't on the list yet
struct DetectedSubscription: Identifiable, Decodable, Equatable {
    let snoozeKey: String
    let name: String
    let averageAmount: Double
    let dayOfMonth: Int
    var id: String { snoozeKey }
}

@MainActor
final class BudgetQuizModel: ObservableObject {
    static let defaultCategories = [
        "Rent", "Groceries", "Subscriptions", "Eating Out",
        "Entertainment", "Utilities", "Savings", "Miscellaneous",
        "Transportation", "Roth IRA", "Car Insurance",
        "Health Insurance", "Brokerage"
    ]
    static let carCategories: Set<String> = ["Car Insurance", "Car Payment", "Gas", "Parking", "Tolls"]
    static let trackerExclusions: Set<String> = ["401(k)", "401k", "401(k) Contribution", "401k Contribution"]
    /// lines an earlier step decides (its answer, or blank to estimate): never asked again on the last step
    static let askedEarlier: Set<String> = [
        "Rent", "Mortgage", "Utilities", "Internet", "Renters Insurance",
        "Health Insurance", "Dental", "Vision",
        "Car Payment", "Car Insurance", "Gas", "Commute", "Transportation", "Parking", "Tolls",
        "Subscriptions", "Streaming Services", "Phone", "Gym", "Medical", "Therapy", "Pet Care", "Childcare",
    ]

    // MARK: Answers

    @Published var step: QuizStep = .bank
    @Published var hasSavedQuiz = false

    // location
    @Published var useDeviceLocation = true
    @Published var city = ""
    @Published var state = ""
    @Published var manualCity = ""
    @Published var manualState = ""

    // pay
    @Published var yearlyIncome = ""
    @Published var retirement = ""
    // dependents by age (the count is their total)
    @Published var under5 = 0
    @Published var age5to12 = 0
    @Published var age13to17 = 0
    @Published var adultDependents = 0
    @Published var childcare = ""                      // blank: estimate; 0: none
    /// an older quiz saved only how many, not their ages
    @Published private(set) var legacyDependents = 0
    @Published var payFrequency: PayFrequency = .biweekly
    @Published var healthPerCheck = ""
    @Published var dentalPerCheck = ""
    @Published var visionPerCheck = ""
    @Published var liveTakeHome: Double?

    // home
    @Published var housingSituation = "Renting"
    @Published var totalRent = ""
    @Published var rentPeople = 1
    @Published var knowsShare = false
    @Published var yourShare = ""
    @Published var mortgage = ""
    @Published var utilitiesIncluded = false
    @Published var utilities = ""
    @Published var internet = ""
    @Published var rentersInsurance = ""

    // getting around
    @Published var carOwnership = "One Car"
    @Published var carPayment = ""
    @Published var carInsurance = ""                   // per payment
    @Published var carInsuranceMonths = 1              // paid every 1, 6 or 12 months
    @Published var carInsuranceNextDue = Date()        // when it's not monthly
    @Published var otherMilesPerWeek = ""
    @Published var workArrangement = "office"
    @Published var workPlace = ""
    @Published var commute = CommuteInputs()
    @Published var route: CommuteRoute.Result?
    @Published var estimatingCommute = false
    @Published var commuteMessage: String?
    @Published var commuteEstimated = false
    /// the gas (or electricity) price that was looked up, and whether it's EIA's real average
    @Published private(set) var lookedUpFuelPrice: Double?
    @Published private(set) var fuelPriceFromEIA = false

    enum FuelPriceSource { case eia, estimate, yours, none }
    /// where the price shown came from (a price they typed is theirs)
    var fuelPriceSource: FuelPriceSource {
        guard commute.fuelPrice > 0 else { return .none }
        guard let looked = lookedUpFuelPrice, abs(looked - commute.fuelPrice) < 0.0005 else { return .yours }
        return fuelPriceFromEIA ? .eia : .estimate
    }

    /// a price that was looked up replaces the one shown, unless they typed their own, or it's an
    /// estimate and EIA's real price is already showing (a second, slower lookup used to swap it out)
    func setLookedUpFuelPrice(_ price: Double, fromEIA: Bool) {
        if fuelPriceSource == .eia && !fromEIA { return }
        if fuelPriceSource != .yours { commute.fuelPrice = price }
        lookedUpFuelPrice = price
        fuelPriceFromEIA = fromEIA
    }

    /// a gas price lookup is under way (another one waits for it instead of asking again)
    private var fuelPriceLookup: Task<Void, Never>?

    // subscriptions
    @Published var subscriptions: [QuizSubscription] = []
    @Published var detected: [DetectedSubscription] = []
    @Published var subscriptionsLoaded = false
    private var originalSubscriptionNames: Set<String> = []

    // other regular costs
    @Published var eatingOutFrequency = "Sometimes"
    @Published var phone = ""
    @Published var gym = ""
    @Published var medical = ""
    @Published var dogs = 0
    @Published var cats = 0
    @Published var otherPets = 0
    @Published var petsMonthly = ""

    // yearly
    @Published var yearlyCosts: [YearlyCost] = []

    // debt
    @Published var hasDebt = false
    @Published var debts: [DebtItem] = []

    // goals and style
    @Published var budgetingStyle: BudgetingStyleChoice = .flexible
    @Published var savePercent: Double = 20
    @Published var primaryGoal = "Balanced"
    @Published var savingsPriority = "Medium"

    // categories
    @Published var allCategories: [String] = BudgetQuizModel.defaultCategories
    @Published var selectedCategories: Set<String> = Set(BudgetQuizModel.defaultCategories)
    @Published var knownCosts: [String: String] = [:]

    // the day of the month each bill is due ("Rent", "Car Payment", …): it goes on the calendar
    @Published var billDueDays: [String: Int] = [:]

    // savings, shared with the Plan tab
    @Published private(set) var plan: Plan?            // nil until it loads
    @Published private(set) var planBalances: [String: Double] = [:]
    @Published var savedNow = ""                       // asked only when the Plan tab has nothing yet

    // bank
    @Published var bankLinked = false
    @Published var bankReady = false
    @Published var bankAverages: [String: Double] = [:]
    @Published var bankMonths: Double = 0
    /// what the bank counts as Subscriptions (what makes up that average)
    @Published var bankCharges: [BankCharge] = []
    /// every transaction counted in the averages, newest first
    @Published var bankTransactions: [BankTransaction] = []
    /// their edits on those (swipe Remove / Move): bank id → the category it goes in, "" for not counted.
    /// Saved with the answers; applied to Monthly Costs when the budget is saved.
    @Published var bankEdits: [String: String] = [:]
    /// Regenerate on the budget page: exactly the page's categories (nothing added from the answers),
    /// and the ones just added there, which get estimated from their spending
    var exactCategories: [String]?
    var newCategories: [String] = []
    /// take-home a month when the quiz was last saved (the compare screen's "current")
    @Published private(set) var savedMonthlyNet: Double?

    /// bank amounts they replaced with their own answer (Change): not sent, so their answer is what counts
    @Published var bankOverrides: Set<String> = []
    /// categories added because the bank shows spending there, and ones they switched off (not added again)
    @Published private(set) var fromBankCategories: Set<String> = []
    @Published var declinedBankCategories: Set<String> = []
    static let bankCategoryMinimum = 25.0
    /// a narrower category this big starts switched on (Alcohol & Bars out of Eating Out)
    static let nicheOnMinimum = 50.0
    @Published var checkingBank = false

    private var takeHomeTask: Task<Void, Never>?

    var username: String { UserDefaults.standard.string(forKey: "loggedInUsername") ?? "" }

    // MARK: Derived

    var finalCity: String { useDeviceLocation ? city : manualCity }

    /// Opening with saved answers: where the phone is now (it used to show the saved city as "Detected").
    /// Same place: Use My Location stays on. Somewhere else: off, keeping the saved place, so a move
    /// saved from the compare screen isn't replaced.
    func phoneLocated(city: String, state: String) {
        guard city != "Permission", !city.isEmpty else { phoneLocationUnavailable(); return }
        let phone = Self.place(city: city, state: state)
        self.city = phone.city
        self.state = phone.state
        let saved = Self.place(city: manualCity, state: manualState)
        let same = phone.city.caseInsensitiveCompare(saved.city) == .orderedSame && (saved.state.isEmpty || phone.state == saved.state)
        useDeviceLocation = same || saved.city.isEmpty
    }

    /// a city and state tidied up: "Ashburn, VA" typed as the city → Ashburn + VA; "Virginia" → VA
    nonisolated static func place(city: String, state: String) -> (city: String, state: String) {
        var city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        var state = stateCode(state) ?? state.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let comma = city.lastIndex(of: ","), let code = stateCode(String(city[city.index(after: comma)...])) {
            city = city[..<comma].trimmingCharacters(in: .whitespaces)
            if state.isEmpty || state == code { state = code }
        }
        return (city, state)
    }

    /// "VA", "va" or "Virginia" → "VA" (nil if it isn't a state)
    nonisolated static func stateCode(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return USState.all.first { $0.code.caseInsensitiveCompare(t) == .orderedSame || $0.name.caseInsensitiveCompare(t) == .orderedSame }?.code
    }

    /// location is off or didn't answer: the saved place, typed in
    func phoneLocationUnavailable() {
        if !manualCity.isEmpty { useDeviceLocation = false }
    }

    /// the phone is somewhere other than the place being budgeted for
    var phoneElsewhere: Bool {
        let saved = Self.place(city: manualCity, state: manualState)
        return !useDeviceLocation && !city.isEmpty && city != "Permission"
            && (city.caseInsensitiveCompare(saved.city) != .orderedSame || state != saved.state)
    }
    var finalState: String { useDeviceLocation ? state : manualState }
    var hasCar: Bool { carOwnership != "No Car" }
    var rents: Bool { housingSituation == "Renting" || housingSituation == "Live with Others" }
    var commutes: Bool { workArrangement == "office" || workArrangement == "hybrid" }

    var insurancePerCheck: Double {
        [healthPerCheck, dentalPerCheck, visionPerCheck].compactMap(Self.amount).reduce(0, +)
    }

    var dependentsCount: Int {
        let byAge = under5 + age5to12 + age13to17 + adultDependents
        return byAge > 0 ? byAge : legacyDependents
    }
    var kidsUnder13: Int { under5 + age5to12 }

    var subscriptionsMonthly: Double { subscriptions.map(\.cost).reduce(0, +) }

    /// car insurance per month (a 6-month or yearly payment set aside monthly)
    var carInsuranceMonthly: Double? {
        Self.amount(carInsurance).map { $0 / Double(max(1, carInsuranceMonths)) }
    }
    var yearlyMonthly: Double { yearlyCosts.map(\.monthly).reduce(0, +) }

    /// what the commute costs a month (nil until estimated, except modes that need no estimate)
    var commuteMonthly: (total: Double, summary: String)? {
        guard commutes, commuteEstimated || commute.mode == .bikeWalk || commute.mode == .carpoolPassenger else { return nil }
        var inputs = commute
        inputs.officeDaysPerWeek = workArrangement == "office" ? 5 : min(commute.officeDaysPerWeek, 4)
        return CommuteCost.monthly(inputs)
    }

    /// the commute's gas (in Gas) and the rest (tolls, parking, transit, rides: in Transportation)
    var commuteSplit: (gas: Double, other: Double)? {
        guard let monthly = commuteMonthly else { return nil }
        var inputs = commute
        inputs.officeDaysPerWeek = workArrangement == "office" ? 5 : min(commute.officeDaysPerWeek, 4)
        let gas = min(monthly.total, CommuteCost.gas(inputs))
        return (gas, max(0, monthly.total - gas))
    }

    /// the Gas line from their own answers: the commute's gas plus other driving (nil if neither is known)
    var gasFromAnswers: (total: Double, commute: Double, other: Double)? {
        let commute = commuteSplit?.gas ?? 0, other = otherGasMonthly ?? 0
        return commute + other > 0 ? (commute + other, commute, other) : nil
    }

    /// gas for driving outside the commute, a month (needs a gas price, from the commute estimate)
    var otherGasMonthly: Double? {
        guard hasCar, let miles = Self.amount(otherMilesPerWeek), miles > 0, commute.fuelPrice > 0 else { return nil }
        return miles * 52 / 12 / commute.car.milesPerUnit * commute.fuelPrice
    }

    /// lines the earlier steps decide (answered there, or left blank to estimate): the last step
    /// doesn't show them again
    var answeredElsewhere: Set<String> {
        Self.askedEarlier.union(yearlyCosts.map(\.name).filter { !$0.isEmpty })
            .union(debts.map { "Debt - \($0.name)" })
    }

    /// the categories the earlier answers call for. Blank means estimate for rent, utilities, phone and
    /// car insurance (0 = none); blank means none for gym and copays, unless the bank shows them.
    /// Health insurance comes out of the paycheck (or isn't there): never a line.
    var derivedCategories: Set<String> {
        var set: Set<String> = ["Transportation"]
        if rents { set.insert("Rent") }
        if !utilitiesIncluded && housingSituation != "Other" { set.insert("Utilities") }
        if hasCar {
            set.insert("Gas")
            if Self.amount(carInsurance) != 0 { set.insert("Car Insurance") }
        }
        if Self.amount(phone) != 0 { set.insert("Phone") }
        if (Self.amount(gym) ?? 0) > 0 || (gym.isEmpty && bankAverage("Gym") != nil) { set.insert("Gym") }
        if (Self.amount(medical) ?? 0) > 0 || (medical.isEmpty && bankAverage("Medical") != nil) { set.insert("Medical") }
        if !subscriptions.isEmpty { set.insert("Subscriptions") }
        return set
    }

    var debtEntriesValid: Bool {
        guard hasDebt else { return true }
        return debts.allSatisfy { !$0.name.isEmpty && Double($0.principal) != nil }
    }

    /// what has to be filled in before going past a step
    func canLeave(_ step: QuizStep) -> Bool {
        switch step {
        case .location: return !finalCity.isEmpty && !finalState.isEmpty && finalCity != "Permission"
        case .pay: return (Self.amount(yearlyIncome) ?? 0) > 0
        case .debt: return debtEntriesValid
        default: return true
        }
    }

    var canBuild: Bool { QuizStep.allCases.allSatisfy(canLeave) }

    /// what the bank says they spend on a category (only once its history is in). A narrower one
    /// (Alcohol & Bars) switched off shows what switching it on would move out of the broad one.
    func bankAverage(_ category: String) -> Double? {
        guard bankReady else { return nil }
        if let value = sortedBankAverages[category], value > 0 { return value }
        guard bankNiches.contains(category), !selectedCategories.contains(category), bankMonths > 0 else { return nil }
        let total = bankTransactions.filter { sortedCategory($0, alsoOn: category) == category }.map(\.amount).reduce(0, +)
        let monthly = (total / bankMonths).rounded()
        return monthly > 0 ? monthly : nil
    }

    /// the narrower categories their transactions could go to (Alcohol & Bars, Coffee...). Not ones an
    /// earlier step answers (Parking, Streaming Services...): those never become their own line here.
    var bankNiches: Set<String> { Set(bankTransactions.flatMap(\.niches)).subtracting(answeredElsewhere) }

    /// a narrower category of this broad one, with what it's worth a month (switched on or not)
    func nichesInside(_ broad: String, atLeast minimum: Double = 10) -> [(name: String, monthly: Double)] {
        bankNiches.filter { nicheParent($0) == broad }
            .compactMap { n in bankAverage(n).flatMap { $0 >= minimum ? (n, $0) : nil } }
            .sorted { $0.1 > $1.1 }
    }

    /// "Track separately" on the bank step: its own line in the budget, its spending out of the broad one
    func trackSeparately(_ niche: String, _ on: Bool) {
        if on && !allCategories.contains(where: { $0.lowercased() == niche.lowercased() }) { allCategories.append(niche) }
        setCategory(niche, on: on)
    }

    /// the broad category a narrower one's transactions come out of (Eating Out for Alcohol & Bars)
    func nicheParent(_ niche: String) -> String? {
        let counts = Dictionary(grouping: bankTransactions.filter { $0.niches.contains(niche) }, by: \.category).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key
    }

    /// where a transaction counts now, or nil when they removed it: their Move first, then a narrower
    /// category that's switched on (or `alsoOn`, to see what switching one on would do)
    func sortedCategory(_ t: BankTransaction, alsoOn extra: String? = nil) -> String? {
        if !t.txnId.isEmpty, let edit = bankEdits[t.txnId] { return edit.isEmpty ? nil : edit }
        var on = selectedCategories.intersection(bankNiches)
        if let extra { on.insert(extra) }
        return t.niches.first(where: on.contains) ?? t.category
    }

    /// what "see the transactions" shows for a category: for a narrower one that's switched off, the ones
    /// switching it on would move there
    func transactionsShown(for category: String) -> [BankTransaction] {
        guard bankNiches.contains(category), !selectedCategories.contains(category) else { return sortedBankTransactions }
        return bankTransactions.compactMap { t in
            guard sortedCategory(t, alsoOn: category) == category else { return nil }
            var moved = t
            moved.category = category
            return moved
        }
    }

    /// the ones they swiped away (the "Not counted" list), in the category they'd have been in
    var removedBankTransactions: [BankTransaction] {
        bankTransactions.filter { !$0.txnId.isEmpty && bankEdits[$0.txnId] == "" }
    }

    /// swipe Remove: not part of what they usually spend, and not added to Monthly Costs
    func removeBankTransaction(_ t: BankTransaction) {
        guard !t.txnId.isEmpty else { return }
        bankEdits[t.txnId] = ""
    }

    /// "Put back" on a removed one, or undoing a move
    func restoreBankTransaction(_ t: BankTransaction) {
        bankEdits[t.txnId] = nil
    }

    /// Move (just this one): it counts in that category; a category the quiz doesn't have yet is added, on
    func moveBankTransaction(_ t: BankTransaction, to category: String) {
        let typed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.txnId.isEmpty, !typed.isEmpty else { return }
        // one they have already, however it was typed ("date night" → Date Night)
        let name = (allCategories + placeChoices).first { $0.lowercased() == typed.lowercased() } ?? typed
        bankEdits[t.txnId] = name
        useCategory(name)
    }

    /// a category spending was moved to: a budget line, switched on (an earlier step's line is already there)
    func useCategory(_ category: String) {
        guard !answeredElsewhere.contains(category) else { return }
        if !allCategories.contains(where: { $0.lowercased() == category.lowercased() }) { allCategories.append(category) }
        selectedCategories.insert(category)
        declinedBankCategories.remove(category)
    }

    /// "Always put this place in…": every transaction from it goes there, in the quiz now and in Monthly
    /// Costs (the last 90 days and from now on). Reloads what the bank shows; false if it didn't save.
    func alwaysPut(_ place: String, in category: String) async -> Bool {
        do {
            try await postJSON("/api/category/place", ["username": username, "merchant": place, "category": category])
        } catch {
            AppBanner.report("save where that place's purchases go", error)
            return false
        }
        // the place's own moves give way to the rule
        for t in bankTransactions where t.name == place && bankEdits[t.txnId] != "" { bankEdits[t.txnId] = nil }
        useCategory(category)
        await checkBank()
        return true
    }

    /// the categories a purchase can be moved to: not money set aside, and not a line only an earlier
    /// step decides that the budget won't have (Parking with no car...)
    var placeChoices: [String] {
        let money: Set<String> = ["Savings", "Roth IRA", "Brokerage", "Emergency Fund"]
        let notLines = answeredElsewhere.subtracting(derivedCategories)
        return Set(CategoryOptions.spending).union(allCategories).union(bankAverages.keys)
            .subtracting(Self.trackerExclusions).subtracting(notLines)
            .filter { !money.contains($0) && !$0.hasPrefix("Debt - ") }.sorted()
    }

    /// the transactions as they count now (what "see the transactions" shows); removed ones aren't here
    var sortedBankTransactions: [BankTransaction] {
        bankTransactions.compactMap { t in
            guard let category = sortedCategory(t) else { return nil }
            var sorted = t
            sorted.category = category
            return sorted
        }
    }

    /// the bank's monthly averages with their moves, removals and the narrower categories they switched
    /// on applied (the same way Monthly Costs records them)
    var sortedBankAverages: [String: Double] {
        guard bankMonths > 0 else { return bankAverages }
        var totals: [String: Double] = [:], changed: Set<String> = []
        for t in bankTransactions {
            let now = sortedCategory(t)
            if let now { totals[now, default: 0] += t.amount }
            if now != t.category {
                changed.insert(t.category)
                if let now { changed.insert(now) }
            }
        }
        guard !changed.isEmpty else { return bankAverages }
        var out = bankAverages
        for category in changed {
            let monthly = ((totals[category] ?? 0) / bankMonths).rounded()
            out[category] = monthly > 0 ? monthly : nil
        }
        return out
    }

    nonisolated static func amount(_ raw: String) -> Double? {
        Double(raw.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
                  .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Live take-home

    func refreshTakeHome() {
        takeHomeTask?.cancel()
        guard let income = Self.amount(yearlyIncome), income > 0 else { liveTakeHome = nil; return }
        let state = finalState, k401 = Self.amount(retirement) ?? 0
        let insurance = insurancePerCheck * Double(payFrequency.rawValue)
        takeHomeTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled,
                  let r = try? await PlanAPI.takeHome(salary: income, state: state.isEmpty ? nil : state, k401Percent: k401,
                                                      preTaxHealthYearly: insurance, payPeriods: 12),
                  !Task.isCancelled else { return }
            liveTakeHome = r.perPaycheck.takeHome
        }
    }

    // MARK: Bank

    /// the last ~3 months of spending by category (read only; nothing is added to spending yet)
    func checkBank() async {
        checkingBank = true
        defer { checkingBank = false }
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/plaid/spending-summary/\(username)") else { return }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        bankLinked = json["linked"] as? Bool ?? false
        bankReady = json["ready"] as? Bool ?? false
        bankMonths = (json["months"] as? NSNumber)?.doubleValue ?? 0
        bankAverages = (json["averages"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        bankTransactions = (json["transactions"] as? [[String: Any]] ?? []).compactMap { t in
            guard let date = (t["date"] as? String).flatMap(day.date), let amount = (t["amount"] as? NSNumber)?.doubleValue else { return nil }
            return BankTransaction(txnId: t["id"] as? String ?? "", date: date, name: t["name"] as? String ?? "", amount: amount,
                                   category: t["category"] as? String ?? "Miscellaneous", how: t["how"] as? String ?? "none",
                                   niches: t["niches"] as? [String] ?? [])
        }
        bankCharges = (json["subscriptionCharges"] as? [[String: Any]] ?? []).compactMap { c in
            guard let name = c["name"] as? String, let amount = (c["amount"] as? NSNumber)?.doubleValue,
                  let last = (c["lastDate"] as? String).flatMap(day.date) else { return nil }
            return BankCharge(name: name, amount: amount, dayOfMonth: (c["dayOfMonth"] as? NSNumber)?.intValue ?? 1,
                              lastDate: last, times: (c["times"] as? NSNumber)?.intValue ?? 1)
        }
        addBankCategories()
        if bankLinked && bankReady { await loadDetected() }
    }

    /// spending the bank shows in a category the budget doesn't have (at least $25 a month): added and
    /// switched on, so each person's budget has the categories they really spend in
    func addBankCategories() {
        guard bankReady else { return }
        let have = Set(allCategories.map { $0.lowercased() })
        let yearlyNames = Set(yearlyCosts.map { $0.name.lowercased() })
        for (category, monthly) in bankAverages where monthly >= Self.bankCategoryMinimum {
            let key = category.lowercased()
            guard category != "Miscellaneous", !have.contains(key), !yearlyNames.contains(key),
                  !answeredElsewhere.contains(category), !declinedBankCategories.contains(category) else { continue }
            allCategories.append(category)
            selectedCategories.insert(category)
            fromBankCategories.insert(category)
        }
        // narrower ones (Alcohol & Bars, Coffee...): $50+ a month switched on (their spending moves out of the
        // broad one), $25+ listed but off
        let candidates = bankNiches.filter { n in !allCategories.contains(where: { $0.lowercased() == n.lowercased() }) }
            .compactMap { n in bankAverage(n).map { (n, $0) } }.sorted { $0.1 > $1.1 }
        for (niche, monthly) in candidates where !declinedBankCategories.contains(niche) && monthly >= Self.bankCategoryMinimum {
            allCategories.append(niche)
            if monthly >= Self.nicheOnMinimum {
                selectedCategories.insert(niche)
                fromBankCategories.insert(niche)
            }
        }
    }

    /// switching a category on or off on the last step (one from the bank that's switched off stays off)
    func setCategory(_ category: String, on: Bool) {
        if on {
            selectedCategories.insert(category)
            declinedBankCategories.remove(category)
        } else {
            selectedCategories.remove(category)
            if bankAverage(category) != nil { declinedBankCategories.insert(category) }
        }
    }

    // MARK: Subscriptions

    /// the Subscriptions page's list (later quizzes) — both stay in sync when the budget is saved
    func loadSubscriptions() async {
        guard !subscriptionsLoaded,
              let url = URL(string: "\(BackendConfig.baseURLString)/api/subscriptions/\(username)") else { return }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return }
        if (200...299).contains(http.statusCode),
           let decoded = try? JSONDecoder().decode(SubscriptionMapResponse.self, from: data) {
            subscriptions = decoded.subscriptions.values
                .map { QuizSubscription(name: $0.name, cost: Double($0.cost ?? "") ?? 0, dueDate: $0.dueDate) }
                .sorted { $0.name < $1.name }
        }
        originalSubscriptionNames = Set(subscriptions.map { $0.name.lowercased() })
        subscriptionsLoaded = (200...299).contains(http.statusCode) || http.statusCode == 404
    }

    /// recurring charges in the bank that aren't on the list yet
    func loadDetected() async {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/subscriptions/recurring/analyze/\(username)?months=6&remindAfterMonths=2") else { return }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        struct Response: Decodable { let prompts: [DetectedSubscription] }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return }
        detected = decoded.prompts
    }

    var detectedToOffer: [DetectedSubscription] {
        let have = Set(subscriptions.map { $0.name.lowercased() })
        return detected.filter { !have.contains($0.name.lowercased()) }
    }

    /// charges the bank calls subscriptions that aren't detected as repeating or already on the list
    var alsoMarkedToOffer: [BankCharge] {
        let have = Set(subscriptions.map { $0.name.lowercased() }).union(detected.map { $0.name.lowercased() })
        return bankCharges.filter { !have.contains($0.id) }
    }

    func add(_ charge: BankCharge) {
        subscriptions.append(QuizSubscription(name: charge.name, cost: charge.amount,
                                              dueDate: Self.nextDate(day: charge.dayOfMonth), fromBank: true))
    }

    func add(_ found: DetectedSubscription) {
        subscriptions.append(QuizSubscription(name: found.name, cost: (found.averageAmount * 100).rounded() / 100,
                                              dueDate: Self.nextDate(day: found.dayOfMonth), fromBank: true))
    }

    static func nextDate(day: Int, from now: Date = Date()) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month], from: now)
        let range = cal.range(of: .day, in: .month, for: now) ?? 1..<29
        comps.day = min(max(1, day), range.count)
        let thisMonth = cal.date(from: comps) ?? now
        return thisMonth >= cal.startOfDay(for: now) ? thisMonth : cal.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth
    }

    // MARK: Savings (the Plan tab)

    func loadPlan() async {
        guard plan == nil, let loaded = try? await PlanAPI.fetchPlan() else { return }
        let accounts = (try? await PlanAPI.fetchAccounts()) ?? []
        planBalances = Dictionary(accounts.compactMap(LinkedBalance.init).map { ($0.id, $0.balance) }, uniquingKeysWith: { a, _ in a })
        plan = loaded
    }

    /// set for testing and previews
    func setPlan(_ plan: Plan, balances: [String: Double] = [:]) {
        self.plan = plan
        planBalances = balances
    }

    var emergencySaved: Double {
        guard let plan else { return Self.amount(savedNow) ?? 0 }
        if let id = plan.emergencyFund.linkedAccountId, let balance = planBalances[id] { return balance }
        return planHasSavings ? plan.emergencyFund.saved : Self.amount(savedNow) ?? 0
    }

    /// the Plan tab already says what they have saved (so the quiz doesn't ask)
    var planHasSavings: Bool {
        guard let plan else { return false }
        return plan.emergencyFund.saved > 0 || plan.emergencyFund.linkedAccountId != nil || !plan.savingsGoals.isEmpty
    }

    func goalSaved(_ goal: SavingsGoal) -> Double {
        goal.linkedAccountId.flatMap { planBalances[$0] } ?? goal.saved
    }

    // MARK: Commute

    func estimateCommute() async {
        estimatingCommute = true
        commuteMessage = nil
        defer { estimatingCommute = false }
        let home = "\(finalCity), \(finalState)"
        do {
            let found = try await CommuteRoute.drive(from: home, to: workPlace)
            route = found
            commute.roundTripMiles = found.roundTripMiles
            commute.oneWayMinutes = found.oneWayMinutes
        } catch {
            commuteMessage = "Couldn't find a route from \(home) to \"\(workPlace)\". Check the city or zip."
            return
        }
        await loadPrices(mode: commute.mode, routeHasTolls: route?.hasTolls == true)
        commuteEstimated = true
    }

    /// the gas price for driving that isn't commuting (when there's no commute estimate)
    func loadGasPrice() async {
        if let running = fuelPriceLookup { await running.value; return }
        guard commute.fuelPrice <= 0 else { return }
        let lookup = Task { await loadPrices(mode: .drive, routeHasTolls: false) }
        fuelPriceLookup = lookup
        await lookup.value
        fuelPriceLookup = nil
    }

    private func loadPrices(mode: CommuteMode, routeHasTolls: Bool) async {
        do {
            let stateName = USState.all.first { $0.code == finalState }?.name ?? finalState
            let prices = try await PlanAPI.commutePrices(mode: mode, homeState: stateName, homeCity: finalCity,
                                                          workPlace: workPlace, electric: commute.car == .electric,
                                                          routeHasTolls: routeHasTolls)
            if let gas = prices["gas"]?["pricePerGallon"] { setLookedUpFuelPrice(gas, fromEIA: prices["gas"]?["fromEIA"] == 1) }
            if let kwh = prices["electricity"]?["pricePerKwh"] {
                setLookedUpFuelPrice(kwh, fromEIA: prices["electricity"]?["fromEIA"] == 1)
            }
            if let toll = prices["tolls"]?["oneWay"] { commute.tollsPerDay = (toll * 2 * 100).rounded() / 100 }
            if let transit = prices["transit"] {
                commute.transitMonthlyPass = transit["monthlyPass"] ?? 0
                commute.transitSingleFare = transit["singleFare"] ?? 0
            }
            if let ride = prices["rideshare"] {
                commute.rideshareBase = (ride["base"] ?? 0) + (ride["bookingFee"] ?? 0)
                commute.ridesharePerMile = ride["perMile"] ?? 0
                commute.ridesharePerMinute = ride["perMinute"] ?? 0
                commute.rideshareMinimum = ride["minimumFare"] ?? 0
            }
        } catch {
            commuteMessage = (error as? AILimitError)?.message ?? "Couldn't look up prices right now. You can type them in."
        }
    }

    // MARK: Building the budget

    /// what's sent to the server (the same keys earlier quizzes saved, plus the new ones)
    func payload() -> [String: Any] {
        let iso = ISO8601DateFormatter()
        let debtsPayload: [[String: Any]] = hasDebt ? debts.map { d in
            ["name": d.name, "principal": Double(d.principal) ?? 0, "apr": Double(d.apr) ?? 0,
             "minPayment": Double(d.minPayment) ?? 0, "dueDate": iso.string(from: d.dueDate)] as [String: Any]
        } : []
        let known: [String: Double] = knownCosts.reduce(into: [:]) { result, entry in
            if let value = Self.amount(entry.value), !answeredElsewhere.contains(entry.key) { result[entry.key] = value }
        }

        var housing: [String: Any] = ["situation": housingSituation, "utilitiesIncluded": utilitiesIncluded]
        if rents {
            if knowsShare { housing.setAmount("yourShare", yourShare) }
            else { housing.setAmount("totalRent", totalRent); housing["people"] = rentPeople }
            housing.setAmount("rentersInsurance", rentersInsurance)
        }
        if housingSituation == "Own with Mortgage" { housing.setAmount("mortgage", mortgage) }
        if !utilitiesIncluded { housing.setAmount("utilities", utilities) }
        // one "utilities & internet" amount; internet on its own only when utilities come with the rent
        housing["internetInUtilities"] = !utilitiesIncluded
        if utilitiesIncluded { housing.setAmount("internet", internet) }

        var work: [String: Any] = ["arrangement": workArrangement]
        if commutes {
            work["location"] = workPlace
            work["officeDays"] = workArrangement == "office" ? 5 : commute.officeDaysPerWeek
            work["mode"] = commute.mode.rawValue
            // the whole estimate, so updating another part of the quiz doesn't lose the commute
            if let inputs = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(commute)) { work["inputs"] = inputs }
            work["estimated"] = commuteEstimated
            // saved so the next quiz starts with them (they weren't, and the car went back to Sedan)
            work["parkingMonthly"] = commute.parkingMonthly
            work["carpoolPeople"] = commute.carpoolPeople
            work["passengerWeekly"] = commute.passengerWeekly
            if let monthly = commuteMonthly {
                work["commuteMonthly"] = (monthly.total * 100).rounded() / 100
                work["commuteSummary"] = monthly.summary
                if let split = commuteSplit {
                    work["commuteGas"] = (split.gas * 100).rounded() / 100
                    work["commuteOther"] = (split.other * 100).rounded() / 100
                }
            }
        }

        var pets: [[String: Any]] = []
        if dogs > 0 { pets.append(["type": "dog", "count": dogs]) }
        if cats > 0 { pets.append(["type": "cat", "count": cats]) }
        if otherPets > 0 { pets.append(["type": "other pet", "count": otherPets]) }
        // a blank amount is left out (estimated, or none), so a typed 0 still means 0 next time
        var other: [String: Any] = [
            "pets": pets,
            // a blank amount is estimated
            "yearly": yearlyCosts.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { cost -> [String: Any] in
                    var item: [String: Any] = ["name": cost.name, "timesPerYear": cost.timesPerYear]
                    if let amount = cost.amount, amount > 0 { item["amount"] = amount }
                    return item
                },
        ]
        other.setAmount("phone", phone)
        other.setAmount("gym", gym)
        other.setAmount("medical", medical)
        other.setAmount("petsMonthly", petsMonthly)
        if hasCar {
            other.setAmount("carPayment", carPayment)
            if let monthly = carInsuranceMonthly { other["carInsurance"] = (monthly * 100).rounded() / 100 }
            other.setAmount("carInsurancePayment", carInsurance)
            other["carInsuranceMonths"] = carInsuranceMonths
            if carInsuranceMonths > 1 { other["carInsuranceNextDue"] = Self.isoDay(carInsuranceNextDue) }
            if let gas = otherGasMonthly { other["otherGas"] = (gas * 100).rounded() / 100 }
            other.setAmount("otherMilesPerWeek", otherMilesPerWeek)
        }

        // the last step's choices, plus what the earlier answers call for (or exactly the budget page's)
        var categories = exactCategories.map { Set($0).subtracting(Self.trackerExclusions) }
            ?? selectedCategories.subtracting(Self.trackerExclusions).subtracting(answeredElsewhere).union(derivedCategories)
        // a once-a-year cost with the same name is its own line already (Car Maintenance)
        let yearlyNames = Set(yearlyCosts.map { $0.name.lowercased() })
        if exactCategories == nil { categories = categories.filter { !yearlyNames.contains($0.lowercased()) } }
        if !hasCar { categories.subtract(Self.carCategories) }

        return [
            "username": username,
            "yearlyIncome": yearlyIncome,
            "401(k) Contribution": retirement.isEmpty ? "0" : retirement,
            "dependents": String(dependentsCount),
            "city": finalCity,
            "state": finalState,
            "spendingStyle": "Medium",                 // older servers; the budgeting style replaced it
            "budgetingStyle": budgetingStyle.rawValue,
            "savePercent": savePercent,
            "primaryGoal": primaryGoal,
            "savingsPriority": savingsPriority,
            "housingSituation": housingSituation,
            "carOwnership": carOwnership,
            "carType": commute.car.rawValue,                // what they drive: its miles per gallon
            "fuelPriceTheirs": fuelPriceSource == .yours,   // a price they typed is kept; a looked-up one is refreshed
            "eatingOutFrequency": eatingOutFrequency,
            "useDeviceLocation": useDeviceLocation,
            "categories": Array(categories.sorted()),
            "knownCosts": known,
            "hasDebt": hasDebt,
            "debts": debtsPayload,
            "housing": housing,
            "work": work,
            "insurance": (["payFrequency": payFrequency.rawValue] as [String: Any])
                .merging(["health": Self.amount(healthPerCheck), "dental": Self.amount(dentalPerCheck),
                          "vision": Self.amount(visionPerCheck)].compactMapValues { $0 }) { a, _ in a },
            // 2: blank amounts are left out and a typed 0 is 0 (older answers saved blanks as 0)
            "answersVersion": 2,
            "exactCategories": exactCategories != nil,
            "newCategories": newCategories,
            "payFrequency": payFrequency.rawValue,
            "otherCosts": other,
            "subscriptions": subscriptions.map { ["name": $0.name, "cost": $0.cost] as [String: Any] },
            "bankAverages": sortedBankAverages.filter { !bankOverrides.contains($0.key) },
            "bankEdits": bankEdits,
            "household": household(),
            "billDueDays": billDueDays,
            "declinedBankCategories": Array(declinedBankCategories).sorted(),
            "withDetails": true,
        ].merging(savingsPayload().map { ["savings": $0] } ?? [:]) { a, _ in a }
    }

    private func household() -> [String: Any] {
        var out: [String: Any] = ["under5": under5, "age5to12": age5to12, "age13to17": age13to17, "adults": adultDependents]
        if kidsUnder13 > 0, let amount = Self.amount(childcare) { out["childcare"] = amount }
        return out
    }

    /// what they have saved and are saving for (nil when the Plan tab didn't load and nothing was typed)
    private func savingsPayload() -> [String: Any]? {
        guard plan != nil || Self.amount(savedNow) != nil else { return nil }
        let goals: [[String: Any]] = (plan?.savingsGoals ?? []).map { goal in
            var g: [String: Any] = ["name": goal.name, "target": goal.target, "saved": goalSaved(goal)]
            if let date = goal.targetDate { g["targetDate"] = date }
            if let needed = goal.monthlyNeeded(saved: goalSaved(goal)) { g["monthlyNeeded"] = (needed * 100).rounded() / 100 }
            return g
        }
        return ["emergencySaved": emergencySaved, "emergencyMonths": plan?.emergencyFund.months ?? 3, "goals": goals]
    }

    /// the AI's budget, for the review screen
    struct Draft: Decodable {
        let budget: [String: Double]
        let why: [String: String]
        let monthlyNet: Double
        let budgetingStyle: String?
        let savePercent: Double?
        /// lines the AI couldn't change (bills they told us, debt minimums)
        var fixed: [String]? = nil
        /// take-home numbers saved with the answers (monthlyNet, afterTaxYearly, k401Monthly)
        var answers: [String: Double]? = nil
        /// where they usually spend more than this plan, and what they usually spend in all (from their transactions)
        var overspending: [Overspend]? = nil
        var usualTotal: Double? = nil
    }

    struct Overspend: Decodable, Equatable {
        let category: String
        let usual: Double
        let planned: Double
    }

    /// `overrides`: amounts changed on the review screen, kept exactly ("Rebuild with AI")
    func build(overrides: [String: Double] = [:]) async throws -> Draft {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/llm/budget") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = payload()
        if !overrides.isEmpty { body["reviewOverrides"] = overrides }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 90
        let (data, response) = try await URLSession.shared.data(for: request)
        if let limit = AILimitError.from(data, response) { throw limit }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Draft.self, from: data)
    }

    // MARK: Saving (after the review)

    /// nothing was saved when the budget was built: this saves the reviewed budget and the answers
    func save(budget: [String: Double], draft: Draft, calendarVM: CalendarViewModel) async throws {
        var answers = payload()
        answers["withDetails"] = nil
        for (key, value) in draft.answers ?? ["monthlyNet": draft.monthlyNet] { answers[key] = value }
        do {
            try await postJSON("/api/llm/budget/save", ["username": username, "budget": budget, "answers": answers])
        } catch is SaveNotFound {
            // a server from before the review screen already saved the quiz when it built it
            try await postJSON("/api/budget", ["username": username, "type": "monthly", "budget": budget])
        }

        // the transactions the quiz looked at go into Monthly Costs (no separate sync needed); after the
        // save, so its fixed costs (rent, savings...) are known and those charges aren't counted twice
        if bankLinked { await importTransactions() }

        // the spending tracker starts with the budget's categories at $0
        var zeros = Dictionary(uniqueKeysWithValues: budget.keys.filter { !Self.trackerExclusions.contains($0) }.map { ($0, 0.0) })
        for d in debts where hasDebt && !d.name.trimmingCharacters(in: .whitespaces).isEmpty { zeros["Debt - \(d.name)"] = 0 }
        try? await postJSON("/api/costs", ["username": username, "type": "monthly", "costs": zeros])

        // asked once, before anything schedules a reminder
        let allowed = await NotificationPermission.ensure(for: "bill and subscription reminders and a check-in on your budget")
        await saveSubscriptions(calendarVM: calendarVM)
        await saveSavingsToPlan()
        syncBills(budget: budget, calendarVM: calendarVM)
        if allowed {
            await remindBeforeLoansStart()
            await scheduleCheckIn()
        }
        clearDraft()
        UserDefaults.standard.set(true, forKey: "budgetQuizCompleted")
        NotificationCenter.default.post(name: .budgetQuizCompleted, object: nil)
    }

    /// what they typed as saved goes to the Plan tab's emergency fund (only when the Plan had nothing)
    private func saveSavingsToPlan() async {
        guard var plan, !planHasSavings, let amount = Self.amount(savedNow), amount > 0 else { return }
        plan.emergencyFund.saved = amount
        do {
            try await PlanAPI.savePlan(plan)
            self.plan = plan
        } catch {
            AppBanner.report("save your savings to your Plan", error)
        }
    }

    // MARK: Bills on the calendar

    struct Bill: Equatable {
        let name: String         // the calendar event's title
        let day: Int             // of the month
        let amount: Double       // per payment
        let eventType: String    // "rent" (housing, shown in red) or "bill"
        var recurrence = "monthly"
        var firstDate: Date? = nil  // a bill that isn't monthly starts on its next due date
    }

    static func isoDay(_ date: Date) -> String { Recurrence.dayKey(date) }

    static let billMarker = "Bill from your budget"

    /// the bills with a due day, at the budget's amounts
    func bills(budget: [String: Double]) -> [Bill] {
        var out: [Bill] = []
        func add(_ name: String, type: String = "bill", when applies: Bool = true) {
            guard applies, let day = billDueDays[name] else { return }
            out.append(Bill(name: name, day: day, amount: budget[name] ?? 0, eventType: type))
        }
        add("Rent", type: "rent", when: rents)
        add("Mortgage", type: "rent", when: housingSituation == "Own with Mortgage")
        add("Utilities", when: !utilitiesIncluded && housingSituation != "Other")
        add("Internet", when: utilitiesIncluded && housingSituation != "Other" && !internet.isEmpty)
        add("Phone")
        add("Car Payment", when: hasCar)
        if hasCar && carInsuranceMonths > 1 {
            out.append(Bill(name: "Car Insurance", day: Calendar.current.component(.day, from: carInsuranceNextDue),
                            amount: Self.amount(carInsurance) ?? 0, eventType: "bill",
                            recurrence: carInsuranceMonths == 12 ? "yearly" : "every-6-months",
                            firstDate: Calendar.current.startOfDay(for: carInsuranceNextDue)))
        } else {
            add("Car Insurance", when: hasCar)
        }
        if hasDebt {
            for debt in debts where !debt.name.trimmingCharacters(in: .whitespaces).isEmpty {
                let day = Calendar.current.component(.day, from: debt.dueDate)
                let amount = budget["Debt - \(debt.name)"] ?? Double(debt.minPayment) ?? 0
                out.append(Bill(name: "\(debt.name) payment", day: day, amount: amount, eventType: "bill"))
            }
        }
        return out
    }

    /// a monthly calendar event for each bill, with a reminder the day before; ones the quiz added
    /// earlier are replaced when their day or amount changed, and removed when the bill is gone
    private func syncBills(budget: [String: Double], calendarVM: CalendarViewModel) {
        let wanted = bills(budget: budget)
        let existing = calendarVM.seriesById.values.filter {
            ($0.eventType == "rent" || $0.eventType == "bill") && $0.description.hasPrefix(Self.billMarker)
        }
        func matches(_ event: Event, _ bill: Bill) -> Bool {
            bill.name.lowercased() == event.title.lowercased()
                && event.recurrence == bill.recurrence
                && event.description == Self.billDescription(bill)
                && (bill.firstDate.map { Recurrence.dayKey($0) == Recurrence.dayKey(event.startDate) }
                    ?? (Calendar.current.component(.day, from: event.startDate) == bill.day))
        }
        for event in existing where !wanted.contains(where: { matches(event, $0) }) {
            calendarVM.deleteEvent(event.id)
        }
        for bill in wanted where !existing.contains(where: { matches($0, bill) }) {
            let day = bill.firstDate ?? Self.nextDate(day: bill.day)
            let start = Calendar.current.date(byAdding: .hour, value: 9, to: day) ?? day
            calendarVM.createEvent(title: bill.name, description: Self.billDescription(bill), startDate: start, endDate: start,
                                   eventType: bill.eventType, recurrence: bill.recurrence, invitedFriends: [], friendsCanSee: false,
                                   reminders: [86_400])
        }
    }

    static func billDescription(_ bill: Bill) -> String {
        let every = bill.recurrence == "every-6-months" ? "every 6 months" : bill.recurrence == "yearly" ? "a year" : "a month"
        return bill.amount > 0 ? "\(billMarker): \(bill.amount.dollars()) \(every)" : billMarker
    }

    // MARK: One-month check-in

    static let checkInId = "budget-checkin"

    /// a month after saving: "How did your budget do?" (opens Budget, where the tune-up card is)
    private func scheduleCheckIn() async {
        let content = UNMutableNotificationContent()
        content.title = "How did your budget do?"
        content.body = bankLinked
            ? "See how your first month compares with your plan, and tune it in a tap."
            : "Compare what you spent with your plan. Linking a bank or card makes this automatic."
        content.sound = .default
        content.userInfo = ["destination": "budget"]
        guard let day = Calendar.current.date(byAdding: .day, value: 30, to: Date()) else { return }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: day)
        comps.hour = 18
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.checkInId])
        try? await center.add(UNNotificationRequest(identifier: Self.checkInId, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    // MARK: Unfinished quiz (kept on the phone)

    private var draftKey: String { "budgetQuizDraft.\(username.lowercased())" }

    /// answers so far, so leaving partway doesn't lose them
    func saveDraft() {
        var draft = payload()
        let iso = ISO8601DateFormatter()
        draft["draftStep"] = step.rawValue
        draft["draftStepName"] = step.key
        draft["draftSubscriptions"] = subscriptions.map { ["name": $0.name, "cost": $0.cost, "dueDate": iso.string(from: $0.dueDate),
                                                           "fromBank": $0.fromBank] as [String: Any] }
        draft["draftSavedNow"] = savedNow
        draft["draftChildcare"] = childcare
        draft["draftCommuteEstimated"] = commuteEstimated
        if let commuteData = try? JSONEncoder().encode(commute),
           let commuteJSON = try? JSONSerialization.jsonObject(with: commuteData) { draft["draftCommute"] = commuteJSON }
        if let data = try? JSONSerialization.data(withJSONObject: draft) { UserDefaults.standard.set(data, forKey: draftKey) }
    }

    /// an unfinished quiz's answers, if there is one
    func savedDraft() -> [String: Any]? {
        guard let data = UserDefaults.standard.data(forKey: draftKey) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func clearDraft() { UserDefaults.standard.removeObject(forKey: draftKey) }

    /// pick up where they left off
    func resume(_ draft: [String: Any]) {
        let wasSaved = hasSavedQuiz
        restore(draft)
        hasSavedQuiz = wasSaved
        let iso = ISO8601DateFormatter()
        if let subs = draft["draftSubscriptions"] as? [[String: Any]] {
            subscriptions = subs.map {
                QuizSubscription(name: $0["name"] as? String ?? "", cost: ($0["cost"] as? NSNumber)?.doubleValue ?? 0,
                                 dueDate: iso.date(from: $0["dueDate"] as? String ?? "") ?? Date(), fromBank: $0["fromBank"] as? Bool ?? false)
            }
        }
        savedNow = draft["draftSavedNow"] as? String ?? ""
        childcare = draft["draftChildcare"] as? String ?? ""
        if let commuteJSON = draft["draftCommute"], let data = try? JSONSerialization.data(withJSONObject: commuteJSON),
           let decoded = try? JSONDecoder().decode(CommuteInputs.self, from: data) {
            commute = decoded
            commuteEstimated = draft["draftCommuteEstimated"] as? Bool ?? false
            // a looked-up gas price is looked up again (a typed one is kept)
            if draft["fuelPriceTheirs"] as? Bool != true { commute.fuelPrice = 0 }
        }
        if let saved = (draft["draftStepName"] as? String).flatMap(QuizStep.named) ?? (draft["draftStep"] as? NSNumber).flatMap({ QuizStep(rawValue: min($0.intValue, QuizStep.allCases.count - 1)) }) {
            step = saved
        }
    }

    /// the quiz's list becomes the Subscriptions page's list, with a calendar event and reminder for each new one
    private func saveSubscriptions(calendarVM: CalendarViewModel) async {
        guard subscriptionsLoaded else { return } // never overwrite a list that didn't load
        var dict: [String: SubscriptionData] = [:]
        for sub in subscriptions where !sub.name.trimmingCharacters(in: .whitespaces).isEmpty {
            dict[sub.name] = SubscriptionData(name: sub.name, cost: String(format: "%.2f", sub.cost), dueDate: sub.dueDate)
        }
        do {
            // the same format the Subscriptions page saves
            guard let url = URL(string: "\(BackendConfig.baseURLString)/api/subscriptions") else { return }
            var request = URLRequest(url: url)
            BackendConfig.addApiKey(to: &request)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(SubscriptionUpload(username: username, subscriptions: dict))
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        } catch {
            AppBanner.report("save your subscriptions", error)
            return
        }
        let now = Set(subscriptions.map { $0.name.lowercased() })
        let added = subscriptions.filter { !originalSubscriptionNames.contains($0.name.lowercased()) }
        let removed = originalSubscriptionNames.subtracting(now)
        for sub in added {
            calendarVM.createEvent(title: sub.name, description: "Subscription reminder (\(sub.cost.dollars(cents: true)))",
                                   startDate: sub.dueDate, endDate: sub.dueDate, eventType: "subscription",
                                   recurrence: "monthly", invitedFriends: [])
            SubscriptionReminders.schedule(name: sub.name, dueDate: sub.dueDate)
        }
        for name in removed {
            for event in calendarVM.seriesById.values where event.eventType.lowercased().hasPrefix("subscription")
                && event.title.lowercased() == name {
                calendarVM.deleteEvent(event.id)
            }
            SubscriptionReminders.cancel(name: name)
        }
        originalSubscriptionNames = now
    }

    /// a loan whose first payment is weeks away isn't in the budget yet: a reminder a week before it starts
    /// (notifications were already allowed in save)
    private func remindBeforeLoansStart() async {
        guard hasDebt else { return }
        let later = debts.filter { $0.dueDate > Date().addingTimeInterval(45 * 86400) && !$0.name.isEmpty }
        guard !later.isEmpty else { return }
        for debt in later {
            guard let remindAt = Calendar.current.date(byAdding: .day, value: -7, to: debt.dueDate) else { continue }
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: remindAt)
            comps.hour = 9
            let content = UNMutableNotificationContent()
            content.title = "Loan payments start soon"
            content.body = "Your \(debt.name) payment is due \(debt.dueDate.formatted(date: .abbreviated, time: .omitted)). Update your budget quiz to include it."
            content.sound = .default
            content.userInfo = ["destination": "budget"]
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: "loan-start-\(debt.name.lowercased())", content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }

    private struct SaveNotFound: Error { }

    /// the last 90 days of bank or card transactions into Monthly Costs (ones already there aren't added
    /// again). By date, so earlier syncs from Monthly Costs don't cut it short; an older server only has sync.
    private func importTransactions() async {
        do {
            do {
                // with their removes and moves from the quiz
                try await postJSON("/api/plaid/import-history", ["username": username, "days": 90, "edits": bankEdits])
            } catch {
                try await postJSON("/api/plaid/sync", ["username": username, "days": 90])
            }
        } catch {
            AppBanner.report("bring in your transactions (you can sync from Monthly Costs)", error)
        }
    }

    private func postJSON(_ path: String, _ body: [String: Any]) async throws {
        guard let url = URL(string: "\(BackendConfig.baseURLString)\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if (response as? HTTPURLResponse)?.statusCode == 404 && path == "/api/llm/budget/save" { throw SaveNotFound() }
            throw AILimitError.from(data, response) ?? URLError(.badServerResponse)
        }
    }

    // MARK: Last answers

    func loadSavedQuiz() async {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/llm/budget/last/\(username)") else { return }
        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any], !dict.isEmpty else { return }
        restore(dict)
    }

    /// an amount as typed: answers saved before version 2 used 0 for blank, so there 0 reads as blank
    private static func text(_ value: Any?, keepZero: Bool = false) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let n = value as? NSNumber { return n.doubleValue == 0 && !keepZero ? "" : n.stringValue }
        return String(describing: value)
    }

    func restore(_ dict: [String: Any]) {
        let keepZero = ((dict["answersVersion"] as? NSNumber)?.intValue ?? 1) >= 2
        let text = { (value: Any?) in Self.text(value, keepZero: keepZero) }
        hasSavedQuiz = true
        savedMonthlyNet = (dict["monthlyNet"] as? NSNumber)?.doubleValue
        yearlyIncome = text(dict["yearlyIncome"])
        retirement = text(dict["401(k) Contribution"])
        if let h = dict["household"] as? [String: Any] {
            under5 = (h["under5"] as? NSNumber)?.intValue ?? 0
            age5to12 = (h["age5to12"] as? NSNumber)?.intValue ?? 0
            age13to17 = (h["age13to17"] as? NSNumber)?.intValue ?? 0
            adultDependents = (h["adults"] as? NSNumber)?.intValue ?? 0
            if let c = h["childcare"] as? NSNumber { childcare = c.doubleValue == 0 ? "0" : c.stringValue }
        }
        legacyDependents = under5 + age5to12 + age13to17 + adultDependents > 0 ? 0 : Int(text(dict["dependents"])) ?? 0
        if let declined = dict["declinedBankCategories"] as? [String] { declinedBankCategories = Set(declined) }
        if let edits = dict["bankEdits"] as? [String: String] { bankEdits = edits }
        if let days = dict["billDueDays"] as? [String: Any] {
            billDueDays = days.compactMapValues { ($0 as? NSNumber)?.intValue }
        }
        let savedPlace = Self.place(city: dict["city"] as? String ?? "", state: dict["state"] as? String ?? "")
        city = savedPlace.city
        state = savedPlace.state
        manualCity = city
        manualState = state
        if let flag = dict["useDeviceLocation"] as? Bool { useDeviceLocation = flag }

        if let cats = dict["categories"] as? [String] {
            let filtered = cats.filter { !Self.trackerExclusions.contains($0) }
            allCategories = Array(Set(allCategories).union(filtered))
            selectedCategories = Set(filtered)
        }
        if let kc = dict["knownCosts"] as? [String: Any] {
            knownCosts = kc.mapValues { text($0) }.filter { !$0.value.isEmpty }
        }
        if let hasDebtSaved = dict["hasDebt"] as? Bool { hasDebt = hasDebtSaved }
        if let savedDebts = dict["debts"] as? [[String: Any]] {
            let iso = ISO8601DateFormatter()
            debts = savedDebts.map { d in
                DebtItem(name: d["name"] as? String ?? "", principal: text(d["principal"]), apr: text(d["apr"]),
                         minPayment: text(d["minPayment"] ?? d["minMonthly"]),
                         dueDate: iso.date(from: d["dueDate"] as? String ?? "") ?? Date())
            }
        }
        if let v = dict["primaryGoal"] as? String, !v.isEmpty { primaryGoal = v }
        if let v = dict["savingsPriority"] as? String, !v.isEmpty { savingsPriority = v }
        if let v = dict["housingSituation"] as? String, !v.isEmpty { housingSituation = v }
        if let v = dict["carOwnership"] as? String, !v.isEmpty { carOwnership = v }
        if let v = dict["eatingOutFrequency"] as? String, !v.isEmpty { eatingOutFrequency = v }
        if let v = (dict["budgetingStyle"] as? String).flatMap(BudgetingStyleChoice.init(rawValue:)) { budgetingStyle = v }
        else if let old = dict["spendingStyle"] as? String {
            // older quizzes: Low saved the most, High spent the most
            budgetingStyle = old == "Low" ? .payYourselfFirst : .flexible
        }
        if let v = (dict["savePercent"] as? NSNumber)?.doubleValue, v > 0 { savePercent = v }
        if let pay = (dict["payFrequency"] as? NSNumber)?.intValue, let f = PayFrequency(rawValue: pay) { payFrequency = f }
        if let ins = dict["insurance"] as? [String: Any] {
            healthPerCheck = text(ins["health"]); dentalPerCheck = text(ins["dental"]); visionPerCheck = text(ins["vision"])
        }
        if let h = dict["housing"] as? [String: Any] {
            yourShare = text(h["yourShare"])
            knowsShare = !yourShare.isEmpty
            totalRent = text(h["totalRent"])
            rentPeople = max(1, (h["people"] as? NSNumber)?.intValue ?? 1)
            mortgage = text(h["mortgage"])
            utilitiesIncluded = h["utilitiesIncluded"] as? Bool ?? false
            utilities = text(h["utilities"])
            internet = text(h["internet"])
            if !utilitiesIncluded, h["internetInUtilities"] as? Bool != true, !internet.isEmpty {
                // an older quiz asked for internet on its own: it's part of Utilities now (left out when
                // utilities were blank, since both are estimated together)
                if let u = Self.amount(utilities), let i = Self.amount(internet) { utilities = Self.text(NSNumber(value: u + i)) }
                internet = ""
            }
            rentersInsurance = text(h["rentersInsurance"])
        }
        if let w = dict["work"] as? [String: Any] {
            workArrangement = w["arrangement"] as? String ?? "office"
            workPlace = w["location"] as? String ?? ""
            if let days = (w["officeDays"] as? NSNumber)?.doubleValue, days > 0 { commute.officeDaysPerWeek = days }
            if let mode = (w["mode"] as? String).flatMap(CommuteMode.init(rawValue:)) { commute.mode = mode }
            if let parking = (w["parkingMonthly"] as? NSNumber)?.doubleValue { commute.parkingMonthly = parking }
            if let people = (w["carpoolPeople"] as? NSNumber)?.doubleValue, people >= 2 { commute.carpoolPeople = people }
            if let weekly = (w["passengerWeekly"] as? NSNumber)?.doubleValue { commute.passengerWeekly = weekly }
            if let inputs = w["inputs"], let data = try? JSONSerialization.data(withJSONObject: inputs),
               let saved = try? JSONDecoder().decode(CommuteInputs.self, from: data) {
                commute = saved
                commuteEstimated = w["estimated"] as? Bool ?? false
                // prices change: a looked-up one is looked up again when the quiz opens
                if dict["fuelPriceTheirs"] as? Bool != true { commute.fuelPrice = 0 }
            }
            if let v = (dict["carType"] as? String).flatMap(CarType.init(rawValue:)) { commute.car = v }
        }
        if let o = dict["otherCosts"] as? [String: Any] {
            phone = text(o["phone"]); gym = text(o["gym"]); medical = text(o["medical"])
            petsMonthly = text(o["petsMonthly"])
            carPayment = text(o["carPayment"])
            carInsurance = text(o["carInsurancePayment"] ?? o["carInsurance"])
            let months = (o["carInsuranceMonths"] as? NSNumber)?.intValue ?? 1
            carInsuranceMonths = [1, 6, 12].contains(months) ? months : 1
            if let next = (o["carInsuranceNextDue"] as? String).flatMap(Plan.day) {
                // the next payment after the saved one
                var due = next
                while due < Calendar.current.startOfDay(for: Date()) {
                    due = Calendar.current.date(byAdding: .month, value: carInsuranceMonths, to: due) ?? Date()
                }
                carInsuranceNextDue = due
            }
            otherMilesPerWeek = text(o["otherMilesPerWeek"])
            for pet in o["pets"] as? [[String: Any]] ?? [] {
                let count = (pet["count"] as? NSNumber)?.intValue ?? 0
                switch pet["type"] as? String {
                case "dog": dogs = count
                case "cat": cats = count
                default: otherPets = count
                }
            }
            yearlyCosts = (o["yearly"] as? [[String: Any]] ?? []).map {
                YearlyCost(name: $0["name"] as? String ?? "", amount: ($0["amount"] as? NSNumber)?.doubleValue,
                           timesPerYear: max(1, ($0["timesPerYear"] as? NSNumber)?.intValue ?? 1))
            }
        }
        // older quizzes asked these again on the last step: keep what was typed there, in its own question
        let moved: [(ReferenceWritableKeyPath<BudgetQuizModel, String>, String)] = [
            (\.phone, "Phone"), (\.gym, "Gym"), (\.medical, "Medical"), (\.carInsurance, "Car Insurance"), (\.carPayment, "Car Payment"),
        ]
        for (field, key) in moved where self[keyPath: field].isEmpty {
            if let typed = knownCosts[key], !typed.isEmpty { self[keyPath: field] = typed }
        }
        refreshTakeHome()
    }
}

/// the monthly "due tomorrow" reminder for a subscription (the same one the Subscriptions page sets)
enum SubscriptionReminders {
    static func identifier(_ name: String) -> String { "subscription-reminder-\(name.lowercased())" }

    static func schedule(name: String, dueDate: Date) {
        var comps = Calendar.current.dateComponents([.day], from: dueDate)
        let day = comps.day ?? 1
        comps.day = day == 1 ? 1 : day - 1
        comps.hour = 9
        comps.minute = 0
        let content = UNMutableNotificationContent()
        content.title = "Subscription Reminder"
        content.body = day == 1 ? "\(name) is due today." : "\(name) is due tomorrow."
        content.sound = .default
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier(name)])
        center.add(UNNotificationRequest(identifier: identifier(name), content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
    }

    static func cancel(name: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(name)])
    }
}

struct USState: Identifiable {
    let id = UUID()
    let name: String
    let code: String

    static let all: [USState] = [
        .init(name: "Alabama", code: "AL"), .init(name: "Alaska", code: "AK"),
        .init(name: "Arizona", code: "AZ"), .init(name: "Arkansas", code: "AR"),
        .init(name: "California", code: "CA"), .init(name: "Colorado", code: "CO"),
        .init(name: "Connecticut", code: "CT"), .init(name: "Delaware", code: "DE"),
        .init(name: "District of Columbia", code: "DC"), .init(name: "Florida", code: "FL"),
        .init(name: "Georgia", code: "GA"), .init(name: "Hawaii", code: "HI"),
        .init(name: "Idaho", code: "ID"), .init(name: "Illinois", code: "IL"),
        .init(name: "Indiana", code: "IN"), .init(name: "Iowa", code: "IA"),
        .init(name: "Kansas", code: "KS"), .init(name: "Kentucky", code: "KY"),
        .init(name: "Louisiana", code: "LA"), .init(name: "Maine", code: "ME"),
        .init(name: "Maryland", code: "MD"), .init(name: "Massachusetts", code: "MA"),
        .init(name: "Michigan", code: "MI"), .init(name: "Minnesota", code: "MN"),
        .init(name: "Mississippi", code: "MS"), .init(name: "Missouri", code: "MO"),
        .init(name: "Montana", code: "MT"), .init(name: "Nebraska", code: "NE"),
        .init(name: "Nevada", code: "NV"), .init(name: "New Hampshire", code: "NH"),
        .init(name: "New Jersey", code: "NJ"), .init(name: "New Mexico", code: "NM"),
        .init(name: "New York", code: "NY"), .init(name: "North Carolina", code: "NC"),
        .init(name: "North Dakota", code: "ND"), .init(name: "Ohio", code: "OH"),
        .init(name: "Oklahoma", code: "OK"), .init(name: "Oregon", code: "OR"),
        .init(name: "Pennsylvania", code: "PA"), .init(name: "Rhode Island", code: "RI"),
        .init(name: "South Carolina", code: "SC"), .init(name: "South Dakota", code: "SD"),
        .init(name: "Tennessee", code: "TN"), .init(name: "Texas", code: "TX"),
        .init(name: "Utah", code: "UT"), .init(name: "Vermont", code: "VT"),
        .init(name: "Virginia", code: "VA"), .init(name: "Washington", code: "WA"),
        .init(name: "West Virginia", code: "WV"), .init(name: "Wisconsin", code: "WI"),
        .init(name: "Wyoming", code: "WY")
    ]
}

struct DebtItem: Identifiable, Codable {
    var id = UUID()
    var name: String = ""
    var principal: String = ""
    var apr: String = ""
    var minPayment: String = ""
    var dueDate: Date = Date()
}

extension Dictionary where Key == String, Value == Any {
    /// an amount as typed: left out when blank (so a blank isn't saved as 0)
    mutating func setAmount(_ key: String, _ raw: String) {
        if let value = BudgetQuizModel.amount(raw) { self[key] = value }
    }
}
