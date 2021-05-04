defmodule Glific.Metrics.Worker do
  @moduledoc """
  Simple worker which caches all the counts for a specific flow and writes them
  out in batches. This allows us to amortize multiple requests into one DB write.

  Module influenced and borrowed from: https://dashbit.co/blog/homemade-analytics-with-ecto-and-elixir
  """
  use GenServer, restart: :temporary

  @registry Glific.Metrics.Registry

  alias Glific.Flows.FlowCount

  @doc false
  def start_link(key) do
    GenServer.start_link(__MODULE__, key, name: {:via, Registry, {@registry, key}})
  end

  @doc false
  @impl true
  def init({:flow_id, flow_id} = _key) do
    Process.flag(:trap_exit, true)
    schedule_upsert()
    {:ok, %{flow_id: flow_id, entries: []}}
  end

  @spec add_entry(map(), list()) :: list()
  defp add_entry(entry, []), do: [entry]

  defp add_entry(entry, entries) do
    recent_messages =
      if Map.has_key?(entry, :recent_message),
        do: [entry.recent_message],
        else: []

    {entries, found} =
      entries
      |> Enum.reduce(
        {[], false},
        fn e, {entries, found} ->
          if !found && e.id == entry.id do
            e =
              e
              |> Map.put(:count, e.count + 1)
              |> Map.put(:recent_messages, e.recent_messages ++ recent_messages)

            {[e | entries], true}
          else
            {[e | entries], found}
          end
        end
      )

    if found do
      entries
    else
      e =
        entry
        |> Map.put(:count, 1)
        |> Map.put(:recent_messages, recent_messages)

      [e | entries]
    end
  end

  @doc false
  defp schedule_upsert do
    # store to database between 1 to 3 minutes
    Process.send_after(self(), :upsert, Enum.random(60..180) * 1_000)
  end

  @doc false
  @impl true
  def handle_info({:bump, entry}, %{flow_id: flow_id, entries: entries}) do
    {:noreply, %{flow_id: flow_id, entries: add_entry(entry, entries)}}
  end

  @impl true
  def handle_info(:upsert, %{flow_id: flow_id} = state) do
    # We first unregister ourselves so we stop receiving new messages.
    Registry.unregister(@registry, {:flow_id, flow_id})

    # Schedule to stop in 2 seconds, this will give us time to process
    # any late messages.
    Process.send_after(self(), :stop, 2_000)
    {:noreply, state}
  end

  @impl true
  def handle_info(:stop, state) do
    # Now we just stop. The terminate callback will write all pending writes.
    {:stop, :shutdown, state}
  end

  @spec upsert!(map()) :: :ok
  defp upsert!(%{entries: []}), do: :ok

  defp upsert!(%{entries: entries}) do
    entries |> Enum.each(&FlowCount.upsert_flow_count(&1))
  end

  @doc false
  @impl true
  def terminate(_, state), do: upsert!(state)
end
