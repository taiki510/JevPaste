import Foundation

final class JevClient: NSObject, URLSessionTaskDelegate {
    typealias SendHandler = (
        JevRequest,
        String,
        @escaping (Result<JevResponse, Error>) -> Void
    ) -> Void

    private let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    private let sendHandler: SendHandler?

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

    init(sendHandler: SendHandler? = nil) {
        self.sendHandler = sendHandler
        super.init()
    }

    func choose(
        field: FocusedFieldContext,
        clips: [Clip],
        apiKey: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let source = boundedContext(from: clips).first else {
            finish(.failure(JevPasteError.emptySource), completion: completion)
            return
        }

        let lines = SelectionGeometry.sourceLines(in: source.text)
        guard !lines.isEmpty else {
            finish(.failure(JevPasteError.emptySource), completion: completion)
            return
        }

        if lines.count == 1 {
            chooseRange(
                in: lines[0],
                source: source,
                field: field,
                apiKey: apiKey,
                requireLineMatch: true,
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
                    requireLineMatch: false,
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
            state: state(
                field: field,
                source: source,
                selectedLine: nil,
                selectedStartOffset: nil
            ),
            questions: [
                "source_line": .init(
                    type: "choice",
                    instructions: "Choose the single source line that contains the exact value that should be inserted into focused_field. Use the complete source text for context. Do not infer or construct a value across multiple lines. The selected line may contain labels, punctuation, or other surrounding text; later steps will select the exact range within it. Choose no_match when no single line contains an appropriate exact value.",
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
                completion(self.lineResult(response, lines: lines))
            }
        }
    }

    func lineResult(
        _ response: JevResponse,
        lines: [SourceLine]
    ) -> Result<SourceLine, Error> {
        guard let answer = response.answers["source_line"] else {
            return .failure(JevPasteError.invalidResponse)
        }
        guard answer.choice != "no_match" else {
            return .failure(JevPasteError.noMatch)
        }
        guard let line = lines.first(where: { $0.id == answer.choice }) else {
            return .failure(JevPasteError.invalidResponse)
        }
        return .success(line)
    }

    private func chooseRange(
        in line: SourceLine,
        source: Clip,
        field: FocusedFieldContext,
        apiKey: String,
        requireLineMatch: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let boundaries = SelectionGeometry.boundaries(in: line.text)
        guard boundaries.count + 1 <= SelectionGeometry.maximumChoiceCount else {
            finish(.failure(JevPasteError.sourceTooComplex), completion: completion)
            return
        }

        let boundaryMarker = SelectionGeometry.boundaryMarker(in: line.text)
        let request = JevRequest(
            model: "jev-latest",
            state: state(
                field: field,
                source: source,
                selectedLine: line.text,
                selectedStartOffset: nil
            ),
            questions: Self.startQuestions(
                boundaries: boundaries,
                boundaryMarker: boundaryMarker,
                requireLineMatch: requireLineMatch
            )
        )

        send(request, apiKey: apiKey) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.finish(.failure(error), completion: completion)
            case .success(let response):
                switch self.startBoundaryResult(
                    response,
                    boundaries: boundaries,
                    requireLineMatch: requireLineMatch
                ) {
                case .failure(let error):
                    self.finish(.failure(error), completion: completion)
                case .success(let startBoundary):
                    self.chooseEndBoundary(
                        in: line,
                        source: source,
                        field: field,
                        apiKey: apiKey,
                        boundaries: boundaries,
                        boundaryMarker: boundaryMarker,
                        startBoundary: startBoundary,
                        completion: completion
                    )
                }
            }
        }
    }

