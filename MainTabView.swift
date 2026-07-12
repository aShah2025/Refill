//
//  MainTabView.swift
//  Refill
//
//  Created by Aaditya Shah on 6/9/26.
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Text("Teacher Home")
                .tabItem {
                    Label("Home", systemImage: "house")
                }
            
            Text("Match Results")
                .tabItem {
                    Label("Match", systemImage: "sparkles")
                }
            
            Text("Parent Feed")
                .tabItem {
                    Label("Feed", systemImage: "heart.text.square")
                }
            
            Text("Impact Dashboard")
                .tabItem {
                    Label("Impact", systemImage: "chart.bar.doc.horizontal")
                }
        }
    }
}

#Preview {
    MainTabView()
}
