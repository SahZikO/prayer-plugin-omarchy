.pragma library

var PRAYERS = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]

var NAMES = {
  fajr: { en: "Fajr", ar: "الفجر" },
  sunrise: { en: "Sunrise", ar: "الشروق" },
  dhuhr: { en: "Dhuhr", ar: "الظهر" },
  asr: { en: "Asr", ar: "العصر" },
  maghrib: { en: "Maghrib", ar: "المغرب" },
  isha: { en: "Isha", ar: "العشاء" }
}

var METHODS = {
  MWL:       { name: "Muslim World League", fajr: 18, isha: 17 },
  ISNA:      { name: "ISNA (North America)", fajr: 15, isha: 15 },
  Egypt:     { name: "Egyptian General Authority", fajr: 19.5, isha: 17.5 },
  Makkah:    { name: "Umm al-Qura, Makkah", fajr: 18.5, ishaMinutes: 90 },
  Karachi:   { name: "University of Islamic Sciences, Karachi", fajr: 18, isha: 18 },
  Tehran:    { name: "Institute of Geophysics, Tehran", fajr: 17.7, isha: 14, maghribAngle: 4.5 },
  Morocco:   { name: "Ministry of Habous, Morocco", fajr: 19, isha: 17,
               offsets: { sunrise: -3, dhuhr: 5, maghrib: 5 } },
  Algeria:   { name: "Ministry of Religious Affairs, Algeria", fajr: 18, isha: 17,
               offsets: { sunrise: -3, dhuhr: 2, maghrib: 3 } },
  Tunisia:   { name: "Ministry of Religious Affairs, Tunisia", fajr: 18, isha: 18 },
  Gulf:      { name: "Gulf Region", fajr: 19.5, ishaMinutes: 90 },
  Turkey:    { name: "Diyanet, Turkey", fajr: 18, isha: 17,
               offsets: { sunrise: -7, dhuhr: 5, asr: 4, maghrib: 7 } },
  France:    { name: "UOIF, France", fajr: 12, isha: 12 },
  Singapore: { name: "MUIS / JAKIM (South-East Asia)", fajr: 20, isha: 18 }
}

var METHOD_KEYS = ["Auto", "MWL", "ISNA", "Egypt", "Makkah", "Karachi", "Tehran",
  "Morocco", "Algeria", "Tunisia", "Gulf", "Turkey", "France", "Singapore"]

var COUNTRY_METHODS = {
  MA: "Morocco", DZ: "Algeria", TN: "Tunisia", LY: "Egypt", EG: "Egypt", SD: "Egypt",
  SY: "Egypt", LB: "Egypt", JO: "Egypt", IQ: "Egypt", PS: "Egypt", MY: "Singapore",
  SA: "Makkah", YE: "Makkah", AE: "Gulf", QA: "Gulf", KW: "Gulf", BH: "Gulf", OM: "Gulf",
  TR: "Turkey", PK: "Karachi", IN: "Karachi", BD: "Karachi", AF: "Karachi", IR: "Tehran",
  FR: "France", US: "ISNA", CA: "ISNA", SG: "Singapore", ID: "Singapore", BN: "Singapore"
}

function resolveMethodKey(setting, countryCode) {
  var key = String(setting || "Auto")
  if (METHODS[key]) return key
  var cc = String(countryCode || "").toUpperCase()
  return COUNTRY_METHODS[cc] || "MWL"
}

function dtr(d) { return d * Math.PI / 180 }
function rtd(r) { return r * 180 / Math.PI }
function sin(d) { return Math.sin(dtr(d)) }
function cos(d) { return Math.cos(dtr(d)) }
function tan(d) { return Math.tan(dtr(d)) }
function arcsin(x) { return rtd(Math.asin(x)) }
function arccos(x) { return rtd(Math.acos(x)) }
function arctan2(y, x) { return rtd(Math.atan2(y, x)) }
function arccot(x) { return rtd(Math.atan(1 / x)) }
function fix(a, b) { a = a - b * Math.floor(a / b); return a < 0 ? a + b : a }
function fixAngle(a) { return fix(a, 360) }
function fixHour(a) { return fix(a, 24) }

