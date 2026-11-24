//
//  QuizTests.swift
//  PlotLineTests
//
//  The budget quiz: commute estimate, saved answers, the quiz model and the review checks.
//

import Testing
import Foundation
@testable import PlotLine

struct CommuteCostTests {
    @Test("Driving: miles ÷ mpg × gas, plus tolls and parking; a carpool splits it")
    func drive() {
        var c = CommuteInputs(mode: .drive, officeDaysPerWeek: 3, roundTripMiles: 30, car: .sedan, fuelPrice: 3.0,
                              parkingMonthly: 50, tollsPerDay: 4)
        let days = 3.0 * 52 / 12                         // 13 office days a month
        let fuel = 30 * days / 30 * 3.0                  // a gallon a day at 30 mpg
        let expected = fuel + 4 * days + 50
        #expect(abs(CommuteCost.monthly(c).total - expected) < 0.01)
        #expect(CommuteCost.monthly(c).summary.contains("tolls"))

        c.mode = .carpoolDriver
        c.carpoolPeople = 3
        #expect(abs(CommuteCost.monthly(c).total - expected / 3) < 0.01)

        c.mode = .drive
        c.car = .electric
        c.fuelPrice = 0.17                               // per kWh, 3.5 miles per kWh
        #expect(abs(CommuteCost.monthly(c).total - (30 * days / 3.5 * 0.17 + 4 * days + 50)) < 0.01)
    }

    @Test("Transit: the cheaper of a monthly pass or paying per ride")
    func transit() {
        var c = CommuteInputs(mode: .transit, officeDaysPerWeek: 5, transitMonthlyPass: 100, transitSingleFare: 2.75)
        #expect(CommuteCost.monthly(c).total == 100)                      // 43 rides would cost more
        c.officeDaysPerWeek = 1
        #expect(abs(CommuteCost.monthly(c).total - 2.75 * 2 * 52 / 12) < 0.01) // ~9 rides: pay per ride
    }

    @Test("Rideshare: base + per mile + per minute, at least the minimum, both ways")
    func rideshare() {
        let c = CommuteInputs(mode: .rideshare, officeDaysPerWeek: 2, roundTripMiles: 10, oneWayMinutes: 15,
                              rideshareBase: 4.5, ridesharePerMile: 1.3, ridesharePerMinute: 0.35, rideshareMinimum: 8)
        let oneWay = 4.5 + 1.3 * 5 + 0.35 * 15           // $16.25
        #expect(abs(CommuteCost.monthly(c).total - oneWay * 2 * 2 * 52 / 12) < 0.01)
    }

    @Test("Passengers pay what they chip in; biking is free")
    func others() {
        #expect(abs(CommuteCost.monthly(CommuteInputs(mode: .carpoolPassenger, passengerWeekly: 20)).total - 20 * 52 / 12) < 0.01)
        #expect(CommuteCost.monthly(CommuteInputs(mode: .bikeWalk)).total == 0)
    }
}

struct QuizAnswerTests {
    @Test("Quiz debts use the minimum the app saved (\"minPayment\"), older ones \"minMonthly\"")
    func debtsFromQuiz() {
        let answers = PlanAPI.quizAnswers([
            "yearlyIncome": "62000", "state": "VA", "401(k) Contribution": 5,
            "debts": [["name": "Card", "principal": 2000, "apr": 24, "minPayment": 75],
                      ["name": "Loan", "principal": "9000", "apr": 5, "minMonthly": 110]],
        ])
        #expect(answers.yearlyIncome == 62000)
        #expect(answers.debts.map(\.minPayment) == [75, 110])
    }
}

struct BudgetReviewTests {
    @Test("Lines sort into needs, wants and savings; debt payments are needs")
    func kinds() {
        #expect(BudgetReview.kind(of: "Rent") == .need)
        #expect(BudgetReview.kind(of: "Debt - Chase Card") == .need)
        #expect(BudgetReview.kind(of: "Roth IRA") == .saving)
        #expect(BudgetReview.kind(of: "Eating Out") == .want)
        #expect(BudgetReview.kind(of: "Pet Care") == .need)
    }

    @Test("Summary: total, what's left, housing and savings as a share of take-home")
    func summary() {
        let s = BudgetReview.summary(["Rent": 1200, "Utilities": 100, "Groceries": 400, "Eating Out": 300, "Savings": 500],
                                     takeHome: 4000)
        #expect(s.total == 2500)
        #expect(s.unassigned == 1500)
        #expect(s.housingShare == 1300.0 / 4000)
        #expect(s.savingsShare == 0.125)
        #expect(s.byKind[.need] == 1700)
        #expect(s.byKind[.want] == 300)
    }

    @Test("Over take-home is the one severe warning; housing over 35% and low savings are flagged")
    func warnings() {
        let over = BudgetReview.summary(["Rent": 2000, "Eating Out": 2500], takeHome: 4000)
        let w = BudgetReview.warnings(over, style: .flexible, savePercent: 20)
        #expect(w.first?.severe == true)
        #expect(w.first?.text.contains("$500") == true)
        #expect(w.contains { $0.text.contains("Housing is 50%") })
        #expect(w.contains { $0.text.contains("10–20%") })
        #expect(w.filter(\.severe).count == 1)
    }

    @Test("Each style checks its own plan")
    func styles() {
        let s = BudgetReview.summary(["Rent": 1000, "Groceries": 1400, "Eating Out": 1000, "Savings": 600], takeHome: 4000)
        // 50/30/20: needs 60%, savings 15%
        let fifty = BudgetReview.warnings(s, style: .fiftyThirtyTwenty, savePercent: 20).map(\.text)
        #expect(fifty.contains { $0.contains("Needs are 60%") })
        #expect(fifty.contains { $0.contains("your plan is 20%") })
        // pay yourself first at 15%: on plan
        #expect(!BudgetReview.warnings(s, style: .payYourselfFirst, savePercent: 15).contains { $0.text.contains("saving") })
        // every dollar: all $4,000 assigned, nothing to flag about unassigned money
        #expect(!BudgetReview.warnings(s, style: .everyDollar, savePercent: 20).contains { $0.text.contains("isn't assigned") })
        let short = BudgetReview.summary(["Rent": 1000, "Savings": 600], takeHome: 4000)
        #expect(BudgetReview.warnings(short, style: .everyDollar, savePercent: 20).contains { $0.text.contains("$2,400 isn't assigned") })
    }
}

@MainActor
struct BudgetQuizModelTests {
    @Test("Once-a-year costs become a monthly amount")
    func yearly() {
        let model = BudgetQuizModel()
        model.yearlyCosts = [YearlyCost(name: "Car registration", amount: 120), YearlyCost(name: "Trips", amount: 600, timesPerYear: 2)]
        #expect(model.yearlyMonthly == 10 + 100)
    }

    @Test("Other driving: miles a week → gas a month, only with a car and a gas price")
    func otherGas() {
        let model = BudgetQuizModel()
        model.otherMilesPerWeek = "60"
        #expect(model.otherGasMonthly == nil)            // no gas price yet
        model.commute.fuelPrice = 3
        let expected = 60.0 * 52 / 12 / 30 * 3           // sedan, 30 mpg
        #expect(abs((model.otherGasMonthly ?? 0) - expected) < 0.001)
        model.carOwnership = "No Car"
        #expect(model.otherGasMonthly == nil)
    }

