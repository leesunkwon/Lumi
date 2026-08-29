//
//  WeatherService.swift
//  MetaGemini
//

import CoreLocation
import Foundation

enum WeatherServiceError: LocalizedError {
    case missingAPIKey
    case locationServicesDisabled
    case locationPermissionDenied
    case locationUnavailable
    case invalidResponse
    case serviceError(String)
    case forecastUnavailable

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "기상청 API 키가 없습니다. Secrets.xcconfig에 KMA_WEATHER_API_KEY를 설정해주세요."
        case .locationServicesDisabled:
            return "날씨를 확인하려면 iPhone의 위치 서비스를 켜주세요."
        case .locationPermissionDenied:
            return "현재 위치를 사용하려면 Lumi의 위치 접근을 허용해주세요."
        case .locationUnavailable:
            return "현재 위치를 가져오지 못했어요. 잠시 후 다시 시도해 주세요."
        case .invalidResponse:
            return "기상청 날씨 정보를 읽지 못했어요."
        case .serviceError(let message):
            return "기상청 날씨 조회에 실패했습니다: \(message)"
        case .forecastUnavailable:
            return "요청한 시간대의 예보가 아직 준비되지 않았어요."
        }
    }
}

enum WeatherTargetDay: String {
    case today
    case tomorrow

    static func resolved(from rawValue: String?) -> WeatherTargetDay {
        WeatherTargetDay(rawValue: rawValue ?? "") ?? .today
    }
}

enum WeatherTargetPeriod: String {
    case current
    case morning
    case afternoon
    case evening
    case night
    case day

    static func resolved(from rawValue: String?) -> WeatherTargetPeriod {
        WeatherTargetPeriod(rawValue: rawValue ?? "") ?? .day
    }

    var targetHour: Int? {
        switch self {
        case .current, .day:
            return nil
        case .morning:
            return 9
        case .afternoon:
            return 15
        case .evening:
            return 19
        case .night:
            return 22
        }
    }

    var title: String {
        switch self {
        case .current:
            return "지금"
        case .morning:
            return "오전"
        case .afternoon:
            return "오후"
        case .evening:
            return "저녁"
        case .night:
            return "밤"
        case .day:
            return "하루"
        }
    }
}

struct WeatherRequest: Decodable {
    let day: WeatherTargetDay
    let period: WeatherTargetPeriod

    init(day: WeatherTargetDay = .today, period: WeatherTargetPeriod = .day) {
        self.day = day
        self.period = period
    }

    private enum CodingKeys: String, CodingKey {
        case day
        case period
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = WeatherTargetDay.resolved(
            from: try container.decodeIfPresent(String.self, forKey: .day)
        )
        period = WeatherTargetPeriod.resolved(
            from: try container.decodeIfPresent(String.self, forKey: .period)
        )
    }
}

@MainActor
final class WeatherService {
    private let locationProvider = CurrentLocationProvider()
    private let serviceBaseURL = "https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0"

    func weatherAnswer(for request: WeatherRequest, now: Date = .now) async throws -> String {
        let location = try await locationProvider.currentLocation()
        let grid = KMAForecastGrid(location.coordinate)

        if request.period == .current {
            do {
                let observations = try await fetchObservations(grid: grid, now: now)
                return currentWeatherAnswer(from: observations)
            } catch WeatherServiceError.forecastUnavailable {
                let forecasts = try await fetchShortForecast(grid: grid, now: now)
                return try currentForecastAnswer(from: forecasts, now: now)
            }
        }

        let items = try await fetchShortForecast(grid: grid, now: now)
        return try forecastAnswer(from: items, request: request, now: now)
    }

