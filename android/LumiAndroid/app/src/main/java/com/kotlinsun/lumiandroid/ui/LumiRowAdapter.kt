package com.kotlinsun.lumiandroid.ui

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.kotlinsun.lumiandroid.databinding.ItemLumiRowBinding

data class LumiRow<T>(val item: T, val title: String, val subtitle: String)

class LumiRowAdapter<T>(private val onClick: (T) -> Unit) : RecyclerView.Adapter<LumiRowAdapter<T>.Holder>() {
    private var items: List<LumiRow<T>> = emptyList()

    fun submit(rows: List<LumiRow<T>>) {
        items = rows
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder = Holder(
        ItemLumiRowBinding.inflate(LayoutInflater.from(parent.context), parent, false),
    )

    override fun onBindViewHolder(holder: Holder, position: Int) = holder.bind(items[position])
    override fun getItemCount(): Int = items.size

    inner class Holder(private val binding: ItemLumiRowBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(row: LumiRow<T>) {
            binding.rowTitle.text = row.title
            binding.rowSubtitle.text = row.subtitle
            binding.root.setOnClickListener { onClick(row.item) }
        }
    }
}
