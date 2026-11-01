#!/usr/bin/env python3
"""Fetch yandex.ru/pogoda for a place and print what the bar widget shows.

This is the data side of the pole.yandex-weather widget. The widget never runs
shell commands built from user input: the place slug (or a typed city name) is
the only argument, and every string printed here is shown as plain text.

Subcommands
-----------
  search <query>        Places matching a typed name.
  weather <slug>        Current weather and a 10-day forecast.
  validate <slug|url>   Where a name or a pasted Yandex link leads.

Output is one JSON object on stdout. A failure is {"error": "<code>"} with a
non-zero exit status; the codes are stable so the widget can translate them.
"""

import html
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/140.0 Safari/537.36"
)
TIMEOUT = 20
MAX_BYTES = 4 * 1024 * 1024

BASE = "https://yandex.ru/pogoda/"
SUGGEST = "https://suggest.yandex.ru/suggest-ya.cgi"

# A slug is a place name in the site's own transliteration: lower-case Latin,
# digits, and dashes ("elektrougli", "saint-petersburg", "new-york").
SLUG = re.compile(r"^[a-z0-9][a-z0-9\-]{0,80}$")

PARTS = ("m", "d", "e", "n")  # morning, day, evening, night

# The kind of weather behind a phrase the page prints: "небольшой дождь" is
# rain, "дождь со снегом" is sleet, "гроза с градом" is thunder. The widget
# draws its own mark for the kind, always with the page's own words beside it.
KIND_WORDS = (
    ("thunder", ("гроз",)),
    ("sleet", ("со снегом", "снег с дожд", "дожд со снег", "мокрый снег",
               "снег с крупой", "с крупой")),
    ("hail", ("град", "круп")),
    ("snow", ("снег", "снеж", "метел", "позем", "позём")),
    ("rain", ("дожд", "ливн", "изморо")),
    ("fog", ("туман", "дымка", "мгла")),
    ("haze", ("пыль", "дым", "мгл")),
    ("wind", ("ветер", "буря", "шторм", "шквал", "ураган", "смерч")),
    ("mostly", ("облачно с прояснениями", "малооблачно", "переменная облачность")),
    ("overcast", ("пасмурно", "облачно", "обл")),
    ("clear", ("ясно", "солнечно", "безоблачн")),
)


# The page's own condition codes for the current reading, and the icon names it
# pairs them with, reduced to the same kinds.
CONDITION_KIND = {
    "CLEAR": "clear",
    "PARTLY_CLOUDY": "mostly",
    "CLOUDY": "mostly",
    "OVERCAST": "overcast",
    "LIGHT_RAIN": "rain",
    "RAIN": "rain",
    "HEAVY_RAIN": "rain",
    "SHOWERS": "rain",
    "LIGHT_SNOW": "snow",
    "SNOW": "snow",
    "HEAVY_SNOW": "snow",
    "SLEET": "sleet",
    "THUNDERSTORM": "thunder",
    "HAIL": "hail",
    "FOG": "fog",
    "MIST": "fog",
}

FACT_ICON_KIND = {
    "ovc": "overcast", "ovc_ts": "thunder", "ovc_ra": "rain", "ovc_ra_sn": "sleet",
    "ovc_sn": "snow", "ovc_mix": "sleet", "ovc_ha": "hail", "ovc_fg": "fog",
    "bkn_ra": "rain", "bkn_sn": "snow", "bkn_ts": "thunder", "bkn_ra_sn": "sleet",
}


def kind_of(condition, is_night=False):
    """The kind of weather a phrase describes, and whether it is at night.

    Night is drawn with a moon instead of the sun: the page marks it by the
    part of the day (evening and night), or by the `_n` suffix on a current
    icon name.
    """
    text = (condition or "").strip().lower().replace("ё", "е")
    for kind, words in KIND_WORDS:
        for word in words:
            if word in text:
                return {"kind": kind, "night": bool(is_night)}
    return {"kind": "unknown", "night": bool(is_night)}


class FetchError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


# --------------------------------------------------------------------------
# HTTP


def fetch(url):
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/xhtml+xml",
            "Accept-Language": "ru,en;q=0.8",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            body = response.read(MAX_BYTES + 1)
            final_url = response.geturl()
    except urllib.error.HTTPError as error:
        raise FetchError("not-found" if error.code == 404 else "network")
    except (urllib.error.URLError, TimeoutError, OSError):
        raise FetchError("network")

    if len(body) > MAX_BYTES:
        raise FetchError("too-large")
    return body.decode("utf-8", "replace"), final_url