    @Test("A detected charge's due date is its next day of the month; ones already listed aren't offered")
    func detected() {
        var comps = DateComponents(year: 2026, month: 10, day: 12)
        let now = Calendar.current.date(from: comps)!
        comps.day = 20
        #expect(BudgetQuizModel.nextDate(day: 20, from: now) == Calendar.current.date(from: comps))
        comps.month = 11; comps.day = 5
        #expect(BudgetQuizModel.nextDate(day: 5, from: now) == Calendar.current.date(from: comps))
        comps.month = 10; comps.day = 31
        #expect(BudgetQuizModel.nextDate(day: 31, from: now) == Calendar.current.date(from: comps))

        let model = BudgetQuizModel()
        model.detected = [DetectedSubscription(snoozeKey: "a", name: "Netflix", averageAmount: 15.49, dayOfMonth: 3),
                          DetectedSubscription(snoozeKey: "b", name: "Spotify", averageAmount: 11.99, dayOfMonth: 9)]
        model.subscriptions = [QuizSubscription(name: "netflix", cost: 15.49, dueDate: now)]
        #expect(model.detectedToOffer.map(\.name) == ["Spotify"])
        model.add(model.detectedToOffer[0])
        #expect(model.detectedToOffer.isEmpty)
        #expect(model.subscriptionsMonthly == 15.49 + 11.99)
        #expect(model.subscriptions.last?.fromBank == true)
    }

    @Test("What's sent: the budgeting style, subscriptions, forgotten costs; car answers only with a car")
    func payload() {
        let model = BudgetQuizModel()
        model.yearlyIncome = "60000"
        model.budgetingStyle = .payYourselfFirst
        model.savePercent = 25
        model.subscriptions = [QuizSubscription(name: "Netflix", cost: 15.49, dueDate: Date())]
        model.phone = "45"
        model.dogs = 1
        model.carPayment = "300"
        model.yearlyCosts = [YearlyCost(name: "Trips", amount: 600), YearlyCost(name: "", amount: 50)]
        var p = model.payload()
        #expect(p["budgetingStyle"] as? String == "payYourselfFirst")
        #expect(p["savePercent"] as? Double == 25)
        #expect(p["withDetails"] as? Bool == true)
        #expect(p["401(k) Contribution"] as? String == "0")
        #expect((p["subscriptions"] as? [[String: Any]])?.first?["cost"] as? Double == 15.49)
        var other = p["otherCosts"] as? [String: Any] ?? [:]
        #expect(other["phone"] as? Double == 45)
        #expect(other["carPayment"] as? Double == 300)
        #expect((other["pets"] as? [[String: Any]])?.first?["type"] as? String == "dog")
        #expect((other["yearly"] as? [[String: Any]])?.count == 1)   // the unnamed one is left out

        model.carOwnership = "No Car"
        p = model.payload()
        other = p["otherCosts"] as? [String: Any] ?? [:]
        #expect(other["carPayment"] == nil)
        #expect(!((p["categories"] as? [String]) ?? []).contains("Car Insurance"))
    }

    @Test("Answers given on their own steps aren't asked again under known costs")
    func answeredElsewhere() {
        let model = BudgetQuizModel()
        model.totalRent = "1600"
        model.subscriptions = [QuizSubscription(name: "Hulu", cost: 8, dueDate: Date())]
        model.gym = "30"
        #expect(model.answeredElsewhere.isSuperset(of: ["Rent", "Subscriptions", "Gym"]))
        #expect(!model.answeredElsewhere.contains("Groceries"))
    }

    @Test("Steps that need an answer: a city and state, an income, complete debts")
    func canLeave() {
        let model = BudgetQuizModel()
        model.useDeviceLocation = false
        #expect(!model.canLeave(.location))
        model.manualCity = "Richmond"; model.manualState = "VA"
        #expect(model.canLeave(.location))
        #expect(!model.canLeave(.pay))
        model.yearlyIncome = "55,000"
        #expect(model.canLeave(.pay))
        model.hasDebt = true
        model.debts = [DebtItem(name: "Card")]
        #expect(!model.canLeave(.debt))                  // no balance
        model.debts[0].principal = "1200"
        #expect(model.canBuild)
        #expect(model.canLeave(.bank))                   // linking a bank is optional
    }

    @Test("Saved answers come back, and the old spending style maps to a budgeting style")
    func restore() {
        let model = BudgetQuizModel()
        model.restore(["yearlyIncome": "70000", "spendingStyle": "Low",
                       "otherCosts": ["phone": 40, "pets": [["type": "cat", "count": 2]],
                                      "yearly": [["name": "Trips", "amount": 900, "timesPerYear": 1]]]])
        #expect(model.hasSavedQuiz)
        #expect(model.budgetingStyle == .payYourselfFirst)
        #expect(model.phone == "40")
        #expect(model.cats == 2)
        #expect(model.yearlyMonthly == 75)

        let other = BudgetQuizModel()
        other.restore(["spendingStyle": "High"])
        #expect(other.budgetingStyle == .flexible)
        let newer = BudgetQuizModel()
        newer.restore(["spendingStyle": "Medium", "budgetingStyle": "everyDollar", "savePercent": 30])
        #expect(newer.budgetingStyle == .everyDollar)
        #expect(newer.savePercent == 30)
    }

    @Test("Ordinals for due dates")
    func ordinals() {
        #expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 31].map(\.ordinal)
                == ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd", "31st"])
    }
}

struct RebalanceTests {
    @Test("Over take-home: wants are trimmed evenly first; fixed and edited lines and needs stay")
    func trimsWants() {
        let budget: [String: Double] = ["Rent": 1500, "Groceries": 400, "Eating Out": 400, "Shopping": 200, "Savings": 600]
        let r = BudgetReview.rebalance(budget, takeHome: 3000, locked: ["Rent"], savingsFloor: 0)
        #expect(r.stillOver == 0)
        #expect(r.budget["Rent"] == 1500)
        #expect(r.budget["Groceries"] == 400)
        #expect(r.budget["Eating Out"] == 333)              // 400 − 100 × 2/3, rounded down
        #expect(r.budget["Shopping"] == 166)
        #expect(r.budget["Savings"] == 600)
        #expect(r.budget.values.reduce(0, +) <= 3000)
    }

    @Test("Then savings, but never below the plan's floor; what can't fit is reported")
    func savingsFloor() {
        let budget: [String: Double] = ["Rent": 2000, "Eating Out": 100, "Savings": 900]
        let r = BudgetReview.rebalance(budget, takeHome: 2600, locked: ["Rent"], savingsFloor: 520)
        #expect(r.budget["Eating Out"] == 0)
        #expect(r.budget["Savings"] == 600)                 // 900 − the other $300
        let tight = BudgetReview.rebalance(budget, takeHome: 2400, locked: ["Rent"], savingsFloor: 520)
        #expect(tight.budget["Savings"] == 520)
        #expect(tight.stillOver == 120)                     // $2,000 rent + $520 savings vs $2,400
        #expect(BudgetReview.savingsFloor(style: .payYourselfFirst, savePercent: 25, takeHome: 4000) == 1000)
        #expect(BudgetReview.savingsFloor(style: .flexible, savePercent: 25, takeHome: 4000) == 0)
    }

