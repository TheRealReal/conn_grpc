defmodule FakeGRPC do
  defmodule Channel do
    defstruct []
  end

  defmodule SuccessStub do
    def connect(_address, _opts), do: {:ok, %FakeGRPC.Channel{}}
  end

  defmodule ErrorStub do
    def connect(_address, _opts), do: {:error, "reason"}
  end
end