# --------------------------------------------------------------------------
# Text helpers


def strip_tags(value):
    return re.sub(r"<[^>]+>", "", value or "")


def unescape(value):
    return html.unescape(value or "").replace("\xa0", " ")


def clean_text(value, limit=120):
    """A short, single-line string, safe to hand to the QML side as plain text."""
    return " ".join(unescape(strip_tags(value)).split())[:limit]


def temperature(value):
    """'+8°' / '−1°' / '-3' -> int, or None."""
    match = re.search(r"([+\-−]?)\s*(\d{1,2})", value or "")
    if not match:
        return None
    number = int(match.group(2))
    return -number if match.group(1) in ("-", "−") else number


def title_case_slug(slug):
    return " ".join(part.capitalize() for part in slug.replace("_", "-").split("-") if part)


def slug_from_url(url):
    match = re.search(r"/pogoda/(?:[a-z]{2}(?:-[A-Z]{2})?/)?([^/?#]+)", url or "")
    return match.group(1) if match else ""


# --------------------------------------------------------------------------
# The page


def place_name(page, slug):
    """The place as Yandex names it, e.g. Электроугли for /elektrougli."""
    patterns = (
        # The details page: "Погода на 10 дней" then a hidden " — Электроугли".
        r'class="Hero_heading[^"]*">[\s\S]{0,400}?<p class="A11Y_visuallyHidden__[^"]*">\s*—\s*([^<]{1,80})</p>',
        # The main page: "Погода в Электроуглях" then "(Электроугли, Россия)".
        r'Погода\s+в\s+[^<]{0,40}<p class="A11Y_visuallyHidden__[^"]*">\s*\(\s*([^,<)]{1,80})',
    )
    for pattern in patterns:
        match = re.search(pattern, page)
        if match:
            name = clean_text(match.group(1), 80)
            if name:
                return name
    return title_case_slug(slug)


def current_weather(page):
    """Now: temperature, what it feels like, the words, wind, humidity, pressure."""
    current = {
        "temp": None, "feels": None, "condition": "", "kind": "unknown", "night": False,
        "humidity": None, "pressure": None, "wind": None, "windDir": "",
    }

    # Some layouts embed the blob as escaped JSON inside a script payload.
    unescaped = page.replace('\\"', '"')
    fact = re.search(r'"fact":\{([\s\S]{0,2000}?)\}', unescaped)
    fact_values = {}
    if fact:
        try:
            fact_values = json.loads("{" + fact.group(1) + "}")
        except ValueError:
            fact_values = {}
        if isinstance(fact_values, dict):
            current["temp"] = as_int(fact_values.get("temperatureInCelsius", fact_values.get("temperature")))
            current["feels"] = as_int(fact_values.get("feelsLikeInCelsius", fact_values.get("feelsLike")))
            current["humidity"] = as_int(fact_values.get("humidity"))
            current["pressure"] = as_int(fact_values.get("pressure"))
            current["wind"] = as_float(fact_values.get("windSpeedInMetersPerSecond", fact_values.get("windSpeed")))
            current["windDir"] = direction_letters(fact_values.get("windDirection"))
            current["kind"] = CONDITION_KIND.get(str(fact_values.get("condition") or ""), "unknown")
            icon_name = str(fact_values.get("icon") or "")
            current["night"] = icon_name.endswith("_n") or str(fact_values.get("daytime") or "") == "NIGHT"
            # The current condition has no phrase on the page, so its mark goes
            # by the fact's own condition and icon name.
            if current["kind"] == "unknown":
                current["kind"] = FACT_ICON_KIND.get(icon_name, "unknown")

    # The hidden summary sentence is there on both page layouts:
    # "Электроугли, погода сейчас: Ясно. Сегодня осадков ..., Температура воздуха +9°, ..."
    summary = re.search(r"погода сейчас:\s*([^<]{0,300})", page)
    if summary:
        text = clean_text(summary.group(1), 300)
        head = re.split(r"\.\s", text, maxsplit=1)[0].strip(" .")
        if head and not current["condition"] and len(head) < 40:
            current["condition"] = head
        # "Сегодня осадков не ожидается" stands where a condition would be when
        # there is nothing to report, but "ясно" is already on the page.
        elif not current["condition"]:
            for phrase in re.findall(r"(?:^|,\s)([А-ЯЁа-яё][а-яё ]{2,25})(?=\s*[.,])", text):
                if kind_of(phrase)["kind"] != "unknown":
                    current["condition"] = clean_text(phrase, 40)
                    break
        for pattern, key in (
            (r"Температура воздуха\s*([+\-−]?\d+)", "temp"),
            (r"ощущается как\s*([+\-−]?\d+)", "feels"),
            (r"Скорость ветра\s*([\d.,]+)", "wind"),
            (r"Влажность\s*(\d+)", "humidity"),
            (r"Давление\s*(\d+)", "pressure"),
        ):
            match = re.search(pattern, text)
            if not match:
                continue
            if key == "wind":
                if current["wind"] is None:
                    current["wind"] = as_float(match.group(1).replace(",", "."))
            elif key == "humidity" or key == "pressure":
                if current[key] is None:
                    current[key] = int(match.group(1))
            elif current[key] is None:
                current[key] = temperature(match.group(1))

    # Last resort for the temperature: the hero at the top of the page.
    if current["temp"] is None:
        hero_temp = re.search(r'AppFactTemperature_value__[^"]*">([+\-−]?\d+)<', page)
        if hero_temp:
            current["temp"] = temperature(hero_temp.group(1))

    # The phrase wins over the code: it is what the site shows.
    current["condition"] = current["condition"].lower()
    if current["condition"]:
        described = kind_of(current["condition"], current["night"])
        current["kind"] = described["kind"] if described["kind"] != "unknown" else current["kind"]
        current["night"] = described["night"]
    return current