function julian(year, month, day) {
  if (month <= 2) { year -= 1; month += 12 }
  var A = Math.floor(year / 100)
  var B = 2 - A + Math.floor(A / 4)
  return Math.floor(365.25 * (year + 4716)) + Math.floor(30.6001 * (month + 1)) + day + B - 1524.5
}

function sunPosition(jd) {
  var D = jd - 2451545.0
  var g = fixAngle(357.529 + 0.98560028 * D)
  var q = fixAngle(280.459 + 0.98564736 * D)
  var L = fixAngle(q + 1.915 * sin(g) + 0.020 * sin(2 * g))
  var e = 23.439 - 0.00000036 * D
  var RA = arctan2(cos(e) * sin(L), cos(L)) / 15
  return { declination: arcsin(sin(e) * sin(L)), equation: q / 15 - fixHour(RA) }
}

function computeUtcHours(year, month, day, lat, lng, elevation, method, asrFactor) {
  var jDate = julian(year, month, day) - lng / (15 * 24)

  function midDay(t) {
    var eqt = sunPosition(jDate + t).equation
    return fixHour(12 - eqt)
  }

  function sunAngleTime(angle, t, ccw) {
    var decl = sunPosition(jDate + t).declination
    var noon = midDay(t)
    var T = arccos((-sin(angle) - sin(decl) * sin(lat)) / (cos(decl) * cos(lat))) / 15
    return noon + (ccw ? -T : T)
  }

  function asrTime(factor, t) {
    var decl = sunPosition(jDate + t).declination
    var angle = -arccot(factor + tan(Math.abs(lat - decl)))
    return sunAngleTime(angle, t)
  }

  var riseSet = 0.833 + 0.0347 * Math.sqrt(Math.max(0, elevation || 0))
  var t = { fajr: 5, sunrise: 6, dhuhr: 12, asr: 13, sunset: 18, maghrib: 18, isha: 18 }
  for (var pass = 0; pass < 2; pass++) {
    var p = {}
    for (var k in t) p[k] = t[k] / 24
    t = {
      fajr: sunAngleTime(method.fajr, p.fajr, true),
      sunrise: sunAngleTime(riseSet, p.sunrise, true),
      dhuhr: midDay(p.dhuhr),
      asr: asrTime(asrFactor, p.asr),
      sunset: sunAngleTime(riseSet, p.sunset),
      maghrib: method.maghribAngle ? sunAngleTime(method.maghribAngle, p.maghrib) : sunAngleTime(riseSet, p.maghrib),
      isha: method.ishaMinutes ? 0 : sunAngleTime(method.isha, p.isha)
    }
  }

  if (method.ishaMinutes) t.isha = t.maghrib + method.ishaMinutes / 60

  var night = 24 - t.sunset + t.sunrise
  function portion(angle) { return angle / 60 * night }
  var fajrPortion = portion(method.fajr)
  if (isNaN(t.fajr) || (t.sunrise - t.fajr) > fajrPortion) t.fajr = t.sunrise - fajrPortion
  if (!method.ishaMinutes) {
    var ishaPortion = portion(method.isha)
    if (isNaN(t.isha) || (t.isha - t.sunset) > ishaPortion) t.isha = t.sunset + ishaPortion
  }

  var out = {}
  for (var i = 0; i < PRAYERS.length; i++) {
    var name = PRAYERS[i]
    var off = (method.offsets && method.offsets[name]) || 0
    out[name] = t[name] - lng / 15 + off / 60
  }
  return out
}

function schedule(opts) {
  var method = METHODS[opts.methodKey] || METHODS.MWL
  var asrFactor = opts.asr === "Hanafi" ? 2 : 1
  var hours = computeUtcHours(opts.year, opts.month, opts.day, opts.latitude, opts.longitude,
    opts.elevation || 0, method, asrFactor)
  var base = Date.UTC(opts.year, opts.month - 1, opts.day)
  var extra = opts.extraOffsets || {}
  var list = []
  for (var i = 0; i < PRAYERS.length; i++) {
    var key = PRAYERS[i]
    var h = hours[key]
    if (isNaN(h)) { list.push({ key: key, epoch: NaN }); continue }
    var ms = base + h * 3600000 + (parseInt(extra[key], 10) || 0) * 60000
    ms = Math.round(ms / 60000) * 60000
    list.push({ key: key, epoch: ms })
  }
  return list
}

