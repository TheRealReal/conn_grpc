defmodule ConnGRPC.Pool do
  use Supervisor

  alias ConnGRPC.Channel

  defmacro __using__(use_opts \\ []) do
    quote do
      def get_channel, do: ConnGRPC.Pool.get_channel(__MODULE__)

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

  def get_channel(pool_name) do
    channels = Registry.lookup(registry(pool_name), :channels)
    pool_size = length(channels)

    if pool_size > 0 do
      do_get_channel(pool_name, channels, pool_size)
    else
      {:error, :not_connected}
    end
  end

  defp do_get_channel(pool_name, channels, pool_size) do
    index =
      :ets.update_counter(
        ets_table(pool_name),
        :index,
        {_pos = 2, _incr = 1, _threshold = pool_size - 1, _reset = 0}
      )

    {pid, _} = Enum.at(channels, index)

    Channel.get(pid)
  end

  @impl true
  def init(opts) do
    pool_name = Keyword.fetch!(opts, :name)
    pool_size = Keyword.fetch!(opts, :pool_size)
    channel_opts = Keyword.fetch!(opts, :channel)
    registry_name = registry(pool_name)

    build_ets_table(pool_name)

    children = [
      {Registry, name: registry_name, keys: :duplicate},
      build_channels_supervisor_spec(pool_size, channel_opts, registry_name)
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp build_channels_supervisor_spec(pool_size, channel_opts, registry_name) do
    channel_opts =
      channel_opts
      |> Keyword.put(:on_connect, fn -> Registry.register(registry_name, :channels, nil) end)
      |> Keyword.put(:on_disconnect, fn -> Registry.unregister(registry_name, :channels) end)

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

  defp ets_table(pool_name) do
    :"#{pool_name}.ETS"
  end

  defp registry(pool_name) do
    :"#{pool_name}.Registry"
  end
end
