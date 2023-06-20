defmodule ConnGRPC.ChannelTest do
  use ExUnit.Case, async: true

  alias ConnGRPC.Channel

  setup do
    Process.register(self(), :channel_test)
    :ok
  end

  setup_all do
    TelemetryHelper.setup_telemetry(:channel_test, [
      [:conn_grpc, :channel, :get],
      [:conn_grpc, :channel, :connected],
      [:conn_grpc, :channel, :connection_failed],
      [:conn_grpc, :channel, :disconnected]
    ])
  end

  describe "start_link/1" do
    test "starts the process successfully" do
      assert {:ok, _pid} =
               Channel.start_link(
                 address: "address",
                 opts: [adapter: GRPC.Client.TestAdapters.Success]
               )
    end

    test "names the process when `name` option is passed" do
      assert {:ok, pid} =
               Channel.start_link(
                 name: :test_channel,
                 address: "address",
                 opts: [adapter: GRPC.Client.TestAdapters.Success]
               )

      assert Process.whereis(:test_channel) == pid
    end
  end

  describe "Connection" do
    test "calls grpc_stub.connect/2 with address and options" do
      defmodule CallArgsTest do
        def connect(address, opts) do
          send(:channel_test, {CallArgsTest, :called_connect, address, opts})
          {:ok, %GRPC.Channel{}}
        end
      end

      {:ok, _pid} =
        Channel.start_link(
          grpc_stub: CallArgsTest,
          address: "address",
          opts: [headers: [foo: "bar"]]
        )

      assert_receive {CallArgsTest, :called_connect, "address", [headers: [foo: "bar"]]}
    end

    test "calls on_connect when connection succeeds" do
      {:ok, _pid} =
        Channel.start_link(
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Success],
          on_connect: fn -> send(:channel_test, :connect_called) end,
          on_disconnect: fn -> send(:channel_test, :disconnect_called) end
        )

      assert_receive :connect_called
      refute_receive :connect_called
    end

    test "executes telemetry when connection succeeds" do
      {:ok, _pid} =
        Channel.start_link(
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Success],
          name: :test_channel
        )

      assert_receive {
        :telemetry_executed,
        _event = [:conn_grpc, :channel, :connected],
        _measurements = %{duration: _},
        _metadata = %{channel_name: :test_channel}
      }
    end

    test "does not call connection callbacks when connection does not succeed" do
      {:ok, _pid} =
        Channel.start_link(
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Error],
          on_connect: fn -> send(:channel_test, :connect_called) end,
          on_disconnect: fn -> send(:channel_test, :disconnect_called) end
        )

      refute_receive :connect_called
      refute_receive :disconnect_called
    end

    test "executes telemetry when connection fails" do
      {:ok, _pid} =
        Channel.start_link(
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Error],
          name: :test_channel
        )

      assert_receive {
        :telemetry_executed,
        _event = [:conn_grpc, :channel, :connection_failed],
        _measurements = %{duration: _, error: _},
        _metadata = %{channel_name: :test_channel}
      }
    end

    test "does not call grpc_stub.connect/2 when receiving :connect from outside with a channel already open" do
      defmodule DuplicateConnectTest do
        def connect(address, opts) do
          send(:channel_test, {DuplicateConnectTest, :called_connect, address, opts})
          {:ok, %GRPC.Channel{}}
        end
      end

      {:ok, channel_pid} = Channel.start_link(grpc_stub: DuplicateConnectTest, address: "address")

      assert_receive {DuplicateConnectTest, :called_connect, _, _}

      send(channel_pid, :connect)

      refute_receive {DuplicateConnectTest, :called_connect, _, _}
    end
  end

  describe "Gun disconnect handling" do
    test "attempts to reconnect when receiving :gun_down tuple" do
      GRPC.Client.TestAdapters.Stateful.start_link(:up)

      {:ok, channel_pid} =
        Channel.start_link(
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Stateful],
          on_connect: fn -> send(:channel_test, :connect_called) end,
          on_disconnect: fn -> send(:channel_test, :disconnect_called) end,
          backoff_module: ConnGRPC.Backoff.Immediate
        )

      assert_receive :connect_called

      GRPC.Client.TestAdapters.Stateful.down()
      send(channel_pid, {:gun_down, fake_pid(), :http2, :normal, []})

      assert_receive :disconnect_called
      refute_receive :connect_called

      GRPC.Client.TestAdapters.Stateful.up()
      assert_receive :connect_called
    end

    test "executes telemetry" do
      {:ok, channel_pid} =
        Channel.start_link(
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Success],
          backoff_module: ConnGRPC.Backoff.NoRetry,
          name: :test_channel
        )

      send(channel_pid, {:gun_down, fake_pid(), :http2, :normal, []})

      assert_receive {
        :telemetry_executed,
        _event = [:conn_grpc, :channel, :disconnected],
        _measurements = %{duration: _},
        _metadata = %{channel_name: :test_channel}
      }
    end
  end

  describe "Mint disconnect handling" do
    test "attempts to reconnect when receiving :connection_down message" do
      GRPC.Client.TestAdapters.Stateful.start_link(:up)

      {:ok, channel_pid} =
        Channel.start_link(
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Stateful],
          on_connect: fn -> send(:channel_test, :connect_called) end,
          on_disconnect: fn -> send(:channel_test, :disconnect_called) end,
          backoff_module: ConnGRPC.Backoff.Immediate
        )

      assert_receive :connect_called

      GRPC.Client.TestAdapters.Stateful.down()
      send(channel_pid, {:EXIT, fake_pid(), %Mint.TransportError{reason: :econnrefused}})
      send(channel_pid, {:elixir_grpc, :connection_down, fake_pid()})

      assert_receive :disconnect_called
      refute_receive :connect_called

      GRPC.Client.TestAdapters.Stateful.up()
      assert_receive :connect_called
    end

    test "executes telemetry" do
      {:ok, channel_pid} =
        Channel.start_link(
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Success],
          backoff_module: ConnGRPC.Backoff.NoRetry,
          name: :test_channel
        )

      send(channel_pid, {:EXIT, fake_pid(), %Mint.TransportError{reason: :econnrefused}})
      send(channel_pid, {:elixir_grpc, :connection_down, fake_pid()})

      assert_receive {
        :telemetry_executed,
        _event = [:conn_grpc, :channel, :disconnected],
        _measurements = %{duration: _},
        _metadata = %{channel_name: :test_channel}
      }
    end
  end

  describe "Retry and backoff" do
    defmodule FakeBackoff do
      @behaviour ConnGRPC.Backoff

      @impl true
      def new(arg) do
        send(:channel_test, {FakeBackoff, :new_called, arg})
        {:backoff_state, 1}
      end

      @impl true
      def backoff({:backoff_state, n} = arg) do
        send(:channel_test, {FakeBackoff, :backoff_called, arg})
        {n, {:backoff_state, n + 1}}
      end

      @impl true
      def reset({:backoff_state, _} = arg) do
        send(:channel_test, {FakeBackoff, :reset_called, arg})
        {:backoff_state, 1}
      end
    end

    test "inits backoff state on start" do
      {:ok, _} =
        Channel.start_link(
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Success],
          backoff_module: FakeBackoff,
          backoff: [min: 500, max: 15_000]
        )

      assert_receive {FakeBackoff, :new_called, [min: 500, max: 15_000]}
    end

    test "uses default opts when not specified" do
      {:ok, _} =
        Channel.start_link(
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Success],
          backoff_module: FakeBackoff
        )

      assert_receive {FakeBackoff, :new_called, [min: 1000, max: 30_000]}
    end

    test "retries on every failed attempt and updates backoff state" do
      {:ok, _} =
        Channel.start_link(
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Error],
          backoff_module: FakeBackoff
        )

      assert_receive {FakeBackoff, :new_called, _}
      assert_receive {FakeBackoff, :backoff_called, {:backoff_state, 1}}
      assert_receive {FakeBackoff, :backoff_called, {:backoff_state, 2}}
      assert_receive {FakeBackoff, :backoff_called, {:backoff_state, 3}}
    end

    test "resets backoff state on success" do
      GRPC.Client.TestAdapters.Stateful.start_link(:down)

      {:ok, _} =
        Channel.start_link(
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Stateful],
          backoff_module: FakeBackoff
        )

      assert_receive {FakeBackoff, :new_called, _}
      assert_receive {FakeBackoff, :backoff_called, {:backoff_state, 1}}
      assert_receive {FakeBackoff, :backoff_called, {:backoff_state, 2}}
      assert_receive {FakeBackoff, :backoff_called, {:backoff_state, 3}}

      GRPC.Client.TestAdapters.Stateful.up()
      assert_receive {FakeBackoff, :reset_called, {:backoff_state, _}}
    end
  end

  describe "get/1" do
    test "returns {:ok, channel} when connection is up" do
      {:ok, channel_pid} =
        Channel.start_link(
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Success]
        )

      assert {:ok, %GRPC.Channel{}} = Channel.get(channel_pid)
    end

    test "executes telemetry when connection is up" do
      {:ok, _} =
        Channel.start_link(
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Success],
          name: :test_channel
        )

      {:ok, _} = Channel.get(:test_channel)

      assert_receive {
        :telemetry_executed,
        _event = [:conn_grpc, :channel, :get],
        _measurements = %{duration: _},
        _metadata = %{channel: :test_channel}
      }
    end

    test "returns {:error, :not_connected} when connection is down" do
      {:ok, channel_pid} =
        Channel.start_link(
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Error]
        )

      assert {:error, :not_connected} = Channel.get(channel_pid)
    end

    test "executes telemetry when connection is down" do
      {:ok, _} =
        Channel.start_link(
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Error],
          name: :test_channel
        )

      {:error, _} = Channel.get(:test_channel)

      assert_receive {
        :telemetry_executed,
        _event = [:conn_grpc, :channel, :get],
        _measurements = %{duration: _},
        _metadata = %{channel: :test_channel}
      }
    end

    test "uses mock when provided" do
      {:ok, channel_pid} =
        Channel.start_link(
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Success],
          mock: fn -> {:ok, %GRPC.Channel{adapter: :mock}} end
        )

      assert {:ok, %GRPC.Channel{adapter: :mock}} = Channel.get(channel_pid)
    end
  end

  describe "__using__" do
    test "allows defining channel as a module" do
      defmodule UsingTestChannel do
        use ConnGRPC.Channel,
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Success]
      end

      Supervisor.start_link([UsingTestChannel], strategy: :one_for_one)

      assert is_pid(Process.whereis(UsingTestChannel))

      assert {:ok, %GRPC.Channel{}} = UsingTestChannel.get()
    end
  end

  defp fake_pid, do: :erlang.list_to_pid('<0.123.456>')
end
