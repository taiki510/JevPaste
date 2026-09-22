import Foundation

final class JevClient: NSObject, URLSessionTaskDelegate {
    private let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    private let minimumConfidence = 0.55

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func choose(
        field: FocusedFieldContext,
        clips: [Clip],
        apiKey: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let source = boundedContext(from: clips).first else {
            finish(.failure(JevPasteError.noMatch), completion: completion)
            return
        }

        let lines = SelectionGeometry.sourceLines(in: source.text)
        guard !lines.isEmpty else {
            finish(.failure(JevPasteError.noMatch), completion: completion)
            return
        }

        if lines.count == 1 {
            chooseRange(
                in: lines[0],
                source: source,
                field: field,
                apiKey: apiKey,
                completion: completion
            )
            return
        }

        guard lines.count + 1 <= SelectionGeometry.maximumChoiceCount else {
            finish(.failure(JevPasteError.sourceTooComplex), completion: completion)
            return
        }

        chooseLine(
            from: lines,
            source: source,
            field: field,
            apiKey: apiKey
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let line):
                self.chooseRange(
                    in: line,
                    source: source,
                    field: field,
                    apiKey: apiKey,
                    completion: completion
                )
            case .failure(let error):
                self.finish(.failure(error), completion: completion)
            }
        }
    }

    private func chooseLine(
        from lines: [SourceLine],
        source: Clip,
        field: FocusedFieldContext,
        apiKey: String,
        completion: @escaping (Result<SourceLine, Error>) -> Void
    ) {
        var criteria = Dictionary(uniqueKeysWithValues: lines.map {
            ($0.id, "This exact source line: \($0.text)")
        })
        criteria["no_match"] = "No single source line contains an exact value appropriate for the focused field."

        let request = JevRequest(
            model: "jev-latest",
            state: state(field: field, source: source, selectedLine: nil),
            questions: [
                "source_line": .init(
                    type: "choice",
                    instructions: "Choose the single source line that contains the exact value that should be inserted into focused_field. Use the complete source text for context. Do not infer or construct a value across multiple lines. The selected line may contain labels, punctuation, or other surrounding text; a later step will select the exact range within it. Choose no_match when no single line contains an appropriate exact value.",
                    criteria: criteria
                )
            ]
        )

        send(request, apiKey: apiKey) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let response):
                guard let answer = response.answers["source_line"] else {
                    completion(.failure(JevPasteError.invalidResponse))
                    return
                }
                guard answer.choice != "no_match" else {
                    completion(.failure(JevPasteError.noMatch))
                    return
                }
                guard (answer.confidence ?? 0) >= self.minimumConfidence else {
                    completion(.failure(JevPasteError.lowConfidence))
                    return
                }
                guard let line = lines.first(where: { $0.id == answer.choice }) else {
                    completion(.failure(JevPasteError.invalidResponse))
                    return
                }
                completion(.success(line))
            }
        }
    }

    private func chooseRange(
        in line: SourceLine,
        source: Clip,
        field: FocusedFieldContext,
        apiKey: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let boundaries = SelectionGeometry.boundaries(in: line.text)
        guard boundaries.count + 1 <= SelectionGeometry.maximumChoiceCount else {
            finish(.failure(JevPasteError.sourceTooComplex), completion: completion)
            return
        }

        var criteria = Dictionary(uniqueKeysWithValues: boundaries.map {
            (
                $0.id,
                "Boundary at character offset \($0.characterOffset). The inserted full-width marker ｜ shows the boundary: \($0.preview)"
            )
        })
        criteria["no_match"] = "No valid boundary can represent the requested exact value."

        let request = JevRequest(
            model: "jev-latest",
            state: state(field: field, source: source, selectedLine: line.text),
            questions: [
                "start_boundary": .init(
                    type: "choice",
                    instructions: "The selected_line contains the value for focused_field. Choose the boundary immediately before the first character of the complete exact value. The full-width ｜ character shown in each criterion is an inserted display marker, not source text. Do not include a label or unrelated prefix unless it is genuinely part of the value. Do not transform, normalize, or generate text. Choose no_match if no boundary is appropriate.",
                    criteria: criteria
                ),
                "end_boundary": .init(
                    type: "choice",
                    instructions: "The selected_line contains the value for focused_field. Choose the boundary immediately after the last character of the complete exact value. The full-width ｜ character shown in each criterion is an inserted display marker, not source text. Do not include unrelated suffix text or punctuation unless it is genuinely part of the value. Do not transform, normalize, or generate text. Choose no_match if no boundary is appropriate.",
                    criteria: criteria
                )
            ]
        )

        send(request, apiKey: apiKey) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.finish(.failure(error), completion: completion)
            case .success(let response):
                guard let start = response.answers["start_boundary"],
                      let end = response.answers["end_boundary"]
                else {
                    self.finish(.failure(JevPasteError.invalidResponse), completion: completion)
                    return
                }

                guard start.choice != "no_match", end.choice != "no_match" else {
                    self.finish(.failure(JevPasteError.noMatch), completion: completion)
                    return
                }

                guard (start.confidence ?? 0) >= self.minimumConfidence,
                      (end.confidence ?? 0) >= self.minimumConfidence
                else {
                    self.finish(.failure(JevPasteError.lowConfidence), completion: completion)
                    return
                }

                guard let value = SelectionGeometry.exactSubstring(
                    in: line.text,
                    boundaries: boundaries,
                    startID: start.choice,
                    endID: end.choice
                ), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    self.finish(.failure(JevPasteError.invalidResponse), completion: completion)
                    return
                }

                self.finish(.success(value), completion: completion)
            }
        }
    }

    private func state(
        field: FocusedFieldContext,
        source: Clip,
        selectedLine: String?
    ) -> JevRequest.State {
        .init(
            focusedField: .init(label: field.label, role: field.role, app: field.app),
            clipboardItems: [
                .init(
                    id: "clipboard_0",
                    sourceApp: source.sourceApp,
                    content: source.text
                )
            ],
            selectedLine: selectedLine
        )
    }

    private func send(
        _ requestBody: JevRequest,
        apiKey: String,
        completion: @escaping (Result<JevResponse, Error>) -> Void
    ) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        guard let body = try? JSONEncoder().encode(requestBody) else {
            completion(.failure(JevPasteError.invalidResponse))
            return
        }
        request.httpBody = body

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
            } else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                completion(.failure(JevPasteError.http(http.statusCode)))
            } else if let data,
                      let decoded = try? JSONDecoder().decode(JevResponse.self, from: data) {
                completion(.success(decoded))
            } else {
                completion(.failure(JevPasteError.invalidResponse))
            }
        }.resume()
    }

    private func finish(
        _ result: Result<String, Error>,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            completion(result)
        }
    }

    private func boundedContext(from clips: [Clip]) -> [Clip] {
        let maximumItems = 1
        let maximumCharactersPerItem = 12_000
        let maximumTotalCharacters = 12_000
        var remaining = maximumTotalCharacters
        var result: [Clip] = []

        for clip in clips.prefix(maximumItems) where remaining > 0 {
            let characterLimit = min(maximumCharactersPerItem, remaining)
            let content = String(clip.text.prefix(characterLimit))
            guard !content.isEmpty else { continue }
            result.append(Clip(
                id: clip.id,
                text: content,
                sourceApp: clip.sourceApp,
                createdAt: clip.createdAt
            ))
            remaining -= content.count
        }
        return result
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard request.url?.scheme == "https", request.url?.host == endpoint.host else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

private struct JevRequest: Encodable {
    struct State: Encodable {
        struct Field: Encodable {
            let label: String
            let role: String
            let app: String
        }

        struct ClipboardItem: Encodable {
            let id: String
            let sourceApp: String
            let content: String

            enum CodingKeys: String, CodingKey {
                case id, content
                case sourceApp = "source_app"
            }
        }

        let focusedField: Field
        let clipboardItems: [ClipboardItem]
        let selectedLine: String?

        enum CodingKeys: String, CodingKey {
            case focusedField = "focused_field"
            case clipboardItems = "clipboard_items"
            case selectedLine = "selected_line"
        }
    }

    struct Question: Encodable {
        let type: String
        let instructions: String
        let criteria: [String: String]
    }

    let model: String
    let state: State
    let questions: [String: Question]
}

private struct JevResponse: Decodable {
    struct Answer: Decodable {
        let choice: String
        let confidence: Double?
    }

    let answers: [String: Answer]
}
