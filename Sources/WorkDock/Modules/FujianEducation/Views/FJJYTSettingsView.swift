import SwiftUI

struct FJJYTSettingsView: View {
    @AppStorage("fjsjyt.cookieRefreshMinutes") private var cookieRefreshMinutes: Double = 30
    @AppStorage("fjsjyt.reminderMinutes") private var reminderMinutes: Double = 15
    @AppStorage("fjsjyt.useKeychain") private var useKeychain = false

    var body: some View {
        Form {
            Stepper(value: $cookieRefreshMinutes, in: 5...180, step: 5) {
                HStack {
                    Text(L.cookieRefreshInterval)
                    Spacer()
                    Text("\(Int(cookieRefreshMinutes)) \(L.minutes)")
                        .foregroundStyle(.secondary)
                }
            }
            Stepper(value: $reminderMinutes, in: 5...120, step: 5) {
                HStack {
                    Text(L.reminderInterval)
                    Spacer()
                    Text("\(Int(reminderMinutes)) \(L.minutes)")
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $useKeychain) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.useKeychain)
                    Text(L.useKeychainDesc)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
