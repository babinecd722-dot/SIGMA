# Security maintenance

The iOS workflow applies reviewed source patches to exact revisions from
`Package.resolved` before compiling either tests or the device archive. The
patcher stops on an unexpected source layout. Its cache key includes all patch
scripts and Citadel templates; package updates require re-reviewing the patches.

## Upstream fixes backported on 2026-11-04

| Dependency | Advisory | Fix | Reachability in this client |
| --- | --- | --- | --- |
| Wellz26/swift-nio-ssh 0.3.7 | [GHSA-998x-vgvp-xwpc](https://github.com/apple/swift-nio-ssh/security/advisories/GHSA-998x-vgvp-xwpc) / CVE-2026-43798 | Reject ECDSA signature integers larger than the curve storage before copying bytes. | Hostile handshake signatures are decoded before host-key approval. |
| swift-crypto 3.15.1 | [GHSA-8q93-f6xh-4f6f](https://github.com/apple/swift-crypto/security/advisories/GHSA-8q93-f6xh-4f6f) / CVE-2026-43823 | Give RSA public-key backing exactly one owner on failed DER/PEM initialization. | The affected `_CryptoExtras._RSA` API has no production call sites in this client or its SSH dependencies. Patched as dependency hardening. |
| swift-crypto 3.15.1 | [GHSA-jwv7-rv4f-rff2](https://github.com/apple/swift-crypto/security/advisories/GHSA-jwv7-rv4f-rff2) / CVE-2026-86983 | Reject VOPRF inputs exceeding the RFC 9497 UInt16 length before processing. | The client does not use VOPRF. Patched as dependency hardening. |

The declared dependency versions remain pinned; advisory scanners using versions
alone cannot determine whether these source backports have been applied. See
`scripts/patch_dependencies.py` and `scripts/patch_crypto_security.py`, plus
`SSHSignatureBoundsTests` and `CryptoDependencySecurityTests`. Those regressions
were also run with AddressSanitizer on Linux; leak detection was disabled for the
Foundation/XCTest runtime, so this is not a leak-audit claim.

## Additional reviewed boundaries

- SSH transport algorithms retain the fork's strict defaults. Known host keys
  are checked, and unknown or changed keys require an explicit trust decision.
- Secrets use device-local Keychain protection. Profile files use complete file
  protection. Remote clipboard reads are denied; writes require consent.
- Mobile OSC input is bounded. Inline images are checked before raster decoding;
  file previews use bounded ImageIO thumbnails without a full-raster fallback.
- SFTP startup and individual requests have deadlines. A timed-out SFTP child
  does not close the shared SSH transport. File replacement preserves the
  original until commit; a recovery file after a failed replacement must not be
  deleted blindly.
- The legacy history migration does not leave persistent copies or install shell
  hooks. It removes recognizable copies left by the previous migration, skips
  symlinks and ambiguous multiline records, and rechecks before each new PTY.
  It does not inject commands into running shells or clear user scrollback.
  External shells may still rewrite their in-memory history concurrently.

The November review covered all 16 resolved Swift packages, the global Swift
advisory feed, package repository advisories and exact-commit OSV queries, plus
targeted source inspection. Advisory databases can omit forks and recently
published issues; source review found issues absent from aggregate results.

CI repeats the native tests and runs a simulator against a real isolated SSH,
tmux and SFTP fixture, including server restart and history-file hygiene, before
packaging IPA/TIPA. These checks do not establish absence of all vulnerabilities,
replace an independent penetration test, or measure performance on physical
iPhones.
