import SwiftUI

struct ExerciseLibraryView: View {
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ExerciseLibraryViewModel?
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var showCreateExercise = false

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
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showCreateExercise = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreateExercise) {
                CreateExerciseView {
                    Task { await vm?.loadExercises() }
                }
            }
        }
        .task {
            if vm == nil, let deps {
                vm = ExerciseLibraryViewModel(
                    exerciseRepository: deps.exerciseRepository
                )
                await vm?.loadFilterOptions()
                await vm?.loadExercises()
            }
        }
    }

    private func libraryContent(vm: ExerciseLibraryViewModel) -> some View {
        VStack(spacing: 0) {
            searchBar(vm: vm)

            FilterChipsView(
                categories: vm.filterCategories,
                categoryValues: vm.categoryValues,
                activeFilters: vm.activeFilters,
                onSelect: { cat, val in
                    vm.selectFilter(category: cat, value: val)
                    Task { await vm.loadExercises() }
                },
                onRemove: { cat in
                    vm.removeFilter(category: cat)
                    Task { await vm.loadExercises() }
                },
                onClearAll: {
                    vm.clearFilters()
                    Task { await vm.loadExercises() }
                }
            )

            List(vm.exercises, id: \.id) { exercise in
                exerciseRow(exercise, vm: vm)
            }
            .listStyle(.plain)
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

    private func searchBar(vm: ExerciseLibraryViewModel) -> some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(BrandTheme.secondaryText)
            TextField("Search exercises...", text: Binding(
                get: { vm.searchQuery },
                set: { vm.searchQuery = $0 }
            ))
            .textFieldStyle(.plain)
            .accessibilityIdentifier("exerciseSearchField")
            if !vm.searchQuery.isEmpty {
                Button {
                    vm.searchQuery = ""
                    Task { await vm.performSearch() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(BrandTheme.secondaryText)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(BrandTheme.cardBackground)
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.vertical, 8)
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
