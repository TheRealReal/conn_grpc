defmodule ConnGRPC.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Starts a worker by calling: ConnGRPC.Worker.start_link(arg)
      # {ConnGRPC.Worker, arg}
      # {ConnGRPC.Channel, name: :my_channel, address: "localhost:50020"}
      # MyChannel,
      # {Registry, name: :my_registry, keys: :duplicate}

      {ConnGRPC.Pool, name: :my_pool, channel: [address: "localhost:50020"], pool_size: 10}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ConnGRPC.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
