package com.kotlinsun.lumiandroid.ui

import android.app.Dialog
import android.graphics.BitmapFactory
import android.os.Bundle
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.AutoCompleteTextView
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.core.os.bundleOf
import androidx.fragment.app.DialogFragment
import androidx.fragment.app.activityViewModels
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.materialswitch.MaterialSwitch
import com.kotlinsun.lumiandroid.data.MemoryCategory
import com.kotlinsun.lumiandroid.data.MemoryEntity
import com.kotlinsun.lumiandroid.data.ResponseTone
import com.kotlinsun.lumiandroid.data.ScheduleEntity
import com.kotlinsun.lumiandroid.data.PhotoStore
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

class ConfirmationDialog : DialogFragment() {
    private val viewModel: LumiViewModel by activityViewModels()

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog = MaterialAlertDialogBuilder(requireContext())
        .setTitle("실행할까요?")
        .setMessage(arguments?.getString("message") ?: "요청한 작업을 실행합니다.")
        .setNegativeButton("취소") { _, _ -> viewModel.clearPendingAction() }
        .setPositiveButton("실행") { _, _ -> viewModel.confirmPendingAction() }
        .create()

    companion object {
        fun show(fragment: androidx.fragment.app.Fragment, message: String) {
            ConfirmationDialog().apply { arguments = bundleOf("message" to message) }
                .show(fragment.parentFragmentManager, "confirmation")
        }
    }
}

class SettingsDialog : DialogFragment() {
    private val viewModel: LumiViewModel by activityViewModels()

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val context = requireContext()
        val state = viewModel.state.value.preferences
        val layout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 16, 48, 0)
        }
        val confirmation = MaterialSwitch(context).apply { text = "실행 전 확인"; isChecked = state.confirmBeforeAction }
        val keyboard = MaterialSwitch(context).apply { text = "키보드 입력 (실험)"; isChecked = state.keyboardInputEnabled }
        val tone = AutoCompleteTextView(context).apply {
            hint = "답변 톤"
            setAdapter(ArrayAdapter(context, android.R.layout.simple_list_item_1, ResponseTone.entries.map(ResponseTone::title)))
            setText(state.responseTone.title, false)
        }
        layout.addView(confirmation)
        layout.addView(keyboard)
        layout.addView(tone)
        return MaterialAlertDialogBuilder(context)
            .setTitle("설정")
            .setView(layout)
            .setNegativeButton("취소", null)
            .setPositiveButton("저장") { _, _ ->
                val selectedTone = ResponseTone.entries.firstOrNull { it.title == tone.text.toString() } ?: state.responseTone
                viewModel.updatePreferences { it.copy(confirmBeforeAction = confirmation.isChecked, keyboardInputEnabled = keyboard.isChecked, responseTone = selectedTone) }
            }.create()
    }
}

class MemoryEditorDialog : DialogFragment() {
    private val viewModel: LumiViewModel by activityViewModels()

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val memory = arguments?.getString("memory_id")?.let { id -> viewModel.state.value.memories.firstOrNull { it.id == id } }
        val context = requireContext()
        val layout = editorLayout(context)
        val title = input(context, "제목", memory?.title.orEmpty())
        val body = input(context, "내용", memory?.body.orEmpty(), true)
        val category = AutoCompleteTextView(context).apply {
            hint = "분류"
            setAdapter(ArrayAdapter(context, android.R.layout.simple_list_item_1, MemoryCategory.entries.map(MemoryCategory::title)))
            setText(memory?.category?.title ?: MemoryCategory.GENERAL.title, false)
        }
        val tags = input(context, "태그 (공백 또는 쉼표로 구분)", memory?.tagsJson?.replace("[", "")?.replace("]", "")?.replace("\"", "") ?: "")
        layout.addView(title); layout.addView(body); layout.addView(category); layout.addView(tags)
        return MaterialAlertDialogBuilder(context)
            .setTitle(if (memory == null) "메모리 추가" else "메모리 수정")
            .setView(layout)
            .setNegativeButton("취소", null)
            .setPositiveButton("저장") { _, _ ->
                val selected = MemoryCategory.entries.firstOrNull { it.title == category.text.toString() } ?: MemoryCategory.GENERAL
                val tagList = tags.text.toString().split(',', ' ', '\n')
                if (memory == null) viewModel.addMemory(title.text.toString(), body.text.toString(), selected)
                else viewModel.updateMemory(memory, title.text.toString(), body.text.toString(), selected, tagList)
            }
            .setNeutralButton(if (memory == null) null else "삭제") { _, _ -> memory?.let(viewModel::deleteMemory) }
            .create()
    }

    companion object {
        fun show(fragment: androidx.fragment.app.Fragment, memory: MemoryEntity? = null) {
            MemoryEditorDialog().apply { arguments = bundleOf("memory_id" to memory?.id) }.show(fragment.parentFragmentManager, "memory_editor")
        }
    }
}

