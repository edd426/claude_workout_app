import SwiftUI
import SwiftData

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ExerciseLibraryViewModel?
    @State private var searchTask: Task<Void, Never>? = nil

    var selectionMode: Bool = false
    var onSelect: ((Exercise) -> Void)? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let vm {
                    libraryContent(vm: vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if selectionMode {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .task {
            if vm == nil {
                vm = ExerciseLibraryViewModel(
                    exerciseRepository: SwiftDataExerciseRepository(context: modelContext)
                )
                await vm?.loadExercises()
            }
        }
    }

    private func libraryContent(vm: ExerciseLibraryViewModel) -> some View {
        VStack(spacing: 0) {
            FilterChipsView(
                categories: vm.filterCategories,
                selectedCategory: vm.selectedCategory,
                selectedValue: vm.selectedValue,
                onSelect: { cat, val in
                    vm.selectFilter(category: cat, value: val)
                    Task { await vm.loadExercises() }
                },
                onClear: {
                    vm.clearFilter()
                    Task { await vm.loadExercises() }
                }
            )

            List(vm.exercises, id: \.id) { exercise in
                exerciseRow(exercise, vm: vm)
            }
            .listStyle(.plain)
            .searchable(text: Binding(
                get: { vm.searchQuery },
                set: { vm.searchQuery = $0 }
            ))
            .onChange(of: vm.searchQuery) { _, _ in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    await vm.performSearch()
                }
            }
        }
    }

    private func exerciseRow(_ exercise: Exercise, vm: ExerciseLibraryViewModel) -> some View {
        Group {
            if selectionMode {
                Button {
                    onSelect?(exercise)
                    dismiss()
                } label: {
                    ExerciseRowView(exercise: exercise)
                }
            } else {
                NavigationLink {
                    ExerciseDetailView(exercise: exercise)
                } label: {
                    ExerciseRowView(exercise: exercise)
                }
            }
        }
    }
}
