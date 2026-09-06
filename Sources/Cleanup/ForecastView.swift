import SwiftUI

struct ForecastView: View {
    @EnvironmentObject var model: AppModel
    @State private var explanation: String?
    @State private var explanationDate: Date?
    @State private var explanationSnapshot = ""
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        let history = model.state.history.filter { reading in
            model.state.activity.first.map { reading.date > $0.date } ?? true
        }
        let forecast = StorageForecast.evaluate(history, target: model.targetBytes)
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Reserve forecast / measured trend")
            Text(forecast.title).font(.headline)
            Text(forecast.detail).font(.callout).fixedSize(horizontal: false, vertical: true)
            if forecast.samples > 0 {
                Text("\(forecast.samples) readings over \(Int(forecast.spanMinutes)) minutes · Home volume only")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            DisclosureGroup("Explain with on-device AI") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Optional Apple model. Only aggregate capacity facts are supplied; no file names, paths or contents. Generated text may be wrong. The measurements above remain authoritative.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    if let reason = LocalStorageAdvisor.unavailableReason { Text(reason).font(.callout) }
                    HStack {
                        Button(task == nil ? "Explain this reading" : "Explaining…") { explain(forecast) }
                            .disabled(task != nil || LocalStorageAdvisor.unavailableReason != nil || model.capacity == nil)
                        if task != nil {
                            ProgressView().controlSize(.small)
                            Button("Cancel") { cancel() }
                        }
                    }
                    if let explanation, let explanationDate {
                        Text("AI explanation · requested \(explanationDate.formatted(date: .omitted, time: .standard))")
                            .font(.caption.weight(.semibold))
                        Text(explanationSnapshot).font(.caption).foregroundStyle(Palette.muted)
                        Text(explanation).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Text("AI describes a past reading. Future capacity and recovery are not guaranteed; the observation does not identify a cause.")
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(Palette.accent) }
                }.padding(.top, 8)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.tint)
            .onDisappear { cancel() }
    }

    private func explain(_ forecast: StorageForecast) {
        let evidence = forecast.advisorEvidence
        explanation = nil
        error = nil
        explanationDate = Date()
        explanationSnapshot = "Snapshot: \(model.capacity.map { sizeText($0.free) } ?? "unknown") available · \(Int(model.state.targetGB)) GB target · \(forecast.title)"
        task = Task { @MainActor in
            do {
                let text = try await LocalStorageAdvisor.explain(evidence)
                guard !Task.isCancelled else { return }
                explanation = text
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "AI explanation could not finish. \(error.localizedDescription)"
            }
            task = nil
        }
    }

    private func cancel() { task?.cancel(); task = nil }
}
