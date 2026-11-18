"""Open secret requests, at most one per chat (and forum topic).

The tool thread registers a request and blocks on it; the gateway's dispatch hook claims it with
the owner's next message in that chat and resolves it from the event loop. Thread-safe.
"""

from __future__ import annotations

import threading
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Request:
    request_id: str
    name: str
    chat_id: str
    thread_id: Optional[str]
    prompt_message_id: Optional[str] = None
    # Set once by resolve(): {"ok": True, "path": ...} or {"ok": False, "error": ...}.
    result: Optional[dict] = None
    done: threading.Event = field(default_factory=threading.Event)


_lock = threading.Lock()
_by_chat: dict[tuple[str, Optional[str]], Request] = {}


def _key(chat_id: str, thread_id: Optional[str]) -> tuple[str, Optional[str]]:
    return (str(chat_id), str(thread_id) if thread_id else None)


def open_request(request: Request) -> bool:
    """Register a request; False when the chat already waits for another secret."""
    with _lock:
        key = _key(request.chat_id, request.thread_id)
        if key in _by_chat:
            return False
        _by_chat[key] = request
        return True


def claim(chat_id: str, thread_id: Optional[str]) -> Optional[Request]:
    """Take the chat's open request, so exactly one message can answer it."""
    with _lock:
        return _by_chat.pop(_key(chat_id, thread_id), None)


def is_open(chat_id: str, thread_id: Optional[str]) -> bool:
    with _lock:
        return _key(chat_id, thread_id) in _by_chat


def drop(request: Request) -> None:
    """Forget a request that timed out or failed before anyone answered it."""
    with _lock:
        key = _key(request.chat_id, request.thread_id)
        if _by_chat.get(key) is request:
            del _by_chat[key]


def resolve(request: Request, result: dict) -> None:
    request.result = result
    request.done.set()
