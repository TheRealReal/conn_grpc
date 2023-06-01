defmodule GRPC.Client.TestAdapter do
  def connect(channel, _) do
    if up?() do
      {:ok, %{channel | adapter_payload: %{ref: make_ref()}}}
    else
      {:error, "Server is down"}
    end
  end

  def disconnect(channel) do
    {:ok, %{channel | adapter_payload: nil}}
  end

  # Test helpers

  def start_link do
    Agent.start_link(fn -> :up end, name: __MODULE__)
  end

  def up do
    Agent.update(__MODULE__, fn _ -> :up end)
  end

  def down do
    Agent.update(__MODULE__, fn _ -> :down end)
  end

  def up? do
    Agent.get(__MODULE__, & &1) == :up
  end
end
