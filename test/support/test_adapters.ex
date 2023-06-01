defmodule GRPC.Client.TestAdapters do
  defmodule Success do
    def connect(channel, _opts) do
      {:ok, %{channel | adapter_payload: %{ref: make_ref()}}}
    end

    def disconnect(channel), do: {:ok, %{channel | adapter_payload: nil}}
  end

  defmodule Error do
    def connect(channel, _opts) do
      {:error, "reason"}
    end

    def disconnect(channel), do: {:ok, %{channel | adapter_payload: nil}}
  end

  defmodule Stateful do
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
        :down -> {:error, "reason"}
      end
    end

    def disconnect(channel), do: {:ok, %{channel | adapter_payload: nil}}
  end
end
