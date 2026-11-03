import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

/// Templates named the way the v3 program names them. Synthetic.
@MainActor
private func weekTemplates() -> [WorkoutTemplate] {
    [
        "Fri · Machines (optional)",
        "Mon · Legs 1 (squat)",
        "Thu · Upper 2 (incline)",
        "Tue · Upper 1 (bench)",
        "Wed · Legs 2 (hinge)",
    ].map { WorkoutTemplate(name: $0) }
}

@MainActor
private func named(_ name: String, in templates: [WorkoutTemplate]) -> WorkoutTemplate? {
    templates.first { $0.name.hasPrefix(name) }
}

@Suite("Today: weekday template matching")
@MainActor
struct TodayTemplatePickerTests {
    private let calendar = VolumeTestClock.calendar

    @Test("A template's leading weekday word is read as that weekday", arguments: [
        ("Mon · Legs 1 (squat)", 2),
        ("Tue · Upper 1 (bench)", 3),
        ("Wed · Legs 2 (hinge)", 4),
        ("Thu · Upper 2 (incline)", 5),
        ("Fri · Machines (optional)", 6),
        ("Sat · Long run", 7),
        ("Sun · Mobility", 1),
        ("Wednesday Push Day", 4),
        ("thurs: arms", 5),
        ("Friday Pump", 6),
    ])
    func weekdayPrefix(name: String, weekday: Int) {
        #expect(TodayTemplatePicker.weekday(named: name) == weekday)
    }

    @Test("Names that only look like weekdays are not matched", arguments: [
        "Lower A", "Upper B", "Mo · Legs", "Monster Arms", "Sunrise Yoga", "Saturation Pump", "",
    ])
    func noWeekday(name: String) {
        #expect(TodayTemplatePicker.weekday(named: name) == nil)
    }

    @Test("On a weekday the template named for that day is picked", arguments: [
        (2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"),
    ])
    func picksTodaysTemplate(day: Int, expectedPrefix: String) {
        let templates = weekTemplates()

        let picked = TodayTemplatePicker.pick(
            from: templates,
            lastDone: [:],
            now: VolumeTestClock.date(day: day, hour: 6),
            calendar: calendar
        )

        #expect(picked?.name.hasPrefix(expectedPrefix) == true)
    }

    @Test("On a weekend the least recently done template is the fallback")
    func weekendFallsBackToLeastRecentlyDone() throws {
        let templates = weekTemplates()
        let lastDone: [UUID: Date] = [
            try #require(named("Mon", in: templates)).id: VolumeTestClock.date(day: 2),
            try #require(named("Tue", in: templates)).id: VolumeTestClock.date(day: 3),
            try #require(named("Wed", in: templates)).id: VolumeTestClock.date(day: 4),
            try #require(named("Thu", in: templates)).id: VolumeTestClock.date(day: 5),
            try #require(named("Fri", in: templates)).id: VolumeTestClock.date(day: 23, month: 10),
        ]

        let picked = TodayTemplatePicker.pick(
            from: templates,
            lastDone: lastDone,
            now: VolumeTestClock.date(day: 7, hour: 9),
            calendar: calendar
        )

        #expect(picked?.name.hasPrefix("Fri") == true)
    }

    @Test("A template never done counts as least recently done")
    func neverDoneIsLeastRecent() throws {
        let templates = [WorkoutTemplate(name: "Lower A"), WorkoutTemplate(name: "Upper A")]
        let lastDone = [templates[0].id: VolumeTestClock.date(day: 1)]

        let picked = TodayTemplatePicker.pick(
            from: templates, lastDone: lastDone, now: VolumeTestClock.now, calendar: calendar
        )

        #expect(picked?.name == "Upper A")
    }

    @Test("With no weekday names at all, the least recently done template is picked")
    func noMatchFallsBack() {
        let templates = [WorkoutTemplate(name: "Lower A"), WorkoutTemplate(name: "Upper A")]
        let lastDone = [
            templates[0].id: VolumeTestClock.date(day: 20, month: 10),
            templates[1].id: VolumeTestClock.date(day: 3),
        ]

        let picked = TodayTemplatePicker.pick(
            from: templates, lastDone: lastDone, now: VolumeTestClock.now, calendar: calendar
        )

        #expect(picked?.name == "Lower A")
    }

    @Test("Ties among never-done templates keep the list order")
    func tiesKeepListOrder() {
        let templates = [WorkoutTemplate(name: "B"), WorkoutTemplate(name: "A")]

        let picked = TodayTemplatePicker.pick(
            from: templates, lastDone: [:], now: VolumeTestClock.now, calendar: calendar
        )

        #expect(picked?.name == "B")
    }

    @Test("Two templates for the same weekday: the less recently done one wins")
    func twoForToday() {
        let first = WorkoutTemplate(name: "Wed · Legs 2 (hinge)")
        let second = WorkoutTemplate(name: "Wed · Pump")
        let lastDone = [first.id: VolumeTestClock.date(day: 28, month: 10)]

        let picked = TodayTemplatePicker.pick(
            from: [first, second], lastDone: lastDone, now: VolumeTestClock.now, calendar: calendar
        )

        #expect(picked?.name == "Wed · Pump")
    }

    @Test("No templates, no pick")
    func empty() {
        #expect(TodayTemplatePicker.pick(
            from: [], lastDone: [:], now: VolumeTestClock.now, calendar: calendar
        ) == nil)
    }

    @Test("The hero subtitle counts exercises and says when it was last done")
    func heroSubtitle() {
        let subtitle = TodayTemplatePicker.subtitle(
            exerciseCount: 4,
            lastDone: VolumeTestClock.date(day: 29, month: 10, hour: 7),
            now: VolumeTestClock.now,
            calendar: calendar
        )
        let never = TodayTemplatePicker.subtitle(
            exerciseCount: 1, lastDone: nil, now: VolumeTestClock.now, calendar: calendar
        )

        #expect(subtitle == "4 exercises · last done 6 days ago")
        #expect(never == "1 exercise · not done yet")
    }
}

