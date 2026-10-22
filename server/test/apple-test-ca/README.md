# Test-only certificate chain (not Apple)

Signs fake App Store transactions and notifications for the end-to-end test. The server trusts
`root.pem` only when run with `cf dev --mode test`; production trusts Apple Root CA G3 alone.
`leaf.pkcs8.pem` is a throwaway test key, safe to publish. `openssl.cnf` shows how the chain was
made: the intermediate and leaf carry Apple's certificate markers (1.2.840.113635.100.6.2.1 and
1.2.840.113635.100.6.11.1), which the verifier requires.
