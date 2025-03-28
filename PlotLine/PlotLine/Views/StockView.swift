//
//  StockView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 3/26/25.
//

import SwiftUI

struct StockView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Investing Tools")
                .font(.largeTitle)
                .bold()
            
            NavigationLink(destination: InvestmentQuizView()) {
                Label("Stock Quiz", systemImage: "questionmark.circle.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green)
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }
        }
        .padding()
    }
}

#Preview {
    StockView()
}

