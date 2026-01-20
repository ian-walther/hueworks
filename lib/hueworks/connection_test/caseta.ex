defmodule Hueworks.ConnectionTest.Caseta do
  @moduledoc false

  @bridge_port 8081

  def test(host, %{caseta_cert: cert_path, caseta_key: key_path, caseta_cacert: cacert_path}) do
    ssl_opts = [
      certfile: cert_path,
      keyfile: key_path,
      cacertfile: cacert_path,
      verify: :verify_none,
      versions: [:"tlsv1.2"]
    ]

    case :ssl.connect(String.to_charlist(host), @bridge_port, ssl_opts, 5_000) do
      {:ok, socket} ->
        :ssl.close(socket)
        {:ok, "Caseta Bridge"}

      {:error, reason} ->
        {:error, "Caseta test failed: #{inspect(reason)}"}
    end
  end

  def test(_host, _staged) do
    {:error, "Caseta test failed: missing required credential files."}
  end
end
