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
    def init(opts) do
      Agent.start_link(fn -> %{success: opts[:success]} end, name: __MODULE__)
    end

    def set_success(success) do
      Agent.update(__MODULE__, fn _ -> %{success: success} end)
    end

    def connect(channel, _opts) do
      case Agent.get(__MODULE__, & &1) do
        %{success: true} -> {:ok, %{channel | adapter_payload: %{ref: make_ref()}}}
        %{success: false} -> {:error, "reason"}
      end
    end

    def disconnect(channel), do: {:ok, %{channel | adapter_payload: nil}}
  end
end
