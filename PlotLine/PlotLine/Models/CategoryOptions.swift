//
//  CategoryOptions.swift
//  PlotLine
//
//  The categories offered when adding one (quiz, budget page, Monthly Costs, a transaction's category)
//  and when telling PlotLine where a place's transactions always go. One list, so they all match.
//

enum CategoryOptions {
    static let common = [
        // Defaults
        "Rent", "Groceries", "Subscriptions", "Eating Out",
        "Entertainment", "Utilities", "Savings", "Miscellaneous",
        "Transportation", "Roth IRA", "Car Insurance",
        "Health Insurance", "Brokerage",
        // Additional common
        "Gas", "Phone", "Internet", "Gym", "Personal Care", "Education", "Childcare", "Pet Care",
        "Travel", "Hobbies", "Shopping", "Medical",
        "Insurance", "Taxes & Fees", "Car Maintenance", "Home", "Gifts & Donations", "Services",
        // Narrower ones: bank transactions go here instead of the broader category when the budget has them
        "Alcohol & Bars", "Coffee", "Fast Food", "Food Delivery", "Parking", "Tolls", "Rideshare", "Public Transit",
        "Streaming Services", "Music", "Gaming", "Dental", "Vision", "Pharmacy", "Therapy", "Gifts", "Donations",
        "Home Maintenance", "Home Decor", "Clothing", "Electronics", "Books", "Baby Supplies", "Haircuts", "Laundry",
        "Electric", "Water", "Flights", "Hotels",
    ]

    /// where a place's purchases can go (not money set aside)
    static let spending = common.filter { !["Savings", "Roth IRA", "Brokerage"].contains($0) }
}
