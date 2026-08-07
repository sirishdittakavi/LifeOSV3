import SwiftUI
import SwiftData

struct ProfilePicker: View {
    @Bindable var selection: SelectedProfile
    @Query(sort: \Profile.name) private var profiles: [Profile]
    @State private var showingProfiles = false

    private var activeProfiles: [Profile] { profiles.filter(\.isActive) }

    var body: some View {
        Menu {
            ForEach(activeProfiles) { profile in
                Button {
                    selection.profile = profile
                } label: {
                    Label(profile.name, systemImage: profile.id == selection.profile?.id ? "checkmark" : "person")
                }
            }
            Divider()
            Button { showingProfiles = true } label: {
                Label("Manage Profiles", systemImage: "person.2.badge.gearshape")
            }
        } label: {
            Label(selection.profile?.name ?? "Profile", systemImage: "person.crop.circle")
        }
        .onAppear {
            if selection.profile == nil {
                let savedID = UserDefaults.standard.string(forKey: SelectedProfile.lastProfileKey)
                    .flatMap(UUID.init(uuidString:))
                selection.profile = activeProfiles.first { $0.id == savedID } ?? activeProfiles.first
            }
        }
        .sheet(isPresented: $showingProfiles) {
            ProfileManagerView(selection: selection)
        }
    }
}