@Suite("Today: derived last-done date (#176)")
@MainActor
struct TemplateLastDoneTests {
    @Test("The last-done date comes from the latest finished workout, not the stored lastPerformedAt")
    func derivedBeatsStaleStoredDate() throws {
        let container = try makeTestContainer()
        let template = WorkoutTemplate(
            name: "Upper A", lastPerformedAt: VolumeTestClock.date(day: 29, month: 9)
        )
        container.mainContext.insert(template)
        let older = Workout(
            name: "Upper A", startedAt: VolumeTestClock.date(day: 29, month: 9),
            templateId: template.id, completedAt: VolumeTestClock.date(day: 29, month: 9, hour: 13)
        )
        let latest = Workout(
            name: "Upper A", startedAt: VolumeTestClock.date(day: 6, month: 10),
            templateId: template.id, completedAt: VolumeTestClock.date(day: 6, month: 10, hour: 13)
        )
        [older, latest].forEach { container.mainContext.insert($0) }

        let dates = TemplateLastDone.dates(from: [older, latest])

        #expect(dates[template.id] == VolumeTestClock.date(day: 6, month: 10))
        #expect(TemplateLastDone.date(for: template, in: dates) == VolumeTestClock.date(day: 6, month: 10))
    }

    @Test("A draft does not count as done")
    func draftIgnored() {
        let templateId = UUID()
        let finished = Workout(
            name: "Lower B", startedAt: VolumeTestClock.date(day: 2, month: 9),
            templateId: templateId, completedAt: VolumeTestClock.date(day: 2, month: 9, hour: 13)
        )
        let draft = Workout(
            name: "Lower B", startedAt: VolumeTestClock.date(day: 30, month: 9),
            templateId: templateId, completedAt: nil
        )

        let dates = TemplateLastDone.dates(from: [draft, finished])

        #expect(dates[templateId] == VolumeTestClock.date(day: 2, month: 9))
    }