    @Test("Under take-home: what's left goes to Savings (another savings line when Savings was changed)")
    func leftover() {
        let r = BudgetReview.rebalance(["Rent": 1000, "Savings": 200], takeHome: 1500.75, locked: [], savingsFloor: 0)
        #expect(r.budget["Savings"] == 500)
        let edited = BudgetReview.rebalance(["Rent": 1000, "Savings": 200, "Roth IRA": 100], takeHome: 1500, locked: ["Savings"], savingsFloor: 0)
        #expect(edited.budget["Savings"] == 200)
        #expect(edited.budget["Roth IRA"] == 300)
    }
}

@MainActor
struct QuizAdditionsTests {
    @Test("Dependents by age: the count, childcare only for kids under 13, and an older quiz's count")
    func dependents() {
        let model = BudgetQuizModel()
        model.under5 = 1; model.age13to17 = 1
        model.childcare = "0"
        let p = model.payload()
        #expect(p["dependents"] as? String == "2")
        let household = p["household"] as? [String: Any] ?? [:]
        #expect(household["childcare"] as? Double == 0)
        model.under5 = 0
        #expect((model.payload()["household"] as? [String: Any])?["childcare"] == nil) // no kids under 13: not asked

        let old = BudgetQuizModel()
        old.restore(["dependents": "2"])
        #expect(old.legacyDependents == 2)
        #expect(old.payload()["dependents"] as? String == "2")
        let newer = BudgetQuizModel()
        newer.restore(["dependents": "1", "household": ["age5to12": 1, "childcare": 900]])
        #expect(newer.legacyDependents == 0)
        #expect(newer.childcare == "900")
    }

    @Test("Bills with a due day become calendar bills at the budget's amounts; ones that don't apply are skipped")
    func bills() {
        let model = BudgetQuizModel()
        model.billDueDays = ["Rent": 1, "Car Payment": 15, "Mortgage": 3, "Phone": 20]
        model.hasDebt = true
        let comps = DateComponents(year: 2026, month: 11, day: 8)
        model.debts = [DebtItem(name: "Chase Card", minPayment: "35", dueDate: Calendar.current.date(from: comps)!)]
        let bills = model.bills(budget: ["Rent": 1450, "Car Payment": 310, "Phone": 45, "Debt - Chase Card": 60])
        #expect(bills.map(\.name) == ["Rent", "Phone", "Car Payment", "Chase Card payment"]) // renting: no mortgage
        #expect(bills.first == BudgetQuizModel.Bill(name: "Rent", day: 1, amount: 1450, eventType: "rent"))
        #expect(bills.last?.day == 8)
        #expect(bills.last?.amount == 60)
        #expect(BudgetQuizModel.billDescription(bills[0]) == "Bill from your budget: $1,450 a month")
        model.carOwnership = "No Car"
        #expect(!model.bills(budget: [:]).contains { $0.name == "Car Payment" })
    }

    @Test("Savings: the Plan tab's (linked balances win); typed here only when the Plan didn't load")
    func savings() {
        let model = BudgetQuizModel()
        #expect(model.payload()["savings"] == nil)          // the Plan didn't load and nothing typed
        model.savedNow = "2500"
        #expect(model.emergencySaved == 2500)
        var plan = Plan()
        plan.emergencyFund.saved = 300
        model.setPlan(plan)
        #expect(model.emergencySaved == 300)                // the Plan's, edited on the quiz's savings card
        plan.emergencyFund = EmergencyFund(months: 6, saved: 4000, linkedAccountId: "acct")
        plan.savingsGoals = [SavingsGoal(name: "Car", target: 5000, saved: 1000, targetDate: "2030-01-01")]
        model.setPlan(plan, balances: ["acct": 7200])
        #expect(model.emergencySaved == 7200)
        let savings = model.payload()["savings"] as? [String: Any] ?? [:]
        #expect(savings["emergencyMonths"] as? Int == 6)
        let goal = (savings["goals"] as? [[String: Any]])?.first ?? [:]
        #expect(goal["name"] as? String == "Car")
        #expect((goal["monthlyNeeded"] as? Double ?? 0) > 0)
    }

    @Test("Bank answers: only once its history is in")
    func bankAverage() {
        let model = BudgetQuizModel()
        model.bankAverages = ["Gas": 140, "Gym": 0]
        #expect(model.bankAverage("Gas") == nil)
        model.bankReady = true
        #expect(model.bankAverage("Gas") == 140)
        #expect(model.bankAverage("Gym") == nil)
    }

    @Test("An unfinished quiz comes back: answers, step, subscriptions and the commute")
    func draft() {
        UserDefaults.standard.set("draft-test-user", forKey: "loggedInUsername")
        defer { UserDefaults.standard.removeObject(forKey: "loggedInUsername") }
        let model = BudgetQuizModel()
        model.clearDraft()
        model.yearlyIncome = "58000"
        model.step = .subscriptions
        model.subscriptions = [QuizSubscription(name: "Hulu", cost: 7.99, dueDate: Date(), fromBank: true)]
        model.commute.mode = .transit
        model.commute.transitMonthlyPass = 95
        model.commuteEstimated = true
        model.billDueDays = ["Rent": 1]
        model.age5to12 = 2
        model.savedNow = "1200"
        model.saveDraft()

        let back = BudgetQuizModel()
        let saved = back.savedDraft()
        #expect(saved != nil)
        back.resume(saved ?? [:])
        #expect(back.yearlyIncome == "58000")
        #expect(back.step == .subscriptions)
        #expect(back.subscriptions.first?.name == "Hulu")
        #expect(back.subscriptions.first?.fromBank == true)
        #expect(back.commute.transitMonthlyPass == 95)
        #expect(back.commuteEstimated)
        #expect(back.billDueDays["Rent"] == 1)
        #expect(back.age5to12 == 2)
        #expect(back.savedNow == "1200")
        #expect(!back.hasSavedQuiz)                          // an unfinished quiz isn't a saved one
        back.clearDraft()
        #expect(back.savedDraft() == nil)
    }
}

@MainActor
struct UtilitiesInternetTests {
    @Test("Internet is part of Utilities; on its own only when utilities come with the rent")
    func merged() {
        let model = BudgetQuizModel()
        model.utilities = "190"
        model.selectedCategories.insert("Internet")
        var housing = model.payload()["housing"] as? [String: Any] ?? [:]
        #expect(housing["internetInUtilities"] as? Bool == true)
        #expect(housing["internet"] == nil)
        #expect(!((model.payload()["categories"] as? [String]) ?? []).contains("Internet"))
        #expect(model.answeredElsewhere.contains("Internet"))

        model.utilitiesIncluded = true
        model.internet = "55"
        model.billDueDays = ["Internet": 12, "Utilities": 5]
        housing = model.payload()["housing"] as? [String: Any] ?? [:]
        #expect(housing["internetInUtilities"] as? Bool == false)
        #expect(housing["internet"] as? Double == 55)
        #expect(model.bills(budget: [:]).map(\.name) == ["Internet"])   // no Utilities bill: they're in the rent
    }

