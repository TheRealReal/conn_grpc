defmodule ConnGRPC.MixProject do
  use Mix.Project

  @source_url "https://github.com/TheRealReal/conn_grpc"
  @version "0.1.0"

  def project do
    [
      app: :conn_grpc,
      version: @version,
      name: "ConnGRPC",
      description: "Persistent channels, and channel pools for gRPC Elixir",
      elixir: "~> 1.10",
      deps: deps(),
      docs: docs(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:backoff, "~> 1.1"},
      {:grpc, "~> 0.0", only: :test},
      {:mint, "~> 1.4.2", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["TheRealReal"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/conn_grpc",
      source_url: @source_url,
      main: "overview",
      extras: [
        "guides/overview.md": [filename: "overview", title: "Overview"],
        "CHANGELOG.md": [filename: "changelog", title: "Changelog"]
      ],
      groups_for_modules: [
        Connection: [ConnGRPC.Channel, ConnGRPC.Pool],
        Backoff: [ConnGRPC.Backoff, ConnGRPC.Backoff.Exponential]
      ]
    ]
  end
end