    private func fetchObservations(grid: KMAForecastGrid, now: Date) async throws -> [KMAWeatherItem] {
        var lastError: Error?

        for offset in stride(from: 45, through: 165, by: 60) {
            let base = latestObservationBase(for: now.addingTimeInterval(-Double(offset - 45) * 60))
            do {
                return try await fetch(
                    endpoint: "getUltraSrtNcst",
                    baseDate: base.date,
                    baseTime: base.time,
                    grid: grid,
                    numberOfRows: 60
                )
            } catch WeatherServiceError.forecastUnavailable {
                lastError = WeatherServiceError.forecastUnavailable
            }
        }

        throw lastError ?? WeatherServiceError.forecastUnavailable
    }

    private func fetchShortForecast(grid: KMAForecastGrid, now: Date) async throws -> [KMAWeatherItem] {
        var lastError: Error?

        for offset in stride(from: 0, through: 21, by: 3) {
            let baseDate = now.addingTimeInterval(-Double(offset) * 60 * 60)
            let base = latestShortForecastBase(for: baseDate)
            do {
                return try await fetch(
                    endpoint: "getVilageFcst",
                    baseDate: base.date,
                    baseTime: base.time,
                    grid: grid,
                    numberOfRows: 1_000
                )
            } catch WeatherServiceError.forecastUnavailable {
                lastError = WeatherServiceError.forecastUnavailable
            }
        }

        throw lastError ?? WeatherServiceError.forecastUnavailable
    }

    private func fetch(
        endpoint: String,
        baseDate: String,
        baseTime: String,
        grid: KMAForecastGrid,
        numberOfRows: Int
    ) async throws -> [KMAWeatherItem] {
        let apiKey = try requireAPIKey()

        guard var components = URLComponents(string: "\(serviceBaseURL)/\(endpoint)") else {
            throw WeatherServiceError.invalidResponse
        }
        let queryItems = [
            ("serviceKey", apiKey),
            ("numOfRows", String(numberOfRows)),
            ("pageNo", "1"),
            ("dataType", "JSON"),
            ("base_date", baseDate),
            ("base_time", baseTime),
            ("nx", String(grid.x)),
            ("ny", String(grid.y))
        ]
        components.percentEncodedQuery = queryItems
            .map { "\($0.0)=\(percentEncodedQueryValue($0.1))" }
            .joined(separator: "&")

        guard let url = components.url else {
            throw WeatherServiceError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeatherServiceError.invalidResponse
        }

        let decodedResponse = try? JSONDecoder().decode(KMAWeatherResponse.self, from: data)
        guard (200...299).contains(httpResponse.statusCode) else {
            throw WeatherServiceError.serviceError(
                decodedResponse?.response.header.resultMsg ?? "HTTP \(httpResponse.statusCode)"
            )
        }
        guard let decodedResponse else {
            throw WeatherServiceError.invalidResponse
        }
        if decodedResponse.response.header.resultMsg == "NO_DATA" {
            throw WeatherServiceError.forecastUnavailable
        }
        guard decodedResponse.response.header.resultCode == "00" else {
            throw WeatherServiceError.serviceError(decodedResponse.response.header.resultMsg ?? "알 수 없는 오류")
        }

        let items = decodedResponse.response.body?.items?.item ?? []
        guard !items.isEmpty else {
            throw WeatherServiceError.forecastUnavailable
        }
        return items
    }

    private func currentWeatherAnswer(from items: [KMAWeatherItem]) -> String {
        let values = Dictionary(
            uniqueKeysWithValues: items.compactMap { item in
                item.observedValue.map { (item.category, $0) }
            }
        )
        let temperature = values["T1H"].flatMap(temperatureText)
        let precipitation = precipitationDescription(values["PTY"])
        let rainAmount = values["RN1"].flatMap(rainAmountText)
        let humidity = values["REH"].flatMap { numericText($0, suffix: "%") }

        var details = [String]()
        if let temperature {
            details.append("기온은 \(temperature)")
        }
        if let precipitation {
            details.append(precipitation)
        }
        if let rainAmount, rainAmount != "강수 없음" {
            details.append("한 시간 강수량은 \(rainAmount)")
        }
        if let humidity {
            details.append("습도는 \(humidity)")
        }

        let summary = details.isEmpty ? "실황 정보를 확인했어요" : details.joined(separator: ", ")
        return "현재 위치 기준 지금은 \(summary)예요."
    }

