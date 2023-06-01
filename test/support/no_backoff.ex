defmodule ConnGRPC.Backoff.NoBackoff do
  @behaviour ConnGRPC.Backoff

  @impl true
  def new(_), do: :no_state

  @impl true
  def backoff(_), do: {1, :no_state}

  @impl true
  def reset(_), do: :no_state
end