    @Test("An older quiz's separate internet is added to Utilities (or estimated with it when Utilities was blank)")
    func olderQuiz() {
        let typed = BudgetQuizModel()
        typed.restore(["housing": ["situation": "Renting", "utilities": 150, "internet": 60, "utilitiesIncluded": false]])
        #expect(typed.utilities == "210")
        #expect(typed.internet == "")
        let blank = BudgetQuizModel()
        blank.restore(["housing": ["situation": "Renting", "internet": 60, "utilitiesIncluded": false]])
        #expect(blank.utilities == "")
        #expect(blank.internet == "")
        let included = BudgetQuizModel()
        included.restore(["housing": ["situation": "Renting", "internet": 60, "utilitiesIncluded": true]])
        #expect(included.internet == "60")
    }
}

@MainActor
struct CarInsuranceAndChargesTests {
    @Test("Car insurance every 6 months: set aside monthly, and a calendar bill every 6 months from the next payment")
    func sixMonths() {
        let model = BudgetQuizModel()
        model.carInsurance = "600"
        model.carInsuranceMonths = 6
        let next = Calendar.current.date(from: DateComponents(year: 2027, month: 2, day: 14))!
        model.carInsuranceNextDue = next
        let other = model.payload()["otherCosts"] as? [String: Any] ?? [:]
        #expect(other["carInsurance"] as? Double == 100)
        #expect(other["carInsurancePayment"] as? Double == 600)
        #expect(other["carInsuranceMonths"] as? Int == 6)
        #expect(other["carInsuranceNextDue"] as? String == "2027-02-14")
        let bill = model.bills(budget: ["Car Insurance": 100]).first { $0.name == "Car Insurance" }
        #expect(bill?.recurrence == "every-6-months")
        #expect(bill?.amount == 600)
        #expect(bill.map(BudgetQuizModel.billDescription) == "Bill from your budget: $600 every 6 months")
        model.carInsuranceMonths = 12
        #expect(model.bills(budget: [:]).first { $0.name == "Car Insurance" }?.recurrence == "yearly")
    }

    @Test("Saved insurance timing comes back; a next payment that has passed moves to the following one")
    func restore() {
        let model = BudgetQuizModel()
        let past = Calendar.current.date(byAdding: .month, value: -2, to: Date())!
        model.restore(["otherCosts": ["carInsurance": 100, "carInsurancePayment": 600, "carInsuranceMonths": 6,
                                      "carInsuranceNextDue": Recurrence.dayKey(past)]])
        #expect(model.carInsurance == "600")
        #expect(model.carInsuranceMonths == 6)
        #expect(Recurrence.dayKey(model.carInsuranceNextDue) == Recurrence.dayKey(Calendar.current.date(byAdding: .month, value: 6, to: past)!))
        let older = BudgetQuizModel()
        older.restore(["otherCosts": ["carInsurance": 130]])
        #expect(older.carInsurance == "130")
        #expect(older.carInsuranceMonths == 1)
    }

    @Test("Charges the bank calls subscriptions are offered unless they're detected or already listed")
    func bankCharges() {
        let model = BudgetQuizModel()
        let day = Date()
        model.bankCharges = [BankCharge(name: "Netflix", amount: 15.49, dayOfMonth: 9, lastDate: day, times: 2),
                             BankCharge(name: "AMC Theatres", amount: 18.5, dayOfMonth: 3, lastDate: day, times: 1),
                             BankCharge(name: "Spotify", amount: 11.99, dayOfMonth: 5, lastDate: day, times: 3)]
        model.detected = [DetectedSubscription(snoozeKey: "s", name: "Spotify", averageAmount: 11.99, dayOfMonth: 5)]
        model.subscriptions = [QuizSubscription(name: "netflix", cost: 15.49, dueDate: day)]
        #expect(model.alsoMarkedToOffer.map(\.name) == ["AMC Theatres"])
        model.add(model.alsoMarkedToOffer[0])
        #expect(model.alsoMarkedToOffer.isEmpty)
        #expect(model.subscriptions.last?.cost == 18.5)
        #expect(model.subscriptions.last?.fromBank == true)
    }
}

@MainActor
struct NoRepeatsTests {
    @Test("Earlier answers decide their lines: blank phone and car insurance are estimated (0 = none), blank gym and copays are none unless the bank shows them, no health insurance line")
    func derived() {
        let model = BudgetQuizModel()
        var cats = Set(model.payload()["categories"] as? [String] ?? [])
        #expect(cats.isSuperset(of: ["Transportation", "Gas", "Car Insurance", "Phone", "Rent", "Utilities", "Groceries"]))
        #expect(cats.isDisjoint(with: ["Health Insurance", "Gym", "Medical", "Subscriptions", "Commute"]))

        model.phone = "0"
        model.carInsurance = "0"
        model.bankReady = true
        model.bankAverages = ["Gym": 35]
        model.subscriptions = [QuizSubscription(name: "Hulu", cost: 8, dueDate: Date())]
        cats = Set(model.payload()["categories"] as? [String] ?? [])
        #expect(!cats.contains("Phone"))
        #expect(!cats.contains("Car Insurance"))
        #expect(cats.contains("Gym"))                       // folded: the bank's amount
        #expect(cats.contains("Subscriptions"))
        model.carOwnership = "No Car"
        #expect(!Set(model.payload()["categories"] as? [String] ?? []).contains("Gas"))
    }

    @Test("The last step never repeats earlier questions, even ones saved by an older quiz")
    func lastStep() {
        let model = BudgetQuizModel()
        model.restore(["categories": ["Rent", "Groceries", "Car Insurance", "Health Insurance", "Transportation", "Hobbies"],
                       "knownCosts": ["Car Insurance": 80, "Phone": 45, "Hobbies": 40, "Commute": 300]])
        let shown = model.allCategories.filter { !model.answeredElsewhere.contains($0) && !BudgetQuizModel.trackerExclusions.contains($0) }
        #expect(!shown.contains("Rent") && !shown.contains("Car Insurance") && !shown.contains("Transportation"))
        #expect(shown.contains("Hobbies") && shown.contains("Groceries"))
        // what was typed there moves to its own question
        #expect(model.carInsurance == "80")
        #expect(model.phone == "45")
        let known = model.payload()["knownCosts"] as? [String: Double] ?? [:]
        #expect(known == ["Hobbies": 40])
    }

    @Test("Once-a-year: blank amounts are estimated; insurance isn't a suggestion; car registration is a need")
    func yearly() {
        let model = BudgetQuizModel()
        model.yearlyCosts = [YearlyCost(name: "Car maintenance"), YearlyCost(name: "Trips", amount: 600, timesPerYear: 2)]
        let yearly = (model.payload()["otherCosts"] as? [String: Any])?["yearly"] as? [[String: Any]] ?? []
        #expect(yearly.count == 2)
        #expect(yearly[0]["amount"] == nil)
        #expect(yearly[1]["amount"] as? Double == 600)
        #expect(!YearlyCost.suggestions.contains { $0.lowercased().contains("insurance") })
        #expect(BudgetReview.kind(of: "Car registration") == .need)
        #expect(BudgetReview.kind(of: "Car maintenance") == .need)
        #expect(BudgetReview.kind(of: "Holidays & gifts") == .want)
    }

