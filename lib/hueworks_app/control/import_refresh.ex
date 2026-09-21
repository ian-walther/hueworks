defmodule Hueworks.Control.ImportRefresh do
  @moduledoc """
  Reconciles a bridge's runtime after a committed import, independently of the caller.
  One task per bridge runs at a time; another import during a refresh schedules a
  second pass over the latest model. Failures retry without changing import status.
  """
  use GenServer
  require Logger
  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.BridgeRefresh
  alias Hueworks.DomainEvents
  alias Hueworks.Repo
  alias Hueworks.RuntimeIO
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Subscription.Readiness

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def status(bridge_id, server \\ __MODULE__), do: GenServer.call(server, {:status, bridge_id})

  def task_supervisor, do: Hueworks.Control.ImportRefresh.Tasks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    Phoenix.PubSub.subscribe(Hueworks.PubSub, DomainEvents.topic())

    {:ok,
     %{
       jobs: %{},
       refresh: Keyword.get(opts, :refresh_fun, &BridgeRefresh.run/1),
       tasks: Keyword.get(opts, :task_supervisor, task_supervisor()),
       timeout: Keyword.get(opts, :timeout_ms, 30_000),
       retry: Keyword.get(opts, :retry_ms, 1_000),
       max_retry: Keyword.get(opts, :max_retry_ms, 30_000),
       recover?: Keyword.get(opts, :recover_on_start, true)
     }, {:continue, :recover}}
  end

  @impl true
  def handle_continue(:recover, state), do: recover(state)

  @impl true
  def handle_call({:status, id}, _from, state) do
    {:reply, state.jobs |> Map.get(id, %{}) |> Map.get(:status), state}
  end

  @impl true
  def handle_info(:recover, state), do: recover(state)

  def handle_info({:bridge_import_applied, id}, state) do
    job = Map.get(state.jobs, id, new_job())

    if job.task do
      {:noreply, put_job(state, id, %{job | again?: true})}
    else
      cancel_timer(job.timer)
      {:noreply, start_job(state, id, new_job())}
    end
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    case task_job(state, ref) do
      {id, job} ->
        Process.demonitor(ref, [:flush])
        {:noreply, finish(state, id, job, result)}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case task_job(state, ref) do
      {id, job} -> {:noreply, finish(state, id, job, {:error, :task_exit})}
      nil -> {:noreply, state}
    end
  end

  def handle_info({:timeout, id, ref}, state) do
    case Map.get(state.jobs, id) do
      %{task: %Task{ref: ^ref} = task} = job ->
        Task.shutdown(task, :brutal_kill)
        {:noreply, finish(state, id, job, {:error, :timeout})}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:retry, id, tag}, state) do
    case Map.get(state.jobs, id) do
      %{task: nil, timer: {_timer, ^tag}} = job ->
        {:noreply, start_job(state, id, %{job | timer: nil})}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.jobs, fn {_id, job} ->
      cancel_timer(job.timer)
      if job.task, do: Task.shutdown(job.task, :brutal_kill)
    end)
  end

  defp new_job, do: %{task: nil, timer: nil, again?: false, attempt: 0, status: nil}

  defp recover(state) do
    cond do
      not state.recover? or RuntimeIO.disabled?() ->
        {:noreply, state}

      Readiness.bridges_table_ready?() ->
        ids =
          Repo.all(
            from(b in Bridge,
              where: b.enabled and b.import_complete,
              select: b.id
            )
          )

        Enum.each(ids, &send(self(), {:bridge_import_applied, &1}))
        {:noreply, %{state | recover?: false}}

      true ->
        Process.send_after(self(), :recover, 2_000)
        {:noreply, state}
    end
  end

  defp start_job(state, id, job) do
    if RuntimeIO.disabled?() do
      report(state, id, job, :disabled)
    else
      task =
        Task.Supervisor.async_nolink(state.tasks, fn -> safely_refresh(state.refresh, id) end)

      timer = Process.send_after(self(), {:timeout, id, task.ref}, state.timeout)
      job = %{job | task: task, timer: {timer, task.ref}, attempt: job.attempt + 1}
      report(state, id, job, :refreshing)
    end
  end

  defp safely_refresh(refresh, id) do
    refresh.(id)
  rescue
    _ -> {:error, :refresh_failed}
  catch
    _kind, _reason -> {:error, :task_exit}
  end

  defp finish(state, id, job, result) do
    cancel_timer(job.timer)
    job = %{job | task: nil, timer: nil}

    cond do
      job.again? ->
        start_job(state, id, new_job())

      result == :ok ->
        report(state, id, job, :ready)

      result in [:disabled, :skipped] ->
        report(state, id, job, result)

      true ->
        delay = min(state.max_retry, state.retry * Integer.pow(2, min(job.attempt - 1, 10)))
        tag = make_ref()
        timer = Process.send_after(self(), {:retry, id, tag}, delay)
        error = error_code(result)

        Logger.warning(
          "Bridge runtime refresh retry bridge_id=#{id} attempt=#{job.attempt} reason=#{error} retry_ms=#{delay}"
        )

        report(state, id, %{job | timer: {timer, tag}}, :retrying, error)
    end
  end

  defp report(state, id, job, phase, error \\ nil) do
    status = %{state: phase, attempt: job.attempt, error: error, updated_at: DateTime.utc_now()}

    Phoenix.PubSub.broadcast(
      Hueworks.PubSub,
      "bridge_runtime_refresh",
      {:bridge_runtime_refresh, id, status}
    )

    put_job(state, id, %{job | status: status})
  end

  defp error_code({:error, code}) when code in [:indexes, :observations, :timeout, :task_exit],
    do: code

  defp error_code(_), do: :refresh_failed

  defp put_job(state, id, job), do: %{state | jobs: Map.put(state.jobs, id, job)}

  defp task_job(state, ref) do
    Enum.find(state.jobs, fn {_id, job} -> match?(%Task{ref: ^ref}, job.task) end)
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer({timer, _tag}), do: Process.cancel_timer(timer)
end
