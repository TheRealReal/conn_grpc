defmodule ConnGRPC.ChannelTest do
  use ExUnit.Case, async: true

  alias ConnGRPC.Channel

  setup do
    Process.register(self(), :test)
    :ok
  end

  describe "start_link/1" do
    test "starts the process successfully" do
      assert {:ok, _pid} = Channel.start_link(
        grpc_stub: FakeGRPC.SuccessStub,
        address: "address"
      )
    end

    test "names the process when `name` option is passed" do
      assert {:ok, pid} = Channel.start_link(
        grpc_stub: FakeGRPC.SuccessStub,
        address: "address",
        name: :test_channel
      )

      assert Process.whereis(:test_channel) == pid
    end
  end

  describe "Connection" do
    test "calls grpc_stub.connect/2 with address and options" do
      defmodule CallArgsTest do
        def connect(address, opts) do
          send(:test, {:called, address, opts})
          {:ok, %FakeGRPC.Channel{}}
        end
      end

      {:ok, _pid} = Channel.start_link(
        grpc_stub: CallArgsTest,
        address: "address",
        opts: [headers: [foo: "bar"]]
      )

      assert_receive {:called, "address", [headers: [foo: "bar"]]}
    end

    test "calls on_connect when connection succeeds" do
      {:ok, _pid} = Channel.start_link(
        grpc_stub: FakeGRPC.SuccessStub,
        address: "address",
        on_connect: fn -> send(:test, :connect_called) end,
        on_disconnect: fn -> send(:test, :disconnect_called) end
      )

      assert_receive :connect_called
      refute_receive :connect_called
    end

    test "does not call connection callbacks when connection does not succeed" do
      {:ok, _pid} = Channel.start_link(
        grpc_stub: FakeGRPC.ErrorStub,
        address: "address",
        on_connect: fn -> send(:test, :connect_called) end,
        on_disconnect: fn -> send(:test, :disconnect_called) end
      )

      refute_receive :connect_called
      refute_receive :connect_called
    end

    test "calls on_disconnect when gun disconnects" do
      {:ok, channel_pid} = Channel.start_link(
        grpc_stub: FakeGRPC.SuccessStub,
        address: "address",
        on_connect: fn -> send(:test, :connect_called) end,
        on_disconnect: fn -> send(:test, :disconnect_called) end
      )

      assert_receive :connect_called

      send(channel_pid, {:gun_down, :erlang.list_to_pid('<0.123.456>'), :http2, :normal, []})

      assert_receive :disconnect_called
    end

    test "calls on_connect when gun reconnects" do
      {:ok, channel_pid} = Channel.start_link(
        grpc_stub: FakeGRPC.SuccessStub,
        address: "address",
        on_connect: fn -> send(:test, :connect_called) end,
        on_disconnect: fn -> send(:test, :disconnect_called) end
      )

      assert_receive :connect_called

      send(channel_pid, {:gun_up, :erlang.list_to_pid('<0.123.456>'), :http2})

      assert_receive :connect_called
    end
  end

  describe "Retry and backoff" do
    defmodule FakeBackoff do
      @behaviour ConnGRPC.Backoff

      @impl true
      def new(arg) do
        send(:test, {FakeBackoff, :new_called, arg})
        {:backoff_state, 1}
      end

      @impl true
      def backoff({:backoff_state, n} = arg) do
        send(:test, {FakeBackoff, :backoff_called, arg})
        {n, {:backoff_state, n + 1}}
      end

      @impl true
      def reset({:backoff_state, _} = arg) do
        send(:test, {FakeBackoff, :reset_called, arg})
        {:backoff_state, 1}
      end
    end

    test "inits backoff state on start" do
      {:ok, _} =
        Channel.start_link(
          grpc_stub: FakeGRPC.SuccessStub,
          backoff_module: FakeBackoff,
          backoff: [min: 500, max: 15_000],
          address: "address"
        )

      assert_receive {FakeBackoff, :new_called, [min: 500, max: 15_000]}
    end

    test "uses default opts when not specified" do
      {:ok, _} =
        Channel.start_link(
          grpc_stub: FakeGRPC.SuccessStub,
          backoff_module: FakeBackoff,
          address: "address"
        )

      assert_receive {FakeBackoff, :new_called, [min: 1000, max: 30_000]}
    end

    test "retries on every failed attempt and updates backoff state" do
      {:ok, _} =
        Channel.start_link(
          grpc_stub: FakeGRPC.ErrorStub,
          backoff_module: FakeBackoff,
          address: "address"
        )

      assert_receive {FakeBackoff, :new_called, _}
      assert_receive {FakeBackoff, :backoff_called, {:backoff_state, 1}}
      assert_receive {FakeBackoff, :backoff_called, {:backoff_state, 2}}
      assert_receive {FakeBackoff, :backoff_called, {:backoff_state, 3}}
    end

    test "resets backoff state on success" do
      FakeGRPC.StatefulStub.init(success: false)

      {:ok, _} =
        Channel.start_link(
          grpc_stub: FakeGRPC.StatefulStub,
          backoff_module: FakeBackoff,
          address: "address"
        )

      assert_receive {FakeBackoff, :new_called, _}
      assert_receive {FakeBackoff, :backoff_called, {:backoff_state, 1}}
      assert_receive {FakeBackoff, :backoff_called, {:backoff_state, 2}}
      assert_receive {FakeBackoff, :backoff_called, {:backoff_state, 3}}

      FakeGRPC.StatefulStub.set_success(true)
      assert_receive {FakeBackoff, :reset_called, {:backoff_state, _}}
    end
  end

  describe "get/1" do
    test "returns {:ok, channel} when it is able to connect" do
      {:ok, channel_pid} = Channel.start_link(
        grpc_stub: FakeGRPC.SuccessStub,
        address: "address"
      )

      assert {:ok, %FakeGRPC.Channel{}} = Channel.get(channel_pid)
    end

    test "returns {:error, :not_connected} when it is not able to connect" do
      {:ok, channel_pid} = Channel.start_link(
        grpc_stub: FakeGRPC.ErrorStub,
        address: "address"
      )

      assert {:error, :not_connected} = Channel.get(channel_pid)
    end
  end

  describe "__using__" do
    test "allows defining channel as a module" do
      defmodule UsingTestChannel do
        use ConnGRPC.Channel, address: "address", grpc_stub: FakeGRPC.SuccessStub
      end

      Supervisor.start_link([UsingTestChannel], strategy: :one_for_one)

      assert is_pid(Process.whereis(UsingTestChannel))

      assert {:ok, %FakeGRPC.Channel{}} = UsingTestChannel.get()
    end
  end
end
