import SwiftUI

/// Root of the Body tab (1.9.0): weight, protein, measurements and
/// medications, one scroll of cards. Zero-argument, like the other tab roots;
/// dependencies come from the environment.
struct BodyView: View {
    @Environment(\.dependencies) private var deps
    @State private var models: BodyModels?

    var body: some View {
        NavigationStack {
            Group {
                if let models {
                    BodyScreen(models: models)
                } else {
                    BodyLoadingRow(label: "Loading…")
                }
            }
            .navigationTitle("Body")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            guard models == nil, let deps else { return }
            #if DEBUG
            await BodyScreenshotSeed.seedIfRequested(deps)
            #endif
            models = BodyModels(deps: deps)
        }
    }
}

/// The Body tab's ViewModels, built once per tab.
@MainActor
struct BodyModels {
    let deps: DependencyContainer
    let weightTrend: BodyWeightTrendViewModel
    let weightLog: BodyWeightViewModel
    let measurements: MeasurementsViewModel
    let medications: MedicationListViewModel
    let usualDoses: any MedicationUsualDoseStoring

    init(deps: DependencyContainer) {
        self.deps = deps
        let usualDoses = UserDefaultsUsualDoseStore()
        self.usualDoses = usualDoses
        weightTrend = BodyWeightTrendViewModel(
            repository: deps.bodyWeightRepository,
            settings: deps.settings
        )
        weightLog = BodyWeightViewModel(
            repository: deps.bodyWeightRepository,
            healthKit: deps.healthKitService,
            settings: deps.settings
        )
        measurements = MeasurementsViewModel(
            repository: deps.bodyMeasurementRepository,
            settings: deps.settings
        )
        medications = MedicationListViewModel(
            medicationRepository: deps.medicationRepository,
            doseRepository: deps.medicationDoseRepository,
            usualDoses: usualDoses
        )
    }

    func loadAll() async {
        await weightTrend.load()
        await measurements.load()
        await medications.load()
        await weightLog.load()
        // Readings from a scale app arrive through Health. Best effort: a
        // declined permission leaves the local history as it is.
        await weightLog.importFromHealthKit()
        await weightTrend.load()
    }

    func detailViewModel(for medication: Medication) -> MedicationDetailViewModel {
        MedicationDetailViewModel(
            medication: medication,
            medicationRepository: deps.medicationRepository,
            doseRepository: deps.medicationDoseRepository,
            usualDoses: usualDoses
        )
    }

    /// A fresh ViewModel for the full weight screen, so its range picker
    /// never changes the Body card's 90 days.
    func trendScreenViewModel() -> BodyWeightTrendViewModel {
        BodyWeightTrendViewModel(repository: deps.bodyWeightRepository, settings: deps.settings)
    }
}

private struct BodyScreen: View {
    let models: BodyModels
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                BodyWeightSection(models: models)
                BodyProteinSection(models: models)
                MeasurementsSection(vm: models.measurements)
                MedicationsSection(models: models)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(BrandTheme.background)
        .refreshable { await models.loadAll() }
        // Also reloads on every return to the tab (UI-P7: pull-to-refresh is
        // never the only way), and after midnight, so "yesterday" stays true.
        .task { await models.loadAll() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await models.loadAll() }
            }
        }
    }
}
