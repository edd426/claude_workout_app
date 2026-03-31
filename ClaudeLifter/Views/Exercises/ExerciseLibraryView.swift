import SwiftUI
import SwiftData

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ExerciseLibraryViewModel?
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var showCreateExercise = false

    var selectionMode: Bool = false
    var onSelect: ((Exercise) -> Void)? = nil
    var uploadService: (any ImageUploadServiceProtocol)? = nil

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
                    ExerciseDetailView(exercise: exercise, uploadService: uploadService)
                } label: {
                    ExerciseRowView(exercise: exercise)
                }
            }
        }
    }
}