    @Test("The commute is sent as gas (in Gas) and the rest (in Transportation)")
    func commuteSplit() {
        let model = BudgetQuizModel()
        model.workArrangement = "office"
        model.commute = CommuteInputs(mode: .drive, roundTripMiles: 60, car: .sedan, fuelPrice: 3, parkingMonthly: 50, tollsPerDay: 2)
        model.commuteEstimated = true
        let work = model.payload()["work"] as? [String: Any] ?? [:]
        let days = 5.0 * 52 / 12
        #expect(abs((work["commuteGas"] as? Double ?? 0) - (60 * days / 30 * 3)) < 0.01)
        #expect(abs((work["commuteOther"] as? Double ?? 0) - (2 * days + 50)) < 0.01)
    }
}

@MainActor
struct BankCategoryTests {
    @Test("Bank categories with $25+ a month are added and switched on; ones asked earlier, small ones and yearly ones aren't")
    func added() {
        let model = BudgetQuizModel()
        model.yearlyCosts = [YearlyCost(name: "Car maintenance")]
        model.bankReady = true
        model.bankAverages = ["Travel": 432, "Insurance": 40, "Gas": 141, "Miscellaneous": 300, "Home": 12,
                              "Car Maintenance": 60, "groceries": 400]
        model.addBankCategories()
        #expect(model.fromBankCategories == ["Travel", "Insurance"])
        #expect(model.selectedCategories.isSuperset(of: ["Travel", "Insurance"]))
        #expect(!model.allCategories.contains("Home"))        // under $25
        #expect(!model.allCategories.contains("Car Maintenance")) // a once-a-year line already
        let cats = Set(model.payload()["categories"] as? [String] ?? [])
        #expect(cats.isSuperset(of: ["Travel", "Insurance"]))
        #expect(!cats.contains("Car maintenance"))           // the yearly line covers it
    }

    @Test("Switching one off keeps it off next time")
    func declined() {
        let model = BudgetQuizModel()
        model.bankReady = true
        model.bankAverages = ["Travel": 432]
        model.addBankCategories()
        model.setCategory("Travel", on: false)
        #expect(model.payload()["declinedBankCategories"] as? [String] == ["Travel"])

        let next = BudgetQuizModel()
        next.restore(["declinedBankCategories": ["Travel"], "categories": ["Groceries"]])
        next.bankReady = true
        next.bankAverages = ["Travel": 432]
        next.addBankCategories()
        #expect(!next.selectedCategories.contains("Travel"))
        next.setCategory("Travel", on: true)
        #expect(next.declinedBankCategories.isEmpty)
    }
}

@MainActor
struct GasTests {
    @Test("Hybrids use their own miles per gallon, for the commute and other driving")
    func hybrids() {
        let model = BudgetQuizModel()
        model.otherMilesPerWeek = "60"
        model.commute.fuelPrice = 3
        model.commute.car = .hybridSedan
        #expect(abs((model.otherGasMonthly ?? 0) - 60.0 * 52 / 12 / 48 * 3) < 0.001)
        model.commute.car = .hybridSuv
        #expect(abs((model.otherGasMonthly ?? 0) - 60.0 * 52 / 12 / 37 * 3) < 0.001)
        #expect(CarType.allCases.map(\.title) == ["Small car", "Sedan", "Hybrid sedan", "SUV or truck", "Hybrid SUV", "Electric"])
    }

    @Test("Gas from their answers is the commute's gas plus other driving; Change keeps the bank's amount out")
    func gasTotal() {
        let model = BudgetQuizModel()
        model.workArrangement = "office"
        model.commute = CommuteInputs(mode: .drive, roundTripMiles: 30, car: .sedan, fuelPrice: 3)
        model.commuteEstimated = true
        model.otherMilesPerWeek = "30"
        let days = 5.0 * 52 / 12
        let gas = model.gasFromAnswers
        #expect(abs((gas?.commute ?? 0) - 30 * days / 30 * 3) < 0.01)
        #expect(abs((gas?.other ?? 0) - 30.0 * 52 / 12 / 30 * 3) < 0.01)

        model.bankAverages = ["Gas": 141, "Groceries": 400]
        #expect((model.payload()["bankAverages"] as? [String: Double])?["Gas"] == 141)
        model.bankOverrides = ["Gas"]
        let sent = model.payload()["bankAverages"] as? [String: Double] ?? [:]
        #expect(sent["Gas"] == nil)
        #expect(sent["Groceries"] == 400)
    }
}

@MainActor
struct StepOrderTests {
    @Test("Subscriptions and once-a-year costs are one step, right after other regular costs")
    func order() {
        #expect(QuizStep.allCases.map(\.key) == ["bank", "location", "pay", "home", "gettingAround", "otherCosts",
                                                  "subscriptions", "debt", "goals", "categories"])
        #expect(QuizStep.subscriptions.title == "Subscriptions & yearly costs")
    }

    @Test("An unfinished quiz comes back on the same step by name; an older one by number")
    func resumeByName() {
        let model = BudgetQuizModel()
        model.resume(["draftStepName": "debt", "draftStep": 3])
        #expect(model.step == .debt)
        let older = BudgetQuizModel()
        older.resume(["draftStep": 10])                    // the old 11-step quiz's last step
        #expect(older.step == .categories)
    }

    @Test("How each bank transaction was sorted, in plain words")
    func howText() {
        func t(_ how: String) -> BankTransaction { BankTransaction(date: Date(), name: "X", amount: 1, category: "Home", how: how) }
        #expect(t("bank").howText == "Your bank or card's label")
        #expect(t("ai").howText == "Sorted by AI from the name")
        #expect(t("store").howText == "A business PlotLine knows")
        #expect(t("yours").howText == "Your rule for this place")
        #expect(t("none").howText == "Couldn't tell what it was")
    }
}

@MainActor
struct FuelPriceTests {
    @Test("The gas price says where it came from; a price they typed isn't replaced by a lookup")
    func source() {
        let model = BudgetQuizModel()
        #expect(model.fuelPriceSource == .none)
        model.setLookedUpFuelPrice(3.071, fromEIA: true)
        #expect(model.commute.fuelPrice == 3.071)
        #expect(model.fuelPriceSource == .eia)
        model.commute.fuelPrice = 2.95                       // they pay less
        #expect(model.fuelPriceSource == .yours)
        model.setLookedUpFuelPrice(3.10, fromEIA: true)      // estimating the commute looks it up again
        #expect(model.commute.fuelPrice == 2.95)
        #expect(model.fuelPriceSource == .yours)

        let estimated = BudgetQuizModel()
        estimated.setLookedUpFuelPrice(3.25, fromEIA: false)
        #expect(estimated.fuelPriceSource == .estimate)
    }
}

@MainActor
struct CarSavedTests {
    @Test("What they drive, parking and carpool details come back with their saved answers")
    func roundTrip() throws {
        let model = BudgetQuizModel()
        model.commute.car = .hybridSedan
        model.workArrangement = "office"
        model.commute.mode = .carpoolDriver
        model.commute.parkingMonthly = 120
        model.commute.carpoolPeople = 3
        // what the server keeps is what was sent (as JSON)
        let saved = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: model.payload())) as? [String: Any] ?? [:]
        let next = BudgetQuizModel()
        next.restore(saved)
        #expect(next.commute.car == .hybridSedan)
        #expect(next.commute.mode == .carpoolDriver)
        #expect(next.commute.parkingMonthly == 120)
        #expect(next.commute.carpoolPeople == 3)
    }
}

