# ConnGRPC demo app

## Installation

`mix deps.get`

## Usage

Make sure there's a gRPC server listening at `localhost:50020`.

Then, run this app with `iex -S mix run`

- To get a standalone channel, call `MyChannel.get()`
- To get a channel from the pool, call `MyPool.get_channel()`
- To view the supervision tree, run `:observer.start()` and click in `Applications`
