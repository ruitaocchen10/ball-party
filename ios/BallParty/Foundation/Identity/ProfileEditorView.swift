import PhotosUI
import SwiftUI

/// The "Edit profile" sheet — name, and a photo or starter avatar. Mirrors
/// `ProfileEditor.tsx`'s dialog: a form screen with the avatar and name, and
/// a photo-chooser screen (upload or pick a starter design) one tap away.
struct ProfileEditorView: View {
    @ObservedObject var viewModel: ProfileEditorViewModel
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .form: form
                case .photo: PhotoChooser(viewModel: viewModel)
                }
            }
            .screenBackground()
            .navigationTitle(viewModel.step == .form ? "Edit profile" : "Profile photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .onChange(of: viewModel.saved) { _, saved in
            if saved {
                onSaved()
                dismiss()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            switch viewModel.step {
            case .form:
                Button("Cancel") { dismiss() }
            case .photo:
                Button("Back") { viewModel.step = .form }
            }
        }
        if viewModel.step == .form {
            ToolbarItem(placement: .confirmationAction) {
                Button(viewModel.isSaving ? "Saving…" : "Save") {
                    Task { await viewModel.save() }
                }
                .disabled(viewModel.isSaving || viewModel.isUploadingAvatar)
            }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button { viewModel.step = .photo } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Avatar(name: viewModel.displayName, url: viewModel.avatarURL, size: 88)
                        cameraBadge
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isUploadingAvatar)
                .accessibilityLabel("Change profile photo")
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Display name").fieldLabel()
                    TextField("Display name", text: $viewModel.displayName)
                        .textContentType(.nickname)
                        .focused($nameFocused)
                        .fieldStyle()
                }

                if let usernameField = viewModel.usernameField {
                    UsernameFieldView(field: usernameField)
                }

                if let notice = viewModel.notice {
                    Text(notice).font(.sans(14)).foregroundStyle(Theme.hiddenText)
                }
            }
            .padding(16)
        }
    }

    private var cameraBadge: some View {
        ZStack {
            Circle().fill(Theme.hidden)
            Image(systemName: "camera.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.fg)
        }
        .frame(width: 30, height: 30)
        .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
    }
}

/// The "choose your look" screen: upload from the library, or pick and
/// recolor a starter design — `ProfilePhotoChooser` + `PresetAvatarPicker` on the web.
private struct PhotoChooser: View {
    @ObservedObject var viewModel: ProfileEditorViewModel
    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Text(viewModel.isUploadingAvatar ? "Uploading…" : "Upload from device")
                }
                .buttonStyle(.ghost)
                .disabled(viewModel.isUploadingAvatar)

                AvatarPresetPicker(viewModel: viewModel)

                if let notice = viewModel.notice {
                    Text(notice).font(.sans(14)).foregroundStyle(Theme.hiddenText)
                }
            }
            .padding(16)
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await viewModel.uploadPhoto(data)
                } else {
                    viewModel.notice = "Choose an image file."
                }
                pickedItem = nil
            }
        }
    }
}

/// The customizable-palette grid of starter avatars.
private struct AvatarPresetPicker: View {
    @ObservedObject var viewModel: ProfileEditorViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Starter avatars").fieldLabel()
            Text("Customize the palette, then choose a design.")
                .font(.sans(13))
                .foregroundStyle(Theme.fgMuted)

            HStack(spacing: 10) {
                ForEach(viewModel.paletteColors.indices, id: \.self) { index in
                    ColorPicker("Avatar color \(index + 1)", selection: $viewModel.paletteColors[index])
                        .labelsHidden()
                }
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(BeamAvatar.presets, id: \.seed) { preset in
                    Button {
                        Task { await viewModel.choosePreset(seed: preset.seed) }
                    } label: {
                        BeamAvatarView(seed: preset.seed, palette: viewModel.paletteColors, size: 56)
                            .overlay {
                                if viewModel.selectedPresetSeed == preset.seed {
                                    Circle().strokeBorder(Theme.hidden, lineWidth: 2)
                                } else {
                                    Circle().strokeBorder(Theme.line, lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isUploadingAvatar)
                    .accessibilityLabel("Choose \(preset.label) avatar")
                }
            }
        }
    }
}

/// The one-time "confirm your username" sheet, shown over the app after
/// sign-in to accounts that were given a generated username.
struct UsernameConfirmView: View {
    @ObservedObject var viewModel: UsernameConfirmViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pick your username").slabTitle(34)
                .accessibilityAddTraits(.isHeader)
            Text("Friends find you by your username. We picked one for you; keep it or change it now. You can change it later in Edit profile.")
                .font(.sans(15))
                .foregroundStyle(Theme.fgMuted)

            UsernameFieldView(field: viewModel.field)

            if let notice = viewModel.notice {
                Text(notice).font(.sans(14)).foregroundStyle(Theme.hiddenText)
            }

            Button {
                Task { await viewModel.save() }
            } label: {
                Text(viewModel.isSaving ? "Saving…" : "Save")
            }
            .buttonStyle(.solid)
            .disabled(viewModel.isSaving)

            Button("Keep current username") { viewModel.keep() }
                .buttonStyle(.quiet)
                .frame(maxWidth: .infinity)
                .disabled(viewModel.isSaving)
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .screenBackground()
        .presentationDetents([.medium, .large])
        .onChange(of: viewModel.finished) { _, finished in
            if finished { dismiss() }
        }
        .onDisappear { viewModel.dismissed() }
    }
}

/// The username field with its live availability hint. Shared by the editor
/// and the one-time confirm prompt.
struct UsernameFieldView: View {
    @ObservedObject var field: UsernameFieldModel

    var body: some View {
        let hint = self.hint
        VStack(alignment: .leading, spacing: 6) {
            Text("Username").fieldLabel()
            TextField("Username", text: $field.text)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .fieldStyle()
                .onChange(of: field.text) { _, _ in field.textChanged() }
            Text(hint.text).font(.sans(13)).foregroundStyle(hint.color)
        }
    }

    private var hint: (text: String, color: Color) {
        switch field.status {
        case .idle, .unchanged:
            return ("3–20 letters, numbers or underscores. Friends find you by this.", Theme.fgMuted)
        case .checking:
            return ("Checking…", Theme.fgMuted)
        case .available:
            return ("Available", Theme.fgMuted)
        case .rejected(let message):
            return (message, Theme.hiddenText)
        case .unchecked:
            return ("Couldn’t check availability. You can still try saving.", Theme.fgMuted)
        }
    }
}
