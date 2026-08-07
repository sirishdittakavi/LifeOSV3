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
                    HStack {
                        ProfileAvatarView(profile: profile, size: 24)
                        Text(profile.name)
                        if profile.id == selection.profile?.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button { showingProfiles = true } label: {
                Label("Manage Profiles", systemImage: "person.2.badge.gearshape")
            }
        } label: {
            HStack(spacing: 6) {
                if let profile = selection.profile {
                    ProfileAvatarView(profile: profile, size: 24)
                } else {
                    Image(systemName: "person.crop.circle")
                }
                Text(selection.profile?.name ?? "Profile")
            }
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
