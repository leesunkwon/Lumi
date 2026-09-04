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
import com.kotlinsun.lumiandroid.data.ConversationWithMessages
import com.kotlinsun.lumiandroid.databinding.FragmentListBinding
import kotlinx.coroutines.launch

class ConversationsFragment : Fragment() {
    private var _binding: FragmentListBinding? = null
    private val binding get() = requireNotNull(_binding)
    private val viewModel: LumiViewModel by activityViewModels()
    private val adapter = LumiRowAdapter<ConversationWithMessages> {
        viewModel.selectConversation(it.conversation.id)
        ConversationDialog.show(this, it)
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentListBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        binding.titleText.text = "대화"
        binding.addButton.text = "새 세션"
        binding.emptyText.text = "새로운 대화를 시작해보세요."
        binding.list.layoutManager = LinearLayoutManager(requireContext())
        binding.list.adapter = adapter
        binding.addButton.setOnClickListener { viewModel.newConversation() }
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.state.collect { state ->
                    adapter.submit(state.conversations.map { conversation ->
                        LumiRow(conversation, conversation.conversation.title, conversation.messages.lastOrNull()?.text ?: "안경 또는 음성으로 질문을 시작해보세요.")
                    })
                    binding.emptyText.visibility = if (state.conversations.isEmpty()) View.VISIBLE else View.GONE
                }
            }
        }
    }

    override fun onDestroyView() { _binding = null; super.onDestroyView() }
}
