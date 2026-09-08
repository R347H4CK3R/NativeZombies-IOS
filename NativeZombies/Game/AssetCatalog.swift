import Foundation

struct ImportedAssetManifest: Codable {
    struct Entry: Codable, Hashable {
        let relativePath: String
        let size: Int64
        let kind: String
        let sha256: String?
    }

    let sourcePlatform: String
    let sourceGame: String
    let generatedAt: Date
    let entries: [Entry]
}

enum AssetCatalogError: Error {
    case manifestMissing
}

enum AssetCatalog {
    static func loadBundledManifest() throws -> ImportedAssetManifest {
        guard let url = Bundle.main.url(forResource: "asset-manifest", withExtension: "json") else {
            throw AssetCatalogError.manifestMissing
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ImportedAssetManifest.self, from: data)
    }
}
