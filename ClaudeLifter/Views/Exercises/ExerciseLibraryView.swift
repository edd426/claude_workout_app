import SwiftUI

struct ExerciseLibraryView: View {
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ExerciseLibraryViewModel?
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var showCreateExercise = false

    var selectionMode: Bool = false
    var onSelect: ((Exercise) -> Void)? = nil
    /// Opens pre-filtered to this primary muscle ("Machine taken → Other…",
    /// #169), when the catalog has it as a `muscle_group` tag. The chip can be
    /// removed like any other filter.
    var initialMuscleFilter: String? = nil

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
            .searchable(
                text: Binding(
                    get: { vm?.searchQuery ?? "" },
                    set: { vm?.searchQuery = $0 }
                ),
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search exercises..."
            )
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
                            Label("New exercise", systemImage: "plus")
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
                if let muscle = initialMuscleFilter,
                   vm?.categoryValues["muscle_group"]?.contains(muscle) == true {
                    vm?.selectFilter(category: "muscle_group", value: muscle)
                }
                await vm?.loadExercises()
            }
        }
    }

    private func libraryContent(vm: ExerciseLibraryViewModel) -> some View {
        VStack(spacing: 0) {
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

            if let message = vm.errorMessage {
                libraryErrorBanner(message, vm: vm)
            }
            if vm.isNarrowed {
                // Says what applies: the query and the chips together (#155).
                Text(resultLine(vm))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("libraryResultCount")
            }
            List(vm.exercises, id: \.id) { exercise in
                exerciseRow(exercise, vm: vm)
                    .onAppear {
                        // The unfiltered library loads 50 at a time; fetch
                        // the next page as the last row appears.
                        if exercise.id == vm.exercises.last?.id {
                            Task { await vm.loadMore() }
                        }
                    }
            }
            .listStyle(.plain)
            .overlay { emptyState(vm) }
            .onChange(of: vm.searchQuery) { _, _ in
                searchTask?.cancel()
                searchTask = Task {
                    // A cancelled sleep is the debounce working, not a failure.
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    await vm.performSearch()
                }
            }
        }
    }

    private func resultLine(_ vm: ExerciseLibraryViewModel) -> String {
        let count = vm.exercises.count == 1 ? "1 exercise" : "\(vm.exercises.count) exercises"
        return "\(count) · \(vm.criteriaDescription)"
    }

    @ViewBuilder
    private func emptyState(_ vm: ExerciseLibraryViewModel) -> some View {
        if vm.exercises.isEmpty, !vm.isLoading, vm.isNarrowed {
            ContentUnavailableView {
                Label("No matches", systemImage: "magnifyingglass")
            } description: {
                Text("Nothing matches \(vm.criteriaDescription).")
            } actions: {
                if !vm.activeFilters.isEmpty {
                    Button("Clear Filters") {
                        vm.clearFilters()
                        Task { await vm.loadExercises() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func libraryErrorBanner(_ message: String, vm: ExerciseLibraryViewModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BrandTheme.warning)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry") {
                Task {
                    await vm.loadFilterOptions()
                    await vm.loadExercises()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(BrandTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding(.vertical, 4)
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
