package com.kotlinsun.lumiandroid.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.fragment.app.activityViewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.kotlinsun.lumiandroid.databinding.FragmentDashboardBinding
import com.kotlinsun.lumiandroid.data.TimerEntity
import kotlinx.coroutines.launch

class DashboardFragment : Fragment() {
    private var _binding: FragmentDashboardBinding? = null
    private val binding get() = requireNotNull(_binding)
    private val viewModel: LumiViewModel by activityViewModels()
    private val host get() = requireActivity() as LumiActionHost
    private var dispatchedSceneMode: SceneMode? = null

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentDashboardBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        binding.settingsButton.setOnClickListener { SettingsDialog().show(parentFragmentManager, "settings") }
        binding.connectGlassesButton.setOnClickListener { host.connectGlasses() }
        binding.sceneButton.setOnClickListener { host.captureScene(SceneMode.DESCRIBE) }
        binding.translateButton.setOnClickListener { host.captureScene(SceneMode.TRANSLATE) }
        binding.placeButton.setOnClickListener { host.captureScene(SceneMode.SAVE_PLACE) }
        binding.parkingButton.setOnClickListener { host.captureScene(SceneMode.SAVE_PARKING) }
        binding.microphoneButton.setOnClickListener { host.toggleVoiceRecording() }
        binding.sendButton.setOnClickListener {
            viewModel.submitText(binding.questionInput.text?.toString().orEmpty())
            binding.questionInput.text?.clear()
        }
        binding.errorText.setOnClickListener { viewModel.dismissError() }
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.state.collect { render(it) }
            }
        }
    }

    private fun render(state: LumiUiState) = with(binding) {
        statusText.text = state.status.label
        microphoneButton.text = if (state.status == AssistantStatus.RECORDING) "녹음 중지하고 질문 보내기" else "음성으로 질문"
        glassesStatusText.text = if (state.pendingSceneMode != null) "안경 카메라를 준비하고 있어요." else "연결하면 장면 촬영을 사용할 수 있어요."
        textInputRow.visibility = if (state.preferences.keyboardInputEnabled) View.VISIBLE else View.GONE
        answerText.text = state.lastAnswer
        answerText.visibility = if (state.lastAnswer.isNullOrBlank()) View.GONE else View.VISIBLE
        errorText.text = state.error
        errorText.visibility = if (state.error.isNullOrBlank()) View.GONE else View.VISIBLE
        renderTimers(state.activeTimers)
        renderSchedules(state.upcomingSchedules)
        if (state.pendingAction != null && parentFragmentManager.findFragmentByTag("confirmation") == null) {
            ConfirmationDialog.show(this@DashboardFragment, actionDescription(state.pendingAction.action))
        }
        val sceneMode = state.pendingSceneMode
        if (sceneMode == null) {
            dispatchedSceneMode = null
        } else if (sceneMode != dispatchedSceneMode) {
            dispatchedSceneMode = sceneMode
            host.launchPendingScene(sceneMode)
        }
    }

    private fun renderTimers(timers: List<TimerEntity>) {
        binding.timerContainer.removeAllViews()
        if (timers.isEmpty()) addSmallText(binding.timerContainer, "진행 중인 타이머가 없어요.")
        timers.forEach { timer ->
            addSmallText(binding.timerContainer, "${timer.title} · ${timer.remainingSeconds() / 60}분 ${timer.remainingSeconds() % 60}초${if (timer.isPaused) " · 일시정지" else ""}")
        }
    }

    private fun renderSchedules(schedules: List<com.kotlinsun.lumiandroid.data.ScheduleEntity>) {
        binding.scheduleContainer.removeAllViews()
        if (schedules.isEmpty()) addSmallText(binding.scheduleContainer, "다가오는 일정이 없어요.")
        schedules.take(3).forEach { addSmallText(binding.scheduleContainer, "${it.title} · ${java.text.DateFormat.getDateTimeInstance().format(java.util.Date(it.scheduledAt))}") }
    }

    private fun addSmallText(container: ViewGroup, text: String) {
        container.addView(TextView(requireContext()).apply { this.text = text; setPadding(8, 10, 8, 10) })
    }

    override fun onDestroyView() { _binding = null; super.onDestroyView() }

    private fun actionDescription(action: com.kotlinsun.lumiandroid.service.AssistantAction): String = when (action) {
        com.kotlinsun.lumiandroid.service.AssistantAction.CREATE_SCHEDULE -> "일정과 로컬 알림을 등록합니다."
        com.kotlinsun.lumiandroid.service.AssistantAction.START_TIMER -> "타이머와 완료 알림을 시작합니다."
        com.kotlinsun.lumiandroid.service.AssistantAction.SAVE_PLACE -> "현재 사진과 위치를 장소 메모리로 저장합니다."
        com.kotlinsun.lumiandroid.service.AssistantAction.SAVE_PARKING -> "현재 사진과 위치를 주차 기억으로 저장합니다."
        com.kotlinsun.lumiandroid.service.AssistantAction.UPDATE_USER_MEMORY -> "선택한 메모리를 수정합니다."
        com.kotlinsun.lumiandroid.service.AssistantAction.DELETE_USER_MEMORY -> "선택한 메모리를 삭제합니다."
        else -> "메모리를 저장합니다."
    }
}

interface LumiActionHost {
    fun toggleVoiceRecording()
    fun connectGlasses()
    fun captureScene(mode: SceneMode)
    fun launchPendingScene(mode: SceneMode)
}