function formatClock(epoch, offsetMinutes, use12h) {
  if (isNaN(epoch)) return "--:--"
  var d = new Date(epoch + offsetMinutes * 60000)
  var h = d.getUTCHours(), m = d.getUTCMinutes()
  var mm = (m < 10 ? "0" : "") + m
  if (use12h) {
    var suffix = h >= 12 ? "PM" : "AM"
    var h12 = h % 12 === 0 ? 12 : h % 12
    return h12 + ":" + mm + " " + suffix
  }
  return (h < 10 ? "0" : "") + h + ":" + mm
}

function formatCountdown(ms) {
  if (!(ms > 0)) return "now"
  var totalMin = Math.ceil(ms / 60000)
  var h = Math.floor(totalMin / 60), m = totalMin % 60
  if (h === 0) return m + "m"
  return h + "h " + (m < 10 ? "0" : "") + m + "m"
}

function nextPrayer(today, tomorrowFajr, now) {
  for (var i = 0; i < today.length; i++) {
    var p = today[i]
    if (p.key === "sunrise" || isNaN(p.epoch)) continue
    if (p.epoch > now) return p
  }
  return tomorrowFajr && !isNaN(tomorrowFajr.epoch) ? tomorrowFajr : null
}

function currentIndex(today, now) {
  var idx = -1
  for (var i = 0; i < today.length; i++) {
    if (!isNaN(today[i].epoch) && today[i].epoch <= now) idx = i
  }
  return idx
}

function parseOffset(text) {
  var m = /([+-])(\d\d):?(\d\d)/.exec(String(text || ""))
  if (!m) return null
  var v = parseInt(m[2], 10) * 60 + parseInt(m[3], 10)
  return m[1] === "-" ? -v : v
}

function validZone(zone) {
  return /^[A-Za-z_]+(\/[A-Za-z0-9_+\-]+){0,2}$/.test(String(zone || "")) && String(zone).length < 64
}

function clampString(s, n) {
  s = String(s === undefined || s === null ? "" : s).replace(/[\u0000-\u001f]/g, "")
  return s.length > n ? s.slice(0, n) : s
}

function validCoord(lat, lng) {
  var a = parseFloat(lat), b = parseFloat(lng)
  return !isNaN(a) && !isNaN(b) && a >= -90 && a <= 90 && b >= -180 && b <= 180
}

function normaliseLocation(obj, source) {
  if (!obj || !validCoord(obj.latitude, obj.longitude)) return null
  return {
    name: clampString(obj.name, 80),
    region: clampString(obj.region || obj.description || "", 120),
    latitude: parseFloat(obj.latitude),
    longitude: parseFloat(obj.longitude),
    elevation: isNaN(parseFloat(obj.elevation)) ? 0 : Math.max(0, Math.min(9000, parseFloat(obj.elevation))),
    country: clampString(obj.country || obj.country_code || "", 2).toUpperCase(),
    timezone: validZone(obj.timezone) ? String(obj.timezone) : "",
    source: clampString(source || obj.source || "", 12)
  }
}

function parseState(text) {
  try {
    var data = JSON.parse(String(text || "{}"))
    if (data.mode !== "manual") return { mode: "auto", location: null }
    return { mode: "manual", location: normaliseLocation(data.location, "manual") }
  } catch (e) {
    return { mode: "auto", location: null }
  }
}

function parseGeocodingResults(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var results = data.results || []
    var out = []
    for (var i = 0; i < results.length && out.length < 6; i++) {
      var r = results[i]
      var loc = normaliseLocation({
        name: r.name,
        region: [r.admin1, r.country].filter(function(x) { return !!x }).join(", "),
        latitude: r.latitude, longitude: r.longitude, elevation: r.elevation,
        country: r.country_code, timezone: r.timezone
      }, "manual")
      if (loc && loc.name) out.push(loc)
    }
    return out
  } catch (e) {
    return []
  }
}

