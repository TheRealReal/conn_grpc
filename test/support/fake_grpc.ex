defmodule FakeGRPC do
  defmodule Channel do
    defstruct ref: nil
  end

  defmodule SuccessStub do
    def connect(_address, _opts), do: {:ok, %FakeGRPC.Channel{ref: make_ref()}}
  end

  defmodule ErrorStub do
    def connect(_address, _opts), do: {:error, "reason"}
  end

  defmodule StatefulStub do
    def init(opts), do: Agent.start_link(fn -> %{success: opts[:success]} end, name: __MODULE__)

    def set_success(success), do: Agent.update(__MODULE__, fn _ -> %{success: success} end)

    def connect(_address, _opts) do
      %{success: success} = Agent.get(__MODULE__, & &1)

      if success do
        {:ok, %FakeGRPC.Channel{ref: make_ref()}}
      else
        {:error, "reason"}
      end
    end
  end
end
