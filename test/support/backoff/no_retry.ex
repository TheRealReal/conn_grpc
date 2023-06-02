defmodule ConnGRPC.Backoff.NoRetry do
  @moduledoc false

  @behaviour ConnGRPC.Backoff

  @impl true
  def new(_), do: :no_state

  @impl true
  def backoff(_), do: {:timer.hours(1000), :no_state}

  @impl true
  def reset(_), do: :no_state
end
