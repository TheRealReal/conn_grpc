defmodule ConnGRPC.Backoff do
  @moduledoc false

  @callback new(opts :: any) :: (state :: any)
  @callback backoff(state :: any) :: {non_neg_integer, state :: any}
  @callback reset(state :: any) :: (state :: any)
end