    @Test("Workouts from other templates or none are ignored")
    func otherTemplatesIgnored() {
        let mine = UUID()
        let theirs = Workout(
            name: "Other", startedAt: VolumeTestClock.date(day: 3),
            templateId: UUID(), completedAt: VolumeTestClock.date(day: 3, hour: 13)
        )
        let adHoc = Workout(
            name: "Quick Workout", startedAt: VolumeTestClock.date(day: 4),
            templateId: nil, completedAt: VolumeTestClock.date(day: 4, hour: 13)
        )

        let dates = TemplateLastDone.dates(from: [theirs, adHoc])

        #expect(dates[mine] == nil)
        #expect(dates.count == 1)
    }

    @Test("With no finished workout at all, the stored date is the only evidence and is used")
    func storedDateFallback() {
        let template = WorkoutTemplate(
            name: "Imported", lastPerformedAt: VolumeTestClock.date(day: 1, month: 8)
        )

        #expect(TemplateLastDone.date(for: template, in: [:]) == VolumeTestClock.date(day: 1, month: 8))
    }

    @Test("HomeViewModel derives last-done dates and today's template from the workout history")
    func homeViewModelDerives() async throws {
        let container = try makeTestContainer()
        let templates = weekTemplates()
        templates.forEach { container.mainContext.insert($0) }
        let monday = try #require(named("Mon", in: templates))
        let wednesday = try #require(named("Wed", in: templates))
        let session = Workout(
            name: monday.name, startedAt: VolumeTestClock.date(day: 2, hour: 6),
            templateId: monday.id, completedAt: VolumeTestClock.date(day: 2, hour: 7)
        )
        container.mainContext.insert(session)
        let templateRepo = MockTemplateRepository()
        templateRepo.templates = templates
        let workoutRepo = MockWorkoutRepository()
        workoutRepo.workouts = [session]
        let vm = HomeViewModel(
            templateRepository: templateRepo,
            workoutRepository: workoutRepo,
            calendar: VolumeTestClock.calendar,
            now: { VolumeTestClock.now }
        )

        await vm.loadToday()

        #expect(vm.lastDoneDate(for: monday) == VolumeTestClock.date(day: 2, hour: 6))
        #expect(vm.lastDoneDate(for: wednesday) == nil)
        #expect(vm.hasLoadedToday)
        #expect(vm.todaysTemplate?.id == wednesday.id)
        #expect(vm.heroIsScheduledToday)
        #expect(vm.otherTemplates.count == 4)
        #expect(vm.otherTemplates.contains { $0.id == wednesday.id } == false)
        #expect(vm.weeklyVolume != nil)
    }

    @Test("On a Saturday the hero is the fallback, flagged as not scheduled for today")
    func weekendHeroIsFallback() async throws {
        let container = try makeTestContainer()
        let templates = weekTemplates()
        templates.forEach { container.mainContext.insert($0) }
        let templateRepo = MockTemplateRepository()
        templateRepo.templates = templates
        let vm = HomeViewModel(
            templateRepository: templateRepo,
            workoutRepository: MockWorkoutRepository(),
            calendar: VolumeTestClock.calendar,
            now: { VolumeTestClock.date(day: 7, hour: 9) }
        )

        await vm.loadToday()

        #expect(vm.todaysTemplate != nil)
        #expect(vm.heroIsScheduledToday == false)
    }

    @Test("With a draft to resume, the hero is Resume and every template is under Other workouts")
    func draftMovesAllTemplatesToOther() async throws {
        let container = try makeTestContainer()
        let templates = weekTemplates()
        templates.forEach { container.mainContext.insert($0) }
        let draft = Workout(name: "Tue · Upper 1 (bench)", startedAt: VolumeTestClock.date(day: 4, hour: 6))
        container.mainContext.insert(draft)
        let exercise = Exercise(name: "Bench Press", primaryMuscles: ["chest"])
        container.mainContext.insert(exercise)
        let entry = WorkoutExercise(order: 0, exercise: exercise)
        container.mainContext.insert(entry)
        let set = WorkoutSet(order: 0, weight: 60, reps: 8, isCompleted: true, completedAt: .now)
        container.mainContext.insert(set)
        entry.sets.append(set)
        draft.exercises.append(entry)
        let templateRepo = MockTemplateRepository()
        templateRepo.templates = templates
        let workoutRepo = MockWorkoutRepository()
        workoutRepo.workouts = [draft]
        let vm = HomeViewModel(
            templateRepository: templateRepo,
            workoutRepository: workoutRepo,
            calendar: VolumeTestClock.calendar,
            now: { VolumeTestClock.now }
        )

        await vm.loadToday()

        #expect(vm.resumableWorkout?.id == draft.id)
        #expect(vm.todaysTemplate == nil)
        #expect(vm.otherTemplates.count == 5)
        #expect(vm.weeklyVolume?.hasAnySets == false)
    }

