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
                    // A Menu row whose label is a custom HStack (not a plain
                    // Label/Text) otherwise exposes NO accessibility content
                    // at all inside a native menu popup — forcing this
                    // subtree into one opaque element with an explicit
                    // label/identifier is what actually makes it visible to
                    // XCUITest (or VoiceOver). The identifier is a
                    // deterministic, human-readable fixture key (from the
                    // Profile's own name) purely so XCUITest can locate this
                    // row reliably — a UI-test convenience, not app
                    // ownership logic, which resolves everything by
                    // profile.id elsewhere (see ProfileIsolation audit).
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(profile.name)
                    .accessibilityIdentifier("profile.row.\(profile.name.lowercased())")
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
        .accessibilityIdentifier("profile.selector")
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
