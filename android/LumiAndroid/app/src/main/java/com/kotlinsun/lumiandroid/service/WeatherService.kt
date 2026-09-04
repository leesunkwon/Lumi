package com.kotlinsun.lumiandroid.service

import android.net.Uri
import com.kotlinsun.lumiandroid.BuildConfig
import com.kotlinsun.lumiandroid.data.MemoryLocation
import java.net.HttpURLConnection
import java.net.URL
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.ZoneId
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.tan
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

class WeatherService {
    suspend fun answer(location: MemoryLocation, detail: WeatherDetail?): String = withContext(Dispatchers.IO) {
        val key = BuildConfig.KMA_WEATHER_API_KEY.takeIf(String::isNotBlank)
            ?: throw WeatherServiceException("기상청 API 키가 없습니다. local.properties에 KMA_WEATHER_API_KEY를 설정해주세요.")
        val now = ZonedDateTime.now(KOREA)
        val targetDay = if (detail?.day == "tomorrow") now.plusDays(1) else now
        val grid = KmaGrid(location.latitude, location.longitude)
        val items = fetchForecast(key, grid, latestBase(now))
        val date = targetDay.format(DATE_FORMAT)
        val targetHour = targetHour(detail?.period, now.hour)
        val values = items.filter { it.date == date }
            .groupBy { it.time }
            .minByOrNull { (_, value) -> kotlin.math.abs(value.firstOrNull()?.time?.take(2)?.toIntOrNull()?.minus(targetHour) ?: 24) }
            ?.value
            ?.associate { it.category to it.value }
            .orEmpty()
        if (values.isEmpty()) throw WeatherServiceException("해당 시간대의 예보가 아직 없어요.")

        val dayTitle = if (targetDay.toLocalDate() == now.toLocalDate()) "오늘" else "내일"
        val periodTitle = periodTitle(detail?.period)
        val condition = precipitation(values["PTY"])?.takeUnless { it == "강수 없음" } ?: sky(values["SKY"])
        val temperature = values["TMP"]?.toDoubleOrNull()?.let { if (it % 1.0 == 0.0) "${it.toInt()}도" else "${"%.1f".format(it)}도" }
        val rainChance = values["POP"]?.toDoubleOrNull()?.toInt()
        val details = listOfNotNull(condition, temperature?.let { "기온은 $it" }, rainChance?.let { "비가 올 확률은 $it퍼센트" })
        "현재 위치 기준 $dayTitle $periodTitle ${details.ifEmpty { listOf("예보를 확인했어요") }.joinToString(", ")}예요."
    }

    private fun fetchForecast(key: String, grid: KmaGrid, base: BaseTime): List<ForecastItem> {
        val uri = Uri.parse("https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getVilageFcst")
            .buildUpon()
            .appendQueryParameter("serviceKey", key)
            .appendQueryParameter("numOfRows", "1000")
            .appendQueryParameter("pageNo", "1")
            .appendQueryParameter("dataType", "JSON")
            .appendQueryParameter("base_date", base.date)
            .appendQueryParameter("base_time", base.time)
            .appendQueryParameter("nx", grid.x.toString())
            .appendQueryParameter("ny", grid.y.toString())
            .build()
        val connection = (URL(uri.toString()).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 20_000
        }
        try {
            val text = (if (connection.responseCode in 200..299) connection.inputStream else connection.errorStream)
                ?.bufferedReader()?.use { it.readText() }.orEmpty()
            val root = JSONObject(text).optJSONObject("response") ?: throw WeatherServiceException("날씨 응답 형식이 올바르지 않아요.")
            val header = root.optJSONObject("header")
            if (connection.responseCode !in 200..299 || header?.optString("resultCode") != "00") {
                throw WeatherServiceException(header?.optString("resultMsg").orEmpty().ifBlank { "날씨 정보를 가져오지 못했어요." })
            }
            val items = root.optJSONObject("body")?.optJSONObject("items")?.optJSONArray("item")
                ?: throw WeatherServiceException("날씨 예보가 아직 없어요.")
            return buildList {
                for (index in 0 until items.length()) {
                    val item = items.optJSONObject(index) ?: continue
                    add(ForecastItem(item.optString("category"), item.optString("fcstDate"), item.optString("fcstTime"), item.optString("fcstValue")))
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun latestBase(now: ZonedDateTime): BaseTime {
        val adjusted = now.minusMinutes(20)
        val releaseHour = listOf(2, 5, 8, 11, 14, 17, 20, 23).lastOrNull { it <= adjusted.hour }
        val base = if (releaseHour != null) adjusted else adjusted.minusDays(1)
        return BaseTime(base.format(DATE_FORMAT), "%02d00".format(releaseHour ?: 23))
    }

    private fun targetHour(period: String?, current: Int): Int = when (period) {
        "morning" -> 9
        "afternoon" -> 15
        "evening" -> 19
        "night" -> 22
        else -> current
    }

    private fun periodTitle(period: String?): String = when (period) {
        "morning" -> "오전에는"
        "afternoon" -> "오후에는"
        "evening" -> "저녁에는"
        "night" -> "밤에는"
        else -> "지금은"
    }

    private fun precipitation(value: String?): String? = when (value) {
        "0" -> "강수 없음"
        "1" -> "비"
        "2" -> "비 또는 눈"
        "3" -> "눈"
        "4" -> "소나기"
        else -> null
    }

    private fun sky(value: String?): String? = when (value) {
        "1" -> "맑음"
        "3" -> "구름 많음"
        "4" -> "흐림"
        else -> null
    }

    private data class ForecastItem(val category: String, val date: String, val time: String, val value: String)
    private data class BaseTime(val date: String, val time: String)

    private class KmaGrid(latitude: Double, longitude: Double) {
        val x: Int
        val y: Int

        init {
            val re = 6371.00877 / 5.0
            val pi = Math.PI
            val degrad = pi / 180.0
            val slat1 = 30.0 * degrad
            val slat2 = 60.0 * degrad
            val olon = 126.0 * degrad
            val olat = 38.0 * degrad
            val sn = ln(cos(slat1) / cos(slat2)) / ln(tan(pi * .25 + slat2 * .5) / tan(pi * .25 + slat1 * .5))
            val sf = tan(pi * .25 + slat1 * .5).pow(sn) * cos(slat1) / sn
            val ro = re * sf / tan(pi * .25 + olat * .5).pow(sn)
            val ra = re * sf / tan(pi * .25 + latitude * degrad * .5).pow(sn)
            var theta = longitude * degrad - olon
            if (theta > pi) theta -= 2.0 * pi
            if (theta < -pi) theta += 2.0 * pi
            theta *= sn
            x = floor(ra * sin(theta) + 43.0 + .5).toInt()
            y = floor(ro - ra * cos(theta) + 136.0 + .5).toInt()
        }
    }

    private companion object {
        val KOREA: ZoneId = ZoneId.of("Asia/Seoul")
        val DATE_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyyMMdd")
    }
}

class WeatherServiceException(message: String) : IllegalStateException(message)
