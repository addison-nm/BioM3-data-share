# Download Credentials

This directory stores credential files used by `download_databases.sh`. All files
except this README and `.gitkeep` are gitignored and must never be committed.

---

## SMART — `smart_credentials.txt`

Create the file with your registered SMART account details:

```
username=YOUR_SMART_USERNAME
password=YOUR_SMART_PASSWORD
```

Register for a free account at <https://smart.embl.de/> if you don't have one.

Then lock down permissions:

```bash
chmod 600 download/credentials/smart_credentials.txt
```

---

## BRENDA — `brenda_key.txt`

BRENDA requires your password as a **SHA-256 hex digest**, not the plain-text
password. Generate it first:

```bash
python3 -c "import hashlib; print(hashlib.sha256(b'YOUR_BRENDA_PASSWORD').hexdigest())"
```

Then create the file with the hash output:

```
email=YOUR_BRENDA_EMAIL
password=<SHA256_OUTPUT_FROM_ABOVE>
```

Register for a free account at <https://www.brenda-enzymes.org/register.php> if
you don't have one.

Lock down permissions:

```bash
chmod 600 download/credentials/brenda_key.txt
```

---

## Security checklist

1. **Verify gitignore** — run `git status` after creating credential files and
   confirm they do not appear as untracked. The project `.gitignore` contains
   `download/credentials/*` to block them.
2. **Set file permissions to 600** — owner-read/write only. This prevents other
   users on shared machines from reading your credentials.
3. **Never commit credentials** — if you accidentally stage a credential file,
   remove it from the index with `git rm --cached <file>` before committing.
4. **Rotate credentials** if you suspect exposure.
