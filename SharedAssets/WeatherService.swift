import Foundation
import CoreLocation
import Security
import os

private let logger = Logger(subsystem: "com.JasonMark.SprintTimer", category: "WeatherService")

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
        guard hasAPIKey else {
            logger.error("Weather fetch skipped: no API key configured")
            return nil
        }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        // Use free 2.5 API (One Call 3.0 requires paid subscription)
        let urlString = "https://api.openweathermap.org/data/2.5/weather?lat=\(lat)&lon=\(lon)&units=metric&appid=\(apiKey)"
        logger.info("Fetching weather for \(lat), \(lon)")

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                logger.error("Weather API returned \(httpResponse.statusCode): \(body)")
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let main = json["main"] as? [String: Any] else {
                return nil
            }

            let temp = main["temp"] as? Double ?? 0
            let feelsLike = main["feels_like"] as? Double ?? 0
            let humidity = main["humidity"] as? Double ?? 0
            let pressure = main["pressure"] as? Double ?? 0

            let windSpeed = (json["wind"] as? [String: Any])?["speed"] as? Double ?? 0
            let windDir = (json["wind"] as? [String: Any])?["deg"] as? Double ?? 0
            let visibility = json["visibility"] as? Double ?? 0

            var condition = "Unknown"
            if let weatherArray = json["weather"] as? [[String: Any]],
               let first = weatherArray.first,
               let mainCondition = first["main"] as? String {
                condition = mainCondition
            }

            // Free API doesn't include UV index or dew point
            logger.info("Weather fetched: \(condition) \(temp)°C, humidity \(humidity)%")
            return WeatherData(
                temperature: temp,
                feelsLike: feelsLike,
                humidity: humidity,
                pressure: pressure,
                windSpeed: windSpeed,
                windDirection: windDir,
                visibility: visibility,
                uvIndex: 0,
                dewPoint: 0,
                weatherCondition: condition
            )
        } catch {
            logger.error("Weather fetch failed: \(error)")
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
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                logger.error("AQI API returned \(httpResponse.statusCode): \(body)")
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["list"] as? [[String: Any]],
                  let first = list.first,
                  let main = first["main"] as? [String: Any],
                  let aqi = main["aqi"] as? Int else {
                logger.error("AQI response parse failed")
                return nil
            }

            logger.info("AQI fetched: \(aqi)")
            return AQIData(aqi: aqi)
        } catch {
            logger.error("AQI fetch failed: \(error)")
            return nil
        }
    }
}