    @Test("Manage Templates derives the same last-done dates")
    func templateListDerives() async throws {
        let container = try makeTestContainer()
        let template = WorkoutTemplate(name: "Lower B", lastPerformedAt: VolumeTestClock.date(day: 2, month: 9))
        container.mainContext.insert(template)
        let session = Workout(
            name: "Lower B", startedAt: VolumeTestClock.date(day: 30, month: 9),
            templateId: template.id, completedAt: VolumeTestClock.date(day: 30, month: 9, hour: 13)
        )
        container.mainContext.insert(session)
        let templateRepo = MockTemplateRepository()
        templateRepo.templates = [template]
        let workoutRepo = MockWorkoutRepository()
        workoutRepo.workouts = [session]
        let vm = TemplateListViewModel(templateRepository: templateRepo, workoutRepository: workoutRepo)

        await vm.loadTemplates()

        #expect(vm.lastDoneDate(for: template) == VolumeTestClock.date(day: 30, month: 9))
    }
}

@Suite("Today: Needs-you row")
struct NeedsYouSummaryTests {
    @Test("Hidden when there is nothing to approve and no open report")
    func hiddenAtZero() {
        #expect(NeedsYouSummary.make(pendingApprovals: 0, openReports: 0) == nil)
    }

    @Test("Merges both counts into one row", arguments: [
        (2, 3, 5, "2 changes to approve · 3 open reports"),
        (1, 1, 2, "1 change to approve · 1 open report"),
        (1, 0, 1, "1 change to approve"),
        (0, 4, 4, "4 open reports"),
    ])
    func mergesCounts(approvals: Int, reports: Int, total: Int, title: String) throws {
        let summary = try #require(NeedsYouSummary.make(pendingApprovals: approvals, openReports: reports))

        #expect(summary.total == total)
        #expect(summary.title == title)
    }

    @Test("Negative counts are treated as zero")
    func negativeIsZero() {
        #expect(NeedsYouSummary.make(pendingApprovals: -1, openReports: 0) == nil)
    }
}

@Suite("Today: Body row")
struct TodayBodySummaryTests {
    private let calendar = VolumeTestClock.calendar
    private let now = VolumeTestClock.now

    @Test("Reads weight, age and pace", arguments: [
        (WeightGoalStatus?.some(.onTrack), "87.9 kg · 2 days ago · on pace"),
        (.some(.tooFast), "87.9 kg · 2 days ago · faster than goal"),
        (.some(.tooSlow), "87.9 kg · 2 days ago · slower than goal"),
        (nil, "87.9 kg · 2 days ago"),
    ])
    func line(status: WeightGoalStatus?, expected: String) {
        let text = TodayBodySummary.line(
            weight: 87.94, unit: .kg, recordedAt: VolumeTestClock.date(day: 2, hour: 7),
            status: status, goalPercentPerWeek: 0.25, now: now, calendar: calendar
        )

        #expect(text == expected)
    }

    @Test("Holding steady and drifting reads as off goal, not faster")
    func maintainGoal() {
        let text = TodayBodySummary.line(
            weight: 194, unit: .lbs, recordedAt: VolumeTestClock.date(day: 4, hour: 7),
            status: .tooFast, goalPercentPerWeek: 0, now: now, calendar: calendar
        )

        #expect(text == "194.0 lbs · today · off goal")
    }

    @Test("A reading a week old or more is stale", arguments: [
        (VolumeTestClock.date(day: 28, month: 10), true),
        (VolumeTestClock.date(day: 29, month: 10), false),
        (VolumeTestClock.date(day: 4), false),
    ])
    func stale(recordedAt: Date, expected: Bool) {
        #expect(TodayBodySummary.isStale(recordedAt: recordedAt, now: now, calendar: calendar) == expected)
    }
}
