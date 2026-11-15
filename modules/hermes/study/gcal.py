"""Manage events in the study calendar (Google Calendar) for the Hermes agent.

Every event this tool writes carries a stable key (for example "moodle-assign-123") in its
private extended properties, so a repeated sync updates events instead of duplicating them.
The tool only lists, updates and deletes events that carry such a key, never the owner's own.

  gcal list [--from YYYY-MM-DD] [--to YYYY-MM-DD]
  gcal upsert --key KEY --title TITLE --start WHEN [--end WHEN] [--description TEXT] [--location TEXT]
  gcal delete --key KEY

WHEN is YYYY-MM-DD (all-day), YYYY-MM-DDTHH:MM (Europe/Zurich) or @<unix time> (as Moodle returns).
Settings: GOOGLE_CALENDAR_ID and GOOGLE_CALENDAR_KEY_FILE (service account JSON key).
"""

import argparse
import json
import os
import sys
import urllib.parse
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

ZONE = ZoneInfo("Europe/Zurich")
KEY_PROPERTY = "hermes_key"
SCOPES = ["https://www.googleapis.com/auth/calendar.events"]


def fail(message):
    print(json.dumps({"error": message}, ensure_ascii=False))
    sys.exit(1)


def session_and_url():
    calendar = os.environ.get("GOOGLE_CALENDAR_ID", "")
    if not calendar:
        fail("GOOGLE_CALENDAR_ID is not set; ask the owner to add it to hermes-env")
    try:
        credentials = service_account.Credentials.from_service_account_file(
            os.environ["GOOGLE_CALENDAR_KEY_FILE"], scopes=SCOPES)
    except (OSError, ValueError, KeyError):
        fail("the calendar key is not set yet; ask the owner to add google-calendar-key.age")
    url = f"https://www.googleapis.com/calendar/v3/calendars/{urllib.parse.quote(calendar)}/events"
    return AuthorizedSession(credentials), url


def parse_when(text):
    """Return a Google Calendar time object and the matching Python value."""
    if text.startswith("@"):
        moment = datetime.fromtimestamp(int(text[1:]), ZONE)
    elif "T" in text:
        moment = datetime.fromisoformat(text).replace(tzinfo=ZONE)
    else:
        day = date.fromisoformat(text)
        return {"date": day.isoformat()}, day
    return {"dateTime": moment.replace(tzinfo=None).isoformat(timespec="seconds"), "timeZone": str(ZONE)}, moment


def default_end(start):
    if isinstance(start, datetime):
        end = start + timedelta(minutes=30)
        return {"dateTime": end.replace(tzinfo=None).isoformat(timespec="seconds"), "timeZone": str(ZONE)}
    return {"date": (start + timedelta(days=1)).isoformat()}  # all-day end is exclusive


def find(session, url, key):
    response = session.get(url, params={"privateExtendedProperty": f"{KEY_PROPERTY}={key}"})
    response.raise_for_status()
    items = response.json().get("items", [])
    return items[0] if items else None


def summary(event):
    return {
        "key": event.get("extendedProperties", {}).get("private", {}).get(KEY_PROPERTY),
        "title": event.get("summary"),
        "start": event["start"].get("dateTime") or event["start"].get("date"),
        "end": event["end"].get("dateTime") or event["end"].get("date"),
    }


def cmd_list(session, url, args):
    first = date.fromisoformat(args.from_) if args.from_ else date.today()
    last = date.fromisoformat(args.to) if args.to else first + timedelta(days=30)
    params = {
        "timeMin": datetime.combine(first, datetime.min.time(), ZONE).isoformat(),
        "timeMax": datetime.combine(last, datetime.min.time(), ZONE).isoformat(),
        "singleEvents": "true",
        "orderBy": "startTime",
        "maxResults": "250",
    }
    response = session.get(url, params=params)
    response.raise_for_status()
    events = [summary(e) for e in response.json().get("items", [])]
    print(json.dumps([e for e in events if e["key"]], ensure_ascii=False, indent=1))


def cmd_upsert(session, url, args):
    start, start_value = parse_when(args.start)
    end = parse_when(args.end)[0] if args.end else default_end(start_value)
    body = {
        "summary": args.title,
        "description": args.description or "",
        "location": args.location or "",
        "start": start,
        "end": end,
        "extendedProperties": {"private": {KEY_PROPERTY: args.key}},
    }
    existing = find(session, url, args.key)
    if existing:
        response = session.patch(f"{url}/{existing['id']}", json=body)
        action = "updated"
    else:
        response = session.post(url, json=body)
        action = "created"
    response.raise_for_status()
    print(json.dumps({"action": action, **summary(response.json())}, ensure_ascii=False))


def cmd_delete(session, url, args):
    existing = find(session, url, args.key)
    if not existing:
        print(json.dumps({"action": "not-found", "key": args.key}))
        return
    session.delete(f"{url}/{existing['id']}").raise_for_status()
    print(json.dumps({"action": "deleted", "key": args.key}))


def main():
    parser = argparse.ArgumentParser(prog="gcal", description="Study calendar events")
    commands = parser.add_subparsers(dest="command", required=True)

    listing = commands.add_parser("list", help="events written by this tool")
    listing.add_argument("--from", dest="from_")
    listing.add_argument("--to")

    upsert = commands.add_parser("upsert", help="create or update the event with this key")
    upsert.add_argument("--key", required=True)
    upsert.add_argument("--title", required=True)
    upsert.add_argument("--start", required=True)
    upsert.add_argument("--end")
    upsert.add_argument("--description")
    upsert.add_argument("--location")

    delete = commands.add_parser("delete", help="delete the event with this key")
    delete.add_argument("--key", required=True)

    args = parser.parse_args()
    session, url = session_and_url()
    try:
        {"list": cmd_list, "upsert": cmd_upsert, "delete": cmd_delete}[args.command](session, url, args)
    except Exception as error:  # report API errors as JSON for the agent
        details = getattr(getattr(error, "response", None), "text", "")
        fail(f"{error} {details}".strip())


if __name__ == "__main__":
    main()
