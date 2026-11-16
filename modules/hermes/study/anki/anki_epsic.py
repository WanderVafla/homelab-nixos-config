"""EPSIC flashcards in Anki, synced through the homelab Anki sync server.

Cards use the Quiz EPSIC format (id, sub, cat, kind, q, a, w | g, acc, f). Every card becomes one
note of the "EPSIC" note type, keyed by its id; the deck is "EPSIC::<subject name>".

  anki-epsic sync                      two-way sync with the server
  anki-epsic list [--sub SUB]          existing cards as JSON (id, sub, cat, kind, question)
  anki-epsic add FILE                  create or update cards from a JSON file; never deletes
  anki-epsic init                      create the note type (only once, on the first collection)
  anki-epsic templates                 replace the card templates and CSS with the shipped ones
  anki-epsic apply-progress FILE       one-time: copy Quiz EPSIC progress onto cards that are new

`add` and `templates` sync before and after. Changing the note type's fields forces a full sync,
so only `init` creates them; `templates` changes only the template text and CSS, which syncs
normally. `add` refuses to run if the note type is missing.

Settings: ANKI_COLLECTION, ANKI_SYNC_URL, ANKI_SYNC_USER, ANKI_SYNC_PASSWORD_FILE,
ANKI_EPSIC_TEMPLATES (front.html, back.html, style.css).
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from anki.collection import Collection

NOTETYPE = "EPSIC"
FIELDS = ["Id", "Subject", "Category", "Kind", "Group", "Question", "Answer",
          "Accepted", "Options", "Fact", "Source"]
SUBJECTS_KEY = "epsic_subjects"  # subject key -> display name, stored in the synced config
POOL_KEY = "epsic_pool"          # group -> extra wrong answers that are never asked
ZONE = ZoneInfo("Europe/Zurich")
DAY_MS = 86_400_000


def fail(message):
    print(json.dumps({"error": message}, ensure_ascii=False))
    sys.exit(1)


def open_collection():
    path = Path(os.environ.get("ANKI_COLLECTION", "/var/lib/hermes/anki/collection.anki2"))
    path.parent.mkdir(parents=True, exist_ok=True)
    return Collection(str(path))


# ---------- sync ----------

def sync(col, allow_upload=False):
    """Two-way sync. A full download replaces the local copy (the server is the source of truth,
    the owner reviews on the phone); a full upload only happens when explicitly allowed."""
    url = os.environ.get("ANKI_SYNC_URL")
    if not url:
        return "skipped: ANKI_SYNC_URL is not set"
    try:
        password = Path(os.environ["ANKI_SYNC_PASSWORD_FILE"]).read_text().strip()
    except (KeyError, OSError):
        fail("the Anki sync password is not available; ask the owner")
    auth = col.sync_login(os.environ.get("ANKI_SYNC_USER", "vladyslav"), password, url)
    out = col.sync_collection(auth, sync_media=False)
    if out.new_endpoint:
        auth.endpoint = out.new_endpoint
    if out.required in (out.NO_CHANGES, out.NORMAL_SYNC):
        return "synced"
    if out.required == out.FULL_DOWNLOAD:
        upload = False
    elif allow_upload:  # first upload of a new collection (FULL_UPLOAD or FULL_SYNC)
        upload = True
    elif out.required == out.FULL_SYNC and col.note_count() == 0 and not notetype(col):
        upload = False  # a blank local collection (never set up): take the server copy
    else:
        col.abort_sync()
        fail("the server needs a full sync that could lose reviews; ask the owner to sync "
             "Anki on the phone first and tell Claude Code")
    col.close_for_full_sync()
    col.full_upload_or_download(auth=auth, server_usn=None, upload=upload)
    col.reopen(after_full_sync=True)
    return "full upload" if upload else "full download"


# ---------- note type ----------

def notetype(col):
    return col.models.by_name(NOTETYPE)


def cmd_init(col, args):
    if notetype(col):
        fail("the EPSIC note type already exists")
    model = col.models.new(NOTETYPE)
    for name in FIELDS:
        col.models.add_field(model, col.models.new_field(name))
    col.models.add_template(model, col.models.new_template("Card"))
    apply_templates(model)
    col.models.add_dict(model)
    print(json.dumps({"created": NOTETYPE}))


def apply_templates(model):
    """Copy the shipped front, back and CSS into the note type; True if anything changed."""
    templates = Path(os.environ["ANKI_EPSIC_TEMPLATES"])
    template = model["tmpls"][0]
    new = {"qfmt": (templates / "front.html").read_text(), "afmt": (templates / "back.html").read_text()}
    css = (templates / "style.css").read_text()
    changed = any(template[k] != v for k, v in new.items()) or model["css"] != css
    template.update(new)
    model["css"] = css
    return changed


def cmd_templates(col, args):
    if not notetype(col):
        fail("the EPSIC note type is missing; ask the owner")
    before = sync(col)
    model = notetype(col)
    changed = apply_templates(model)
    if changed:
        col.models.update_dict(model)
    print(json.dumps({"templates": "updated" if changed else "unchanged",
                      "sync_before": before, "sync_after": sync(col) if changed else "skipped"}))


# ---------- cards ----------

def find_note(col, card_id):
    ids = col.find_notes(f'"note:{NOTETYPE}" "Id:{card_id}"')
    return col.get_note(ids[0]) if ids else None


def deck_id(col, sub):
    subjects = col.get_config(SUBJECTS_KEY, {})
    return col.decks.id(f"EPSIC::{subjects.get(sub, sub)}")


def fact_parts(card):
    f = card.get("f") or []
    return (f[0] if len(f) > 0 else ""), (f[1] if len(f) > 1 else "")


def fill(note, card):
    fact, source = fact_parts(card)
    note["Id"] = card["id"]
    note["Subject"] = card["sub"]
    note["Category"] = card.get("cat", "")
    note["Kind"] = card["kind"]
    note["Group"] = card.get("g", "")
    note["Question"] = card["q"]
    note["Answer"] = card["a"]
    note["Accepted"] = json.dumps(card.get("acc", []), ensure_ascii=False)
    note["Options"] = json.dumps(card.get("w", []), ensure_ascii=False)
    note["Fact"] = fact
    note["Source"] = source
    note.tags = [card["sub"]]


def validate(card):
    for key in ("id", "sub", "kind", "q", "a"):
        if not card.get(key):
            return f"card {card.get('id', '?')}: missing {key}"
    if card["kind"] not in ("mc", "fr", "ru", "num"):
        return f"card {card['id']}: unknown kind {card['kind']}"
    if card["kind"] == "mc" and not card.get("w") and not card.get("g"):
        return f"card {card['id']}: a multiple-choice card needs w or g"
    if card["kind"] != "mc" and not card.get("acc"):
        return f"card {card['id']}: a typed card needs acc"
    return None


def refresh_group_options(col):
    """A group card offers the answers of the other cards in its group (plus pool entries)."""
    pool = col.get_config(POOL_KEY, {})
    groups = {}
    for nid in col.find_notes(f'"note:{NOTETYPE}" "Group:_*"'):
        note = col.get_note(nid)
        groups.setdefault(note["Group"], []).append(note)
    for group, notes in groups.items():
        answers = [n["Answer"] for n in notes] + pool.get(group, [])
        for note in notes:
            options = json.dumps(sorted({a for a in answers if a != note["Answer"]}), ensure_ascii=False)
            if note["Options"] != options:
                note["Options"] = options
                col.update_note(note)


def cmd_add(col, args):
    data = json.loads(Path(args.file).read_text())
    cards = data["CARDS"] if isinstance(data, dict) else data
    errors = [e for e in (validate(c) for c in cards if not c.get("pool")) if e]
    if errors:
        fail("; ".join(errors[:10]))
    sync_before = sync(col)
    model = notetype(col)
    if not model:
        fail("the EPSIC note type is missing; it is created once by Claude Code, not by the agent")
    if isinstance(data, dict) and data.get("SUBJECTS"):
        subjects = col.get_config(SUBJECTS_KEY, {})
        subjects.update({k: v["name"] for k, v in data["SUBJECTS"].items()})
        col.set_config(SUBJECTS_KEY, subjects)
    pool = col.get_config(POOL_KEY, {})
    created, updated = [], []
    for card in cards:
        if card.get("pool"):
            pool.setdefault(card["g"], [])
            if card["a"] not in pool[card["g"]]:
                pool[card["g"]].append(card["a"])
            continue
        note = find_note(col, card["id"])
        if note:
            fill(note, card)
            col.update_note(note)
            updated.append(card["id"])
        else:
            note = col.new_note(model)
            fill(note, card)
            note.guid = "epsic-" + card["id"]
            col.add_note(note, deck_id(col, card["sub"]))
            created.append(card["id"])
    col.set_config(POOL_KEY, pool)
    refresh_group_options(col)
    print(json.dumps({"created": len(created), "updated": len(updated), "new_ids": created,
                      "sync_before": sync_before, "sync_after": sync(col)}, ensure_ascii=False))


def cmd_list(col, args):
    query = f'"note:{NOTETYPE}"' + (f' "Subject:{args.sub}"' if args.sub else "")
    rows = []
    for nid in col.find_notes(query):
        note = col.get_note(nid)
        rows.append({"id": note["Id"], "sub": note["Subject"], "cat": note["Category"],
                     "kind": note["Kind"], "q": note["Question"]})
    print(json.dumps(rows, ensure_ascii=False, indent=1))


def cmd_sync(col, args):
    print(json.dumps({"sync": sync(col, allow_upload=args.allow_upload)}))


def cmd_apply_progress(col, args):
    """Copy Quiz EPSIC review state (SM-2: due, ivl, ease, reps, lapses) onto new cards only."""
    progress = json.loads(Path(args.file).read_text())["cards"]
    today_start = datetime.now(ZONE).replace(hour=0, minute=0, second=0, microsecond=0)
    today_ms = int(today_start.timestamp() * 1000)
    applied, skipped = 0, []
    for card_id, rec in progress.items():
        note = find_note(col, card_id)
        if not note or rec.get("s") != "review":
            skipped.append(card_id)
            continue
        card = note.cards()[0]
        if card.type != 0:  # already scheduled in Anki: keep Anki's state
            skipped.append(card_id)
            continue
        card.type = card.queue = 2
        card.ivl = max(1, int(rec["ivl"]))
        card.factor = int(round(rec["ease"] * 1000))
        card.reps = int(rec.get("reps", 0))
        card.lapses = int(rec.get("lapses", 0))
        card.due = col.sched.today + max(0, (int(rec["due"]) - today_ms) // DAY_MS)
        card.mod = int(time.time())
        col.update_card(card)
        applied += 1
    print(json.dumps({"applied": applied, "skipped": skipped}))


def main():
    parser = argparse.ArgumentParser(prog="anki-epsic", description="EPSIC flashcards in Anki")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("init", help="create the EPSIC note type")
    commands.add_parser("templates", help="update the card templates and CSS")
    s = commands.add_parser("sync", help="sync with the server")
    s.add_argument("--allow-upload", action="store_true", help="allow replacing the server copy")
    lst = commands.add_parser("list", help="existing cards")
    lst.add_argument("--sub")
    add = commands.add_parser("add", help="create or update cards from a JSON file")
    add.add_argument("file")
    prog = commands.add_parser("apply-progress", help="copy Quiz EPSIC progress onto new cards")
    prog.add_argument("file")
    args = parser.parse_args()

    handlers = {"init": cmd_init, "templates": cmd_templates, "sync": cmd_sync, "list": cmd_list,
                "add": cmd_add, "apply-progress": cmd_apply_progress}
    col = open_collection()
    try:
        handlers[args.command](col, args)
    finally:
        if col.db:
            col.close()


if __name__ == "__main__":
    main()
