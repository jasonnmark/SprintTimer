import Foundation
import CoreLocation

struct WeatherData {
    let temperature: Double       // Celsius
    let feelsLike: Double         // Celsius
    let humidity: Double          // Percentage
    let pressure: Double          // hPa
    let windSpeed: Double         // m/s
    let windDirection: Double     // degrees
    let visibility: Double        // meters
    let uvIndex: Int
    let dewPoint: Double          // Celsius
    let weatherCondition: String  // e.g. "Clear", "Rain", "Clouds"
}

struct AQIData {
    let aqi: Int // 1-5 scale (1=Good, 5=Very Poor)
}

class WeatherService {
    static let shared = WeatherService()

    private let defaults = UserDefaults(suiteName: "group.com.JasonMark.SprintTimer")
    private let apiKeyKey = "settings.openWeatherAPIKey"

    var apiKey: String {
        get { defaults?.string(forKey: apiKeyKey) ?? "" }
        set {
            defaults?.set(newValue, forKey: apiKeyKey)
            defaults?.synchronize()
        }
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func fetchWeather(for location: CLLocation) async -> WeatherData? {
        guard hasAPIKey else { return nil }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let urlString = "https://api.openweathermap.org/data/3.0/onecall?lat=\(lat)&lon=\(lon)&units=metric&exclude=minutely,hourly,daily,alerts&appid=\(apiKey)"

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("Weather API error: bad status code")
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any] else {
                return nil
            }

            let temp = current["temp"] as? Double ?? 0
            let feelsLike = current["feels_like"] as? Double ?? 0
            let humidity = current["humidity"] as? Double ?? 0
            let pressure = current["pressure"] as? Double ?? 0
            let windSpeed = current["wind_speed"] as? Double ?? 0
            let windDir = current["wind_deg"] as? Double ?? 0
            let visibility = current["visibility"] as? Double ?? 0
            let uvi = current["uvi"] as? Double ?? 0
            let dewPoint = current["dew_point"] as? Double ?? 0

            var condition = "Unknown"
            if let weatherArray = current["weather"] as? [[String: Any]],
               let first = weatherArray.first,
               let main = first["main"] as? String {
                condition = main
            }

            return WeatherData(
                temperature: temp,
                feelsLike: feelsLike,
                humidity: humidity,
                pressure: pressure,
                windSpeed: windSpeed,
                windDirection: windDir,
                visibility: visibility,
                uvIndex: Int(uvi),
                dewPoint: dewPoint,
                weatherCondition: condition
            )
        } catch {
            print("Weather fetch error: \(error)")
            return nil
        }
    }

    func fetchAQI(for location: CLLocation) async -> AQIData? {
        guard hasAPIKey else { return nil }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let urlString = "https://api.openweathermap.org/data/2.5/air_pollution?lat=\(lat)&lon=\(lon)&appid=\(apiKey)"

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["list"] as? [[String: Any]],
                  let first = list.first,
                  let main = first["main"] as? [String: Any],
                  let aqi = main["aqi"] as? Int else {
                return nil
            }

            return AQIData(aqi: aqi)
        } catch {
            print("AQI fetch error: \(error)")
            return nil
        }
    }
}
