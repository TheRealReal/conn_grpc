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

  To get the connection in your application, call:

      ConnGRPC.Channel.get_channel(:demo_channel)

  ## Options available

  For all options available, see `start_link/1`.
  """

  use GenServer

  require Logger

  @backoff_module ConnGRPC.Backoff.Exponential
  @backoff_opts [min: 1000, max: 30_000]

  # Client

  @doc """
  Starts and links process that keeps a persistent gRPC channel.

  ### Options

    * `:address` - The gRPC server address. For more details,
    see [`GRPC.Stub.connect/2`](https://hexdocs.pm/grpc/0.5.0/GRPC.Stub.html#connect/2)

    * `:opts` - Options for Elixir gRPC. For more details,
    see [`GRPC.Stub.connect/2`](https://hexdocs.pm/grpc/0.5.0/GRPC.Stub.html#connect/2)

    * `:name` - A name to register the started process (see the `:name` option
      in `GenServer.start_link/3`)

    * `:backoff` - Minimum and maximum exponential backoff intervals (default: `[min: 1000, max: 30_000]`)

    * `:backoff_module` - Backoff module to be used (default: `ConnGRPC.Backoff.Exponential`).
    If you'd like to implement your own backoff, see the `ConnGRPC.Backoff` behavior.

    * `:debug` - Write debug logs (default: `false`)

    * `:on_connect` - Function to run on connect (0-arity)

    * `:on_disconnect` - Function to run on disconnect (0-arity)
  """
  def start_link(options) when is_list(options) do
    GenServer.start_link(__MODULE__, options, name: options[:name])
  end

  @doc "Returns the gRPC channel"
  @spec get(atom | pid) :: {:ok, GRPC.Channel.t()} | {:error, :not_connected}
  def get(channel, opts \\ []) do
    start = System.monotonic_time()

    result = GenServer.call(channel, :get)

    :telemetry.execute(
      [:conn_grpc, :channel, :get],
      %{duration: System.monotonic_time() - start},
      %{channel: channel, pool_name: opts[:pool_name]}
    )

    result
  end

  # Server

  @impl true
  def init(options) do
    state = %{
      backoff: %{
        module: Keyword.get(options, :backoff_module, @backoff_module),
        opts: Keyword.get(options, :backoff, @backoff_opts)
      },
      channel: nil,
      connection_start: nil,
      config: %{
        grpc_stub: Keyword.get(options, :grpc_stub, GRPC.Stub),
        address: Keyword.fetch!(options, :address),
        opts: Keyword.get(options, :opts, [])
      },
      debug: Keyword.get(options, :debug, false),
      name: Keyword.get(options, :name),
      pool_name: Keyword.get(options, :pool_name),
      on_connect: Keyword.get(options, :on_connect, fn -> nil end),
      on_disconnect: Keyword.get(options, :on_disconnect, fn -> nil end),
      retry_timer_ref: nil
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

  # START - Gun callbacks

  # By default, Gun reconnects automatically. However, to keep a single interface
  # for backoff, we do not use its retry and handle it on our own.
  def handle_info({:gun_down, _, _, _, _}, state) do
    {:noreply, handle_disconnect(state)}
  end

  # END - Gun callbacks

  # START - Mint callbacks

  # Mint adapter traps exits, this is called when the connection goes down
  def handle_info({:EXIT, _pid, _}, state), do: {:noreply, state}

  # This is also called with the Mint adapter when connection goes down
  def handle_info({:elixir_grpc, :connection_down, _pid}, state) do
    {:noreply, handle_disconnect(state)}
  end

  # END - Mint callbacks

  def handle_info(msg, state) do
    debug(state, "Unexpected message: #{inspect(msg)}")
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

  defp connect(%{channel: nil} = state) do
    %{grpc_stub: grpc_stub, address: address, opts: opts} = state.config

    start = System.monotonic_time()

    case grpc_stub.connect(address, opts) do
      {:ok, channel} ->
        now = System.monotonic_time()

        :telemetry.execute(
          [:conn_grpc, :channel, :connected],
          %{duration: now - start},
          telemetry_metadata(state)
        )

        debug(state, "Connected")
        state.on_connect.()
        {:noreply, %{state | channel: channel, connection_start: now} |> reset_backoff()}

      {:error, error} ->
        now = System.monotonic_time()

        :telemetry.execute(
          [:conn_grpc, :channel, :connection_failed],
          %{duration: now - start, error: error},
          telemetry_metadata(state)
        )

        debug(state, "Connection failed: #{inspect(error)}")
        {:noreply, schedule_retry(state)}
    end
  end

  defp connect(state), do: {:noreply, state}

  defp handle_disconnect(state) do
    now = System.monotonic_time()
    debug(state, "Connection down")
    state.on_disconnect.()
    state.channel.adapter.disconnect(state.channel)

    :telemetry.execute(
      [:conn_grpc, :channel, :disconnected],
      %{duration: now - state.connection_start},
      telemetry_metadata(state)
    )

    state = %{state | channel: nil}
    schedule_retry(state)
  end

  defp schedule_retry(state) do
    state = clear_timer(state)
    {retry_delay, state} = increment_backoff(state)
    retry_timer_ref = Process.send_after(self(), :connect, retry_delay)
    debug(state, "Retrying in #{retry_delay}ms")
    %{state | retry_timer_ref: retry_timer_ref}
  end

  defp clear_timer(%{retry_timer_ref: nil} = state), do: state

  defp clear_timer(%{retry_timer_ref: timer} = state) do
    Process.cancel_timer(timer)
    %{state | retry_timer_ref: nil}
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

  defp debug(%{debug: true, pool_name: pool_name}, message) when not is_nil(pool_name) do
    prefix = "[ConnGRPC.Channel] [#{inspect(pool_name)}] [#{inspect(self())}] "
    Logger.debug(prefix <> message)
  end

  defp debug(%{debug: true, name: name}, message) do
    prefix = "[ConnGRPC.Channel] [#{inspect(name || self())}] "
    Logger.debug(prefix <> message)
  end

  defp telemetry_metadata(state), do: %{channel_name: state.name, pool_name: state.pool_name}

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
