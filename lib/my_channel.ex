defmodule MyChannel do
  use ConnGRPC.Channel, address: "localhost:50020"

end
