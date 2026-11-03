/// Transaction ordering for a secret whose access policy cannot be
/// changed in place. Keep the backup unless an original is confirmed.
enum SecretMigration {
    static func replace(
        stage: () -> Int32,
        removeOriginal: () -> Int32,
        install: () -> Int32,
        restore: () -> Int32,
        removeBackup: () -> Void
    ) -> Int32 {
        let staged = stage()
        guard staged == 0 else { return staged }
        let removed = removeOriginal()
        guard removed == 0 else {
            removeBackup()
            return removed
        }
        let installed = install()
        guard installed == 0 else {
            let restored = restore()
            if restored == 0 { removeBackup() }
            return restored == 0 ? installed : restored
        }
        removeBackup()
        return 0
    }
}
