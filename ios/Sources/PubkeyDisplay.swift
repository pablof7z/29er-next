enum PubkeyDisplay {
    static func shortHex(_ pubkey: String) -> String {
        pubkey.count > 16 ? "\(pubkey.prefix(8))…\(pubkey.suffix(8))" : pubkey
    }
}