@MainActor
struct EverythingSavesTests {
    /// every answer in the quiz, filled in
    private func filledIn() -> BudgetQuizModel {
        let m = BudgetQuizModel()
        m.useDeviceLocation = false; m.manualCity = "Ashburn"; m.manualState = "VA"
        m.yearlyIncome = "87000"; m.retirement = "6"; m.payFrequency = .twiceMonthly
        m.healthPerCheck = "55"; m.dentalPerCheck = "4"; m.visionPerCheck = "2"
        m.under5 = 1; m.age5to12 = 2; m.age13to17 = 1; m.adultDependents = 1; m.childcare = "900"
        m.housingSituation = "Live with Others"; m.knowsShare = false; m.totalRent = "2080"; m.rentPeople = 2
        m.utilitiesIncluded = false; m.utilities = "140"; m.rentersInsurance = "12"
        m.billDueDays = ["Rent": 1, "Utilities": 15, "Phone": 20, "Car Payment": 5]
        m.carOwnership = "Multiple Cars"; m.carPayment = "310"; m.carInsurance = "600"; m.carInsuranceMonths = 6
        m.carInsuranceNextDue = Calendar.current.date(byAdding: .month, value: 2, to: Calendar.current.startOfDay(for: Date()))!
        m.otherMilesPerWeek = "40"
        m.workArrangement = "hybrid"; m.workPlace = "Reston, VA"
        m.commute = CommuteInputs(mode: .drive, officeDaysPerWeek: 3, roundTripMiles: 32, oneWayMinutes: 25, car: .hybridSuv,
                                  fuelPrice: 3.07, parkingMonthly: 60, tollsPerDay: 4.5)
        m.commuteEstimated = true
        m.eatingOutFrequency = "Often"; m.phone = "45"; m.gym = "30"; m.medical = "20"
        m.dogs = 1; m.cats = 2; m.otherPets = 1; m.petsMonthly = "150"
        m.yearlyCosts = [YearlyCost(name: "Car registration", amount: 95), YearlyCost(name: "Trips", amount: 600, timesPerYear: 2),
                         YearlyCost(name: "Car maintenance")]
        m.hasDebt = true
        m.debts = [DebtItem(name: "Chase Card", principal: "2400", apr: "24.9", minPayment: "60",
                            dueDate: Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 8))!)]
        m.budgetingStyle = .payYourselfFirst; m.savePercent = 25; m.primaryGoal = "Maximize Investing"; m.savingsPriority = "High"
        m.allCategories.append("Hobbies"); m.selectedCategories = ["Groceries", "Eating Out", "Savings", "Hobbies"]
        m.knownCosts = ["Hobbies": "40", "Groceries": "450"]
        m.declinedBankCategories = ["Travel"]
        return m
    }

    @Test("Every answer comes back when the quiz is opened again")
    func everything() throws {
        let m = filledIn()
        let saved = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: m.payload())) as? [String: Any] ?? [:]
        let r = BudgetQuizModel()
        r.restore(saved)

        // where you live
        #expect(r.useDeviceLocation == false)
        #expect(r.finalCity == "Ashburn" && r.finalState == "VA")
        // pay
        #expect(r.yearlyIncome == "87000" && r.retirement == "6" && r.payFrequency == .twiceMonthly)
        #expect(r.healthPerCheck == "55" && r.dentalPerCheck == "4" && r.visionPerCheck == "2")
        #expect(r.under5 == 1 && r.age5to12 == 2 && r.age13to17 == 1 && r.adultDependents == 1 && r.childcare == "900")
        // home
        #expect(r.housingSituation == "Live with Others" && !r.knowsShare && r.totalRent == "2080" && r.rentPeople == 2)
        #expect(!r.utilitiesIncluded && r.utilities == "140" && r.rentersInsurance == "12")
        #expect(r.billDueDays == ["Rent": 1, "Utilities": 15, "Phone": 20, "Car Payment": 5])
        // getting around
        #expect(r.carOwnership == "Multiple Cars" && r.carPayment == "310" && r.carInsurance == "600" && r.carInsuranceMonths == 6)
        #expect(Recurrence.dayKey(r.carInsuranceNextDue) == Recurrence.dayKey(m.carInsuranceNextDue))
        #expect(r.otherMilesPerWeek == "40")
        #expect(r.workArrangement == "hybrid" && r.workPlace == "Reston, VA")
        #expect(r.commute.mode == .drive && r.commute.officeDaysPerWeek == 3 && r.commute.car == .hybridSuv)
        #expect(r.commute.parkingMonthly == 60)
        // the commute estimate itself (so updating one part doesn't lose it)
        #expect(r.commute.roundTripMiles == 32 && r.commute.oneWayMinutes == 25 && r.commute.tollsPerDay == 4.5)
        #expect(r.commute.fuelPrice == 3.07)
        #expect(r.commuteEstimated)
        #expect(r.commuteMonthly?.total == m.commuteMonthly?.total)
        // other costs
        #expect(r.eatingOutFrequency == "Often" && r.phone == "45" && r.gym == "30" && r.medical == "20")
        #expect(r.dogs == 1 && r.cats == 2 && r.otherPets == 1 && r.petsMonthly == "150")
        // yearly (a blank one stays blank: estimated)
        #expect(r.yearlyCosts.map(\.name) == ["Car registration", "Trips", "Car maintenance"])
        #expect(r.yearlyCosts.map(\.amount) == [95, 600, nil])
        #expect(r.yearlyCosts.map(\.timesPerYear) == [1, 2, 1])
        // debt
        #expect(r.hasDebt && r.debts.count == 1)
        #expect(r.debts.first?.name == "Chase Card" && r.debts.first?.principal == "2400" && r.debts.first?.apr == "24.9")
        #expect(r.debts.first?.minPayment == "60")
        #expect(Recurrence.dayKey(r.debts.first?.dueDate ?? Date()) == "2026-11-08")
        // goals
        #expect(r.budgetingStyle == .payYourselfFirst && r.savePercent == 25)
        #expect(r.primaryGoal == "Maximize Investing" && r.savingsPriority == "High")
        // categories
        #expect(r.selectedCategories.isSuperset(of: ["Groceries", "Eating Out", "Savings", "Hobbies"]))
        #expect(r.knownCosts["Hobbies"] == "40" && r.knownCosts["Groceries"] == "450")
        #expect(r.declinedBankCategories == ["Travel"])
    }

    @Test("A looked-up gas price is looked up again next time; one they typed is kept")
    func fuelPriceNextTime() throws {
        let m = filledIn()
        m.commute.fuelPrice = 0
        m.setLookedUpFuelPrice(3.07, fromEIA: true)
        let saved = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: m.payload())) as? [String: Any] ?? [:]
        let r = BudgetQuizModel()
        r.restore(saved)
        #expect(r.commute.fuelPrice == 0)                    // refreshed when the quiz opens
        #expect(r.commute.roundTripMiles == 32)               // the rest of the estimate stays
    }
}