    private func forecastAnswer(
        from items: [KMAWeatherItem],
        request: WeatherRequest,
        now: Date
    ) throws -> String {
        let targetDate = weatherDate(for: request.day, now: now)
        let dateKey = dateString(targetDate)
        let dayItems = items.filter { $0.forecastDate == dateKey }
        guard !dayItems.isEmpty else {
            throw WeatherServiceError.forecastUnavailable
        }

        if request.period == .day {
            return dailyForecastAnswer(from: dayItems, day: request.day)
        }

        guard let targetHour = request.period.targetHour,
              let values = forecastValues(near: targetHour, in: dayItems)
        else {
            throw WeatherServiceError.forecastUnavailable
        }

        return periodForecastAnswer(values: values, day: request.day, period: request.period)
    }

    private func currentForecastAnswer(from items: [KMAWeatherItem], now: Date) throws -> String {
        let dateKey = dateString(now)
        let dayItems = items.filter { $0.forecastDate == dateKey }
        let currentHour = koreanCalendar.component(.hour, from: now)

        guard let values = forecastValues(near: currentHour, in: dayItems) else {
            throw WeatherServiceError.forecastUnavailable
        }

        let condition = precipitationDescription(values["PTY"]) ?? skyDescription(values["SKY"])
        let temperature = values["TMP"].flatMap(temperatureText)
        let rainChance = values["POP"]
            .flatMap(Double.init)
            .map { Int($0.rounded()) }

        var details = [String]()
        if let condition {
            details.append(condition)
        }
        if let temperature {
            details.append("기온은 \(temperature)")
        }
        if let rainChance {
            details.append("비가 올 확률은 \(rainChance)퍼센트")
        }

        let summary = details.isEmpty ? "예보를 확인했어요" : details.joined(separator: ", ")
        return "현재 위치 기준 지금은 \(summary)예요."
    }

    private func dailyForecastAnswer(from items: [KMAWeatherItem], day: WeatherTargetDay) -> String {
        let values = valuesByCategory(in: items)
        let lowest = values["TMN"]?.first.flatMap(temperatureText)
        let highest = values["TMX"]?.first.flatMap(temperatureText)
        let maximumRainChance = values["POP"]?
            .compactMap(Double.init)
            .max()
            .map { Int($0.rounded()) }
        let precipitation = values["PTY"]?
            .compactMap(precipitationDescription)
            .first(where: { $0 != "강수 없음" })
        let sky = values["SKY"]?
            .compactMap(skyDescription)
            .first

        var details = [String]()
        if let lowest, let highest {
            details.append("최저 \(lowest), 최고 \(highest)")
        } else if let highest {
            details.append("최고 \(highest)")
        } else if let lowest {
            details.append("최저 \(lowest)")
        }
        if let precipitation {
            details.append(precipitation)
        } else if let sky {
            details.append(sky)
        }
        if let maximumRainChance {
            details.append("비가 올 확률은 최대 \(maximumRainChance)퍼센트")
        }

        let dateTitle = day == .today ? "오늘" : "내일"
        guard !details.isEmpty else {
            return "현재 위치 기준 \(dateTitle) 예보를 확인했어요."
        }
        return "현재 위치 기준 \(dateTitle)은 \(details.joined(separator: ", "))예요."
    }

    private func periodForecastAnswer(
        values: [String: String],
        day: WeatherTargetDay,
        period: WeatherTargetPeriod
    ) -> String {
        let dateTitle = day == .today ? "오늘" : "내일"
        let condition = precipitationDescription(values["PTY"]) ?? skyDescription(values["SKY"])
        let temperature = values["TMP"].flatMap(temperatureText)
        let rainChance = values["POP"]
            .flatMap(Double.init)
            .map { Int($0.rounded()) }

        var details = [String]()
        if let condition {
            details.append(condition)
        }
        if let temperature {
            details.append("기온은 \(temperature)")
        }
        if let rainChance {
            details.append("비가 올 확률은 \(rainChance)퍼센트")
        }

        let summary = details.isEmpty ? "예보를 확인했어요" : details.joined(separator: ", ")
        return "현재 위치 기준 \(dateTitle) \(period.title)에는 \(summary)예요."
    }

