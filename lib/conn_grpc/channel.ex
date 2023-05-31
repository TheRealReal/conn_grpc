defmodule ConnGRPC.Channel do
  @doc """
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

  # Client

  def start_link(options) when is_list(options) do
    GenServer.start_link(__MODULE__, options, name: options[:name])
  end

  def get(channel) do
    GenServer.call(channel, :get)
  end

  # Server

  def init(options) do
    send(self(), :connect)

    config = %{
      address: Keyword.fetch!(options, :address),
      opts: Keyword.get(options, :opts, [])
    }

    on_connect = Keyword.get(options, :on_connect, fn -> nil end)
    on_disconnect = Keyword.get(options, :on_disconnect, fn -> nil end)

    {:ok, %{channel: nil, config: config, on_connect: on_connect, on_disconnect: on_disconnect}}
  end

  def handle_info(:connect, state) do
    case GRPC.Stub.connect(state.config.address, state.config.opts) do
      {:ok, channel} ->
        state.on_connect.()
        {:noreply, Map.put(state, :channel, channel)}

      {:error, _error} ->
        Process.send_after(self(), :connect, 2000)
        {:noreply, state}
    end
  end

  def handle_info({:gun_down, _, _, _, _}, state) do
    state.on_disconnect.()
    {:noreply, state}
  end

  def handle_info({:gun_up, _, _}, state) do
    state.on_connect.()
    {:noreply, state}
  end

  def handle_call(:get, _from, state) do
    response =
      case state.channel do
        nil -> {:error, :not_connected}
        channel -> {:ok, channel}
      end

    {:reply, response, state}
  end

  defmacro __using__(use_opts \\ []) do
    quote do
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
