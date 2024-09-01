//
//  RebaseDailyNewsApp.swift
//  RebaseDailyNews
//
//  Created by davirian on 2024/9/1.
//

import SwiftUI

@main
struct RebaseDailyNewsApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