    private func forecastValues(near targetHour: Int, in items: [KMAWeatherItem]) -> [String: String]? {
        let groupedByTime = Dictionary(grouping: items) { $0.forecastTime ?? "" }
        let nearestCandidate = groupedByTime.keys
            .compactMap { time -> (String, Int)? in
                guard let hour = hour(from: time) else { return nil }
                return (time, hour)
            }
            .min { abs($0.1 - targetHour) < abs($1.1 - targetHour) }
        let nearestTime = nearestCandidate.map { $0.0 }

        guard let nearestTime,
              let matchingItems = groupedByTime[nearestTime]
        else {
            return nil
        }
        return Dictionary(
            uniqueKeysWithValues: matchingItems.compactMap { item in
                item.forecastValue.map { (item.category, $0) }
            }
        )
    }

    private func valuesByCategory(in items: [KMAWeatherItem]) -> [String: [String]] {
        Dictionary(grouping: items.compactMap { item -> (String, String)? in
            guard let value = item.forecastValue else { return nil }
            return (item.category, value)
        }, by: \.0)
        .mapValues { $0.map(\.1) }
    }

    private func precipitationDescription(_ value: String?) -> String? {
        guard let value else { return nil }
        switch value {
        case "0": return "강수 없음"
        case "1": return "비"
        case "2": return "비 또는 눈"
        case "3": return "눈"
        case "4": return "소나기"
        case "5": return "빗방울"
        case "6": return "빗방울과 눈날림"
        case "7": return "눈날림"
        default: return nil
        }
    }

    private func skyDescription(_ value: String?) -> String? {
        guard let value else { return nil }
        switch value {
        case "1": return "맑음"
        case "3": return "구름 많음"
        case "4": return "흐림"
        default: return nil
        }
    }

    private func temperatureText(_ value: String) -> String? {
        numericText(value, suffix: "도")
    }

    private func rainAmountText(_ value: String) -> String? {
        guard value != "0", value != "강수없음" else { return "강수 없음" }
        return value.contains("mm") ? value : "\(value)밀리미터"
    }

    private func numericText(_ value: String, suffix: String) -> String? {
        guard let number = Double(value) else { return nil }
        let rounded = number.rounded()
        let text = number == rounded ? String(Int(rounded)) : String(format: "%.1f", number)
        return "\(text)\(suffix)"
    }

    private func latestObservationBase(for date: Date) -> KMAIssueTime {
        let adjusted = date.addingTimeInterval(-45 * 60)
        return KMAIssueTime(date: adjusted, hour: koreanCalendar.component(.hour, from: adjusted))
    }

    private func latestShortForecastBase(for date: Date) -> KMAIssueTime {
        let adjusted = date.addingTimeInterval(-20 * 60)
        let hour = koreanCalendar.component(.hour, from: adjusted)
        let releaseHours = [2, 5, 8, 11, 14, 17, 20, 23]

        if let releaseHour = releaseHours.last(where: { $0 <= hour }) {
            return KMAIssueTime(date: adjusted, hour: releaseHour)
        }

        guard let previousDay = koreanCalendar.date(byAdding: .day, value: -1, to: adjusted) else {
            return KMAIssueTime(date: adjusted, hour: 23)
        }
        return KMAIssueTime(date: previousDay, hour: 23)
    }

