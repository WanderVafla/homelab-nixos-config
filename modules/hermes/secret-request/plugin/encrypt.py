"""Encrypts a secret with age to the recipients fixed in config.json (host and owner keys).

The plaintext goes to age over stdin only: never to argv, a file, or a log line. The agent can
read the result but not decrypt it; only the host (agenix) and the owner hold the private keys.
"""

from __future__ import annotations

import asyncio
import os
from pathlib import Path


async def to_file(age_bin: str, recipients: list[str], plaintext: str, path: Path) -> None:
    """Write ``plaintext`` encrypted to ``path`` (mode 0640). Raises RuntimeError on failure."""
    args = [age_bin]
    for recipient in recipients:
        args += ["-r", recipient]
    process = await asyncio.create_subprocess_exec(
        *args,
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    ciphertext, stderr = await process.communicate(plaintext.encode())
    if process.returncode != 0 or not ciphertext.startswith(b"age-encryption.org/v1"):
        # age's stderr never contains the input, so it is safe to report.
        raise RuntimeError(f"age failed ({process.returncode}): {stderr.decode(errors='replace').strip()}")

    path.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o640)
    with os.fdopen(descriptor, "wb") as file:
        file.write(ciphertext)
    os.replace(temporary, path)
