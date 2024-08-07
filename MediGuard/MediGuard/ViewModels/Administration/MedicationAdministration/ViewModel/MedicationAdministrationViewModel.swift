//
//  MedicationDetailViewModel.swift
//  MediGuard
//
//  Created by Alvaro Guillermo del Castillo Forero on 13.06.24.
//

import SwiftUI
import FirebaseFirestore
import FirebaseFirestoreSwift
import UserNotifications

// MARK: - MedicationDetailViewModel Klasse

/**
 Die MedicationDetailViewModel-Klasse verwaltet die Daten und die Logik für die Detailansicht von Medikamenten.
 
 Diese Klasse ermöglicht das Abrufen, Hinzufügen, Aktualisieren und Löschen von Medikamenten sowie das Planen von Benachrichtigungen.
 
 - Eigenschaften:
    - medications: Eine Liste von Medikamenten.
    - errorMessage: Eine Fehlermeldung, die angezeigt wird, wenn ein Fehler auftritt.
    - listener: Eine ListenerRegistration, um den Firestore-Listener zu entfernen.
 
 - Funktionen:
    - fetchMedications(userId:): Ruft die Medikamente für den angegebenen Benutzer in Echtzeit ab.
    - removeListener(): Entfernt den Listener und löscht die Medikamente.
    - scheduleNotification(for:): Plant eine Benachrichtigung für das angegebene Medikament.
    - listScheduledNotifications(): Listet alle geplanten Benachrichtigungen auf.
    - addMedication(name:intakeTime:day:nextIntakeDate:color:dosage:dosageUnit:userId:): Fügt ein neues Medikament hinzu und plant eine Benachrichtigung.
    - deleteMedication(_:userId:): Löscht ein Medikament und entfernt die zugehörige Benachrichtigung.
    - updateMedication(_:userId:): Aktualisiert ein Medikament und plant eine neue Benachrichtigung.
 */
@MainActor
class MedicationAdminstrationViewModel: ObservableObject {
    @Published var medications: [Medication] = []
    @Published var errorMessage: String = ""
    
    private var listener: ListenerRegistration?

    /// Initialisiert das ViewModel und listet geplante Benachrichtigungen auf.
    init() {
        listScheduledNotifications()
        print("MedicationAdminstrationViewModel initialisiert")
        
        
        
    }
    

    // MARK: - Medikamente abrufen
    
    /**
     Ruft die Medikamente für einen gegebenen Benutzer aus Firestore ab und hört auf alle Änderungen.
     
     - Parameter userId: Die ID des Benutzers, dessen Medikamente abgerufen werden sollen.
     */
    func fetchMedications(userId: String) {
        // Entfernt den vorherigen Listener, falls vorhanden
        listener?.remove()
        // Fügt einen neuen Listener hinzu, um auf Änderungen in der Medikamenten-Sammlung zu hören
        listener = Firestore.firestore().collection("users").document(userId).collection("medications")
            .addSnapshotListener { querySnapshot, error in
                // Fehlerbehandlung
                if let error = error {
                    self.errorMessage = "Fehler beim Abrufen der Medikamente: \(error.localizedDescription)"
                    return
                }
                
                // Überprüft, ob Dokumente vorhanden sind
                guard let documents = querySnapshot?.documents else {
                    self.errorMessage = "Keine Medikamente gefunden"
                    return
                }
                
                // Konvertiert die Dokumente in Medication-Objekte und speichert sie in der medications-Array
                self.medications = documents.compactMap { doc -> Medication? in
                    try? doc.data(as: Medication.self)
                }
            }
    }

    // MARK: - Benachrichtigung planen
    
