![Tests](https://github.com/TheRealReal/conn_grpc/actions/workflows/ci.yml/badge.svg)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.md)

# ConnGRPC

Persistent channels, and channel pools for [gRPC Elixir](https://github.com/elixir-grpc/grpc).

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

## How to use

You can use ConnGRPC with a pool of persistent channels, or with a single persistent channel.

### Channel pools

Define a module that uses [`ConnGRPC.Pool`](https://hexdocs.pm/conn_grpc/ConnGRPC.Pool.html):

```elixir
defmodule DemoPool do
  use ConnGRPC.Pool,
    pool_size: 5,
    channel: [address: "localhost:50051", opts: []]
end
```

Then add `DemoPool` to your supervision tree, and call `get_channel/0` from anywhere in your application to get a channel connection:

```elixir
{:ok, channel} = DemoPool.get_channel()
```

Each time `get_channel` is called, a different channel from your pool will be returned using round-robin distribution.

For more info, see [`ConnGRPC.Pool` on Hexdocs](https://hexdocs.pm/conn_grpc/ConnGRPC.Pool.html).

### Single channel

For a single persistent channel, define a module that uses [`ConnGRPC.Channel`](https://hexdocs.pm/conn_grpc/ConnGRPC.Channel.html).

```elixir
defmodule DemoChannel do
  use ConnGRPC.Channel, address: "localhost:50051", opts: []
end
```

Then add `DemoChannel` to your supervision tree, and call `get/0` from anywhere in your application to get your channel connection:

```elixir
{:ok, channel} = DemoChannel.get()
```

Depending on the load, using a single channel for the entire application may become a bottleneck. In that case, use the `ConnGRPC.Pool` module, that creates a pool of channels.

For more info, see [`ConnGRPC.Channel` on Hexdocs](https://hexdocs.pm/conn_grpc/ConnGRPC.Channel.html).

## Code of Conduct

This project uses Contributor Covenant version 2.1. Check [CODE_OF_CONDUCT.md](/CODE_OF_CONDUCT.md) file for more information.

## License

ConnGRPC source code is released under Apache License 2.0.

Check [NOTICE](/NOTICE) and [LICENSE](/LICENSE) files for more information.
