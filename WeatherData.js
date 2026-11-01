.pragma library

// Plain data helpers for the Яндекс Погода widget: turning the numbers the
// fetcher prints into the short strings the bar and the panel show. Nothing
// here touches the network or the shell, and no wording lives here — the
// panel supplies it through Commons.I18n, which follows the desktop language.

// "+8°", "0°", "−3°" — the degree sign is always there, the plus only above zero.
function formatTemp(value) {
  var n = Number(value)
  if (value === null || value === undefined || !isFinite(n)) return "—"
  n = Math.round(n)
  return (n > 0 ? "+" + n : String(n)) + "°"
}

// A speed as it is written in the interface: "9", "1,3". Rounded to one
// decimal above a whole number, and to a whole number once it is 10 or more.
function formatNumber(value) {
  var n = Number(value)
  if (value === null || value === undefined || !isFinite(n)) return ""
  if (n >= 10) return String(Math.round(n))
  return String(Math.round(n * 10) / 10).replace(".", ",")
}

// The first word group of a day heading: "Сегодня, 1 ноября" ->
// { lead: "Сегодня", rest: "1 ноября" }. A translated heading without a comma
// keeps all of it as the lead.
function splitTitle(title) {
  var text = String(title || "")
  var comma = text.indexOf(",")
  if (comma < 0) return { lead: text, rest: "" }
  return { lead: text.slice(0, comma).trim(), rest: text.slice(comma + 1).trim() }
}

// Which part of a day is nearest to now.
function partForHour(hour) {
  if (hour >= 6 && hour < 12) return "m"
  if (hour >= 12 && hour < 18) return "d"
  if (hour >= 18 && hour < 23) return "e"
  return "n"
}

// The reading a day's row shows: daytime whenever there is one, so the
// figure beside a day is the one people compare days by.
function representativePart(day) {
  if (!day || !day.parts) return null
  if (day.parts.d) return day.parts.d
  for (var key in day.parts) return day.parts[key]
  return null
}

// The coldest and warmest figures of a day, across the parts that have one.
function dayRange(day) {
  var low = null
  var high = null
  if (!day || !day.parts) return { low: null, high: null }
  for (var key in day.parts) {
    var temp = day.parts[key].temp
    if (temp === null || temp === undefined) continue
    if (low === null || temp < low) low = temp
    if (high === null || temp > high) high = temp
  }
  return { low: low, high: high }
}

// Whole minutes between a unix timestamp and now; -1 when there is no reading.
function minutesSince(then, now) {
  var t = Number(then)
  if (!isFinite(t) || t <= 0) return -1
  return Math.floor(Math.max(0, Number(now) - t) / 60)
}

// When the reading came in, in the caller's own words: the catalog's minute,
// hour and "just now" strings, with %1 filled by the count.
function fetchedAgo(then, now, justNow, minutesText, hoursText) {
  var minutes = minutesSince(then, now)
  if (minutes < 0) return ""
  if (minutes < 1) return justNow
  if (minutes < 60) return String(minutesText).replace("%1", String(minutes))
  return String(hoursText).replace("%1", String(Math.floor(minutes / 60)))
}
