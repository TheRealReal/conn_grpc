defmodule ConnGrpc.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Starts a worker by calling: ConnGrpc.Worker.start_link(arg)
      # {ConnGrpc.Worker, arg}
      {ConnGrpc.Channel, name: :my_channel, address: "localhost:50020"}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ConnGrpc.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
