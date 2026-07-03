import Foundation

public protocol RemindersProviding: Sendable {
  func reminderLists() throws -> [GatewayCalendar]
  func reminders() throws -> [Reminder]
  func reminder(reminderId: String) throws -> Reminder?
}

public protocol RemindersWriting: Sendable {
  func createReminderList(_ input: CreateReminderListInput) throws -> GatewayCalendar
  func createReminder(_ reminder: Reminder) throws -> Reminder
  func updateReminder(_ reminder: Reminder) throws -> Reminder
  func deleteReminder(reminderId: String) throws -> DeleteResult
}
