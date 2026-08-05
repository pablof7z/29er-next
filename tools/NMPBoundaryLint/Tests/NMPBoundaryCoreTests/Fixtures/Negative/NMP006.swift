let epoch = NMPStoreEpoch(fileManager: .default)
let nmpStore = "nmp.redb"
try fileManager.removeItem(at: storeURL)
