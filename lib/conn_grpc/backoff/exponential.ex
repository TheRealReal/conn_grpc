defmodule ConnGRPC.Backoff.Exponential do
  @moduledoc """
  Exponential backoff with jitter.

  This is the default retry backoff mechanism used by ConnGRPC.
  """

  @behaviour ConnGRPC.Backoff

  @impl true
  def new(opts) do
    min = Keyword.fetch!(opts, :min)
    max = Keyword.fetch!(opts, :max)
    :backoff.init(min, max) |> :backoff.type(:jitter)
  end

  @impl true
  def backoff(state) do
    :backoff.fail(state)
  end

  @impl true
  def reset(state) do
    {_, state} = :backoff.succeed(state)
    state
  end
end
