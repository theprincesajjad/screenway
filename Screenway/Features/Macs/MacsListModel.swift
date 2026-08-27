import Foundation
import Observation

@MainActor
@Observable
final class MacsListModel {
    private let repository: MacProfileRepository
    private(set) var profiles: [MacProfile] = []

    init(repository: MacProfileRepository) {
        self.repository = repository
    }

    func reload() async {
        profiles = await repository.allProfiles()
    }

    func delete(at offsets: IndexSet) async {
        let doomed = offsets.map { profiles[$0] }
        for profile in doomed {
            try? await repository.delete(id: profile.id)
        }
        await reload()
    }
}
