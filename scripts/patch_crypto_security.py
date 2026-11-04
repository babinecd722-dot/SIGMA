"""Narrow upstream security backports compatible with pinned Swift Crypto 3.x."""
from pathlib import Path


def patch_crypto_security(checkouts: Path, replace_once, write_source):
    rsa = checkouts / "swift-crypto/Sources/_CryptoExtras/RSA/RSA_boring.swift"
    # GHSA-8q93-f6xh-4f6f / CVE-2026-43823, fixed upstream in 4.5.1.
    # Delegate ownership before parsing, so failed initialization has exactly
    # one release in Backing.deinit, including DER/PEM fallback failures.
    text = rsa.read_text()
    start = text.index("extension BoringSSLRSAPublicKey {\n    @available")
    end = text.index("\nextension BoringSSLRSAPrivateKey {", start)
    public_backing = text[start:end]

    def replace_public(before, after):
        nonlocal public_backing
        if after in public_backing:
            return
        if public_backing.count(before) != 1:
            raise RuntimeError(f"Unexpected RSA public-key source: {rsa}")
        public_backing = public_backing.replace(before, after, 1)

    replace_public(
        """        fileprivate init(pemRepresentation: String) throws {
            var pemRepresentation = pemRepresentation
            self.pointer = CCryptoBoringSSL_EVP_PKEY_new()""",
        """        fileprivate convenience init(pemRepresentation: String) throws {
            self.init(takingOwnershipOf: CCryptoBoringSSL_EVP_PKEY_new())
            var pemRepresentation = pemRepresentation""")
    replace_public(
        """        private init<Bytes: ContiguousBytes>(contiguousDerRepresentation: Bytes) throws {
            self.pointer = CCryptoBoringSSL_EVP_PKEY_new()""",
        """        private convenience init<Bytes: ContiguousBytes>(contiguousDerRepresentation: Bytes) throws {
            self.init(takingOwnershipOf: CCryptoBoringSSL_EVP_PKEY_new())""")
    before = """                } catch {
                    CCryptoBoringSSL_EVP_PKEY_free(self.pointer)
                    throw error
                }"""
    after = """                } catch {
                    // Backing.deinit owns the sole release, even on failure.
                    throw error
                }"""
    if public_backing.count(after) != 2:
        if public_backing.count(before) != 2:
            raise RuntimeError(f"Unexpected RSA ownership source: {rsa}")
        public_backing = public_backing.replace(before, after)
    write_source(rsa, text[:start] + public_backing + text[end:])

    voprf = checkouts / "swift-crypto/Sources/_CryptoExtras/OPRFs/VOPRF+API.swift"
    # GHSA-jwv7-rv4f-rff2 / CVE-2026-86983, fixed upstream in 5.0.3.
    # RFC 9497 prefixes inputs with UInt16 lengths. Reject before storing or
    # hashing oversized input, rather than trapping during finalization.
    for signature in [
        "    internal func blind<D: DataProtocol>(_ input: D, with fixedBlind: P384._VOPRF.H2G.G.Scalar) throws -> P384._VOPRF.BlindedInput {",
        "    public func evaluate<D: DataProtocol>(_ input: D) throws -> Data {",
    ]:
        replace_once(voprf, signature, signature + """
        guard input.count <= Int(UInt16.max) else {
            throw CryptoKitError.incorrectParameterSize
        }""")
