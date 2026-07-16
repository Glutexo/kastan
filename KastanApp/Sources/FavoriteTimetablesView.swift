import Kastan
import SwiftUI

/// Manages every timetable favorite from one native sidebar destination.
struct FavoriteTimetablesView: View {
    @AppStorage(TimetableFavorites.storageKey) private var serializedTimetableFavorites = "[]"

    var body: some View {
        List {
            Section {
                if favorites.timetables.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("No favorite timetables", systemImage: "star")
                            .font(.headline)
                        Text("Use the stars to choose which timetables appear first in search menus.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(favorites.timetables, id: \.slug) { timetable in
                        timetableRow(timetable, isFavorite: true)
                    }
                }
            }

            ForEach(AppTimetableGroup.allCases) { group in
                let timetables = favorites.nonFavorites(in: group.timetables)
                if !timetables.isEmpty {
                    Section {
                        ForEach(timetables, id: \.slug) { timetable in
                            timetableRow(timetable, isFavorite: false)
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
        TimetableFavorites(serialized: serializedTimetableFavorites)
    }

    private func timetableRow(_ timetable: IDOSTimetable, isFavorite: Bool) -> some View {
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

    private func toggle(_ timetable: IDOSTimetable) {
        var updatedFavorites = favorites
        updatedFavorites.toggle(timetable)
        serializedTimetableFavorites = updatedFavorites.serialized
    }
}
