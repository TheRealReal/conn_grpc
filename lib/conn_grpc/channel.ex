defmodule ConnGRPC.Channel do
  use GenServer

  # Client

  def start_link(options) when is_list(options) do
    GenServer.start_link(__MODULE__, options, [name: options[:name]])
  end

  def get(channel) do
    GenServer.call(channel, :get)
  end

  # server

  def init(options) do
    send(self(), :connect)
    config = %{address: Keyword.fetch!(options, :address), options: Keyword.get(options, :options, [])}
    {:ok, %{channel: nil, config: config}}
  end

  def handle_info(:connect, state) do
    case GRPC.Stub.connect(state.config.address, state.config.options) do
      {:ok, channel} ->
        {:noreply, Map.put(state, :channel, channel)}

      {:error, _error} ->
        Process.send_after(self(), :connect, 2000)
        {:noreply, state}
    end
  end

  def handle_info({:gun_down, _, _, _, _}, state) do
    {:noreply, state}
  end

  def handle_info({:gun_up, _, _}, state) do
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
