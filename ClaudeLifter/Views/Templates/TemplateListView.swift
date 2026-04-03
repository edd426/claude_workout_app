import SwiftUI

struct TemplateListView: View {
    @Environment(\.dependencies) private var deps
    @State private var vm: TemplateListViewModel?
    @State private var showEditor = false
    @State private var selectedTemplate: WorkoutTemplate? = nil

    var body: some View {
        Group {
            if let vm {
                templateList(vm: vm)
            } else {
                ProgressView()
            }
        }
        .task {
            if vm == nil, let deps {
                vm = TemplateListViewModel(
                    templateRepository: deps.templateRepository
                )
                await vm?.loadTemplates()
            }
        }
    }

    private func templateList(vm: TemplateListViewModel) -> some View {
        List {
            ForEach(vm.templates, id: \.id) { template in
                Button {
                    selectedTemplate = template
                } label: {
                    TemplateRowView(template: template)
                }
            }
            .onDelete { offsets in
                for i in offsets {
                    Task { await vm.deleteTemplate(vm.templates[i]) }
                }
            }
        }
        .navigationTitle("Templates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New", systemImage: "plus") { showEditor = true }
            }
        }
        .sheet(isPresented: $showEditor, onDismiss: { Task { await vm.loadTemplates() } }) {
            if let deps {
                TemplateEditorView(
                    vm: TemplateEditorViewModel(
                        template: nil,
                        templateRepository: deps.templateRepository
                    )
                )
            }
        }
        .sheet(item: $selectedTemplate, onDismiss: { Task { await vm.loadTemplates() } }) { template in
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
}
