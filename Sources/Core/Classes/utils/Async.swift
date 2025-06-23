import Foundation

public extension Result {
    //TODO: revenir à la fin quand le SDK compile et voir si je peux renommer cette méthode en « flatMap »
    func flatMapAsync<NewSuccess>(_ transform: (Success) async -> Result<NewSuccess, Failure>) async -> Result<NewSuccess, Failure> where NewSuccess : ~Copyable {
        switch self {
        case .success(let value):
            return await transform(value)
        case .failure(let error):
            return .failure(error)
        }
    }
    
    consuming func flatMapErrorAsync<NewFailure>(_ transform: (Failure) async -> Result<Success, NewFailure>) async -> Result<Success, NewFailure> where NewFailure : Error {
        switch self {
        case .success(let value):
            return .success(value)
        case .failure(let error):
            return await transform(error)
        }
    }
    
    @discardableResult
    func onSuccess(callback: @escaping (Success) async -> Void) async -> Self {
        if case .success(let value) = self {
            await callback(value)
        }
        return self
    }
    

    @discardableResult
    func onFailure(callback: @escaping (Failure) async -> Void) async -> Self {
        if case .failure(let value) = self {
            await callback(value)
        }
        return self
    }

    @discardableResult
    func onComplete(callback: @escaping (Self) async -> Void) async -> Self {
        await callback(self)
        return self
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

public extension Sequence {
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
