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
      assert is_list(UsingTestPool.get_all_pids())
    end
  end

  defp send_disconnect_msg(pid), do: send(pid, {:gun_down, fake_pid(), :http2, :normal, []})

  defp fake_pid, do: :erlang.list_to_pid('<0.123.456>')
end
