defmodule ConnGRPCTest do
  use ExUnit.Case
  doctest ConnGRPC

  test "greets the world" do
    assert ConnGRPC.hello() == :world
  end
end
