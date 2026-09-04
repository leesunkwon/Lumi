package com.kotlinsun.lumiandroid.service

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import androidx.core.content.ContextCompat
import com.kotlinsun.lumiandroid.data.MemoryLocation
import java.util.Locale
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine

class LocationService(private val context: Context) {
    fun hasPermission(): Boolean = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    suspend fun currentLocation(): MemoryLocation = suspendCancellableCoroutine { continuation ->
        if (!hasPermission()) {
            continuation.resumeWithException(LocationServiceException("위치 권한이 필요해요."))
            return@suspendCancellableCoroutine
        }
        val manager = context.getSystemService(LocationManager::class.java)
        val provider = when {
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> null
        }
        if (provider == null) {
            continuation.resumeWithException(LocationServiceException("위치 서비스를 켜주세요."))
            return@suspendCancellableCoroutine
        }
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                manager.removeUpdates(this)
                continuation.resume(location.toMemoryLocation())
            }
        }
        continuation.invokeOnCancellation { manager.removeUpdates(listener) }
        manager.getLastKnownLocation(provider)?.let {
            continuation.resume(it.toMemoryLocation())
            return@suspendCancellableCoroutine
        }
        manager.requestSingleUpdate(provider, listener, null)
    }

    private fun Location.toMemoryLocation(): MemoryLocation {
        val address = runCatching {
            Geocoder(context, Locale.KOREA).getFromLocation(latitude, longitude, 1)?.firstOrNull()?.getAddressLine(0)
        }.getOrNull()
        return MemoryLocation(latitude, longitude, address)
    }
}

class LocationServiceException(message: String) : IllegalStateException(message)
