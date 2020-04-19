defmodule Server.Requestor do
  use GenServer

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def handle_reply(reply) do
    GenServer.call(__MODULE__, {:handle_reply, reply})
  end

  def send(device_id, event, payload, timeout \\ 15_000) do
    payload = Map.put_new_lazy(payload, :reference, &:rand.uniform/0)

    ref = payload[:reference]

    try do
      GenServer.call(__MODULE__, {:send, device_id, event, payload}, timeout)
    catch
      :exit, {:timeout, {GenServer, :call, _}} ->
        GenServer.cast(__MODULE__, {:cleanup, ref})
        {:error, :timeout}
    end
  end

  def send_async(device_id, event, payload) do
    payload = Map.put_new_lazy(payload, :reference, &:rand.uniform/0)
    GenServer.cast(__MODULE__, {:send, device_id, event, payload})
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:handle_reply, reply}, _from, state) do
    ref = reply["reference"]
    {from, state} = Map.pop(state, ref)

    if from do
      # Request was made from this node, so reply to waiting process
      GenServer.reply(from, {:ok, reply})

      ServerWeb.Endpoint.unsubscribe("devices:replies:#{ref}")
    else
      # Request was made from another node. Broadcast reply so subscriber
      # can handle it
      ServerWeb.Endpoint.broadcast_from!(
        self(),
        "devices:replies:#{ref}",
        "reply",
        reply
      )
    end

    {:reply, :ok, state}
  end

  def handle_call({:send, device_id, event, payload}, from, requests) do
    ref = payload[:reference]

    ServerWeb.Endpoint.subscribe("devices:replies:#{ref}")

    case do_send(device_id, event, payload) do
      :ok ->
        {:noreply, Map.put(requests, ref, from)}

      {:error, _} = err ->
        {:reply, err, requests}
    end
  end

  @impl true
  def handle_cast({:cleanup, ref}, requests) do
    {:noreply, Map.delete(requests, ref)}
  end

  def handle_cast({:send, device_id, event, payload}, requests) do
    do_send(device_id, event, payload)
    {:noreply, requests}
  end

  @impl true
  def handle_info(%{event: "reply", payload: reply}, state) do
    {from, state} = Map.pop(state, reply["reference"])
    GenServer.reply(from, reply)

    if is_nil(from) do
      Logger.warn("Unhandled reply - #{reply}")
    end

    {:noreply, state}
  end

  defp do_send(device_id, event, payload) do
    ServerWeb.Endpoint.broadcast_from!(self(), "devices:#{device_id}:request", event, payload)
  end
end
