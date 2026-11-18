"""secret-request: the agent asks the owner for a secret in Telegram, and the value never reaches it.

Flow:
1. The agent calls ``request_secret(name, purpose)``. The tool posts a force-reply prompt in the
   owner's chat and blocks until the request is answered, cancelled or times out.
2. While a request is open, the owner's next message in that chat (and forum topic) is taken by
   the ``pre_gateway_dispatch`` hook, which runs before authorization and before the agent. The
   hook returns ``skip`` at once, so the message never enters the turn, the session or the model.
3. A background task encrypts the text with age to the host and owner keys, deletes the owner's
   message and edits the prompt into a confirmation. The tool returns only the .age path.

Fail-closed rule: once a message is matched to an open request, it is skipped no matter what
fails afterwards. A hook that raises lets the message through to the agent, so the matching part
is kept trivial and everything risky runs in the background task.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import time
import uuid
from pathlib import Path
from typing import Any, Optional

from . import encrypt, pending, telegram_ui

logger = logging.getLogger(__name__)

CONFIG = json.loads(Path(__file__).with_name("config.json").read_text())
NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]{0,47}$")
MAX_PURPOSE = 300
WAIT_SECONDS = 600
CANCEL = "/cancel"

SCHEMA = {
    "name": "request_secret",
    "description": (
        "Ask the owner for a secret (API key, token, password of a service you set up) without ever "
        "seeing it. Works only in the owner's Telegram chat. Posts a prompt there and waits up to 10 "
        "minutes for the owner's reply; the reply is encrypted with age to the host and owner keys "
        "before you could read it, and the message is deleted. Returns the path of the .age file, "
        "which you commit as secrets/<name>.age and declare with agenix. Never ask for secrets in "
        "plain chat, and never ask for sudo, SSH or GitHub account passwords."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "name": {
                "type": "string",
                "description": "Secret name, lowercase letters, digits and dashes, e.g. 'openai-key'. "
                               "It becomes secrets/<name>.age.",
            },
            "purpose": {
                "type": "string",
                "description": "One sentence for the owner: what the secret is for and where it will be used.",
            },
        },
        "required": ["name", "purpose"],
        "additionalProperties": False,
    },
}


def _json(value: dict) -> str:
    return json.dumps(value, ensure_ascii=False)


def _owners() -> set[str]:
    raw = os.environ.get(CONFIG["ownersEnv"], "")
    return {part for part in re.split(r"[,\s]+", raw) if part}


def _gateway() -> tuple[Any, Any, Any]:
    """The running gateway's Telegram bot and event loop, or Nones outside a gateway."""
    from gateway.config import Platform
    from gateway.run import _gateway_runner_ref

    runner = _gateway_runner_ref()
    if runner is None:
        return None, None, None
    adapter = runner.adapters.get(Platform.TELEGRAM)
    bot = getattr(adapter, "_bot", None)
    return runner, bot, getattr(runner, "_gateway_loop", None)


def _on_loop(loop: Any, coroutine: Any, timeout: float = 30) -> Any:
    return asyncio.run_coroutine_threadsafe(coroutine, loop).result(timeout)


def _session(name: str) -> str:
    from gateway.session_context import get_session_env

    return get_session_env(name, "") or ""


# ── Tool ─────────────────────────────────────────────────────────────────────


def request_secret(args: dict, **_: Any) -> str:
    name = str(args.get("name", "")).strip()
    purpose = " ".join(str(args.get("purpose", "")).split())[:MAX_PURPOSE]
    if not NAME_PATTERN.match(name):
        return _json({"success": False, "error": "name must match ^[a-z0-9][a-z0-9-]{0,47}$"})
    if not purpose:
        return _json({"success": False, "error": "purpose is required"})

    if _session("HERMES_SESSION_PLATFORM") != "telegram":
        return _json({"success": False, "error": (
            "Secret entry works only in the owner's Telegram chat with you. Ask the owner to continue "
            "this task there; never ask for the value in this chat.")})
    owners = _owners()
    chat_id = _session("HERMES_SESSION_CHAT_ID")
    thread_id = _session("HERMES_SESSION_THREAD_ID") or None
    if not owners or _session("HERMES_SESSION_USER_ID") not in owners or not chat_id:
        return _json({"success": False, "error": "Only the owner's own chat may receive a secret request."})

    _, bot, loop = _gateway()
    if bot is None or loop is None:
        return _json({"success": False, "error": "The Telegram gateway is not running in this process."})

    request = pending.Request(request_id=uuid.uuid4().hex[:12], name=name, chat_id=chat_id, thread_id=thread_id)
    if not pending.open_request(request):
        return _json({"success": False, "error": "This chat already waits for another secret; try again later."})

    prompt = (
        f"🔑 Hermes просит секрет «{name}»\n"
        f"Зачем: {purpose}\n\n"
        "Отправь значение следующим сообщением (или ответом на это). Hermes его не увидит: "
        "сообщение сразу зашифруется через age и удалится.\n"
        f"Отмена: {CANCEL}. Ждём 10 минут."
    )
    try:
        request.prompt_message_id = _on_loop(loop, telegram_ui.send_prompt(bot, chat_id, thread_id, prompt))
    except Exception as exc:  # noqa: BLE001
        pending.drop(request)
        logger.warning("secret-request: posting the prompt failed: %s", type(exc).__name__)
        return _json({"success": False, "error": "Could not post the request in Telegram."})

    if not request.done.wait(WAIT_SECONDS):
        pending.drop(request)
        # The owner may have answered at the last moment: the hook then resolved it after all.
        if not request.done.is_set():
            _on_loop(loop, telegram_ui.replace_prompt(
                bot, chat_id, request.prompt_message_id, f"⌛ Запрос секрета «{name}» истёк."))
            return _json({"success": False, "error": "The owner did not answer within 10 minutes."})
    return _json({"success": bool(request.result and request.result.get("ok")), **(request.result or {})})


