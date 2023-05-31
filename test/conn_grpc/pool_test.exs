defmodule ConnGRPC.PoolTest do
  use ExUnit.Case, async: true

  alias ConnGRPC.Pool

  setup do
    pool_name = :"test_pool_#{inspect(self())}"
    {:ok, pool_name: pool_name}
  end

  describe "start_link/1" do
    test "starts the process successfully", %{pool_name: pool_name} do
      assert {:ok, _} = Pool.start_link(
        name: pool_name,
        pool_size: 5,
        channel: [grpc_stub: FakeGRPC.SuccessStub, address: "address"]
      )
    end

    test "names the process when `name` option is passed" do
      assert {:ok, pid} = Pool.start_link(
        name: :test_pool,
        pool_size: 5,
        channel: [grpc_stub: FakeGRPC.SuccessStub, address: "address"]
      )

      assert Process.whereis(:test_pool) == pid
    end
  end

  describe "get_channel/1" do
    test "returns {:ok, channel} using round-robin", %{pool_name: pool_name} do
      {:ok, _} = Pool.start_link(
        name: pool_name,
        pool_size: 3,
        channel: [grpc_stub: FakeGRPC.SuccessStub, address: "address"]
      )

      :timer.sleep(100)

      assert {:ok, %FakeGRPC.Channel{} = channel1} = Pool.get_channel(pool_name)
      assert {:ok, %FakeGRPC.Channel{} = channel2} = Pool.get_channel(pool_name)
      assert {:ok, %FakeGRPC.Channel{} = channel3} = Pool.get_channel(pool_name)
      assert {:ok, %FakeGRPC.Channel{} = ^channel1} = Pool.get_channel(pool_name)
      assert {:ok, %FakeGRPC.Channel{} = ^channel2} = Pool.get_channel(pool_name)
      assert {:ok, %FakeGRPC.Channel{} = ^channel3} = Pool.get_channel(pool_name)

      refute channel1 == channel2
      refute channel2 == channel3
    end

    test "returns {:error, :not_connected} when there is no connected channel", %{pool_name: pool_name} do
      {:ok, _} = Pool.start_link(
        name: pool_name,
        pool_size: 3,
        channel: [grpc_stub: FakeGRPC.ErrorStub, address: "address"]
      )

      :timer.sleep(100)

      assert {:error, :not_connected} = Pool.get_channel(pool_name)
    end

    test "does not return disconnected channel", %{pool_name: pool_name} do
      {:ok, _} = Pool.start_link(
        name: pool_name,
        pool_size: 3,
        channel: [grpc_stub: FakeGRPC.SuccessStub, address: "address"]
      )

      :timer.sleep(100)

      # Simulate disconnect
      pids = Pool.get_all_pids(pool_name)
      Enum.at(pids, 1) |> simulate_disconnect()
      :timer.sleep(100)

      assert {:ok, %FakeGRPC.Channel{} = channel1} = Pool.get_channel(pool_name)
      assert {:ok, %FakeGRPC.Channel{} = channel2} = Pool.get_channel(pool_name)
      assert {:ok, %FakeGRPC.Channel{} = ^channel1} = Pool.get_channel(pool_name)
      assert {:ok, %FakeGRPC.Channel{} = ^channel2} = Pool.get_channel(pool_name)

      refute channel1 == channel2
    end

    test "returns reconnected channel", %{pool_name: pool_name} do
      {:ok, _} = Pool.start_link(
        name: pool_name,
        pool_size: 3,
        channel: [grpc_stub: FakeGRPC.SuccessStub, address: "address"]
      )

      :timer.sleep(100)

      # Simulate disconnect
      pids = Pool.get_all_pids(pool_name)
      Enum.at(pids, 1) |> simulate_disconnect()
      :timer.sleep(100)

      # Simulate reconnect
      Enum.at(pids, 1) |> simulate_connect()
      :timer.sleep(100)

      assert {:ok, %FakeGRPC.Channel{} = channel1} = Pool.get_channel(pool_name)
      assert {:ok, %FakeGRPC.Channel{} = channel2} = Pool.get_channel(pool_name)
      assert {:ok, %FakeGRPC.Channel{} = channel3} = Pool.get_channel(pool_name)
      assert {:ok, %FakeGRPC.Channel{} = ^channel1} = Pool.get_channel(pool_name)
      assert {:ok, %FakeGRPC.Channel{} = ^channel2} = Pool.get_channel(pool_name)
      assert {:ok, %FakeGRPC.Channel{} = ^channel3} = Pool.get_channel(pool_name)

      refute channel1 == channel2
      refute channel2 == channel3
    end
  end

  describe "get_all_pids/1" do
    test "returns list of pids", %{pool_name: pool_name} do
      {:ok, _} = Pool.start_link(
        name: pool_name,
        pool_size: 5,
        channel: [grpc_stub: FakeGRPC.SuccessStub, address: "address"]
      )

      :timer.sleep(100)

      result = Pool.get_all_pids(pool_name)
      assert length(result) == 5
      assert Enum.all?(result, &is_pid/1)
    end

    test "does not return pid of disconnected channel", %{pool_name: pool_name} do
      {:ok, _} = Pool.start_link(
        name: pool_name,
        pool_size: 5,
        channel: [grpc_stub: FakeGRPC.SuccessStub, address: "address"]
      )

      :timer.sleep(100)

      # Simulate disconnect
      pids = Pool.get_all_pids(pool_name)
      disconnected_pid = Enum.at(pids, 1)
      simulate_disconnect(disconnected_pid)
      :timer.sleep(100)

      result = Pool.get_all_pids(pool_name)
      assert length(result) == 4
      assert Enum.all?(result, &is_pid/1)
      refute disconnected_pid in result
    end

    test "returns pid of reconnected channel", %{pool_name: pool_name} do
      {:ok, _} = Pool.start_link(
        name: pool_name,
        pool_size: 5,
        channel: [grpc_stub: FakeGRPC.SuccessStub, address: "address"]
      )

      :timer.sleep(100)

      # Simulate disconnect
      pids = Pool.get_all_pids(pool_name)
      Enum.at(pids, 1) |> simulate_disconnect()
      :timer.sleep(100)

      # Simulate connect
      Enum.at(pids, 1) |> simulate_connect()
      :timer.sleep(100)

      result = Pool.get_all_pids(pool_name)
      assert length(result) == 5
      assert Enum.all?(result, &is_pid/1)
    end
  end

  describe "__using__" do
    test "allows defining pool as a module" do
      defmodule UsingTestPool do
        use ConnGRPC.Pool, pool_size: 3, channel: [address: "address", grpc_stub: FakeGRPC.SuccessStub]
      end

      Supervisor.start_link([UsingTestPool], strategy: :one_for_one)

      assert is_pid(Process.whereis(UsingTestPool))

      :timer.sleep(100)

      assert {:ok, %FakeGRPC.Channel{}} = UsingTestPool.get_channel()
      assert is_list(UsingTestPool.get_all_pids())
    end
  end

  defp simulate_connect(pid) do
    send(pid, {:gun_up, :erlang.list_to_pid('<0.123.456>'), :http2})
  end

  defp simulate_disconnect(pid) do
    send(pid, {:gun_down, :erlang.list_to_pid('<0.123.456>'), :http2, :normal, []})
  end
end
