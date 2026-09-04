package com.kotlinsun.lumiandroid.ui

import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import androidx.fragment.app.Fragment
import androidx.fragment.app.activityViewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.kotlinsun.lumiandroid.data.MemoryEntity
import com.kotlinsun.lumiandroid.data.PhotoStore
import com.kotlinsun.lumiandroid.databinding.FragmentListBinding
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.launch

class MemoriesFragment : Fragment() {
    private var _binding: FragmentListBinding? = null
    private val binding get() = requireNotNull(_binding)
    private val viewModel: LumiViewModel by activityViewModels()
    private val adapter = LumiRowAdapter<MemoryEntity>(::showMemoryActions)

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentListBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        binding.titleText.text = "메모리"
        binding.addButton.text = "메모 추가"
        binding.emptyText.text = "기억해둘 정보가 없어요.\n“기억해줘”라고 말하거나 직접 추가할 수 있어요."
        binding.list.layoutManager = LinearLayoutManager(requireContext())
        binding.list.adapter = adapter
        binding.addButton.setOnClickListener { MemoryEditorDialog.show(this) }
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.state.collect { state ->
                    adapter.submit(state.memories.map { memory ->
                        val place = memory.location?.displayName?.let { " · $it" }.orEmpty()
                        LumiRow(memory, "${memory.category.title} · ${memory.title}", "${memory.body}\n${DateFormat.getDateInstance().format(Date(memory.createdAt))}$place")
                    })
                    binding.emptyText.visibility = if (state.memories.isEmpty()) View.VISIBLE else View.GONE
                }
            }
        }
    }

    private fun showMemoryActions(memory: MemoryEntity) {
        val actions = buildList {
            add("수정")
            if (memory.photoFilename != null) add("사진 보기")
            if (memory.location != null) add("지도에서 열기")
            add("삭제")
        }
        MaterialAlertDialogBuilder(requireContext())
            .setTitle(memory.title)
            .setItems(actions.toTypedArray()) { _, selected ->
                when (actions[selected]) {
                    "수정" -> MemoryEditorDialog.show(this, memory)
                    "사진 보기" -> showPhoto(memory)
                    "지도에서 열기" -> memory.location?.let { location ->
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("geo:${location.latitude},${location.longitude}?q=${location.latitude},${location.longitude}")))
                    }
                    "삭제" -> viewModel.deleteMemory(memory)
                }
            }.show()
    }

    private fun showPhoto(memory: MemoryEntity) {
        val file = PhotoStore(requireContext()).memoryPhoto(memory.photoFilename ?: return)
        if (!file.exists()) {
            viewModel.reportError(IllegalStateException("저장된 사진을 찾을 수 없어요."))
            return
        }
        MaterialAlertDialogBuilder(requireContext())
            .setTitle(memory.title)
            .setView(ImageView(requireContext()).apply {
                setImageBitmap(BitmapFactory.decodeFile(file.absolutePath))
                adjustViewBounds = true
                contentDescription = memory.visualSummary ?: "저장된 메모리 사진"
            })
            .setMessage(memory.visualSummary)
            .setPositiveButton("닫기", null)
            .show()
    }

    override fun onDestroyView() { _binding = null; super.onDestroyView() }
}