    /**
     Planen einer Benachrichtigung für ein Medikament.

     Diese Methode plant eine lokale Benachrichtigung für die Einnahme eines Medikaments am nächsten geplanten Wochentag zur angegebenen Uhrzeit.

     - Parameter medication: Das Medikament, für das die Benachrichtigung geplant werden soll. Enthält den Namen, den Wochentag und die Einnahmezeit.
     */
    func scheduleNotification(for medication: Medication) {
        let content = UNMutableNotificationContent()
        content.title = "Medikamentenerinnerung"
        content.body = "Es ist Zeit, \(medication.name) einzunehmen."
        content.sound = UNNotificationSound.default

        // Aktuelles Datum und Zeit in der lokalen Zeitzone
        let now = Date()
        let calendar = Calendar.current
        let timeZone = TimeZone.current

        // Konvertiere den Tag in ein Weekday-Enum
        guard let weekday = Weekday.from(medication.day) else {
            self.errorMessage = "Ungültiger Wochentag: \(String(describing: medication.day))"
            return
        }

        // Berechne das nächste Datum für den angegebenen Wochentag und die Einnahmezeit
        if let nextDate = Weekday.next(weekday, after: now, intakeHour: medication.intakeTime.hour ?? 0, intakeMinute: medication.intakeTime.minute ?? 0) {
            var dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextDate)
            dateComponents.timeZone = timeZone

            // Erstelle das Datum aus den DateComponents
            guard let notificationTime = calendar.date(from: dateComponents) else {
                self.errorMessage = "Fehler beim Erstellen der Benachrichtigungszeit aus den DateComponents"
                return
            }

            // Ausgabe der geplanten Zeit in der lokalen Zeitzone
            print("Geplante Zeit (local): \(dateComponents)")
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            formatter.timeZone = timeZone
            print("Benachrichtigungszeit (local): \(formatter.string(from: notificationTime))")

            // Überprüfe, ob die Benachrichtigungszeit in der Zukunft liegt
            if notificationTime > now {
                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

                // Füge die Benachrichtigung hinzu
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        self.errorMessage = "Fehler beim Planen der Benachrichtigung: \(error.localizedDescription)"
                    } else {
                        print("Benachrichtigung geplant für \(medication.name) um \(dateComponents.hour ?? 0):\(dateComponents.minute ?? 0) am \(weekday.name)")
                    }
                }
            } else {
                self.errorMessage = "Die geplante Benachrichtigungszeit liegt in der Vergangenheit"
            }
        } else {
            self.errorMessage = "Fehler bei der Berechnung des nächsten Wochentages"
        }
    }












    // MARK: - Geplante Benachrichtigungen auflisten

    /**
     Listet alle geplanten Benachrichtigungen auf und gibt deren Details aus.
     */
    func listScheduledNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { notifications in
            notifications.forEach { notification in
                guard let dateComponents = (notification.trigger as? UNCalendarNotificationTrigger)?.dateComponents,
                      let _ = Calendar.current.date(from: dateComponents) else { return }

                // Konvertiere die Benachrichtigungszeit in die lokale Zeitzone
                let timeZone = TimeZone.current
                var localDateComponents = dateComponents
                localDateComponents.timeZone = timeZone
                if let localDate = Calendar.current.date(from: localDateComponents) {
                    print("-----> Benachrichtigungen: ", localDate, notification.identifier)
                } else {
                    print("-----> Fehler beim Konvertieren der Benachrichtigungszeit in die lokale Zeitzone")
                }
            }
        }
    }

    // MARK: - Medikament hinzufügen
    
    /**
     Fügt ein neues Medikament zur Firestore-Datenbank hinzu.
     
     - Parameter name: Der Name des Medikaments.
     - Parameter intakeTime: Die Zeit, zu der das Medikament eingenommen werden soll.
     - Parameter day: Der Tag, an dem das Medikament eingenommen werden soll.
     - Parameter nextIntakeDate: Das Datum der nächsten Einnahme, falls vorhanden.
     - Parameter color: Die Farbe des Medikaments.
     - Parameter dosage: Die Dosierung des Medikaments.
     - Parameter dosageUnit: Die Einheit der Dosierung.
     - Parameter userId: Die ID des Benutzers, dem das Medikament gehört.
     - Throws: `ValidationError` falls die Validierung fehlschlägt.
     */
    func addMedication(name: String, intakeTime: DateComponents, day: Int, nextIntakeDate: DateComponents?, color: MedicationColor, dosage: Int, dosageUnit: DosageUnit, userId: String, daily: Bool) throws {
            if name.isEmpty {
                throw ValidationError.emptyName
            }
            
            if medications.contains(where: { $0.name == name && $0.intakeTime == intakeTime }) {
                throw ValidationError.duplicateMedication
            }

            let firestore = Firestore.firestore()
            let medicationRef = firestore.collection("users").document(userId).collection("medications")

            let newMedication = Medication(id: UUID().uuidString, name: name, intakeTime: intakeTime, day: day, nextIntakeDate: nextIntakeDate, color: color, dosage: dosage, dosageUnit: dosageUnit, daily: daily)
            
            do {
                if daily {
                    for weekday in Weekday.allCases {
                        let dailyMedication = Medication(id: UUID().uuidString, name: name, intakeTime: intakeTime, day: weekday.rawValue, nextIntakeDate: nextIntakeDate, color: color, dosage: dosage, dosageUnit: dosageUnit, daily: daily)
                        try medicationRef.addDocument(from: dailyMedication) { error in
                            if let error = error {
                                self.errorMessage = "Fehler beim Hinzufügen des Medikaments: \(error.localizedDescription)"
                                return
                            }
                            // Planen der Benachrichtigung für tägliche Medikamente
                            self.scheduleNotification(for: dailyMedication)
                            self.listScheduledNotifications()
                        }
                    }
                } else {
                    try medicationRef.addDocument(from: newMedication) { error in
                        if let error = error {
                            self.errorMessage = "Fehler beim Hinzufügen des Medikaments: \(error.localizedDescription)"
                            return
                        }
                        // Planen der Benachrichtigung für tägliche Medikamente
                        self.scheduleNotification(for: newMedication)
                        self.listScheduledNotifications()
                    }
                }
            } catch let error {
                self.errorMessage = "Fehler beim Serialisieren des Medikaments: \(error.localizedDescription)"
            }

            if let nextIntakeDate = nextIntakeDate {
                let nextMedicationRef = firestore.collection("users").document(userId).collection("medications")
                let nextDay = Weekday.from(nextIntakeDate.weekday)?.rawValue ?? 1
                let nextMedication = Medication(id: UUID().uuidString, name: name, intakeTime: nextIntakeDate, day: nextDay, nextIntakeDate: nil, color: color, dosage: dosage, dosageUnit: dosageUnit, daily: daily)
                
                do {
                    try nextMedicationRef.addDocument(from: nextMedication) { error in
                        if let error = error {
                            self.errorMessage = "Fehler beim Hinzufügen der nächsten Medikation: \(error.localizedDescription)"
                            return
                        }
                        // Planen der Benachrichtigung für tägliche Medikamente
                        self.scheduleNotification(for: nextMedication)
                        self.listScheduledNotifications()
                    }
                } catch let error {
                    self.errorMessage = "Fehler beim Serialisieren der nächsten Medikation: \(error.localizedDescription)"
                }
            }
        }

    // MARK: - Medikament löschen
    
    /**
     Löscht ein Medikament aus der Firestore-Datenbank.
     
     - Parameter medication: Das `Medication`-Objekt, das gelöscht werden soll.
     - Parameter userId: Die ID des Benutzers, dem das Medikament gehört.
     */
    func deleteMedication(_ medication: Medication, userId: String) {
        // Überprüft, ob das Medikament eine ID hat
        guard let id = medication.id else { return }

        // Referenz zum zu löschenden Medikament
        let medicationRef = Firestore.firestore().collection("users").document(userId).collection("medications").document(id)

        // Löscht das Medikament aus der Datenbank
        medicationRef.delete { error in
            if let error = error {
                self.errorMessage = "Fehler beim Löschen des Medikaments: \(error.localizedDescription)"
                return
            }

            // Entfernt das Medikament aus dem lokalen Array
            self.medications.removeAll { $0.id == medication.id }
            
            // Entfernt alle damit verbunden Benachrichtigungen
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        }
    }

    // MARK: - Medikament aktualisieren
    
    /**
     Aktualisiert ein vorhandenes Medikament in der Firestore-Datenbank.
     
     - Parameter medication: Das `Medication`-Objekt, das aktualisiert werden soll.
     - Parameter userId: Die ID des Benutzers, dem das Medikament gehört.
     - Throws: `ValidationError` falls die Validierung fehlschlägt.
     */
    func updateMedication(_ medication: Medication, userId: String) async throws {
        guard let id = medication.id else {
            throw ValidationError.other("Medikations-ID fehlt")
        }

        if medication.name.isEmpty {
            throw ValidationError.emptyName
        }
        
        let firestore = Firestore.firestore()
        let medicationRef = firestore.collection("users").document(userId).collection("medications").document(id)
        let medicationCollectionRef = firestore.collection("users").document(userId).collection("medications")

        do {
            // Löscht das Original-Medikament
            try await medicationRef.delete()
            
            // Löscht alle täglichen Einträge des Medikaments
            let existingMedications = medications.filter { $0.name == medication.name && $0.daily }
            for existingMedication in existingMedications {
                if let existingId = existingMedication.id {
                    let existingMedicationRef = medicationCollectionRef.document(existingId)
                    try await existingMedicationRef.delete()
                }
            }

            // Fügt neue tägliche Einträge hinzu, wenn daily aktiviert ist
            if medication.daily {
                for weekday in Weekday.allCases {
                    let dailyMedication = Medication(
                        id: UUID().uuidString,
                        name: medication.name,
                        intakeTime: medication.intakeTime,
                        day: weekday.rawValue,
                        nextIntakeDate: medication.nextIntakeDate,
                        color: medication.color,
                        dosage: medication.dosage,
                        dosageUnit: medication.dosageUnit,
                        daily: medication.daily
                    )
                    try  medicationCollectionRef.addDocument(from: dailyMedication)
                }
            } else {
                // Füge das Medikament nur einmal hinzu, wenn daily deaktiviert ist
                try  medicationCollectionRef.addDocument(from: medication)
            }

            // Füge ggf. die nächste Einnahme des Medikaments hinzu
            if let nextIntakeDate = medication.nextIntakeDate {
                let nextDay = Weekday.from(nextIntakeDate.weekday)?.rawValue ?? 1
                let nextMedication = Medication(
                    id: UUID().uuidString,
                    name: medication.name,
                    intakeTime: nextIntakeDate,
                    day: nextDay,
                    nextIntakeDate: nil,
                    color: medication.color,
                    dosage: medication.dosage,
                    dosageUnit: medication.dosageUnit,
                    daily: medication.daily
                )
                
                try  medicationCollectionRef.addDocument(from: nextMedication)
                
                // Planen der Benachrichtigung für die nächste Einnahme des Medikaments
                scheduleNotification(for: nextMedication)
                self.listScheduledNotifications()
            }
        } catch let error {
            self.errorMessage = "Fehler beim Aktualisieren des Medikaments: \(error.localizedDescription)"
        }
    }
    
    
   

}
