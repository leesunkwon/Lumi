package com.kotlinsun.lumiandroid.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.fragment.app.activityViewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.LinearLayoutManager
import com.kotlinsun.lumiandroid.data.ScheduleEntity
import com.kotlinsun.lumiandroid.databinding.FragmentListBinding
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.launch

class SchedulesFragment : Fragment() {
    private var _binding: FragmentListBinding? = null
    private val binding get() = requireNotNull(_binding)
    private val viewModel: LumiViewModel by activityViewModels()
    private val adapter = LumiRowAdapter<ScheduleEntity> { ScheduleEditorDialog.show(this, it) }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentListBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        binding.titleText.text = "일정"
        binding.addButton.text = "일정 추가"
        binding.emptyText.text = "등록한 일정이 없어요.\n말하거나 직접 입력해 일정을 추가할 수 있어요."
        binding.list.layoutManager = LinearLayoutManager(requireContext())
        binding.list.adapter = adapter
        binding.addButton.setOnClickListener { ScheduleEditorDialog.show(this) }
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.state.collect { state ->
                    adapter.submit(state.schedules.map { schedule ->
                        LumiRow(schedule, schedule.title, "${DateFormat.getDateTimeInstance().format(Date(schedule.scheduledAt))}${schedule.note?.let { " · $it" }.orEmpty()}")
                    })
                    binding.emptyText.visibility = if (state.schedules.isEmpty()) View.VISIBLE else View.GONE
                }
            }
        }
    }

    override fun onDestroyView() { _binding = null; super.onDestroyView() }
}
