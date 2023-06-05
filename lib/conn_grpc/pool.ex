defmodule ConnGRPC.Pool do
  @moduledoc """
  A process that manages a pool of persistent gRPC channels.

  When `ConnGRPC.Pool` is started, it will start a pool of pre-connected channels. You can
  then fetch an individual channel from it by calling `ConnGRPC.Pool.get_channel/1`, which
  uses round-robin to determine the channel returned.

  `ConnGRPC.Pool` doesn't implement any checkout mechanism and acts as a routing pool, or a simple
  load balancer. The reason checkout is not implemented is because gRPC allows making multiple
  requests in parallel in a single channel, so we don't need to lock the channel to a specific process
  while it's being used.

  ## Module-based pool

  To implement a module-based gRPC pool, define a module that uses `ConnGRPC.Pool`.

      defmodule DemoPool do
        use ConnGRPC.Pool,
          pool_size: 5,
          channel: [address: "localhost:50051", opts: []]
      end

  The format of `address` and `opts` is the same used by
  [`GRPC.Stub.connect/2`](https://hexdocs.pm/grpc/0.5.0/GRPC.Stub.html#connect/2)

  Then, you can add the module to your application supervision tree.

      defmodule Demo.Application do
        use Application

        @impl true
        def start(_type, _args) do
          children = [
            DemoPool
          ]

          Supervisor.start_link(children, strategy: :one_for_one, name: Demo.Supervisor)
        end
      end

  To get a connection from the pool in your application, call:

      DemoPool.get_channel()

  It'll return either `{:ok, channel}` or `{:error, :not_connected}`.

  ## Pool without module

  If you don't want to define a module for your pool, you can add `ConnGRPC.Pool` directly to your
  supervision tree and pass the options on the child spec.

      defmodule Demo.Application do
        use Application

        @impl true
        def start(_type, _args) do
          children = [
            Supervisor.child_spec(
              {ConnGRPC.Pool, name: :demo_pool, pool_size: 5, channel: [address: "localhost:50051", opts: []]},
              id: :demo_pool
            )
          ]

          Supervisor.start_link(children, strategy: :one_for_one, name: Demo.Supervisor)
        end
      end

  The format of `address` and `opts` is the same used by
  [`GRPC.Stub.connect/2`](https://hexdocs.pm/grpc/0.5.0/GRPC.Stub.html#connect/2)

  To get a connection from the pool in your application, call:

      ConnGRPC.Pool.get_channel(:demo_pool)

  """

  use Supervisor

  alias ConnGRPC.Channel

  @telemetry_interval :timer.seconds(3)

  defmacro __using__(use_opts \\ []) do
    quote do
      @doc "Returns a gRPC channel from the pool"
      @spec get_channel() :: {:ok, GRPC.Channel.t()} | {:error, :not_connected}
      def get_channel, do: ConnGRPC.Pool.get_channel(__MODULE__)

      @doc "Returns all pids on the pool"
      @spec get_all_pids() :: [pid()]
      def get_all_pids, do: ConnGRPC.Pool.get_all_pids(__MODULE__)

      def child_spec(opts) do
        [name: __MODULE__]
        |> Keyword.merge(unquote(use_opts))
        |> Keyword.merge(opts)
        |> ConnGRPC.Pool.child_spec()
        |> Supervisor.child_spec(id: __MODULE__)
      end
    end
  end

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc "Returns a gRPC channel from the pool"
  @spec get_channel(module | atom) :: {:ok, GRPC.Channel.t()} | {:error, :not_connected}
  def get_channel(pool_name) do
    start = System.monotonic_time()
    channels = Registry.lookup(registry(pool_name), :channels)
    pool_size = length(channels)

    result =
      if pool_size > 0 do
        do_get_channel(pool_name, channels, pool_size)
      else
        {:error, :not_connected}
      end

    :telemetry.execute(
      [:conn_grpc, :pool, :get_channel],
      %{duration: System.monotonic_time() - start},
      %{pool_name: pool_name}
    )

    result
  end

  defp do_get_channel(pool_name, channels, pool_size) do
    index =
      :ets.update_counter(
        ets_table(pool_name),
        :index,
        {_pos = 2, _incr = 1, _threshold = pool_size - 1, _reset = 0}
      )

    {pid, _} = Enum.at(channels, index)

    Channel.get(pid, pool_name)
  end

  @doc "Returns all pids on the pool"
  @spec get_all_pids(module | atom) :: [pid()]
  def get_all_pids(pool_name) do
    registry(pool_name)
    |> Registry.lookup(:channels)
    |> Enum.map(fn {pid, _} -> pid end)
  end

  @impl true
  def init(opts) do
    pool_name = Keyword.fetch!(opts, :name)
    pool_size = Keyword.fetch!(opts, :pool_size)
    channel_opts = Keyword.fetch!(opts, :channel)
    telemetry_interval = Keyword.get(opts, :telemetry_interval, @telemetry_interval)
    registry_name = registry(pool_name)

    build_ets_table(pool_name)

    children = [
      {Registry, name: registry_name, keys: :duplicate},
      build_channels_supervisor_spec(pool_name, pool_size, channel_opts, registry_name),
      Supervisor.child_spec(
        {Task, fn -> telemetry_status_loop(pool_name, pool_size, telemetry_interval) end},
        id: :telemetry_status_loop,
        restart: :permanent
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp build_channels_supervisor_spec(pool_name, pool_size, channel_opts, registry_name) do
    channel_opts =
      channel_opts
      |> Keyword.put(:on_connect, fn -> Registry.register(registry_name, :channels, nil) end)
      |> Keyword.put(:on_disconnect, fn -> Registry.unregister(registry_name, :channels) end)
      |> Keyword.put(:pool_name, pool_name)

    channels_specs =
      for index <- 1..pool_size do
        Supervisor.child_spec({ConnGRPC.Channel, channel_opts}, id: {ConnGRPC.Channel, index})
      end

    %{
      id: :channels_supervisor,
      type: :supervisor,
      start: {Supervisor, :start_link, [channels_specs, [strategy: :one_for_one]]}
    }
  end

  defp build_ets_table(pool_name) do
    ets_table = ets_table(pool_name)

    :ets.new(ets_table, [:public, :named_table, :set])
    :ets.insert(ets_table, {:index, -1})
  end

  defp telemetry_status_loop(pool_name, pool_size, interval) do
    current_size = Registry.lookup(registry(pool_name), :channels) |> length()

    :telemetry.execute(
      [:conn_grpc, :pool, :status],
      %{expected_size: pool_size, current_size: current_size},
      %{pool_name: pool_name}
    )

    :timer.sleep(interval)
    telemetry_status_loop(pool_name, pool_size, interval)
  end

  defp ets_table(pool_name) do
    :"#{pool_name}.ETS"
  end

  defp registry(pool_name) do
    :"#{pool_name}.Registry"
  end
end