    private func weatherDate(for day: WeatherTargetDay, now: Date) -> Date {
        switch day {
        case .today:
            return now
        case .tomorrow:
            return koreanCalendar.date(byAdding: .day, value: 1, to: now) ?? now
        }
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = koreanCalendar
        formatter.timeZone = koreanTimeZone
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private func hour(from time: String) -> Int? {
        Int(time.prefix(2))
    }

    private func percentEncodedQueryValue(_ value: String) -> String {
        let decodedValue = value.removingPercentEncoding ?? value
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.remove(charactersIn: ":#[]@!$&'()*+,;=/?%")
        return decodedValue.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? decodedValue
    }

    private func requireAPIKey() throws -> String {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "KMAWeatherAPIKey") as? String,
              !apiKey.isEmpty,
              !apiKey.contains("$")
        else {
            throw WeatherServiceError.missingAPIKey
        }
        return apiKey
    }

    private var koreanCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.timeZone = koreanTimeZone
        return calendar
    }

    private var koreanTimeZone: TimeZone {
        TimeZone(identifier: "Asia/Seoul") ?? .current
    }
}

@MainActor
final class CurrentLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentLocation() async throws -> CLLocation {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return try await requestLocation()
        case .notDetermined:
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            throw WeatherServiceError.locationPermissionDenied
        @unknown default:
            throw WeatherServiceError.locationUnavailable
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            resolve(with: .failure(WeatherServiceError.locationPermissionDenied))
        case .notDetermined:
            break
        @unknown default:
            resolve(with: .failure(WeatherServiceError.locationUnavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            resolve(with: .failure(WeatherServiceError.locationUnavailable))
            return
        }
        resolve(with: .success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resolve(with: .failure(WeatherServiceError.locationUnavailable))
    }

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    private func resolve(with result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

private struct KMAForecastGrid {
    let x: Int
    let y: Int

    init(_ coordinate: CLLocationCoordinate2D) {
        let re = 6_371.00877
        let grid = 5.0
        let slat1 = 30.0
        let slat2 = 60.0
        let olon = 126.0
        let olat = 38.0
        let xo = 43.0
        let yo = 136.0
        let pi = Double.pi
        let degrad = pi / 180.0

        let reGrid = re / grid
        let slat1Rad = slat1 * degrad
        let slat2Rad = slat2 * degrad
        let olonRad = olon * degrad
        let olatRad = olat * degrad
        let sn = log(cos(slat1Rad) / cos(slat2Rad)) / log(tan(pi * 0.25 + slat2Rad * 0.5) / tan(pi * 0.25 + slat1Rad * 0.5))
        let sf = pow(tan(pi * 0.25 + slat1Rad * 0.5), sn) * cos(slat1Rad) / sn
        let ro = reGrid * sf / pow(tan(pi * 0.25 + olatRad * 0.5), sn)
        let ra = reGrid * sf / pow(tan(pi * 0.25 + coordinate.latitude * degrad * 0.5), sn)
        var theta = coordinate.longitude * degrad - olonRad

        if theta > pi { theta -= 2.0 * pi }
        if theta < -pi { theta += 2.0 * pi }
        theta *= sn

        x = Int(floor(ra * sin(theta) + xo + 0.5))
        y = Int(floor(ro - ra * cos(theta) + yo + 0.5))
    }
}

private struct KMAIssueTime {
    let date: String
    let time: String

    init(date: Date, hour: Int) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyyMMdd"
        self.date = formatter.string(from: date)
        self.time = String(format: "%02d00", hour)
    }
}

private struct KMAWeatherResponse: Decodable {
    let response: Response

    struct Response: Decodable {
        let header: Header
        let body: Body?
    }

    struct Header: Decodable {
        let resultCode: String
        let resultMsg: String?
    }

    struct Body: Decodable {
        let items: Items?
    }

    struct Items: Decodable {
        let item: [KMAWeatherItem]?
    }
}

private struct KMAWeatherItem: Decodable {
    let category: String
    let forecastDate: String?
    let forecastTime: String?
    let forecastValue: String?
    let observedValue: String?

    enum CodingKeys: String, CodingKey {
        case category
        case forecastDate = "fcstDate"
        case forecastTime = "fcstTime"
        case forecastValue = "fcstValue"
        case observedValue = "obsrValue"
    }
}
