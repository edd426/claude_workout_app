import SwiftUI
import Charts

struct ChartsView: View {
    @State var viewModel: ProgressChartsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                volumeChart
                oneRMChart
                muscleDistributionChart
            }
            .padding()
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadVolumeOverTime()
            await viewModel.loadMuscleDistribution()
            await viewModel.loadExercises()
        }
    }

    // MARK: - Volume Chart

    private var volumeChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Volume Over Time")
                .font(.headline)

            if viewModel.volumeData.isEmpty {
                emptyChartPlaceholder("No workout data yet")
            } else {
                Chart {
                    ForEach(viewModel.volumeData) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Volume (kg)", point.volume)
                        )
                        .foregroundStyle(BrandTheme.terracotta)
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Volume (kg)", point.volume)
                        )
                        .foregroundStyle(BrandTheme.terracotta.opacity(0.15))
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - 1RM Chart

    private var oneRMChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Estimated 1RM")
                    .font(.headline)
                Spacer()
                exercisePicker
            }

            if viewModel.oneRMData.isEmpty {
                emptyChartPlaceholder(viewModel.selectedExerciseId == nil ? "Select an exercise" : "No data for this exercise")
            } else {
                Chart {
                    ForEach(viewModel.oneRMData) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("1RM (kg)", point.estimated1RM)
                        )
                        .foregroundStyle(BrandTheme.terracotta)
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("1RM (kg)", point.estimated1RM)
                        )
                        .foregroundStyle(BrandTheme.terracotta)
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }

    private var exercisePicker: some View {
        Menu {
            ForEach(viewModel.exercises, id: \.id) { exercise in
                Button(exercise.name) {
                    viewModel.selectedExerciseId = exercise.id
                    Task { await viewModel.load1RMProgression(exerciseId: exercise.id) }
                }
            }
        } label: {
            Label(
                viewModel.exercises.first { $0.id == viewModel.selectedExerciseId }?.name ?? "Select",
                systemImage: "chevron.down"
            )
            .font(.caption)
            .foregroundStyle(BrandTheme.terracotta)
        }
    }

    // MARK: - Muscle Distribution Chart

    private var muscleDistributionChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Muscle Distribution (30 days)")
                .font(.headline)

            if viewModel.muscleDistribution.isEmpty {
                emptyChartPlaceholder("No workout data yet")
            } else {
                Chart {
                    ForEach(viewModel.muscleDistribution) { dist in
                        SectorMark(
                            angle: .value("Sets", dist.percentage),
                            innerRadius: .ratio(0.5)
                        )
                        .foregroundStyle(by: .value("Muscle", dist.muscle))
                    }
                }
                .frame(height: 200)

                muscleDistributionLegend
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }

    private var muscleDistributionLegend: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
            ForEach(viewModel.muscleDistribution) { dist in
                HStack(spacing: 4) {
                    Text(dist.muscle.capitalized)
                        .font(.caption2)
                    Spacer()
                    Text(String(format: "%.0f%%", dist.percentage))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func emptyChartPlaceholder(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(height: 100)
            .frame(maxWidth: .infinity)
    }
}
