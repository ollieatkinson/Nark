The client Initial hex fixtures are the 1,200-byte published packet-protection
vectors from RFC 9001 Appendix A.2 and RFC 9369 Appendix A.2:

- https://www.rfc-editor.org/rfc/rfc9001.html#appendix-A.2
- https://www.rfc-editor.org/rfc/rfc9369.html#appendix-A.2

Both contain the visible SNI `example.com`. These independently verify header
protection, version-specific HKDF labels/salts, packet-number handling and AEAD
integrity before the synthetic fragmentation tests run.
