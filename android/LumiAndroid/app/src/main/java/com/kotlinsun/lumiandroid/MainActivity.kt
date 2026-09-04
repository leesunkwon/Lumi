package com.kotlinsun.lumiandroid

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import com.kotlinsun.lumiandroid.databinding.ActivityMainBinding
import com.kotlinsun.lumiandroid.service.GlassesException
import com.kotlinsun.lumiandroid.ui.ConversationsFragment
import com.kotlinsun.lumiandroid.ui.DashboardFragment
import com.kotlinsun.lumiandroid.ui.LumiActionHost
import com.kotlinsun.lumiandroid.ui.LumiViewModel
import com.kotlinsun.lumiandroid.ui.MemoriesFragment
import com.kotlinsun.lumiandroid.ui.SceneMode
import com.kotlinsun.lumiandroid.ui.SchedulesFragment
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.PermissionStatus

class MainActivity : AppCompatActivity(), LumiActionHost {
    private lateinit var binding: ActivityMainBinding
    private val viewModel: LumiViewModel by viewModels()

    private val microphonePermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) viewModel.startRecording()
        else viewModel.reportError(IllegalStateException(getString(R.string.permission_microphone)))
    }
    private val locationPermission = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { grants ->
        if (grants.values.none { it }) viewModel.reportError(IllegalStateException(getString(R.string.permission_location)))
    }
    private val devicePermission = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { grants ->
        if (grants.values.any { !it }) viewModel.reportError(GlassesException("Bluetooth 권한을 허용하면 안경을 연결할 수 있어요."))
    }
    private val wearableCameraPermission = registerForActivityResult(Wearables.RequestPermissionContract()) { result ->
        result.onSuccess { status ->
            if (status == PermissionStatus.Granted) viewModel.captureScenePhoto()
            else viewModel.reportError(GlassesException("Meta AI에서 카메라 권한을 허용해주세요."))
        }.onFailure { error, _ ->
            viewModel.reportError(GlassesException(error.description))
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        binding.navigation.setOnItemSelectedListener { item ->
            showTab(
                when (item.itemId) {
                    R.id.tab_conversations -> ConversationsFragment()
                    R.id.tab_schedules -> SchedulesFragment()
                    R.id.tab_memories -> MemoriesFragment()
                    else -> DashboardFragment()
                },
            )
            true
        }
        if (savedInstanceState == null) binding.navigation.selectedItemId = R.id.tab_dashboard
        requestDevicePermissions()
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.hasExtra(EXTRA_TIMER_ID)) binding.navigation.selectedItemId = R.id.tab_dashboard
    }

    override fun toggleVoiceRecording() {
        if (viewModel.state.value.status.name == "RECORDING") {
            viewModel.stopRecordingAndAsk()
        } else if (hasPermission(Manifest.permission.RECORD_AUDIO)) {
            viewModel.startRecording()
        } else {
            microphonePermission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    override fun connectGlasses() {
        viewModel.glasses.startRegistration(this).onFailure(viewModel::reportError)
    }

    override fun captureScene(mode: SceneMode) {
        viewModel.requestScene(mode)
        launchPendingScene(mode)
    }

    override fun launchPendingScene(mode: SceneMode) {
        if ((mode == SceneMode.SAVE_PLACE || mode == SceneMode.SAVE_PARKING) && !hasLocationPermission()) {
            locationPermission.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
            return
        }
        wearableCameraPermission.launch(Permission.CAMERA)
    }

    private fun requestDevicePermissions() {
        val permissions = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                add(Manifest.permission.BLUETOOTH_CONNECT)
                add(Manifest.permission.BLUETOOTH_SCAN)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) add(Manifest.permission.POST_NOTIFICATIONS)
        }.filterNot(::hasPermission)
        if (permissions.isNotEmpty()) devicePermission.launch(permissions.toTypedArray())
    }

    private fun hasLocationPermission(): Boolean = hasPermission(Manifest.permission.ACCESS_FINE_LOCATION) || hasPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
    private fun hasPermission(permission: String): Boolean = ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    private fun showTab(fragment: Fragment) {
        supportFragmentManager.beginTransaction()
            .replace(R.id.screen_container, fragment)
            .commit()
    }

    companion object {
        const val EXTRA_TIMER_ID = "timer_id"
    }
}