def direction_letters(value):
    """'NORTH_EAST' or 'СВ' -> ['СВ'] joined, e.g. 'СВ'."""
    if not value:
        return ""
    names = {
        "NORTH": "С", "SOUTH": "Ю", "WEST": "З", "EAST": "В",
        "NORTH_EAST": "СВ", "NORTH_WEST": "СЗ", "SOUTH_EAST": "ЮВ", "SOUTH_WEST": "ЮЗ",
        "N": "С", "S": "Ю", "W": "З", "E": "В", "NE": "СВ", "NW": "СЗ", "SE": "ЮВ", "SW": "ЮЗ",
    }
    text = str(value)
    if text in names:
        return names[text]
    return text if re.match(r"^[А-ЯЁ]{1,2}$", text) else ""


def as_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def as_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


# --------------------------------------------------------------------------
# Forecast


def day_cards(page):
    """Every day's detailed card on the 10-day page, in order."""
    starts = [match.start() for match in re.finditer(r'data-day="(\d+)_\d+"', page)]
    cards = []
    for index, start in enumerate(starts):
        end = starts[index + 1] if index + 1 < len(starts) else start + 24000
        cards.append(page[start:end])
    return cards


def parse_day(card, number):
    title = re.search(r'grid-area:day-title"[^>]*>([^<]{1,120})</h3>', card)
    heading = clean_text(title.group(1), 60) if title else ""

    parts = {}
    for part in PARTS:
        temp = re.search(r'grid-area:%s-temp"[^>]*>([^<]{1,12})<' % part, card)
        text = re.search(r'grid-area:%s-text"[^>]*>([^<]{1,80})<' % part, card)
        humidity = re.search(r'grid-area:%s-hum"[^>]*>(\d{1,3})%%' % part, card)
        feels = re.search(r'grid-area:%s-feels"[^>]*>([^<]{1,12})<' % part, card)
        # The wind cell appears twice per part: "5" and then "5 м/с" or "5,2 м/с и
        # порывы до 9 м/с". The longer one is the last.
        winds = re.findall(r'grid-area:%s-wind"[^>]*>([^<]{1,40})<' % part, card)
        direction = re.search(
            r'grid-area:%s-dir"[^>]*>[\s\S]{0,300}?direction__value__[^"]*">([^<]{1,12})<'
            % part, card)
        degrees = re.search(
            r'grid-area:%s-dir"[^>]*>[\s\S]{0,300}?rotate\((-?\d+(?:\.\d+)?)deg\)' % part, card)

        if not (temp or text):
            continue

        phrase = clean_text(text.group(1), 80) if text else ""
        described = kind_of(phrase, part in ("e", "n"))
        parts[part] = {
            "part": part,
            "temp": temperature(temp.group(1)) if temp else None,
            "condition": phrase,
            "kind": described["kind"],
            "night": described["night"],
            "humidity": int(humidity.group(1)) if humidity else None,
            "wind": clean_text(winds[-1], 40) if winds else "",
            "feels": temperature(feels.group(1)) if feels else None,
            "windDir": clean_text(direction.group(1), 8) if direction else "",
            "windDirDeg": float(degrees.group(1)) if degrees else None,
        }

    return {"index": number, "title": heading, "parts": parts}


