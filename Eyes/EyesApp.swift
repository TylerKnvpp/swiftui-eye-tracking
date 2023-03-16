//
//  EyesApp.swift
//  Eyes
//
//  Created by Tyler Knapp on 3/16/23.
//

import SwiftUI

@main
struct EyesApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
