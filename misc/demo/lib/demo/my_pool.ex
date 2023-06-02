defmodule MyPool do
  use ConnGRPC.Pool,
    pool_size: 10,
    channel: [address: "localhost:50020", debug: true]
end