# ── Hook ─────────────────────────────────────────────────────────────────────


async def _store(request: pending.Request, text: str, message_id: Optional[str], bot: Any) -> None:
    """Encrypt, delete the owner's message, confirm, and wake the waiting tool."""
    chat_id, name = request.chat_id, request.name
    deleted = await telegram_ui.delete(bot, chat_id, message_id)
    warning = "" if deleted else "\n⚠️ Не смог удалить твоё сообщение: удали его вручную."

    if text.strip() == CANCEL:
        await telegram_ui.replace_prompt(bot, chat_id, request.prompt_message_id, f"🚫 Запрос секрета «{name}» отменён.")
        pending.resolve(request, {"ok": False, "error": "The owner cancelled the request."})
        return
    if not text.strip():
        await telegram_ui.replace_prompt(bot, chat_id, request.prompt_message_id,
                                         f"❌ Для «{name}» нужен текст. Попроси Hermes запросить секрет заново.{warning}")
        pending.resolve(request, {"ok": False, "error": "The owner's reply had no text."})
        return

    path = Path(CONFIG["inbox"]) / f"{name}-{time.strftime('%Y%m%d-%H%M%S')}-{request.request_id}.age"
    try:
        await encrypt.to_file(CONFIG["age"], CONFIG["recipients"], text, path)
    except Exception as exc:  # noqa: BLE001
        logger.warning("secret-request: encrypting %s failed: %s", name, exc)
        await telegram_ui.replace_prompt(bot, chat_id, request.prompt_message_id,
                                         f"❌ Не смог зашифровать «{name}», секрет не сохранён.{warning}")
        pending.resolve(request, {"ok": False, "error": "Encryption failed; nothing was saved."})
        return

    await telegram_ui.replace_prompt(bot, chat_id, request.prompt_message_id,
                                     f"🔒 «{name}» получен и зашифрован.{warning}")
    logger.info("secret-request: stored %s as %s (message deleted: %s)", name, path, deleted)
    pending.resolve(request, {
        "ok": True,
        "name": name,
        "path": str(path),
        "recipients": "host and owner keys from secrets/secrets.nix",
        "next": (f"Copy the file to secrets/{name}.age in the repository, add "
                 f"\"{name}.age\".publicKeys = all; to secrets/secrets.nix, declare age.secrets.{name} "
                 "in the module that needs it, and open a needs-review PR. You cannot decrypt it."),
    })


async def on_pre_gateway_dispatch(event: Any, gateway: Any = None, **_: Any) -> Optional[dict]:
    source = getattr(event, "source", None)
    platform = getattr(getattr(source, "platform", None), "value", None)
    if source is None or platform != "telegram":
        return None
    chat_id = str(getattr(source, "chat_id", "") or "")
    thread_id = getattr(source, "thread_id", None) or None
    if not pending.is_open(chat_id, thread_id) or str(getattr(source, "user_id", "")) not in _owners():
        return None
    request = pending.claim(chat_id, thread_id)
    if request is None:
        return None

    # From here on the message belongs to the request: skip it whatever happens next.
    try:
        _, bot, _ = _gateway()
        text = getattr(event, "text", "") or ""
        message_id = getattr(event, "message_id", None)
        asyncio.get_running_loop().create_task(_store(request, text, message_id, bot))
    except Exception as exc:  # noqa: BLE001
        logger.warning("secret-request: handling the reply failed: %s", type(exc).__name__)
        pending.resolve(request, {"ok": False, "error": "Handling the reply failed; nothing was saved."})
    return {"action": "skip", "reason": "secret-request"}


def register(ctx: Any) -> None:
    ctx.register_tool(
        name="request_secret",
        toolset="secret_request",
        schema=SCHEMA,
        handler=request_secret,
        description="Ask the owner for a secret; you get only an age-encrypted file.",
        emoji="🔑",
    )
    ctx.register_hook("pre_gateway_dispatch", on_pre_gateway_dispatch)
