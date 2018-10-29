defmodule AmqpDsl.Mixfile do
  use Mix.Project

  def project do
    [app: :amqp_dsl,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:amqp, github: "pma/amqp"},
      {:mock, "~> 0.3.0", only: :test},
      {:poison, "~> 3.0"},
      {:ex_json_schema, "~> 0.5.4"},
      {:meck, "~> 0.8.5"},
      {:ranch, "~> 1.6.2", override: true},
      {:ranch_proxy_protocol, "~> 2.1.1", override: true},
    ]
  end
end