class ScheduleEditorDialog : DialogFragment() {
    private val viewModel: LumiViewModel by activityViewModels()

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val schedule = arguments?.getString("schedule_id")?.let { id -> viewModel.state.value.schedules.firstOrNull { it.id == id } }
        val context = requireContext()
        val layout = editorLayout(context)
        val title = input(context, "일정 제목", schedule?.title.orEmpty())
        val date = input(context, "일시 (yyyy-MM-dd HH:mm)", schedule?.scheduledAt?.let(::formatDate) ?: formatDate(System.currentTimeMillis() + 3_600_000))
        val note = input(context, "메모 (선택)", schedule?.note.orEmpty(), true)
        layout.addView(title); layout.addView(date); layout.addView(note)
        return MaterialAlertDialogBuilder(context)
            .setTitle(if (schedule == null) "일정 추가" else "일정 수정")
            .setView(layout)
            .setNegativeButton("취소", null)
            .setPositiveButton("저장") { _, _ ->
                val instant = runCatching { LocalDateTime.parse(date.text.toString(), FORMAT).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli() }.getOrNull()
                if (instant == null) {
                    viewModel.reportError(IllegalArgumentException("일시를 yyyy-MM-dd HH:mm 형식으로 입력해주세요."))
                } else if (schedule == null) {
                    viewModel.addSchedule(title.text.toString(), instant, note.text.toString())
                } else {
                    viewModel.updateSchedule(schedule, title.text.toString(), instant, note.text.toString())
                }
            }
            .setNeutralButton(if (schedule == null) null else "삭제") { _, _ -> schedule?.let(viewModel::deleteSchedule) }
            .create()
    }

    companion object {
        private val FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
        private fun formatDate(millis: Long): String = FORMAT.format(Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()))
        fun show(fragment: androidx.fragment.app.Fragment, schedule: ScheduleEntity? = null) {
            ScheduleEditorDialog().apply { arguments = bundleOf("schedule_id" to schedule?.id) }.show(fragment.parentFragmentManager, "schedule_editor")
        }
    }
}

class ConversationDialog : DialogFragment() {
    private val viewModel: LumiViewModel by activityViewModels()

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val conversation = arguments?.getString("conversation_id")?.let { id -> viewModel.state.value.conversations.firstOrNull { it.conversation.id == id } }
        val body = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 12, 48, 12)
            conversation?.messages?.forEach { message ->
                addView(TextView(context).apply {
                    text = "${if (message.role.name == "USER") "나" else "Lumi"}: ${message.text}"
                    setPadding(0, 10, 0, 10)
                })
                message.photoFilename?.let { filename ->
                    val file = PhotoStore(context).conversationPhoto(filename)
                    if (file.exists()) addView(ImageView(context).apply {
                        setImageBitmap(BitmapFactory.decodeFile(file.absolutePath))
                        adjustViewBounds = true
                        contentDescription = "대화에 사용한 사진"
                    })
                }
            }
        }
        return MaterialAlertDialogBuilder(requireContext())
            .setTitle(conversation?.conversation?.title ?: "대화")
            .setView(body)
            .setPositiveButton("닫기", null)
            .create()
    }

    companion object {
        fun show(fragment: androidx.fragment.app.Fragment, conversation: ConversationWithMessages) {
            ConversationDialog().apply { arguments = bundleOf("conversation_id" to conversation.conversation.id) }.show(fragment.parentFragmentManager, "conversation")
        }
    }
}

private fun editorLayout(context: android.content.Context) = LinearLayout(context).apply {
    orientation = LinearLayout.VERTICAL
    setPadding(48, 8, 48, 0)
}

private fun input(context: android.content.Context, hint: String, value: String, multiline: Boolean = false): EditText = EditText(context).apply {
    this.hint = hint
    setText(value)
    minLines = if (multiline) 3 else 1
    maxLines = if (multiline) 5 else 1
    layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
}
