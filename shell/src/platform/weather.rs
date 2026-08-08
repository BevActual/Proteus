use std::process::Command;

#[derive(Debug, Clone, Default, PartialEq)]
pub struct WeatherGlance {
    pub enabled: bool,
    pub has_location: bool,
    pub name: String,
    pub temp_label: String,
    pub condition: String,
    pub error: String,
}

/// Thin Open-Meteo glance for the menu-bar weather chip / popover.
pub fn weather_glance() -> WeatherGlance {
    let base = proteus_shell_core::facts::config_base();
    let settings = proteus_shell_core::facts::read_settings(&base);
    let enabled = settings
        .get("weatherEnabled")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    let name = settings
        .get("locationName")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string();
    let lat = settings
        .get("locationLatitude")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);
    let lon = settings
        .get("locationLongitude")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);
    let units = settings
        .get("weatherUnits")
        .and_then(|v| v.as_str())
        .unwrap_or("metric");
    let has_location = lat.abs() > 0.01 || lon.abs() > 0.01 || !name.is_empty();
    if !enabled {
        return WeatherGlance {
            enabled: false,
            has_location,
            name,
            temp_label: "—".into(),
            condition: String::new(),
            error: "Weather muted".into(),
        };
    }
    if !has_location {
        return WeatherGlance {
            enabled: true,
            has_location: false,
            name: String::new(),
            temp_label: "—".into(),
            condition: String::new(),
            error: "Set location in Settings".into(),
        };
    }
    let unit = if units == "imperial" {
        "fahrenheit"
    } else {
        "celsius"
    };
    let url = format!(
        "https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=temperature_2m,weather_code&temperature_unit={unit}"
    );
    let out = Command::new("curl")
        .args(["-fsS", "--max-time", "3", &url])
        .output();
    let Ok(out) = out else {
        return WeatherGlance {
            enabled: true,
            has_location: true,
            name,
            temp_label: "…".into(),
            condition: String::new(),
            error: "Fetch unavailable".into(),
        };
    };
    if !out.status.success() {
        return WeatherGlance {
            enabled: true,
            has_location: true,
            name,
            temp_label: "—".into(),
            condition: String::new(),
            error: "Weather error".into(),
        };
    }
    let raw = String::from_utf8_lossy(&out.stdout);
    let temp = raw
        .find("\"temperature_2m\":")
        .and_then(|i| {
            let rest = &raw[i + "\"temperature_2m\":".len()..];
            rest.split([',', '}'])
                .next()
                .and_then(|s| s.trim().parse::<f64>().ok())
        });
    let code = raw
        .find("\"weather_code\":")
        .and_then(|i| {
            let rest = &raw[i + "\"weather_code\":".len()..];
            rest.split([',', '}'])
                .next()
                .and_then(|s| s.trim().parse::<i32>().ok())
        })
        .unwrap_or(0);
    let condition = weather_code_label(code);
    let temp_label = temp
        .map(|t| format!("{:.0}°", t))
        .unwrap_or_else(|| "—".into());
    WeatherGlance {
        enabled: true,
        has_location: true,
        name,
        temp_label,
        condition,
        error: String::new(),
    }
}

fn weather_code_label(code: i32) -> String {
    match code {
        0 => "Clear".into(),
        1..=3 => "Cloudy".into(),
        45 | 48 => "Fog".into(),
        51..=67 => "Rain".into(),
        71..=77 => "Snow".into(),
        80..=82 => "Showers".into(),
        95..=99 => "Storm".into(),
        _ => "—".into(),
    }
}
