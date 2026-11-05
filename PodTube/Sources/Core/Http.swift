import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum HttpError: Error {
    case badStatus(Int)
    case noData
}

extension HttpError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "HTTP \(code)"
        case .noData: return "No data"
        }
    }
}

final class Http {
    static let shared = Http()

    let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 120
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: cfg)
    }

    @discardableResult
    func send(_ request: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) -> URLSessionDataTask {
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse, let data = data else {
                completion(.failure(HttpError.noData))
                return
            }
            if !(200..<300).contains(http.statusCode) {
                completion(.failure(HttpError.badStatus(http.statusCode)))
                return
            }
            completion(.success(data))
        }
        task.resume()
        return task
    }

    @discardableResult
    func get(_ url: URL, headers: [String: String] = [:], completion: @escaping (Result<Data, Error>) -> Void) -> URLSessionDataTask {
        var req = URLRequest(url: url)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return send(req, completion: completion)
    }
}
