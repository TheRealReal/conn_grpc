defmodule ConnGRPC.Backoff do
  @moduledoc "Behaviour for implementing custom backoff."

  @doc "Initializes the backoff state. This is called when the channel process is started."
  @callback new(opts :: any) :: state :: any

  @doc """
  Generate backoff delay and new state.
  This is called each time that we fail to connect.
  """
  @callback backoff(state :: any) :: {delay :: non_neg_integer, state :: any}

  @doc "Reset backoff state. This is called when connecting succeeds."
  @callback reset(state :: any) :: state :: any
end
