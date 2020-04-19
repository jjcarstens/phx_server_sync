defmodule ServerWeb.DeviceChannel do
  use ServerWeb, :channel

  def join("devices:" <> id, _params, socket) do
    socket.endpoint.subscribe("devices:#{id}:request")
    {:ok, %{status: :joined}, socket}
  end

  def handle_in("reply", payload, socket) do
    Server.Requestor.handle_reply(payload)
    {:noreply, socket}
  end

  def handle_info(%{event: event, payload: payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end
end
