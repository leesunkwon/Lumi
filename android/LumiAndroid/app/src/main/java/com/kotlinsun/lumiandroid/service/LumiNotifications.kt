package com.kotlinsun.lumiandroid.service

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.kotlinsun.lumiandroid.MainActivity
import com.kotlinsun.lumiandroid.R
import com.kotlinsun.lumiandroid.data.LumiDatabase
import com.kotlinsun.lumiandroid.data.LumiRepository
import com.kotlinsun.lumiandroid.data.ScheduleEntity
import com.kotlinsun.lumiandroid.data.TimerEntity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

object LumiNotifications {
    const val SCHEDULE_CHANNEL = "lumi_schedules"
    const val TIMER_CHANNEL = "lumi_timers"
    const val ACTION_TIMER_COMPLETE = "com.kotlinsun.lumiandroid.TIMER_COMPLETE"
    const val ACTION_TIMER_PAUSE = "com.kotlinsun.lumiandroid.TIMER_PAUSE"
    const val ACTION_TIMER_RESUME = "com.kotlinsun.lumiandroid.TIMER_RESUME"
    const val ACTION_TIMER_CANCEL = "com.kotlinsun.lumiandroid.TIMER_CANCEL"
    const val ACTION_SCHEDULE = "com.kotlinsun.lumiandroid.SCHEDULE_DUE"

    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannels(
            listOf(
                NotificationChannel(SCHEDULE_CHANNEL, "Lumi 일정", NotificationManager.IMPORTANCE_HIGH).apply { description = "일정 리마인더" },
                NotificationChannel(TIMER_CHANNEL, "Lumi 타이머", NotificationManager.IMPORTANCE_HIGH).apply { description = "타이머 진행 및 완료 알림" },
            ),
        )
    }

    fun scheduleSchedule(context: Context, schedule: ScheduleEntity) {
        setAlarm(context, schedule.scheduledAt, schedulePendingIntent(context, schedule.id))
    }

    fun cancelSchedule(context: Context, id: String) = cancelAlarm(context, schedulePendingIntent(context, id))

    fun scheduleTimer(context: Context, timer: TimerEntity) {
        if (timer.isPaused) {
            cancelTimer(context, timer.id)
            showTimer(context, timer)
            return
        }
        setAlarm(context, timer.endsAt, timerPendingIntent(context, timer.id, ACTION_TIMER_COMPLETE))
        showTimer(context, timer)
    }

    fun cancelTimer(context: Context, id: String) {
        cancelAlarm(context, timerPendingIntent(context, id, ACTION_TIMER_COMPLETE))
        NotificationManagerCompat.from(context).cancel(timerNotificationId(id))
    }

    fun showTimer(context: Context, timer: TimerEntity) {
        val contentIntent = PendingIntent.getActivity(
            context,
            timerNotificationId(timer.id),
            Intent(context, MainActivity::class.java).putExtra(MainActivity.EXTRA_TIMER_ID, timer.id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(context, TIMER_CHANNEL)
            .setSmallIcon(R.drawable.ic_lumi_notification)
            .setContentTitle(timer.title)
            .setContentText(if (timer.isPaused) "타이머가 일시정지되었어요." else "타이머 진행 중")
            .setContentIntent(contentIntent)
            .setOngoing(!timer.isPaused)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
        if (!timer.isPaused) {
            builder.setUsesChronometer(true)
                .setWhen(timer.endsAt)
                .setChronometerCountDown(true)
                .addAction(R.drawable.ic_pause, "일시정지", timerPendingIntent(context, timer.id, ACTION_TIMER_PAUSE))
        } else {
            builder.addAction(R.drawable.ic_play, "재개", timerPendingIntent(context, timer.id, ACTION_TIMER_RESUME))
        }
        builder.addAction(R.drawable.ic_close, "취소", timerPendingIntent(context, timer.id, ACTION_TIMER_CANCEL))
        NotificationManagerCompat.from(context).notify(timerNotificationId(timer.id), builder.build())
    }

    fun showScheduleDue(context: Context, schedule: ScheduleEntity) {
        NotificationManagerCompat.from(context).notify(
            scheduleNotificationId(schedule.id),
            NotificationCompat.Builder(context, SCHEDULE_CHANNEL)
                .setSmallIcon(R.drawable.ic_lumi_notification)
                .setContentTitle(schedule.title)
                .setContentText(schedule.note ?: "등록한 일정 시간이에요.")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build(),
        )
    }

    fun showTimerComplete(context: Context, timer: TimerEntity) {
        cancelTimer(context, timer.id)
        NotificationManagerCompat.from(context).notify(
            timerNotificationId(timer.id),
            NotificationCompat.Builder(context, TIMER_CHANNEL)
                .setSmallIcon(R.drawable.ic_lumi_notification)
                .setContentTitle("${timer.title} 완료")
                .setContentText("타이머가 끝났어요.")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build(),
        )
    }

    private fun setAlarm(context: Context, at: Long, pendingIntent: PendingIntent) {
        val alarm = context.getSystemService(AlarmManager::class.java)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarm.canScheduleExactAlarms()) {
            alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pendingIntent)
        } else {
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pendingIntent)
        }
    }

    private fun cancelAlarm(context: Context, pendingIntent: PendingIntent) {
        context.getSystemService(AlarmManager::class.java).cancel(pendingIntent)
        pendingIntent.cancel()
    }

    private fun schedulePendingIntent(context: Context, id: String): PendingIntent = PendingIntent.getBroadcast(
        context,
        scheduleNotificationId(id),
        Intent(context, ScheduleAlarmReceiver::class.java).setAction(ACTION_SCHEDULE).putExtra(EXTRA_ID, id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun timerPendingIntent(context: Context, id: String, action: String): PendingIntent = PendingIntent.getBroadcast(
        context,
        (id + action).hashCode(),
        Intent(context, TimerActionReceiver::class.java).setAction(action).putExtra(EXTRA_ID, id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun timerNotificationId(id: String): Int = ("timer:$id").hashCode()
    private fun scheduleNotificationId(id: String): Int = ("schedule:$id").hashCode()
    const val EXTRA_ID = "lumi_id"
}

class ScheduleAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val id = intent.getStringExtra(LumiNotifications.EXTRA_ID) ?: return@launch
                LumiRepository(LumiDatabase.create(context)).schedule(id)?.let { LumiNotifications.showScheduleDue(context, it) }
            } finally {
                pendingResult.finish()
            }
        }
    }
}

class TimerActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val id = intent.getStringExtra(LumiNotifications.EXTRA_ID) ?: return@launch
                val repository = LumiRepository(LumiDatabase.create(context))
                when (intent.action) {
                    LumiNotifications.ACTION_TIMER_COMPLETE -> repository.timer(id)?.let {
                        LumiNotifications.showTimerComplete(context, it)
                        repository.deleteTimer(it)
                    }
                    LumiNotifications.ACTION_TIMER_PAUSE -> repository.pauseTimer(id)?.let { LumiNotifications.scheduleTimer(context, it) }
                    LumiNotifications.ACTION_TIMER_RESUME -> repository.resumeTimer(id)?.let { LumiNotifications.scheduleTimer(context, it) }
                    LumiNotifications.ACTION_TIMER_CANCEL -> repository.timer(id)?.let {
                        LumiNotifications.cancelTimer(context, it.id)
                        repository.deleteTimer(it)
                    }
                }
            } finally {
                pendingResult.finish()
            }
        }
    }
}
