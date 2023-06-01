defmodule GRPC.Client.TestAdapters do
  @moduledoc false

  # gRPC adapter that always succeeds to connect
  defmodule Success do
    @moduledoc false

    def connect(channel, _opts) do
      {:ok, %{channel | adapter_payload: %{ref: make_ref()}}}
    end

    def disconnect(channel), do: {:ok, %{channel | adapter_payload: nil}}
  end

  # gRPC adapter that always fails to connect
  defmodule Error do
    @moduledoc false

    def connect(_channel, _opts) do
      {:error, "down"}
    end

    def disconnect(channel), do: {:ok, %{channel | adapter_payload: nil}}
  end

  # gRPC adapter that succeeds or fails to connect based on current state.
  #
  # Usage:
  #
  # {:ok, _} = GRPC.Client.TestAdapters.Stateful.start_link(:up)                       # start in online mode
  #
  # {:ok, %GRPC.Channel{}} = GRPC.Client.TestAdapters.Stateful.connect("address", [])  # connects
  #
  # GRPC.Client.TestAdapters.Stateful.down()                                           # make it offline
  #
  # {:error, "down"} = GRPC.Client.TestAdapters.Stateful.connect("address", [])        # doesn't connect
  #
  # GRPC.Client.TestAdapters.Stateful.up()                                             # make it online
  #
  # {:ok, %GRPC.Channel{}} = GRPC.Client.TestAdapters.Stateful.connect("address", [])  # connects
  defmodule Stateful do
    @moduledoc false

    def start_link(state) when state in [:up, :down] do
      Agent.start_link(fn -> state end, name: __MODULE__)
    end

    def up do
      Agent.update(__MODULE__, fn _ -> :up end)
    end

    def down do
      Agent.update(__MODULE__, fn _ -> :down end)
    end

    def connect(channel, _opts) do
      case Agent.get(__MODULE__, & &1) do
        :up -> {:ok, %{channel | adapter_payload: %{ref: make_ref()}}}
        :down -> {:error, "down"}
      end
    end

    def disconnect(channel), do: {:ok, %{channel | adapter_payload: nil}}
  end
end
