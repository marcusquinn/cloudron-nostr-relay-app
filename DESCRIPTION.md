A private [Nostr](https://nostr.com) relay powered by
[strfry](https://github.com/hoytech/strfry).

Only the public keys you list can publish events. Every other write is
rejected, so the relay never becomes an open public relay. Anyone who knows
the address can still read events, so treat published content as public unless
it is encrypted.

### Features

* Fast strfry relay with an LMDB database stored in Cloudron backups
* Write allowlist of `npub` or hexadecimal public keys, read on every event, so
  changes apply without a restart
* Starts closed: an empty allowlist rejects every write
* NIP-11 relay information (name, description, contact, operator key) set
  through app environment variables
* Real client IP addresses from Cloudron's reverse proxy
