import SwiftUI

/// Manage Templates, pushed from Today's "Other workouts" header.
struct TemplateListView: View {
    @Environment(\.dependencies) private var deps
    @State private var vm: TemplateListViewModel?
    @State private var showEditor = false
    @State private var selectedTemplate: WorkoutTemplate? = nil
    @State private var pendingDelete: WorkoutTemplate?
    @State private var deleteConfirmed = 0

    var body: some View {
        Group {
            if let vm {
                templateList(vm: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Templates")
        .task {
            if vm == nil, let deps {
                vm = TemplateListViewModel(
                    templateRepository: deps.templateRepository,
                    workoutRepository: deps.workoutRepository
                )
                await vm?.loadTemplates()
            }
        }
    }

    private func templateList(vm: TemplateListViewModel) -> some View {
        List {
            ForEach(vm.templates, id: \.id) { template in
                templateRow(template, vm: vm)
            }
        }
        .overlay {
            if vm.templates.isEmpty && !vm.isLoading {
                ContentUnavailableView(
                    "No templates",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Tap New to build one.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New", systemImage: "plus") { showEditor = true }
                    .accessibilityIdentifier("newTemplate")
            }
        }
        .sensoryFeedback(.warning, trigger: deleteConfirmed)
        .confirmationDialog(
            "Delete this template?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { template in
            Button("Delete \"\(template.name)\"", role: .destructive) {
                deleteConfirmed += 1
                Task { await vm.deleteTemplate(template) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Past workouts started from it are kept.")
        }
        .sheet(isPresented: $showEditor, onDismiss: { Task { await vm.loadTemplates() } }) {
            editor(for: nil)
        }
        .sheet(item: $selectedTemplate, onDismiss: { Task { await vm.loadTemplates() } }) { template in
            editor(for: template)
        }
    }

    /// The row opens the editor; its menu offers Edit and Delete, so delete
    /// is never swipe-only (UI-P7) and is always confirmed (UI-P6).
    private func templateRow(_ template: WorkoutTemplate, vm: TemplateListViewModel) -> some View {
        HStack(spacing: 8) {
            Button {
                selectedTemplate = template
            } label: {
                TemplateRowView(template: template, lastDone: vm.lastDoneDate(for: template))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                Button("Edit", systemImage: "pencil") { selectedTemplate = template }
                Section {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        pendingDelete = template
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(BrandTheme.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(template.name)")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                pendingDelete = template
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(BrandTheme.destructive)
        }
    }

    @ViewBuilder
    private func editor(for template: WorkoutTemplate?) -> some View {
        if let deps {
            TemplateEditorView(
                vm: TemplateEditorViewModel(
                    template: template,
                    templateRepository: deps.templateRepository
                )
            )
        }
    }
}
