//
//  CoreDataProvider.swift
//  im-hybrid-demo
//
//  Created by Personal on 28/11/2024.
//

import CoreData

enum CoreDataProviderError: Error {
    case userAlreadyExists
}


class CoreDataProvider {
    let persistentContainer: NSPersistentContainer
    
    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    init() throws {
        do {
            
            persistentContainer = NSPersistentContainer(name: "CoreStorage")
            
            persistentContainer.loadPersistentStores { description, error in
                if let error = error {
                    fatalError("CoreDataProvider: Unable to load persistent store: \(error)")
                }
            }
            
            if try getUser() == nil {
                let user = CSUser(context: viewContext)
                user.uuid = UUID()
                user.name = "John Doe"
                user.phone = "+1 234 567 890"
                
                try self.saveUser(user: user)
            }
        } catch {
            if case CoreDataProviderError.userAlreadyExists = error {
            } else {
                // Handle other errors
                print("Error initializing CoreDataProvider: \(error)")
                throw error
            }
        }
    }
    
    func saveContext() throws {
        if viewContext.hasChanges {
            do {
                try viewContext.save()
            } catch {
                throw error
            }
        }
    }
    
    // User
    func getUser () throws -> CSUser? {
        let fetchRequest: NSFetchRequest<CSUser> = CSUser.fetchRequest()
        do {
            return try viewContext.fetch(fetchRequest).first
        } catch {
            throw error
        }
    }
    
    func saveUser(user: CSUser) throws {
        if let existingUser = try getUser() {
            throw CoreDataProviderError.userAlreadyExists
        }
        
        do {
            viewContext.insert(user)
            try saveContext()
        } catch {
            throw error
        }
    }
    
    
    // Sessions
    func fetchSessions() throws -> [CSSession] {
        let fetchRequest: NSFetchRequest<CSSession> = CSSession.fetchRequest()
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            throw error
        }
    }
    
    func getSessionByUuid(uuid: UUID) throws -> CSSession? {
        let fetchRequest: NSFetchRequest<CSSession> = CSSession.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "uuid == %@", uuid as CVarArg)
        do {
            return try viewContext.fetch(fetchRequest).first
        } catch {
            throw error
        }
    }
    
    func saveSession(session: CSSession) throws {
        do {
            viewContext.insert(session)
            try saveContext()
        } catch {
            throw error
        }
    }
    
    func deleteSession(session: CSSession) throws {
        do {
            viewContext.delete(session)
            try saveContext()
        } catch {
            throw error
        }
    }
    
    func deleteAllSessions() throws {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = CSSession.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

        do {
            try viewContext.execute(deleteRequest)
            try saveContext()
        } catch {
            throw error
        }
    }
    
    // Passkeys
    func fetchPasskeys() throws -> [CSPasskey] {
        let fetchRequest: NSFetchRequest<CSPasskey> = CSPasskey.fetchRequest()
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            throw error
        }
    }
    
    func newPasskey(credId: String, counter: Int32, publicKeyHex: String, aaguid: UUID) throws -> CSPasskey {
        let newPasskey = CSPasskey(context: viewContext)
        newPasskey.uuid = UUID()
        newPasskey.counter = counter
        newPasskey.cred_id = credId
        newPasskey.created_at = Date()
        newPasskey.aaguid = aaguid
        newPasskey.public_key_hex = publicKeyHex
        
        do {
            viewContext.insert(newPasskey)
            try saveContext()
        } catch {
            throw error
        }
        
        return newPasskey
    }
    
    func updatePasskey(passkey: CSPasskey) throws {
        do {
            try saveContext()
        } catch {
            throw error
        }
    }
    
    func getFirstActivePasskey() throws -> CSPasskey? {
        let fetchRequest: NSFetchRequest<CSPasskey> = CSPasskey.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "is_disabled == NO")
        do {
            return try viewContext.fetch(fetchRequest).first
        } catch {
            fatalError("CoreDataProvider: Unable to fetch passkeys: \(error)")
        }
    }
}
