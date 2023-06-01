defmodule ConnGRPC.Backoff.ExponentialTest do
  use ExUnit.Case, async: true

  alias ConnGRPC.Backoff.Exponential

  @backoff_opts [min: 1000, max: 30_000]

  test "backoffs always in [min, max]" do
    backoff = Exponential.new(@backoff_opts)
    {delays, _} = backoff(backoff, 20)

    assert Enum.all?(delays, fn delay ->
             delay >= @backoff_opts[:min] and delay <= @backoff_opts[:max]
           end)
  end

  test "backoffs increase until a third of max" do
    backoff = Exponential.new(@backoff_opts)
    {delays, _} = backoff(backoff, 20)

    Enum.reduce(delays, fn next, prev ->
      assert next >= prev or next >= div(@backoff_opts[:max], 3)
      next
    end)
  end

  test "backoffs reset in [min, min * 3]" do
    backoff = Exponential.new(@backoff_opts)
    {[delay | _], backoff} = backoff(backoff, 20)
    assert delay in @backoff_opts[:min]..@backoff_opts[:max]

    backoff = Exponential.reset(backoff)
    {[delay], _} = backoff(backoff, 1)
    assert delay in @backoff_opts[:min]..(@backoff_opts[:max] * 3)
  end

  defp backoff(backoff, n) do
    Enum.map_reduce(1..n, backoff, fn _, acc -> Exponential.backoff(acc) end)
  end
end
