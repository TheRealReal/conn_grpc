defmodule ConnGrpcTest do
  use ExUnit.Case
  doctest ConnGrpc

  test "greets the world" do
    assert ConnGrpc.hello() == :world
  end
end
