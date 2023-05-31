defmodule ConnGRPC.Channel do
  @moduledoc """
  A process that manages a gRPC channel.

  When `ConnGRPC.Channel` is started, it will create a gRPC connection, which can be fetched with
  `ConnGRPC.Channel.get/1`.

  You can use this if you want to keep a persistent gRPC channel open to be reused in your application.

  Depending on the load, using a single channel for the entire application may become a bottleneck. In that
  case, see the `ConnGRPC.Pool` module, that allows creating a pool of channels.

  ## Module-based channel

  To implement a module-based gRPC channel, define a module that uses `ConnGRPC.Channel`.

      defmodule DemoChannel do
        use ConnGRPC.Channel, address: "localhost:50051", opts: []
      end

  The format of `address` and `opts` is the same used by
  [`GRPC.Stub.connect/2`](https://hexdocs.pm/grpc/0.5.0/GRPC.Stub.html#connect/2)

  Then, you can add the module to your application supervision tree.

      defmodule Demo.Application do
        use Application

        @impl true
        def start(_type, _args) do
          children = [
            DemoChannel
          ]

          Supervisor.start_link(children, strategy: :one_for_one, name: Demo.Supervisor)
        end
      end

  To get the connection in your application, call:

      DemoChannel.get()

  It'll return either `{:ok, channel}` or `{:error, :not_connected}`.

  ## Channel without module

  If you don't want to define for your channel, you can add `ConnGRPC.Channel` directly to your
  supervision tree and pass the options on the child spec.

      defmodule Demo.Application do
        use Application

        @impl true
        def start(_type, _args) do
          children = [
            Supervisor.child_spec(
              {ConnGRPC.Channel, name: :demo_channel, address: "localhost:50051", opts: []},
              id: :demo_channel
            )
          ]

          Supervisor.start_link(children, strategy: :one_for_one, name: Demo.Supervisor)
        end
      end

  The format of `address` and `opts` is the same used by
  [`GRPC.Stub.connect/2`](https://hexdocs.pm/grpc/0.5.0/GRPC.Stub.html#connect/2)

  To get the connection in your application, call:

      ConnGRPC.Channel.get_channel(:demo_channel)

  """

  use GenServer

  require Logger

  # Client

  def start_link(options) when is_list(options) do
    GenServer.start_link(__MODULE__, options, name: options[:name])
  end

  @doc "Returns the gRPC channel"
  @spec get(atom | pid) :: {:ok, GRPC.Channel.t()} | {:error, :not_connected}
  def get(channel) do
    GenServer.call(channel, :get)
  end

  # Server

  @impl true
  def init(options) do
    backoff_options = Keyword.get(options, :backoff, [])

    state = %{
      backoff: %{
        module: Keyword.get(backoff_options, :module, ConnGRPC.Backoff.Exponential),
        opts: Keyword.get(backoff_options, :opts, min: 1000, max: 30_000)
      },
      channel: nil,
      config: %{
        grpc_stub: Keyword.get(options, :grpc_stub, GRPC.Stub),
        address: Keyword.fetch!(options, :address),
        opts: Keyword.get(options, :opts, [])
      },
      debug: Keyword.get(options, :debug, false),
      name: Keyword.get(options, :name),
      on_connect: Keyword.get(options, :on_connect, fn -> nil end),
      on_disconnect: Keyword.get(options, :on_disconnect, fn -> nil end)
    }

    state = initialize_backoff(state)

    {:ok, state, {:continue, :connect}}
  end

  defp initialize_backoff(state) do
    %{module: module, opts: opts} = state.backoff
    put_in(state.backoff[:state], module.new(opts))
  end

  @impl true
  def handle_continue(:connect, state), do: connect(state)

  @impl true
  def handle_info(:connect, state), do: connect(state)

  def handle_info({:gun_down, _, _, _, _}, state) do
    debug(state, "Gun disconnected")
    state.on_disconnect.()
    {:noreply, state}
  end

  def handle_info({:gun_up, _, _}, state) do
    debug(state, "Gun reconnected")
    state.on_connect.()
    {:noreply, state}
  end

  @impl true
  def handle_call(:get, _from, state) do
    response =
      case state.channel do
        nil -> {:error, :not_connected}
        channel -> {:ok, channel}
      end

    {:reply, response, state}
  end

  defp connect(state) do
    %{grpc_stub: grpc_stub, address: address, opts: opts} = state.config

    case grpc_stub.connect(address, opts) do
      {:ok, channel} ->
        debug(state, "Connected")
        state.on_connect.()
        {:noreply, %{state | channel: channel} |> reset_backoff()}

      {:error, error} ->
        {retry_delay, state} = increment_backoff(state)
        Process.send_after(self(), :connect, retry_delay)
        debug(state, "Connection failed. Retrying in #{retry_delay}ms. Error: #{inspect(error)}.")
        {:noreply, state}
    end
  end

  defp reset_backoff(state) do
    %{module: backoff_module} = state.backoff
    update_in(state.backoff.state, &backoff_module.reset/1)
  end

  defp increment_backoff(state) do
    %{module: backoff_module, state: backoff_state} = state.backoff

    {delay, backoff_state} = backoff_module.backoff(backoff_state)

    {delay, put_in(state.backoff.state, backoff_state)}
  end

  defp debug(%{debug: false}, _message), do: nil

  defp debug(%{debug: true, name: name}, message) do
    prefix = "[ConnGRPC.Channel:#{inspect(name || self())}] "
    Logger.debug(prefix <> message)
  end

  defmacro __using__(use_opts \\ []) do
    quote do
      @doc "Returns the gRPC channel"
      @spec get() :: {:ok, GRPC.Channel.t()} | {:error, :not_connected}
      def get, do: ConnGRPC.Channel.get(__MODULE__)

      def child_spec(opts) do
        [name: __MODULE__]
        |> Keyword.merge(unquote(use_opts))
        |> Keyword.merge(opts)
        |> ConnGRPC.Channel.child_spec()
        |> Supervisor.child_spec(id: __MODULE__)
      end
    end
  end
end
