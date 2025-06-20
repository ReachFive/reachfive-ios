import Foundation

extension Result {
    //TODO: revenir à la fin quand le SDK compile et voir si je peux renommer cette méthode en « flatMap »
    func flatMapAsync<NewSuccess>(_ transform: (Success) async -> Result<NewSuccess, Failure>) async -> Result<NewSuccess, Failure> where NewSuccess : ~Copyable {
        switch self {
        case .success(let value):
            return await transform(value)
        case .failure(let error):
            return .failure(error)
        }
    }

// Si je dois les reprendre, peut-être les nommer mapAsync. Mais voir TODO ci-dessus
//    func map<NewSuccess>(_ transform: (Success) async -> NewSuccess) async -> Result<NewSuccess, Failure> {
//        await flatMap { .success(await transform($0)) }
//    }

//    func map<NewSuccess>(_ transform: (Success) async -> NewSuccess) async -> Result<NewSuccess, Failure> {
//        switch self {
//        case .success(let value): return await .success(transform(value))
//        case .failure(let error):
//            return .failure(error)
//        }
//    }
}

extension Sequence {
    func traverse<NewElement, E>(_ transform: @escaping (Element) async -> Result<NewElement, E>) async -> Result<[NewElement], E> where E: Error {
        var results = [NewElement]()
        for try element in self {
            let result = await transform(element)
            switch result {
            case .success(let newElement):
                results.append(newElement)
            case .failure(let error):
                return .failure(error)
            }
        }
        return .success(results)
    }
}
