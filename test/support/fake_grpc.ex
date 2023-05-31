defmodule FakeGRPC do
  defmodule Channel do
    defstruct [ref: nil]
  end

  defmodule SuccessStub do
    def connect(_address, _opts), do: {:ok, %FakeGRPC.Channel{ref: make_ref()}}
  end

  defmodule ErrorStub do
    def connect(_address, _opts), do: {:error, "reason"}
  end
end
