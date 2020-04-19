defmodule Client.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {PhoenixClient.Socket,
       {[url: "ws://localhost:4000/socket/websocket"], [name: Client.Socket]}},
      {Client.DeviceChannel, 1}
    ]

    opts = [strategy: :one_for_one, name: Client.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
