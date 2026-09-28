# Publishing to Cloudron Community Apps

`CloudronVersions.json` is generated only by the catalog workflow; never edit
it by hand. Add the repository secret `CLOUDRON_RELEASE_PAT` as a
repository-scoped fine-grained token with only Contents read/write access.

Before Community Apps submission, perform a live qualification:

```bash
cloudron install --versions-url <PUBLIC_VERSIONS_URL> --location relay-test
```

Confirm allowlisted and rejected writes, restart persistence, upgrade, health
checks, and backup/restore. Then submit the public versions URL at
[ca.cloudron.io](https://ca.cloudron.io). Do not use a production relay for
qualification.
