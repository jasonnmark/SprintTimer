import Foundation
import CoreLocation
import Security

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

    private let keychainAccount = "com.JasonMark.SprintTimer.openWeatherAPIKey"

    var apiKey: String {
        get { readKeychain() ?? "" }
        set { saveKeychain(newValue) }
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Keychain

    private func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveKeychain(_ value: String) {
        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    // MARK: - API

    func fetchWeather(for location: CLLocation) async -> WeatherData? {
        guard hasAPIKey else { return nil }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let urlString = "https://api.openweathermap.org/data/3.0/onecall?lat=\(lat)&lon=\(lon)&units=metric&exclude=minutely,hourly,daily,alerts&appid=\(apiKey)"

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
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
            return nil
        }
    }
}
