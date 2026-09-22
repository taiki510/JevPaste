import Foundation

final class JevClient: NSObject, URLSessionTaskDelegate {
    private let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
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
        let contextClips = boundedContext(from: clips)
        let clipboardIDs = Dictionary(uniqueKeysWithValues: contextClips.enumerated().map {
            ($0.element.id, "clipboard_\($0.offset)")
        })
        let candidates = CandidateExtractor.extract(from: contextClips)
        let indexedCandidates = candidates.enumerated().map { ("candidate_\($0.offset)", $0.element) }
        let candidateCriteria = Dictionary(uniqueKeysWithValues: indexedCandidates.map { id, candidate in
            let source = clipboardIDs[candidate.sourceClipID] ?? "unknown"
            let description: String
            switch candidate.kind {
            case .explicitGroup:
                description = "Explicitly grouped exact substring"
            case .structuredValue:
                description = "Structurally identified exact substring"
            case .tokenSpan:
                description = "Exact contiguous token span"
            case .structuralFragment:
                description = "Exact structural fragment"
            }
            return (id, "\(description): \(candidate.value). Found in \(source).")
        })
        let stateCandidates = Dictionary(uniqueKeysWithValues: indexedCandidates.map { id, candidate in
            (
                id,
                JevRequest.State.Candidate(
                    value: candidate.value,
                    clipboardItemID: clipboardIDs[candidate.sourceClipID] ?? "unknown"
                )
            )
        })
        let requestBody = JevRequest(
            model: "jev-latest",
            state: .init(
                focusedField: .init(label: field.label, role: field.role, app: field.app),
                clipboardItems: contextClips.enumerated().map {
                    .init(
                        id: "clipboard_\($0.offset)",
                        sourceApp: $0.element.sourceApp,
                        content: $0.element.text
                    )
                },
                candidates: stateCandidates
            ),
            questions: [
                "best_match": .init(
                    type: "choice",
                    instructions: "Use clipboard_items as the authoritative context, including all surrounding text, layout, ordering, and relationships. Candidate generation is syntactic and does not classify names, addresses, organizations, or other domains. Choose the exact candidate that fully represents the value requested by focused_field. Exclude surrounding field labels, keys, punctuation, or unrelated text. An explicitly grouped candidate is a strong hint from the source author, but it must still fit the focused field semantically. Do not prefer a shorter candidate when it would omit part of the requested value. Choose no_match when no exact candidate is appropriate. Never combine candidates, generate new text, normalize whitespace, or transform a value.",
                    criteria: candidateCriteria.merging([
                        "no_match": "None of the saved values naturally and specifically answers this field."
                    ]) { current, _ in current }
                )
            ]
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(requestBody)

        session.dataTask(with: request) { data, response, error in
            let result: Result<String, Error>
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                result = .failure(JevPasteError.http(http.statusCode))
            } else if let data,
                      let decoded = try? JSONDecoder().decode(JevResponse.self, from: data),
                      let answer = decoded.answers["best_match"] {
                if answer.choice == "no_match" {
                    result = .failure(JevPasteError.noMatch)
                } else if (answer.confidence ?? 0) < 0.55 {
                    result = .failure(JevPasteError.lowConfidence)
                } else if let candidate = indexedCandidates.first(where: { $0.0 == answer.choice })?.1 {
                    result = .success(candidate.value)
                } else {
                    result = .failure(JevPasteError.invalidResponse)
                }
            } else {
                result = .failure(JevPasteError.invalidResponse)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
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
        struct Candidate: Encodable {
            let value: String
            let clipboardItemID: String

            enum CodingKeys: String, CodingKey {
                case value
                case clipboardItemID = "clipboard_item_id"
            }
        }
        let focusedField: Field
        let clipboardItems: [ClipboardItem]
        let candidates: [String: Candidate]

        enum CodingKeys: String, CodingKey {
            case focusedField = "focused_field"
            case clipboardItems = "clipboard_items"
            case candidates
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
