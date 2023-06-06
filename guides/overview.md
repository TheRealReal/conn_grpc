ConnGRPC allows you to keep persistent channels, and use channel pools with [gRPC Elixir](https://github.com/elixir-grpc/grpc).

## Installation

Add `conn_grpc` to your list of dependencies:

```elixir
def deps do
  [
    {:conn_grpc, "~> 0.1"},

    # You also need to have gRPC Elixir installed
    {:grpc, "~> 0.5"}
  ]
end
```

## Usage

You can use ConnGRPC with a pool of persistent channels, or with a single persistent channel.

### Channel pools

Define a module that uses `ConnGRPC.Pool`.

```elixir
defmodule DemoPool do
  use ConnGRPC.Pool,
    pool_size: 5,
    channel: [address: "localhost:50051", opts: []]
end
```

Then add `DemoPool` to your supervision tree, and call anywhere in your application to get a channel connection:

```elixir
{:ok, channel} = DemoPool.get_channel()
```

Each time `get_channel` is called, a different channel from your pool will be returned using round-robin.

For more info, see `ConnGRPC.Pool`.

### Single channel

For a single persistent channel, define a module that uses `ConnGRPC.Channel`.

```elixir
defmodule DemoChannel do
  use ConnGRPC.Channel, address: "localhost:50051", opts: []
end
```

Then add `DemoChannel` to your supervision tree, and call anywhere in your application to get your channel connection:

```elixir
{:ok, channel} = DemoChannel.get()
```

Depending on the load, using a single channel for the entire application may become a bottleneck. In that case, use the `ConnGRPC.Pool` module, that allows creating a pool of channels.

For more info, see `ConnGRPC.Channel`.
