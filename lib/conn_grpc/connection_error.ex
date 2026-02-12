defmodule ConnGRPC.ConnectionError do
  @moduledoc """
  Raised by `ConnGRPC.Pool.get_channel!/1` when a channel cannot be retrieved from the pool.
  """

  @typedoc """
  Connection error exception.

  ## Fields

    * `:reason` - The underlying error reason (e.g. `:not_connected`)
    * `:pool_name` - The name of the pool that failed to provide a channel
  """
  @type t :: %__MODULE__{
          reason: atom(),
          pool_name: module()
        }

  defexception [:reason, :pool_name]

  @impl true
  def message(%__MODULE__{reason: reason, pool_name: pool_name}) do
    "failed to get gRPC channel from pool #{inspect(pool_name)}: #{inspect(reason)}"
  end
end
