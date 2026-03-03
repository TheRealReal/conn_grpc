defmodule ConnGRPC.PoolTest do
  use ExUnit.Case, async: true

  alias ConnGRPC.Pool

  setup do
    Process.register(self(), :pool_test)

    {:ok, pool_name: :"test_pool_#{inspect(self())}"}
  end

  setup_all do
    TelemetryHelper.setup_telemetry(:pool_test, [
      [:conn_grpc, :pool, :status],
      [:conn_grpc, :pool, :get_channel]
    ])
  end

  describe "start_link/1" do
    test "starts the process successfully", %{pool_name: pool_name} do
      assert {:ok, _} =
               Pool.start_link(
                 name: pool_name,
                 pool_size: 5,
                 channel: [address: "address", opts: [adapter: GRPC.Client.TestAdapters.Success]]
               )
    end

    test "names the process when `name` option is passed" do
      assert {:ok, pid} =
               Pool.start_link(
                 name: :test_pool,
                 pool_size: 5,
                 channel: [address: "address", opts: [adapter: GRPC.Client.TestAdapters.Success]]
               )

      assert Process.whereis(:test_pool) == pid
    end
  end

  describe "get_channel/1" do
    test "returns {:ok, channel} using round-robin", %{pool_name: pool_name} do
      {:ok, _} =
        Pool.start_link(
          name: pool_name,
          pool_size: 3,
          channel: [address: "address", opts: [adapter: GRPC.Client.TestAdapters.Success]]
        )

      :timer.sleep(100)

      assert {:ok, %GRPC.Channel{} = channel1} = Pool.get_channel(pool_name)
      assert {:ok, %GRPC.Channel{} = channel2} = Pool.get_channel(pool_name)
      assert {:ok, %GRPC.Channel{} = channel3} = Pool.get_channel(pool_name)
      assert {:ok, %GRPC.Channel{} = ^channel1} = Pool.get_channel(pool_name)
      assert {:ok, %GRPC.Channel{} = ^channel2} = Pool.get_channel(pool_name)
      assert {:ok, %GRPC.Channel{} = ^channel3} = Pool.get_channel(pool_name)

      refute channel1 == channel2
      refute channel2 == channel3
    end

    test "returns {:error, :not_connected} when there is no connected channel", %{
      pool_name: pool_name
    } do
      {:ok, _} =
        Pool.start_link(
          name: pool_name,
          pool_size: 3,
          channel: [address: "address", opts: [adapter: GRPC.Client.TestAdapters.Error]]
        )

      :timer.sleep(100)

      assert {:error, :not_connected} = Pool.get_channel(pool_name)
    end

    test "returns {:error, :not_connected} when address is nil", %{
      pool_name: pool_name
    } do
      {:ok, _} =
        Pool.start_link(
          name: pool_name,
          pool_size: 3,
          channel: [address: nil, opts: [adapter: GRPC.Client.TestAdapters.Error]]
        )

      :timer.sleep(100)

      assert {:error, :not_connected} = Pool.get_channel(pool_name)
    end

    test "does not return disconnected channel", %{pool_name: pool_name} do
      {:ok, _} =
        Pool.start_link(
          name: pool_name,
          pool_size: 3,
          channel: [address: "address", opts: [adapter: GRPC.Client.TestAdapters.Success]],
          backoff_module: ConnGRPC.Backoff.NoRetry
        )

      :timer.sleep(100)

      # Simulate disconnect
      pids = Pool.get_all_pids(pool_name)
      Enum.at(pids, 1) |> send_disconnect_msg()
      :timer.sleep(100)

      # It won't reconnect because we're using `ConnGRPC.Backoff.NoRetry`

      assert {:ok, %GRPC.Channel{} = channel1} = Pool.get_channel(pool_name)
      assert {:ok, %GRPC.Channel{} = channel2} = Pool.get_channel(pool_name)
      assert {:ok, %GRPC.Channel{} = ^channel1} = Pool.get_channel(pool_name)
      assert {:ok, %GRPC.Channel{} = ^channel2} = Pool.get_channel(pool_name)

      refute channel1 == channel2
    end

    test "returns reconnected channel", %{pool_name: pool_name} do
      {:ok, _} =
        Pool.start_link(
          name: pool_name,
          pool_size: 3,
          channel: [
            address: "address",
            opts: [adapter: GRPC.Client.TestAdapters.Success],
            backoff_module: ConnGRPC.Backoff.Immediate
          ]
        )

      :timer.sleep(100)

      # Simulate disconnect
      pids = Pool.get_all_pids(pool_name)
      Enum.at(pids, 1) |> send_disconnect_msg()

      # It will quickly reconnect because we're using `ConnGRPC.Backoff.Immediate` and the channel is up
      :timer.sleep(100)

      assert {:ok, %GRPC.Channel{} = channel1} = Pool.get_channel(pool_name)
      assert {:ok, %GRPC.Channel{} = channel2} = Pool.get_channel(pool_name)
      assert {:ok, %GRPC.Channel{} = channel3} = Pool.get_channel(pool_name)

      refute channel1 == channel2
      refute channel2 == channel3
    end

    test "executes telemetry on success", %{pool_name: pool_name} do
      {:ok, _} =
        Pool.start_link(
          name: pool_name,
          pool_size: 3,
          channel: [address: "address", opts: [adapter: GRPC.Client.TestAdapters.Success]]
        )

      :timer.sleep(100)

      {:ok, _} = Pool.get_channel(pool_name)

      assert_receive {
        :telemetry_executed,
        _event = [:conn_grpc, :pool, :get_channel],
        _measurements = %{duration: _},
        _metadata = %{pool_name: ^pool_name}
      }
    end

    test "executes telemetry on error", %{pool_name: pool_name} do
      {:ok, _} =
        Pool.start_link(
          name: pool_name,
          pool_size: 3,
          channel: [address: "address", opts: [adapter: GRPC.Client.TestAdapters.Error]]
        )

      :timer.sleep(100)

      {:error, _} = Pool.get_channel(pool_name)

      assert_receive {
        :telemetry_executed,
        _event = [:conn_grpc, :pool, :get_channel],
        _measurements = %{duration: _},
        _metadata = %{pool_name: ^pool_name}
      }
    end
  end

  describe "get_channel!/1" do
    test "returns channel when connected", %{pool_name: pool_name} do
      {:ok, _} =
        Pool.start_link(
          name: pool_name,
          pool_size: 3,
          channel: [address: "address", opts: [adapter: GRPC.Client.TestAdapters.Success]]
        )

      :timer.sleep(100)

      assert %GRPC.Channel{} = Pool.get_channel!(pool_name)
    end

    test "raises ConnectionError with reason and pool_name when not connected", %{
      pool_name: pool_name
    } do
      {:ok, _} =
        Pool.start_link(
          name: pool_name,
          pool_size: 3,
          channel: [address: "address", opts: [adapter: GRPC.Client.TestAdapters.Error]]
        )

      :timer.sleep(100)

      error =
        assert_raise ConnGRPC.ConnectionError, fn ->
          Pool.get_channel!(pool_name)
        end

      assert error.reason == :not_connected
      assert error.pool_name == pool_name

      assert Exception.message(error) ==
               "failed to get gRPC channel from pool #{inspect(pool_name)}: :not_connected"
    end
  end

  describe "get_all_pids/1" do
    test "returns list of pids", %{pool_name: pool_name} do
      {:ok, _} =
        Pool.start_link(
          name: pool_name,
          pool_size: 5,
          channel: [address: "address", opts: [adapter: GRPC.Client.TestAdapters.Success]]
        )

      :timer.sleep(100)

      result = Pool.get_all_pids(pool_name)
      assert length(result) == 5
      assert Enum.all?(result, &is_pid/1)
    end

    test "does not return pid of disconnected channel", %{pool_name: pool_name} do
      {:ok, _} =
        Pool.start_link(
          name: pool_name,
          pool_size: 5,
          channel: [
            address: "address",
            opts: [adapter: GRPC.Client.TestAdapters.Success],
            backoff_module: ConnGRPC.Backoff.NoRetry
          ]
        )

      :timer.sleep(100)

      # Simulate disconnect
      pids = Pool.get_all_pids(pool_name)
      disconnected_pid = Enum.at(pids, 1)
      send_disconnect_msg(disconnected_pid)

      # It won't reconnect because we're using `ConnGRPC.Backoff.NoRetry`
      :timer.sleep(100)

      result = Pool.get_all_pids(pool_name)
      assert length(result) == 4
      assert Enum.all?(result, &is_pid/1)
      refute disconnected_pid in result
    end

    test "returns pid of reconnected channel", %{pool_name: pool_name} do
      {:ok, _} =
        Pool.start_link(
          name: pool_name,
          pool_size: 5,
          channel: [
            address: "address",
            opts: [adapter: GRPC.Client.TestAdapters.Success],
            backoff_module: ConnGRPC.Backoff.Immediate
          ]
        )

      :timer.sleep(100)

      # Simulate disconnect
      pids = Pool.get_all_pids(pool_name)
      Enum.at(pids, 1) |> send_disconnect_msg()
      :timer.sleep(100)

      # It will quickly reconnect because we're using `ConnGRPC.Backoff.Immediate` and the channel is up
      :timer.sleep(100)

      result = Pool.get_all_pids(pool_name)
      assert length(result) == 5
      assert Enum.all?(result, &is_pid/1)
    end

    test "does not return any pid when pool_size is 0", %{pool_name: pool_name} do
      {:ok, _} =
        Pool.start_link(
          name: pool_name,
          pool_size: 0,
          channel: [
            address: "address",
            opts: [adapter: GRPC.Client.TestAdapters.Success]
          ]
        )

      :timer.sleep(100)

      assert Pool.get_all_pids(pool_name) == []
    end
  end

  describe "[:conn_grpc, :pool, :status] telemetry event" do
    test "is sent periodically", %{pool_name: pool_name} do
      assert {:ok, _} =
               Pool.start_link(
                 name: pool_name,
                 pool_size: 5,
                 channel: [address: "address", opts: [adapter: GRPC.Client.TestAdapters.Success]],
                 telemetry_interval: 25
               )

      for _ <- 1..2 do
        assert_receive {
          :telemetry_executed,
          _event = [:conn_grpc, :pool, :status],
          _measurements = %{expected_size: 5, current_size: 5},
          _metadata = %{pool_name: ^pool_name}
        }
      end
    end

    test "reports current size correctly", %{pool_name: pool_name} do
      assert {:ok, _} =
               Pool.start_link(
                 name: pool_name,
                 pool_size: 5,
                 channel: [address: "address", opts: [adapter: GRPC.Client.TestAdapters.Error]],
                 telemetry_interval: 25
               )

      for _ <- 1..2 do
        assert_receive {
          :telemetry_executed,
          _event = [:conn_grpc, :pool, :status],
          _measurements = %{expected_size: 5, current_size: 0},
          _metadata = %{pool_name: ^pool_name}
        }
      end
    end
  end

  describe "on_connect and on_disconnect callbacks" do
    test "calls user-provided on_connect when channel connects", %{pool_name: pool_name} do
      test_pid = self()

      Pool.start_link(
        name: pool_name,
        pool_size: 2,
        channel: [
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Success],
          on_connect: fn -> send(test_pid, :user_on_connect) end
        ]
      )

      :timer.sleep(100)

      assert_received :user_on_connect
      assert_received :user_on_connect
    end

    test "calls user-provided on_disconnect when channel disconnects", %{pool_name: pool_name} do
      test_pid = self()

      Pool.start_link(
        name: pool_name,
        pool_size: 2,
        channel: [
          address: "address",
          opts: [adapter: GRPC.Client.TestAdapters.Success],
          backoff_module: ConnGRPC.Backoff.NoRetry,
          on_disconnect: fn -> send(test_pid, :user_on_disconnect) end
        ]
      )

      :timer.sleep(100)

      pids = Pool.get_all_pids(pool_name)
      Enum.each(pids, &send_disconnect_msg/1)

      :timer.sleep(100)

      assert_received :user_on_disconnect
      assert_received :user_on_disconnect
    end
  end

  describe "__using__" do
    test "allows defining pool as a module" do
      defmodule UsingTestPool do
        use ConnGRPC.Pool,
          pool_size: 3,
          channel: [
            address: "address",
            opts: [adapter: GRPC.Client.TestAdapters.Success]
          ]
      end

      Supervisor.start_link([UsingTestPool], strategy: :one_for_one)

      assert is_pid(Process.whereis(UsingTestPool))

      :timer.sleep(100)

      assert {:ok, %GRPC.Channel{}} = UsingTestPool.get_channel()
      assert %GRPC.Channel{} = UsingTestPool.get_channel!()
      assert is_list(UsingTestPool.get_all_pids())
    end

    test "loads configuration from Application.get_env when otp_app is specified" do
      defmodule UsingTestPoolWithConfig do
        use ConnGRPC.Pool, otp_app: :test_app
      end

      Application.put_env(:test_app, UsingTestPoolWithConfig,
        pool_size: 2,
        channel: [address: "test_address", opts: [adapter: GRPC.Client.TestAdapters.Success]]
      )

      child_spec = UsingTestPoolWithConfig.child_spec([])
      {_module, _function, [opts]} = child_spec.start

      assert opts[:pool_size] == 2
      assert opts[:channel][:address] == "test_address"
      assert opts[:name] == UsingTestPoolWithConfig

      Application.delete_env(:test_app, UsingTestPoolWithConfig)
    end

    test "merges Application.get_env config with child_spec opts" do
      defmodule UsingTestPoolWithMerge do
        use ConnGRPC.Pool, otp_app: :test_app
      end

      Application.put_env(:test_app, UsingTestPoolWithMerge,
        pool_size: 2,
        channel: [address: "test_address", opts: [adapter: GRPC.Client.TestAdapters.Success]]
      )

      child_spec = UsingTestPoolWithMerge.child_spec(pool_size: 3)
      {_module, _function, [opts]} = child_spec.start

      assert Keyword.get(opts, :pool_size) == 3

      Application.delete_env(:test_app, UsingTestPoolWithMerge)
    end
  end

  defp send_disconnect_msg(pid), do: send(pid, {:gun_down, fake_pid(), :http2, :normal, []})

  defp fake_pid, do: :erlang.list_to_pid(~c"<0.123.456>")
end
