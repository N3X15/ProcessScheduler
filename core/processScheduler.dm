// Singleton instance of game_controller_new, setup in world.New()
var/global/datum/controller/processScheduler/processScheduler

/datum/controller/processScheduler
	// Processes known by the scheduler
	var/tmp/datum/controller/process/list/processes = new

	// Processes that are currently running
	var/tmp/datum/controller/process/list/running = new

	// Processes that are idle
	var/tmp/datum/controller/process/list/idle = new

	// Processes that are queued to run
	var/tmp/datum/controller/process/list/queued = new

	// Process name -> process object map
	var/tmp/datum/controller/process/list/nameToProcessMap = new

	// Process last start times
	var/tmp/datum/controller/process/list/last_start = new

	// Process last run durations
	var/tmp/datum/controller/process/list/last_run_time = new

	// Per process list of the last 20 durations
	var/tmp/datum/controller/process/list/last_twenty_run_times = new

	// Process highest run time
	var/tmp/datum/controller/process/list/highest_run_time = new

	// Sleep 1 tick -- This may be too aggressive.
	var/tmp/scheduler_sleep_interval = 1

	// Controls whether the scheduler is running or not
	var/tmp/isRunning = 0

/datum/controller/processScheduler/proc/setup()
	// There can be only one
	if(processScheduler && (processScheduler != src))
		del(src)
		return 0

	// Add all the processes we can find, except for the ticker
	for (var/process in typesof(/datum/controller/process) - /datum/controller/process - /datum/controller/process/ticker)
		addProcess(new process(src))

	// Ticker has to be initialized last
	addProcess(new /datum/controller/process/ticker(src))

	// Once the process scheduler is initialized, start the pregame process
	spawn
		ticker.pregame()

/datum/controller/processScheduler/proc/start()
	isRunning = 1
	spawn(0)
		process()

/datum/controller/processScheduler/proc/process()
	while(isRunning)
		checkRunningProcesses()
		queueProcesses()
		runQueuedProcesses()
		sleep(scheduler_sleep_interval)

/datum/controller/processScheduler/proc/stop()
	isRunning = 0

/datum/controller/processScheduler/proc/checkRunningProcesses()
	for(var/datum/controller/process/p in running)
		p.update()

		var/status = p.getStatus()
		var/previousStatus = p.getPreviousStatus()

		// Check status changes
		if(status != previousStatus)
			//Status changed.
			switch(status)
				if(PROCESS_STATUS_PROBABLY_HUNG)
					message_admins("Process '[p.name]' may be hung.")
				if(PROCESS_STATUS_HUNG)
					message_admins("Process '[p.name]' is hung and will be restarted.")

/datum/controller/processScheduler/proc/queueProcesses()
	for(var/datum/controller/process/p in processes)
		// Don't double-queue, don't queue running processes
		if (p.running || p.queued || !p.idle)
			continue

		// If the process should be running by now, go ahead and queue it
		if (world.time > last_start[p] + p.schedule_interval)
			setQueuedProcessState(p)

/datum/controller/processScheduler/proc/runQueuedProcesses()
	for(var/datum/controller/process/p in queued)
		runProcess(p)

/datum/controller/processScheduler/proc/addProcess(var/datum/controller/process/process)
	processes.Add(process)
	process.idle()
	idle.Add(process)

	// init recordkeeping vars
	last_start.Add(process)
	last_run_time.Add(process)
	last_twenty_run_times.Add(process)
	last_twenty_run_times[process] = list()
	highest_run_time.Add(process)
	highest_run_time[process] = 0

	// init starts and stops record starts
	recordStart(process, 0)
	recordEnd(process, 0)

	// Set up process
	process.setup()

	// Save process in the name -> process map
	nameToProcessMap[process.name] = process

/datum/controller/processScheduler/proc/runProcess(var/datum/controller/process/process)
	spawn(0)
		process.process()

/datum/controller/processScheduler/proc/processStarted(var/datum/controller/process/process)
	setRunningProcessState(process)
	recordStart(process)

/datum/controller/processScheduler/proc/processFinished(var/datum/controller/process/process)
	setIdleProcessState(process)
	recordEnd(process)

/datum/controller/processScheduler/proc/setIdleProcessState(var/datum/controller/process/process)
	if (process in running)
		running -= process
	if (process in queued)
		queued -= process
	if (!(process in idle))
		idle += process

/datum/controller/processScheduler/proc/setQueuedProcessState(var/datum/controller/process/process)
	if (process in running)
		running -= process
	if (process in idle)
		idle -= process
	if (!(process in queued))
		queued += process

	// The other state transitions are handled internally by the process.
	process.queued()

/datum/controller/processScheduler/proc/setRunningProcessState(var/datum/controller/process/process)
	if (process in queued)
		queued -= process
	if (process in idle)
		idle -= process
	if (!(process in running))
		running += process

/datum/controller/processScheduler/proc/recordStart(var/datum/controller/process/process, var/time = null)
	if (!(process in last_start))
		last_start += process
	if (isnull(time))
		time = world.time

	last_start[process] = time

/datum/controller/processScheduler/proc/recordEnd(var/datum/controller/process/process, var/time = null)
	if (!(process in last_run_time))
		last_run_time[process] = 0
	if (isnull(time))
		time = world.time

	var/lastRunTime = time - last_start[process]

	if(lastRunTime < 0)
		lastRunTime = 0

	recordRunTime(process, lastRunTime)

/**
 * recordRunTime
 * Records a run time for a process
 */
/datum/controller/processScheduler/proc/recordRunTime(var/datum/controller/process/process, time)
	last_run_time[process] = time
	if(time > highest_run_time[process])
		highest_run_time[process] = time

	var/list/lastTwenty = last_twenty_run_times[process]
	if (lastTwenty.len == 20)
		lastTwenty.Cut(1, 2)
	lastTwenty.len++
	lastTwenty[lastTwenty.len] = time

/**
 * averageRunTime
 * returns the average run time (over the last 20) of the process
 */
/datum/controller/processScheduler/proc/averageRunTime(var/datum/controller/process/process)
	var/lastTwenty = last_twenty_run_times[process]

	var/t = 0
	var/c = 0
	for(var/time in lastTwenty)
		t += time
		c++

	if(c > 0)
		return t / c
	return c

/datum/controller/processScheduler/proc/getStatusData()
	var/list/data = new

	for (var/datum/controller/process/p in processes)
		data.len++
		data[data.len] = p.getContextData()

	return data

/datum/controller/processScheduler/proc/getProcessCount()
	return processes.len

/datum/controller/processScheduler/proc/killProcess(var/processName as text)
	if (nameToProcessMap[processName])
		var/datum/controller/process/p = nameToProcessMap[processName]
		p.kill()