@MainActor
struct DraftFuelPriceTests {
    @Test("Resuming an unfinished quiz looks the gas price up again unless they typed it")
    func resume() {
        UserDefaults.standard.set("draft-fuel-user", forKey: "loggedInUsername")
        defer { UserDefaults.standard.removeObject(forKey: "loggedInUsername") }
        let model = BudgetQuizModel()
        model.setLookedUpFuelPrice(3.45, fromEIA: false)
        model.saveDraft()
        let back = BudgetQuizModel()
        back.resume(back.savedDraft() ?? [:])
        #expect(back.commute.fuelPrice == 0)

        model.commute.fuelPrice = 3.10                      // typed
        model.saveDraft()
        let typed = BudgetQuizModel()
        typed.resume(typed.savedDraft() ?? [:])
        #expect(typed.commute.fuelPrice == 3.10)
        typed.clearDraft()
    }
}

@MainActor
struct ZeroSavesTests {
    @Test("A typed 0 comes back as 0 (none); a blank comes back blank (estimated); older answers' 0 still means blank")
    func zeros() throws {
        let m = BudgetQuizModel()
        m.phone = "0"
        m.carInsurance = "0"
        m.utilities = ""
        let saved = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: m.payload())) as? [String: Any] ?? [:]
        let other = saved["otherCosts"] as? [String: Any] ?? [:]
        #expect(other["phone"] as? Double == 0)
        #expect(other["gym"] == nil)                          // blank isn't sent
        #expect((saved["housing"] as? [String: Any])?["utilities"] == nil)
        let r = BudgetQuizModel()
        r.restore(saved)
        #expect(r.phone == "0" && r.carInsurance == "0")
        #expect(r.gym == "" && r.utilities == "")
        let cats = Set(r.payload()["categories"] as? [String] ?? [])
        #expect(!cats.contains("Phone") && !cats.contains("Car Insurance"))

        let older = BudgetQuizModel()
        older.restore(["otherCosts": ["phone": 0, "gym": 0], "housing": ["utilities": 0]])
        #expect(older.phone == "" && older.gym == "" && older.utilities == "")
    }
}

@MainActor
struct RegenerateTests {
    @Test("Regenerate sends exactly the page's categories and which ones are new; the quiz doesn't")
    func exactCategories() {
        let model = BudgetQuizModel()
        model.phone = "45"
        model.exactCategories = ["Rent", "Groceries", "Travel", "401(k) Contribution"]
        model.newCategories = ["Travel"]
        let p = model.payload()
        #expect(Set(p["categories"] as? [String] ?? []) == ["Rent", "Groceries", "Travel"])  // no Phone, Gas, Transportation added
        #expect(p["exactCategories"] as? Bool == true)
        #expect(p["newCategories"] as? [String] == ["Travel"])

        let quiz = BudgetQuizModel()
        #expect(quiz.payload()["exactCategories"] as? Bool == false)
        #expect(Set(quiz.payload()["categories"] as? [String] ?? []).contains("Transportation"))
    }

    @Test("The take-home from the last saved quiz is kept for comparing")
    func savedTakeHome() {
        let model = BudgetQuizModel()
        model.restore(["yearlyIncome": "135000", "monthlyNet": 7458.12])
        #expect(model.savedMonthlyNet == 7458.12)
    }
}

@MainActor
struct BillReminderTests {
    private func event(_ title: String, type: String, start: Date) -> Event {
        Event(id: "e-\(title)", title: title, description: "", startDate: start, endDate: start, eventType: type,
              recurrence: "none", invitedFriends: [])
    }

    @Test("The utilities bill reminder opens Monthly Costs on its day; other reminders still open the calendar")
    func utilitiesOpensCosts() {
        let now = Date()
        let due = Calendar.current.date(byAdding: .day, value: 10, to: Calendar.current.startOfDay(for: now))!.addingTimeInterval(9 * 3600)
        let events = [event("Utilities", type: "bill", start: due), event("Rent", type: "rent", start: due),
                      event("Phone", type: "bill", start: due), event("Dinner", type: "user", start: due)]
        let planned = EventReminders.planned(ownEvents: events, friendEvents: [:], offsets: { _ in [86_400] }, now: now)
        let utilities = planned.first { $0.title == "Utilities" }
        #expect(utilities?.logCategory == "Utilities")
        #expect(planned.filter { $0.title != "Utilities" }.allSatisfy { $0.logCategory == nil })

        let info = EventReminders.request(for: utilities!).content.userInfo
        #expect(info["navigateTo"] as? String == "costs")
        #expect(info["costsCategory"] as? String == "Utilities")
        #expect(info["costsDay"] as? String == Recurrence.dayKey(due))
        #expect(EventReminders.request(for: utilities!).content.body.contains("Tap to enter this month's amount"))
        let rent = planned.first { $0.title == "Rent" }!
        #expect(EventReminders.request(for: rent).content.userInfo["navigateTo"] as? String == "calendar")

        // one scheduled before this change (opens the calendar) is replaced
        let old = (identifier: utilities!.identifier, userInfo: [AnyHashable: Any](uniqueKeysWithValues: [
            ("navigateTo", "calendar" as Any), ("eventTitle", "Utilities" as Any),
            ("eventDate", ISO8601DateFormatter().string(from: due) as Any)]))
        let change = EventReminders.reconcile(pending: [old], planned: [utilities!], loadedFriends: [])
        #expect(change.remove == [utilities!.identifier])
        #expect(change.add.map(\.identifier) == [utilities!.identifier])
    }

    @Test("Tapping it asks Monthly Costs for that day and category")
    func router() {
        let router = CostsRouter()
        router.open(["navigateTo": "costs", "costsDay": "2026-11-15", "costsCategory": "Utilities"])
        #expect(router.request?.category == "Utilities")
        #expect(router.request.map { Recurrence.dayKey($0.day) } == "2026-11-15")
        let ignored = CostsRouter()
        ignored.open(["navigateTo": "calendar"])
        #expect(ignored.request == nil)
    }
}

@MainActor
struct FuelPriceNoDowngradeTests {
    @Test("A slower AI estimate doesn't replace EIA's price that's already showing")
    func keepsEia() {
        let model = BudgetQuizModel()
        model.setLookedUpFuelPrice(4.363, fromEIA: true)
        model.setLookedUpFuelPrice(3.45, fromEIA: false)
        #expect(model.commute.fuelPrice == 4.363)
        #expect(model.fuelPriceSource == .eia)
        model.setLookedUpFuelPrice(4.401, fromEIA: true)   // a newer EIA price still updates it
        #expect(model.commute.fuelPrice == 4.401)
    }
}

@MainActor
struct LocationOnOpenTests {
    @Test("Opening with saved answers: same place keeps Use My Location on; somewhere else turns it off and keeps the saved place")
    func savedPlace() {
        let here = BudgetQuizModel()
        here.restore(["city": "Ashburn", "state": "VA", "useDeviceLocation": true])
        here.phoneLocated(city: "Ashburn", state: "VA")
        #expect(here.useDeviceLocation && here.finalCity == "Ashburn")
        #expect(!here.phoneElsewhere)

        let moved = BudgetQuizModel()
        moved.restore(["city": "Hunt Valley", "state": "MD", "useDeviceLocation": true])
        moved.phoneLocated(city: "Ashburn", state: "VA")
        #expect(!moved.useDeviceLocation)
        #expect(moved.finalCity == "Hunt Valley" && moved.finalState == "MD")   // the saved place
        #expect(moved.phoneElsewhere)

        let denied = BudgetQuizModel()
        denied.restore(["city": "Hunt Valley", "state": "MD", "useDeviceLocation": true])
        denied.phoneLocated(city: "Permission", state: "Denied")
        #expect(!denied.useDeviceLocation && denied.finalCity == "Hunt Valley")
    }
}