    private func chooseEndBoundary(
        in line: SourceLine,
        source: Clip,
        field: FocusedFieldContext,
        apiKey: String,
        boundaries: [TextBoundary],
        boundaryMarker: String,
        startBoundary: TextBoundary,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let request = JevRequest(
            model: "jev-latest",
            state: state(
                field: field,
                source: source,
                selectedLine: line.text,
                selectedStartOffset: startBoundary.characterOffset
            ),
            questions: Self.endQuestions(
                boundaries: boundaries,
                startBoundary: startBoundary,
                boundaryMarker: boundaryMarker
            )
        )

        send(request, apiKey: apiKey) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.finish(.failure(error), completion: completion)
            case .success(let response):
                self.finish(
                    self.endResult(
                        response,
                        in: line.text,
                        boundaries: boundaries,
                        startBoundary: startBoundary
                    ),
                    completion: completion
                )
            }
        }
    }

    static func startQuestions(
        boundaries: [TextBoundary],
        boundaryMarker: String,
        requireLineMatch: Bool
    ) -> [String: JevRequest.Question] {
        var criteria = Dictionary(uniqueKeysWithValues: boundaries.map {
            (
                $0.id,
                "Boundary at character offset \($0.characterOffset). The inserted marker \(boundaryMarker) shows the boundary: \($0.preview)"
            )
        })
        criteria["no_match"] = "No valid start boundary can represent the requested exact value."

        var questions: [String: JevRequest.Question] = [
            "start_boundary": .init(
                type: "choice",
                instructions: "Inspect selected_line for a complete exact value appropriate for focused_field. If such a value exists, choose the boundary immediately before its first character. The marker \(boundaryMarker) shown in each criterion is inserted only for display and is guaranteed not to occur in selected_line. Do not include a label or unrelated prefix unless it is genuinely part of the value. Do not transform, normalize, or generate text. Choose no_match if selected_line contains no appropriate exact value or no start boundary is appropriate.",
                criteria: criteria
            )
        ]

        if requireLineMatch {
            questions["line_match"] = .init(
                type: "choice",
                instructions: "Decide whether selected_line contains a complete exact value appropriate for focused_field. Do not assume a match exists merely because the source has only one non-empty line. Choose match only when the value occurs contiguously in selected_line without combining, transforming, normalizing, or generating text. Otherwise choose no_match.",
                criteria: [
                    "match": "selected_line contains a complete exact value appropriate for focused_field.",
                    "no_match": "selected_line does not contain any complete exact value appropriate for focused_field.",
                ]
            )
        }

        return questions
    }

    static func endQuestions(
        boundaries: [TextBoundary],
        startBoundary: TextBoundary,
        boundaryMarker: String
    ) -> [String: JevRequest.Question] {
        let validEnds = boundaries.filter { $0.index > startBoundary.index }
        var criteria = Dictionary(uniqueKeysWithValues: validEnds.map {
            (
                $0.id,
                "End boundary at character offset \($0.characterOffset). The inserted marker \(boundaryMarker) shows this candidate end: \($0.preview)"
            )
        })
        criteria["no_match"] = "No valid end boundary completes an appropriate exact value from the fixed start boundary."

        return [
            "end_boundary": .init(
                type: "choice",
                instructions: "The start of the value is already fixed at character offset \(startBoundary.characterOffset), shown here: \(startBoundary.preview). Choose the boundary immediately after the last character of the complete exact value that begins at exactly that fixed start. Do not switch to a different occurrence or a different value elsewhere in selected_line. The marker \(boundaryMarker) is inserted only for display and is guaranteed not to occur in selected_line. Do not include unrelated suffix text or punctuation unless it is genuinely part of the value. Do not transform, normalize, or generate text. Choose no_match if no offered end boundary completes an appropriate exact value from the fixed start.",
                criteria: criteria
            )
        ]
    }

    func startBoundaryResult(
        _ response: JevResponse,
        boundaries: [TextBoundary],
        requireLineMatch: Bool
    ) -> Result<TextBoundary, Error> {
        if requireLineMatch {
            guard let lineMatch = response.answers["line_match"] else {
                return .failure(JevPasteError.invalidResponse)
            }
            guard lineMatch.choice != "no_match" else {
                return .failure(JevPasteError.noMatch)
            }
            guard lineMatch.choice == "match" else {
                return .failure(JevPasteError.invalidResponse)
            }
        }

        guard let start = response.answers["start_boundary"] else {
            return .failure(JevPasteError.invalidResponse)
        }
        guard start.choice != "no_match" else {
            return .failure(JevPasteError.noMatch)
        }
        guard let boundary = boundaries.first(where: { $0.id == start.choice }),
              let finalBoundary = boundaries.last,
              boundary.index < finalBoundary.index
        else {
            return .failure(JevPasteError.invalidResponse)
        }
        return .success(boundary)
    }

    func endResult(
        _ response: JevResponse,
        in line: String,
        boundaries: [TextBoundary],
        startBoundary: TextBoundary
    ) -> Result<String, Error> {
        guard let end = response.answers["end_boundary"] else {
            return .failure(JevPasteError.invalidResponse)
        }
        guard end.choice != "no_match" else {
            return .failure(JevPasteError.noMatch)
        }
        guard let endBoundary = boundaries.first(where: {
            $0.id == end.choice && $0.index > startBoundary.index
        }),
              let value = SelectionGeometry.exactSubstring(
                in: line,
                boundaries: boundaries,
                startID: startBoundary.id,
                endID: endBoundary.id
              ),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .failure(JevPasteError.invalidResponse)
        }
        return .success(value)
    }

    private func state(
        field: FocusedFieldContext,
        source: Clip,
        selectedLine: String?,
        selectedStartOffset: Int?
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
            selectedLine: selectedLine,
            selectedStartOffset: selectedStartOffset
        )
    }

    private func send(
        _ requestBody: JevRequest,
        apiKey: String,
        completion: @escaping (Result<JevResponse, Error>) -> Void
    ) {
        if let sendHandler {
            sendHandler(requestBody, apiKey, completion)
            return
        }

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

struct JevRequest: Encodable {
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
        let selectedStartOffset: Int?

        enum CodingKeys: String, CodingKey {
            case focusedField = "focused_field"
            case clipboardItems = "clipboard_items"
            case selectedLine = "selected_line"
            case selectedStartOffset = "selected_start_offset"
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

struct JevResponse: Decodable {
    struct Answer: Decodable {
        let choice: String
        let confidence: Double?
    }

    let answers: [String: Answer]
}
