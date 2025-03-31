//
//  InvestmentHomeView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 3/31/25.
//

import SwiftUI

struct InvestmentHomeView: View {
    var body: some View {
        TabView {
            StockView()
                .tabItem {
                    Label("Portfolio", systemImage: "chart.pie.fill")
                }

            WatchlistView()
                .tabItem {
                    Label("Watchlist", systemImage: "eye.fill")
                }
        }
    }
}

#Preview {
    InvestmentHomeView()
}


#Preview {
    InvestmentHomeView()
}