# --------------------------------------------------------------------------
# Commands


def cmd_weather(argument):
    slug = argument.strip()
    if not SLUG.match(slug):
        return {"error": "bad-slug"}, 2

    page, final_url = fetch(BASE + slug)
    resolved = slug_from_url(final_url) or slug

    cards = day_cards(page)
    days = [parse_day(card, index + 1) for index, card in enumerate(cards)]
    days = [day for day in days if day["parts"]][:10]
    if not days:
        return {"error": "no-forecast"}, 1

    current = current_weather(page)
    if current["temp"] is None:
        # The 10-day page carries the forecast but not the current reading;
        # the place's own page does.
        try:
            main_page, _ = fetch(BASE + resolved)
            current = current_weather(main_page)
        except FetchError:
            pass
    if current["temp"] is None:
        daytime = days[0]["parts"].get("d") or {}
        current["temp"] = daytime.get("temp")

    return {
        "slug": resolved,
        "name": place_name(page, resolved),
        "url": "https://yandex.ru/pogoda/" + resolved,
        "fetched": int(time.time()),
        "current": current,
        "days": days,
    }, 0


def flatten(value):
    """Every list inside a suggestion payload, however deeply nested."""
    stack = [value]
    out = []
    while stack:
        item = stack.pop(0)
        if isinstance(item, list):
            out.append(item)
            for inner in item:
                if isinstance(inner, list):
                    stack.append(inner)
    return out


def cmd_search(argument):
    query = " ".join((argument or "").split())[:60]
    if not query:
        return {"results": []}, 0

    # Yandex only offers its weather entry for a phrase it recognises as a place,
    # and "москва" alone is not one — it is asked as "<what was typed> погода",
    # which also answers for the English name of a Russian city (Moscow).
    raw, _ = fetch(SUGGEST + "?part=" + urllib.parse.quote(query + " погода", safe="") + "&srv=weather&v=4")
    try:
        payload = json.loads(raw)
    except ValueError:
        return {"error": "parse"}, 1

    plain = [entry for entry in payload[1] if isinstance(entry, str)] if (
        isinstance(payload, list) and len(payload) > 1 and isinstance(payload[1], list)) else []

    results = []
    seen = set()
    for block in flatten(payload):
        if not block or block[0] != "weather":
            continue
        # ["weather", "<query>", "+10 °C", "skc_d", "yandex.ru/pogoda/<slug>"]
        for entry in block:
            if not (isinstance(entry, str) and "/pogoda/" in entry):
                continue
            slug = slug_from_url(entry)
            if not SLUG.match(slug) or slug in seen:
                break
            seen.add(slug)
            temp = next((value for value in block
                         if isinstance(value, str) and re.match(r"^[+\-−]?\d+\s*°", value)), "")
            # The block is ["weather", "<what was typed> погода", "+8 °C",
            # "<icon code>", "<link>"]; the query is the one with " погода".
            query = next((value for value in block
                          if isinstance(value, str) and value.endswith(" погода")), "")
            results.append({
                "slug": slug,
                "name": title_case_slug(slug),
                "query": clean_text(query.replace(" погода", ""), 40),
                "temp": clean_text(temp, 12),
            })
            break

    # The weather block only names one place, and not every place has one. The
    # plain suggestions then go through the site's imprecise search, which
    # lands on the right page when there is one — a misspelled guess comes back
    # as the site's own spelling, or as a 404 for a place it does not know.
    # Search lists more than six names; four are enough to find the place
    # without a burst of requests for a name nobody meant.
    if not results:
        for text in plain[:4]:
            if len(text) < 3:
                continue
            slug = search_slug(text)
            if not slug or slug in seen:
                continue
            seen.add(slug)
            results.append({"slug": slug, "name": title_case_slug(slug),
                            "query": text[:40], "temp": ""})


    return {"results": results[:6]}, 0


def search_slug(text):
    """The slug the site itself redirects a guess to."""
    guess = transliterate(text)
    if not guess:
        return ""
    request = urllib.request.Request(
        BASE + guess, headers={"User-Agent": USER_AGENT, "Accept": "text/html"})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            return slug_from_url(response.geturl())
    except (urllib.error.URLError, TimeoutError, OSError):
        return ""


