// Pure helpers for Spotlight calc + light unit conversion.
.pragma library

function stripSpaces(s) {
  return String(s || "").replace(/\s+/g, " ").trim()
}

function tryMath(expr) {
  const raw = stripSpaces(expr)
  if (!raw.length || raw.length > 80)
    return null
  // Digits, ops, parens, decimal, percent, caret→**
  if (!/^[\d+\-*/().%\s^]+$/.test(raw))
    return null
  if (!/\d/.test(raw))
    return null
  let e = raw.replace(/\^/g, "**").replace(/%/g, "*0.01")
  // Disallow empty operator runs / leading ops beyond minus
  try {
    const v = Function('"use strict"; return (' + e + ")")()
    if (typeof v !== "number" || !isFinite(v))
      return null
    const rounded = Math.abs(v) >= 1e10 || (Math.abs(v) > 0 && Math.abs(v) < 1e-6)
      ? v.toExponential(6)
      : (Math.round(v * 1e10) / 1e10)
    return {
      expression: raw,
      value: rounded,
      display: String(rounded)
    }
  } catch (err) {
    return null
  }
}

const lengthToM = {
  m: 1,
  meter: 1,
  meters: 1,
  km: 1000,
  kilometer: 1000,
  kilometers: 1000,
  cm: 0.01,
  mm: 0.001,
  mi: 1609.344,
  mile: 1609.344,
  miles: 1609.344,
  ft: 0.3048,
  foot: 0.3048,
  feet: 0.3048,
  in: 0.0254,
  inch: 0.0254,
  inches: 0.0254,
  yd: 0.9144,
  yard: 0.9144,
  yards: 0.9144
}

const massToKg = {
  kg: 1,
  kilogram: 1,
  kilograms: 1,
  g: 0.001,
  gram: 0.001,
  grams: 0.001,
  lb: 0.45359237,
  lbs: 0.45359237,
  pound: 0.45359237,
  pounds: 0.45359237,
  oz: 0.028349523125,
  ounce: 0.028349523125,
  ounces: 0.028349523125
}

function convertTemp(value, from, to) {
  const f = String(from).toLowerCase()
  const t = String(to).toLowerCase()
  let c = value
  if (f === "f" || f === "fahrenheit")
    c = (value - 32) * 5 / 9
  else if (f === "k" || f === "kelvin")
    c = value - 273.15
  else if (f !== "c" && f !== "celsius")
    return null
  if (t === "f" || t === "fahrenheit")
    return c * 9 / 5 + 32
  if (t === "k" || t === "kelvin")
    return c + 273.15
  if (t === "c" || t === "celsius")
    return c
  return null
}

function tryConvert(expr) {
  const raw = stripSpaces(expr).toLowerCase()
  // "32 f to c" / "10 km in miles" / "5kg to lb"
  let m = raw.match(/^(-?\d+(?:\.\d+)?)\s*([a-z]+)\s+(?:to|in|as)\s+([a-z]+)$/)
  if (!m)
    m = raw.match(/^(-?\d+(?:\.\d+)?)([a-z]+)\s+(?:to|in|as)\s+([a-z]+)$/)
  if (!m)
    return null
  const value = Number(m[1])
  const from = m[2]
  const to = m[3]
  if (!isFinite(value))
    return null

  const temp = convertTemp(value, from, to)
  if (temp !== null && isFinite(temp)) {
    const out = Math.round(temp * 1000) / 1000
    return {
      expression: stripSpaces(expr),
      value: out,
      display: out + " " + to
    }
  }

  if (lengthToM[from] && lengthToM[to]) {
    const meters = value * lengthToM[from]
    const out = Math.round((meters / lengthToM[to]) * 1e6) / 1e6
    return {
      expression: stripSpaces(expr),
      value: out,
      display: out + " " + to
    }
  }

  if (massToKg[from] && massToKg[to]) {
    const kg = value * massToKg[from]
    const out = Math.round((kg / massToKg[to]) * 1e6) / 1e6
    return {
      expression: stripSpaces(expr),
      value: out,
      display: out + " " + to
    }
  }

  return null
}

function tryCalc(expr) {
  const conv = tryConvert(expr)
  if (conv) {
    conv.kind = "convert"
    return conv
  }
  const math = tryMath(expr)
  if (math) {
    math.kind = "math"
    return math
  }
  return null
}

// True when the query looks like calc/convert but may still fail to evaluate.
function looksLikeCalc(expr) {
  const raw = stripSpaces(expr)
  if (!raw.length || raw.length > 80)
    return false
  if (!/\d/.test(raw))
    return false
  if (/^(?:to|in|as)\b/i.test(raw))
    return false
  // Unit convert shape: "32 f to c" / "10km in miles"
  if (/^-?\d+(?:\.\d+)?\s*[a-z]+\s+(?:to|in|as)\s+[a-z]+$/i.test(raw))
    return true
  if (/^-?\d+(?:\.\d+)?[a-z]+\s+(?:to|in|as)\s+[a-z]+$/i.test(raw))
    return true
  // Math shape: digits + operators (not a plain integer/decimal alone)
  if (/^[\d+\-*/().%\s^]+$/.test(raw) && /[+\-*/^%]/.test(raw))
    return true
  return false
}
