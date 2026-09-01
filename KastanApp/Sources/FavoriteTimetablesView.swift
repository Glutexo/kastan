import Kastan
import SwiftUI

/// Manages every timetable favorite in the secondary window opened from the main toolbar.
struct FavoriteTimetablesView: View {
    /// Keeps the complete catalog usable in a narrow dedicated manager window.
    static let minimumWindowWidth: CGFloat = 320
    static let defaultWindowWidth = minimumWindowWidth

    @AppStorage(TimetableFavorites.storageKey) private var serializedTimetableFavorites = "[]"
    let timetables: [TransitTimetable]

    init(timetables: [TransitTimetable] = TransitTimetable.known) {
        self.timetables = timetables
    }

    var body: some View {
        List {
            ForEach(AppTimetableGroup.allCases) { group in
                let groupedTimetables = group.timetables(in: timetables)
                if !groupedTimetables.isEmpty {
                    Section {
                        ForEach(groupedTimetables, id: \.appIdentity) { timetable in
                            timetableRow(timetable, isFavorite: favorites.contains(timetable))
                        }
                    } header: {
                        Text(group.title)
                    }
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("Favorite timetables")
    }

    private var favorites: TimetableFavorites {
        TimetableFavorites(serialized: serializedTimetableFavorites, catalog: timetables)
    }

    private func timetableRow(_ timetable: TransitTimetable, isFavorite: Bool) -> some View {
        let actionLabel: LocalizedStringKey = isFavorite
            ? "Remove timetable from favorites"
            : "Add timetable to favorites"

        return Button {
            toggle(timetable)
        } label: {
            HStack(spacing: 10) {
                Text(timetable.appDisplayName)
                Spacer(minLength: 8)
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(actionLabel))
        .help(Text(actionLabel))
    }

    private func toggle(_ timetable: TransitTimetable) {
        var updatedFavorites = favorites
        updatedFavorites.toggle(timetable)
        serializedTimetableFavorites = updatedFavorites.serialized
    }
}
