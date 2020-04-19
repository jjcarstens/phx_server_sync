defmodule Client.DeviceChannel do
  use GenServer

  alias PhoenixClient.{Channel, Message}

  require Logger

  @rejoin_after 5_000

  def child_spec(device_id) do
    %{id: via_name(device_id), start: {__MODULE__, :start_link, [device_id]}}
  end

  def start_link(device_id) do
    GenServer.start_link(__MODULE__, device_id, name: __MODULE__)
  end

  def via_name(device_id) do
    {:via, Registry, {SCPRegistry, to_string(device_id)}}
  end

  @impl true
  def init(device_id) do
    send(self(), :join)
    {:ok, %{id: device_id, channel: nil, connected?: false}}
  end

  @impl true
  def handle_info(:join, state) do
    case Channel.join(Client.Socket, "devices:#{state.id}", %{}) do
      {:ok, _reply, channel} ->
        {:noreply, %{state | channel: channel, connected?: true}}

      _error ->
        Process.send_after(self(), :join, @rejoin_after)
        {:noreply, %{state | connected?: false}}
    end
  end

  def handle_info(%Message{event: "request", payload: payload}, state) do
    sleep = :rand.uniform(10)
    Logger.warn("Sleeping before return: #{sleep} seconds - #{DateTime.utc_now()}")

    :timer.sleep(sleep * 1000)

    Channel.push_async(state.channel, "reply", payload)
    {:noreply, state}
  end

  def handle_info(%Message{event: event, payload: payload}, state)
      when event in ["phx_error", "phx_close"] do
    reason = Map.get(payload, :reason, "unknown")
    Logger.error("Disconnected with #{inspect(reason)} - Attempting reconnect")
    Process.send_after(self(), :join, @rejoin_after)
    {:noreply, %{state | connected?: false}}
  end

  def handle_info(msg, state) do
    Logger.warn("Unknown message: #{inspect(msg)}")
    {:noreply, state}
  end
end
