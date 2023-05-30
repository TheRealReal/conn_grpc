defmodule ConnGRPC.Channel do
  use GenServer

  # Client

  def start_link(options) when is_list(options) do
    GenServer.start_link(__MODULE__, options, name: options[:name])
  end

  def get(channel) do
    GenServer.call(channel, :get)
  end

  # server

  def init(options) do
    send(self(), :connect)

    config = %{
      address: Keyword.fetch!(options, :address),
      options: Keyword.get(options, :options, [])
    }

    on_connect = Keyword.get(options, :on_connect, fn -> nil end)
    on_disconnect = Keyword.get(options, :on_disconnect, fn -> nil end)

    {:ok, %{channel: nil, config: config, on_connect: on_connect, on_disconnect: on_disconnect}}
  end

  def handle_info(:connect, state) do
    case GRPC.Stub.connect(state.config.address, state.config.options) do
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