@MainActor
struct PlaceMatchTests {
    @Test("A city typed with its state, or a state written out, still matches where the phone is")
    func lenient() {
        #expect(BudgetQuizModel.place(city: "Ashburn, VA", state: "") == ("Ashburn", "VA"))
        #expect(BudgetQuizModel.place(city: " ashburn ", state: "Virginia") == ("ashburn", "VA"))
        #expect(BudgetQuizModel.place(city: "Washington, DC", state: "DC") == ("Washington", "DC"))
        #expect(BudgetQuizModel.place(city: "Winston-Salem", state: "nc") == ("Winston-Salem", "NC"))

        let typed = BudgetQuizModel()
        typed.restore(["city": "Ashburn, VA", "state": "", "useDeviceLocation": false])
        #expect(typed.manualCity == "Ashburn" && typed.manualState == "VA")
        typed.phoneLocated(city: "Ashburn", state: "VA")
        #expect(typed.useDeviceLocation)
        #expect(!typed.phoneElsewhere)

        let written = BudgetQuizModel()
        written.restore(["city": "ashburn", "state": "Virginia", "useDeviceLocation": false])
        written.phoneLocated(city: "Ashburn", state: "VA")
        #expect(written.useDeviceLocation)
    }
}

@MainActor
struct NicheCategoryTests {
    @Test("A narrower category is suggested off; switched on, its spending moves out of the broad one")
    func nicheMovesSpending() {
        let model = BudgetQuizModel()
        model.bankReady = true
        model.bankMonths = 3
        model.bankAverages = ["Eating Out": 100]
        model.bankTransactions = [
            BankTransaction(date: Date(), name: "JOE'S TAVERN", amount: 60, category: "Eating Out", how: "bank", niches: ["Alcohol & Bars"]),
            BankTransaction(date: Date(), name: "THE PUB", amount: 30, category: "Eating Out", how: "store", niches: ["Alcohol & Bars"]),
            BankTransaction(date: Date(), name: "OLIVE GARDEN", amount: 210, category: "Eating Out", how: "bank"),
        ]
        model.addBankCategories()
        #expect(model.allCategories.contains("Alcohol & Bars"))
        #expect(!model.selectedCategories.contains("Alcohol & Bars"))      // suggested, off
        #expect(model.bankAverage("Alcohol & Bars") == 30)                  // what it would take out
        #expect(model.bankAverage("Eating Out") == 100)                     // nothing moved yet
        #expect(model.nicheParent("Alcohol & Bars") == "Eating Out")

        model.setCategory("Alcohol & Bars", on: true)
        #expect(model.bankAverage("Alcohol & Bars") == 30)
        #expect(model.bankAverage("Eating Out") == 70)
        #expect(model.sortedBankTransactions.filter { $0.category == "Alcohol & Bars" }.map(\.name) == ["JOE'S TAVERN", "THE PUB"])

        model.setCategory("Alcohol & Bars", on: false)
        #expect(model.bankAverage("Eating Out") == 100)
    }

    @Test("Big narrower categories start on; the bank step lists them under their broad one; earlier-step ones never split")
    func nicheBreakdown() {
        let model = BudgetQuizModel()
        model.bankReady = true
        model.bankMonths = 2
        model.bankAverages = ["Eating Out": 300, "Transportation": 100]
        model.bankTransactions = [
            BankTransaction(date: Date(), name: "THE BRASS TAP", amount: 160, category: "Eating Out", how: "ai", niches: ["Alcohol & Bars"]),
            BankTransaction(date: Date(), name: "STARBUCKS", amount: 40, category: "Eating Out", how: "bank", niches: ["Coffee"]),
            BankTransaction(date: Date(), name: "OLIVE GARDEN", amount: 400, category: "Eating Out", how: "bank"),
            BankTransaction(date: Date(), name: "SPOTHERO", amount: 120, category: "Transportation", how: "bank", niches: ["Parking"]),
            BankTransaction(date: Date(), name: "LYFT", amount: 80, category: "Transportation", how: "bank"),
        ]
        // what switching Coffee on would move, while it's off
        #expect(model.transactionsShown(for: "Coffee").map(\.name) == ["STARBUCKS"])

        model.addBankCategories()
        #expect(model.selectedCategories.contains("Alcohol & Bars"))      // $80 a month: on
        #expect(!model.selectedCategories.contains("Coffee"))             // $20: under $25, not even listed
        #expect(!model.allCategories.contains("Coffee"))
        #expect(model.bankAverage("Eating Out") == 220)
        #expect(model.nichesInside("Eating Out").map(\.name) == ["Alcohol & Bars", "Coffee"])
        // parking is asked with the commute: never split out of Transportation here
        #expect(!model.bankNiches.contains("Parking"))
        #expect(model.bankAverage("Transportation") == 100)

        model.trackSeparately("Coffee", true)
        #expect(model.allCategories.contains("Coffee"))
        #expect(model.bankAverage("Eating Out") == 200)
        model.trackSeparately("Alcohol & Bars", false)
        #expect(model.declinedBankCategories.contains("Alcohol & Bars"))  // not switched back on later
        #expect(model.bankAverage("Eating Out") == 280)
    }

    @Test("Swipe Remove and Move: the monthly amounts change, a new category is added and on, and Put Back undoes it")
    func removeAndMove() {
        let model = BudgetQuizModel()
        model.bankReady = true
        model.bankMonths = 2
        model.bankAverages = ["Shopping": 600, "Eating Out": 100]
        let tv = BankTransaction(txnId: "tv", date: Date(), name: "BEST BUY", amount: 1000, category: "Shopping", how: "bank")
        let shirt = BankTransaction(txnId: "shirt", date: Date(), name: "OLD NAVY", amount: 200, category: "Shopping", how: "bank")
        let dinner = BankTransaction(txnId: "dinner", date: Date(), name: "OLIVE GARDEN", amount: 200, category: "Eating Out", how: "bank")
        model.bankTransactions = [tv, shirt, dinner]

        model.removeBankTransaction(tv)
        #expect(model.bankAverage("Shopping") == 100)                       // the TV isn't usual spending
        #expect(model.removedBankTransactions.map(\.txnId) == ["tv"])
        #expect(!model.sortedBankTransactions.contains { $0.txnId == "tv" })

        model.moveBankTransaction(dinner, to: "date night")
        #expect(model.bankAverage("Eating Out") == nil)                     // nothing left there
        #expect(model.bankAverage("date night") == 100)
        #expect(model.selectedCategories.contains("date night"))            // added, switched on
        model.moveBankTransaction(shirt, to: "Date Night")                  // the same one, however it's typed
        #expect(model.bankEdits["shirt"] == "date night")
        #expect(model.bankAverage("date night") == 200)

        // sent with the answers (and to Monthly Costs on save); Put Back undoes
        #expect((model.payload()["bankEdits"] as? [String: String])?["tv"] == "")
        #expect((model.payload()["bankAverages"] as? [String: Double])?["Shopping"] == nil)
        model.restoreBankTransaction(tv)
        model.restoreBankTransaction(shirt)
        #expect(model.bankAverage("Shopping") == 600)
    }
}