def transliterate(text):
    table = {
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh",
        "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o",
        "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "kh", "ц": "ts",
        "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu",
        "я": "ya", "і": "i", "ї": "yi", "є": "ye", "ґ": "g",
    }
    out = []
    for char in (text or "").lower().strip():
        if char in table:
            out.append(table[char])
        elif re.match(r"[a-z0-9]", char):
            out.append(char)
        elif char in " -_":
            out.append("-")
    return re.sub(r"-{2,}", "-", "".join(out)).strip("-")


GEO = "https://ipinfo.io/json"


def locate():
    """The place the network says this machine is in.

    ipinfo.io answers with a rough city and a pair of coordinates for the
    public address — the same place the browser would land on — and Yandex,
    asked with those coordinates, names the place itself: its page carries the
    locality's own slug beside the city it belongs to.
    """
    raw, _ = fetch(GEO)
    try:
        info = json.loads(raw)
    except ValueError:
        raise FetchError("parse")
    if not isinstance(info, dict):
        raise FetchError("parse")
    loc = str(info.get("loc") or "")
    match = re.match(r"^(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)$", loc)
    if not match:
        raise FetchError("geo")

    lat, lon = match.group(1), match.group(2)
    page, final_url = fetch(BASE + "?lat=" + lat + "&lon=" + lon)

    # Yandex names the place for those coordinates in its own JSON, as
    # `"locality":{"id":…,"name":"Электросталь","slug":"elektrostal",…}`. The
    # blob is escaped inside a script payload, so both spellings are tried.
    text = page.replace('\\"', '"')
    name = ""
    slug = ""
    for pattern in (
        r'"locality":\{[^}]{0,400}?"name":"([^"]{1,60})"[^}]{0,300}?"slug":"([a-z0-9\-]{2,60})"',
        r'"locality":\{[^}]{0,400}?"slug":"([a-z0-9\-]{2,60})"[^}]{0,300}?"name":"([^"]{1,60})"',
    ):
        match = re.search(pattern, text)
        if match:
            first, second = match.group(1), match.group(2)
            if re.match(r"^[a-z0-9\-]+$", first) and not re.match(r"^[a-z0-9\-]+$", second):
                slug, name = first, second
            else:
                name, slug = first, second
            break
    if not slug:
        # The page was not the place's own — Yandex kept this machine's address
        # — but its heading still names the city.
        raised = re.search(
            r'Погода\s+в\s+[^<]{0,40}<p class="A11Y_visuallyHidden__[^"]*">\s*\(\s*([^,<)]{1,80})',
            page)
        if raised:
            name = clean_text(raised.group(1), 80)
        if not name:
            raise FetchError("geo")
        slug = transliterate(name)

    return {
        "slug": slug,
        "name": name or title_case_slug(slug),
        "latitude": float(lat),
        "longitude": float(lon),
        "url": "https://yandex.ru/pogoda/" + slug,
    }, 0


def cmd_validate(argument):
    value = (argument or "").strip()
    if not value:
        return {"error": "bad-slug"}, 2

    if re.search(r"yandex\.[a-z.]+/pogoda/", value):
        slug = slug_from_url(value)
    else:
        slug = value.lower().replace(" ", "-")
    if not SLUG.match(slug):
        return {"error": "bad-slug"}, 2

    page, final_url = fetch(BASE + slug)
    resolved = slug_from_url(final_url) or slug
    return {
        "slug": resolved,
        "name": place_name(page, resolved),
        "url": "https://yandex.ru/pogoda/" + resolved,
    }, 0


def main(argv):
    if len(argv) < 2:
        print(json.dumps({"error": "usage"}))
        return 2

    command = argv[1]
    argument = " ".join(argv[2:]) if len(argv) > 2 else ""
    try:
        if command == "weather":
            result, status = cmd_weather(argument)
        elif command == "search":
            result, status = cmd_search(argument)
        elif command == "validate":
            result, status = cmd_validate(argument)
        elif command == "locate":
            result, status = locate()
        else:
            result, status = {"error": "usage"}, 2
    except FetchError as error:
        result, status = {"error": error.code}, 1
    except (ValueError, KeyError, IndexError) as error:
        result, status = {"error": "parse", "detail": str(error)[:80]}, 1

    sys.stdout.write(json.dumps(result, ensure_ascii=False))
    sys.stdout.write("\n")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv))
