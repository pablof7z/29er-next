import SwiftUI

/// The questions section. Unlike the read-only reference player, the listener
/// can select answers and publish them back to the group.
struct TTS29QuestionsSection: View {
    let item: TTS29Item
    let existingAnswer: TTS29AnswerBundle?
    let canAnswer: Bool
    let answerState: TTS29AnswerState
    let onSubmit: ([TTS29Answer]) -> Void

    @State private var draft: [String: [String]] = [:]
    @State private var didSeed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Questions", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                statusBadge
            }

            ForEach(item.questions) { question in
                TTS29QuestionView(
                    question: question,
                    values: draft[question.id] ?? [],
                    isEditable: canAnswer && !answerState.isSubmitting,
                    onChange: { draft[question.id] = $0 }
                )
            }

            footer
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.accentColor.opacity(0.08)))
        .onAppear(perform: seedIfNeeded)
        .accessibilityIdentifier("tts29-questions")
    }

    private var statusBadge: some View {
        Group {
            if let existingAnswer {
                Text("Answered · \(TTS29Formatting.timestamp(Date(timeIntervalSince1970: TimeInterval(existingAnswer.createdAt))))")
                    .foregroundStyle(Color.accentColor)
            } else {
                Text("Awaiting reply").foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.medium))
    }

    @ViewBuilder
    private var footer: some View {
        switch answerState {
        case .submitting:
            HStack(spacing: 8) { ProgressView(); Text("Sending answer…").foregroundStyle(.secondary) }
                .font(.footnote)
        case .submitted:
            Label("Answer published", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Color.accentColor)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                submitButton(title: "Try again")
            }
        case .idle:
            if canAnswer {
                submitButton(title: existingAnswer == nil ? "Submit answer" : "Update answer")
            } else {
                Text("Sign in to answer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func submitButton(title: String) -> some View {
        Button(title) { onSubmit(collectedAnswers()) }
            .buttonStyle(.borderedProminent)
            .disabled(collectedAnswers().isEmpty)
            .accessibilityIdentifier("tts29-submit-answer")
    }

    private func collectedAnswers() -> [TTS29Answer] {
        item.questions.compactMap { question in
            let values = (draft[question.id] ?? []).filter { !$0.isEmpty }
            guard !values.isEmpty else { return nil }
            return TTS29Answer(questionID: question.id, values: values)
        }
    }

    private func seedIfNeeded() {
        guard !didSeed else { return }
        didSeed = true
        guard let existingAnswer else { return }
        for question in item.questions {
            let values = existingAnswer.values(for: question.id)
            if !values.isEmpty { draft[question.id] = values }
        }
    }
}

private struct TTS29QuestionView: View {
    let question: TTS29Question
    let values: [String]
    let isEditable: Bool
    let onChange: ([String]) -> Void

    @State private var freeformText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.title).font(.headline)
            if let description = question.description {
                Text(description).font(.subheadline).foregroundStyle(.secondary)
            }
            switch question.kind {
            case .freeform:
                freeformField
            case .single, .multiple:
                ForEach(question.options) { option in
                    optionRow(option)
                }
            }
        }
        .onAppear { if question.kind == .freeform { freeformText = values.first ?? "" } }
    }

    private var freeformField: some View {
        TextField("Your answer", text: Binding(
            get: { freeformText },
            set: { freeformText = $0; onChange($0.isEmpty ? [] : [$0]) }
        ), axis: .vertical)
        .lineLimit(1...4)
        .textFieldStyle(.roundedBorder)
        .disabled(!isEditable)
    }

    private func optionRow(_ option: TTS29QuestionOption) -> some View {
        let selected = values.contains(option.id)
        return Button {
            toggle(option.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol(selected: selected))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .foregroundStyle(.primary)
                    if let description = option.description {
                        Text(description).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
    }

    private func symbol(selected: Bool) -> String {
        switch question.kind {
        case .multiple: selected ? "checkmark.square.fill" : "square"
        default: selected ? "checkmark.circle.fill" : "circle"
        }
    }

    private func toggle(_ optionID: String) {
        switch question.kind {
        case .multiple:
            var next = Set(values)
            if next.contains(optionID) { next.remove(optionID) } else { next.insert(optionID) }
            onChange(question.options.map(\.id).filter(next.contains))
        default:
            onChange([optionID])
        }
    }
}
