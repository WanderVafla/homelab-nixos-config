"""The Telegram side of a secret request: the prompt, its final status, and deleting the reply.

Uses the gateway's live python-telegram-bot ``Bot`` directly, because the adapter's ``send`` has no
force-reply markup. All texts are plain (no parse mode), so a name or purpose chosen by the agent
cannot inject formatting or links.
"""

from __future__ import annotations

from typing import Any, Optional


async def send_prompt(bot: Any, chat_id: str, thread_id: Optional[str], text: str) -> str:
    """Post the request with force-reply, so the owner's client opens a reply to it."""
    from telegram import ForceReply

    kwargs: dict[str, Any] = {}
    if thread_id:
        kwargs["message_thread_id"] = int(thread_id)
    message = await bot.send_message(
        chat_id=int(chat_id),
        text=text,
        reply_markup=ForceReply(selective=True, input_field_placeholder="секрет"),
        **kwargs,
    )
    return str(message.message_id)


async def replace_prompt(bot: Any, chat_id: str, message_id: Optional[str], text: str) -> None:
    """Turn the prompt into its outcome; a failed edit is not worth failing the request for."""
    if not message_id:
        return
    try:
        await bot.edit_message_text(chat_id=int(chat_id), message_id=int(message_id), text=text)
    except Exception:  # noqa: BLE001 -- cosmetic: the secret is already handled
        pass


async def delete(bot: Any, chat_id: str, message_id: Optional[str]) -> bool:
    """Delete the owner's message; in a group the bot needs the "delete messages" admin right."""
    if not message_id:
        return False
    try:
        return bool(await bot.delete_message(chat_id=int(chat_id), message_id=int(message_id)))
    except Exception:  # noqa: BLE001 -- reported to the owner by the caller
        return False
